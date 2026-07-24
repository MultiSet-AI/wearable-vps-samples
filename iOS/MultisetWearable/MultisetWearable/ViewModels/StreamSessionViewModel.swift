/*
Copyright (c) 2026 MultiSet AI. All rights reserved.
Licensed under the MultiSet License. You may not use this file except in compliance with the License. and you can't re-distribute this file without a prior notice
For license details, visit www.multiset.ai.
Redistribution in source or binary forms must retain this notice.
*/

import MWDATCamera
import MWDATCore
import SwiftUI

/// Thread-safe one-shot flag protecting continuation resumption.
private final class SSVMOnceFlag: @unchecked Sendable {
  private let lock = NSLock()
  private var isSet = false
  func trySet() -> Bool {
    lock.lock()
    defer { lock.unlock() }
    guard !isSet else { return false }
    isSet = true
    return true
  }
}

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

  /// Mirrors the app-wide DeviceSessionManager's device-availability signal.
  /// Kept as a real @Published (rather than a computed passthrough) so this
  /// ObservableObject's objectWillChange fires when the underlying @Observable
  /// manager changes and SwiftUI views re-render.
  @Published private(set) var hasActiveDevice: Bool = false

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

  /// Timestamp of the most recent video frame. Localizing a stale frame returns
  /// where the user *was*, so the pose — and the 2D map — freeze in place.
  private(set) var lastVideoFrameAt: Date?

  /// Oldest a video frame may be to still be used for localization.
  private let frameStalenessLimit: TimeInterval = 1.5
  private let speechManager = SpeechManager.shared
  // DAT SDK flow: DeviceSession → addStream → Stream
  // We qualify it as MWDATCamera.Stream because SwiftUI/Foundation also expose a
  // `Stream` type.
  private var streamSession: MWDATCamera.Stream?
  private let streamSessionConfig: StreamConfiguration
  // Listener tokens are used to manage DAT SDK event subscriptions
  private var stateListenerToken: AnyListenerToken?
  private var videoFrameListenerToken: AnyListenerToken?
  private var errorListenerToken: AnyListenerToken?
  private var photoDataListenerToken: AnyListenerToken?
  private let wearables: WearablesInterface
  /// App-wide session owner. Device session acquisition/teardown is delegated
  /// entirely to this manager — this VM only owns the video Stream built on top of it.
  private let sessionManager: DeviceSessionManager
  private var deviceAvailabilityTask: Task<Void, Never>?

  init(wearables: WearablesInterface, sessionManager: DeviceSessionManager) {
    self.wearables = wearables
    self.sessionManager = sessionManager
    self.streamSessionConfig = StreamConfiguration(
      videoCodec: VideoCodec.raw,
      resolution: StreamingResolution.medium,
      frameRate: 24)

    self.hasActiveDevice = sessionManager.hasActiveDevice
    startDeviceAvailabilityObserver()
  }

  /// Re-arming `withObservationTracking` loop that mirrors the @Observable
  /// DeviceSessionManager's `hasActiveDevice` into this VM's @Published property,
  /// so SwiftUI views observing this ObservableObject re-render on change.
  private func startDeviceAvailabilityObserver() {
    deviceAvailabilityTask = Task { @MainActor [weak self] in
      while let self, !Task.isCancelled {
        let current = self.sessionManager.hasActiveDevice
        if current != self.hasActiveDevice { self.hasActiveDevice = current }
        await self.awaitActiveDeviceChange()
      }
    }
  }

  private func awaitActiveDeviceChange() async {
    await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
      let once = SSVMOnceFlag()
      withObservationTracking {
        _ = self.sessionManager.hasActiveDevice
      } onChange: {
        if once.trySet() { continuation.resume() }
      }
      Task {
        try? await Task.sleep(for: .seconds(2))
        if once.trySet() { continuation.resume() }
      }
    }
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
          self.lastVideoFrameAt = Date()
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
          // Captured photos are only ever user-initiated — localization runs off
          // the live video frame and never calls capturePhoto().
          self.capturedPhoto = uiImage
          self.showPhotoPreview = true
        }
      }
    }
  }

  deinit {
    // Cancel all tasks to prevent memory leaks
    timerTask?.cancel()
    periodicLocalizationTask?.cancel()
    deviceAvailabilityTask?.cancel()
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

    // The DeviceSession must reach `.started` before `addStream` will succeed.
    // `sessionManager.getSession()` handles creation + the state-stream await,
    // and is shared app-wide so this VM never owns a private device session.
    let deviceSession: DeviceSession
    do {
      deviceSession = try await sessionManager.getSession()
    } catch {
      showError("Failed to start session: \(error.localizedDescription)")
      return
    }
    guard deviceSession.state == .started else {
      showError("Device session is not ready. Please try again.")
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
    // Release the shared device session back to DeviceSessionManager (a no-op if
    // keepAlive is set, e.g. a Display capability is attached elsewhere).
    sessionManager.stopCurrentSession()
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
    localizationResult = nil

    // Play localizing audio file instead of speech
    NavigationAudioService.shared.playLocalizationAudio(.localizing)

    // Localize from the live video frame. Never call capturePhoto() while the
    // stream is running: on SDK 0.8 it permanently stalls video frame delivery,
    // which freezes the pose (and the 2D map) for the rest of the session.
    if let frame = freshVideoFrame {
      localizationStatus = .localizing
      Task { @MainActor in
        await localizeUsing(frame: frame, onEncodeFailure: "Couldn't encode the camera frame.")
      }
    } else {
      // No fresh frame right now (stream still warming up or recovering) —
      // wait briefly for the next one rather than capturing a photo.
      localizationStatus = .capturing
      Task { @MainActor in
        guard let frame = await waitForFreshFrame(timeout: 5) else {
          isLocalizing = false
          localizationStatus = .error
          showError("Couldn't get a camera frame from the glasses. Check that the stream is running and try again.")
          return
        }
        localizationStatus = .localizing
        await localizeUsing(frame: frame, onEncodeFailure: "Couldn't encode the camera frame.")
      }
    }
  }

  /// Trigger localization silently (no audio feedback).
  /// Used for periodic multiplayer re-localization.
  func localizeSilently() {
    guard canLocalize else { return }

    isSilentLocalization = true
    isLocalizing = true

    // Skip the cycle when there is no fresh frame — never capture a photo mid-stream.
    guard let frame = freshVideoFrame else {
      isLocalizing = false
      return
    }
    localizationStatus = .localizing
    Task { @MainActor in
      await localizeUsing(frame: frame, onEncodeFailure: nil)
    }
  }

  /// The current video frame, but only if it is recent enough to describe where
  /// the user is *now*.
  private var freshVideoFrame: UIImage? {
    guard let frame = currentVideoFrame, let at = lastVideoFrameAt,
      Date().timeIntervalSince(at) < frameStalenessLimit
    else { return nil }
    return frame
  }

  /// Encodes off the main actor, then localizes. Keeping the JPEG encode off the
  /// main actor leaves it free to drain incoming video frames.
  private func localizeUsing(frame: UIImage, onEncodeFailure message: String?) async {
    guard let jpegData = await Self.encodeJPEG(frame) else {
      isLocalizing = false
      if let message {
        localizationStatus = .error
        showError(message)
      }
      return
    }
    await performLocalization(jpegData: jpegData, image: frame)
  }

  /// Waits up to `timeout` for a video frame fresh enough to localize against.
  private func waitForFreshFrame(timeout: TimeInterval) async -> UIImage? {
    let deadline = Date().addingTimeInterval(timeout)
    while Date() < deadline, !Task.isCancelled {
      if let frame = freshVideoFrame { return frame }
      try? await Task.sleep(nanoseconds: 100_000_000)
    }
    return nil
  }

  private static func encodeJPEG(_ image: UIImage) async -> Data? {
    await Task.detached(priority: .userInitiated) {
      image.jpegData(compressionQuality: 0.75)
    }.value
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

          // During navigation the periodic loop retries on its own; for manual
          // localization, retry automatically after a short delay.
          if !isNavigationActive {
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

      isSilentLocalization = false
    } catch {
      isLocalizing = false
      localizationStatus = .error
      localizationResult = nil
      if !isNavigationActive && !isSilentLocalization {
        NavigationAudioService.shared.playLocalizationAudio(.failed)
        showError("Localization failed: \(error.localizedDescription)")
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

  /// Start periodic localization for navigation.
  ///
  /// A resilient repeating loop that ticks for as long as navigation is active,
  /// localizing from the live video frame. Transient conditions (stream paused,
  /// a manual localization in flight, no fresh frame) skip the tick and retry,
  /// so a single bad tick can never end the loop.
  private func startPeriodicLocalization() {
    stopPeriodicLocalization()
    periodicLocalizationTask = Task { @MainActor [weak self] in
      var lastStaleLogAt = Date.distantPast
      while !Task.isCancelled {
        guard let self, self.isNavigationActive else { return }

        // Navigation service stopped on its own (e.g. destination reached).
        if !self.navigationService.isNavigating {
          self.isNavigationActive = false
          return
        }

        if !self.isLocalizing, self.streamingStatus == .streaming {
          if let frame = self.freshVideoFrame {
            self.isLocalizing = true
            self.localizationStatus = .localizing
            await self.localizeUsing(frame: frame, onEncodeFailure: nil)
          } else if Date().timeIntervalSince(lastStaleLogAt) > 3 {
            // Stream stalled — localizing the stale frame would report where the
            // user was and freeze the map. Skip the tick; log at most every ~3s.
            lastStaleLogAt = Date()
            let age = Date().timeIntervalSince(self.lastVideoFrameAt ?? .distantPast)
            print("Skipping nav localization: video frame is \(String(format: "%.1f", age))s old — stream stalled?")
          }
        }

        // Breather after each response (or skipped tick) so the video stream keeps
        // radio headroom and the main actor stays free to drain incoming frames.
        try? await Task.sleep(nanoseconds: 400_000_000)
      }
    }
  }

  /// Stop periodic localization
  private func stopPeriodicLocalization() {
    periodicLocalizationTask?.cancel()
    periodicLocalizationTask = nil
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
      // The stream stopped on its own (e.g. device error/disconnect) rather than
      // via our own stopSession() — release the shared device session here too.
      sessionManager.stopCurrentSession()
    case .waitingForDevice, .starting, .stopping, .paused:
      streamingStatus = .waiting
    case .streaming:
      streamingStatus = .streaming
    }
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
