/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 * All rights reserved.
 *
 * This source code is licensed under the license found in the
 * LICENSE file in the root directory of this source tree.
 */

import Foundation
import MWDATCore
import SwiftUI

@main
struct MultisetWearableApp: App {
  private let wearables: WearablesInterface
  @StateObject private var wearablesViewModel: WearablesViewModel
  private let deviceSessionManager: DeviceSessionManager

  init() {
    do {
      try Wearables.configure()
    } catch {
      #if DEBUG
      NSLog("[MultisetWearable] Failed to configure Wearables SDK: \(error)")
      #endif
    }
    let wearables = Wearables.shared
    self.wearables = wearables
    self._wearablesViewModel = StateObject(wrappedValue: WearablesViewModel(wearables: wearables))
    self.deviceSessionManager = DeviceSessionManager(wearables: wearables)
  }

  var body: some Scene {
    WindowGroup {
      // Main app view with access to the shared Wearables SDK instance
      // The Wearables.shared singleton provides the core DAT API
      MainAppView(
        wearables: Wearables.shared,
        viewModel: wearablesViewModel,
        deviceSessionManager: deviceSessionManager
      )
        // Show error alerts for view model failures
        .alert("Error", isPresented: $wearablesViewModel.showError) {
          Button("OK") {
            wearablesViewModel.dismissError()
          }
        } message: {
          Text(wearablesViewModel.errorMessage)
        }

      // Registration view handles the flow for connecting to the glasses via Meta AI
      RegistrationView(viewModel: wearablesViewModel)
    }
  }
}
