/*
Copyright (c) 2026 MultiSet AI. All rights reserved.
Licensed under the MultiSet License. You may not use this file except in compliance with the License. and you can't re-distribute this file without a prior notice
For license details, visit www.multiset.ai.
Redistribution in source or binary forms must retain this notice.
*/

import SwiftUI
import Combine

/// ViewModel for managing 2D navigation map state and data binding
@MainActor
class NavigationMapViewModel: ObservableObject {

    // MARK: - Published Properties (Map Data)

    /// Map boundary information for coordinate transformation
    @Published private(set) var bounds: MapBounds?

    /// All waypoints in the navigation graph
    @Published private(set) var waypoints: [WaypointData] = []

    /// All points of interest on the map
    @Published private(set) var pois: [NavigationPOI] = []

    // MARK: - Published Properties (User State)

    /// User's current position from localization
    @Published var userPosition: NavPosition?

    /// User's current rotation (quaternion) from localization
    @Published var userRotation: Rotation?

    // MARK: - Published Properties (Navigation State)

    /// Active navigation path (waypoint IDs in sequence)
    @Published private(set) var activePath: [Int]?

    /// Current destination POI when navigating
    @Published private(set) var destinationPOI: NavigationPOI?

    /// Current waypoint index in the path (for progress visualization)
    @Published private(set) var currentWaypointIndex: Int = 0

    /// Whether navigation is currently active
    @Published private(set) var isNavigating: Bool = false

    // MARK: - Published Properties (Map View State)

    /// Current zoom scale (1.0 = fit to view, >1 = zoomed in)
    @Published var zoomScale: CGFloat = 1.0

    /// Map rotation angle (0 = north up, rotates with user heading if enabled)
    @Published var mapRotation: Angle = .zero

    /// Whether map rotates to match user heading
    @Published var rotateWithHeading: Bool = false

    /// Pan offset for the map
    @Published var panOffset: CGSize = .zero

    /// Whether full screen map is shown
    @Published var showFullScreenMap: Bool = false

    // MARK: - Zoom Constraints

    static let minZoom: CGFloat = 0.3
    static let maxZoom: CGFloat = 10.0

    // MARK: - Services

    private let dataService = NavigationDataService.shared
    private let navigationService = AudioNavigationService.shared

    // MARK: - Combine

    private var cancellables = Set<AnyCancellable>()

    // MARK: - Computed Properties

    /// Whether map data is available for display
    var hasMapData: Bool {
        bounds != nil && !waypoints.isEmpty
    }

    // MARK: - Initialization

    init() {
        loadMapData()
        observeNavigationState()
    }

    // MARK: - Zoom & Pan Methods

    /// Apply zoom change with constraints
    func applyZoom(_ scale: CGFloat) {
        let newScale = zoomScale * scale
        zoomScale = min(max(newScale, Self.minZoom), Self.maxZoom)
    }

    /// Reset zoom and pan to default
    func resetZoomAndPan() {
        withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
            zoomScale = 1.0
            panOffset = .zero
        }
    }

    /// Fit map to screen and center (no animation, for initial display)
    func fitMapToScreen() {
        zoomScale = 1.0
        panOffset = .zero
        mapRotation = .zero
    }

    /// Center map on user position
    func centerOnUser() {
        withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
            panOffset = .zero
        }
    }

    /// Toggle map rotation mode
    func toggleRotationMode() {
        rotateWithHeading.toggle()
        if !rotateWithHeading {
            withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                mapRotation = .zero
            }
        }
    }

    /// Update map rotation based on user heading (if enabled)
    func updateMapRotation() {
        guard rotateWithHeading, let rotation = userRotation else { return }

        // Extract yaw and rotate map opposite to user heading
        // so user always appears to be facing "up" on the map
        let siny_cosp = 2.0 * (rotation.w * rotation.y + rotation.x * rotation.z)
        let cosy_cosp = 1.0 - 2.0 * (rotation.y * rotation.y + rotation.z * rotation.z)
        let yaw = atan2(siny_cosp, cosy_cosp)

        // Rotate map in opposite direction of user heading
        // This makes the user always appear to face "up" on the rotated map
        withAnimation(.easeOut(duration: 0.2)) {
            mapRotation = Angle(radians: Double(yaw))
        }
    }

    // MARK: - Public Methods

    /// Reload map data (useful when map code changes)
    func reloadMapData() {
        dataService.reloadData()
        loadMapData()
    }

    /// Update user pose from localization result
    func updateUserPose(position: NavPosition?, rotation: Rotation?) {
        userPosition = position
        userRotation = rotation
    }

    /// Update user pose from localization result
    func updateFromLocalizationResult(_ result: LocalizationResult?) {
        guard let result = result, result.poseFound else {
            return
        }

        if let position = result.posePosition {
            userPosition = NavPosition(from: position)
        }
        userRotation = result.poseRotation

        // Update map rotation if enabled
        updateMapRotation()
    }

    // MARK: - POI Selection

    /// Find POI near a screen point (for tap interaction)
    func findPOI(nearScreenPoint point: CGPoint, in canvasSize: CGSize, tapRadius: CGFloat = 30) -> NavigationPOI? {
        guard let bounds = bounds else { return nil }

        let transformer = MapCoordinateTransformer(bounds: bounds, canvasSize: canvasSize)

        for poi in pois {
            let poiScreenPoint = transformer.toScreenPoint(poi.position)
            let distance = hypot(point.x - poiScreenPoint.x, point.y - poiScreenPoint.y)

            if distance <= tapRadius {
                return poi
            }
        }

        return nil
    }

    /// Get distance from user to a POI
    func distanceToPOI(_ poi: NavigationPOI) -> Float? {
        guard let userPos = userPosition else { return nil }
        return userPos.distance2D(to: poi.position)
    }

    // MARK: - Private Methods

    private func loadMapData() {
        dataService.ensureDataLoaded()

        bounds = dataService.navigationData?.bounds
        waypoints = dataService.navigationData?.waypoints ?? []
        pois = dataService.navigationData?.pois ?? []
    }

    private func observeNavigationState() {
        // Observe navigation active state
        navigationService.$isNavigating
            .receive(on: DispatchQueue.main)
            .sink { [weak self] isNavigating in
                guard let self = self else { return }
                let wasNavigating = self.isNavigating
                self.isNavigating = isNavigating

                if isNavigating && !wasNavigating {
                    // Navigation just started - show full screen map and fit to screen
                    self.fitMapToScreen()
                    self.showFullScreenMap = true
                } else if !isNavigating {
                    self.activePath = nil
                    self.destinationPOI = nil
                }
            }
            .store(in: &cancellables)

        // Observe current destination
        navigationService.$currentDestination
            .receive(on: DispatchQueue.main)
            .assign(to: &$destinationPOI)

        // Observe waypoint progress
        navigationService.$currentWaypointIndex
            .receive(on: DispatchQueue.main)
            .assign(to: &$currentWaypointIndex)

        // Observe navigation path
        navigationService.$currentNavigationPath
            .receive(on: DispatchQueue.main)
            .assign(to: &$activePath)
    }
}
