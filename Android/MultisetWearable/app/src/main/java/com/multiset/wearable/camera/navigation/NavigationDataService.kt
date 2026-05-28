/*
Copyright (c) 2026 MultiSet AI. All rights reserved.
Licensed under the MultiSet License. You may not use this file except in compliance with the License. and you can't re-distribute this file without a prior notice
For license details, visit www.multiset.ai.
Redistribution in source or binary forms must retain this notice.
*/

// Loads and manages navigation data, ported from the iOS NavigationDataService.swift.
// Reads `assets/navigation/{mapCode}_navigation_data.json`, builds lookups, and provides
// A* pathfinding with a precomputed-path fast path.

package com.multiset.wearable.vps.navigation

import android.content.Context
import android.util.Log
import com.multiset.wearable.vps.localization.SDKConfig
import org.json.JSONObject

class NavigationDataService(private val context: Context) {

    companion object {
        private const val TAG = "NavigationDataService"
    }

    private var navigationData: NavigationData? = null
    private val waypointLookup = mutableMapOf<Int, WaypointData>()
    private val pathLookup = mutableMapOf<String, PrecomputedPath>()
    private val poiLookup = mutableMapOf<Int, NavigationPOI>()
    private var hasAttemptedLoad = false
    /** The map code the currently-loaded data was loaded for (to detect runtime changes). */
    private var loadedCode: String? = null

    val isDataLoaded: Boolean
        get() {
            ensureDataLoaded()
            return navigationData != null
        }

    val bounds: MapBounds?
        get() {
            ensureDataLoaded()
            return navigationData?.bounds
        }

    fun ensureDataLoaded() {
        // Reload when first accessed, or whenever the configured map code has changed at
        // runtime (e.g. the user entered a different MAP_CODE in settings).
        val codeToUse = SDKConfig.MAP_CODE.ifEmpty { SDKConfig.MAP_SET_CODE }.trim()
        if (!hasAttemptedLoad || codeToUse != loadedCode) {
            hasAttemptedLoad = true
            loadNavigationData(codeToUse)
        }
    }

    fun getPOIs(): List<NavigationPOI> {
        ensureDataLoaded()
        return navigationData?.pois ?: emptyList()
    }

    fun getPOI(id: Int): NavigationPOI? {
        ensureDataLoaded()
        return poiLookup[id]
    }

    fun getWaypoint(id: Int): WaypointData? {
        ensureDataLoaded()
        return waypointLookup[id]
    }

    fun getAllWaypoints(): List<WaypointData> {
        ensureDataLoaded()
        return navigationData?.waypoints ?: emptyList()
    }

    /** Reload (e.g. when the map code changes). */
    fun reload() {
        waypointLookup.clear()
        pathLookup.clear()
        poiLookup.clear()
        navigationData = null
        hasAttemptedLoad = false
        ensureDataLoaded()
    }

    /** Find the nearest waypoint to a position (2D). */
    fun findNearestWaypoint(to: NavPosition): WaypointData? {
        ensureDataLoaded()
        val waypoints = navigationData?.waypoints ?: return null
        var nearest: WaypointData? = null
        var nearestDistance = Float.MAX_VALUE
        for (wp in waypoints) {
            val d = to.distance2D(wp.position)
            if (d < nearestDistance) {
                nearestDistance = d
                nearest = wp
            }
        }
        return nearest
    }

    /** Get a precomputed path, falling back to runtime A* if none exists. */
    fun getPath(fromWaypointId: Int, toPoiId: Int): PrecomputedPath? {
        ensureDataLoaded()
        pathLookup["${fromWaypointId}_$toPoiId"]?.let { return it }

        val targetPOI = poiLookup[toPoiId] ?: return null
        val targetWaypointId = targetPOI.nearestWaypointId

        val waypointPath = findPathAStar(fromWaypointId, targetWaypointId) ?: return null

        var totalDistance = 0f
        for (i in 0 until waypointPath.size - 1) {
            val wp1 = waypointLookup[waypointPath[i]]
            val wp2 = waypointLookup[waypointPath[i + 1]]
            if (wp1 != null && wp2 != null) totalDistance += wp1.position.distance2D(wp2.position)
        }
        waypointLookup[waypointPath.lastOrNull() ?: targetWaypointId]?.let {
            totalDistance += it.position.distance2D(targetPOI.position)
        }

        return PrecomputedPath(fromWaypointId, toPoiId, waypointPath, totalDistance)
    }

    /** A* pathfinding between two waypoints. */
    private fun findPathAStar(startId: Int, goalId: Int): List<Int>? {
        val startWp = waypointLookup[startId] ?: return null
        val goalWp = waypointLookup[goalId] ?: return null

        val openSet = mutableListOf(0f to startId)
        val cameFrom = mutableMapOf<Int, Int>()
        val gScore = mutableMapOf(startId to 0f)
        val closedSet = mutableSetOf<Int>()
        // seed fScore (not strictly needed beyond openSet ordering)
        @Suppress("UNUSED_VARIABLE")
        val initialF = startWp.position.distance2D(goalWp.position)

        while (openSet.isNotEmpty()) {
            openSet.sortBy { it.first }
            val (_, currentId) = openSet.removeAt(0)

            if (currentId == goalId) {
                val path = mutableListOf(currentId)
                var current = currentId
                while (cameFrom.containsKey(current)) {
                    current = cameFrom[current]!!
                    path.add(0, current)
                }
                return path
            }

            if (closedSet.contains(currentId)) continue
            closedSet.add(currentId)

            val currentWp = waypointLookup[currentId] ?: continue
            for (neighborId in currentWp.connectedWaypoints) {
                if (closedSet.contains(neighborId)) continue
                val neighborWp = waypointLookup[neighborId] ?: continue
                val tentativeG =
                    (gScore[currentId] ?: Float.MAX_VALUE) +
                        currentWp.position.distance2D(neighborWp.position)
                if (tentativeG < (gScore[neighborId] ?: Float.MAX_VALUE)) {
                    cameFrom[neighborId] = currentId
                    gScore[neighborId] = tentativeG
                    val f = tentativeG + neighborWp.position.distance2D(goalWp.position)
                    openSet.add(f to neighborId)
                }
            }
        }
        Log.w(TAG, "A* failed to find path from $startId to $goalId")
        return null
    }

    private fun loadNavigationData(codeToUse: String) {
        // Reset any previously-loaded data before (re)loading.
        loadedCode = codeToUse
        waypointLookup.clear()
        pathLookup.clear()
        poiLookup.clear()
        navigationData = null

        if (codeToUse.isEmpty()) {
            Log.w(TAG, "No mapCode or mapSetCode configured")
            return
        }
        val fileName = "navigation/${codeToUse}_navigation_data.json"
        try {
            val text = context.assets.open(fileName).bufferedReader().use { it.readText() }
            val data = NavigationData.fromJson(JSONObject(text))
            navigationData = data
            buildLookups(data)
            Log.i(
                TAG,
                "Loaded navigation data for '$codeToUse': ${data.pois.size} POIs, ${data.waypoints.size} waypoints, ${data.paths.size} paths",
            )
        } catch (e: Exception) {
            Log.e(TAG, "Failed to load navigation data '$fileName': ${e.message}")
        }
    }

    private fun buildLookups(data: NavigationData) {
        for (wp in data.waypoints) waypointLookup[wp.id] = wp
        for (path in data.paths) pathLookup["${path.fromWaypointId}_${path.toPoiId}"] = path
        for (poi in data.pois) poiLookup[poi.id] = poi
    }
}
