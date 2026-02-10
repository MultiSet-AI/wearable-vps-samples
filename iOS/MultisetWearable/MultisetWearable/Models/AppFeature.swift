/*
Copyright (c) 2026 MultiSet AI. All rights reserved.
Licensed under the MultiSet License. You may not use this file except in compliance with the License. and you can't re-distribute this file without a prior notice
For license details, visit www.multiset.ai.
Redistribution in source or binary forms must retain this notice.
*/

import SwiftUI

/// Represents the two main feature experiences in the app
enum AppFeature: String, CaseIterable, Identifiable {
    case localization = "Localization Demo"
    case navigation = "Navigation Demo"

    var id: String { rawValue }

    /// Display title for the feature
    var title: String {
        switch self {
        case .localization:
            return "Localization Demo"
        case .navigation:
            return "Navigation Demo"
        }
    }

    /// Short description of the feature
    var description: String {
        switch self {
        case .localization:
            return "Capture images and test positioning with real-time pose data"
        case .navigation:
            return "Full navigation with audio-guided turn-by-turn directions"
        }
    }

    /// SF Symbol icon name
    var iconName: String {
        switch self {
        case .localization:
            return "location.viewfinder"
        case .navigation:
            return "point.topleft.down.to.point.bottomright.curvepath.fill"
        }
    }

    /// Accent color for the feature
    var accentColor: Color {
        switch self {
        case .localization:
            return AppColors.accentBlue
        case .navigation:
            return AppColors.accentGreen
        }
    }
}
