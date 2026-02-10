/*
Copyright (c) 2026 MultiSet AI. All rights reserved.
Licensed under the MultiSet License. You may not use this file except in compliance with the License. and you can't re-distribute this file without a prior notice
For license details, visit www.multiset.ai.
Redistribution in source or binary forms must retain this notice.
*/

import Foundation

// MARK: - Unified Navigation Data Model (from {mapCode}_navigation_data.json)

/// Complete navigation data including POIs, waypoints, and precomputed paths
struct NavigationDataResponse: Codable {
    let mapCode: String?
    let exportedAt: String?
    let waypointSpacing: Float?
    let bounds: MapBounds?
    let pois: [NavigationPOI]
    let waypoints: [WaypointData]
    let paths: [PrecomputedPath]
}

/// Map boundary information
struct MapBounds: Codable {
    let center: NavPosition
    let size: NavPosition
    let min: NavPosition
    let max: NavPosition
}

/// Point of Interest for navigation (unified model with waypoint navigation data)
struct NavigationPOI: Codable, Identifiable {
    let id: Int
    let name: String
    let description: String
    let type: String
    let position: NavPosition
    let worldPosition: NavPosition
    let nearestWaypointId: Int
    let arrivalRadius: Float

    /// Icon name based on POI type
    var iconName: String {
        switch type.lowercased() {
        case "room":
            return "door.left.hand.closed"
        case "foodarea":
            return "fork.knife"
        case "exit":
            return "figure.walk.arrival"
        case "information":
            return "info.circle.fill"
        default:
            return "mappin.circle.fill"
        }
    }

    /// Color for POI type
    var typeColor: String {
        switch type.lowercased() {
        case "room":
            return "accentBlue"
        case "foodarea":
            return "accentGreen"
        case "exit":
            return "accentPurple"
        case "information":
            return "accentBlue"
        default:
            return "textSecondary"
        }
    }
}

/// Individual waypoint in the navigation graph
struct WaypointData: Codable, Identifiable {
    let id: Int
    let position: NavPosition
    let connectedWaypoints: [Int]
}

/// Precomputed navigation path from waypoint to POI
struct PrecomputedPath: Codable {
    let fromWaypointId: Int
    let toPoiId: Int
    let waypointPath: [Int]
    let totalDistance: Float
}

// MARK: - Shared Position Type

/// 3D position used in navigation data
struct NavPosition: Codable {
    let x: Float
    let y: Float
    let z: Float

    /// Distance to another position (3D)
    func distance(to other: NavPosition) -> Float {
        let dx = other.x - x
        let dy = other.y - y
        let dz = other.z - z
        return sqrt(dx * dx + dy * dy + dz * dz)
    }

    /// Distance to another position (2D, ignoring Y/height)
    func distance2D(to other: NavPosition) -> Float {
        let dx = other.x - x
        let dz = other.z - z
        return sqrt(dx * dx + dz * dz)
    }

    /// Create from LocalizationResponse Position
    /// Both Unity navigation data and API now use left-handed coordinate system
    /// (isRightHanded=false in localization request)
    init(from position: Position) {
        self.x = position.x
        self.y = position.y
        self.z = position.z
    }

    init(x: Float, y: Float, z: Float) {
        self.x = x
        self.y = y
        self.z = z
    }
}
