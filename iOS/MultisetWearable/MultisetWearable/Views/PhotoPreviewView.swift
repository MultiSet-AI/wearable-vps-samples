/*
Copyright (c) 2026 MultiSet AI. All rights reserved.
Licensed under the MultiSet License. You may not use this file except in compliance with the License. and you can't re-distribute this file without a prior notice
For license details, visit www.multiset.ai.
Redistribution in source or binary forms must retain this notice.
*/

//
// PhotoPreviewView.swift
//
// UI for previewing localization results from Meta wearable devices via the DAT SDK.
// Displays captured photos and localization information in a clean, centered layout.
//

import SwiftUI

struct PhotoPreviewView: View {
  let photo: UIImage
  let localizationResult: LocalizationResult?
  let localizationStatus: LocalizationStatus
  let onDismiss: () -> Void

  @State private var dragOffset = CGSize.zero

  // Convenience initializer for backward compatibility (no localization)
  init(photo: UIImage, onDismiss: @escaping () -> Void) {
    self.photo = photo
    self.localizationResult = nil
    self.localizationStatus = .idle
    self.onDismiss = onDismiss
  }

  // Full initializer with localization
  init(photo: UIImage, localizationResult: LocalizationResult?, localizationStatus: LocalizationStatus, onDismiss: @escaping () -> Void) {
    self.photo = photo
    self.localizationResult = localizationResult
    self.localizationStatus = localizationStatus
    self.onDismiss = onDismiss
  }

  private var isSuccess: Bool {
    localizationStatus == .success
  }

  var body: some View {
    ZStack {
      // Background
      AppColors.primaryBackground
        .ignoresSafeArea()

      VStack(spacing: 0) {
        // Header with close button
        headerView

        // Main content
        ScrollView {
          VStack(spacing: 24) {
            // Centered photo
            photoView

            // Status card
            statusCard

            // Detailed info (only on success)
            if isSuccess, let result = localizationResult {
              detailsCard(result: result)
            }
          }
          .padding(.horizontal, 20)
          .padding(.bottom, 32)
        }
      }
    }
    .gesture(
      DragGesture()
        .onChanged { value in
          if value.translation.height > 0 {
            dragOffset = value.translation
          }
        }
        .onEnded { value in
          if value.translation.height > 100 {
            onDismiss()
          } else {
            withAnimation(.spring()) {
              dragOffset = .zero
            }
          }
        }
    )
    .offset(y: dragOffset.height)
  }

  // MARK: - Header

  private var headerView: some View {
    HStack {
      Text("Localization Result")
        .font(.system(size: 20, weight: .bold))
        .foregroundColor(AppColors.textPrimary)

      Spacer()

      Button {
        onDismiss()
      } label: {
        Image(systemName: "xmark.circle.fill")
          .font(.system(size: 28))
          .foregroundColor(AppColors.textSecondary)
      }
    }
    .padding(.horizontal, 20)
    .padding(.vertical, 16)
  }

  // MARK: - Photo View

  private var photoView: some View {
    Image(uiImage: photo)
      .resizable()
      .aspectRatio(contentMode: .fit)
      .frame(maxHeight: 280)
      .cornerRadius(16)
      .shadow(color: .black.opacity(0.3), radius: 12, x: 0, y: 6)
  }

  // MARK: - Status Card

  private var statusCard: some View {
    VStack(spacing: 16) {
      // Status icon and text
      HStack(spacing: 12) {
        ZStack {
          Circle()
            .fill(isSuccess ? AppColors.accentGreen.opacity(0.15) : AppColors.yellow.opacity(0.15))
            .frame(width: 56, height: 56)

          Image(systemName: isSuccess ? "checkmark.circle.fill" : "xmark.circle.fill")
            .font(.system(size: 28))
            .foregroundColor(isSuccess ? AppColors.accentGreen : AppColors.yellow)
        }

        VStack(alignment: .leading, spacing: 4) {
          Text(isSuccess ? "Localization Successful" : "Localization Failed")
            .font(.system(size: 18, weight: .semibold))
            .foregroundColor(AppColors.textPrimary)

          if isSuccess, let confidence = localizationResult?.confidence {
            Text(String(format: "%.0f%% confidence", confidence * 100))
              .font(.system(size: 14))
              .foregroundColor(AppColors.accentGreen)
          } else if !isSuccess {
            Text("Pose not found in mapped area")
              .font(.system(size: 14))
              .foregroundColor(AppColors.textSecondary)
          }
        }

        Spacer()
      }

      // Distance from origin (prominent display for success)
      if isSuccess, let position = localizationResult?.posePosition {
        Divider()
          .background(Color.white.opacity(0.1))

        HStack {
          VStack(alignment: .leading, spacing: 4) {
            Text("Distance from Origin")
              .font(.system(size: 13))
              .foregroundColor(AppColors.textSecondary)

            Text(String(format: "%.2f m", position.distanceFromOrigin))
              .font(.system(size: 32, weight: .bold, design: .rounded))
              .foregroundColor(AppColors.accentGreen)
          }

          Spacer()

          Image(systemName: "location.fill")
            .font(.system(size: 24))
            .foregroundColor(AppColors.accentGreen.opacity(0.5))
        }
      }
    }
    .padding(20)
    .background(AppColors.cardBackground)
    .cornerRadius(20)
  }

  // MARK: - Details Card

  private func detailsCard(result: LocalizationResult) -> some View {
    VStack(alignment: .leading, spacing: 16) {
      Text("Position & Orientation")
        .font(.system(size: 16, weight: .semibold))
        .foregroundColor(AppColors.textPrimary)

      // Position
      if let position = result.posePosition {
        VStack(alignment: .leading, spacing: 8) {
          Text("POSITION")
            .font(.system(size: 11, weight: .medium))
            .foregroundColor(AppColors.textSecondary)
            .tracking(1)

          HStack(spacing: 12) {
            coordinateView(label: "X", value: position.x, color: AppColors.accentBlue)
            coordinateView(label: "Y", value: position.y, color: AppColors.accentGreen)
            coordinateView(label: "Z", value: position.z, color: AppColors.accentPurple)
          }
        }
      }

      Divider()
        .background(Color.white.opacity(0.1))

      // Rotation
      if let rotation = result.poseRotation {
        VStack(alignment: .leading, spacing: 8) {
          Text("ROTATION (QUATERNION)")
            .font(.system(size: 11, weight: .medium))
            .foregroundColor(AppColors.textSecondary)
            .tracking(1)

          HStack(spacing: 8) {
            coordinateView(label: "X", value: rotation.x, color: AppColors.textSecondary)
            coordinateView(label: "Y", value: rotation.y, color: AppColors.textSecondary)
            coordinateView(label: "Z", value: rotation.z, color: AppColors.textSecondary)
            coordinateView(label: "W", value: rotation.w, color: AppColors.textSecondary)
          }
        }
      }

      Divider()
        .background(Color.white.opacity(0.1))

      // Map info
      let config = LocalizationConfig.shared
      if !config.mapCode.isEmpty {
        HStack {
          VStack(alignment: .leading, spacing: 4) {
            Text("MAP CODE")
              .font(.system(size: 11, weight: .medium))
              .foregroundColor(AppColors.textSecondary)
              .tracking(1)

            Text(config.mapCode)
              .font(.system(size: 15, weight: .medium, design: .monospaced))
              .foregroundColor(AppColors.textPrimary)
          }

          Spacer()

          Image(systemName: "map.fill")
            .font(.system(size: 20))
            .foregroundColor(AppColors.textSecondary.opacity(0.5))
        }
      }
    }
    .padding(20)
    .background(AppColors.cardBackground)
    .cornerRadius(20)
  }

  private func coordinateView(label: String, value: Float, color: Color) -> some View {
    VStack(spacing: 4) {
      Text(label)
        .font(.system(size: 11, weight: .semibold))
        .foregroundColor(color)

      Text(String(format: "%.3f", value))
        .font(.system(size: 14, weight: .medium, design: .monospaced))
        .foregroundColor(AppColors.textPrimary)
    }
    .frame(maxWidth: .infinity)
    .padding(.vertical, 10)
    .background(color.opacity(0.1))
    .cornerRadius(10)
  }
}
