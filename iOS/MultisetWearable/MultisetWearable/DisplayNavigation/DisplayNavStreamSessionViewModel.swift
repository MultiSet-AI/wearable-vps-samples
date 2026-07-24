/*
Copyright (c) 2026 MultiSet AI. All rights reserved.
Licensed under the MultiSet License. You may not use this file except in compliance with the License. and you can't re-distribute this file without a prior notice
For license details, visit www.multiset.ai.
Redistribution in source or binary forms must retain this notice.
*/

import MWDATCamera
import MWDATCore
import Observation
import Photos
import SwiftUI

/// Where a photo capture was initiated from. HUD captures auto-save to the
/// photo library and flash a confirmation card on the glasses.
enum CaptureSource {
  case app
  case hud
}

/// ViewModel for video streaming UI. Delegates device management to DeviceSessionManager.
@Observable
@MainActor
final class DisplayNavStreamSessionViewModel {
  // MARK: - State

  var currentVideoFrame: UIImage?
  var hasReceivedFirstFrame: Bool = false
  var streamingStatus: StreamingStatus = .stopped
  var showError: Bool = false
  var errorMessage: String = ""
  var requiresDATAppUpdate: Bool = false

  var capturedPhoto: UIImage?
  var showPhotoPreview: Bool = false
  var showPhotoCaptureError: Bool = false
  var isCapturingPhoto: Bool = false
  /// Increments after each successful HUD-triggered save to the photo library.
  private(set) var savedPhotoCount: Int = 0

  var hasActiveDevice: Bool { sessionManager.hasActiveDevice }
  var isDeviceSessionReady: Bool { sessionManager.isReady }

  var isStreaming: Bool { streamingStatus != .stopped }

  // MARK: - Private

  private let sessionManager: DeviceSessionManager
  private let wearables: WearablesInterface
  private var stream: MWDATCamera.Stream?
  private var captureSource: CaptureSource = .app

  private var stateListenerToken: AnyListenerToken?
  private var videoFrameListenerToken: AnyListenerToken?
  private var errorListenerToken: AnyListenerToken?
  private var photoDataListenerToken: AnyListenerToken?

  // MARK: - Init

  init(wearables: WearablesInterface, sessionManager: DeviceSessionManager) {
    self.wearables = wearables
    self.sessionManager = sessionManager
  }

  // MARK: - Public API

  func handleStartStreaming() async {
    let permission = Permission.camera
    do {
      var status = try await wearables.checkPermissionStatus(permission)
      if status != .granted {
        status = try await wearables.requestPermission(permission)
      }
      guard status == .granted else {
        showError("Permission denied")
        return
      }
      await startSession()
    } catch {
      // Use `localizedDescription` for user-facing text — `description` is
      // always English and intended for logs.
      showError("Permission error: \(error.localizedDescription)")
    }
  }

  func stopSession() {
    stream?.stop()
  }

  /// Fully tears down the stream and releases the underlying device session.
  func endSession() {
    stream = nil
    clearListeners()
    streamingStatus = .stopped
    currentVideoFrame = nil
    hasReceivedFirstFrame = false
    sessionManager.cleanup()
  }

  func capturePhoto(source: CaptureSource = .app) {
    guard !isCapturingPhoto, streamingStatus == .streaming else {
      showPhotoCaptureError = true
      return
    }
    captureSource = source
    isCapturingPhoto = true
    let success = stream?.capturePhoto(format: .jpeg) ?? false
    if !success {
      isCapturingPhoto = false
      captureSource = .app
      showPhotoCaptureError = true
    }
  }

  /// HUD-triggered capture. If idle, auto-starts the stream, waits (bounded)
  /// for the first frame, then captures. The stream stays running afterward.
  func hudCapture() async {
    if streamingStatus == .streaming {
      capturePhoto(source: .hud)
      return
    }

    // A start is already in flight (e.g. HUD double-tap) — ignore this tap.
    guard streamingStatus == .stopped else { return }

    await handleStartStreaming()

    // A failed start leaves the status at .stopped (the error is already
    // surfaced by handleStartStreaming) — abort quietly.
    guard streamingStatus != .stopped else { return }

    let deadline = ContinuousClock.now + .seconds(10)
    while !(streamingStatus == .streaming && hasReceivedFirstFrame) {
      // The stream died while we were waiting — abort quietly.
      if streamingStatus == .stopped { return }
      guard ContinuousClock.now < deadline else {
        showError("Timed out waiting for the stream to start")
        return
      }
      try? await Task.sleep(for: .milliseconds(100))
    }

    capturePhoto(source: .hud)
  }

  func dismissError() {
    showError = false
    errorMessage = ""
  }

  func dismissPhotoCaptureError() {
    showPhotoCaptureError = false
  }

  func dismissPhotoPreview() {
    showPhotoPreview = false
    capturedPhoto = nil
  }

  /// Opens the DAT-app-update flow on the glasses. Passthrough to the SDK.
  func openDATGlassesAppUpdate() async {
    try? await wearables.openDATGlassesAppUpdate()
  }

  // MARK: - Private

  private func startSession() async {
    let deviceSession: DeviceSession
    do {
      deviceSession = try await sessionManager.getSession()
      requiresDATAppUpdate = false
    } catch DeviceSessionError.datAppOnTheGlassesUpdateRequired {
      requiresDATAppUpdate = true
      showError(DeviceSessionError.datAppOnTheGlassesUpdateRequired.localizedDescription)
      return
    } catch {
      showError("Failed to start session: \(error.localizedDescription)")
      return
    }

    guard deviceSession.state == .started else {
      showError("Device session is not ready. Please try again.")
      return
    }

    let config = StreamConfiguration(
      videoCodec: VideoCodec.raw,
      resolution: StreamingResolution.low,
      frameRate: 24
    )

    do {
      guard let newStream = try deviceSession.addStream(config: config) else {
        showError("Unable to create stream. Please try again.")
        return
      }
      stream = newStream
      streamingStatus = .waiting
      setupListeners(for: newStream)
      newStream.start()
    } catch {
      showError("Failed to start stream: \(error.localizedDescription)")
    }
  }

  private func setupListeners(for stream: MWDATCamera.Stream) {
    stateListenerToken = stream.statePublisher.listen { [weak self] state in
      Task { @MainActor in self?.handleStateChange(state) }
    }

    videoFrameListenerToken = stream.videoFramePublisher.listen { [weak self] frame in
      Task { @MainActor in self?.handleVideoFrame(frame) }
    }

    errorListenerToken = stream.errorPublisher.listen { [weak self] error in
      Task { @MainActor in self?.handleError(error) }
    }

    photoDataListenerToken = stream.photoDataPublisher.listen { [weak self] data in
      Task { @MainActor in self?.handlePhotoData(data) }
    }
  }

  private func clearListeners() {
    stateListenerToken = nil
    videoFrameListenerToken = nil
    errorListenerToken = nil
    photoDataListenerToken = nil
  }

  private func handleStateChange(_ state: StreamState) {
    switch state {
    case .stopped:
      currentVideoFrame = nil
      streamingStatus = .stopped
      stream = nil
      clearListeners()
      hasReceivedFirstFrame = false
      sessionManager.stopCurrentSession()
    case .waitingForDevice, .starting, .stopping, .paused:
      streamingStatus = .waiting
    case .streaming:
      streamingStatus = .streaming
    }
  }

  private func handleVideoFrame(_ frame: VideoFrame) {
    if let image = frame.makeUIImage() {
      currentVideoFrame = image
      if !hasReceivedFirstFrame {
        hasReceivedFirstFrame = true
      }
    }
  }

  private func handleError(_ error: StreamError) {
    let message = error.localizedDescription
    if message != errorMessage {
      showError(message)
    }
  }

  private func handlePhotoData(_ data: PhotoData) {
    isCapturingPhoto = false
    let source = captureSource
    captureSource = .app
    if let image = UIImage(data: data.data) {
      if source == .hud {
        saveToPhotoLibrary(image)
      }
      capturedPhoto = image
      showPhotoPreview = true
    }
  }

  /// Saves a HUD-captured photo straight to the photo library. Requires
  /// NSPhotoLibraryAddUsageDescription in Info.plist; PHPhotoLibrary prompts
  /// for add-only access on first use.
  private func saveToPhotoLibrary(_ image: UIImage) {
    PHPhotoLibrary.shared().performChanges({
      PHAssetChangeRequest.creationRequestForAsset(from: image)
    }) { [weak self] success, error in
      Task { @MainActor [weak self] in
        guard let self else { return }
        if success {
          self.savedPhotoCount += 1
        } else {
          self.showError("Failed to save photo: \(error?.localizedDescription ?? "unknown error")")
        }
      }
    }
  }

  private func showError(_ message: String) {
    errorMessage = message
    showError = true
  }
}
