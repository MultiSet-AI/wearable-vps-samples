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
  // The core DAT SDK StreamSession - handles all streaming operations
  private var streamSession: StreamSession
  // Listener tokens are used to manage DAT SDK event subscriptions
  private var stateListenerToken: AnyListenerToken?
  private var videoFrameListenerToken: AnyListenerToken?
  private var errorListenerToken: AnyListenerToken?
  private var photoDataListenerToken: AnyListenerToken?
  private let wearables: WearablesInterface
  private let deviceSelector: AutoDeviceSelector
  private var deviceMonitorTask: Task<Void, Never>?

  init(wearables: WearablesInterface) {
    self.wearables = wearables
    // Let the SDK auto-select from available devices
    self.deviceSelector = AutoDeviceSelector(wearables: wearables)
    let config = StreamSessionConfig(
      videoCodec: VideoCodec.raw,
      resolution: StreamingResolution.low,
      frameRate: 24)
    streamSession = StreamSession(streamSessionConfig: config, deviceSelector: deviceSelector)

    // Monitor device availability
    deviceMonitorTask = Task { @MainActor in
      for await device in deviceSelector.activeDeviceStream() {
        self.hasActiveDevice = device != nil
      }
    }

    // Subscribe to session state changes using the DAT SDK listener pattern
    // State changes tell us when streaming starts, stops, or encounters issues
    stateListenerToken = streamSession.statePublisher.listen { [weak self] state in
      Task { @MainActor [weak self] in
        self?.updateStatusFromState(state)
      }
    }

    // Subscribe to video frames from the device camera
    // Each VideoFrame contains the raw camera data that we convert to UIImage
    videoFrameListenerToken = streamSession.videoFramePublisher.listen { [weak self] videoFrame in
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

    // Subscribe to streaming errors
    // Errors include device disconnection, streaming failures, etc.
    errorListenerToken = streamSession.errorPublisher.listen { [weak self] error in
      Task { @MainActor [weak self] in
        guard let self else { return }
        let newErrorMessage = formatStreamingError(error)
        if newErrorMessage != self.errorMessage {
          showError(newErrorMessage)
        }
      }
    }

    updateStatusFromState(streamSession.state)

    // Subscribe to photo capture events
    // PhotoData contains the captured image in the requested format (JPEG/HEIC)
    // When localizing, the captured image is sent to the localization API
    photoDataListenerToken = streamSession.photoDataPublisher.listen { [weak self] photoData in
      Task { @MainActor [weak self] in
        guard let self else { return }
        if let uiImage = UIImage(data: photoData.data) {
          self.capturedPhoto = uiImage

          // If we're localizing, send to API
          if self.isLocalizing {
            await self.performLocalization(image: uiImage)
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

    await streamSession.start()
  }

  private func showError(_ message: String) {
    errorMessage = message
    showError = true
  }

  func stopSession() async {
    stopTimer()
    await streamSession.stop()
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
    streamSession.capturePhoto(format: .jpeg)
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

    isLocalizing = true
    localizationStatus = .capturing
    localizationResult = nil

    // Play localizing audio file instead of speech
    NavigationAudioService.shared.playLocalizationAudio(.localizing)

    // Capture photo - the listener will handle sending to API
    streamSession.capturePhoto(format: .jpeg)
  }

  private func performLocalization(image: UIImage) async {
    localizationStatus = .localizing

    do {
      let result = try await localizationService.sendLocalizationRequest(image: image)

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

        // Play success audio (but not during navigation to avoid audio overlap)
        if !isNavigationActive {
          NavigationAudioService.shared.playLocalizationAudio(.success)
          // Don't show photo preview automatically - user can tap info button to see details
        }
      } else {
        localizationStatus = .failure
        if !isNavigationActive {
          NavigationAudioService.shared.playLocalizationAudio(.failed)
          // Don't show photo preview automatically
        }
      }

      // Schedule next localization if navigation is active
      if isNavigationActive {
        scheduleNextLocalization()
      }
    } catch {
      isLocalizing = false
      localizationStatus = .error
      localizationResult = nil
      if !isNavigationActive {
        NavigationAudioService.shared.playLocalizationAudio(.failed)
        showError("Localization failed: \(error.localizedDescription)")
      }

      // Schedule next localization even on error if navigation is active
      if isNavigationActive {
        scheduleNextLocalization()
      }
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
      // Wait 200ms before next localization
      try? await Task.sleep(nanoseconds: 200_000_000)

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

  /// Trigger localization during navigation (silent, no audio feedback)
  private func localizeForNavigation() {
    guard streamingStatus == .streaming && !isLocalizing else { return }

    isLocalizing = true
    localizationStatus = .capturing
    // Don't play any audio during background navigation localization

    // Capture photo - the listener will handle sending to API
    streamSession.capturePhoto(format: .jpeg)
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

  private func updateStatusFromState(_ state: StreamSessionState) {
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

  private func formatStreamingError(_ error: StreamSessionError) -> String {
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
    case .audioStreamingError:
      return "Audio streaming failed. Please try again."
    case .permissionDenied:
      return "Camera permission denied. Please grant permission in Settings."
    @unknown default:
      return "An unknown streaming error occurred."
    }
  }
}
