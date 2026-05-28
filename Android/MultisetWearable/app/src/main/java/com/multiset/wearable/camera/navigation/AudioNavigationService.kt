/*
Copyright (c) 2026 MultiSet AI. All rights reserved.
Licensed under the MultiSet License. You may not use this file except in compliance with the License. and you can't re-distribute this file without a prior notice
For license details, visit www.multiset.ai.
Redistribution in source or binary forms must retain this notice.
*/

// Core navigation engine — ported from the iOS AudioNavigationService.swift. Follows the
// waypoint path, computes turn instructions, and emits audio cues. Exposes NavigationState
// as a StateFlow for the UI. Algorithm constants match the iOS/Unity reference exactly.

package com.multiset.wearable.vps.navigation

import android.util.Log
import com.multiset.wearable.vps.localization.Position
import com.multiset.wearable.vps.localization.Rotation
import kotlin.math.abs
import kotlin.math.atan2
import kotlin.math.cos
import kotlin.math.sin
import kotlin.math.sqrt
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Job
import kotlinx.coroutines.delay
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.flow.update
import kotlinx.coroutines.launch

/** Observable navigation state for the UI. */
data class NavigationState(
    val isNavigating: Boolean = false,
    val destination: NavigationPOI? = null,
    val currentInstruction: NavigationInstruction? = null,
    val remainingDistance: Float = 0f,
    val currentWaypointIndex: Int = 0,
    val totalWaypoints: Int = 0,
    val navigationPath: List<Int>? = null,
    val userPosition: NavPosition? = null,
    val userRotation: Rotation? = null,
)

class AudioNavigationService(
    private val dataService: NavigationDataService,
    private val audioService: NavigationAudioService,
    private val scope: CoroutineScope,
) {
    companion object {
        private const val TAG = "AudioNavigationService"
        // Angle thresholds (degrees) from the Unity reference
        private const val FORWARD_ANGLE_THRESHOLD = 20.0f
        private const val SLIGHT_TURN_THRESHOLD = 60.0f
        private const val TURN_AROUND_THRESHOLD = 150.0f
        private const val WAYPOINT_REACH_DISTANCE = 1.0f
        private const val MAX_OFF_PATH_DISTANCE = 5.0f
        private const val HYSTERESIS_BUFFER = 10.0f
        private const val HEADING_HISTORY_SIZE = 5
        private const val LOOK_AHEAD_WAYPOINT_COUNT = 4
        private const val LOOK_AHEAD_MAX_DISTANCE = 8.0f
        private const val MOVEMENT_HEADING_STALENESS_MS = 3000L
        private const val MIN_MOVEMENT_FOR_HEADING = 0.3f
        private const val MIN_MOVEMENT_FOR_VELOCITY = 0.1f
    }

    private val _state = MutableStateFlow(NavigationState())
    val state: StateFlow<NavigationState> = _state.asStateFlow()

    val isNavigating: Boolean
        get() = _state.value.isNavigating

    // Private path/position state
    private var currentPath: List<Int> = emptyList()
    private var currentWaypointIndex = 0
    private var lastUserPosition: NavPosition? = null
    private var lastUserRotation: Rotation? = null
    private var previousUserPosition: NavPosition? = null
    private var movementHeading: Float? = null
    private var lastMovementTime: Long = 0L
    private val headingHistory = mutableListOf<Float>()
    private var userVelocityX = 0f
    private var userVelocityZ = 0f
    private var lastPositionUpdateTime: Long? = null
    private var lastInstructionAngle: Float? = null

    private var firstInstructionJob: Job? = null
    private var arrivalJob: Job? = null

    /** Returns true if navigation actually started (a route was found). */
    fun startNavigation(poiId: Int): Boolean {
        val poi = dataService.getPOI(poiId) ?: run { Log.e(TAG, "POI $poiId not found"); return false }
        val userPosition = lastUserPosition ?: run { Log.e(TAG, "No user position"); return false }
        val nearestWaypoint =
            dataService.findNearestWaypoint(userPosition) ?: run { Log.e(TAG, "No nearby waypoint"); return false }
        val path = dataService.getPath(nearestWaypoint.id, poiId) ?: run {
            Log.e(TAG, "No path from waypoint ${nearestWaypoint.id} to POI $poiId")
            return false
        }

        currentPath = path.waypointPath
        currentWaypointIndex = 0
        movementHeading = null
        previousUserPosition = lastUserPosition
        lastMovementTime = 0L
        headingHistory.clear()
        userVelocityX = 0f
        userVelocityZ = 0f
        lastPositionUpdateTime = System.currentTimeMillis()
        lastInstructionAngle = null

        _state.update {
            it.copy(
                isNavigating = true,
                destination = poi,
                currentInstruction = null,
                remainingDistance = path.totalDistance,
                currentWaypointIndex = 0,
                totalWaypoints = currentPath.size,
                navigationPath = currentPath,
            )
        }

        audioService.resetCooldowns()
        audioService.playInstruction(NavigationInstruction.NAVIGATION_STARTED, force = true)
        Log.i(TAG, "Navigation started to ${poi.name}, ${"%.1f".format(path.totalDistance)}m")

        firstInstructionJob?.cancel()
        firstInstructionJob = scope.launch {
            delay(1500)
            if (isNavigating) giveNavigationInstruction(null)
        }
        return true
    }

    fun stopNavigation() {
        firstInstructionJob?.cancel()
        arrivalJob?.cancel()
        currentPath = emptyList()
        currentWaypointIndex = 0
        movementHeading = null
        previousUserPosition = null
        lastMovementTime = 0L
        headingHistory.clear()
        userVelocityX = 0f
        userVelocityZ = 0f
        lastPositionUpdateTime = null
        lastInstructionAngle = null
        audioService.stopAudio()
        _state.update {
            it.copy(
                isNavigating = false,
                destination = null,
                currentInstruction = null,
                remainingDistance = 0f,
                currentWaypointIndex = 0,
                totalWaypoints = 0,
                navigationPath = null,
            )
        }
        Log.i(TAG, "Navigation stopped")
    }

    /** Called on each localization success. */
    fun updatePosition(position: Position, rotation: Rotation) {
        val navPosition = NavPosition.from(position)
        val now = System.currentTimeMillis()

        previousUserPosition?.let { prevPos ->
            val dx = navPosition.x - prevPos.x
            val dz = navPosition.z - prevPos.z
            val moveDist = sqrt(dx * dx + dz * dz)

            if (moveDist > MIN_MOVEMENT_FOR_VELOCITY) {
                lastPositionUpdateTime?.let { lastTime ->
                    val timeDelta = (now - lastTime) / 1000f
                    if (timeDelta > 0.01f) {
                        userVelocityX = dx / timeDelta
                        userVelocityZ = dz / timeDelta
                    }
                }
            }

            if (moveDist > MIN_MOVEMENT_FOR_HEADING) {
                val newHeading = atan2(dz, dx) * 180f / Math.PI.toFloat()
                addHeadingToHistory(newHeading)
                movementHeading = smoothedHeading()
                lastMovementTime = now
            }
        }

        if (now - lastMovementTime > MOVEMENT_HEADING_STALENESS_MS) {
            movementHeading = null
            userVelocityX = 0f
            userVelocityZ = 0f
        }

        previousUserPosition = lastUserPosition
        lastUserPosition = navPosition
        lastUserRotation = rotation
        lastPositionUpdateTime = now

        _state.update { it.copy(userPosition = navPosition, userRotation = rotation) }

        if (!isNavigating) return

        val predicted = predictPosition(navPosition)

        _state.value.destination?.let {
            _state.update { s -> s.copy(remainingDistance = predicted.distance2D(it.position)) }
        }

        if (checkArrival()) return

        updatePathProgress(predicted)
        checkOffPath()
        giveNavigationInstruction(predicted)
    }

    private fun addHeadingToHistory(heading: Float) {
        headingHistory.add(heading)
        if (headingHistory.size > HEADING_HISTORY_SIZE) headingHistory.removeAt(0)
    }

    private fun smoothedHeading(): Float {
        if (headingHistory.isEmpty()) return 0f
        var sumSin = 0f
        var sumCos = 0f
        for (h in headingHistory) {
            val r = h * Math.PI.toFloat() / 180f
            sumSin += sin(r)
            sumCos += cos(r)
        }
        return atan2(sumSin, sumCos) * 180f / Math.PI.toFloat()
    }

    private fun predictPosition(position: NavPosition): NavPosition {
        val latency = 0.1f
        return NavPosition(
            position.x + userVelocityX * latency,
            position.y,
            position.z + userVelocityZ * latency,
        )
    }

    private fun checkArrival(): Boolean {
        val destination = _state.value.destination ?: return false
        val userPosition = lastUserPosition ?: return false
        val distance = userPosition.distance2D(destination.position)
        if (distance <= destination.arrivalRadius) {
            audioService.playInstruction(NavigationInstruction.DESTINATION_REACHED, force = true)
            _state.update {
                it.copy(isNavigating = false, currentInstruction = NavigationInstruction.DESTINATION_REACHED)
            }
            Log.i(TAG, "Arrived at ${destination.name}")
            arrivalJob?.cancel()
            arrivalJob = scope.launch {
                delay(3000)
                stopNavigation()
            }
            return true
        }
        return false
    }

    private fun updatePathProgress(predicted: NavPosition) {
        val userPos = predicted
        if (currentPath.isEmpty()) return
        while (currentWaypointIndex < currentPath.size - 1) {
            val currentWp = dataService.getWaypoint(currentPath[currentWaypointIndex]) ?: break
            val nextWp = dataService.getWaypoint(currentPath[currentWaypointIndex + 1]) ?: break
            val distanceToWaypoint = userPos.distance2D(currentWp.position)
            val withinReach = distanceToWaypoint <= WAYPOINT_REACH_DISTANCE
            val passed = hasPassedWaypoint(userPos, currentWp.position, nextWp.position)
            if (withinReach || passed) {
                currentWaypointIndex++
                _state.update { it.copy(currentWaypointIndex = currentWaypointIndex) }
            } else {
                break
            }
        }
    }

    private fun hasPassedWaypoint(userPos: NavPosition, waypoint: NavPosition, nextWaypoint: NavPosition): Boolean {
        val pathDirX = nextWaypoint.x - waypoint.x
        val pathDirZ = nextWaypoint.z - waypoint.z
        val toUserX = userPos.x - waypoint.x
        val toUserZ = userPos.z - waypoint.z
        val dotProduct = pathDirX * toUserX + pathDirZ * toUserZ
        val pathLength = sqrt(pathDirX * pathDirX + pathDirZ * pathDirZ)
        if (pathLength <= 0.001f) return false
        val crossProduct = abs(pathDirX * toUserZ - pathDirZ * toUserX)
        val perpendicularDistance = crossProduct / pathLength
        // Only count as passed when user is actually past the waypoint along the segment
        // (projection beyond a small slack) AND close enough laterally — prevents the covered
        // portion of the route from jumping far ahead of the user.
        val projectionAlongSegment = dotProduct / pathLength
        return projectionAlongSegment > 0.5f && perpendicularDistance < 1.5f
    }

    private fun checkOffPath() {
        val userPosition = lastUserPosition ?: return
        val destination = _state.value.destination ?: return
        if (currentWaypointIndex >= currentPath.size) return
        val currentWp = dataService.getWaypoint(currentPath[currentWaypointIndex]) ?: return
        val distance = userPosition.distance2D(currentWp.position)
        if (distance > MAX_OFF_PATH_DISTANCE) {
            Log.w(TAG, "Off-path (${"%.1f".format(distance)}m), recalculating")
            audioService.playInstruction(NavigationInstruction.RECALCULATING, force = true)
            val nearest = dataService.findNearestWaypoint(userPosition) ?: return
            val newPath = dataService.getPath(nearest.id, destination.id) ?: return
            currentPath = newPath.waypointPath
            currentWaypointIndex = 0
            _state.update {
                it.copy(navigationPath = currentPath, currentWaypointIndex = 0, totalWaypoints = currentPath.size)
            }
        }
    }

    private fun giveNavigationInstruction(predicted: NavPosition?) {
        if (!isNavigating) return
        val userRotation = lastUserRotation ?: return
        val userPos = predicted ?: lastUserPosition ?: return

        val targetPosition: NavPosition =
            if (currentWaypointIndex < currentPath.size) {
                calculateLookAheadTarget(userPos)
            } else {
                _state.value.destination?.position ?: return
            }

        val angle = calculateAngleToTarget(userPos, userRotation, targetPosition)
        val instruction = determineInstructionWithHysteresis(angle)

        if (instruction != _state.value.currentInstruction) {
            _state.update { it.copy(currentInstruction = instruction) }
            lastInstructionAngle = angle
        }
        audioService.playInstruction(instruction)
    }

    private fun calculateLookAheadTarget(userPos: NavPosition): NavPosition {
        if (currentWaypointIndex >= currentPath.size) {
            return _state.value.destination?.position ?: userPos
        }
        val waypoints = mutableListOf<NavPosition>()
        var cumulativeDistance = 0f
        var prevPos = userPos
        val startIdx = currentWaypointIndex
        val endIdx = minOf(currentPath.size, startIdx + LOOK_AHEAD_WAYPOINT_COUNT)
        for (i in startIdx until endIdx) {
            val wp = dataService.getWaypoint(currentPath[i]) ?: continue
            cumulativeDistance += prevPos.distance2D(wp.position)
            if (cumulativeDistance > LOOK_AHEAD_MAX_DISTANCE && waypoints.isNotEmpty()) break
            waypoints.add(wp.position)
            prevPos = wp.position
        }
        if (endIdx >= currentPath.size - 1) {
            _state.value.destination?.let { waypoints.add(it.position) }
        }
        if (waypoints.size < 2) return waypoints.firstOrNull() ?: (_state.value.destination?.position ?: userPos)

        var weightedX = 0f
        var weightedZ = 0f
        var totalWeight = 0f
        waypoints.forEachIndexed { i, wpPos ->
            val weight = 1.0f / (i + 1)
            val dx = wpPos.x - userPos.x
            val dz = wpPos.z - userPos.z
            val dist = sqrt(dx * dx + dz * dz)
            if (dist > 0.001f) {
                weightedX += (dx / dist) * weight
                weightedZ += (dz / dist) * weight
                totalWeight += weight
            }
        }
        if (totalWeight <= 0f) return waypoints.first()

        val avgDirX = weightedX / totalWeight
        val avgDirZ = weightedZ / totalWeight
        val immediateDist = userPos.distance2D(waypoints[0])
        val projectionDist = maxOf(immediateDist, 2.0f)
        val dirMag = sqrt(avgDirX * avgDirX + avgDirZ * avgDirZ)
        if (dirMag <= 0.001f) return waypoints[0]
        return NavPosition(
            userPos.x + (avgDirX / dirMag) * projectionDist,
            userPos.y,
            userPos.z + (avgDirZ / dirMag) * projectionDist,
        )
    }

    private fun determineInstructionWithHysteresis(angle: Float): NavigationInstruction {
        val newInstruction = determineInstruction(angle)
        val prevAngle = lastInstructionAngle
        val prevInstruction = _state.value.currentInstruction
        if (prevAngle == null || prevInstruction == null) return newInstruction
        if (newInstruction != prevInstruction) {
            val angleDelta = abs(abs(angle) - abs(prevAngle))
            if (angleDelta < HYSTERESIS_BUFFER) return prevInstruction
        }
        return newInstruction
    }

    private fun calculateAngleToTarget(
        userPosition: NavPosition,
        userRotation: Rotation,
        targetPosition: NavPosition,
    ): Float {
        val dirX = targetPosition.x - userPosition.x
        val dirZ = targetPosition.z - userPosition.z
        val dirMag = sqrt(dirX * dirX + dirZ * dirZ)
        if (dirMag <= 0.001f) return 0f
        val normDirX = dirX / dirMag
        val normDirZ = dirZ / dirMag
        val targetAngle = atan2(normDirZ, normDirX) * 180f / Math.PI.toFloat()

        val userHeading: Float =
            movementHeading ?: run {
                val forwardX = 2.0f * (userRotation.x * userRotation.z + userRotation.w * userRotation.y)
                val forwardZ = 1.0f - 2.0f * (userRotation.x * userRotation.x + userRotation.y * userRotation.y)
                atan2(forwardZ, forwardX) * 180f / Math.PI.toFloat()
            }

        var angleDiff = targetAngle - userHeading
        while (angleDiff > 180) angleDiff -= 360
        while (angleDiff < -180) angleDiff += 360
        return angleDiff
    }

    /** Positive angle = target to the LEFT (turn left); negative = RIGHT. */
    private fun determineInstruction(angle: Float): NavigationInstruction {
        val absAngle = abs(angle)
        return when {
            absAngle < FORWARD_ANGLE_THRESHOLD -> NavigationInstruction.MOVE_FORWARD
            absAngle < SLIGHT_TURN_THRESHOLD ->
                if (angle > 0) NavigationInstruction.SLIGHT_LEFT else NavigationInstruction.SLIGHT_RIGHT
            absAngle >= TURN_AROUND_THRESHOLD -> NavigationInstruction.TURN_AROUND
            else -> if (angle > 0) NavigationInstruction.TURN_LEFT else NavigationInstruction.TURN_RIGHT
        }
    }
}
