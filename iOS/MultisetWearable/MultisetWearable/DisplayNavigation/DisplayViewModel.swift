/*
Copyright (c) 2026 MultiSet AI. All rights reserved.
Licensed under the MultiSet License. You may not use this file except in compliance with the License. and you can't re-distribute this file without a prior notice
For license details, visit www.multiset.ai.
Redistribution in source or binary forms must retain this notice.
*/

import MWDATCore
import MWDATDisplay
import Observation
import SwiftUI

@Observable
@MainActor
class DisplayViewModel {
  var isConnected: Bool = false
  var isSending: Bool = false
  var errorMessage: String?
  var requiresDATAppUpdate: Bool = false
  var didFailToStartSession: Bool = false

  @ObservationIgnored private let wearables: WearablesInterface
  @ObservationIgnored private let sessionManager: DeviceSessionManager
  @ObservationIgnored private var deviceSession: DeviceSession?
  @ObservationIgnored private var display: Display?
  @ObservationIgnored private var stateListenerToken: AnyListenerToken?
  @ObservationIgnored private var coreStateTask: Task<Void, Never>?
  @ObservationIgnored private var sessionErrorTask: Task<Void, Never>?
  @ObservationIgnored private var registrationTask: Task<Void, Never>?
  @ObservationIgnored private var displayStateTask: Task<Void, Never>?
  @ObservationIgnored private var displayStateContinuation: AsyncStream<DisplayState>.Continuation?
  @ObservationIgnored private var pendingAction: (() async -> Void)?

  // MARK: - Navigation glasses UI state

  /// Which navigation screen currently drives the glasses display.
  enum NavGlassesScreen: Equatable {
    case none          // navigation UI not driving the display
    case welcome       // feature intro: Localize / Destinations buttons
    case browse        // pre-localization destination list (names only)
    case localizing    // animated "scanning" frames
    case destinations  // tappable POI list
    case confirm       // Navigate / Cancel for a tapped POI
    case hud           // turn-by-turn HUD
    case arrived       // arrival moment: trip stats + Next stop / End
  }

  /// Current navigation screen on the glasses (`.none` when inactive).
  private(set) var navScreen: NavGlassesScreen = .none

  /// Whether the turn-by-turn navigation HUD is currently driving the display.
  var isNavigationHUDActive: Bool { navScreen == .hud }

  @ObservationIgnored private var lastHUDSendTime: Date?
  @ObservationIgnored private var lastHUDInstruction: NavigationInstruction?
  /// Minimum interval between periodic HUD refreshes; maneuver changes bypass it.
  /// Keep conservative: HUD sends share the Bluetooth link with the video stream.
  @ObservationIgnored private let hudMinRefreshInterval: TimeInterval = 4.0
  /// Stop callback rendered as the HUD's "Stop" button on every HUD send.
  @ObservationIgnored private var hudOnStop: (@Sendable () -> Void)?
  /// While true the HUD renders the calm "reacquiring position" variant instead of guidance.
  @ObservationIgnored private var hudReacquiring = false
  /// False when the Display is attached to a session owned elsewhere; then we only
  /// add/remove the Display capability, never start/stop the session.
  @ObservationIgnored private var ownsSession = true

  // MARK: - Destination picker state

  @ObservationIgnored private var pickerDestinations: [NavDestination] = []
  @ObservationIgnored private var pickerSelected: NavDestination?
  @ObservationIgnored private var pickerOnNavigate: ((Int) -> Void)?
  @ObservationIgnored private var pickerOnRelocalize: (@Sendable () -> Void)?
  /// Renders a route-preview mini-map data URI for a candidate destination
  /// (nil omits the map). Injected by the view.
  @ObservationIgnored private var pickerRoutePreview: ((NavDestination) -> String?)?
  @ObservationIgnored private var localizingAnimationTask: Task<Void, Never>?

  init(wearables: WearablesInterface, sessionManager: DeviceSessionManager) {
    self.wearables = wearables
    self.sessionManager = sessionManager
    observeRegistration()
  }

  isolated deinit {
    stateListenerToken = nil
    coreStateTask?.cancel()
    sessionErrorTask?.cancel()
    registrationTask?.cancel()
    displayStateTask?.cancel()
    localizingAnimationTask?.cancel()
  }

  // MARK: - Registration Observation

  private func observeRegistration() {
    registrationTask = Task { [weak self] in
      guard let wearables = self?.wearables else { return }
      for await state in wearables.registrationStateStream() {
        guard let self, !Task.isCancelled else { return }
        if state == .available || state == .unavailable {
          await self.resetDisplaySession()
        }
      }
    }
  }

  private func resetDisplaySession() async {
    await detachFromDisplay()
  }

  // MARK: - Public API

  /// Sends a display view to the glasses. Auto-attaches if not connected;
  /// the view is queued and sent once the display session is ready.
  func send(_ view: some DisplayableView) async {
    if let display, isConnected {
      await doSend(view, on: display)
      return
    }

    // Store as pending action — will fire once display is ready
    let sendableView = view
    pendingAction = { [weak self] in
      guard let self, let cap = self.display else { return }
      await self.doSend(sendableView, on: cap)
    }

    if display == nil {
      await attachToDisplay()
    }
  }

  private func doSend(_ view: some DisplayableView, on capability: Display) async {
    isSending = true
    defer { isSending = false }

    do {
      try await capability.send(view)
    } catch {
      let message = (error as? DisplayError)?.description ?? error.localizedDescription
      errorMessage = message
    }
  }

  // MARK: - Navigation glasses UI

  /// Moves the navigation display to a new screen, tearing down screen-specific
  /// side effects (the localizing animation timer).
  private func setNavScreen(_ screen: NavGlassesScreen) {
    if screen != .localizing {
      localizingAnimationTask?.cancel()
      localizingAnimationTask = nil
    }
    navScreen = screen
  }

  /// Shows the navigation entry screen (greeting + Localize / Destinations).
  /// - failedAttempt: re-renders with a "try again" hint after a failed localize.
  /// - logoURI: optional data-URI logo; pass only while the camera is off.
  func showNavigationWelcome(
    mapName: String?,
    failedAttempt: Bool = false,
    logoURI: String? = nil,
    sharedSession: DeviceSession? = nil,
    onLocalize: @escaping @Sendable () -> Void,
    onBrowseDestinations: (@Sendable () -> Void)? = nil
  ) async {
    setNavScreen(.welcome)
    await attachSharedDisplay(sharedSession)
    await send(NavigationDestinationsBuilder.makeWelcome(
      mapName: mapName,
      failedAttempt: failedAttempt,
      logoURI: logoURI,
      onLocalize: onLocalize,
      onBrowseDestinations: onBrowseDestinations
    ))
  }

  /// Shows the pre-localization destination browser (names only). Tapping a row
  /// fires `onSelect(poiId)` — the feature localizes first, then opens confirm.
  func showDestinationBrowser(
    _ destinations: [NavDestination],
    sharedSession: DeviceSession? = nil,
    onSelect: @escaping @Sendable (Int) -> Void,
    onLocalize: @escaping @Sendable () -> Void,
    onBack: @escaping @Sendable () -> Void
  ) async {
    setNavScreen(.browse)
    await attachSharedDisplay(sharedSession)
    await send(NavigationDestinationsBuilder.makeBrowseList(
      destinations,
      onSelect: onSelect,
      onLocalize: onLocalize,
      onBack: onBack
    ))
  }

  /// Shows the animated "Localizing…" screen. The Display kit has no intrinsic
  /// animation, so a timer re-sends successive frames until the screen changes.
  func showLocalizingAnimation(sharedSession: DeviceSession? = nil) async {
    guard navScreen != .localizing else { return }
    setNavScreen(.localizing)
    await attachSharedDisplay(sharedSession)

    localizingAnimationTask?.cancel()
    localizingAnimationTask = Task { @MainActor [weak self] in
      var frame = 0
      while !Task.isCancelled {
        guard let self, self.navScreen == .localizing else { return }
        await self.send(NavigationDestinationsBuilder.makeLocalizing(frame: frame))
        frame += 1
        // Keep slow: Display sends share the glasses link with the video stream.
        try? await Task.sleep(nanoseconds: 2_500_000_000) // ~2.5s per frame
      }
    }
  }

  /// Shows the tappable destination list. Tapping a row opens a Navigate / Cancel
  /// confirmation; confirming fires `onNavigate(poiId)`. Attaches the Display to
  /// the camera's shared session, so there's only ever one DeviceSession.
  /// - preselect: POI id from the browse list; opens its confirm screen directly.
  func showDestinationPicker(
    _ destinations: [NavDestination],
    sharedSession: DeviceSession? = nil,
    preselect: Int? = nil,
    onNavigate: @escaping (Int) -> Void,
    onRelocalize: (@Sendable () -> Void)? = nil,
    routePreview: ((NavDestination) -> String?)? = nil
  ) async {
    pickerDestinations = destinations
    pickerSelected = nil
    pickerOnNavigate = onNavigate
    pickerOnRelocalize = onRelocalize
    pickerRoutePreview = routePreview
    setNavScreen(.destinations)

    await attachSharedDisplay(sharedSession)
    if let preselect, destinations.contains(where: { $0.id == preselect }) {
      await handlePickerSelect(preselect)
    } else {
      await pushDestinationPicker()
    }
  }

  private func pushDestinationPicker() async {
    // One vertical column; taller-than-display content scrolls on the glasses.
    let list = NavigationDestinationsBuilder.makeList(
      pickerDestinations,
      onSelect: { [weak self] id in
        Task { @MainActor in await self?.handlePickerSelect(id) }
      },
      onRelocalize: pickerOnRelocalize
    )
    await send(list)
  }

  /// Row tapped on the glasses → show the Navigate / Cancel confirmation
  /// (with a route-preview map when one can be rendered).
  private func handlePickerSelect(_ id: Int) async {
    guard navScreen == .destinations,
          let destination = pickerDestinations.first(where: { $0.id == id }) else { return }
    pickerSelected = destination
    setNavScreen(.confirm)

    await send(NavigationDestinationsBuilder.makeConfirm(
      destination,
      routePreviewURI: pickerRoutePreview?(destination),
      onNavigate: { [weak self] in
        Task { @MainActor in self?.handleConfirmNavigate() }
      },
      onCancel: { [weak self] in
        Task { @MainActor in
          guard let self, self.navScreen == .confirm else { return }
          self.setNavScreen(.destinations)
          await self.pushDestinationPicker()
        }
      }
    ))
  }

  // MARK: - Arrived

  /// The arrival moment: destination + trip stats, with Next stop / End.
  func showArrived(
    destinationName: String,
    statsLine: String?,
    sharedSession: DeviceSession? = nil,
    onNextStop: @escaping @Sendable () -> Void,
    onEnd: @escaping @Sendable () -> Void
  ) async {
    setNavScreen(.arrived)
    await attachSharedDisplay(sharedSession)
    await send(NavigationDestinationsBuilder.makeArrived(
      destinationName: destinationName,
      statsLine: statsLine,
      onNextStop: onNextStop,
      onEnd: onEnd
    ))
  }

  /// "Navigate" confirmed → hand the id to the navigation starter. The HUD
  /// replaces this screen once navigation begins, so keep the Display attached.
  private func handleConfirmNavigate() {
    guard navScreen == .confirm, let destination = pickerSelected else { return }
    pickerSelected = nil
    pickerOnNavigate?(destination.id)
  }

  // MARK: - Navigation HUD

  /// Begins driving the glasses display with the turn-by-turn navigation HUD.
  /// `sharedSession` is the camera's already-started `DeviceSession`: the glasses
  /// allow only one `DeviceSession`, so the HUD attaches its `Display` capability
  /// to it rather than creating a second one. `onStop` renders a "Stop" button.
  func startNavigationHUD(
    _ snapshot: NavHUDSnapshot,
    sharedSession: DeviceSession? = nil,
    onStop: (@Sendable () -> Void)? = nil
  ) async {
    setNavScreen(.hud)
    lastHUDSendTime = nil
    lastHUDInstruction = nil
    hudOnStop = onStop
    hudReacquiring = false

    await attachSharedDisplay(sharedSession)
    await pushNavigationHUD(snapshot, force: true)
  }

  /// Switches the HUD between normal guidance and the "reacquiring position"
  /// variant. One soft audio cue on entry; recovery is silent.
  func setNavReacquiring(_ reacquiring: Bool, snapshot: NavHUDSnapshot) async {
    guard navScreen == .hud, hudReacquiring != reacquiring else { return }
    hudReacquiring = reacquiring
    if reacquiring {
      NavigationAudioService.shared.playLocalizationAudio(.localizing)
    }
    await pushNavigationHUD(snapshot, force: true)
  }

  /// Refreshes the HUD. Maneuver changes (and arrival) send immediately; other
  /// updates are throttled to `hudMinRefreshInterval` to limit re-render/transfer.
  func updateNavigationHUD(_ snapshot: NavHUDSnapshot) async {
    guard navScreen == .hud else { return }
    let maneuverChanged = snapshot.instruction != lastHUDInstruction
    if !maneuverChanged, let last = lastHUDSendTime,
       Date().timeIntervalSince(last) < hudMinRefreshInterval {
      return
    }
    await pushNavigationHUD(snapshot, force: maneuverChanged)
  }

  /// Tears down the navigation display entirely (any screen) and detaches the
  /// Display capability. Safe to call when nothing is active.
  func endNavigationDisplay() async {
    guard navScreen != .none else { return }
    setNavScreen(.none)
    pickerOnNavigate = nil
    pickerOnRelocalize = nil
    pickerRoutePreview = nil
    pickerSelected = nil
    hudOnStop = nil
    hudReacquiring = false
    lastHUDSendTime = nil
    lastHUDInstruction = nil
    await detachFromDisplay()
  }

  /// Attaches the Display capability early — call at stream start, while the
  /// glasses link is calm.
  func prepareNavigationDisplay(sharedSession: DeviceSession?) async {
    await attachSharedDisplay(sharedSession)
  }

  /// Attaches the Display capability to an already-started shared session (the
  /// camera's). No-op if already attached or the session isn't ready.
  private func attachSharedDisplay(_ sharedSession: DeviceSession?) async {
    // No explicit session — resolve the shared one through DeviceSessionManager.
    guard let sharedSession else {
      await attachToDisplay()
      return
    }
    guard sharedSession.state == .started else { return }
    // The shared session may have been recycled — if our Display hangs off a
    // different, now-dead session, drop it and re-attach to the live one.
    if display != nil, !ownsSession, deviceSession !== sharedSession {
      stateListenerToken = nil
      displayStateContinuation?.finish()
      displayStateContinuation = nil
      displayStateTask?.cancel()
      displayStateTask = nil
      display = nil
      deviceSession = nil
      isConnected = false
    }
    guard display == nil else { return }
    ownsSession = false
    deviceSession = sharedSession
    await setupDisplay(on: sharedSession)
  }

  private func pushNavigationHUD(_ snapshot: NavHUDSnapshot, force: Bool) async {
    let hud: FlexBox
    if hudReacquiring {
      // Degraded guidance: text-only frame while the pipeline recovers.
      hud = NavigationHUDBuilder.makeReacquiring(snapshot, onStop: hudOnStop)
    } else {
      // Default-component HUD only (arrow + distance + instruction + progress +
      // Stop). No bitmap mini-map: bitmaps compete with the video stream.
      hud = NavigationHUDBuilder.makeHUD(snapshot, onStop: hudOnStop)
    }

    lastHUDInstruction = snapshot.instruction
    lastHUDSendTime = Date()
    await send(hud)
  }

  // MARK: - Session Management

  func attachToDisplay() async {
    guard display == nil else { return }

    didFailToStartSession = false

    do {
      // getSession() creates + starts the shared session and returns once it
      // reaches .started. keepAlive keeps a stream stop from tearing it down
      // while our Display hangs off it.
      let devSession = try await sessionManager.getSession()
      sessionManager.keepAlive = true
      ownsSession = false
      deviceSession = devSession
      requiresDATAppUpdate = false

      sessionErrorTask = Task { [weak self] in
        for await error in devSession.errorStream() {
          guard let self, !Task.isCancelled else { return }
          self.handleSessionError(error)
        }
      }

      await setupDisplay(on: devSession)
    } catch DeviceSessionError.datAppOnTheGlassesUpdateRequired {
      sessionManager.keepAlive = false
      requiresDATAppUpdate = true
      didFailToStartSession = true
      errorMessage = DeviceSessionError.datAppOnTheGlassesUpdateRequired.localizedDescription
    } catch {
      sessionManager.keepAlive = false
      requiresDATAppUpdate = false
      didFailToStartSession = true
      errorMessage = "Failed to create session: \(error.localizedDescription)"
    }
  }

  func clearSessionStartFailure() {
    didFailToStartSession = false
  }

  private func setupDisplay(on devSession: DeviceSession) async {
    guard display == nil else { return }

    do {
      let capability = try devSession.addDisplay()

      let (stateStream, continuation) = AsyncStream.makeStream(of: DisplayState.self)
      displayStateContinuation = continuation
      stateListenerToken = capability.statePublisher.listen { state in
        continuation.yield(state)
      }

      displayStateTask = Task { [weak self] in
        for await state in stateStream {
          guard let self, !Task.isCancelled else { return }
          switch state {
          case .starting:
            break
          case .started:
            self.isConnected = true
            // Execute pending action now that display is ready
            if let action = self.pendingAction {
              self.pendingAction = nil
              await action()
            }
          case .stopping:
            self.isConnected = false
          case .stopped:
            self.isConnected = false
            self.stateListenerToken = nil
            self.displayStateContinuation?.finish()
            self.displayStateContinuation = nil
            self.display = nil
            self.coreStateTask?.cancel()
            self.coreStateTask = nil
            // The session is DeviceSessionManager's — never stop it here.
            self.sessionManager.keepAlive = false
            self.deviceSession = nil
          }
        }
      }

      capability.start()
      display = capability
    } catch {
      errorMessage = "Failed to start display: \(error.localizedDescription)"
    }
  }

  func detachFromDisplay() async {
    stateListenerToken = nil
    displayStateContinuation?.finish()
    displayStateContinuation = nil
    displayStateTask?.cancel()
    displayStateTask = nil
    display?.stop()
    display = nil
    coreStateTask?.cancel()
    coreStateTask = nil
    sessionErrorTask?.cancel()
    sessionErrorTask = nil
    // The session belongs to DeviceSessionManager — release keepAlive so a
    // stream stop can reclaim it, but never stop it here.
    sessionManager.keepAlive = false
    deviceSession = nil
    ownsSession = true
    isConnected = false
  }

  private func handleSessionError(_ error: DeviceSessionError) {
    requiresDATAppUpdate = error == .datAppOnTheGlassesUpdateRequired
    didFailToStartSession = true
    errorMessage = error.localizedDescription
  }
}
