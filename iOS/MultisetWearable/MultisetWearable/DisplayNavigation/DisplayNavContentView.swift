/*
Copyright (c) 2026 MultiSet AI. All rights reserved.
Licensed under the MultiSet License. You may not use this file except in compliance with the License. and you can't re-distribute this file without a prior notice
For license details, visit www.multiset.ai.
Redistribution in source or binary forms must retain this notice.
*/

import MWDATCore
import SwiftUI
import UIKit

struct DisplayNavContentView: View {
  var wearablesViewModel: WearablesViewModel
  @Bindable var viewModel: DisplayNavStreamSessionViewModel
  @ObservedObject var controller: LocalizationController
  /// Drives the Meta Ray-Ban Display glasses UI (screens + HUD).
  let displayViewModel: DisplayViewModel
  @ObservedObject private var navigationService = DisplayNavRouteEngine.shared

  /// Optional dismiss callback for when launched from FeatureSelectionView
  var onDismiss: (() -> Void)?

  // Auto-localize attempt tracking (initial try + 2 silent retries, then the
  // failed-welcome screen with a manual Localize button).
  @State private var autoLocalizeRetries = 0
  private let maxAutoLocalizeRetries = 2

  /// Set on the user's explicit "go" (welcome/browse Localize button or a
  /// browse destination tap). Until then the camera stays off — the stream
  /// only auto-starts to serve a request made before the device was ready.
  @State private var hasRequestedLocalization = false

  /// Destination tapped on the pre-localization browse list. Once the fix
  /// lands, its confirm screen opens directly instead of the full list.
  @State private var pendingBrowseDestinationId: Int?

  // Trip stats for the Arrived screen.
  @State private var tripStartedAt: Date?
  @State private var tripStartDistance: Float = 0
  @State private var tripDestinationName: String?

  /// Auto-advances Arrived → Destinations if the user doesn't choose.
  @State private var arrivedAdvanceTask: Task<Void, Never>?

  // Body is split into staged sub-properties — one long modifier chain makes
  // the type-checker time out.

  private var screenContent: some View {
    ZStack {
      if viewModel.isStreaming {
        // Full-screen video view with streaming controls
        DisplayNavStreamView(
          viewModel: viewModel,
          wearablesVM: wearablesViewModel,
          controller: controller,
          onDismiss: featureDismiss
        )
      } else {
        // Pre-streaming setup view (auto-start usually skips past this quickly)
        DisplayNavNonStreamView(
          viewModel: viewModel,
          wearablesVM: wearablesViewModel,
          controller: controller,
          onDismiss: featureDismiss
        )
      }
    }
    .alert("Error", isPresented: $viewModel.showError) {
      Button("OK") {
        viewModel.dismissError()
      }
    } message: {
      Text(viewModel.errorMessage)
    }
    .alert("Photo capture failed", isPresented: $viewModel.showPhotoCaptureError) {
      Button("OK") {
        viewModel.dismissPhotoCaptureError()
      }
    } message: {
      Text("Unable to capture photo. This may be due to low storage on device or another capture already in progress. Please try again in a few moments.")
    }
    .alert("Localization", isPresented: $controller.showError) {
      Button("OK") {
        controller.dismissError()
      }
    } message: {
      Text(controller.errorMessage)
    }
  }

  private var withStreamHandlers: some View {
    screenContent
    // --- Phone-free entry: greet on the glasses; the camera stays OFF until
    // the user explicitly chooses to localize (welcome/browse buttons) ---
    .onAppear {
      Task {
        // Attach the Display now, while the radio is idle (no video yet) —
        // getSession() + keepAlive give it a session of its own until the
        // camera joins the same session on stream start.
        await displayViewModel.prepareNavigationDisplay(sharedSession: nil)
        await showWelcomeOnGlasses()
      }
    }
    .onChange(of: viewModel.hasActiveDevice) { _, active in
      guard active else { return }
      Task {
        if hasRequestedLocalization {
          // The user already chose to localize before the device was ready.
          attemptAutoStart()
        } else if !navigationService.isNavigating, !controller.hasLocalizedOnce,
                  displayViewModel.navScreen == .none || displayViewModel.navScreen == .welcome {
          // Device (re)connected while we're still at the entry stage — the
          // onAppear attach had no device to bind to, so redo it and greet.
          // (Skipped while the user is browsing destinations.)
          await displayViewModel.prepareNavigationDisplay(sharedSession: nil)
          await showWelcomeOnGlasses()
        }
      }
    }
    // --- (Re)sync the glasses UI whenever streaming (re)starts. On first
    // start this kicks off auto-localization instead of a welcome tap.
    .onChange(of: viewModel.streamingStatus) { _, status in
      guard status == .streaming else { return }
      Task {
        // Attach the Display right after the stream starts, not mid-localization.
        await displayViewModel.prepareNavigationDisplay(sharedSession: nil)
        if navigationService.isNavigating {
          await startHUDOnGlasses()
        } else if controller.hasLocalizedOnce {
          await showDestinationPickerOnGlasses()
        } else if viewModel.hasReceivedFirstFrame {
          await autoLocalizeOrWelcome()
        }
        // else: wait for the first video frame so auto-localize uses the live-frame path.
      }
    }
    // --- First frame in: kick off automatic localization (phone-free) ---
    .onChange(of: viewModel.hasReceivedFirstFrame) { _, received in
      guard received, !controller.hasLocalizedOnce,
            !controller.isLocalizing, !navigationService.isNavigating else { return }
      Task {
        // Let the stream settle for a moment before adding upload traffic.
        try? await Task.sleep(nanoseconds: 800_000_000)
        guard !controller.hasLocalizedOnce, !controller.isLocalizing,
              !navigationService.isNavigating else { return }
        await autoLocalizeOrWelcome()
      }
    }
  }

  private var withLocalizationHandlers: some View {
    withStreamHandlers
    // --- Scanning animation while any (auto or manual) localization runs ---
    .onChange(of: controller.isLocalizing) { _, localizing in
      guard localizing, !controller.isNavigationActive, !navigationService.isNavigating else { return }
      Task {
        await displayViewModel.showLocalizingAnimation(sharedSession: nil)
      }
    }
    // --- Route the localization outcome (outside navigation) ---
    .onChange(of: controller.localizationStatus) { _, status in
      guard !controller.isNavigationActive, !navigationService.isNavigating else { return }
      Task {
        switch status {
        case .success:
          autoLocalizeRetries = 0
          // A destination tapped on the browse list skips the full picker —
          // its confirm screen opens directly now that a fix exists.
          let preselect = pendingBrowseDestinationId
          pendingBrowseDestinationId = nil
          await showDestinationPickerOnGlasses(preselect: preselect)
        case .failure, .error:
          if controller.hasLocalizedOnce {
            // Already have a position from earlier — stay on the list.
            pendingBrowseDestinationId = nil
            await showDestinationPickerOnGlasses()
          } else if autoLocalizeRetries < maxAutoLocalizeRetries {
            // Silent auto-retry before bothering the user.
            autoLocalizeRetries += 1
            try? await Task.sleep(nanoseconds: 1_500_000_000)
            if controller.canLocalize { controller.localize() }
          } else {
            autoLocalizeRetries = 0
            pendingBrowseDestinationId = nil
            await showWelcomeOnGlasses(failed: true)
          }
        default:
          break
        }
      }
    }
    // --- Degraded guidance: calm "reacquiring position" HUD state ---
    .onChange(of: controller.isReacquiring) { _, reacquiring in
      Task {
        await displayViewModel.setNavReacquiring(reacquiring, snapshot: currentNavSnapshot())
      }
    }
  }

  var body: some View {
    withLocalizationHandlers
    // --- Drive the glasses HUD from navigation state ---
    .onChange(of: navigationService.isNavigating) { _, isNavigating in
      Task {
        if isNavigating {
          tripStartedAt = Date()
          tripStartDistance = navigationService.remainingDistance
          tripDestinationName = navigationService.currentDestination?.name
          await startHUDOnGlasses()
        } else if navigationService.currentInstruction == .destinationReached {
          // Arrival — show the dedicated arrived screen.
          await showArrivedOnGlasses()
        } else if controller.hasLocalizedOnce {
          // Stopped early — back to the destination list.
          await showDestinationPickerOnGlasses()
        } else {
          await showWelcomeOnGlasses()
        }
      }
    }
    .onChange(of: navigationService.currentInstruction) { _, _ in
      Task { await displayViewModel.updateNavigationHUD(currentNavSnapshot()) }
    }
    .onChange(of: navigationService.remainingDistance) { _, _ in
      Task { await displayViewModel.updateNavigationHUD(currentNavSnapshot()) }
    }
    .onChange(of: navigationService.currentWaypointIndex) { _, _ in
      Task { await displayViewModel.updateNavigationHUD(currentNavSnapshot()) }
    }
    // No `.onDisappear` teardown: a fullScreenCover (full-screen map) fires onDisappear on this covered view, which would stop the DeviceSession mid-feature; teardown happens in `featureDismiss`, which every exit path goes through.
  }

  // MARK: - Stream start (user-initiated)

  /// Starts streaming for a user-requested localization once a device is
  /// active. Safe to call repeatedly — the view model guards re-entry and
  /// this no-ops unless fully stopped.
  private func attemptAutoStart() {
    guard viewModel.hasActiveDevice, viewModel.streamingStatus == .stopped else { return }
    Task { await viewModel.handleStartStreaming() }
  }

  /// First-run path once streaming is up: localize automatically (the scanning
  /// screen appears via the `isLocalizing` change); fall back to the welcome
  /// screen with a manual button if localization can't start.
  private func autoLocalizeOrWelcome() async {
    if controller.canLocalize {
      autoLocalizeRetries = 0
      controller.localize()
    } else {
      await showWelcomeOnGlasses()
    }
  }

  /// The user's explicit "go" — from the welcome or browse Localize buttons,
  /// or a browse destination tap. If the camera is already up, localize
  /// immediately; otherwise show the scanning screen (doubling as "starting
  /// camera…" feedback) and start the stream — the existing streaming/first-
  /// frame handlers then run the localization exactly as before.
  private func requestLocalization() {
    hasRequestedLocalization = true
    autoLocalizeRetries = 0
    if controller.canLocalize {
      controller.localize()
    } else {
      Task { await displayViewModel.showLocalizingAnimation(sharedSession: nil) }
      attemptAutoStart()
    }
  }

  // MARK: - Dismissal

  /// Dismiss wrapper that stops navigation and the stream and tears down the
  /// glasses navigation UI before invoking the caller's dismiss action. The
  /// DeviceSession belongs to DeviceSessionManager — reclaimed by the
  /// normal stream-stop path.
  private var featureDismiss: (() -> Void)? {
    guard let onDismiss else { return nil }
    return {
      arrivedAdvanceTask?.cancel()
      if controller.isNavigationActive {
        controller.stopNavigation()
      }
      viewModel.stopSession()
      Task { @MainActor in
        await displayViewModel.endNavigationDisplay()
      }
      onDismiss()
    }
  }

  // MARK: - Glasses navigation screens

  /// Feature entry screen: greeting + "Localize" (with its helper caption) and
  /// "Destinations" (browse before localizing). Also re-shown, with a "try
  /// again" hint, after automatic localization gives up.
  private func showWelcomeOnGlasses(failed: Bool = false) async {
    await displayViewModel.showNavigationWelcome(
      mapName: LocalizationConfig.shared.mapCode,
      failedAttempt: failed,
      // Bitmap logo only while the camera is off — once streaming, every image
      // sent to the glasses competes with video on the same radio link.
      logoURI: viewModel.isStreaming ? nil : Self.welcomeLogoURI,
      sharedSession: nil,
      onLocalize: {
        Task { @MainActor in requestLocalization() }
      },
      onBrowseDestinations: {
        Task { @MainActor in await showBrowseListOnGlasses() }
      }
    )
  }

  /// Pre-localization destination browser (names only — no pose, no
  /// distances). Tapping a row is the "I already know where I want to go"
  /// shortcut: remember the choice, localize, then open its confirm screen.
  private func showBrowseListOnGlasses() async {
    await displayViewModel.showDestinationBrowser(
      navDestinations(),
      sharedSession: nil,
      onSelect: { poiId in
        Task { @MainActor in
          pendingBrowseDestinationId = poiId
          requestLocalization()
        }
      },
      onLocalize: {
        Task { @MainActor in
          pendingBrowseDestinationId = nil
          requestLocalization()
        }
      },
      onBack: {
        Task { @MainActor in await showWelcomeOnGlasses() }
      }
    )
  }

  /// Tappable destination list; confirming a row (Navigate) starts the same
  /// navigation as an in-app POI selection. Re-localize keeps manual control.
  /// - preselect: browse-list choice — opens that destination's confirm
  ///   screen directly (Cancel falls back to this list).
  private func showDestinationPickerOnGlasses(preselect: Int? = nil) async {
    await displayViewModel.showDestinationPicker(
      navDestinations(),
      sharedSession: nil,
      preselect: preselect,
      onNavigate: { poiId in
        Task { @MainActor in
          controller.startNavigation(to: poiId)
          // startNavigation refuses without a fresh successful fix (stale-pose
          // guidance would be wrong). Don't leave the glasses hanging on the
          // confirm screen — return to the list, where Re-localize is available.
          if !controller.isNavigationActive {
            await showDestinationPickerOnGlasses()
          }
        }
      },
      onRelocalize: {
        Task { @MainActor in
          autoLocalizeRetries = 0
          controller.localize()
        }
      },
      // No custom route-preview image while the video stream is active — every
      // bitmap sent to the glasses competes with the camera stream on the same
      // radio link, so the HUD uses default components only.
      routePreview: { _ in nil }
    )
  }

  /// Turn-by-turn HUD with the glasses-side Stop control.
  private func startHUDOnGlasses() async {
    await displayViewModel.startNavigationHUD(
      currentNavSnapshot(),
      sharedSession: nil,
      onStop: {
        Task { @MainActor in controller.stopNavigation() }
      }
    )
  }

  /// Arrival screen: destination + trip stats, Next stop / End. Auto-advances
  /// to the destination list if the user doesn't choose.
  private func showArrivedOnGlasses() async {
    let name = navigationService.currentDestination?.name ?? tripDestinationName ?? "Destination"
    var stats: String?
    if let startedAt = tripStartedAt {
      let minutes = max(1, Int((Date().timeIntervalSince(startedAt) / 60).rounded()))
      let walked = NavigationHUDBuilder.distanceText(tripStartDistance)
      stats = "\(walked) walked · \(minutes) min"
    }

    await displayViewModel.showArrived(
      destinationName: name,
      statsLine: stats,
      sharedSession: nil,
      onNextStop: {
        Task { @MainActor in
          arrivedAdvanceTask?.cancel()
          await showDestinationPickerOnGlasses()
        }
      },
      onEnd: {
        Task { @MainActor in
          featureDismiss?()
        }
      }
    )

    arrivedAdvanceTask?.cancel()
    arrivedAdvanceTask = Task { @MainActor in
      try? await Task.sleep(nanoseconds: 20_000_000_000) // 20s
      guard !Task.isCancelled, displayViewModel.navScreen == .arrived else { return }
      await showDestinationPickerOnGlasses()
    }
  }

  // MARK: - Data helpers

  /// Small data-URI rendition of the MultiSet logo for the pre-stream welcome
  /// masthead. Rendered once; ~96px JPEG keeps the payload to a few KB.
  private static let welcomeLogoURI: String? = {
    guard let image = UIImage(named: "AppIconImage") else { return nil }
    let side: CGFloat = 96
    let format = UIGraphicsImageRendererFormat()
    format.scale = 1
    let renderer = UIGraphicsImageRenderer(size: CGSize(width: side, height: side), format: format)
    let scaled = renderer.image { _ in
      image.draw(in: CGRect(x: 0, y: 0, width: side, height: side))
    }
    guard let data = scaled.jpegData(compressionQuality: 0.8) else { return nil }
    return "data:image/jpeg;base64," + data.base64EncodedString()
  }()

  /// Builds the destination list from available POIs, nearest-first
  /// (alphabetical before a fix, when no distances exist).
  private func navDestinations() -> [NavDestination] {
    let user = controller.currentUserPosition
    return navigationService.getAvailablePOIs()
      .map { poi in
        NavDestination(
          id: poi.id,
          name: poi.name,
          type: poi.type,
          distance: user.map { $0.distance2D(to: poi.position) }
        )
      }
      .sorted {
        let lhs = $0.distance ?? .greatestFiniteMagnitude
        let rhs = $1.distance ?? .greatestFiniteMagnitude
        if lhs == rhs {
          return $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
        }
        return lhs < rhs
      }
  }

  /// Builds the HUD snapshot from the current navigation + localization state.
  private func currentNavSnapshot() -> NavHUDSnapshot {
    let userPosition = controller.localizationResult?.posePosition.map { NavPosition(from: $0) }
    return NavHUDSnapshot(
      instruction: navigationService.currentInstruction,
      remainingDistance: navigationService.remainingDistance,
      distanceToManeuver: navigationService.distanceToNextManeuver,
      destinationName: navigationService.currentDestination?.name,
      waypointIndex: navigationService.currentWaypointIndex,
      totalWaypoints: navigationService.totalWaypoints,
      userPosition: userPosition,
      userRotation: controller.localizationResult?.poseRotation,
      activePath: navigationService.currentNavigationPath,
      routePolyline: navigationService.routeGeometry,
      progressFraction: navigationService.routeProgressFraction
    )
  }
}
