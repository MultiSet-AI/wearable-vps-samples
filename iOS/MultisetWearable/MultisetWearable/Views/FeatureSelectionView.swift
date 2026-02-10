/*
Copyright (c) 2026 MultiSet AI. All rights reserved.
Licensed under the MultiSet License. You may not use this file except in compliance with the License. and you can't re-distribute this file without a prior notice
For license details, visit www.multiset.ai.
Redistribution in source or binary forms must retain this notice.
*/

import MWDATCore
import SwiftUI

/// Landing page after glasses are paired, allowing user to choose between
/// Localization Demo and Navigation Demo experiences
struct FeatureSelectionView: View {
    let wearables: WearablesInterface
    @ObservedObject var wearablesVM: WearablesViewModel
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass

    @State private var selectedFeature: AppFeature?
    @State private var showSettings = false
    @State private var showCredentialsAlert = false

    private let config = LocalizationConfig.shared

    /// Adaptive horizontal padding for iPhone/iPad
    private var horizontalPadding: CGFloat {
        horizontalSizeClass == .regular ? 60 : 24
    }

    /// Maximum content width for iPad to prevent overly wide layouts
    private var maxContentWidth: CGFloat {
        horizontalSizeClass == .regular ? 600 : .infinity
    }

    var body: some View {
        ZStack {
            // Background gradient
            AppColors.backgroundGradient
                .ignoresSafeArea()

            VStack(spacing: 0) {
                // Top bar
                topBar
                    .padding(.horizontal, horizontalPadding)
                    .padding(.top, 16)

                Spacer()

                // Center content
                VStack(spacing: 24) {
                    // Logo and title
                    logoSection

                    // Feature selection cards
                    featureCards
                }
                .frame(maxWidth: maxContentWidth)
                .padding(.horizontal, horizontalPadding)

                Spacer()

                // Footer text
                Text("Select an experience to begin")
                    .font(.system(size: 13))
                    .foregroundColor(AppColors.textSecondary)
                    .padding(.bottom, 32)
            }
        }
        .sheet(isPresented: $showSettings) {
            SettingsView()
        }
        .alert("Configuration Required", isPresented: $showCredentialsAlert) {
            Button("View Status") {
                showSettings = true
            }
            Button("OK", role: .cancel) {}
        } message: {
            Text("API credentials are not configured.\n\nPlease add your credentials in LocalizationConfig.swift and rebuild the app.")
        }
        .onAppear {
            // Show alert if credentials are missing on first appearance
            if !config.hasCredentials {
                showCredentialsAlert = true
            }
        }
        .fullScreenCover(item: $selectedFeature) { feature in
            switch feature {
            case .localization:
                LocalizationDemoView(
                    wearables: wearables,
                    wearablesVM: wearablesVM,
                    onDismiss: { selectedFeature = nil }
                )
            case .navigation:
                StreamSessionView(
                    wearables: wearables,
                    wearablesVM: wearablesVM,
                    onDismiss: { selectedFeature = nil }
                )
            }
        }
    }

    // MARK: - Top Bar

    private var topBar: some View {
        HStack {
            // Connected badge with disconnect menu
            Menu {
                Button("Disconnect Glasses", role: .destructive) {
                    wearablesVM.disconnectGlasses()
                }
                .disabled(wearablesVM.registrationState != .registered)
            } label: {
                HStack(spacing: 6) {
                    Circle()
                        .fill(AppColors.accentGreen)
                        .frame(width: 8, height: 8)
                    Text("Glasses Paired")
                        .font(.system(size: 13, weight: .medium))
                }
                .foregroundColor(AppColors.accentGreen)
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(
                    Capsule()
                        .fill(AppColors.accentGreen.opacity(0.15))
                )
            }

            Spacer()

            Button {
                showSettings = true
            } label: {
                Image(systemName: "gearshape.fill")
                    .font(.system(size: 20))
                    .foregroundColor(AppColors.textSecondary)
            }
        }
    }

    // MARK: - Logo Section

    private var logoSection: some View {
        VStack(spacing: 12) {
            ZStack {
                Circle()
                    .fill(AppColors.deepBlue.opacity(0.2))
                    .frame(width: 90, height: 90)

                Image(systemName: "location.viewfinder")
                    .font(.system(size: 40))
                    .foregroundColor(AppColors.accentBlue)
            }

            Text("MultiSet Wearable VPS")
                .font(.system(size: 28, weight: .bold))
                .foregroundColor(AppColors.textPrimary)

            Text("Choose an experience below")
                .font(.system(size: 15))
                .foregroundColor(AppColors.textSecondary)
        }
    }

    // MARK: - Feature Cards

    private var featureCards: some View {
        VStack(spacing: 16) {
            ForEach(AppFeature.allCases) { feature in
                FeatureSelectionCard(
                    feature: feature,
                    isDisabled: !config.isConfigured
                ) {
                    selectedFeature = feature
                }
            }

            // Configuration warning if not configured
            if !config.isConfigured {
                configWarningBanner
            }
        }
    }

    private var alertMessage: String {
        let errors = config.missingConfiguration
        if errors.isEmpty {
            return "All configuration is complete."
        }
        return errors.map { "• \($0.message)" }.joined(separator: "\n")
    }

    private var configWarningBanner: some View {
        HStack(spacing: 10) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 16))
                .foregroundColor(AppColors.yellow)

            Text("Configure credentials in LocalizationConfig.swift and rebuild")
                .font(.system(size: 13))
                .foregroundColor(AppColors.textSecondary)

            Spacer()

            Button {
                showSettings = true
            } label: {
                Text("Status")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(AppColors.deepBlue)
            }
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(AppColors.yellow.opacity(0.15))
        )
    }
}

// MARK: - Feature Selection Card

struct FeatureSelectionCard: View {
    let feature: AppFeature
    let isDisabled: Bool
    let onSelect: () -> Void

    var body: some View {
        Button(action: onSelect) {
            HStack(spacing: 16) {
                // Icon
                ZStack {
                    RoundedRectangle(cornerRadius: 14)
                        .fill(feature.accentColor.opacity(0.15))
                        .frame(width: 56, height: 56)

                    Image(systemName: feature.iconName)
                        .font(.system(size: 24))
                        .foregroundColor(feature.accentColor)
                }

                // Text content
                VStack(alignment: .leading, spacing: 4) {
                    Text(feature.title)
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundColor(AppColors.textPrimary)

                    Text(feature.description)
                        .font(.system(size: 13))
                        .foregroundColor(AppColors.textSecondary)
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)
                }

                Spacer()

                // Arrow
                Image(systemName: "chevron.right")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(AppColors.textSecondary)
            }
            .padding(16)
            .background(
                RoundedRectangle(cornerRadius: 16)
                    .fill(AppColors.cardBackground)
            )
            .opacity(isDisabled ? 0.5 : 1.0)
        }
        .disabled(isDisabled)
    }
}
