/*
Copyright (c) 2026 MultiSet AI. All rights reserved.
Licensed under the MultiSet License. You may not use this file except in compliance with the License. and you can't re-distribute this file without a prior notice
For license details, visit www.multiset.ai.
Redistribution in source or binary forms must retain this notice.
*/

import MWDATCore
import Observation
import SwiftUI

/// Manages DeviceSession lifecycle with 1:1 device-to-session mapping.
/// Monitors device availability and creates sessions on demand via `getSession()`.
@Observable
@MainActor
final class DeviceSessionManager {
  private(set) var isReady: Bool = false
  private(set) var hasActiveDevice: Bool = false
  private(set) var activeSupportsDisplay: Bool = false

  /// When true the session is kept open across stream stops — set while a Display
  /// capability is attached and still needs the session.
  @ObservationIgnored var keepAlive: Bool = false

  private let wearables: WearablesInterface
  private let deviceSelector: AutoDeviceSelector
  private var deviceSession: DeviceSession?
  @ObservationIgnored private var deviceMonitorTask: Task<Void, Never>?
  @ObservationIgnored private var stateObserverTask: Task<Void, Never>?

  init(wearables: WearablesInterface) {
    self.wearables = wearables
    self.deviceSelector = AutoDeviceSelector(wearables: wearables)
    startDeviceMonitoring()
  }

  isolated deinit {
    deviceMonitorTask?.cancel()
    stateObserverTask?.cancel()
    deviceSession?.stop()
  }

  func stopCurrentSession() {
    // A Display capability may share this session; keep it open while attached.
    guard !keepAlive else { return }
    stateObserverTask?.cancel()
    stateObserverTask = nil
    deviceSession?.stop()
    deviceSession = nil
    isReady = false
  }

  /// Stops the device session and cancels monitoring. Call before releasing.
  func cleanup() {
    keepAlive = false
    deviceMonitorTask?.cancel()
    deviceMonitorTask = nil
    stateObserverTask?.cancel()
    stateObserverTask = nil
    deviceSession?.stop()
    deviceSession = nil
    isReady = false
    hasActiveDevice = false
  }

  /// Returns a ready DeviceSession, creating one if needed.
  /// Waits for the session to reach .started state before returning.
  func getSession() async throws(DeviceSessionError) -> DeviceSession {
    if let session = deviceSession, session.state == .started {
      isReady = true
      return session
    }

    if deviceSession?.state == .stopped {
      deviceSession = nil
    }

    // Wait for an in-progress session to finish starting
    if let session = deviceSession {
      // The session may have already transitioned to .started before the
      // for-await loop begins iterating (stateStream doesn't buffer past events).
      if session.state == .started {
        isReady = true
        startStateObserver(for: session)
        return session
      }

      try await waitForSessionStart(
        stateStream: session.stateStream(),
        errorStream: session.errorStream()
      )
      isReady = true
      startStateObserver(for: session)
      return session
    }

    // Create a new session
    do throws(DeviceSessionError) {
      let session = try wearables.createSession(deviceSelector: deviceSelector)
      deviceSession = session

      let stateStream = session.stateStream()
      let errorStream = session.errorStream()
      try session.start()

      // The session may have already transitioned to .started before the
      // for-await loop begins iterating (the state change is delivered on
      // another thread and the stream does not buffer past events).
      if session.state == .started {
        isReady = true
        startStateObserver(for: session)
        return session
      }

      try await waitForSessionStart(stateStream: stateStream, errorStream: errorStream)
      isReady = true
      startStateObserver(for: session)
      return session
    } catch {
      isReady = false
      deviceSession = nil
      throw error
    }
  }

  // MARK: - Private

  private func waitForSessionStart(
    stateStream: AsyncStream<DeviceSessionState>,
    errorStream: AsyncStream<DeviceSessionError>
  ) async throws(DeviceSessionError) {
    do {
      try await withThrowingTaskGroup(of: Void.self) { group in
        group.addTask {
          for await state in stateStream {
            if state == .started {
              return
            }
            if state == .stopped {
              throw DeviceSessionError.unexpectedError(description: "The session failed to start")
            }
          }
          guard !Task.isCancelled else {
            return
          }
          throw DeviceSessionError.unexpectedError(description: "The session failed to start")
        }

        group.addTask {
          for await error in errorStream {
            throw error
          }
          guard !Task.isCancelled else {
            return
          }
          throw DeviceSessionError.unexpectedError(description: "The session failed to start")
        }

        guard try await group.next() != nil else {
          throw DeviceSessionError.unexpectedError(description: "The session failed to start")
        }
        group.cancelAll()
      }
    } catch let error as DeviceSessionError {
      throw error
    } catch {
      throw .unexpectedError(description: error.localizedDescription)
    }
  }

  /// Monitors device availability only — does NOT create sessions.
  /// Session creation is deferred to `getSession()` to avoid races.
  private func startDeviceMonitoring() {
    deviceMonitorTask = Task { [weak self] in
      guard let self else { return }
      for await deviceId in deviceSelector.activeDeviceStream() {
        hasActiveDevice = deviceId != nil
        if let deviceId = deviceId, let device = wearables.deviceForIdentifier(deviceId) {
          activeSupportsDisplay = device.supportsDisplay()
        } else {
          activeSupportsDisplay = false
        }
      }
    }
  }

  private func startStateObserver(for session: DeviceSession) {
    stateObserverTask?.cancel()
    stateObserverTask = Task { [weak self] in
      for await state in session.stateStream() {
        guard let self else { return }
        if state == .started {
          isReady = true
        } else if state == .stopped {
          // DeviceSession.stopped is terminal - clean up
          isReady = false
          deviceSession = nil
          return
        }
      }
    }
  }
}
