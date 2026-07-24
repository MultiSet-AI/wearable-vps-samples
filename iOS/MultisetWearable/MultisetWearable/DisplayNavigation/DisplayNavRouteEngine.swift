/*
Copyright (c) 2026 MultiSet AI. All rights reserved.
Licensed under the MultiSet License. You may not use this file except in compliance with the License. and you can't re-distribute this file without a prior notice
For license details, visit www.multiset.ai.
Redistribution in source or binary forms must retain this notice.
*/

import Foundation
import os.log
import Combine

/// Core navigation service that manages path following and audio instructions
@MainActor
final class DisplayNavRouteEngine: ObservableObject {

    // MARK: - Singleton

    static let shared = DisplayNavRouteEngine()

    // MARK: - Published State

    /// Whether navigation is currently active
    @Published private(set) var isNavigating: Bool = false

    /// Current destination POI
    @Published private(set) var currentDestination: NavigationPOI?

    /// Current navigation instruction
    @Published private(set) var currentInstruction: NavigationInstruction?

    /// Remaining distance to destination (meters)
    @Published private(set) var remainingDistance: Float = 0

    /// Current waypoint index in the path
    @Published private(set) var currentWaypointIndex: Int = 0

    /// Total waypoints in current path
    @Published private(set) var totalWaypoints: Int = 0

    /// Current navigation path (waypoint IDs) for map visualization
    @Published private(set) var currentNavigationPath: [Int]?

    /// Distance to the next maneuver target (meters) — the HUD's big number.
    @Published private(set) var distanceToNextManeuver: Float = 0

    // MARK: - Private State

    private var currentPath: [Int] = []
    private var lastUserPosition: NavPosition?
    private var lastUserRotation: Rotation?

    /// Previous position for movement-based heading calculation
    private var previousUserPosition: NavPosition?

    /// Movement-based heading (calculated from position changes)
    private var movementHeading: Float?

    /// Timestamp of last significant movement (for heading staleness detection)
    private var lastMovementTime: Date = .distantPast

    /// Rolling average of recent headings for smoothing (stores last N heading values)
    private var headingHistory: [Float] = []

    /// User velocity for dead reckoning (meters per second in X and Z)
    private var userVelocity: (x: Float, z: Float) = (0, 0)

    /// Timestamp of last position update (for velocity calculation)
    private var lastPositionUpdateTime: Date?

    /// Last instruction's angle threshold center (for hysteresis)
    private var lastInstructionAngle: Float?

    /// Candidate instruction awaiting confirmation by a second consecutive fix
    /// (temporal debounce — keeps pose noise from flickering the arrow)
    private var pendingInstruction: NavigationInstruction?

    /// Route polyline: waypoint positions plus the destination at the end.
    private var routePoints: [NavPosition] = []
    /// Cumulative arc length at each route point.
    private var routeCumLengths: [Float] = []
    private var routeTotalLength: Float = 0
    /// Monotonic arc-length progress of the user's projection along the route.
    private var routeProgress: Float = 0

    /// Read-only route geometry for rendering (card route preview, maps).
    var routeGeometry: [NavPosition] { routePoints }

    /// Fraction of the route completed (0…1), for progress displays.
    var routeProgressFraction: Float {
        routeTotalLength > 0 ? min(1, max(0, routeProgress / routeTotalLength)) : 0
    }

    // MARK: - Services

    private let dataService = NavigationDataService.shared
    private let audioService = NavigationAudioService.shared
    private let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "MultiSetWearable", category: "DisplayNavRouteEngine")

    // MARK: - Constants (angle thresholds from Unity reference)

    /// Angle threshold for "move forward" instruction (degrees)
    private let forwardAngleThreshold: Float = 20.0

    /// Angle threshold for "slight turn" instruction (degrees)
    private let slightTurnThreshold: Float = 60.0

    /// Angle threshold for "turn around" instruction (degrees) - when user is facing opposite direction
    private let turnAroundThreshold: Float = 150.0

    /// Maximum cross-track distance (user → route line) before recalculating (meters)
    private let maxOffPathDistance: Float = 4.0

    /// Pure-pursuit look-ahead: guidance aims this far ahead ALONG the route (meters)
    private let pursuitLookAhead: Float = 3.5

    /// Chord window used to sample smoothed route direction (meters).
    /// Averages out the 0.5 m grid staircase.
    private let chordWindow: Float = 2.0

    /// How far the projection may regress behind current progress (meters) —
    /// tolerates pose noise without letting progress run backward.
    private let backProjectionTolerance: Float = 2.0

    // MARK: - Constants (Navigation Improvements)

    /// Hysteresis buffer to prevent instruction flip-flopping (degrees)
    /// Angle must change by this amount beyond threshold to trigger new instruction
    private let hysteresisBuffer: Float = 10.0

    /// Number of heading samples to keep for smoothing
    private let headingHistorySize: Int = 5

    /// Time after which movement heading is considered stale (seconds)
    private let movementHeadingStalenessTimeout: TimeInterval = 3.0

    /// How far ahead along the path an upcoming bend is announced (meters)
    private let turnAnticipationDistance: Float = 4.0

    /// Minimum path bend that counts as an upcoming turn (degrees)
    private let pathBendThreshold: Float = 40.0

    /// Minimum movement distance to update heading (meters)
    private let minimumMovementForHeading: Float = 0.3

    /// Minimum movement distance to update velocity (meters)
    private let minimumMovementForVelocity: Float = 0.1

    // MARK: - Initialization

    private init() {}

    // MARK: - Public Methods

    /// Start navigation to a POI
    /// - Parameter poiId: The ID of the destination POI
    func startNavigation(to poiId: Int) {
        guard let poi = dataService.getPOI(byId: poiId) else {
            logger.error("POI \(poiId) not found")
            return
        }

        guard let userPosition = lastUserPosition else {
            logger.error("No user position available - localize first")
            return
        }

        // Find nearest waypoint to user's current position
        guard let nearestWaypoint = dataService.findNearestWaypoint(to: userPosition) else {
            logger.error("No nearby waypoint found")
            return
        }

        // Look up precomputed path
        guard let path = dataService.getPath(fromWaypointId: nearestWaypoint.id, toPoiId: poiId) else {
            logger.error("No path found from waypoint \(nearestWaypoint.id) to POI \(poiId)")
            return
        }

        // Set navigation state
        currentPath = path.waypointPath
        currentNavigationPath = path.waypointPath
        currentWaypointIndex = 0
        totalWaypoints = currentPath.count
        currentDestination = poi
        isNavigating = true
        buildRouteGeometry()
        remainingDistance = routeTotalLength

        // Reset movement tracking (will be calculated from position changes)
        movementHeading = nil
        previousUserPosition = lastUserPosition
        lastMovementTime = .distantPast
        headingHistory.removeAll()
        userVelocity = (0, 0)
        lastPositionUpdateTime = Date()
        lastInstructionAngle = nil
        pendingInstruction = nil

        // Reset audio cooldowns and play start audio
        audioService.resetCooldowns()
        audioService.playInstruction(.navigationStarted, force: true)

        logger.info("Navigation started to \(poi.name), distance: \(String(format: "%.1f", self.remainingDistance))m")

        // Give first instruction after a short delay
        Task {
            try? await Task.sleep(nanoseconds: 1_500_000_000) // 1.5 seconds
            if isNavigating {
                giveNavigationInstruction()
            }
        }
    }

    /// Stop current navigation
    func stopNavigation() {
        isNavigating = false
        currentDestination = nil
        currentPath = []
        currentNavigationPath = nil
        currentWaypointIndex = 0
        totalWaypoints = 0
        remainingDistance = 0
        distanceToNextManeuver = 0
        currentInstruction = nil
        movementHeading = nil
        previousUserPosition = nil
        lastMovementTime = .distantPast
        headingHistory.removeAll()
        userVelocity = (0, 0)
        lastPositionUpdateTime = nil
        lastInstructionAngle = nil
        pendingInstruction = nil
        routePoints = []
        routeCumLengths = []
        routeTotalLength = 0
        routeProgress = 0
        audioService.stopAudio()

        logger.info("Navigation stopped")
    }

    /// Update user position (called on each localization success)
    /// - Parameters:
    ///   - position: User's position from localization
    ///   - rotation: User's rotation (quaternion) from localization
    func updatePosition(position: Position, rotation: Rotation) {
        // Position and rotation from API are in map coordinate system (same as Unity navigation data)
        let navPosition = NavPosition(from: position)
        let currentTime = Date()

        // Calculate velocity and movement-based heading (from position change)
        if let prevPos = previousUserPosition {
            let dx = navPosition.x - prevPos.x
            let dz = navPosition.z - prevPos.z
            let moveDist = sqrt(dx * dx + dz * dz)

            // Calculate velocity for dead reckoning
            if moveDist > minimumMovementForVelocity, let lastTime = lastPositionUpdateTime {
                let timeDelta = Float(currentTime.timeIntervalSince(lastTime))
                if timeDelta > 0.01 {  // Avoid division by very small numbers
                    userVelocity = (x: dx / timeDelta, z: dz / timeDelta)
                }
            }

            // Only update movement heading if moved significantly
            if moveDist > minimumMovementForHeading {
                let newHeading = atan2(dz, dx) * 180.0 / Float.pi
                addHeadingToHistory(newHeading)
                self.movementHeading = getSmoothedHeading()
                self.lastMovementTime = currentTime
            }
        }

        // Check if movement heading is stale
        if currentTime.timeIntervalSince(lastMovementTime) > movementHeadingStalenessTimeout {
            // Movement heading is stale - clear it so we fall back to quaternion
            // but also clear velocity since user is likely stationary
            movementHeading = nil
            userVelocity = (0, 0)
        }

        // Store positions and time
        previousUserPosition = lastUserPosition
        lastUserPosition = navPosition
        lastUserRotation = rotation
        lastPositionUpdateTime = currentTime

        guard isNavigating else { return }

        // Apply dead reckoning to predict current position
        let predictedPosition = predictPosition(from: navPosition, time: currentTime)

        // Project the user onto the route polyline: progress is arc length
        // (monotonic), cross-track is the lateral offset from the route.
        if let projection = projectOntoRoute(predictedPosition) {
            routeProgress = max(routeProgress, projection.s)
            currentWaypointIndex = min(projection.segmentIndex, max(currentPath.count - 1, 0))
            // Remaining distance = what's actually left ALONG the route (honest
            // for corridors, unlike straight-line to the POI).
            remainingDistance = max(0, routeTotalLength - routeProgress)

            // Check if arrived at destination (straight-line, authored radius)
            if checkArrival() {
                return
            }

            // Too far from the route line laterally → recalculate from here.
            if projection.crossTrack > maxOffPathDistance {
                recalculateRoute(from: navPosition)
            }
        } else if let destination = currentDestination {
            remainingDistance = predictedPosition.distance2D(to: destination.position)
            if checkArrival() { return }
        }

        // Give navigation instruction using predicted position
        giveNavigationInstruction(using: predictedPosition)
    }

    // MARK: - Heading Smoothing

    /// Add a heading value to the rolling history
    private func addHeadingToHistory(_ heading: Float) {
        headingHistory.append(heading)
        if headingHistory.count > headingHistorySize {
            headingHistory.removeFirst()
        }
    }

    /// Get smoothed heading from history using circular mean
    private func getSmoothedHeading() -> Float {
        guard !headingHistory.isEmpty else { return 0 }

        // Use circular mean to handle wraparound at ±180°
        var sumSin: Float = 0
        var sumCos: Float = 0

        for heading in headingHistory {
            let radians = heading * Float.pi / 180.0
            sumSin += sin(radians)
            sumCos += cos(radians)
        }

        let avgRadians = atan2(sumSin, sumCos)
        return avgRadians * 180.0 / Float.pi
    }

    // MARK: - Dead Reckoning

    /// Predict current position based on last known position and velocity
    private func predictPosition(from position: NavPosition, time: Date) -> NavPosition {
        // Estimate time since position was captured (assume ~100ms latency)
        let latencyEstimate: Float = 0.1

        // Apply velocity to predict where user is now
        let predictedX = position.x + userVelocity.x * latencyEstimate
        let predictedZ = position.z + userVelocity.z * latencyEstimate

        return NavPosition(x: predictedX, y: position.y, z: predictedZ)
    }

    /// Get available POIs for navigation
    func getAvailablePOIs() -> [NavigationPOI] {
        dataService.getPOIs()
    }

    /// Check if navigation data is loaded
    var isDataLoaded: Bool {
        dataService.isDataLoaded
    }

    // MARK: - Private Navigation Logic

    /// Check if user has arrived at destination
    private func checkArrival() -> Bool {
        guard let destination = currentDestination,
              let userPosition = lastUserPosition else { return false }

        let distanceToPOI = userPosition.distance2D(to: destination.position)

        // Use the authored arrival radius with a small floor for pose noise.
        if distanceToPOI <= max(destination.arrivalRadius, 0.75) {
            // Arrived!
            isNavigating = false
            currentInstruction = .destinationReached
            audioService.playInstruction(.destinationReached, force: true)

            logger.info("Arrived at \(destination.name)")

            // Reset after arrival announcement
            Task {
                try? await Task.sleep(nanoseconds: 3_000_000_000) // 3 seconds
                await MainActor.run {
                    self.stopNavigation()
                }
            }

            return true
        }

        return false
    }

    // MARK: - Route geometry

    /// Builds the continuous route polyline (waypoints + destination) and its
    /// cumulative arc lengths. Called on start and after every recalculation.
    private func buildRouteGeometry() {
        routePoints = currentPath.compactMap { dataService.getWaypoint(byId: $0)?.position }
        if let dest = currentDestination?.position {
            routePoints.append(dest)
        }
        routeCumLengths = [0]
        for (a, b) in zip(routePoints, routePoints.dropFirst()) {
            routeCumLengths.append((routeCumLengths.last ?? 0) + a.distance2D(to: b))
        }
        routeTotalLength = routeCumLengths.last ?? 0
        routeProgress = 0
    }

    private func projectOntoRoute(_ p: NavPosition) -> (s: Float, crossTrack: Float, segmentIndex: Int)? {
        guard routePoints.count >= 2 else { return nil }
        let minS = routeProgress - backProjectionTolerance
        var best: (s: Float, d: Float, i: Int)?

        for i in 0..<(routePoints.count - 1) {
            if routeCumLengths[i + 1] < minS { continue }
            let a = routePoints[i]
            let b = routePoints[i + 1]
            let abx = b.x - a.x
            let abz = b.z - a.z
            let len2 = abx * abx + abz * abz
            var t: Float = 0
            if len2 > 1e-6 {
                t = max(0, min(1, ((p.x - a.x) * abx + (p.z - a.z) * abz) / len2))
            }
            let qx = a.x + abx * t
            let qz = a.z + abz * t
            let dx = p.x - qx
            let dz = p.z - qz
            let d = sqrt(dx * dx + dz * dz)
            let s = routeCumLengths[i] + sqrt(len2) * t
            if s < minS { continue }
            if best == nil || d < best!.d {
                best = (s, d, i)
            }
        }
        guard let found = best else { return nil }
        return (found.s, found.d, found.i)
    }

    /// The route point at arc length `s` (clamped to the route).
    private func pointAlongRoute(_ s: Float) -> NavPosition? {
        guard routePoints.count >= 2 else { return routePoints.first }
        let clamped = max(0, min(s, routeTotalLength))
        var i = 0
        while i < routeCumLengths.count - 2 && routeCumLengths[i + 1] < clamped {
            i += 1
        }
        let segLen = routeCumLengths[i + 1] - routeCumLengths[i]
        let t = segLen > 1e-6 ? (clamped - routeCumLengths[i]) / segLen : 0
        let a = routePoints[i]
        let b = routePoints[i + 1]
        return NavPosition(x: a.x + (b.x - a.x) * t, y: a.y, z: a.z + (b.z - a.z) * t)
    }

    /// Smoothed route direction at arc length `s`: the chord from `s` to
    /// `s + chordWindow`. Averages out the 0.5 m grid staircase.
    private func routeDirectionAngle(at s: Float) -> Float? {
        guard let p1 = pointAlongRoute(s),
              let p2 = pointAlongRoute(min(s + chordWindow, routeTotalLength)) else { return nil }
        let dx = p2.x - p1.x
        let dz = p2.z - p1.z
        guard sqrt(dx * dx + dz * dz) > 0.15 else { return nil }
        return atan2(dz, dx) * 180.0 / Float.pi
    }

    /// Recalculates the route from the user's actual position (cross-track
    /// exceeded `maxOffPathDistance`).
    private func recalculateRoute(from userPosition: NavPosition) {
        guard let destination = currentDestination else { return }
        logger.warning("User off-route, recalculating…")
        audioService.playInstruction(.recalculating, force: true)

        if let nearestWaypoint = dataService.findNearestWaypoint(to: userPosition),
           let newPath = dataService.getPath(fromWaypointId: nearestWaypoint.id, toPoiId: destination.id) {
            currentPath = newPath.waypointPath
            currentNavigationPath = newPath.waypointPath
            currentWaypointIndex = 0
            totalWaypoints = currentPath.count
            buildRouteGeometry()
            remainingDistance = routeTotalLength
            logger.info("Recalculated route: \(self.currentPath)")
        }
    }


    private func giveNavigationInstruction(using predictedPosition: NavPosition? = nil) {
        guard isNavigating,
              let userRotation = lastUserRotation else { return }

        let userPosition = predictedPosition ?? lastUserPosition
        guard let userPos = userPosition else { return }

        // Pure-pursuit target: a point ahead along the route; the POI itself
        // once the remaining route is shorter than the look-ahead.
        let targetPosition: NavPosition
        if routeTotalLength - routeProgress > pursuitLookAhead,
           let pursuit = pointAlongRoute(routeProgress + pursuitLookAhead) {
            targetPosition = pursuit
        } else if let destination = currentDestination {
            targetPosition = destination.position
        } else {
            return
        }

        // Upcoming bend (smoothed chords) drives the maneuver distance and the
        // anticipatory arrow; with no bend ahead, the big number counts down
        // the remaining route.
        let upcoming = upcomingTurn()
        distanceToNextManeuver = upcoming?.distance ?? remainingDistance

        // Calculate angle to target
        let angle = calculateAngleToTarget(
            userPosition: userPos,
            userRotation: userRotation,
            targetPosition: targetPosition
        )

        // Corrective instruction: get the user pointed at the target (with hysteresis)
        var candidate = determineInstructionWithHysteresis(angle: angle)

        // Anticipatory upgrade: when the user is already on track, announce the
        // next significant bend BEFORE reaching it — the arrow flips ahead of
        // the corner instead of reacting after it (real-nav behavior).
        if abs(angle) < slightTurnThreshold,
           let upcoming, upcoming.distance <= turnAnticipationDistance {
            candidate = upcoming.instruction
        }

        // Temporal debounce: adopt a changed instruction only when two
        // consecutive fixes agree (turn-around excepted — a gross correction
        // should never wait). Kills arrow flicker from pose noise.
        let instruction = debounced(candidate)

        // Only update if instruction changed (hysteresis/debounce may keep same instruction)
        if instruction != currentInstruction {
            currentInstruction = instruction
            lastInstructionAngle = angle
        }

        // Play audio instruction (audio service handles cooldown)
        audioService.playInstruction(instruction)

        logger.debug("Nav: s=\(String(format: "%.1f", self.routeProgress))/\(String(format: "%.1f", self.routeTotalLength))m, \(String(format: "%.0f", angle))°, \(instruction.description)")
    }

    private func upcomingTurn() -> (instruction: NavigationInstruction, distance: Float)? {
        guard routePoints.count >= 2 else { return nil }
        let scanLimit = min(routeProgress + 10.0, routeTotalLength - 0.3)
        var probe = routeProgress

        while probe < scanLimit {
            guard let angleHere = routeDirectionAngle(at: probe),
                  let angleAfter = routeDirectionAngle(at: probe + chordWindow) else { break }
            var bend = angleAfter - angleHere
            while bend > 180 { bend -= 360 }
            while bend < -180 { bend += 360 }

            if abs(bend) >= pathBendThreshold {
                let distance = max(0, probe + chordWindow - routeProgress)
                let instruction: NavigationInstruction = abs(bend) >= slightTurnThreshold
                    ? (bend > 0 ? .turnLeft : .turnRight)
                    : (bend > 0 ? .slightLeft : .slightRight)
                return (instruction, distance)
            }
            probe += 0.5
        }
        return nil
    }

    /// Adopts a changed instruction only after two consecutive fixes produce it.
    /// The first instruction of a navigation and `.turnAround` pass immediately.
    private func debounced(_ candidate: NavigationInstruction) -> NavigationInstruction {
        guard let current = currentInstruction, current != candidate else {
            pendingInstruction = nil
            return candidate
        }
        if candidate == .turnAround {
            pendingInstruction = nil
            return candidate
        }
        if pendingInstruction == candidate {
            pendingInstruction = nil
            return candidate
        }
        pendingInstruction = candidate
        return current
    }

    /// Determine navigation instruction with hysteresis to prevent flip-flopping
    private func determineInstructionWithHysteresis(angle: Float) -> NavigationInstruction {
        let absAngle = abs(angle)

        // Get base instruction without hysteresis
        let newInstruction = determineInstruction(angle: angle)

        // If we have a previous instruction, apply hysteresis
        guard let prevAngle = lastInstructionAngle, let prevInstruction = currentInstruction else {
            return newInstruction
        }

        // If instruction would change, check if angle has moved enough past threshold
        if newInstruction != prevInstruction {
            let angleDelta = abs(absAngle - abs(prevAngle))

            // Require angle to change by hysteresis buffer before accepting new instruction
            if angleDelta < hysteresisBuffer {
                // Not enough change - keep previous instruction
                return prevInstruction
            }
        }

        return newInstruction
    }

    /// Calculate signed angle from user's forward direction to target
    /// - Returns: Angle in degrees (positive = turn right, negative = turn left)
    private func calculateAngleToTarget(
        userPosition: NavPosition,
        userRotation: Rotation,
        targetPosition: NavPosition
    ) -> Float {
        // Calculate direction to target
        let dirX = targetPosition.x - userPosition.x
        let dirZ = targetPosition.z - userPosition.z
        let dirMag = sqrt(dirX * dirX + dirZ * dirZ)
        guard dirMag > 0.001 else { return 0 }

        let normDirX = dirX / dirMag
        let normDirZ = dirZ / dirMag

        // Calculate the absolute angle to the target from +X axis
        let targetAngle = atan2(normDirZ, normDirX) * 180.0 / Float.pi

        // Determine user heading: prefer movement-based heading, fall back to quaternion
        let userHeading: Float
        if let moveHead = movementHeading {
            userHeading = moveHead
        } else {
            // Extract forward direction vector from quaternion (same as MapCoordinateTransformer)
            let forwardX = 2.0 * (userRotation.x * userRotation.z + userRotation.w * userRotation.y)
            let forwardZ = 1.0 - 2.0 * (userRotation.x * userRotation.x + userRotation.y * userRotation.y)
            // Use atan2(Z, X) to match target angle calculation format
            userHeading = atan2(forwardZ, forwardX) * 180.0 / Float.pi
        }

        // Calculate turn angle and normalize to -180 to 180
        var angleDiff = targetAngle - userHeading
        while angleDiff > 180 { angleDiff -= 360 }
        while angleDiff < -180 { angleDiff += 360 }

        return angleDiff
    }

    private func determineInstruction(angle: Float) -> NavigationInstruction {
        let absAngle = abs(angle)

        if absAngle < forwardAngleThreshold {
            return .moveForward
        } else if absAngle < slightTurnThreshold {
            // Positive angle = turn left, negative = turn right
            return angle > 0 ? .slightLeft : .slightRight
        } else if absAngle >= turnAroundThreshold {
            // User is facing the opposite direction
            return .turnAround
        } else {
            return angle > 0 ? .turnLeft : .turnRight
        }
    }
}
