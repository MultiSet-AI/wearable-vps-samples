/*
Copyright (c) 2026 MultiSet AI. All rights reserved.
Licensed under the MultiSet License. You may not use this file except in compliance with the License. and you can't re-distribute this file without a prior notice
For license details, visit www.multiset.ai.
Redistribution in source or binary forms must retain this notice.
*/

//
// StreamView.swift
//
// Main UI for video streaming from Meta wearable devices using the DAT SDK.
// This view demonstrates the complete streaming API: video streaming with real-time display, photo capture,
// and error handling.
//

import MWDATCore
import SwiftUI

struct StreamView: View {
  @ObservedObject var viewModel: StreamSessionViewModel
  @ObservedObject var wearablesVM: WearablesViewModel
  @Environment(\.horizontalSizeClass) private var horizontalSizeClass
  @StateObject private var mapViewModel = NavigationMapViewModel()
  @State private var showSettings = false
  @State private var showStopConfirmation = false
  @State private var showFullScreenMap = false

  /// Optional dismiss callback for when launched from FeatureSelectionView
  var onDismiss: (() -> Void)?

  /// Adaptive horizontal padding for navigation map
  private var mapHorizontalPadding: CGFloat {
    horizontalSizeClass == .regular ? 40 : 16
  }

  /// Adaptive bottom padding for navigation map
  private var mapBottomPadding: CGFloat {
    horizontalSizeClass == .regular ? 180 : 150
  }

  var body: some View {
    ZStack {
      // Black background for letterboxing/pillarboxing
      Color.black
        .edgesIgnoringSafeArea(.all)

      // Video backdrop
      if let videoFrame = viewModel.currentVideoFrame, viewModel.hasReceivedFirstFrame {
        GeometryReader { geometry in
          Image(uiImage: videoFrame)
            .resizable()
            .aspectRatio(contentMode: .fill)
            .frame(width: geometry.size.width, height: geometry.size.height)
            .clipped()
        }
        .edgesIgnoringSafeArea(.all)
      } else {
        ProgressView()
          .scaleEffect(1.5)
          .foregroundColor(.white)
      }

      // Top bar with info and settings buttons
      VStack {
        HStack {
          // Localization info button (shows when localized)
          if viewModel.localizationStatus == .success {
            Button {
              viewModel.showPhotoPreview = true
            } label: {
              HStack(spacing: 6) {
                Image(systemName: "checkmark.circle.fill")
                  .font(.system(size: 16))
                if let distance = viewModel.localizationResult?.posePosition?.distanceFromOrigin {
                  Text(String(format: "Origin: %.1f m", distance))
                    .font(.system(size: 14, weight: .medium))
                }
              }
              .foregroundColor(.white)
              .padding(.horizontal, 12)
              .padding(.vertical, 8)
              .background(AppColors.accentGreen.opacity(0.8))
              .clipShape(Capsule())
              .shadow(color: .black.opacity(0.3), radius: 4, x: 0, y: 2)
            }
          }

          Spacer()

          // Map button (always visible)
          Button {
            showFullScreenMap = true
          } label: {
            Image(systemName: "map.fill")
              .font(.system(size: 20))
              .foregroundColor(.white)
              .padding(12)
              .background(Color.black.opacity(0.5))
              .clipShape(Circle())
          }

          Button {
            showSettings = true
          } label: {
            Image(systemName: "gearshape.fill")
              .font(.system(size: 22))
              .foregroundColor(.white)
              .padding(12)
              .background(Color.black.opacity(0.5))
              .clipShape(Circle())
          }
        }
        Spacer()
      }
      .padding(.all, 16)

      // Navigation status (when navigating)
      if viewModel.isNavigationActive {
        VStack {
          NavigationStatusView(
            navigationService: viewModel.navigationService,
            onStopNavigation: {
              viewModel.stopNavigation()
            }
          )
          Spacer()
        }
        .padding(.top, 100)
        .padding(.horizontal, 8)
      }

      // Navigation map overlay (shown after successful localization or during navigation)
      if viewModel.localizationStatus == .success || viewModel.isNavigationActive {
        VStack {
          Spacer()
          NavigationMapView(
            streamViewModel: viewModel,
            onStartNavigation: { poiId in
              viewModel.startNavigation(to: poiId)
            },
            onStopNavigation: {
              viewModel.stopNavigation()
            }
          )
            .padding(.horizontal, mapHorizontalPadding)
            .padding(.bottom, mapBottomPadding) // Position above bottom controls
        }
        .transition(.opacity.combined(with: .move(edge: .bottom)))
        .animation(.spring(response: 0.4, dampingFraction: 0.8), value: viewModel.localizationStatus)
      }

      // Bottom controls layer
      VStack {
        Spacer()
        ControlsView(
          viewModel: viewModel,
          showStopConfirmation: $showStopConfirmation,
          onShowPOIList: {
            withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
              viewModel.showPOIList = true
            }
          }
        )
      }
      .padding(.all, 24)

      // Timer display area with fixed height
      VStack {
        Spacer()
        if viewModel.activeTimeLimit.isTimeLimited && viewModel.remainingTime > 0 {
          Text("Streaming ending in \(viewModel.remainingTime.formattedCountdown)")
            .font(.system(size: 15))
            .foregroundColor(.white)
        }
      }

      // POI List overlay
      if viewModel.showPOIList {
        POIListView(
          navigationService: viewModel.navigationService,
          isPresented: $viewModel.showPOIList,
          isLocalized: viewModel.localizationStatus == .success,
          userPosition: viewModel.currentUserPosition,
          onSelectPOI: { poiId in
            viewModel.startNavigation(to: poiId)
          }
        )
        .transition(.move(edge: .bottom).combined(with: .opacity))
      }
    }
    .onDisappear {
      Task {
        if viewModel.streamingStatus != .stopped {
          await viewModel.stopSession()
        }
      }
    }
    // Show captured photos from DAT SDK in a preview sheet
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
    // Settings sheet
    .sheet(isPresented: $showSettings) {
      SettingsView()
    }
    // Full screen map (accessible anytime)
    .fullScreenCover(isPresented: $showFullScreenMap) {
      FullScreenMapView(
        viewModel: mapViewModel,
        onStartNavigation: { poiId in
          viewModel.startNavigation(to: poiId)
        },
        onStopNavigation: {
          viewModel.stopNavigation()
        },
        navigationService: viewModel.navigationService,
        isLocalized: viewModel.localizationStatus == .success
      )
    }
    .onReceive(viewModel.$localizationResult) { result in
      mapViewModel.updateFromLocalizationResult(result)
    }
    // Stop confirmation alert
    .alert("Close Navigation?", isPresented: $showStopConfirmation) {
      Button("Cancel", role: .cancel) { }
      Button("Close", role: .destructive) {
        Task {
          if viewModel.isNavigationActive {
            viewModel.stopNavigation()
          }
          await viewModel.stopSession()
          // Dismiss back to feature selection if launched from there
          onDismiss?()
        }
      }
    } message: {
      Text("This will stop the camera stream and end any active navigation.")
    }
  }
}

// Extracted controls for clarity
struct ControlsView: View {
  @ObservedObject var viewModel: StreamSessionViewModel
  @Binding var showStopConfirmation: Bool
  let onShowPOIList: () -> Void

  var body: some View {
    VStack(spacing: 16) {
      // Direction guidance icon (shown during navigation)
      if viewModel.isNavigationActive {
        DirectionGuidanceIcon(navigationService: viewModel.navigationService)
      }

      // Controls row with capture button centered
      HStack {
        // Stop button (left)
        Button {
          showStopConfirmation = true
        } label: {
          Image(systemName: "xmark")
            .font(.system(size: 16, weight: .bold))
            .foregroundColor(.white)
            .frame(width: 50, height: 50)
            .background(Color.white.opacity(0.25))
            .clipShape(Circle())
            .shadow(color: .black.opacity(0.4), radius: 6, x: 0, y: 3)
        }

        Spacer()

        // Capture/Localize button (center)
        LocalizeButton(viewModel: viewModel)

        Spacer()

        // POI List button (right)
        Button {
          onShowPOIList()
        } label: {
          Image(systemName: viewModel.isNavigationActive ? "location.fill" : "mappin.circle.fill")
            .font(.system(size: 22))
            .foregroundColor(.white)
            .frame(width: 50, height: 50)
            .background(viewModel.isNavigationActive ? AppColors.accentGreen.opacity(0.8) : Color.white.opacity(0.25))
            .clipShape(Circle())
            .shadow(color: .black.opacity(0.4), radius: 6, x: 0, y: 3)
        }
      }
      .padding(.horizontal, 40)
    }
  }
}

// Localization button with loading state
struct LocalizeButton: View {
  @ObservedObject var viewModel: StreamSessionViewModel

  var body: some View {
    Button {
      viewModel.localize()
    } label: {
      ZStack {
        Image("localization_button")
          .resizable()
          .aspectRatio(contentMode: .fit)
          .frame(width: 72, height: 72)
          .opacity(viewModel.isLocalizing ? 0.6 : 1.0)

        if viewModel.isLocalizing {
          ProgressView()
            .progressViewStyle(CircularProgressViewStyle(tint: .white))
            .scaleEffect(1.2)
        }
      }
    }
    .disabled(viewModel.isLocalizing)
    .scaleEffect(viewModel.isLocalizing ? 0.95 : 1.0)
    .animation(.easeInOut(duration: 0.15), value: viewModel.isLocalizing)
  }
}

// Direction guidance icon shown above localize button during navigation
struct DirectionGuidanceIcon: View {
  @ObservedObject var navigationService: AudioNavigationService
  @State private var animateIcon: Bool = false
  @State private var lastInstruction: NavigationInstruction?

  var body: some View {
    if let instruction = navigationService.currentInstruction {
      HStack(spacing: 8) {
        ZStack {
          Circle()
            .fill(AppColors.accentGreen.opacity(0.3))
            .frame(width: 48, height: 48)
            .scaleEffect(animateIcon ? 1.15 : 1.0)

          Circle()
            .fill(AppColors.accentGreen)
            .frame(width: 36, height: 36)

          Image(systemName: instruction.iconName)
            .font(.system(size: 18, weight: .bold))
            .foregroundColor(.white)
            .rotationEffect(.degrees(animateIcon ? 0 : (lastInstruction != instruction ? -10 : 0)))
        }
        .shadow(color: .black.opacity(0.4), radius: 8, x: 0, y: 4)

        Text(instruction.description)
          .font(.system(size: 14, weight: .semibold))
          .foregroundColor(.white)
          .padding(.horizontal, 12)
          .padding(.vertical, 8)
          .background(AppColors.cardBackground.opacity(0.9))
          .cornerRadius(16)
          .shadow(color: .black.opacity(0.3), radius: 6, x: 0, y: 3)
      }
      .onChange(of: instruction) { _, newInstruction in
        // Animate when instruction changes
        withAnimation(.easeInOut(duration: 0.3)) {
          animateIcon = true
        }
        lastInstruction = newInstruction
        // Reset animation
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
          withAnimation(.easeInOut(duration: 0.2)) {
            animateIcon = false
          }
        }
      }
      .onAppear {
        lastInstruction = instruction
      }
    }
  }
}
