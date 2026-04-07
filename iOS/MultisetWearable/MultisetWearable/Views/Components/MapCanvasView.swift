/*
Copyright (c) 2026 MultiSet AI. All rights reserved.
Licensed under the MultiSet License. You may not use this file except in compliance with the License. and you can't re-distribute this file without a prior notice
For license details, visit www.multiset.ai.
Redistribution in source or binary forms must retain this notice.
*/

import SwiftUI

/// SwiftUI Canvas view for drawing 2D navigation map visualization
struct MapCanvasView: View {

    // MARK: - Properties

    let bounds: MapBounds?
    let waypoints: [WaypointData]
    let pois: [NavigationPOI]
    let userPosition: NavPosition?
    let userRotation: Rotation?
    let activePath: [Int]?
    let destinationPOI: NavigationPOI?
    let currentWaypointIndex: Int

    /// Current zoom scale for adjusting element sizes
    var zoomScale: CGFloat = 1.0

    /// Whether navigation is currently active (reduces visual clutter)
    var isNavigating: Bool = false

    // MARK: - Drawing Constants

    private enum DrawingConstants {
        // Waypoints
        static let waypointRadiusBase: CGFloat = 2.0
        static let waypointRadiusMin: CGFloat = 1.0
        static let waypointRadiusMax: CGFloat = 3.0
        static let waypointColorNormal = Color.white.opacity(0.15)
        static let waypointColorNavigating = Color.white.opacity(0.06)
        static let connectionColorNormal = Color.white.opacity(0.08)
        static let connectionColorNavigating = Color.white.opacity(0.03)
        static let connectionWidth: CGFloat = 0.5

        // Floor plane
        static let floorPlaneColor = Color(white: 0.09)
        static let floorPlaneBorderColor = Color.white.opacity(0.06)
        static let floorPlanePadding: CGFloat = 16
        static let floorPlaneCornerRadius: CGFloat = 12

        // Active path
        static let activePathColor = AppColors.accentGreen
        static let coveredPathColor = Color.white.opacity(0.25)
        static let activePathGlowOpacity: CGFloat = 0.15
        static let activePathWidth: CGFloat = 4.0
        static let activePathGlowWidth: CGFloat = 12
        static let activePathDotSpacing: CGFloat = 3.0

        // POI markers (base values) — larger and more prominent
        static let poiRadiusBase: CGFloat = 12
        static let poiDestinationRadiusBase: CGFloat = 16
        static let poiGlowRadiusBase: CGFloat = 24
        static let poiIconSizeBase: CGFloat = 13
        static let poiBorderWidth: CGFloat = 2.5
        static let poiShadowRadius: CGFloat = 6

        // User marker (base values) — larger and cleaner
        static let userOuterRadiusBase: CGFloat = 16
        static let userInnerRadiusBase: CGFloat = 11
        static let userArrowLengthBase: CGFloat = 22
        static let userArrowBaseWidthBase: CGFloat = 10
        static let userPulseRadiusBase: CGFloat = 26
    }

    // MARK: - Computed Properties

    /// Calculate waypoint density factor based on map size and waypoint count
    private var waypointDensityFactor: CGFloat {
        guard let bounds = bounds, !waypoints.isEmpty else { return 1.0 }

        let mapWidth = CGFloat(bounds.max.x - bounds.min.x)
        let mapHeight = CGFloat(bounds.max.z - bounds.min.z)
        let mapArea = mapWidth * mapHeight

        // Calculate average area per waypoint
        let areaPerWaypoint = mapArea / CGFloat(waypoints.count)

        // Normalize: smaller area per waypoint = denser = smaller circles
        // Base case: 4 sq meters per waypoint = factor 1.0
        let baseDensity: CGFloat = 4.0
        let factor = sqrt(areaPerWaypoint / baseDensity)

        return min(max(factor, 0.5), 2.0)  // Clamp between 0.5 and 2.0
    }

    /// Inverse zoom scale for keeping elements readable
    private var inverseZoom: CGFloat {
        1.0 / max(zoomScale, 0.5)
    }

    // MARK: - Body

    var body: some View {
        GeometryReader { geometry in
            Canvas { context, size in
                guard let bounds = bounds else {
                    drawNoDataMessage(context: context, size: size)
                    return
                }

                let transformer = MapCoordinateTransformer(
                    bounds: bounds,
                    canvasSize: size,
                    padding: 24
                )

                // Draw layers from bottom to top
                drawFloorPlane(context: context, transformer: transformer, size: size)

                drawWaypointConnections(context: context, transformer: transformer)
                drawActivePath(context: context, transformer: transformer)
                drawWaypoints(context: context, transformer: transformer)

                drawPOIs(context: context, transformer: transformer)
                drawUserMarker(context: context, transformer: transformer)
            }
        }
        .background(Color(hex: "0A0E14"))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    // MARK: - Drawing Methods

    /// Draw "No map data" message when bounds are not available
    private func drawNoDataMessage(context: GraphicsContext, size: CGSize) {
        let text = Text("No map data available")
            .font(.system(size: 14, weight: .medium))
            .foregroundColor(AppColors.textSecondary)

        context.draw(
            context.resolve(text),
            at: CGPoint(x: size.width / 2, y: size.height / 2),
            anchor: .center
        )
    }

    /// Draw a polished floor plane behind waypoints with subtle layered styling
    private func drawFloorPlane(context: GraphicsContext, transformer: MapCoordinateTransformer, size: CGSize) {
        guard !waypoints.isEmpty else { return }

        var minX: CGFloat = .greatestFiniteMagnitude
        var maxX: CGFloat = -.greatestFiniteMagnitude
        var minY: CGFloat = .greatestFiniteMagnitude
        var maxY: CGFloat = -.greatestFiniteMagnitude

        for waypoint in waypoints {
            let point = transformer.toScreenPoint(waypoint.position)
            minX = min(minX, point.x)
            maxX = max(maxX, point.x)
            minY = min(minY, point.y)
            maxY = max(maxY, point.y)
        }

        let padding = DrawingConstants.floorPlanePadding
        minX -= padding
        maxX += padding
        minY -= padding
        maxY += padding

        let floorRect = CGRect(x: minX, y: minY, width: maxX - minX, height: maxY - minY)
        let cornerRadius = DrawingConstants.floorPlaneCornerRadius
        let floorPath = Path(roundedRect: floorRect, cornerRadius: cornerRadius)

        // Outer subtle shadow layer
        let shadowRect = floorRect.insetBy(dx: -2, dy: -2)
        let shadowPath = Path(roundedRect: shadowRect, cornerRadius: cornerRadius + 2)
        context.fill(shadowPath, with: .color(Color.white.opacity(0.02)))

        // Main floor fill
        context.fill(floorPath, with: .color(DrawingConstants.floorPlaneColor))

        // Subtle border
        context.stroke(
            floorPath,
            with: .color(DrawingConstants.floorPlaneBorderColor),
            lineWidth: 1
        )
    }

    /// Draw connections between waypoints (graph edges)
    private func drawWaypointConnections(context: GraphicsContext, transformer: MapCoordinateTransformer) {
        let waypointDict = Dictionary(uniqueKeysWithValues: waypoints.map { ($0.id, $0) })

        for waypoint in waypoints {
            let fromPoint = transformer.toScreenPoint(waypoint.position)

            for connectedId in waypoint.connectedWaypoints {
                // Only draw each connection once (where id < connectedId to avoid duplicates)
                guard waypoint.id < connectedId,
                      let connectedWaypoint = waypointDict[connectedId] else {
                    continue
                }

                let toPoint = transformer.toScreenPoint(connectedWaypoint.position)

                var path = Path()
                path.move(to: fromPoint)
                path.addLine(to: toPoint)

                context.stroke(
                    path,
                    with: .color(DrawingConstants.connectionColorNormal),
                    lineWidth: DrawingConstants.connectionWidth
                )
            }
        }
    }

    /// Draw the active navigation path with highlight effect and covered path
    private func drawActivePath(context: GraphicsContext, transformer: MapCoordinateTransformer) {
        guard let pathIds = activePath, pathIds.count >= 2 else { return }

        let waypointDict = Dictionary(uniqueKeysWithValues: waypoints.map { ($0.id, $0) })

        // Draw covered (completed) path as dashed line
        if currentWaypointIndex > 0 {
            var coveredPath = Path()
            var isFirst = true

            for i in 0..<min(currentWaypointIndex + 1, pathIds.count) {
                guard let waypoint = waypointDict[pathIds[i]] else { continue }
                let point = transformer.toScreenPoint(waypoint.position)

                if isFirst {
                    coveredPath.move(to: point)
                    isFirst = false
                } else {
                    coveredPath.addLine(to: point)
                }
            }

            // Dashed covered path for clear visual distinction from active segment
            context.stroke(
                coveredPath,
                with: .color(DrawingConstants.coveredPathColor),
                style: StrokeStyle(
                    lineWidth: DrawingConstants.activePathWidth * 0.7,
                    lineCap: .round,
                    lineJoin: .round,
                    dash: [6, 4]
                )
            )
        }

        // Draw remaining active path
        var canvasPath = Path()
        var isFirst = true

        for i in currentWaypointIndex..<pathIds.count {
            guard let waypoint = waypointDict[pathIds[i]] else { continue }
            let point = transformer.toScreenPoint(waypoint.position)

            if isFirst {
                canvasPath.move(to: point)
                isFirst = false
            } else {
                canvasPath.addLine(to: point)
            }
        }

        // Draw glow effect (wider, semi-transparent)
        context.stroke(
            canvasPath,
            with: .color(DrawingConstants.activePathColor.opacity(DrawingConstants.activePathGlowOpacity)),
            style: StrokeStyle(
                lineWidth: DrawingConstants.activePathGlowWidth,
                lineCap: .round,
                lineJoin: .round
            )
        )

        // Draw main path line
        context.stroke(
            canvasPath,
            with: .color(DrawingConstants.activePathColor),
            style: StrokeStyle(
                lineWidth: DrawingConstants.activePathWidth,
                lineCap: .round,
                lineJoin: .round
            )
        )

        // Draw progress indicators
        for (index, waypointId) in pathIds.enumerated() {
            guard let waypoint = waypointDict[waypointId] else { continue }
            let point = transformer.toScreenPoint(waypoint.position)

            if index < currentWaypointIndex {
                // Completed waypoint - checkmark indicator
                let size: CGFloat = 8
                let rect = CGRect(x: point.x - size/2, y: point.y - size/2, width: size, height: size)
                context.fill(Path(ellipseIn: rect), with: .color(DrawingConstants.coveredPathColor))

                // Inner check
                let innerSize: CGFloat = 4
                let innerRect = CGRect(x: point.x - innerSize/2, y: point.y - innerSize/2, width: innerSize, height: innerSize)
                context.fill(Path(ellipseIn: innerRect), with: .color(.white.opacity(0.6)))
            } else if index == currentWaypointIndex {
                // Current target waypoint - pulsing indicator
                let outerSize: CGFloat = 12
                let outerRect = CGRect(x: point.x - outerSize/2, y: point.y - outerSize/2, width: outerSize, height: outerSize)
                context.fill(Path(ellipseIn: outerRect), with: .color(DrawingConstants.activePathColor.opacity(0.4)))

                let innerSize: CGFloat = 6
                let innerRect = CGRect(x: point.x - innerSize/2, y: point.y - innerSize/2, width: innerSize, height: innerSize)
                context.fill(Path(ellipseIn: innerRect), with: .color(DrawingConstants.activePathColor))
            }
        }
    }

    /// Draw waypoint nodes with dynamic sizing and zoom-aware scaling
    private func drawWaypoints(context: GraphicsContext, transformer: MapCoordinateTransformer) {
        // Scale waypoints inversely with zoom to keep them from getting too large when zoomed out
        let zoomFactor = min(inverseZoom, 1.2)
        let densityAdjusted = DrawingConstants.waypointRadiusBase * waypointDensityFactor * zoomFactor
        let radius = min(max(densityAdjusted, DrawingConstants.waypointRadiusMin), DrawingConstants.waypointRadiusMax)

        for waypoint in waypoints {
            let point = transformer.toScreenPoint(waypoint.position)
            let rect = CGRect(
                x: point.x - radius,
                y: point.y - radius,
                width: radius * 2,
                height: radius * 2
            )
            context.fill(Path(ellipseIn: rect), with: .color(DrawingConstants.waypointColorNormal))
        }
    }

    /// Draw POI markers with type-based styling, shadow, and zoom-aware sizing
    private func drawPOIs(context: GraphicsContext, transformer: MapCoordinateTransformer) {
        let scaleFactor = min(inverseZoom, 1.5)

        for poi in pois {
            let point = transformer.toScreenPoint(poi.position)
            let isDestination = destinationPOI?.id == poi.id
            let color = poiColor(for: poi.type)

            let baseRadius = isDestination ? DrawingConstants.poiDestinationRadiusBase : DrawingConstants.poiRadiusBase
            let radius = baseRadius * scaleFactor

            // Shadow behind POI
            let shadowRadius = radius + DrawingConstants.poiShadowRadius * scaleFactor
            let shadowRect = CGRect(
                x: point.x - shadowRadius,
                y: point.y - shadowRadius + 1,
                width: shadowRadius * 2,
                height: shadowRadius * 2
            )
            context.fill(Path(ellipseIn: shadowRect), with: .color(Color.black.opacity(0.3)))

            // Outer glow for destination
            if isDestination {
                let glowRadius = DrawingConstants.poiGlowRadiusBase * scaleFactor
                let glowRect = CGRect(
                    x: point.x - glowRadius,
                    y: point.y - glowRadius,
                    width: glowRadius * 2,
                    height: glowRadius * 2
                )
                context.fill(Path(ellipseIn: glowRect), with: .color(color.opacity(0.25)))
            }

            // White border ring
            let borderRadius = radius + DrawingConstants.poiBorderWidth
            let borderRect = CGRect(
                x: point.x - borderRadius,
                y: point.y - borderRadius,
                width: borderRadius * 2,
                height: borderRadius * 2
            )
            context.fill(Path(ellipseIn: borderRect), with: .color(.white.opacity(0.9)))

            // Main POI circle
            let rect = CGRect(
                x: point.x - radius,
                y: point.y - radius,
                width: radius * 2,
                height: radius * 2
            )
            context.fill(Path(ellipseIn: rect), with: .color(color))

            // POI icon
            let iconSize = DrawingConstants.poiIconSizeBase * scaleFactor
            let iconImage = context.resolve(Image(systemName: poi.iconName))
            let iconRect = CGRect(
                x: point.x - iconSize / 2,
                y: point.y - iconSize / 2,
                width: iconSize,
                height: iconSize
            )
            context.draw(iconImage, in: iconRect, style: .init(antialiased: true))
        }
    }

    /// Draw user position marker with heading arrow on top
    private func drawUserMarker(context: GraphicsContext, transformer: MapCoordinateTransformer) {
        guard let position = userPosition else { return }

        let point = transformer.toScreenPoint(position)
        let scaleFactor = min(inverseZoom, 1.5)

        let pulseRadius = DrawingConstants.userPulseRadiusBase * scaleFactor
        let outerRadius = DrawingConstants.userOuterRadiusBase * scaleFactor
        let innerRadius = DrawingConstants.userInnerRadiusBase * scaleFactor

        // Soft pulse ring
        let pulseRect = CGRect(
            x: point.x - pulseRadius,
            y: point.y - pulseRadius,
            width: pulseRadius * 2,
            height: pulseRadius * 2
        )
        context.fill(Path(ellipseIn: pulseRect), with: .color(AppColors.accentBlue.opacity(0.12)))

        // Shadow
        let shadowRect = CGRect(
            x: point.x - outerRadius,
            y: point.y - outerRadius + 1,
            width: outerRadius * 2,
            height: outerRadius * 2
        )
        context.fill(Path(ellipseIn: shadowRect), with: .color(Color.black.opacity(0.25)))

        // White outer ring
        let outerRect = CGRect(
            x: point.x - outerRadius,
            y: point.y - outerRadius,
            width: outerRadius * 2,
            height: outerRadius * 2
        )
        context.fill(Path(ellipseIn: outerRect), with: .color(.white))

        // Blue inner circle
        let innerRect = CGRect(
            x: point.x - innerRadius,
            y: point.y - innerRadius,
            width: innerRadius * 2,
            height: innerRadius * 2
        )
        context.fill(Path(ellipseIn: innerRect), with: .color(AppColors.accentBlue))

        // White border on inner circle
        context.stroke(
            Path(ellipseIn: innerRect),
            with: .color(.white.opacity(0.8)),
            lineWidth: 2 * scaleFactor
        )

        // Center dot
        let centerRadius: CGFloat = 3 * scaleFactor
        let centerRect = CGRect(x: point.x - centerRadius, y: point.y - centerRadius, width: centerRadius * 2, height: centerRadius * 2)
        context.fill(Path(ellipseIn: centerRect), with: .color(.white))

        // Heading arrow ON TOP of the dot so it's clearly visible
        if let rotation = userRotation {
            let heading = transformer.headingAngle(from: rotation)
            drawHeadingArrow(context: context, at: point, angle: heading, scaleFactor: scaleFactor)
        }
    }

    /// Draw directional arrow indicating user heading
    private func drawHeadingArrow(context: GraphicsContext, at point: CGPoint, angle: Angle, scaleFactor: CGFloat) {
        let arrowLength = DrawingConstants.userArrowLengthBase * scaleFactor
        let baseWidth = DrawingConstants.userArrowBaseWidthBase * scaleFactor

        // Arrow tip
        let tipX = point.x + sin(CGFloat(angle.radians)) * arrowLength
        let tipY = point.y - cos(CGFloat(angle.radians)) * arrowLength

        // Arrow base
        let baseOffset = baseWidth / 2
        let base1X = point.x + cos(CGFloat(angle.radians)) * baseOffset
        let base1Y = point.y + sin(CGFloat(angle.radians)) * baseOffset
        let base2X = point.x - cos(CGFloat(angle.radians)) * baseOffset
        let base2Y = point.y - sin(CGFloat(angle.radians)) * baseOffset

        var arrowPath = Path()
        arrowPath.move(to: CGPoint(x: tipX, y: tipY))
        arrowPath.addLine(to: CGPoint(x: base1X, y: base1Y))
        arrowPath.addLine(to: CGPoint(x: base2X, y: base2Y))
        arrowPath.closeSubpath()

        context.fill(arrowPath, with: .color(AppColors.accentBlue))

        context.stroke(
            arrowPath,
            with: .color(.white.opacity(0.7)),
            lineWidth: 1.5 * scaleFactor
        )
    }

    // MARK: - Helper Methods

    /// Get color for POI based on type
    private func poiColor(for type: String) -> Color {
        switch type.lowercased() {
        case "room":
            return AppColors.accentBlue
        case "foodarea":
            return AppColors.accentGreen
        case "exit":
            return AppColors.accentPurple
        case "information":
            return AppColors.yellow
        default:
            return AppColors.textSecondary
        }
    }
}

// MARK: - Preview

#Preview {
    MapCanvasView(
        bounds: MapBounds(
            center: NavPosition(x: 0, y: 0, z: 0),
            size: NavPosition(x: 10, y: 0, z: 10),
            min: NavPosition(x: -5, y: 0, z: -5),
            max: NavPosition(x: 5, y: 0, z: 5)
        ),
        waypoints: [
            WaypointData(id: 1, position: NavPosition(x: -3, y: 0, z: -3), connectedWaypoints: [2]),
            WaypointData(id: 2, position: NavPosition(x: 0, y: 0, z: 0), connectedWaypoints: [1, 3]),
            WaypointData(id: 3, position: NavPosition(x: 3, y: 0, z: 3), connectedWaypoints: [2])
        ],
        pois: [
            NavigationPOI(
                id: 1,
                name: "Room A",
                description: "Test room",
                type: "room",
                position: NavPosition(x: 3, y: 0, z: 3),
                worldPosition: NavPosition(x: 3, y: 0, z: 3),
                nearestWaypointId: 3,
                arrivalRadius: 1.5
            )
        ],
        userPosition: NavPosition(x: -2, y: 0, z: -2),
        userRotation: Rotation(x: 0, y: 0.7071, z: 0, w: 0.7071),
        activePath: [1, 2, 3],
        destinationPOI: nil,
        currentWaypointIndex: 1,
        zoomScale: 1.0,
        isNavigating: false
    )
    .frame(height: 300)
    .padding()
    .background(Color.black)
}
