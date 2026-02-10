/*
Copyright (c) 2026 MultiSet AI. All rights reserved.
Licensed under the MultiSet License. You may not use this file except in compliance with the License. and you can't re-distribute this file without a prior notice
For license details, visit www.multiset.ai.
Redistribution in source or binary forms must retain this notice.
*/

import SwiftUI

/// Slide-up panel showing available Points of Interest for navigation
struct POIListView: View {
    @ObservedObject var navigationService: AudioNavigationService
    @Binding var isPresented: Bool
    let isLocalized: Bool
    let userPosition: NavPosition?
    let onSelectPOI: (Int) -> Void

    @State private var dragOffset: CGFloat = 0
    @State private var showToast: Bool = false

    var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .bottom) {
                // Semi-transparent background
                Color.black.opacity(0.5)
                    .ignoresSafeArea()
                    .onTapGesture {
                        dismissWithAnimation()
                    }

                // Panel content - stretches to bottom
                VStack(spacing: 0) {
                    // Drag handle
                    dragHandle

                    // Header
                    headerView

                    // Always show POI list
                    poiListContent
                }
                .frame(maxHeight: .infinity)
                .background(AppColors.primaryBackground)
                .cornerRadius(24, corners: [.topLeft, .topRight])
                .offset(y: dragOffset)
                .gesture(dragGesture)
                .animation(.spring(response: 0.4, dampingFraction: 0.8), value: dragOffset)

                // Toast overlay
                if showToast {
                    VStack {
                        toastView
                            .padding(.top, 100)
                        Spacer()
                    }
                    .transition(.opacity.combined(with: .scale))
                }
            }
        }
    }

    // MARK: - Subviews

    private var dragHandle: some View {
        Capsule()
            .fill(Color.white.opacity(0.3))
            .frame(width: 36, height: 5)
            .padding(.top, 12)
            .padding(.bottom, 8)
    }

    private var headerView: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text("Navigate to")
                    .font(.system(size: 24, weight: .bold))
                    .foregroundColor(AppColors.textPrimary)

                Text("\(navigationService.getAvailablePOIs().count) destinations available")
                    .font(.system(size: 14))
                    .foregroundColor(AppColors.textSecondary)
            }

            Spacer()

            // Close button
            Button {
                dismissWithAnimation()
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 28))
                    .foregroundColor(AppColors.textSecondary)
            }
        }
        .padding(.horizontal, 20)
        .padding(.bottom, 16)
    }

    private var poiListContent: some View {
        ScrollView {
            LazyVStack(spacing: 12) {
                ForEach(navigationService.getAvailablePOIs()) { poi in
                    POICardView(
                        poi: poi,
                        distance: isLocalized ? calculateDistance(to: poi) : nil,
                        isEnabled: true
                    ) {
                        if isLocalized {
                            onSelectPOI(poi.id)
                            dismissWithAnimation()
                        } else {
                            showToastMessage()
                        }
                    }
                }
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 32)
        }
    }

    private var toastView: some View {
        HStack(spacing: 10) {
            Image(systemName: "location.slash.fill")
                .font(.system(size: 16))
                .foregroundColor(AppColors.yellow)

            Text("Localize first to start Navigation")
                .font(.system(size: 14, weight: .medium))
                .foregroundColor(.white)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 14)
        .background(Color.black.opacity(0.85))
        .cornerRadius(25)
        .shadow(color: .black.opacity(0.3), radius: 10, x: 0, y: 5)
    }

    private func showToastMessage() {
        withAnimation(.easeInOut(duration: 0.3)) {
            showToast = true
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) {
            withAnimation(.easeInOut(duration: 0.3)) {
                showToast = false
            }
        }
    }

    // MARK: - Helpers

    private var dragGesture: some Gesture {
        DragGesture()
            .onChanged { value in
                if value.translation.height > 0 {
                    dragOffset = value.translation.height
                }
            }
            .onEnded { value in
                if value.translation.height > 100 {
                    dismissWithAnimation()
                } else {
                    dragOffset = 0
                }
            }
    }

    private func calculateDistance(to poi: NavigationPOI) -> Float? {
        guard let position = userPosition else { return nil }
        let poiPosition = NavPosition(x: poi.position.x, y: poi.position.y, z: poi.position.z)
        return position.distance2D(to: poiPosition)
    }

    private func dismissWithAnimation() {
        withAnimation(.easeOut(duration: 0.25)) {
            dragOffset = 1000
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
            isPresented = false
            dragOffset = 0
        }
    }
}

// MARK: - POI Card View

struct POICardView: View {
    let poi: NavigationPOI
    let distance: Float?
    let isEnabled: Bool
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 16) {
                // Icon
                ZStack {
                    Circle()
                        .fill(iconColor.opacity(0.15))
                        .frame(width: 50, height: 50)

                    Image(systemName: poi.iconName)
                        .font(.system(size: 20))
                        .foregroundColor(iconColor)
                }

                // Text content
                VStack(alignment: .leading, spacing: 4) {
                    Text(poi.name)
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundColor(AppColors.textPrimary)

                    HStack(spacing: 8) {
                        Text(poi.type)
                            .font(.system(size: 13))
                            .foregroundColor(AppColors.textSecondary)

                        if let distance = distance {
                            Text("•")
                                .foregroundColor(AppColors.textSecondary)

                            Text(String(format: "%.1f m", distance))
                                .font(.system(size: 13, weight: .medium))
                                .foregroundColor(AppColors.accentBlue)
                        }
                    }
                }

                Spacer()

                // Chevron
                Image(systemName: "chevron.right")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(AppColors.textSecondary)
            }
            .padding(16)
            .background(AppColors.cardBackground)
            .cornerRadius(16)
        }
        .disabled(!isEnabled)
        .opacity(isEnabled ? 1.0 : 0.5)
    }

    private var iconColor: Color {
        switch poi.type.lowercased() {
        case "room":
            return AppColors.accentBlue
        case "foodarea":
            return AppColors.accentGreen
        case "exit":
            return AppColors.accentPurple
        default:
            return AppColors.textSecondary
        }
    }
}

// MARK: - Corner Radius Extension

extension View {
    func cornerRadius(_ radius: CGFloat, corners: UIRectCorner) -> some View {
        clipShape(RoundedCorner(radius: radius, corners: corners))
    }
}

struct RoundedCorner: Shape {
    var radius: CGFloat = .infinity
    var corners: UIRectCorner = .allCorners

    func path(in rect: CGRect) -> Path {
        let path = UIBezierPath(
            roundedRect: rect,
            byRoundingCorners: corners,
            cornerRadii: CGSize(width: radius, height: radius)
        )
        return Path(path.cgPath)
    }
}
