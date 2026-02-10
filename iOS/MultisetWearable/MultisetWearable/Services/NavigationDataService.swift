/*
Copyright (c) 2026 MultiSet AI. All rights reserved.
Licensed under the MultiSet License. You may not use this file except in compliance with the License. and you can't re-distribute this file without a prior notice
For license details, visit www.multiset.ai.
Redistribution in source or binary forms must retain this notice.
*/

import Foundation
import os.log

/// Service for loading and managing navigation data from JSON files
@MainActor
final class NavigationDataService {

    // MARK: - Singleton

    static let shared = NavigationDataService()

    // MARK: - Properties

    private let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "MultiSetWearable", category: "NavigationDataService")

    /// Loaded unified navigation data (POIs, waypoints, paths, and map info)
    private(set) var navigationData: NavigationDataResponse?

    /// Quick lookup for waypoints by ID
    private(set) var waypointLookup: [Int: WaypointData] = [:]

    /// Quick lookup for paths: "fromWaypointId_toPoiId" -> Path
    private(set) var pathLookup: [String: PrecomputedPath] = [:]

    /// Quick lookup for POIs by ID
    private(set) var poiLookup: [Int: NavigationPOI] = [:]

    /// Whether data has been loaded successfully
    var isDataLoaded: Bool {
        ensureDataLoaded()
        return navigationData != nil
    }

    // MARK: - Initialization

    private var hasAttemptedLoad = false

    private init() {
        // Don't load in init - load lazily when data is first needed
        // This ensures mapCode is properly set from UserDefaults first
    }

    /// Ensure data is loaded (call before accessing data)
    func ensureDataLoaded() {
        if !hasAttemptedLoad {
            hasAttemptedLoad = true
            loadNavigationData()
        }
    }

    // MARK: - Public Methods

    /// Get list of available POIs for navigation
    func getPOIs() -> [NavigationPOI] {
        ensureDataLoaded()
        return navigationData?.pois ?? []
    }

    /// Get POI by ID
    func getPOI(byId id: Int) -> NavigationPOI? {
        ensureDataLoaded()
        return poiLookup[id]
    }

    /// Get precomputed path from waypoint to POI, with runtime fallback
    func getPath(fromWaypointId: Int, toPoiId: Int) -> PrecomputedPath? {
        ensureDataLoaded()
        let key = "\(fromWaypointId)_\(toPoiId)"

        // Try precomputed path first
        if let path = pathLookup[key] {
            return path
        }

        // No precomputed path - try to compute one at runtime
        logger.debug("Computing path at runtime for '\(key)'")

        // Get the target POI to find its nearest waypoint
        guard let targetPOI = poiLookup[toPoiId] else {
            logger.error("POI \(toPoiId) not found")
            return nil
        }

        let targetWaypointId = targetPOI.nearestWaypointId

        // Use A* to find path from current waypoint to target's nearest waypoint
        if let waypointPath = findPathAStar(from: fromWaypointId, to: targetWaypointId) {
            // Calculate total distance
            var totalDistance: Float = 0
            for i in 0..<(waypointPath.count - 1) {
                if let wp1 = waypointLookup[waypointPath[i]],
                   let wp2 = waypointLookup[waypointPath[i + 1]] {
                    totalDistance += wp1.position.distance2D(to: wp2.position)
                }
            }
            // Add distance from last waypoint to POI
            if let lastWp = waypointLookup[waypointPath.last ?? targetWaypointId] {
                totalDistance += lastWp.position.distance2D(to: targetPOI.position)
            }

            logger.debug("Computed path: \(waypointPath.count) waypoints, \(String(format: "%.1f", totalDistance))m")

            return PrecomputedPath(
                fromWaypointId: fromWaypointId,
                toPoiId: toPoiId,
                waypointPath: waypointPath,
                totalDistance: totalDistance
            )
        }

        logger.error("Failed to compute path from waypoint \(fromWaypointId) to POI \(toPoiId)")
        return nil
    }

    /// A* pathfinding between two waypoints
    private func findPathAStar(from startId: Int, to goalId: Int) -> [Int]? {
        guard let startWp = waypointLookup[startId],
              let goalWp = waypointLookup[goalId] else {
            return nil
        }

        // Priority queue: (f_score, waypoint_id)
        var openSet: [(Float, Int)] = [(0, startId)]
        var cameFrom: [Int: Int] = [:]
        var gScore: [Int: Float] = [startId: 0]
        var fScore: [Int: Float] = [startId: startWp.position.distance2D(to: goalWp.position)]
        var closedSet: Set<Int> = []

        while !openSet.isEmpty {
            // Sort and get lowest f_score
            openSet.sort { $0.0 < $1.0 }
            let (_, currentId) = openSet.removeFirst()

            if currentId == goalId {
                // Reconstruct path
                var path: [Int] = [currentId]
                var current = currentId
                while let prev = cameFrom[current] {
                    path.insert(prev, at: 0)
                    current = prev
                }
                return path
            }

            if closedSet.contains(currentId) {
                continue
            }
            closedSet.insert(currentId)

            guard let currentWp = waypointLookup[currentId] else { continue }

            // Explore neighbors
            for neighborId in currentWp.connectedWaypoints {
                if closedSet.contains(neighborId) { continue }

                guard let neighborWp = waypointLookup[neighborId] else { continue }

                let tentativeG = (gScore[currentId] ?? .infinity) + currentWp.position.distance2D(to: neighborWp.position)

                if tentativeG < (gScore[neighborId] ?? .infinity) {
                    cameFrom[neighborId] = currentId
                    gScore[neighborId] = tentativeG
                    let h = neighborWp.position.distance2D(to: goalWp.position)
                    fScore[neighborId] = tentativeG + h
                    openSet.append((fScore[neighborId]!, neighborId))
                }
            }
        }

        // No path found
        logger.warning("A* failed to find path from \(startId) to \(goalId)")
        return nil
    }

    /// Get waypoint by ID
    func getWaypoint(byId id: Int) -> WaypointData? {
        ensureDataLoaded()
        return waypointLookup[id]
    }

    /// Find the nearest waypoint to a given position
    func findNearestWaypoint(to position: NavPosition) -> WaypointData? {
        ensureDataLoaded()
        guard let waypoints = navigationData?.waypoints, !waypoints.isEmpty else {
            return nil
        }

        var nearestWaypoint: WaypointData?
        var nearestDistance: Float = .greatestFiniteMagnitude

        for waypoint in waypoints {
            let distance = position.distance2D(to: waypoint.position)
            if distance < nearestDistance {
                nearestDistance = distance
                nearestWaypoint = waypoint
            }
        }

        if let nearest = nearestWaypoint {
            logger.debug("Nearest waypoint: \(nearest.id) at distance \(String(format: "%.2f", nearestDistance))m")
        }

        return nearestWaypoint
    }

    /// Calculate distance from a position to a POI
    func distanceToPOI(from position: NavPosition, poiId: Int) -> Float? {
        guard let poi = poiLookup[poiId] else { return nil }
        return position.distance2D(to: poi.position)
    }

    /// Reload navigation data (useful when map code changes or for testing)
    func reloadData() {
        waypointLookup.removeAll()
        pathLookup.removeAll()
        poiLookup.removeAll()
        navigationData = nil
        hasAttemptedLoad = false
        loadNavigationData()
        hasAttemptedLoad = true
    }

    // MARK: - Private Methods

    private func loadNavigationData() {
        // Use mapCode or mapSetCode from config to build dynamic filename
        let codeToUse = !LocalizationConfig.mapCode.isEmpty ? LocalizationConfig.mapCode : LocalizationConfig.mapSetCode
        let fileName = "\(codeToUse)_navigation_data"

        guard !codeToUse.isEmpty else {
            logger.warning("No mapCode or mapSetCode configured")
            return
        }

        guard let url = Bundle.main.url(forResource: fileName, withExtension: "json") else {
            logger.error("Navigation data file '\(fileName).json' not found in bundle")
            return
        }

        do {
            let data = try Data(contentsOf: url)
            navigationData = try JSONDecoder().decode(NavigationDataResponse.self, from: data)
            buildLookupDictionaries()

            logger.info("Loaded navigation data: \(self.navigationData?.pois.count ?? 0) POIs, \(self.navigationData?.waypoints.count ?? 0) waypoints, \(self.navigationData?.paths.count ?? 0) paths")
        } catch {
            logger.error("Failed to decode navigation data: \(error)")
        }
    }

    private func buildLookupDictionaries() {
        // Build waypoint lookup
        if let waypoints = navigationData?.waypoints {
            for waypoint in waypoints {
                waypointLookup[waypoint.id] = waypoint
            }
        }

        // Build path lookup
        if let paths = navigationData?.paths {
            for path in paths {
                let key = "\(path.fromWaypointId)_\(path.toPoiId)"
                pathLookup[key] = path
            }
        }

        // Build POI lookup
        if let pois = navigationData?.pois {
            for poi in pois {
                poiLookup[poi.id] = poi
            }
        }

        logger.debug("Built lookups: \(self.waypointLookup.count) waypoints, \(self.pathLookup.count) paths, \(self.poiLookup.count) POIs")
    }
}
