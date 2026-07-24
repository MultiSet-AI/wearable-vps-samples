/*
Copyright (c) 2026 MultiSet AI. All rights reserved.
Licensed under the MultiSet License. You may not use this file except in compliance with the License. and you can't re-distribute this file without a prior notice
For license details, visit www.multiset.ai.
Redistribution in source or binary forms must retain this notice.
*/

//
// StreamSessionView.swift
//
//

import MWDATCore
import SwiftUI

struct StreamSessionView: View {
  let wearables: WearablesInterface
  @ObservedObject private var wearablesViewModel: WearablesViewModel
  let deviceSessionManager: DeviceSessionManager
  @StateObject private var viewModel: StreamSessionViewModel

  /// Optional dismiss callback for when launched from FeatureSelectionView
  var onDismiss: (() -> Void)?

  init(
    wearables: WearablesInterface,
    wearablesVM: WearablesViewModel,
    deviceSessionManager: DeviceSessionManager,
    onDismiss: (() -> Void)? = nil
  ) {
    self.wearables = wearables
    self.wearablesViewModel = wearablesVM
    self.deviceSessionManager = deviceSessionManager
    self.onDismiss = onDismiss
    self._viewModel = StateObject(wrappedValue: StreamSessionViewModel(wearables: wearables, sessionManager: deviceSessionManager))
  }

  var body: some View {
    ZStack {
      if viewModel.isStreaming {
        // Full-screen video view with streaming controls
        StreamView(viewModel: viewModel, wearablesVM: wearablesViewModel, onDismiss: onDismiss)
      } else {
        // Pre-streaming setup view with permissions and start button
        NonStreamView(viewModel: viewModel, wearablesVM: wearablesViewModel, onDismiss: onDismiss)
      }
    }
    .alert("Error", isPresented: $viewModel.showError) {
      Button("OK") {
        viewModel.dismissError()
      }
    } message: {
      Text(viewModel.errorMessage)
    }
  }
}
