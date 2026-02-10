/*
Copyright (c) 2026 MultiSet AI. All rights reserved.
Licensed under the MultiSet License. You may not use this file except in compliance with the License. and you can't re-distribute this file without a prior notice
For license details, visit www.multiset.ai.
Redistribution in source or binary forms must retain this notice.
*/

import Foundation

/// Localization audio types
enum LocalizationAudioType: String, CaseIterable {
    case localizing
    case success
    case failed

    var fileName: String {
        switch self {
        case .localizing:
            return "localizing"
        case .success:
            return "localization_successful"
        case .failed:
            return "localization_failed"
        }
    }

    var fallbackText: String {
        switch self {
        case .localizing:
            return "Localizing"
        case .success:
            return "Localization successful"
        case .failed:
            return "Localization failed"
        }
    }

    /// SF Symbol icon name for UI representation
    var iconName: String {
        switch self {
        case .localizing:
            return "location.magnifyingglass"
        case .success:
            return "checkmark.circle.fill"
        case .failed:
            return "xmark.circle.fill"
        }
    }
}

/// Navigation instruction types with associated audio files
enum NavigationInstruction: String, CaseIterable, Equatable, Identifiable {
    case moveForward
    case turnLeft
    case turnRight
    case slightLeft
    case slightRight
    case turnAround
    case destinationReached
    case navigationStarted
    case recalculating

    /// Conformance to Identifiable for use in SwiftUI lists
    var id: String { rawValue }

    /// Audio file name (without extension)
    var audioFileName: String {
        switch self {
        case .moveForward:
            return "move_forward"
        case .turnLeft:
            return "turn_left"
        case .turnRight:
            return "turn_right"
        case .slightLeft:
            return "slight_left"
        case .slightRight:
            return "slight_right"
        case .turnAround:
            return "turn_around"
        case .destinationReached:
            return "destination_reached"
        case .navigationStarted:
            return "navigation_started"
        case .recalculating:
            return "recalculating"
        }
    }

    /// User-friendly description
    var description: String {
        switch self {
        case .moveForward:
            return "Move forward"
        case .turnLeft:
            return "Turn left"
        case .turnRight:
            return "Turn right"
        case .slightLeft:
            return "Slight left"
        case .slightRight:
            return "Slight right"
        case .turnAround:
            return "Turn around"
        case .destinationReached:
            return "You have arrived"
        case .navigationStarted:
            return "Navigation started"
        case .recalculating:
            return "Recalculating route"
        }
    }

    /// SF Symbol icon name
    var iconName: String {
        switch self {
        case .moveForward:
            return "arrow.up"
        case .turnLeft:
            return "arrow.turn.up.left"
        case .turnRight:
            return "arrow.turn.up.right"
        case .slightLeft:
            return "arrow.up.left"
        case .slightRight:
            return "arrow.up.right"
        case .turnAround:
            return "arrow.uturn.down"
        case .destinationReached:
            return "checkmark.circle.fill"
        case .navigationStarted:
            return "location.fill"
        case .recalculating:
            return "arrow.triangle.2.circlepath"
        }
    }

    /// Icon color for UI representation
    var iconColor: String {
        switch self {
        case .moveForward:
            return "accentGreen"
        case .turnLeft, .turnRight:
            return "accentBlue"
        case .slightLeft, .slightRight:
            return "accentPurple"
        case .turnAround:
            return "orange"
        case .destinationReached:
            return "accentGreen"
        case .navigationStarted:
            return "accentBlue"
        case .recalculating:
            return "yellow"
        }
    }
}
