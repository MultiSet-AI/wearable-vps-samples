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
        // Waypoints (base values, will be adjusted by density and zoom)
        static let waypointRadiusBase: CGFloat = 2.0
        static let waypointRadiusMin: CGFloat = 1.0
        static let waypointRadiusMax: CGFloat = 3.0
        static let waypointColorNormal = Color.white.opacity(0.20)
        static let waypointColorNavigating = Color.white.opacity(0.08)
        static let connectionColorNormal = Color.white.opacity(0.10)
        static let connectionColorNavigating = Color.white.opacity(0.04)
        static let connectionWidth: CGFloat = 0.6

        // Floor plane
        static let floorPlaneColor = Color(white: 0.12)
        static let floorPlanePadding: CGFloat = 12

        // Active path
        static let activePathColor = AppColors.accentGreen
        static let coveredPathColor = Color.orange.opacity(0.5)
        static let activePathGlowOpacity: CGFloat = 0.2
        static let activePathWidth: CGFloat = 3.5
        static let activePathGlowWidth: CGFloat = 10

        // POI markers (base values)
        static let poiRadiusBase: CGFloat = 10
        static let poiDestinationRadiusBase: CGFloat = 14
        static let poiGlowRadiusBase: CGFloat = 20
        static let poiIconSizeBase: CGFloat = 12
        static let poiBorderWidth: CGFloat = 2

        // User marker (base values)
        static let userOuterRadiusBase: CGFloat = 14
        static let userInnerRadiusBase: CGFloat = 9
        static let userArrowLengthBase: CGFloat = 20
        static let userArrowBaseWidthBase: CGFloat = 9
        static let userPulseRadiusBase: CGFloat = 22
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
        .background(AppColors.primaryBackground)
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

    /// Draw a transparent floor plane behind waypoints
    private func drawFloorPlane(context: GraphicsContext, transformer: MapCoordinateTransformer, size: CGSize) {
        guard !waypoints.isEmpty else { return }

        // Find convex hull or bounding box of waypoints with padding
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

        // Add padding
        let padding = DrawingConstants.floorPlanePadding
        minX -= padding
        maxX += padding
        minY -= padding
        maxY += padding

        // Draw rounded rectangle floor
        let floorRect = CGRect(x: minX, y: minY, width: maxX - minX, height: maxY - minY)
        let floorPath = Path(roundedRect: floorRect, cornerRadius: 8)

        context.fill(floorPath, with: .color(DrawingConstants.floorPlaneColor))

        // Draw subtle border
        context.stroke(
            floorPath,
            with: .color(Color.white.opacity(0.08)),
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

        // Draw covered (completed) path first
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

            // Draw covered path with muted color
            context.stroke(
                coveredPath,
                with: .color(DrawingConstants.coveredPathColor),
                style: StrokeStyle(
                    lineWidth: DrawingConstants.activePathWidth,
                    lineCap: .round,
                    lineJoin: .round
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

    /// Draw POI markers with type-based styling and zoom-aware sizing
    private func drawPOIs(context: GraphicsContext, transformer: MapCoordinateTransformer) {
        // Scale POI sizes inversely with zoom to keep them readable
        let scaleFactor = min(inverseZoom, 1.5)  // Cap the scaling

        for poi in pois {
            let point = transformer.toScreenPoint(poi.position)
            let isDestination = destinationPOI?.id == poi.id
            let color = poiColor(for: poi.type)

            let baseRadius = isDestination ? DrawingConstants.poiDestinationRadiusBase : DrawingConstants.poiRadiusBase
            let radius = baseRadius * scaleFactor

            // Draw outer glow for destination
            if isDestination {
                let glowRadius = DrawingConstants.poiGlowRadiusBase * scaleFactor
                let glowRect = CGRect(
                    x: point.x - glowRadius,
                    y: point.y - glowRadius,
                    width: glowRadius * 2,
                    height: glowRadius * 2
                )
                context.fill(Path(ellipseIn: glowRect), with: .color(color.opacity(0.3)))
            }

            // Draw POI border
            let borderRect = CGRect(
                x: point.x - radius - DrawingConstants.poiBorderWidth/2,
                y: point.y - radius - DrawingConstants.poiBorderWidth/2,
                width: (radius + DrawingConstants.poiBorderWidth/2) * 2,
                height: (radius + DrawingConstants.poiBorderWidth/2) * 2
            )
            context.fill(Path(ellipseIn: borderRect), with: .color(color.opacity(0.8)))

            // Draw POI circle background
            let rect = CGRect(
                x: point.x - radius,
                y: point.y - radius,
                width: radius * 2,
                height: radius * 2
            )
            context.fill(Path(ellipseIn: rect), with: .color(color))

            // Draw POI icon
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

    /// Draw user position marker with heading indicator
    private func drawUserMarker(context: GraphicsContext, transformer: MapCoordinateTransformer) {
        guard let position = userPosition else { return }

        let point = transformer.toScreenPoint(position)

        // Scale marker sizes inversely with zoom
        let scaleFactor = min(inverseZoom, 1.5)

        let pulseRadius = DrawingConstants.userPulseRadiusBase * scaleFactor
        let outerRadius = DrawingConstants.userOuterRadiusBase * scaleFactor
        let innerRadius = DrawingConstants.userInnerRadiusBase * scaleFactor

        // Draw outer pulse ring
        let pulseRect = CGRect(
            x: point.x - pulseRadius,
            y: point.y - pulseRadius,
            width: pulseRadius * 2,
            height: pulseRadius * 2
        )
        context.fill(Path(ellipseIn: pulseRect), with: .color(AppColors.accentBlue.opacity(0.12)))

        // Draw outer circle
        let outerRect = CGRect(
            x: point.x - outerRadius,
            y: point.y - outerRadius,
            width: outerRadius * 2,
            height: outerRadius * 2
        )
        context.fill(Path(ellipseIn: outerRect), with: .color(AppColors.accentBlue.opacity(0.25)))

        // Draw inner circle
        let innerRect = CGRect(
            x: point.x - innerRadius,
            y: point.y - innerRadius,
            width: innerRadius * 2,
            height: innerRadius * 2
        )
        context.fill(Path(ellipseIn: innerRect), with: .color(AppColors.accentBlue))

        // Draw white border on inner circle
        context.stroke(
            Path(ellipseIn: innerRect),
            with: .color(.white.opacity(0.8)),
            lineWidth: 2 * scaleFactor
        )

        // Draw center dot
        let centerRadius: CGFloat = 3 * scaleFactor
        let centerRect = CGRect(x: point.x - centerRadius, y: point.y - centerRadius, width: centerRadius * 2, height: centerRadius * 2)
        context.fill(Path(ellipseIn: centerRect), with: .color(.white))

        // Draw heading arrow if rotation is available
        if let rotation = userRotation {
            let heading = transformer.headingAngle(from: rotation)
            drawHeadingArrow(context: context, at: point, angle: heading, scaleFactor: scaleFactor)
        }
    }

    /// Draw directional arrow indicating user heading
    private func drawHeadingArrow(context: GraphicsContext, at point: CGPoint, angle: Angle, scaleFactor: CGFloat) {
        let arrowLength = DrawingConstants.userArrowLengthBase * scaleFactor
        let baseWidth = DrawingConstants.userArrowBaseWidthBase * scaleFactor

        // Calculate arrow tip position
        let tipX = point.x + sin(CGFloat(angle.radians)) * arrowLength
        let tipY = point.y - cos(CGFloat(angle.radians)) * arrowLength

        // Calculate arrow base positions
        let baseOffset = baseWidth / 2

        let base1X = point.x + cos(CGFloat(angle.radians)) * baseOffset
        let base1Y = point.y + sin(CGFloat(angle.radians)) * baseOffset

        let base2X = point.x - cos(CGFloat(angle.radians)) * baseOffset
        let base2Y = point.y - sin(CGFloat(angle.radians)) * baseOffset

        // Create arrow path
        var arrowPath = Path()
        arrowPath.move(to: CGPoint(x: tipX, y: tipY))
        arrowPath.addLine(to: CGPoint(x: base1X, y: base1Y))
        arrowPath.addLine(to: CGPoint(x: base2X, y: base2Y))
        arrowPath.closeSubpath()

        context.fill(arrowPath, with: .color(AppColors.accentBlue))

        // Draw arrow outline
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
