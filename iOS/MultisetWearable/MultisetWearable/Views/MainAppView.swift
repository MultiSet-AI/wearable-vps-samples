/*
Copyright (c) 2026 MultiSet AI. All rights reserved.
Licensed under the MultiSet License. You may not use this file except in compliance with the License. and you can't re-distribute this file without a prior notice
For license details, visit www.multiset.ai.
Redistribution in source or binary forms must retain this notice.
*/

import MWDATCore
import SwiftUI

struct MainAppView: View {
  let wearables: WearablesInterface
  @ObservedObject private var viewModel: WearablesViewModel
  let deviceSessionManager: DeviceSessionManager

  init(
    wearables: WearablesInterface,
    viewModel: WearablesViewModel,
    deviceSessionManager: DeviceSessionManager
  ) {
    self.wearables = wearables
    self.viewModel = viewModel
    self.deviceSessionManager = deviceSessionManager
  }

  var body: some View {
    if viewModel.registrationState == .registered {
      // User registered - show feature selection landing page
      FeatureSelectionView(
        wearables: wearables,
        wearablesVM: viewModel,
        deviceSessionManager: deviceSessionManager
      )
    } else {
      // User not registered - show localization home/onboarding flow
      LocalizationHomeView(wearablesVM: viewModel)
    }
  }
}
