/*
Copyright (c) 2026 MultiSet AI. All rights reserved.
Licensed under the MultiSet License. You may not use this file except in compliance with the License. and you can't re-distribute this file without a prior notice
For license details, visit www.multiset.ai.
Redistribution in source or binary forms must retain this notice.
*/

import Foundation
import SwiftUI
import os.log

/// Thread-safe one-shot flag protecting continuation resumption.
private final class OnceFlag: @unchecked Sendable {
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

@MainActor
final class LocalizationController: ObservableObject {

  // MARK: - Published state

  @Published var localizationStatus: LocalizationStatus = .idle
  @Published var localizationResult: LocalizationResult?
  @Published var isLocalizing: Bool = false
  @Published var showPOIList: Bool = false
  @Published var isNavigationActive: Bool = false
  @Published private(set) var hasLocalizedOnce: Bool = false
  /// Calm "reacquiring position" state after repeated misses/stale frames.
  @Published private(set) var isReacquiring: Bool = false
  /// The frame that was sent with the last localization query (details sheet).
  @Published var queriedFrame: UIImage?

  @Published var showError: Bool = false
  @Published var errorMessage: String = ""

  /// Suppresses audio/error feedback for background re-localization.
  var isSilentLocalization: Bool = false
  /// VPS coordinate handedness toggle (default off).
  var useRightHandedCoordinates: Bool = false

  let navigationService = DisplayNavRouteEngine.shared

  // MARK: - Dependencies

  private let streamViewModel: DisplayNavStreamSessionViewModel
  private let localizationService = LocalizationService.shared
  private let speechManager = SpeechManager.shared

  // MARK: - Internals

  private var periodicLocalizationTask: Task<Void, Never>?
  private var localizationTimeoutTask: Task<Void, Never>?
  private let localizationTimeout: TimeInterval = 12
  private let minimumConfidenceThreshold: Float = 0.4

  /// Newest age a video frame may have to be used for navigation localization.
  /// Localizing a stale frame returns a stale pose, so guidance freezes.
  private let navFrameStalenessLimit: TimeInterval = 1.5

  /// Stamped by the frame-watch loop each time the stream VM publishes a new frame.
  private(set) var lastVideoFrameAt: Date?
  private var frameWatchTask: Task<Void, Never>?

  private static let navLogger = Logger(
    subsystem: Bundle.main.bundleIdentifier ?? "MultisetWearable", category: "NavLocalization")

  // MARK: - Init

  init(streamViewModel: DisplayNavStreamSessionViewModel) {
    self.streamViewModel = streamViewModel
    startFrameWatch()
  }

  isolated deinit {
    frameWatchTask?.cancel()
    periodicLocalizationTask?.cancel()
    localizationTimeoutTask?.cancel()
  }

  // MARK: - Frame freshness watch

  /// Re-arming observation loop: stamps `lastVideoFrameAt` whenever the
  /// streaming VM's `currentVideoFrame` changes. The 5 s fallback bounds each
  /// continuation's lifetime when the stream is idle.
  private func startFrameWatch() {
    frameWatchTask = Task { [weak self] in
      while let self, !Task.isCancelled {
        let changed = await self.awaitNextFrameChange()
        if changed, self.streamViewModel.currentVideoFrame != nil {
          self.lastVideoFrameAt = Date()
        }
      }
    }
  }

  /// Returns true when the observed property changed, false on fallback timeout.
  private func awaitNextFrameChange() async -> Bool {
    await withCheckedContinuation { (continuation: CheckedContinuation<Bool, Never>) in
      let once = OnceFlag()
      withObservationTracking {
        _ = streamViewModel.currentVideoFrame
      } onChange: {
        if once.trySet() { continuation.resume(returning: true) }
      }
      Task {
        try? await Task.sleep(for: .seconds(5))
        if once.trySet() { continuation.resume(returning: false) }
      }
    }
  }

  // MARK: - Localization

  /// Check if localization is properly configured and a stream is live.
  var canLocalize: Bool {
    LocalizationConfig.shared.isConfigured
      && streamViewModel.streamingStatus == .streaming
      && !isLocalizing
  }

  /// Trigger localization: encode the live video frame and send to the VPS API.
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

    NavigationAudioService.shared.playLocalizationAudio(.localizing)

    // Prefer the live video frame: it skips the Bluetooth photo round-trip and
    // avoids calling capturePhoto() while streaming, which stalls frame delivery.
    let frameAge = Date().timeIntervalSince(lastVideoFrameAt ?? .distantPast)
    if let frame = streamViewModel.currentVideoFrame, frameAge < 2.0 {
      localizationStatus = .localizing
      queriedFrame = frame
      Task { @MainActor in
        if let jpegData = await Self.encodeJPEG(frame) {
          await self.performLocalization(jpegData: jpegData, image: frame)
        } else {
          self.failLocalization(message: "Couldn't encode the camera frame.", surfaceError: true)
        }
      }
    } else {
      // No fresh frame right now (stream may be recovering) — wait briefly for
      // the next frame instead of falling back to capturePhoto().
      localizationStatus = .capturing
      startLocalizationTimeout()
      Task { @MainActor in
        if let frame = await self.waitForFreshFrame(timeout: 5) {
          self.localizationStatus = .localizing
          self.queriedFrame = frame
          if let jpegData = await Self.encodeJPEG(frame) {
            await self.performLocalization(jpegData: jpegData, image: frame)
            return
          }
        }
        self.failLocalization(
          message:
            "Couldn't get a camera frame from the glasses — check that the stream is running and try again.",
          surfaceError: true)
      }
    }
  }

  /// Trigger localization silently (no audio feedback). Skips the cycle when
  /// no frame is available — never captures a photo mid-stream.
  func localizeSilently() {
    guard canLocalize else { return }

    isSilentLocalization = true
    isLocalizing = true

    guard let frame = streamViewModel.currentVideoFrame else {
      isLocalizing = false
      return
    }
    localizationStatus = .localizing
    Task { @MainActor in
      if let jpegData = await Self.encodeJPEG(frame) {
        await performLocalization(jpegData: jpegData, image: frame)
      } else {
        isLocalizing = false
      }
    }
  }

  /// Waits up to `timeout` for a video frame fresher than 2 s.
  private func waitForFreshFrame(timeout: TimeInterval) async -> UIImage? {
    let deadline = Date().addingTimeInterval(timeout)
    while Date() < deadline, !Task.isCancelled {
      if let frame = streamViewModel.currentVideoFrame, let at = lastVideoFrameAt,
        Date().timeIntervalSince(at) < 2.0 {
        return frame
      }
      try? await Task.sleep(nanoseconds: 250_000_000)
    }
    return nil
  }

  // MARK: - Localization timeout

  private func startLocalizationTimeout() {
    localizationTimeoutTask?.cancel()
    let timeout = localizationTimeout
    localizationTimeoutTask = Task { @MainActor [weak self] in
      try? await Task.sleep(nanoseconds: UInt64(timeout * 1_000_000_000))
      guard let self, !Task.isCancelled, self.isLocalizing else { return }
      self.failLocalization(
        message: "Localization timed out — couldn't capture an image from the glasses. "
          + "Check that the camera stream is connected and try again.",
        surfaceError: true
      )
    }
  }

  private func cancelLocalizationTimeout() {
    localizationTimeoutTask?.cancel()
    localizationTimeoutTask = nil
  }

  /// Ends the current localization attempt with a failure.
  private func failLocalization(message: String?, surfaceError: Bool) {
    cancelLocalizationTimeout()
    guard isLocalizing else { return }
    isLocalizing = false
    localizationStatus = .error
    localizationResult = nil
    if surfaceError, !isSilentLocalization {
      NavigationAudioService.shared.playLocalizationAudio(.failed)
      if let message { showError(message) }
    }
    isSilentLocalization = false
    // Navigation stays alive — the periodic loop retries on the next tick.
  }

  private func performLocalization(jpegData: Data, image: UIImage) async {
    cancelLocalizationTimeout()
    localizationStatus = .localizing

    let width = Int(image.size.width)
    let height = Int(image.size.height)

    do {
      let result = try await localizationService.sendLocalizationRequest(
        imageData: jpegData,
        imageWidth: width,
        imageHeight: height,
        isRightHanded: useRightHandedCoordinates
      )

      // Confidence gate — below threshold, discard and retry.
      if result.poseFound {
        let confidence = result.confidence ?? 1.0
        if confidence < minimumConfidenceThreshold {
          isLocalizing = false
          Self.navLogger.info(
            "Localization confidence too low: \(String(format: "%.1f%%", confidence * 100))")
          // During navigation the periodic loop retries on its own; for manual
          // localization, retry automatically after a short delay.
          if !isNavigationActive {
            Task { @MainActor in
              try? await Task.sleep(nanoseconds: 100_000_000)
              if self.streamViewModel.streamingStatus == .streaming && !self.isLocalizing {
                self.localize()
              }
            }
          }
          return
        }
      }

      localizationResult = result
      isLocalizing = false

      if result.poseFound {
        localizationStatus = .success
        hasLocalizedOnce = true

        if isNavigationActive, let position = result.posePosition,
          let rotation = result.poseRotation {
          navigationService.updatePosition(position: position, rotation: rotation)
        }

        if !isNavigationActive && !isSilentLocalization {
          NavigationAudioService.shared.playLocalizationAudio(.success)
        }
      } else {
        localizationStatus = .failure
        if !isNavigationActive && !isSilentLocalization {
          NavigationAudioService.shared.playLocalizationAudio(.failed)
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

  /// User's current position as NavPosition (for POI distance calculation).
  var currentUserPosition: NavPosition? {
    guard let position = localizationResult?.posePosition else { return nil }
    return NavPosition(from: position)
  }

  /// Called when the user selects a POI to navigate to.
  func startNavigation(to poiId: Int) {
    guard localizationStatus == .success,
      let position = localizationResult?.posePosition,
      let rotation = localizationResult?.poseRotation
    else {
      showError("Please localize first before starting navigation.")
      return
    }

    navigationService.updatePosition(position: position, rotation: rotation)
    navigationService.startNavigation(to: poiId)
    isNavigationActive = true
    showPOIList = false

    startPeriodicLocalization()
  }

  /// Stop current navigation.
  func stopNavigation() {
    navigationService.stopNavigation()
    isNavigationActive = false
    isReacquiring = false
    stopPeriodicLocalization()
  }

  /// Start periodic localization for navigation.
  ///
  /// A resilient repeating loop: it ticks for as long as navigation is active,
  /// localizing from the live video frame. Transient conditions (stream paused,
  /// a manual localization in flight, no frame yet) just skip the tick and retry.
  private func startPeriodicLocalization() {
    stopPeriodicLocalization()
    periodicLocalizationTask = Task { @MainActor [weak self] in
      var loggedFrameSize = false
      var lastStaleLogAt = Date.distantPast
      var consecutiveFailures = 0
      var consecutiveStaleTicks = 0
      while !Task.isCancelled {
        guard let self, self.isNavigationActive else { return }

        // Navigation service stopped on its own (e.g. destination reached) —
        // sync the flag and end the loop.
        if !self.navigationService.isNavigating {
          self.isNavigationActive = false
          self.isReacquiring = false
          return
        }

        if !self.isLocalizing, self.streamViewModel.streamingStatus == .streaming,
          let frame = self.streamViewModel.currentVideoFrame, let frameAt = self.lastVideoFrameAt {
          let frameAge = Date().timeIntervalSince(frameAt)
          if frameAge > self.navFrameStalenessLimit {
            // Stream stalled (e.g. Bluetooth congestion) — don't localize a
            // stale image. Log at most every ~3s to avoid spam.
            consecutiveStaleTicks += 1
            if consecutiveStaleTicks >= 3 { self.isReacquiring = true }
            if Date().timeIntervalSince(lastStaleLogAt) > 3 {
              lastStaleLogAt = Date()
              Self.navLogger.warning(
                "Skipping nav localization: video frame is \(String(format: "%.1f", frameAge))s old — stream stalled?"
              )
            }
          } else {
            consecutiveStaleTicks = 0
            if !loggedFrameSize {
              loggedFrameSize = true
              Self.navLogger.info(
                "Nav localization using video frames of \(Int(frame.size.width))x\(Int(frame.size.height)) px"
              )
            }
            self.isLocalizing = true
            self.localizationStatus = .localizing
            if let jpegData = await Self.encodeJPEG(frame) {
              await self.performLocalization(jpegData: jpegData, image: frame)
              if self.localizationStatus == .success {
                consecutiveFailures = 0
                self.isReacquiring = false
              } else {
                consecutiveFailures += 1
                // Silent for the first couple of misses; then surface the calm
                // "reacquiring" state.
                if consecutiveFailures >= 3 { self.isReacquiring = true }
              }
            } else {
              self.isLocalizing = false
            }
          }
        } else if !self.isLocalizing {
          // Stream restarting or warming up — wait, and count toward the calm
          // reacquiring state.
          consecutiveStaleTicks += 1
          if consecutiveStaleTicks >= 3 { self.isReacquiring = true }
        }

        // Pace: breather after each response (or skipped tick). 400 ms keeps
        // fixes at ~1/1.5 s while leaving radio headroom for the video stream.
        try? await Task.sleep(nanoseconds: 400_000_000)
      }
    }
  }

  private func stopPeriodicLocalization() {
    periodicLocalizationTask?.cancel()
    periodicLocalizationTask = nil
  }

  // MARK: - Helpers

  /// JPEG-encode off the main actor — encoding on the main thread every cycle
  /// janks the video feed and HUD. Quality 0.75 keeps uploads small.
  private static func encodeJPEG(_ image: UIImage) async -> Data? {
    await Task.detached(priority: .userInitiated) {
      image.jpegData(compressionQuality: 0.75)
    }.value
  }

  func dismissError() {
    showError = false
    errorMessage = ""
  }

  private func showError(_ message: String) {
    errorMessage = message
    showError = true
  }
}
