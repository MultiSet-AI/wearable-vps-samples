/*
Copyright (c) 2026 MultiSet AI. All rights reserved.
Licensed under the MultiSet License. You may not use this file except in compliance with the License. and you can't re-distribute this file without a prior notice
For license details, visit www.multiset.ai.
Redistribution in source or binary forms must retain this notice.
*/

import SwiftUI

/// Interactive wrapper for MapCanvasView with gesture support (tap, pinch-to-zoom, pan, rotation)
struct InteractiveMapView: View {

    // MARK: - Properties

    @ObservedObject var viewModel: NavigationMapViewModel

    /// Callback when a POI is tapped
    var onPOITapped: ((NavigationPOI) -> Void)?

    /// Whether to show POI labels
    var showLabels: Bool = true

    /// Whether interaction is enabled
    var interactionEnabled: Bool = true

    // MARK: - Gesture State

    @State private var lastScale: CGFloat = 1.0
    @State private var currentCanvasSize: CGSize = .zero
    @State private var dragStartOffset: CGSize = .zero

    // MARK: - Body

    var body: some View {
        GeometryReader { geometry in
            ZStack {
                // Map canvas with transforms
                MapCanvasView(
                    bounds: viewModel.bounds,
                    waypoints: viewModel.waypoints,
                    pois: viewModel.pois,
                    userPosition: viewModel.userPosition,
                    userRotation: viewModel.userRotation,
                    activePath: viewModel.activePath,
                    destinationPOI: viewModel.destinationPOI,
                    currentWaypointIndex: viewModel.currentWaypointIndex,
                    zoomScale: viewModel.zoomScale,
                    isNavigating: viewModel.isNavigating
                )
                .scaleEffect(viewModel.zoomScale)
                .offset(viewModel.panOffset)

                // POI label overlays (only when zoomed in enough to avoid clutter)
                if showLabels && viewModel.zoomScale > 1.5 {
                    poiLabelsOverlay(in: geometry.size)
                }
            }
            .background(AppColors.primaryBackground)
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .contentShape(Rectangle())
            .onAppear {
                currentCanvasSize = geometry.size
                viewModel.canvasSize = geometry.size
                dragStartOffset = viewModel.panOffset
            }
            .onChange(of: geometry.size) { _, newSize in
                currentCanvasSize = newSize
                viewModel.canvasSize = newSize
            }
            .onChange(of: viewModel.zoomScale) { _, _ in
                // Sync drag offset when zoom changes (e.g., from reset)
                if viewModel.panOffset == .zero {
                    dragStartOffset = .zero
                }
            }
            .onChange(of: viewModel.panOffset) { _, newOffset in
                // Sync drag start offset when panOffset changes programmatically (e.g., recenter)
                if viewModel.isRecenterActive {
                    dragStartOffset = newOffset
                }
            }
            .gesture(interactionEnabled ? combinedGesture : nil)
        }
    }

    // MARK: - Gestures

    private var combinedGesture: some Gesture {
        SimultaneousGesture(
            tapGesture,
            SimultaneousGesture(magnificationGesture, dragGesture)
        )
    }

    private var tapGesture: some Gesture {
        SpatialTapGesture()
            .onEnded { value in
                handleTap(at: value.location)
            }
    }

    private var magnificationGesture: some Gesture {
        MagnificationGesture()
            .onChanged { scale in
                let rawDelta = scale / lastScale
                lastScale = scale
                // Dampen the zoom delta to reduce sensitivity:
                // Map raw delta (e.g., 0.8..1.2) closer to 1.0 by blending with 1.0
                let dampening: CGFloat = 0.4 // 0 = no zoom, 1 = full sensitivity
                let dampenedDelta = 1.0 + (rawDelta - 1.0) * dampening
                withAnimation(.interactiveSpring(response: 0.15, dampingFraction: 0.9)) {
                    viewModel.applyZoom(dampenedDelta)
                }
            }
            .onEnded { _ in
                lastScale = 1.0
            }
    }

    private var dragGesture: some Gesture {
        DragGesture()
            .onChanged { value in
                // Manual pan breaks recenter mode (user takes control)
                if viewModel.isRecenterActive {
                    viewModel.deactivateRecenter()
                }

                // Use absolute translation from drag start, not incremental
                viewModel.panOffset = CGSize(
                    width: dragStartOffset.width + value.translation.width,
                    height: dragStartOffset.height + value.translation.height
                )
            }
            .onEnded { _ in
                dragStartOffset = viewModel.panOffset
            }
    }

    // MARK: - Tap Handling

    private func handleTap(at location: CGPoint) {
        // Adjust tap location for current transforms
        let adjustedLocation = adjustPointForTransforms(location)

        if let poi = viewModel.findPOI(nearScreenPoint: adjustedLocation, in: currentCanvasSize, tapRadius: 40 / viewModel.zoomScale) {
            onPOITapped?(poi)
        }
    }

    private func adjustPointForTransforms(_ point: CGPoint) -> CGPoint {
        let center = CGPoint(x: currentCanvasSize.width / 2, y: currentCanvasSize.height / 2)

        // Reverse pan offset
        var adjusted = CGPoint(
            x: point.x - viewModel.panOffset.width,
            y: point.y - viewModel.panOffset.height
        )

        // Reverse scale (relative to center)
        adjusted = CGPoint(
            x: center.x + (adjusted.x - center.x) / viewModel.zoomScale,
            y: center.y + (adjusted.y - center.y) / viewModel.zoomScale
        )

        return adjusted
    }

    // MARK: - POI Labels Overlay

    @ViewBuilder
    private func poiLabelsOverlay(in size: CGSize) -> some View {
        if let bounds = viewModel.bounds {
            ForEach(viewModel.pois) { poi in
                poiLabel(for: poi, bounds: bounds, size: size)
            }
        }
    }

    @ViewBuilder
    private func poiLabel(for poi: NavigationPOI, bounds: MapBounds, size: CGSize) -> some View {
        let finalPoint = transformedPosition(for: poi.position, bounds: bounds, size: size)
        let isDestination = viewModel.destinationPOI?.id == poi.id
        let labelColor = isDestination ? AppColors.accentGreen : AppColors.textPrimary

        Text(poi.name)
            .font(.system(size: 10, weight: .medium))
            .foregroundColor(labelColor)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(AppColors.cardBackground.opacity(0.9))
            .cornerRadius(4)
            .position(x: finalPoint.x, y: finalPoint.y - 20 * viewModel.zoomScale)
    }

    /// Transform a map position to screen position accounting for zoom, pan, and rotation
    private func transformedPosition(for position: NavPosition, bounds: MapBounds, size: CGSize) -> CGPoint {
        let transformer = MapCoordinateTransformer(bounds: bounds, canvasSize: size, padding: 24)
        let center = CGPoint(x: size.width / 2, y: size.height / 2)
        let basePoint = transformer.toScreenPoint(position)

        // 1. Scale relative to center
        let scaledX = center.x + (basePoint.x - center.x) * viewModel.zoomScale
        let scaledY = center.y + (basePoint.y - center.y) * viewModel.zoomScale

        // 2. Apply pan offset
        let pannedX = scaledX + viewModel.panOffset.width
        let pannedY = scaledY + viewModel.panOffset.height

        return CGPoint(x: pannedX, y: pannedY)
    }
}

// MARK: - Map Control Buttons

/// Control buttons for map interaction (zoom, center, rotate)
struct MapControlButtons: View {

    @ObservedObject var viewModel: NavigationMapViewModel
    var onFullScreen: (() -> Void)?

    var body: some View {
        VStack(spacing: 8) {
            // Full screen button
            if let onFullScreen = onFullScreen {
                controlButton(icon: "arrow.up.left.and.arrow.down.right", action: onFullScreen)
            }

            // Zoom in
            controlButton(icon: "plus.magnifyingglass") {
                withAnimation(.spring(response: 0.2, dampingFraction: 0.8)) {
                    viewModel.applyZoom(1.5)
                }
            }

            // Zoom out
            controlButton(icon: "minus.magnifyingglass") {
                withAnimation(.spring(response: 0.2, dampingFraction: 0.8)) {
                    viewModel.applyZoom(0.67)
                }
            }

            // Center on user
            controlButton(
                icon: "location.fill",
                isActive: viewModel.isRecenterActive
            ) {
                if viewModel.isRecenterActive {
                    viewModel.deactivateRecenter()
                } else {
                    viewModel.activateRecenter()
                }
            }

            // Reset view
            controlButton(icon: "arrow.counterclockwise") {
                viewModel.resetZoomAndPan()
            }
        }
    }

    @ViewBuilder
    private func controlButton(icon: String, isActive: Bool = false, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 14, weight: .semibold))
                .foregroundColor(isActive ? AppColors.accentBlue : .white)
                .frame(width: 32, height: 32)
                .background(AppColors.cardBackground.opacity(0.9))
                .clipShape(Circle())
                .shadow(color: .black.opacity(0.2), radius: 2, x: 0, y: 1)
        }
    }
}

// MARK: - Preview

#Preview {
    ZStack {
        Color.black.ignoresSafeArea()

        VStack {
            Text("Interactive Map Preview")
                .foregroundColor(.white)
            // Note: Preview requires mock ViewModel
        }
    }
}
