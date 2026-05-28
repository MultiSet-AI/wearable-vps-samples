/*
Copyright (c) 2026 MultiSet AI. All rights reserved.
Licensed under the MultiSet License. You may not use this file except in compliance with the License. and you can't re-distribute this file without a prior notice
For license details, visit www.multiset.ai.
Redistribution in source or binary forms must retain this notice.
*/

//
// StreamSessionViewModel.swift
//
// Core view model demonstrating video streaming from Meta wearable devices using the DAT SDK.
// This class showcases the key streaming patterns: device selection, session management,
// video frame handling, photo capture, and error handling.
//

import MWDATCamera
import MWDATCore
import SwiftUI

enum StreamingStatus {
  case streaming
  case waiting
  case stopped
}

enum LocalizationStatus {
  case idle
  case capturing
  case localizing
  case success
  case failure
  case error
}

@MainActor
class StreamSessionViewModel: ObservableObject {
  @Published var currentVideoFrame: UIImage?
  @Published var hasReceivedFirstFrame: Bool = false
  @Published var streamingStatus: StreamingStatus = .stopped
  @Published var showError: Bool = false
  @Published var errorMessage: String = ""
  @Published var hasActiveDevice: Bool = false

  var isStreaming: Bool {
    streamingStatus != .stopped
  }

  // Timer properties
  @Published var activeTimeLimit: StreamTimeLimit = .noLimit
  @Published var remainingTime: TimeInterval = 0

  // Photo capture properties
  @Published var capturedPhoto: UIImage?
  @Published var showPhotoPreview: Bool = false

  // Localization properties
  @Published var localizationStatus: LocalizationStatus = .idle
  @Published var localizationResult: LocalizationResult?
  @Published var isLocalizing: Bool = false
  /// When true, suppresses audio feedback during localization (used by multiplayer re-localization)
  var isSilentLocalization: Bool = false
  /// When true, requests right-handed (ARKit) coordinates from the API instead of left-handed (Unity).
  /// Used by multiplayer to match the host device's coordinate system directly.
  var useRightHandedCoordinates: Bool = false

  // Navigation properties
  @Published var showPOIList: Bool = false
  @Published var isNavigationActive: Bool = false
  let navigationService = AudioNavigationService.shared

  private var timerTask: Task<Void, Never>?
  private var periodicLocalizationTask: Task<Void, Never>?
  private let localizationService = LocalizationService.shared

  /// Minimum confidence threshold for accepting localization results (40%)
  private let minimumConfidenceThreshold: Float = 0.4
  private let speechManager = SpeechManager.shared
  // DAT SDK flow: DeviceSession → addStream → Stream
  // In 0.7.0 the camera stream type was renamed StreamSession → Stream. We qualify
  // it as MWDATCamera.Stream because SwiftUI/Foundation also expose a `Stream` type.
  private var deviceSession: DeviceSession?
  private var streamSession: MWDATCamera.Stream?
  private let streamSessionConfig: StreamConfiguration
  // Listener tokens are used to manage DAT SDK event subscriptions
  private var stateListenerToken: AnyListenerToken?
  private var videoFrameListenerToken: AnyListenerToken?
  private var errorListenerToken: AnyListenerToken?
  private var photoDataListenerToken: AnyListenerToken?
  private let wearables: WearablesInterface
  private let deviceSelector: AutoDeviceSelector
  private var deviceMonitorTask: Task<Void, Never>?
  private var deviceStateObserverTask: Task<Void, Never>?

  init(wearables: WearablesInterface) {
    self.wearables = wearables
    // Let the SDK auto-select from available devices
    self.deviceSelector = AutoDeviceSelector(wearables: wearables)
    self.streamSessionConfig = StreamConfiguration(
      videoCodec: VideoCodec.raw,
      resolution: StreamingResolution.medium,
      frameRate: 24)

    // Monitor device availability and pre-warm the device session so user-initiated
    // streaming starts immediately. When a device disconnects we tear everything down.
    deviceMonitorTask = Task { @MainActor [weak self] in
      guard let self else { return }
      for await device in self.deviceSelector.activeDeviceStream() {
        self.hasActiveDevice = device != nil
        if device != nil {
          _ = await self.getDeviceSession()
        } else {
          self.handleDeviceLost()
        }
      }
    }
  }

  /// Return a DeviceSession in `.started` state, creating one if needed and awaiting
  /// the state transition via `stateStream()`. Returns nil if creation or start fails.
  /// In 0.6.0, `DeviceSession.stopped` is terminal — a stopped session cannot be
  /// restarted, so we discard it and create a fresh one.
  private func getDeviceSession() async -> DeviceSession? {
    if let session = deviceSession, session.state == .started {
      return session
    }

    if deviceSession?.state == .stopped {
      deviceStateObserverTask?.cancel()
      deviceStateObserverTask = nil
      deviceSession = nil
    }

    guard deviceSession == nil else { return nil }

    do {
      let session = try wearables.createSession(deviceSelector: deviceSelector)
      deviceSession = session

      let stateStream = session.stateStream()
      try session.start()

      for await state in stateStream {
        if state == .started {
          startDeviceStateObserver(for: session)
          return session
        } else if state == .stopped {
          deviceSession = nil
          return nil
        }
      }
    } catch {
      showError("Failed to create session: \(error.localizedDescription)")
      deviceSession = nil
    }
    return nil
  }

  private func startDeviceStateObserver(for session: DeviceSession) {
    deviceStateObserverTask?.cancel()
    deviceStateObserverTask = Task { @MainActor [weak self] in
      for await state in session.stateStream() {
        guard let self else { return }
        if state == .stopped {
          self.deviceSession = nil
          self.streamSession = nil
          self.clearStreamListeners()
          return
        }
      }
    }
  }

  private func handleDeviceLost() {
    deviceStateObserverTask?.cancel()
    deviceStateObserverTask = nil
    deviceSession?.stop()
    deviceSession = nil
    streamSession = nil
    clearStreamListeners()
    streamingStatus = .stopped
  }

  private func clearStreamListeners() {
    stateListenerToken = nil
    videoFrameListenerToken = nil
    errorListenerToken = nil
    photoDataListenerToken = nil
  }

  private func setupStreamListeners(for stream: MWDATCamera.Stream) {
    stateListenerToken = stream.statePublisher.listen { [weak self] state in
      Task { @MainActor [weak self] in
        self?.updateStatusFromState(state)
      }
    }

    videoFrameListenerToken = stream.videoFramePublisher.listen { [weak self] videoFrame in
      Task { @MainActor [weak self] in
        guard let self else { return }
        if let image = videoFrame.makeUIImage() {
          self.currentVideoFrame = image
          if !self.hasReceivedFirstFrame {
            self.hasReceivedFirstFrame = true
          }
        }
      }
    }

    errorListenerToken = stream.errorPublisher.listen { [weak self] error in
      Task { @MainActor [weak self] in
        guard let self else { return }
        let newErrorMessage = formatStreamingError(error)
        if newErrorMessage != self.errorMessage {
          showError(newErrorMessage)
        }
      }
    }

    photoDataListenerToken = stream.photoDataPublisher.listen { [weak self] photoData in
      Task { @MainActor [weak self] in
        guard let self else { return }
        if let uiImage = UIImage(data: photoData.data) {
          self.capturedPhoto = uiImage

          // If we're localizing, downscale to half resolution (540x720) before
          // sending — the API rejects images with max side > 1280, and Ray-Ban
          // Meta captures come in at 1080x1440.
          if self.isLocalizing {
            let (jpegData, image) = Self.resizeCaptureForLocalization(uiImage) ?? (photoData.data, uiImage)
            await self.performLocalization(jpegData: jpegData, image: image)
          } else {
            self.showPhotoPreview = true
          }
        }
      }
    }
  }

  deinit {
    // Cancel all tasks to prevent memory leaks
    deviceMonitorTask?.cancel()
    deviceStateObserverTask?.cancel()
    timerTask?.cancel()
    periodicLocalizationTask?.cancel()
  }

  func handleStartStreaming() async {
    let permission = Permission.camera
    do {
      let status = try await wearables.checkPermissionStatus(permission)
      if status == .granted {
        await startSession()
        return
      }
      let requestStatus = try await wearables.requestPermission(permission)
      if requestStatus == .granted {
        await startSession()
        return
      }
      showError("Permission denied")
    } catch {
      showError("Permission error: \(error.description)")
    }
  }

  func startSession() async {
    // Reset to unlimited time when starting a new stream
    activeTimeLimit = .noLimit
    remainingTime = 0
    stopTimer()

    // In 0.6.0, the DeviceSession must reach `.started` before `addStream` will
    // succeed. `getDeviceSession` handles creation + the state-stream await.
    guard let deviceSession = await getDeviceSession(), deviceSession.state == .started else {
      return
    }

    guard let stream = try? deviceSession.addStream(config: streamSessionConfig) else {
      showError("Failed to add stream to device session.")
      return
    }
    streamSession = stream
    streamingStatus = .waiting
    setupStreamListeners(for: stream)

    await stream.start()

    // Pre-warm auth token in background so first localization doesn't pay the fetch penalty
    Task {
      _ = try? await AuthManager.shared.getToken()
    }
  }

  private func showError(_ message: String) {
    errorMessage = message
    showError = true
  }

  func stopSession() async {
    stopTimer()
    guard let stream = streamSession else { return }
    streamSession = nil
    clearStreamListeners()
    streamingStatus = .stopped
    currentVideoFrame = nil
    hasReceivedFirstFrame = false
    await stream.stop()
    // Keep DeviceSession alive so a subsequent startSession() can re-addStream quickly.
  }

  func dismissError() {
    showError = false
    errorMessage = ""
  }

  func setTimeLimit(_ limit: StreamTimeLimit) {
    activeTimeLimit = limit
    remainingTime = limit.durationInSeconds ?? 0

    if limit.isTimeLimited {
      startTimer()
    } else {
      stopTimer()
    }
  }

  func capturePhoto() {
    _ = streamSession?.capturePhoto(format: .jpeg)
  }

  func dismissPhotoPreview() {
    showPhotoPreview = false
    // Keep capturedPhoto, localizationResult, and localizationStatus
    // so user can view info again by tapping the info button
    // These are reset when starting a new localization
  }

  // MARK: - Localization

  /// Check if localization is properly configured
  var canLocalize: Bool {
    LocalizationConfig.shared.isConfigured && streamingStatus == .streaming && !isLocalizing
  }

  /// Trigger localization: capture photo and send to API
  func localize() {
    guard canLocalize else {
      if !LocalizationConfig.shared.isConfigured {
        speechManager.speak(.notConfigured)
        showError("Please configure API credentials and map code in settings.")
      }
      return
    }

    isSilentLocalization = false
    isLocalizing = true
    localizationStatus = .capturing
    localizationResult = nil

    // Play localizing audio file instead of speech
    NavigationAudioService.shared.playLocalizationAudio(.localizing)

    // Capture photo - the listener will handle sending to API
    _ = streamSession?.capturePhoto(format: .jpeg)
  }

  /// Trigger localization silently (no audio feedback).
  /// Used for periodic multiplayer re-localization.
  /// Uses current video frame directly to skip Bluetooth photo capture round-trip.
  func localizeSilently() {
    guard canLocalize else { return }

    isSilentLocalization = true
    isLocalizing = true

    // Use current video frame for faster localization
    if let frame = currentVideoFrame,
       let jpegData = frame.jpegData(compressionQuality: 0.85) {
      localizationStatus = .localizing
      Task { @MainActor in
        await performLocalization(jpegData: jpegData, image: frame)
      }
    } else {
      // Fallback to photo capture if no video frame
      localizationStatus = .capturing
      _ = streamSession?.capturePhoto(format: .jpeg)
    }
  }

  private func performLocalization(jpegData: Data, image: UIImage) async {
    localizationStatus = .localizing

    let width = Int(image.size.width)
    let height = Int(image.size.height)

    do {
      // Send raw JPEG data directly — avoids decoding then re-encoding the image
      let result = try await localizationService.sendLocalizationRequest(
        imageData: jpegData,
        imageWidth: width,
        imageHeight: height,
        isRightHanded: useRightHandedCoordinates
      )

      // Check confidence threshold - if below minimum, retry localization
      if result.poseFound {
        let confidence = result.confidence ?? 1.0  // Assume full confidence if not provided

        if confidence < minimumConfidenceThreshold {
          // Confidence too low - don't accept this result, request another frame
          isLocalizing = false

          // Log the low confidence for debugging
          print("Localization confidence too low: \(String(format: "%.1f%%", confidence * 100)) (threshold: \(String(format: "%.0f%%", minimumConfidenceThreshold * 100)))")

          // Schedule immediate retry if navigation is active, otherwise just reset
          if isNavigationActive {
            scheduleNextLocalization()
          } else {
            // For manual localization, retry automatically after a short delay
            Task { @MainActor in
              try? await Task.sleep(nanoseconds: 100_000_000)  // 100ms
              if self.streamingStatus == .streaming && !self.isLocalizing {
                self.localize()
              }
            }
          }
          return
        }
      }

      // Confidence is acceptable or pose not found - proceed normally
      localizationResult = result
      isLocalizing = false

      if result.poseFound {
        localizationStatus = .success

        // Update navigation service with new position if navigating
        if isNavigationActive, let position = result.posePosition, let rotation = result.poseRotation {
          navigationService.updatePosition(position: position, rotation: rotation)
        }

        // Play success audio (but not during navigation or silent localization)
        if !isNavigationActive && !isSilentLocalization {
          NavigationAudioService.shared.playLocalizationAudio(.success)
          // Don't show photo preview automatically - user can tap info button to see details
        }
      } else {
        localizationStatus = .failure
        if !isNavigationActive && !isSilentLocalization {
          NavigationAudioService.shared.playLocalizationAudio(.failed)
          // Don't show photo preview automatically
        }
      }

      // Schedule next localization if navigation is active
      if isNavigationActive {
        scheduleNextLocalization()
      }

      isSilentLocalization = false
    } catch {
      isLocalizing = false
      localizationStatus = .error
      localizationResult = nil
      if !isNavigationActive && !isSilentLocalization {
        NavigationAudioService.shared.playLocalizationAudio(.failed)
        showError("Localization failed: \(error.localizedDescription)")
      }

      // Schedule next localization even on error if navigation is active
      if isNavigationActive {
        scheduleNextLocalization()
      }

      isSilentLocalization = false
    }
  }

  // MARK: - Navigation

  /// Get user's current position as NavPosition (for POI distance calculation)
  var currentUserPosition: NavPosition? {
    guard let position = localizationResult?.posePosition else { return nil }
    return NavPosition(from: position)
  }

  /// Called when user selects a POI to navigate to
  func startNavigation(to poiId: Int) {
    guard localizationStatus == .success,
          let position = localizationResult?.posePosition,
          let rotation = localizationResult?.poseRotation else {
      showError("Please localize first before starting navigation.")
      return
    }

    // Update navigation service with current position
    navigationService.updatePosition(position: position, rotation: rotation)

    // Start navigation
    navigationService.startNavigation(to: poiId)
    isNavigationActive = true
    showPOIList = false

    // Start periodic localization
    startPeriodicLocalization()
  }

  /// Stop current navigation
  func stopNavigation() {
    navigationService.stopNavigation()
    isNavigationActive = false
    stopPeriodicLocalization()
  }

  /// Start periodic localization for navigation
  /// Triggers immediately and continues after each response with 200ms delay
  private func startPeriodicLocalization() {
    stopPeriodicLocalization()
    // Trigger first localization immediately
    localizeForNavigation()
  }

  /// Schedule next localization after current one completes (called from performLocalization)
  private func scheduleNextLocalization() {
    periodicLocalizationTask?.cancel()
    periodicLocalizationTask = Task { @MainActor [weak self] in
      // Short delay before next localization (video frame approach is fast, no Bluetooth wait)
      try? await Task.sleep(nanoseconds: 50_000_000) // 50ms

      guard let self, !Task.isCancelled, self.isNavigationActive else { return }

      // Check if navigation service has stopped (e.g., destination reached)
      if !self.navigationService.isNavigating {
        self.isNavigationActive = false
        return
      }

      // Trigger next localization if still streaming
      if !self.isLocalizing && self.streamingStatus == .streaming {
        self.localizeForNavigation()
      }
    }
  }

  /// Stop periodic localization
  private func stopPeriodicLocalization() {
    periodicLocalizationTask?.cancel()
    periodicLocalizationTask = nil
  }

  /// Trigger localization during navigation using the current video frame directly.
  /// This skips the Bluetooth photo capture round-trip (1-3s) by converting the
  /// already-streaming video frame to JPEG on-device, dramatically reducing latency.
  private func localizeForNavigation() {
    guard streamingStatus == .streaming && !isLocalizing else { return }

    // Use the current video frame instead of capturePhoto() to avoid Bluetooth round-trip
    guard let frame = currentVideoFrame,
          let jpegData = frame.jpegData(compressionQuality: 0.85) else {
      // Fallback to photo capture if no video frame available
      isLocalizing = true
      localizationStatus = .capturing
      _ = streamSession?.capturePhoto(format: .jpeg)
      return
    }

    isLocalizing = true
    localizationStatus = .localizing

    Task { @MainActor in
      await performLocalization(jpegData: jpegData, image: frame)
    }
  }

  private func startTimer() {
    stopTimer()
    timerTask = Task { @MainActor [weak self] in
      while let self, remainingTime > 0 {
        try? await Task.sleep(nanoseconds: NSEC_PER_SEC)
        guard !Task.isCancelled else { break }
        remainingTime -= 1
      }
      if let self, !Task.isCancelled {
        await stopSession()
      }
    }
  }

  private func stopTimer() {
    timerTask?.cancel()
    timerTask = nil
  }

  private func updateStatusFromState(_ state: StreamState) {
    switch state {
    case .stopped:
      currentVideoFrame = nil
      streamingStatus = .stopped
    case .waitingForDevice, .starting, .stopping, .paused:
      streamingStatus = .waiting
    case .streaming:
      streamingStatus = .streaming
    }
  }

  /// Downscale a Ray-Ban Meta capture (nominally 1080x1440) to the half-resolution
  /// form expected by the localization API (max side 1280). Redrawing also bakes
  /// EXIF orientation into the pixel buffer so the declared width/height match the
  /// JPEG bytes that actually get uploaded.
  private static func resizeCaptureForLocalization(_ image: UIImage) -> (Data, UIImage)? {
    let targetSize = CGSize(
      width: CGFloat(RayBanMetaIntrinsics.halfWidth),
      height: CGFloat(RayBanMetaIntrinsics.halfHeight)
    )
    let format = UIGraphicsImageRendererFormat()
    format.scale = 1.0
    format.opaque = true
    let renderer = UIGraphicsImageRenderer(size: targetSize, format: format)
    let resized = renderer.image { _ in
      image.draw(in: CGRect(origin: .zero, size: targetSize))
    }
    guard let jpegData = resized.jpegData(compressionQuality: 0.85) else { return nil }
    return (jpegData, resized)
  }

  private func formatStreamingError(_ error: StreamError) -> String {
    switch error {
    case .internalError:
      return "An internal error occurred. Please try again."
    case .deviceNotFound:
      return "Device not found. Please ensure your device is connected."
    case .deviceNotConnected:
      return "Device not connected. Please check your connection and try again."
    case .timeout:
      return "The operation timed out. Please try again."
    case .videoStreamingError:
      return "Video streaming failed. Please try again."
    case .permissionDenied:
      return "Camera permission denied. Please grant permission in Settings."
    case .hingesClosed:
      return "Glasses hinges are closed. Please open them to continue."
    case .thermalCritical:
      return "Device temperature is too high. Please wait for it to cool down."
    case .thermalEmergency:
      return "Device temperature reached an emergency level. Streaming stopped — please let it cool down."
    case .peakPowerShutdown:
      return "The device shut down due to a power spike. Please try again."
    case .batteryCritical:
      return "Device battery is critically low. Please charge it and try again."
    @unknown default:
      return "An unknown streaming error occurred."
    }
  }
}
