/*
Copyright (c) 2026 MultiSet AI. All rights reserved.
Licensed under the MultiSet License. You may not use this file except in compliance with the License. and you can't re-distribute this file without a prior notice
For license details, visit www.multiset.ai.
Redistribution in source or binary forms must retain this notice.
*/

import SwiftUI

/// Transforms navigation map coordinates (NavPosition X-Z plane) to screen coordinates for 2D visualization
struct MapCoordinateTransformer {

    // MARK: - Properties

    let bounds: MapBounds
    let canvasSize: CGSize
    let padding: CGFloat

    /// Calculated scale factor to fit map in canvas
    private let scale: CGFloat

    /// Offset to center the map in canvas
    private let offset: CGPoint

    /// Map dimensions in world units
    private let mapWidth: CGFloat
    private let mapHeight: CGFloat

    // MARK: - Initialization

    init(bounds: MapBounds, canvasSize: CGSize, padding: CGFloat = 20) {
        self.bounds = bounds
        self.canvasSize = canvasSize
        self.padding = padding

        // Calculate map dimensions from bounds (X-Z plane)
        self.mapWidth = CGFloat(bounds.max.x - bounds.min.x)
        self.mapHeight = CGFloat(bounds.max.z - bounds.min.z)

        // Calculate available drawing area
        let availableWidth = canvasSize.width - (padding * 2)
        let availableHeight = canvasSize.height - (padding * 2)

        // Calculate uniform scale to maintain aspect ratio
        let scaleX = availableWidth / mapWidth
        let scaleY = availableHeight / mapHeight
        self.scale = min(scaleX, scaleY)

        // Calculate offset to center the map
        let scaledMapWidth = mapWidth * scale
        let scaledMapHeight = mapHeight * scale
        self.offset = CGPoint(
            x: (canvasSize.width - scaledMapWidth) / 2,
            y: (canvasSize.height - scaledMapHeight) / 2
        )
    }

    // MARK: - Coordinate Transformation

    /// Transform a NavPosition (using X-Z plane) to screen CGPoint
    /// - Parameter position: The navigation position in world coordinates
    /// - Returns: Screen coordinate point for drawing
    ///
    /// Coordinate mapping:
    /// - Map +X (right) → Screen +X (right)
    /// - Map +Z (forward) → Screen -Y (up) - inverted so forward points up on map
    func toScreenPoint(_ position: NavPosition) -> CGPoint {
        // Normalize position relative to bounds minimum
        let normalizedX = CGFloat(position.x - bounds.min.x)
        let normalizedZ = CGFloat(position.z - bounds.min.z)

        // Invert Z axis so +Z (forward in map) points UP on screen (smaller Y)
        let invertedZ = mapHeight - normalizedZ

        // Apply scale and offset
        return CGPoint(
            x: offset.x + normalizedX * scale,
            y: offset.y + invertedZ * scale
        )
    }

    /// Transform screen CGPoint back to NavPosition (for hit testing)
    /// - Parameter point: Screen coordinate
    /// - Returns: Approximate NavPosition (Y will be 0)
    func toMapPosition(_ point: CGPoint) -> NavPosition {
        let normalizedX = (point.x - offset.x) / scale
        // Reverse the Z inversion
        let invertedZ = (point.y - offset.y) / scale
        let normalizedZ = mapHeight - invertedZ

        return NavPosition(
            x: Float(normalizedX) + bounds.min.x,
            y: 0,
            z: Float(normalizedZ) + bounds.min.z
        )
    }

    /// Calculate the screen distance for a given world distance
    /// - Parameter worldDistance: Distance in world units (meters)
    /// - Returns: Distance in screen points
    func toScreenDistance(_ worldDistance: Float) -> CGFloat {
        CGFloat(worldDistance) * scale
    }

    // MARK: - Heading Calculation

    /// Extract heading angle from quaternion rotation (Y-axis yaw)
    /// - Parameter rotation: Quaternion rotation from localization
    /// - Returns: Angle for rotation in SwiftUI for the arrow (0 = pointing up on screen)
    ///
    /// In the left-handed coordinate system used by the localization:
    /// - We extract the forward direction vector from the quaternion
    /// - Then convert to screen angle for arrow rendering
    func headingAngle(from rotation: Rotation) -> Angle {
        // Extract the forward direction vector from quaternion
        // For a quaternion rotating the local +Z axis (forward), the world-space direction is:
        let forwardX = 2.0 * (rotation.x * rotation.z + rotation.w * rotation.y)
        let forwardZ = 1.0 - 2.0 * (rotation.x * rotation.x + rotation.y * rotation.y)

        // Convert to screen angle where:
        // - Screen +X is right
        // - Screen -Y is up (we use -cos for Y in arrow drawing)
        // - Map +Z points up on screen (Z is inverted in toScreenPoint)
        // So we need: atan2(forwardX, forwardZ) for the angle from +Z axis
        let screenAngle = atan2(Double(forwardX), Double(forwardZ))

        return Angle(radians: screenAngle)
    }

    /// Calculate heading angle from movement direction (position delta)
    /// - Parameters:
    ///   - from: Previous position
    ///   - to: Current position
    /// - Returns: Angle for rotation in SwiftUI
    func headingAngle(from: NavPosition, to: NavPosition) -> Angle? {
        let dx = to.x - from.x
        let dz = to.z - from.z
        let distance = sqrt(dx * dx + dz * dz)

        // Only calculate if moved significantly
        guard distance > 0.1 else { return nil }

        // atan2(dz, dx) gives angle from +X axis
        // dx>0,dz=0 → 0 (facing right)
        // dx=0,dz>0 → π/2 (facing forward/+Z)
        let mapAngle = atan2(dz, dx)

        // Convert to screen angle (same as quaternion)
        return Angle(radians: Double(.pi / 2 - mapAngle))
    }

    // MARK: - Viewport Info

    /// Get the visible map bounds in screen coordinates
    var visibleRect: CGRect {
        CGRect(
            x: offset.x,
            y: offset.y,
            width: mapWidth * scale,
            height: mapHeight * scale
        )
    }

    /// Current scale factor
    var currentScale: CGFloat {
        scale
    }
}
