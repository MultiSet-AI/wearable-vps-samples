/*
Copyright (c) 2026 MultiSet AI. All rights reserved.
Licensed under the MultiSet License. You may not use this file except in compliance with the License. and you can't re-distribute this file without a prior notice
For license details, visit www.multiset.ai.
Redistribution in source or binary forms must retain this notice.
*/

import SwiftUI

/// Collapsible 2D navigation map overlay for the streaming view
struct NavigationMapView: View {

    // MARK: - Properties

    @StateObject private var viewModel = NavigationMapViewModel()
    @ObservedObject var streamViewModel: StreamSessionViewModel
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass

    /// Callback when navigation is requested from map
    var onStartNavigation: ((Int) -> Void)?

    /// Callback when navigation should be stopped
    var onStopNavigation: (() -> Void)?

    @State private var isExpanded = false

    // MARK: - Adaptive Sizing

    /// Collapsed height based on device type
    private var collapsedHeight: CGFloat {
        horizontalSizeClass == .regular ? 200 : 160
    }

    /// Expanded height based on device type
    private var expandedHeight: CGFloat {
        horizontalSizeClass == .regular ? 360 : 280
    }

    // MARK: - Constants

    private enum Constants {
        static let cornerRadius: CGFloat = 16
        static let headerPadding: CGFloat = 12
    }

    // MARK: - Body

    var body: some View {
        VStack(spacing: 0) {
            // Header with expand/collapse toggle
            mapHeader

            // Map with controls
            ZStack(alignment: .topTrailing) {
                // Interactive map canvas
                InteractiveMapView(
                    viewModel: viewModel,
                    onPOITapped: { poi in
                        handlePOITap(poi)
                    },
                    showLabels: isExpanded,
                    interactionEnabled: true
                )
                .frame(height: isExpanded ? expandedHeight : collapsedHeight)
                .animation(.spring(response: 0.3, dampingFraction: 0.8), value: isExpanded)

                // Mini control buttons (only zoom and fullscreen)
                VStack(spacing: 6) {
                    // Full screen button
                    miniControlButton(icon: "arrow.up.left.and.arrow.down.right") {
                        viewModel.showFullScreenMap = true
                    }

                    // Zoom controls
                    miniControlButton(icon: "plus") {
                        withAnimation(.spring(response: 0.2, dampingFraction: 0.8)) {
                            viewModel.applyZoom(1.3)
                        }
                    }

                    miniControlButton(icon: "minus") {
                        withAnimation(.spring(response: 0.2, dampingFraction: 0.8)) {
                            viewModel.applyZoom(0.77)
                        }
                    }

                    // Center on user
                    miniControlButton(icon: "location.fill") {
                        viewModel.centerOnUser()
                    }
                }
                .padding(8)
            }
        }
        .background(AppColors.cardBackground)
        .cornerRadius(Constants.cornerRadius)
        .shadow(color: .black.opacity(0.3), radius: 8, x: 0, y: 4)
        .onReceive(streamViewModel.$localizationResult) { result in
            viewModel.updateFromLocalizationResult(result)
        }
        .opacity(viewModel.hasMapData ? 1 : 0)
        .animation(.easeInOut(duration: 0.2), value: viewModel.hasMapData)
        .fullScreenCover(isPresented: $viewModel.showFullScreenMap) {
            FullScreenMapView(
                viewModel: viewModel,
                onStartNavigation: { poiId in
                    onStartNavigation?(poiId)
                },
                onStopNavigation: onStopNavigation,
                navigationService: streamViewModel.navigationService,
                isLocalized: streamViewModel.localizationStatus == .success
            )
        }
    }

    // MARK: - Subviews

    private var mapHeader: some View {
        HStack(spacing: 8) {
            // Map icon
            Image(systemName: "map.fill")
                .font(.system(size: 14, weight: .semibold))
                .foregroundColor(AppColors.accentBlue)

            // Title
            Text("Navigation Map")
                .font(.system(size: 14, weight: .semibold))
                .foregroundColor(AppColors.textPrimary)

            Spacer()

            // Navigation status indicator
            if viewModel.isNavigating {
                HStack(spacing: 4) {
                    Circle()
                        .fill(AppColors.accentGreen)
                        .frame(width: 6, height: 6)
                    Text("Navigating")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(AppColors.accentGreen)
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(AppColors.accentGreen.opacity(0.15))
                .cornerRadius(8)
            }

            // Expand/collapse button
            Button {
                withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                    isExpanded.toggle()
                }
            } label: {
                Image(systemName: isExpanded ? "chevron.up.circle.fill" : "chevron.down.circle.fill")
                    .font(.system(size: 20))
                    .foregroundColor(AppColors.textSecondary)
            }
        }
        .padding(.horizontal, Constants.headerPadding)
        .padding(.vertical, 10)
        .background(AppColors.cardBackground)
    }

    @ViewBuilder
    private func miniControlButton(icon: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 12, weight: .bold))
                .foregroundColor(.white)
                .frame(width: 28, height: 28)
                .background(Color.black.opacity(0.5))
                .clipShape(Circle())
        }
    }

    // MARK: - POI Tap Handling

    private func handlePOITap(_ poi: NavigationPOI) {
        // If localized, show confirmation or start navigation directly
        if streamViewModel.localizationStatus == .success {
            // For mini-map, go to full screen to show details
            viewModel.showFullScreenMap = true
        }
    }
}

// MARK: - Preview

#Preview("Navigation Map View") {
    ZStack {
        Color.black.ignoresSafeArea()

        VStack {
            Spacer()

            // Preview placeholder
            VStack(spacing: 0) {
                HStack(spacing: 8) {
                    Image(systemName: "map.fill")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(AppColors.accentBlue)

                    Text("Navigation Map")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(AppColors.textPrimary)

                    Spacer()

                    Image(systemName: "chevron.down.circle.fill")
                        .font(.system(size: 20))
                        .foregroundColor(AppColors.textSecondary)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 10)

                Rectangle()
                    .fill(AppColors.primaryBackground)
                    .frame(height: 160)
            }
            .background(AppColors.cardBackground)
            .cornerRadius(16)
            .shadow(color: .black.opacity(0.3), radius: 8, x: 0, y: 4)
            .padding(.horizontal, 16)
            .padding(.bottom, 150)
        }
    }
}
