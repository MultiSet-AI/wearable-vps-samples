/*
Copyright (c) 2026 MultiSet AI. All rights reserved.
Licensed under the MultiSet License. You may not use this file except in compliance with the License. and you can't re-distribute this file without a prior notice
For license details, visit www.multiset.ai.
Redistribution in source or binary forms must retain this notice.
*/

import MWDATCore
import SwiftUI

/// Simplified streaming view focused only on localization testing
/// Shows video stream, localize button, and pose results without navigation features
struct LocalizationDemoView: View {
    let wearables: WearablesInterface
    @ObservedObject var wearablesVM: WearablesViewModel
    let onDismiss: () -> Void

    @StateObject private var viewModel: StreamSessionViewModel
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @State private var showSettings = false

    private let config = LocalizationConfig.shared

    /// Adaptive horizontal padding for iPhone/iPad
    private var horizontalPadding: CGFloat {
        horizontalSizeClass == .regular ? 60 : 24
    }

    /// Maximum content width for iPad
    private var maxContentWidth: CGFloat {
        horizontalSizeClass == .regular ? 600 : .infinity
    }

    /// Adaptive horizontal padding for result panel
    private var resultPanelPadding: CGFloat {
        horizontalSizeClass == .regular ? 40 : 16
    }

    init(wearables: WearablesInterface, wearablesVM: WearablesViewModel, onDismiss: @escaping () -> Void) {
        self.wearables = wearables
        self.wearablesVM = wearablesVM
        self.onDismiss = onDismiss
        _viewModel = StateObject(wrappedValue: StreamSessionViewModel(wearables: wearables))
    }

    var body: some View {
        ZStack {
            // Background
            if viewModel.isStreaming {
                Color.black.ignoresSafeArea()
            } else {
                AppColors.backgroundGradient.ignoresSafeArea()
            }

            // Main content based on streaming state
            if viewModel.streamingStatus == .stopped {
                // Pre-streaming landing page
                landingPageView
            } else if viewModel.streamingStatus == .waiting {
                // Waiting for stream to start
                waitingView
            } else {
                // Active streaming view
                streamingView
            }
        }
        .onDisappear {
            Task {
                if viewModel.streamingStatus != .stopped {
                    await viewModel.stopSession()
                }
            }
        }
        .sheet(isPresented: $viewModel.showPhotoPreview) {
            if let photo = viewModel.capturedPhoto {
                PhotoPreviewView(
                    photo: photo,
                    localizationResult: viewModel.localizationResult,
                    localizationStatus: viewModel.localizationStatus,
                    onDismiss: {
                        viewModel.dismissPhotoPreview()
                    }
                )
            }
        }
        .sheet(isPresented: $showSettings) {
            SettingsView()
        }
    }

    // MARK: - Landing Page View

    private var landingPageView: some View {
        VStack(spacing: 0) {
            // Top bar
            topBar
                .padding(.horizontal, horizontalPadding)
                .padding(.top, 16)

            Spacer()

            // Center content
            VStack(spacing: 16) {
                // Logo and title
                logoSection

                // Status badges row
                statusRow

                // Feature description
                featureDescription
            }
            .frame(maxWidth: maxContentWidth)
            .padding(.horizontal, horizontalPadding)

            Spacer()

            // Bottom section with button
            VStack(spacing: 12) {
                openLocalizationButton
            }
            .frame(maxWidth: maxContentWidth)
            .padding(.horizontal, horizontalPadding)
            .padding(.bottom, 32)
        }
    }

    // MARK: - Top Bar

    private var topBar: some View {
        HStack {
            // Back button
            Button {
                onDismiss()
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 14, weight: .semibold))
                    Text("Back")
                        .font(.system(size: 14, weight: .medium))
                }
                .foregroundColor(AppColors.textPrimary)
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(
                    Capsule()
                        .fill(AppColors.cardBackground)
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
        VStack(spacing: 10) {
            ZStack {
                Circle()
                    .fill(AppColors.accentBlue.opacity(0.15))
                    .frame(width: 80, height: 80)

                Image(systemName: "location.viewfinder")
                    .font(.system(size: 36))
                    .foregroundColor(AppColors.accentBlue)
            }

            Text("Localization")
                .font(.system(size: 28, weight: .bold))
                .foregroundColor(AppColors.textPrimary)

            Text("Visual positioning with Ray-Ban Meta")
                .font(.system(size: 14))
                .foregroundColor(AppColors.textSecondary)

            Text("Capture images from your glasses camera and get precise position and orientation data.")
                .font(.system(size: 13))
                .foregroundColor(AppColors.textSecondary.opacity(0.8))
                .multilineTextAlignment(.center)
                .padding(.top, 4)
                .padding(.horizontal, 8)
        }
    }

    // MARK: - Status Row

    private var statusRow: some View {
        HStack(spacing: 12) {
            // Device status
            HStack(spacing: 6) {
                Image(systemName: viewModel.hasActiveDevice ? "checkmark.circle.fill" : "hourglass")
                    .font(.system(size: 14))
                Text(viewModel.hasActiveDevice ? "Device Ready" : "Waiting...")
                    .font(.system(size: 13, weight: .medium))
            }
            .foregroundColor(viewModel.hasActiveDevice ? AppColors.accentGreen : AppColors.yellow)
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(
                Capsule()
                    .fill((viewModel.hasActiveDevice ? AppColors.accentGreen : AppColors.yellow).opacity(0.15))
            )

            // Map status
            if !config.mapCode.isEmpty {
                HStack(spacing: 6) {
                    Image(systemName: "map.fill")
                        .font(.system(size: 12))
                    Text(config.mapCode)
                        .font(.system(size: 12, weight: .medium, design: .monospaced))
                }
                .foregroundColor(AppColors.accentPurple)
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(
                    Capsule()
                        .fill(AppColors.accentPurple.opacity(0.15))
                )
            }
        }
    }

    // MARK: - Feature Description

    private var featureDescription: some View {
        VStack(spacing: 12) {
            Text("How it works")
                .font(.system(size: 13, weight: .semibold))
                .foregroundColor(AppColors.textSecondary)
                .frame(maxWidth: .infinity, alignment: .leading)

            HStack(spacing: 12) {
                compactFeature(
                    icon: "camera.fill",
                    color: AppColors.accentBlue,
                    title: "Capture",
                    subtitle: "Take photo"
                )
                compactFeature(
                    icon: "arrow.up.arrow.down.circle.fill",
                    color: AppColors.accentPurple,
                    title: "Process",
                    subtitle: "Send to API"
                )
                compactFeature(
                    icon: "location.fill",
                    color: AppColors.accentGreen,
                    title: "Localize",
                    subtitle: "Get position"
                )
            }
        }
        .padding(.vertical, 14)
        .padding(.horizontal, 16)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(AppColors.cardBackground)
        )
    }

    private func compactFeature(icon: String, color: Color, title: String, subtitle: String) -> some View {
        VStack(spacing: 6) {
            ZStack {
                Circle()
                    .fill(color.opacity(0.15))
                    .frame(width: 40, height: 40)

                Image(systemName: icon)
                    .font(.system(size: 16))
                    .foregroundColor(color)
            }

            VStack(spacing: 2) {
                Text(title)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(AppColors.textPrimary)

                Text(subtitle)
                    .font(.system(size: 10))
                    .foregroundColor(AppColors.textSecondary)
            }
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - Open Localization Button

    private var openLocalizationButton: some View {
        VStack(spacing: 10) {
            Button {
                Task {
                    await viewModel.handleStartStreaming()
                }
            } label: {
                HStack(spacing: 10) {
                    Image(systemName: "location.viewfinder")
                        .font(.system(size: 20))

                    Text("Open Localization")
                        .font(.system(size: 17, weight: .semibold))
                }
                .foregroundColor(.white)
                .frame(maxWidth: .infinity)
                .frame(height: 54)
                .background(
                    RoundedRectangle(cornerRadius: 14)
                        .fill(viewModel.hasActiveDevice ? AppColors.deepBlue : AppColors.deepBlue.opacity(0.5))
                )
                .shadow(color: AppColors.deepBlue.opacity(0.3), radius: 8, x: 0, y: 4)
            }
            .disabled(!viewModel.hasActiveDevice)

            if !viewModel.hasActiveDevice {
                Text("Waiting for glasses to become active...")
                    .font(.system(size: 11))
                    .foregroundColor(AppColors.textSecondary)
            } else {
                Text("Starts camera stream for localization testing")
                    .font(.system(size: 11))
                    .foregroundColor(AppColors.textSecondary)
            }
        }
    }

    // MARK: - Waiting View

    private var waitingView: some View {
        VStack(spacing: 24) {
            Spacer()

            VStack(spacing: 16) {
                ProgressView()
                    .scaleEffect(1.5)
                    .tint(AppColors.accentBlue)

                Text("Starting camera stream...")
                    .font(.system(size: 15))
                    .foregroundColor(AppColors.textSecondary)
            }

            Spacer()

            Button {
                Task {
                    await viewModel.stopSession()
                }
            } label: {
                Text("Cancel")
                    .font(.system(size: 16, weight: .medium))
                    .foregroundColor(AppColors.textPrimary)
                    .padding(.horizontal, 24)
                    .padding(.vertical, 12)
                    .background(AppColors.cardBackground)
                    .cornerRadius(10)
            }
            .padding(.bottom, 32)
        }
    }

    // MARK: - Streaming View

    private var streamingView: some View {
        ZStack {
            // Video backdrop
            if let videoFrame = viewModel.currentVideoFrame, viewModel.hasReceivedFirstFrame {
                GeometryReader { geometry in
                    Image(uiImage: videoFrame)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                        .frame(width: geometry.size.width, height: geometry.size.height)
                        .clipped()
                }
                .ignoresSafeArea()
            } else {
                VStack {
                    ProgressView()
                        .scaleEffect(1.5)
                        .tint(.white)
                    Text("Waiting for video...")
                        .font(.system(size: 14))
                        .foregroundColor(.white.opacity(0.7))
                        .padding(.top, 12)
                }
            }

            // Top bar with back and settings
            VStack {
                HStack {
                    // Close button
                    Button {
                        Task {
                            await viewModel.stopSession()
                        }
                    } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 16, weight: .bold))
                            .foregroundColor(.white)
                            .frame(width: 36, height: 36)
                            .background(Color.black.opacity(0.5))
                            .clipShape(Circle())
                    }

                    Spacer()

                    // Settings button
                    Button {
                        showSettings = true
                    } label: {
                        Image(systemName: "gearshape.fill")
                            .font(.system(size: 20))
                            .foregroundColor(.white)
                            .padding(12)
                            .background(Color.black.opacity(0.5))
                            .clipShape(Circle())
                    }
                }
                .padding(.horizontal, 16)
                .padding(.top, 16)

                Spacer()
            }

            // Bottom section with result panel and localize button
            VStack {
                Spacer()

                // Result panel (shown after localization)
                if viewModel.localizationStatus == .success || viewModel.localizationStatus == .failure {
                    localizationResultPanel
                        .padding(.horizontal, resultPanelPadding)
                        .padding(.bottom, 16)
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                }

                // Localize button
                LocalizeButton(viewModel: viewModel)
                    .padding(.bottom, 40)
            }
        }
        .animation(.spring(response: 0.4, dampingFraction: 0.8), value: viewModel.localizationStatus)
    }

    // MARK: - Localization Result Panel

    private var localizationResultPanel: some View {
        VStack(spacing: 12) {
            // Header with status
            HStack {
                HStack(spacing: 8) {
                    Image(systemName: viewModel.localizationStatus == .success ? "checkmark.circle.fill" : "xmark.circle.fill")
                        .font(.system(size: 18))
                        .foregroundColor(viewModel.localizationStatus == .success ? AppColors.accentGreen : AppColors.accentRed)

                    Text(viewModel.localizationStatus == .success ? "Localized" : "Not Localized")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundColor(AppColors.textPrimary)
                }

                Spacer()

                // View details button
                if viewModel.localizationStatus == .success {
                    Button {
                        viewModel.showPhotoPreview = true
                    } label: {
                        Text("Details")
                            .font(.system(size: 13, weight: .medium))
                            .foregroundColor(AppColors.accentBlue)
                    }
                }
            }

            // Pose data (only show on success)
            if viewModel.localizationStatus == .success, let result = viewModel.localizationResult {
                Divider()
                    .background(AppColors.textSecondary.opacity(0.3))

                VStack(spacing: 8) {
                    // Position row
                    if let position = result.posePosition {
                        HStack {
                            Text("Position")
                                .font(.system(size: 13, weight: .medium))
                                .foregroundColor(AppColors.textSecondary)

                            Spacer()

                            Text(String(format: "X: %.2f  Y: %.2f  Z: %.2f", position.x, position.y, position.z))
                                .font(.system(size: 13, weight: .medium, design: .monospaced))
                                .foregroundColor(AppColors.textPrimary)
                        }

                        // Distance from origin
                        HStack {
                            Text("Distance")
                                .font(.system(size: 13, weight: .medium))
                                .foregroundColor(AppColors.textSecondary)

                            Spacer()

                            Text(String(format: "%.2f m from origin", position.distanceFromOrigin))
                                .font(.system(size: 13, weight: .medium))
                                .foregroundColor(AppColors.accentBlue)
                        }
                    }

                    // Confidence row
                    if let confidence = result.confidence {
                        HStack {
                            Text("Confidence")
                                .font(.system(size: 13, weight: .medium))
                                .foregroundColor(AppColors.textSecondary)

                            Spacer()

                            Text(String(format: "%.0f%%", confidence * 100))
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundColor(confidenceColor(confidence))
                        }
                    }
                }
            }
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(AppColors.cardBackground.opacity(0.95))
        )
        .shadow(color: .black.opacity(0.3), radius: 10, x: 0, y: 4)
    }

    private func confidenceColor(_ confidence: Float) -> Color {
        if confidence >= 0.7 {
            return AppColors.accentGreen
        } else if confidence >= 0.4 {
            return AppColors.yellow
        } else {
            return AppColors.accentRed
        }
    }
}
