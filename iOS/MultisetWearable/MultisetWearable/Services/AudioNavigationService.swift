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
final class AudioNavigationService: ObservableObject {

    // MARK: - Singleton

    static let shared = AudioNavigationService()

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

    // MARK: - Services

    private let dataService = NavigationDataService.shared
    private let audioService = NavigationAudioService.shared
    private let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "MultiSetWearable", category: "AudioNavigationService")

    // MARK: - Constants (angle thresholds from Unity reference)

    /// Angle threshold for "move forward" instruction (degrees)
    private let forwardAngleThreshold: Float = 20.0

    /// Angle threshold for "slight turn" instruction (degrees)
    private let slightTurnThreshold: Float = 60.0

    /// Angle threshold for "turn around" instruction (degrees) - when user is facing opposite direction
    private let turnAroundThreshold: Float = 150.0

    /// Distance to consider waypoint reached (meters)
    private let waypointReachDistance: Float = 1.5

    /// Maximum distance before recalculating path (meters)
    private let maxOffPathDistance: Float = 5.0

    // MARK: - Constants (Navigation Improvements)

    /// Hysteresis buffer to prevent instruction flip-flopping (degrees)
    /// Angle must change by this amount beyond threshold to trigger new instruction
    private let hysteresisBuffer: Float = 10.0

    /// Number of heading samples to keep for smoothing
    private let headingHistorySize: Int = 5

    /// Time after which movement heading is considered stale (seconds)
    private let movementHeadingStalenessTimeout: TimeInterval = 3.0

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
        remainingDistance = path.totalDistance

        // Reset movement tracking (will be calculated from position changes)
        movementHeading = nil
        previousUserPosition = lastUserPosition
        lastMovementTime = .distantPast
        headingHistory.removeAll()
        userVelocity = (0, 0)
        lastPositionUpdateTime = Date()
        lastInstructionAngle = nil

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
        currentInstruction = nil
        movementHeading = nil
        previousUserPosition = nil
        lastMovementTime = .distantPast
        headingHistory.removeAll()
        userVelocity = (0, 0)
        lastPositionUpdateTime = nil
        lastInstructionAngle = nil
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

        // Update remaining distance using predicted position
        if let destination = currentDestination {
            remainingDistance = predictedPosition.distance2D(to: destination.position)
        }

        // Check if arrived at destination (use actual position for arrival check)
        if checkArrival() {
            return
        }

        // Update path progress with predicted position
        updatePathProgress(using: predictedPosition)

        // Check if off-path and need recalculation
        checkOffPath()

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

        if distanceToPOI <= destination.arrivalRadius {
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

    /// Update progress along the waypoint path
    /// - Parameter predictedPosition: Optional predicted position (uses last known if nil)
    private func updatePathProgress(using predictedPosition: NavPosition? = nil) {
        let userPosition = predictedPosition ?? lastUserPosition
        guard let userPos = userPosition else { return }
        guard currentPath.count > 0 else { return }

        // Check if we've passed waypoints
        while currentWaypointIndex < currentPath.count - 1 {
            let currentWaypointId = currentPath[currentWaypointIndex]
            let nextWaypointId = currentPath[currentWaypointIndex + 1]

            guard let currentWaypoint = dataService.getWaypoint(byId: currentWaypointId),
                  let nextWaypoint = dataService.getWaypoint(byId: nextWaypointId) else { break }

            let distanceToWaypoint = userPos.distance2D(to: currentWaypoint.position)

            // Check 1: Within reach distance of current waypoint
            let withinReachDistance = distanceToWaypoint <= waypointReachDistance

            // Check 2: Passed the waypoint (using dot product with path direction)
            let passedWaypoint = hasPassedWaypoint(
                userPosition: userPos,
                waypoint: currentWaypoint.position,
                nextWaypoint: nextWaypoint.position
            )

            if withinReachDistance || passedWaypoint {
                currentWaypointIndex += 1
                logger.debug("Reached waypoint \(currentWaypointId) (within: \(withinReachDistance), passed: \(passedWaypoint)), advancing to index \(self.currentWaypointIndex)")
            } else {
                break
            }
        }
    }

    /// Check if user has passed a waypoint using dot product
    /// Returns true if user is past the waypoint in the direction of the next waypoint
    private func hasPassedWaypoint(userPosition: NavPosition, waypoint: NavPosition, nextWaypoint: NavPosition) -> Bool {
        // Vector from waypoint to next waypoint (path direction)
        let pathDirX = nextWaypoint.x - waypoint.x
        let pathDirZ = nextWaypoint.z - waypoint.z

        // Vector from waypoint to user
        let toUserX = userPosition.x - waypoint.x
        let toUserZ = userPosition.z - waypoint.z

        // Dot product: positive means user is in the direction of next waypoint from current waypoint
        let dotProduct = pathDirX * toUserX + pathDirZ * toUserZ

        // Also check that user is reasonably close to the path (within 3m perpendicular distance)
        let pathLength = sqrt(pathDirX * pathDirX + pathDirZ * pathDirZ)
        guard pathLength > 0.001 else { return false }

        // Cross product magnitude gives perpendicular distance * path length
        let crossProduct = abs(pathDirX * toUserZ - pathDirZ * toUserX)
        let perpendicularDistance = crossProduct / pathLength

        // User has passed if: dot product is positive AND within 3m of path line
        return dotProduct > 0 && perpendicularDistance < 3.0
    }

    /// Check if user is off-path and recalculate if needed
    private func checkOffPath() {
        guard let userPosition = lastUserPosition,
              let destination = currentDestination,
              currentWaypointIndex < currentPath.count else { return }

        let currentWaypointId = currentPath[currentWaypointIndex]
        guard let currentWaypoint = dataService.getWaypoint(byId: currentWaypointId) else { return }

        let distanceToCurrentWaypoint = userPosition.distance2D(to: currentWaypoint.position)

        // If too far from current waypoint, recalculate path
        if distanceToCurrentWaypoint > maxOffPathDistance {
            logger.warning("User off-path (distance: \(String(format: "%.1f", distanceToCurrentWaypoint))m), recalculating...")
            audioService.playInstruction(.recalculating, force: true)

            // Find new nearest waypoint and path
            if let nearestWaypoint = dataService.findNearestWaypoint(to: userPosition),
               let newPath = dataService.getPath(fromWaypointId: nearestWaypoint.id, toPoiId: destination.id) {
                currentPath = newPath.waypointPath
                currentNavigationPath = newPath.waypointPath
                currentWaypointIndex = 0
                totalWaypoints = currentPath.count
                logger.info("Recalculated path: \(self.currentPath)")
            }
        }
    }

    /// Calculate and announce navigation instruction
    /// - Parameter predictedPosition: Optional predicted position (uses last known if nil)
    private func giveNavigationInstruction(using predictedPosition: NavPosition? = nil) {
        guard isNavigating,
              let userRotation = lastUserRotation else { return }

        let userPosition = predictedPosition ?? lastUserPosition
        guard let userPos = userPosition else { return }

        // Determine target position
        // Strategy: Navigate to current waypoint first, then to destination
        let targetPosition: NavPosition
        var targetName: String = ""

        if currentWaypointIndex < currentPath.count {
            // Navigate to current waypoint in the path
            let currentWaypointId = currentPath[currentWaypointIndex]
            guard let currentWaypoint = dataService.getWaypoint(byId: currentWaypointId) else { return }

            let distToCurrentWp = userPos.distance2D(to: currentWaypoint.position)

            // If close to current waypoint, target the next one or POI
            if distToCurrentWp <= waypointReachDistance {
                if currentWaypointIndex < currentPath.count - 1 {
                    // Target next waypoint
                    let nextWaypointId = currentPath[currentWaypointIndex + 1]
                    guard let nextWaypoint = dataService.getWaypoint(byId: nextWaypointId) else { return }
                    targetPosition = nextWaypoint.position
                    targetName = "WP\(nextWaypointId)"
                } else if let destination = currentDestination {
                    // At last waypoint, target POI directly
                    targetPosition = destination.position
                    targetName = destination.name
                } else {
                    return
                }
            } else {
                // Navigate to current waypoint first
                targetPosition = currentWaypoint.position
                targetName = "WP\(currentWaypointId)"
            }
        } else if let destination = currentDestination {
            // No more waypoints, navigate directly to POI
            targetPosition = destination.position
            targetName = destination.name
        } else {
            return
        }

        let distanceToTarget = userPos.distance2D(to: targetPosition)

        // Calculate angle to target
        let angle = calculateAngleToTarget(
            userPosition: userPos,
            userRotation: userRotation,
            targetPosition: targetPosition
        )

        // Determine instruction based on angle WITH hysteresis
        let instruction = determineInstructionWithHysteresis(angle: angle)

        // Only update if instruction changed (hysteresis may keep same instruction)
        if instruction != currentInstruction {
            currentInstruction = instruction
            lastInstructionAngle = angle
        }

        // Play audio instruction (audio service handles cooldown)
        audioService.playInstruction(instruction)

        logger.debug("Nav: \(targetName), \(String(format: "%.1f", distanceToTarget))m, \(String(format: "%.0f", angle))°, \(instruction.description)")
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

    /// Determine navigation instruction based on angle
    /// In left-handed coordinate system with our angle calculation:
    /// Positive angle = target is to the LEFT (turn left)
    /// Negative angle = target is to the RIGHT (turn right)
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
