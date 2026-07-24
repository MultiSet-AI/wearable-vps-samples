/*
Copyright (c) 2026 MultiSet AI. All rights reserved.
Licensed under the MultiSet License. You may not use this file except in compliance with the License. and you can't re-distribute this file without a prior notice
For license details, visit www.multiset.ai.
Redistribution in source or binary forms must retain this notice.
*/

import MWDATCore
import SwiftUI

struct DisplayNavStreamView: View {
  @Bindable var viewModel: DisplayNavStreamSessionViewModel
  var wearablesVM: WearablesViewModel
  @ObservedObject var controller: LocalizationController
  @Environment(\.horizontalSizeClass) private var horizontalSizeClass
  @StateObject private var mapViewModel = NavigationMapViewModel(routeSource: DisplayNavRouteEngine.shared)
  @State private var showSettings = false
  @State private var showStopConfirmation = false
  @State private var showFullScreenMap = false
  @State private var showLocalizationInfo = false

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
          if controller.localizationStatus == .success {
            Button {
              showLocalizationInfo = true
            } label: {
              HStack(spacing: 6) {
                Image(systemName: "checkmark.circle.fill")
                  .font(.system(size: 16))
                if let distance = controller.localizationResult?.posePosition?.distanceFromOrigin {
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
      if controller.isNavigationActive {
        VStack {
          NavigationStatusView(
            navigationService: controller.navigationService,
            onStopNavigation: {
              controller.stopNavigation()
            }
          )
          Spacer()
        }
        .padding(.top, 100)
        .padding(.horizontal, 8)
      }

      // Navigation map overlay (shown after successful localization or during navigation)
      if controller.localizationStatus == .success || controller.isNavigationActive {
        VStack {
          Spacer()
          DisplayNavMapView(
            controller: controller,
            onStartNavigation: { poiId in
              controller.startNavigation(to: poiId)
            },
            onStopNavigation: {
              controller.stopNavigation()
            }
          )
            .padding(.horizontal, mapHorizontalPadding)
            .padding(.bottom, mapBottomPadding) // Position above bottom controls
        }
        .transition(.opacity.combined(with: .move(edge: .bottom)))
        .animation(.spring(response: 0.4, dampingFraction: 0.8), value: controller.localizationStatus)
      }

      // Bottom controls layer
      VStack {
        Spacer()
        DisplayNavControlsView(
          viewModel: viewModel,
          controller: controller,
          showStopConfirmation: $showStopConfirmation,
          onShowPOIList: {
            withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
              controller.showPOIList = true
            }
          }
        )
      }
      .padding(.all, 24)

      // POI List overlay
      if controller.showPOIList {
        POIListView(
          navigationService: controller.navigationService,
          isPresented: $controller.showPOIList,
          isLocalized: controller.localizationStatus == .success,
          userPosition: controller.currentUserPosition,
          onSelectPOI: { poiId in
            controller.startNavigation(to: poiId)
          }
        )
        .transition(.move(edge: .bottom).combined(with: .opacity))
      }
    }
    // No `.onDisappear` stop here: presenting the full-screen map (fullScreenCover)
    // fires onDisappear on this view while streaming should continue. The stream is
    // stopped explicitly via the close confirmation and on feature dismiss.
    // Captured photos from the DAT SDK (camera button / glasses HUD)
    .sheet(isPresented: $viewModel.showPhotoPreview) {
      if let photo = viewModel.capturedPhoto {
        PhotoPreviewView(
          photo: photo,
          onDismiss: {
            viewModel.dismissPhotoPreview()
          }
        )
      }
    }
    // Localization details (info badge)
    .sheet(isPresented: $showLocalizationInfo) {
      if let frame = controller.queriedFrame {
        PhotoPreviewView(
          photo: frame,
          localizationResult: controller.localizationResult,
          localizationStatus: controller.localizationStatus,
          onDismiss: {
            showLocalizationInfo = false
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
          controller.startNavigation(to: poiId)
        },
        onStopNavigation: {
          controller.stopNavigation()
        },
        navigationService: nil,
        isLocalized: controller.localizationStatus == .success
      )
    }
    .onReceive(controller.$localizationResult) { result in
      mapViewModel.updateFromLocalizationResult(result)
    }
    // Stop confirmation alert
    .alert("Close Navigation?", isPresented: $showStopConfirmation) {
      Button("Cancel", role: .cancel) { }
      Button("Close", role: .destructive) {
        if controller.isNavigationActive {
          controller.stopNavigation()
        }
        viewModel.stopSession()
        // Dismiss back to feature selection if launched from there
        onDismiss?()
      }
    } message: {
      Text("This will stop the camera stream and end any active navigation.")
    }
  }
}

// Extracted controls for clarity
struct DisplayNavControlsView: View {
  var viewModel: DisplayNavStreamSessionViewModel
  @ObservedObject var controller: LocalizationController
  @Binding var showStopConfirmation: Bool
  let onShowPOIList: () -> Void

  var body: some View {
    VStack(spacing: 16) {
      // Direction guidance icon (shown during navigation)
      if controller.isNavigationActive {
        DisplayNavDirectionGuidanceIcon(navigationService: controller.navigationService)
      }

      // Controls row with the localize button centered
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

        // Localize button (center)
        DisplayNavLocalizeButton(controller: controller)

        Spacer()

        // POI List button (right)
        Button {
          onShowPOIList()
        } label: {
          Image(systemName: controller.isNavigationActive ? "location.fill" : "mappin.circle.fill")
            .font(.system(size: 22))
            .foregroundColor(.white)
            .frame(width: 50, height: 50)
            .background(controller.isNavigationActive ? AppColors.accentGreen.opacity(0.8) : Color.white.opacity(0.25))
            .clipShape(Circle())
            .shadow(color: .black.opacity(0.4), radius: 6, x: 0, y: 3)
        }
      }
      .padding(.horizontal, 24)
    }
  }
}

// Localization button with loading state
struct DisplayNavLocalizeButton: View {
  @ObservedObject var controller: LocalizationController

  var body: some View {
    Button {
      controller.localize()
    } label: {
      ZStack {
        Image("localization_button")
          .resizable()
          .aspectRatio(contentMode: .fit)
          .frame(width: 72, height: 72)
          .opacity(controller.isLocalizing ? 0.6 : 1.0)

        if controller.isLocalizing {
          ProgressView()
            .progressViewStyle(CircularProgressViewStyle(tint: .white))
            .scaleEffect(1.2)
        }
      }
    }
    .disabled(controller.isLocalizing)
    .scaleEffect(controller.isLocalizing ? 0.95 : 1.0)
    .animation(.easeInOut(duration: 0.15), value: controller.isLocalizing)
  }
}

// Direction guidance icon shown above localize button during navigation
struct DisplayNavDirectionGuidanceIcon: View {
  @ObservedObject var navigationService: DisplayNavRouteEngine
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
