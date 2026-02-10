/*
Copyright (c) 2026 MultiSet AI. All rights reserved.
Licensed under the MultiSet License. You may not use this file except in compliance with the License. and you can't re-distribute this file without a prior notice
For license details, visit www.multiset.ai.
Redistribution in source or binary forms must retain this notice.
*/

import SwiftUI

/// Floating status bar shown during active navigation
struct NavigationStatusView: View {
    @ObservedObject var navigationService: AudioNavigationService
    let onStopNavigation: () -> Void

    @State private var isExpanded: Bool = false

    var body: some View {
        VStack(spacing: 0) {
            // Compact status bar
            compactStatusBar
                .onTapGesture {
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                        isExpanded.toggle()
                    }
                }

            // Expanded details
            if isExpanded {
                expandedContent
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .background(AppColors.cardBackground)
        .cornerRadius(20)
        .shadow(color: .black.opacity(0.3), radius: 10, x: 0, y: 5)
        .padding(.horizontal, 16)
    }

    // MARK: - Compact View

    private var compactStatusBar: some View {
        HStack(spacing: 12) {
            // Navigation indicator (pulsing)
            ZStack {
                Circle()
                    .fill(AppColors.accentGreen.opacity(0.3))
                    .frame(width: 40, height: 40)

                Circle()
                    .fill(AppColors.accentGreen)
                    .frame(width: 28, height: 28)

                if let instruction = navigationService.currentInstruction {
                    Image(systemName: instruction.iconName)
                        .font(.system(size: 14, weight: .bold))
                        .foregroundColor(.white)
                }
            }

            // Destination and distance
            VStack(alignment: .leading, spacing: 2) {
                if let destination = navigationService.currentDestination {
                    Text(destination.name)
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundColor(AppColors.textPrimary)
                }

                Text(String(format: "%.1f m remaining", navigationService.remainingDistance))
                    .font(.system(size: 12))
                    .foregroundColor(AppColors.textSecondary)
            }

            Spacer()

            // Current instruction text
            if let instruction = navigationService.currentInstruction {
                Text(instruction.description)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(AppColors.accentGreen)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(AppColors.accentGreen.opacity(0.15))
                    .cornerRadius(12)
            }

            // Expand/collapse indicator
            Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                .font(.system(size: 12, weight: .semibold))
                .foregroundColor(AppColors.textSecondary)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }

    // MARK: - Expanded View

    private var expandedContent: some View {
        VStack(spacing: 16) {
            Divider()
                .background(Color.white.opacity(0.1))

            // Progress indicator
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("Progress")
                        .font(.system(size: 13))
                        .foregroundColor(AppColors.textSecondary)

                    Spacer()

                    Text("\(navigationService.currentWaypointIndex + 1) of \(navigationService.totalWaypoints) waypoints")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundColor(AppColors.textPrimary)
                }

                // Progress bar
                GeometryReader { geometry in
                    ZStack(alignment: .leading) {
                        Capsule()
                            .fill(Color.white.opacity(0.1))
                            .frame(height: 6)

                        Capsule()
                            .fill(AppColors.accentGreen)
                            .frame(width: progressWidth(in: geometry.size.width), height: 6)
                    }
                }
                .frame(height: 6)
            }

            // Stop navigation button
            Button {
                onStopNavigation()
            } label: {
                HStack {
                    Image(systemName: "xmark.circle.fill")
                    Text("Stop Navigation")
                }
                .font(.system(size: 15, weight: .semibold))
                .foregroundColor(.white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
                .background(AppColors.red)
                .cornerRadius(12)
            }
        }
        .padding(.horizontal, 16)
        .padding(.bottom, 16)
    }

    // MARK: - Helpers

    private func progressWidth(in totalWidth: CGFloat) -> CGFloat {
        guard navigationService.totalWaypoints > 0 else { return 0 }
        let progress = CGFloat(navigationService.currentWaypointIndex + 1) / CGFloat(navigationService.totalWaypoints)
        return totalWidth * progress
    }
}

// MARK: - Preview

#Preview {
    ZStack {
        Color.black.ignoresSafeArea()

        VStack {
            NavigationStatusView(
                navigationService: AudioNavigationService.shared,
                onStopNavigation: {}
            )

            Spacer()
        }
        .padding(.top, 60)
    }
}
