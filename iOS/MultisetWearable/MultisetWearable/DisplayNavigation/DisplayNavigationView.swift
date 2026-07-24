/*
Copyright (c) 2026 MultiSet AI. All rights reserved.
Licensed under the MultiSet License. You may not use this file except in compliance with the License. and you can't re-distribute this file without a prior notice
For license details, visit www.multiset.ai.
Redistribution in source or binary forms must retain this notice.
*/

import MWDATCore
import SwiftUI

/// Feature entry point for Display Navigation. Constructs and owns the VM graph
/// so the Display capability is attached only for this feature's lifetime, then
/// hosts the glasses-driven flow (DisplayNavContentView).
struct DisplayNavigationView: View {
  private let wearables: WearablesInterface
  private let wearablesVM: WearablesViewModel
  private let deviceSessionManager: DeviceSessionManager
  private let onDismiss: () -> Void

  @State private var streamViewModel: DisplayNavStreamSessionViewModel
  @StateObject private var controller: LocalizationController
  @State private var displayViewModel: DisplayViewModel

  init(
    wearables: WearablesInterface,
    wearablesVM: WearablesViewModel,
    deviceSessionManager: DeviceSessionManager,
    onDismiss: @escaping () -> Void
  ) {
    self.wearables = wearables
    self.wearablesVM = wearablesVM
    self.deviceSessionManager = deviceSessionManager
    self.onDismiss = onDismiss

    let svm = DisplayNavStreamSessionViewModel(wearables: wearables, sessionManager: deviceSessionManager)
    _streamViewModel = State(initialValue: svm)
    _controller = StateObject(wrappedValue: LocalizationController(streamViewModel: svm))
    _displayViewModel = State(initialValue: DisplayViewModel(wearables: wearables, sessionManager: deviceSessionManager))
  }

  var body: some View {
    DisplayNavContentView(
      wearablesViewModel: wearablesVM,
      viewModel: streamViewModel,
      controller: controller,
      displayViewModel: displayViewModel,
      onDismiss: onDismiss
    )
  }
}
