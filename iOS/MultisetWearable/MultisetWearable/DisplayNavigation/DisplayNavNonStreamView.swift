/*
Copyright (c) 2026 MultiSet AI. All rights reserved.
Licensed under the MultiSet License. You may not use this file except in compliance with the License. and you can't re-distribute this file without a prior notice
For license details, visit www.multiset.ai.
Redistribution in source or binary forms must retain this notice.
*/

import MWDATCore
import SwiftUI

private let updateRequiredBackgroundColor = Color(red: 1.0, green: 0.957, blue: 0.839)
private let updateRequiredForegroundColor = Color(red: 0.541, green: 0.294, blue: 0.0)
private let updateRequiredTitle = "Update required"

struct DisplayNavNonStreamView: View {
  var viewModel: DisplayNavStreamSessionViewModel
  @ObservedObject var wearablesVM: WearablesViewModel
  @ObservedObject var controller: LocalizationController
  @Environment(\.horizontalSizeClass) private var horizontalSizeClass
  @State private var showSettings = false
  @State private var sheetHeight: CGFloat = 300

  /// Optional dismiss callback for when launched from FeatureSelectionView
  var onDismiss: (() -> Void)?

  private let config = LocalizationConfig.shared

  private var isUpdateRequired: Bool {
    viewModel.requiresDATAppUpdate
  }

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
        VStack(spacing: 16) {
          // Logo and title
          logoSection

          // Status badges row
          statusRow

          // Compact feature list
          featureList

          // Map preview with all POIs
          MapPreviewCard()
        }
        .frame(maxWidth: maxContentWidth)
        .padding(.horizontal, horizontalPadding)

        Spacer()

        // Bottom section with button
        VStack(spacing: 12) {
          if isUpdateRequired {
            UpdateRequiredMessage(
              showFirmwareUpdate: false,
              showDATAppUpdate: viewModel.requiresDATAppUpdate
            )
          }

          if viewModel.requiresDATAppUpdate {
            CustomButton(
              title: "Update app on glasses",
              style: .primary,
              isDisabled: false
            ) {
              Task {
                await viewModel.openDATGlassesAppUpdate()
              }
            }
          }

          navigationButton
        }
        .frame(maxWidth: maxContentWidth)
        .padding(.horizontal, horizontalPadding)
        .padding(.bottom, 32)
      }
    }
    .sheet(isPresented: $showSettings) {
      SettingsView()
    }
    .sheet(isPresented: $wearablesVM.showGettingStartedSheet) {
      GettingStartedSheetView(height: $sheetHeight)
        .presentationDetents([.height(sheetHeight)])
        .presentationDragIndicator(.visible)
    }
  }

  // MARK: - Top Bar
  private var topBar: some View {
    HStack {
      // Back button (when launched from feature selection)
      if let onDismiss = onDismiss {
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
      } else {
        // Connected badge
        Menu {
          Button("Disconnect Glasses", role: .destructive) {
            Task { await wearablesVM.disconnectGlasses() }
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

        Image(systemName: "point.topleft.down.to.point.bottomright.curvepath.fill")
          .font(.system(size: 36))
          .foregroundColor(AppColors.accentBlue)
      }

      Text("Navigation")
        .font(.system(size: 28, weight: .bold))
        .foregroundColor(AppColors.textPrimary)

      Text("Audio-guided wayfinding with Ray-Ban Meta")
        .font(.system(size: 14))
        .foregroundColor(AppColors.textSecondary)

      Text("Navigate hands-free using your glasses camera for localization and receive turn-by-turn audio instructions.")
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

  // MARK: - Feature List (Compact)
  private var featureList: some View {
    VStack(spacing: 12) {
      Text("How it works")
        .font(.system(size: 13, weight: .semibold))
        .foregroundColor(AppColors.textSecondary)
        .frame(maxWidth: .infinity, alignment: .leading)

      HStack(spacing: 12) {
        compactFeature(
          icon: "location.fill",
          color: AppColors.accentBlue,
          title: "Localize",
          subtitle: "Find position"
        )
        compactFeature(
          icon: "arrow.triangle.turn.up.right.diamond.fill",
          color: AppColors.accentGreen,
          title: "Navigate",
          subtitle: "Pick destination"
        )
        compactFeature(
          icon: "speaker.wave.2.fill",
          color: AppColors.accentPurple,
          title: "Listen",
          subtitle: "Follow audio"
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

  // MARK: - Navigation Button
  private var navigationButton: some View {
    VStack(spacing: 10) {
      Button {
        Task {
          await viewModel.handleStartStreaming()
        }
      } label: {
        HStack(spacing: 10) {
          Image(systemName: "arrow.triangle.turn.up.right.circle.fill")
            .font(.system(size: 20))

          Text("Open Navigation")
            .font(.system(size: 17, weight: .semibold))
        }
        .foregroundColor(.white)
        .frame(maxWidth: .infinity)
        .frame(height: 54)
        .background(
          RoundedRectangle(cornerRadius: 14)
            .fill(viewModel.hasActiveDevice && !isUpdateRequired ? AppColors.deepBlue : AppColors.deepBlue.opacity(0.5))
        )
        .shadow(color: AppColors.deepBlue.opacity(0.3), radius: 8, x: 0, y: 4)
      }
      .disabled(!viewModel.hasActiveDevice || isUpdateRequired)

      if !viewModel.hasActiveDevice {
        Text("Waiting for glasses to become active...")
          .font(.system(size: 11))
          .foregroundColor(AppColors.textSecondary)
      } else {
        Text("Starts camera stream for localization")
          .font(.system(size: 11))
          .foregroundColor(AppColors.textSecondary)
      }
    }
  }
}

struct UpdateRequiredMessage: View {
  let showFirmwareUpdate: Bool
  let showDATAppUpdate: Bool

  private var message: String {
    if showFirmwareUpdate && showDATAppUpdate {
      return "Your glasses firmware and app need updates before Camera Access can start."
    }
    if showFirmwareUpdate {
      return "Your glasses firmware needs an update before Camera Access can start."
    }
    return "The app on your glasses needs an update before Camera Access can start."
  }

  var body: some View {
    HStack(alignment: .top, spacing: 12) {
      Image(systemName: "exclamationmark.triangle.fill")
        .resizable()
        .aspectRatio(contentMode: .fit)
        .foregroundStyle(updateRequiredForegroundColor)
        .frame(width: 24, height: 24)
        .accessibilityHidden(true)

      VStack(alignment: .leading, spacing: 4) {
        Text(updateRequiredTitle)
          .font(.system(size: 16, weight: .semibold))
          .foregroundStyle(updateRequiredForegroundColor)

        Text(message)
          .font(.system(size: 15))
          .foregroundStyle(updateRequiredForegroundColor)
          .fixedSize(horizontal: false, vertical: true)
      }

      Spacer(minLength: 0)
    }
    .padding(.all, 16)
    .frame(maxWidth: .infinity, alignment: .leading)
    .background(updateRequiredBackgroundColor)
    .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
  }
}

struct GettingStartedSheetView: View {
  @Environment(\.dismiss) var dismiss
  @Binding var height: CGFloat

  var body: some View {
    VStack(spacing: 24) {
      Text("Getting started")
        .font(.system(size: 18, weight: .semibold))
        .foregroundStyle(.primary)

      VStack(spacing: 12) {
        TipItemView(
          resource: .videoIcon,
          text: "First, Camera Access needs permission to use your glasses camera."
        )
        TipItemView(
          resource: .tapIcon,
          text: "Capture photos by tapping the camera button."
        )
        TipItemView(
          resource: .smartGlassesIcon,
          text: "The capture LED lets others know when you're capturing content or going live."
        )
      }
      .padding(.bottom, 16)

      CustomButton(
        title: "Continue",
        style: .primary,
        isDisabled: false
      ) {
        dismiss()
      }
    }
    .padding(.all, 24)
    .background(
      GeometryReader { geo -> Color in
        DispatchQueue.main.async {
          height = geo.size.height
        }
        return Color.clear
      }
    )
  }
}

struct TipItemView: View {
  let resource: ImageResource
  let text: String

  var body: some View {
    HStack(alignment: .top, spacing: 12) {
      Image(resource)
        .resizable()
        .renderingMode(.template)
        .foregroundStyle(.primary)
        .aspectRatio(contentMode: .fit)
        .frame(width: 24)
        .padding(.leading, 4)
        .padding(.top, 4)

      Text(text)
        .font(.system(size: 15))
        .foregroundStyle(.primary)
        .fixedSize(horizontal: false, vertical: true)
    }
    .frame(maxWidth: .infinity, alignment: .leading)
  }
}
