/*
Copyright (c) 2026 MultiSet AI. All rights reserved.
Licensed under the MultiSet License. You may not use this file except in compliance with the License. and you can't re-distribute this file without a prior notice
For license details, visit www.multiset.ai.
Redistribution in source or binary forms must retain this notice.
*/

import SwiftUI

/// A card component showing a preview of the navigation map with all POIs
/// Used on the navigation home screen before starting a stream
struct MapPreviewCard: View {

    // MARK: - Properties

    @StateObject private var viewModel = NavigationMapViewModel()
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass

    /// Callback when user taps a POI
    var onPOISelected: ((NavigationPOI) -> Void)?

    @State private var selectedPOI: NavigationPOI?
    @State private var showPOIPopup: Bool = false
    @State private var isExpanded: Bool = false
    @State private var showFullScreen: Bool = false

    // MARK: - Adaptive Sizing

    private var collapsedHeight: CGFloat {
        horizontalSizeClass == .regular ? 240 : 180
    }

    private var expandedHeight: CGFloat {
        horizontalSizeClass == .regular ? 400 : 320
    }

    // MARK: - Constants

    private enum Constants {
        static let cornerRadius: CGFloat = 16
    }

    // MARK: - Body

    var body: some View {
        VStack(spacing: 0) {
            // Header
            header

            // Map content
            ZStack(alignment: .topTrailing) {
                // Interactive map (no user position in preview)
                InteractiveMapView(
                    viewModel: viewModel,
                    onPOITapped: { poi in
                        selectedPOI = poi
                        withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                            showPOIPopup = true
                        }
                    },
                    showLabels: isExpanded,
                    interactionEnabled: true
                )
                .frame(height: isExpanded ? expandedHeight : collapsedHeight)

                // Mini controls
                VStack(spacing: 6) {
                    // Zoom in
                    miniControlButton(icon: "plus") {
                        withAnimation(.spring(response: 0.2, dampingFraction: 0.8)) {
                            viewModel.applyZoom(1.3)
                        }
                    }

                    // Zoom out
                    miniControlButton(icon: "minus") {
                        withAnimation(.spring(response: 0.2, dampingFraction: 0.8)) {
                            viewModel.applyZoom(0.77)
                        }
                    }

                    // Reset view
                    miniControlButton(icon: "arrow.counterclockwise") {
                        viewModel.resetZoomAndPan()
                    }
                }
                .padding(8)

                // POI popup overlay
                if showPOIPopup, let poi = selectedPOI {
                    poiPopup(poi: poi)
                }
            }

            // Legend row
            legendRow
        }
        .background(AppColors.cardBackground)
        .cornerRadius(Constants.cornerRadius)
        .shadow(color: .black.opacity(0.2), radius: 6, x: 0, y: 3)
        .opacity(viewModel.hasMapData ? 1 : 0)
        .animation(.easeInOut(duration: 0.3), value: viewModel.hasMapData)
        .fullScreenCover(isPresented: $showFullScreen) {
            FullScreenMapView(
                viewModel: viewModel,
                onStartNavigation: nil,
                onStopNavigation: nil,
                navigationService: nil,
                isLocalized: false
            )
        }
    }

    // MARK: - Header

    private var header: some View {
        HStack(spacing: 8) {
            Image(systemName: "map.fill")
                .font(.system(size: 14, weight: .semibold))
                .foregroundColor(AppColors.accentBlue)

            Text("Map Preview")
                .font(.system(size: 14, weight: .semibold))
                .foregroundColor(AppColors.textPrimary)

            Spacer()

            // POI count badge
            if !viewModel.pois.isEmpty {
                HStack(spacing: 4) {
                    Image(systemName: "mappin.circle.fill")
                        .font(.system(size: 10))
                    Text("\(viewModel.pois.count) POIs")
                        .font(.system(size: 11, weight: .medium))
                }
                .foregroundColor(AppColors.accentPurple)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(AppColors.accentPurple.opacity(0.15))
                .cornerRadius(8)
            }

            // Full screen button
            Button {
                showFullScreen = true
            } label: {
                Image(systemName: "arrow.up.left.and.arrow.down.right")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(AppColors.accentBlue)
                    .frame(width: 28, height: 28)
                    .background(AppColors.accentBlue.opacity(0.15))
                    .clipShape(Circle())
            }

            // Expand/collapse
            Button {
                withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                    isExpanded.toggle()
                }
            } label: {
                Image(systemName: isExpanded ? "chevron.up.circle.fill" : "chevron.down.circle.fill")
                    .font(.system(size: 18))
                    .foregroundColor(AppColors.textSecondary)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
    }

    // MARK: - Legend Row

    private var legendRow: some View {
        HStack(spacing: 16) {
            legendItem(color: AppColors.accentBlue, label: "Room")
            legendItem(color: AppColors.accentGreen, label: "Food")
            legendItem(color: AppColors.accentPurple, label: "Exit")

            Spacer()

            Text("Tap POI for details")
                .font(.system(size: 10))
                .foregroundColor(AppColors.textSecondary.opacity(0.7))
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(AppColors.secondaryBackground.opacity(0.5))
    }

    @ViewBuilder
    private func legendItem(color: Color, label: String) -> some View {
        HStack(spacing: 4) {
            Circle()
                .fill(color)
                .frame(width: 8, height: 8)
            Text(label)
                .font(.system(size: 10, weight: .medium))
                .foregroundColor(AppColors.textSecondary)
        }
    }

    // MARK: - Mini Control Button

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

    // MARK: - POI Popup

    @ViewBuilder
    private func poiPopup(poi: NavigationPOI) -> some View {
        VStack(spacing: 0) {
            Spacer()

            VStack(spacing: 10) {
                // Close button row
                HStack {
                    Spacer()
                    Button {
                        withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                            showPOIPopup = false
                            selectedPOI = nil
                        }
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 20))
                            .foregroundColor(AppColors.textSecondary)
                    }
                }
                .padding(.horizontal, 12)
                .padding(.top, 8)

                // POI info
                HStack(spacing: 10) {
                    // Icon
                    Circle()
                        .fill(poiColor(for: poi.type))
                        .frame(width: 40, height: 40)
                        .overlay(
                            Image(systemName: poi.iconName)
                                .font(.system(size: 16))
                                .foregroundColor(.white)
                        )

                    VStack(alignment: .leading, spacing: 2) {
                        Text(poi.name)
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundColor(AppColors.textPrimary)

                        Text(poi.type.capitalized)
                            .font(.system(size: 12))
                            .foregroundColor(AppColors.textSecondary)
                    }

                    Spacer()
                }
                .padding(.horizontal, 12)
                .padding(.bottom, 12)
            }
            .background(AppColors.cardBackground)
            .cornerRadius(12)
            .shadow(color: .black.opacity(0.3), radius: 8, x: 0, y: 2)
            .padding(8)
        }
        .transition(.opacity.combined(with: .scale(scale: 0.9)))
    }

    // MARK: - Helper

    private func poiColor(for type: String) -> Color {
        switch type.lowercased() {
        case "room": return AppColors.accentBlue
        case "foodarea": return AppColors.accentGreen
        case "exit": return AppColors.accentPurple
        default: return AppColors.textSecondary
        }
    }
}
