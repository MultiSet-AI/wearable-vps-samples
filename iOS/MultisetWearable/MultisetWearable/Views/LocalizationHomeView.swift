/*
Copyright (c) 2026 MultiSet AI. All rights reserved.
Licensed under the MultiSet License. You may not use this file except in compliance with the License. and you can't re-distribute this file without a prior notice
For license details, visit www.multiset.ai.
Redistribution in source or binary forms must retain this notice.
*/

import SwiftUI

/// Landing page for the Multiset VPS localization feature
/// Compact design that fits on screen without scrolling
struct LocalizationHomeView: View {
    @ObservedObject var wearablesVM: WearablesViewModel
    @State private var showSettings = false

    private let config = LocalizationConfig.shared

    var body: some View {
        ZStack {
            // Background gradient
            AppColors.backgroundGradient
                .ignoresSafeArea()

            VStack(spacing: 0) {
                // Top bar with settings
                topBar
                    .padding(.horizontal, 24)
                    .padding(.top, 8)

                // Main content
                VStack(spacing: 16) {
                    // Compact logo and title
                    logoSection

                    // Status card (pairing + map code)
                    statusCard

                    // Feature list
                    featureList

                    Spacer()

                    // Connect button at bottom
                    connectSection
                }
                .padding(.horizontal, 24)
                .padding(.bottom, 32)
            }
        }
        .sheet(isPresented: $showSettings) {
            SettingsView()
        }
    }

    // MARK: - Top Bar
    private var topBar: some View {
        HStack {
            Spacer()
            Button {
                showSettings = true
            } label: {
                Image(systemName: "gearshape.fill")
                    .font(.system(size: 22))
                    .foregroundColor(AppColors.textSecondary)
            }
        }
    }

    // MARK: - Logo Section (Compact with App Icon)
    private var logoSection: some View {
        HStack(spacing: 16) {
            // App icon from assets
            Image("AppIconImage")
                .resizable()
                .aspectRatio(contentMode: .fill)
                .frame(width: 60, height: 60)
                .clipShape(RoundedRectangle(cornerRadius: 14))
                .shadow(color: AppColors.deepBlue.opacity(0.3), radius: 8, x: 0, y: 4)

            VStack(alignment: .leading, spacing: 4) {
                Text("MultiSet Wearable")
                    .font(.system(size: 24, weight: .bold))
                    .foregroundColor(AppColors.textPrimary)

                Text("Visual Positioning System")
                    .font(.system(size: 14))
                    .foregroundColor(AppColors.textSecondary)
            }

            Spacer()
        }
        .padding(.top, 8)
    }

    // MARK: - Status Card (Pairing + Map Code)
    private var statusCard: some View {
        VStack(spacing: 12) {
            // Glasses pairing status
            HStack(spacing: 12) {
                Image("cameraAccessIcon")
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: 24, height: 24)

                Text("Glasses")
                    .font(.system(size: 14))
                    .foregroundColor(AppColors.textSecondary)

                Spacer()

                HStack(spacing: 6) {
                    Circle()
                        .fill(AppColors.yellow)
                        .frame(width: 8, height: 8)
                    Text("Not Connected")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundColor(AppColors.yellow)
                }
            }

            Divider()
                .background(AppColors.textSecondary.opacity(0.3))

            // Map code status
            HStack(spacing: 12) {
                Image(systemName: "map.fill")
                    .font(.system(size: 18))
                    .foregroundColor(AppColors.textSecondary)
                    .frame(width: 24)

                Text("Map")
                    .font(.system(size: 14))
                    .foregroundColor(AppColors.textSecondary)

                Spacer()

                if config.isConfigured {
                    Text(mapDisplayText)
                        .font(.system(size: 14, weight: .medium))
                        .foregroundColor(AppColors.accentGreen)
                        .lineLimit(1)
                } else {
                    HStack(spacing: 6) {
                        Circle()
                            .fill(AppColors.yellow)
                            .frame(width: 8, height: 8)
                        Text("Not Configured")
                            .font(.system(size: 14, weight: .medium))
                            .foregroundColor(AppColors.yellow)
                    }
                }
            }
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(AppColors.cardBackground)
        )
    }

    private var mapDisplayText: String {
        if !config.mapCode.isEmpty {
            return config.mapCode
        } else if !config.mapSetCode.isEmpty {
            return config.mapSetCode
        }
        return "Not configured"
    }

    // MARK: - Feature List
    private var featureList: some View {
        VStack(spacing: 8) {
            FeatureRow(
                icon: "location.fill",
                iconColor: AppColors.accentBlue,
                title: "Precise Localization",
                description: "Get accurate position and orientation"
            )
            FeatureRow(
                icon: "arrow.triangle.turn.up.right.diamond.fill",
                iconColor: AppColors.accentGreen,
                title: "Navigation",
                description: "Turn-by-turn guidance to your destination"
            )
            FeatureRow(
                icon: "speaker.wave.2.fill",
                iconColor: AppColors.accentPurple,
                title: "Audio Feedback",
                description: "Hear directions through your glasses"
            )
            FeatureRow(
                icon: "video.fill",
                iconColor: AppColors.accentRed,
                title: "Live Stream",
                description: "First-person view from Ray-Ban Meta"
            )
            FeatureRow(
                icon: "map.fill",
                iconColor: AppColors.yellow,
                title: "Map Integration",
                description: "Works with your pre-mapped environments"
            )
        }
    }

    // MARK: - Connect Section
    private var connectSection: some View {
        VStack(spacing: 12) {
            Button {
                wearablesVM.connectGlasses()
            } label: {
                HStack {
                    Image(systemName: "glasses")
                        .font(.system(size: 18))
                    Text("Connect My Glasses")
                        .font(.system(size: 16, weight: .semibold))
                }
                .foregroundColor(.white)
                .frame(maxWidth: .infinity)
                .frame(height: 56)
                .background(
                    RoundedRectangle(cornerRadius: 12)
                        .fill(config.isConfigured ? AppColors.deepBlue : AppColors.deepBlue.opacity(0.5))
                )
            }
            .disabled(!config.isConfigured)

            Text("Requires Ray-Ban Meta smart glasses")
                .font(.system(size: 12))
                .foregroundColor(AppColors.textSecondary)
        }
    }
}

// MARK: - Feature Row Component
struct FeatureRow: View {
    let icon: String
    let iconColor: Color
    let title: String
    let description: String

    var body: some View {
        HStack(spacing: 14) {
            // Icon with gradient background
            ZStack {
                Circle()
                    .fill(
                        LinearGradient(
                            colors: [iconColor.opacity(0.25), iconColor.opacity(0.1)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: 40, height: 40)

                Image(systemName: icon)
                    .font(.system(size: 18, weight: .medium))
                    .foregroundColor(iconColor)
            }

            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundColor(AppColors.textPrimary)

                Text(description)
                    .font(.system(size: 12))
                    .foregroundColor(AppColors.textSecondary)
                    .lineLimit(1)
            }

            Spacer()

            // Checkmark indicator
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 16))
                .foregroundColor(iconColor.opacity(0.6))
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .background(
            RoundedRectangle(cornerRadius: 14)
                .fill(AppColors.cardBackground)
                .overlay(
                    RoundedRectangle(cornerRadius: 14)
                        .stroke(iconColor.opacity(0.15), lineWidth: 1)
                )
        )
    }
}

// Preview requires WearablesInterface which is provided by DAT SDK
// Use the app itself for visual testing
