/*
Copyright (c) 2026 MultiSet AI. All rights reserved.
Licensed under the MultiSet License. You may not use this file except in compliance with the License. and you can't re-distribute this file without a prior notice
For license details, visit www.multiset.ai.
Redistribution in source or binary forms must retain this notice.
*/

import SwiftUI

/// Full-screen navigation map view with complete controls and POI interaction
struct FullScreenMapView: View {

    // MARK: - Properties

    @ObservedObject var viewModel: NavigationMapViewModel
    @Environment(\.dismiss) private var dismiss

    /// Callback when navigation is requested to a POI
    var onStartNavigation: ((Int) -> Void)?

    /// Callback when navigation should be stopped
    var onStopNavigation: (() -> Void)?

    /// Reference to navigation service for current instruction
    var navigationService: AudioNavigationService?

    /// Whether user is currently localized
    var isLocalized: Bool

    // MARK: - State

    @State private var selectedPOI: NavigationPOI?
    @State private var showPOIDetail: Bool = false

    // MARK: - Body

    var body: some View {
        ZStack {
            // Background
            AppColors.primaryBackground
                .ignoresSafeArea()

            VStack(spacing: 0) {
                // Header
                header

                // Map with controls
                ZStack(alignment: .topTrailing) {
                    // Interactive map
                    InteractiveMapView(
                        viewModel: viewModel,
                        onPOITapped: { poi in
                            selectedPOI = poi
                            showPOIDetail = true
                        },
                        showLabels: true,
                        interactionEnabled: true
                    )
                    .padding(12)

                    // Control buttons
                    MapControlButtons(viewModel: viewModel)
                        .padding(.top, 20)
                        .padding(.trailing, 20)
                }

                // Navigation controls (when navigating)
                if viewModel.isNavigating {
                    navigationControlBar
                } else {
                    // Legend (only show when not navigating)
                    legendView
                }
            }

            // POI detail sheet
            if showPOIDetail, let poi = selectedPOI {
                poiDetailOverlay(poi: poi)
            }
        }
        .onAppear {
            // Fit map to screen and center when view appears
            viewModel.fitMapToScreen()
        }
    }

    // MARK: - Header

    private var header: some View {
        HStack {
            // Close button
            Button {
                dismiss()
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 28))
                    .foregroundColor(AppColors.textSecondary)
            }

            Spacer()

            VStack(spacing: 2) {
                Text("Navigation Map")
                    .font(.system(size: 18, weight: .bold))
                    .foregroundColor(AppColors.textPrimary)

                if viewModel.isNavigating, let dest = viewModel.destinationPOI {
                    HStack(spacing: 4) {
                        Circle()
                            .fill(AppColors.accentGreen)
                            .frame(width: 6, height: 6)
                        Text("Navigating to \(dest.name)")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundColor(AppColors.accentGreen)
                    }
                }
            }

            Spacer()

            // Placeholder for symmetry
            Color.clear.frame(width: 28, height: 28)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(AppColors.cardBackground)
    }

    // MARK: - Legend

    private var legendView: some View {
        HStack(spacing: 16) {
            legendItem(color: AppColors.accentBlue, icon: "door.left.hand.closed", label: "Room")
            legendItem(color: AppColors.accentGreen, icon: "fork.knife", label: "Food")
            legendItem(color: AppColors.accentPurple, icon: "figure.walk.arrival", label: "Exit")
            legendItem(color: AppColors.accentBlue, icon: "location.fill", label: "You")
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(AppColors.cardBackground)
    }

    @ViewBuilder
    private func legendItem(color: Color, icon: String, label: String) -> some View {
        HStack(spacing: 4) {
            Image(systemName: icon)
                .font(.system(size: 12))
                .foregroundColor(color)
            Text(label)
                .font(.system(size: 11, weight: .medium))
                .foregroundColor(AppColors.textSecondary)
        }
    }

    // MARK: - Navigation Control Bar

    private var navigationControlBar: some View {
        HStack(spacing: 12) {
            // Direction indicator
            if let instruction = navigationService?.currentInstruction {
                HStack(spacing: 10) {
                    // Direction icon
                    ZStack {
                        Circle()
                            .fill(AppColors.accentGreen.opacity(0.2))
                            .frame(width: 44, height: 44)

                        Circle()
                            .fill(AppColors.accentGreen)
                            .frame(width: 32, height: 32)

                        Image(systemName: instruction.iconName)
                            .font(.system(size: 16, weight: .bold))
                            .foregroundColor(.white)
                    }

                    // Instruction text
                    VStack(alignment: .leading, spacing: 2) {
                        Text(instruction.description)
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundColor(AppColors.textPrimary)

                        if let dest = viewModel.destinationPOI {
                            Text("To \(dest.name)")
                                .font(.system(size: 12))
                                .foregroundColor(AppColors.textSecondary)
                        }
                    }
                }
            } else {
                // Fallback when no instruction
                HStack(spacing: 8) {
                    ProgressView()
                        .scaleEffect(0.8)
                        .tint(AppColors.accentGreen)

                    Text("Calculating route...")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundColor(AppColors.textSecondary)
                }
            }

            Spacer()

            // Stop navigation button
            Button {
                onStopNavigation?()
                dismiss()
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "xmark")
                        .font(.system(size: 12, weight: .bold))
                    Text("Stop")
                        .font(.system(size: 13, weight: .semibold))
                }
                .foregroundColor(.white)
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .background(AppColors.accentRed.opacity(0.9))
                .cornerRadius(20)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(AppColors.cardBackground)
    }

    // MARK: - POI Detail Overlay

    @ViewBuilder
    private func poiDetailOverlay(poi: NavigationPOI) -> some View {
        VStack {
            Spacer()

            VStack(spacing: 12) {
                // Handle
                Capsule()
                    .fill(AppColors.textSecondary.opacity(0.5))
                    .frame(width: 36, height: 4)
                    .padding(.top, 8)

                // POI info
                HStack(spacing: 12) {
                    // Icon
                    Circle()
                        .fill(poiColor(for: poi.type))
                        .frame(width: 48, height: 48)
                        .overlay(
                            Image(systemName: poi.iconName)
                                .font(.system(size: 20))
                                .foregroundColor(.white)
                        )

                    // Details
                    VStack(alignment: .leading, spacing: 4) {
                        Text(poi.name)
                            .font(.system(size: 18, weight: .bold))
                            .foregroundColor(AppColors.textPrimary)

                        Text(poi.type.capitalized)
                            .font(.system(size: 13, weight: .medium))
                            .foregroundColor(AppColors.textSecondary)

                        if let distance = viewModel.distanceToPOI(poi) {
                            Text(String(format: "%.1f m away", distance))
                                .font(.system(size: 13, weight: .medium))
                                .foregroundColor(AppColors.accentBlue)
                        }
                    }

                    Spacer()
                }
                .padding(.horizontal, 16)

                // Action buttons
                HStack(spacing: 12) {
                    // Cancel button
                    Button {
                        withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                            showPOIDetail = false
                            selectedPOI = nil
                        }
                    } label: {
                        Text("Cancel")
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundColor(AppColors.textPrimary)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 14)
                            .background(AppColors.secondaryBackground)
                            .cornerRadius(12)
                    }

                    // Navigate button
                    Button {
                        if isLocalized {
                            onStartNavigation?(poi.id)
                            dismiss()
                        }
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: "location.fill")
                            Text("Navigate")
                        }
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .background(isLocalized ? AppColors.accentGreen : AppColors.textSecondary)
                        .cornerRadius(12)
                    }
                    .disabled(!isLocalized)
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 20)
            }
            .background(AppColors.cardBackground)
            .cornerRadius(20, corners: [.topLeft, .topRight])
        }
        .transition(.move(edge: .bottom).combined(with: .opacity))
        .animation(.spring(response: 0.3, dampingFraction: 0.8), value: showPOIDetail)
        .onTapGesture {
            // Dismiss when tapping outside
        }
        .background(
            Color.black.opacity(0.3)
                .ignoresSafeArea()
                .onTapGesture {
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                        showPOIDetail = false
                        selectedPOI = nil
                    }
                }
        )
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
