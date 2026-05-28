/*
Copyright (c) 2026 MultiSet AI. All rights reserved.
Licensed under the MultiSet License. You may not use this file except in compliance with the License. and you can't re-distribute this file without a prior notice
For license details, visit www.multiset.ai.
Redistribution in source or binary forms must retain this notice.
*/

// Navigation data model — ported from the iOS NavigationModels.swift. Parsed from
// `{mapCode}_navigation_data.json` (POIs, waypoint graph, precomputed paths, bounds).
// Coordinates are left-handed (X-Z ground plane), matching localization isRightHanded=false.

package com.multiset.wearable.vps.navigation

import com.multiset.wearable.vps.localization.Position
import kotlin.math.sqrt
import org.json.JSONObject

/** 3D position used in navigation data. */
data class NavPosition(val x: Float, val y: Float, val z: Float) {
    fun distance(to: NavPosition): Float {
        val dx = to.x - x
        val dy = to.y - y
        val dz = to.z - z
        return sqrt(dx * dx + dy * dy + dz * dz)
    }

    /** 2D distance, ignoring height (Y). */
    fun distance2D(to: NavPosition): Float {
        val dx = to.x - x
        val dz = to.z - z
        return sqrt(dx * dx + dz * dz)
    }

    companion object {
        fun from(position: Position) = NavPosition(position.x, position.y, position.z)

        fun fromJson(json: JSONObject?): NavPosition {
            if (json == null) return NavPosition(0f, 0f, 0f)
            return NavPosition(
                json.optDouble("x", 0.0).toFloat(),
                json.optDouble("y", 0.0).toFloat(),
                json.optDouble("z", 0.0).toFloat(),
            )
        }
    }
}

/** Map boundary information. */
data class MapBounds(
    val center: NavPosition,
    val size: NavPosition,
    val min: NavPosition,
    val max: NavPosition,
)

/** Point of Interest for navigation. */
data class NavigationPOI(
    val id: Int,
    val name: String,
    val description: String,
    val type: String,
    val position: NavPosition,
    val worldPosition: NavPosition,
    val nearestWaypointId: Int,
    val arrivalRadius: Float,
)

/** Individual waypoint in the navigation graph. */
data class WaypointData(
    val id: Int,
    val position: NavPosition,
    val connectedWaypoints: List<Int>,
)

/** Precomputed navigation path from a waypoint to a POI. */
data class PrecomputedPath(
    val fromWaypointId: Int,
    val toPoiId: Int,
    val waypointPath: List<Int>,
    val totalDistance: Float,
)

/** Complete navigation data including POIs, waypoints, and precomputed paths. */
data class NavigationData(
    val mapCode: String?,
    val bounds: MapBounds?,
    val pois: List<NavigationPOI>,
    val waypoints: List<WaypointData>,
    val paths: List<PrecomputedPath>,
) {
    companion object {
        fun fromJson(root: JSONObject): NavigationData {
            val boundsJson = root.optJSONObject("bounds")
            val bounds =
                boundsJson?.let {
                    MapBounds(
                        center = NavPosition.fromJson(it.optJSONObject("center")),
                        size = NavPosition.fromJson(it.optJSONObject("size")),
                        min = NavPosition.fromJson(it.optJSONObject("min")),
                        max = NavPosition.fromJson(it.optJSONObject("max")),
                    )
                }

            val pois = mutableListOf<NavigationPOI>()
            root.optJSONArray("pois")?.let { arr ->
                for (i in 0 until arr.length()) {
                    val o = arr.getJSONObject(i)
                    pois.add(
                        NavigationPOI(
                            id = o.optInt("id"),
                            name = o.optString("name"),
                            description = o.optString("description"),
                            type = o.optString("type"),
                            position = NavPosition.fromJson(o.optJSONObject("position")),
                            worldPosition = NavPosition.fromJson(o.optJSONObject("worldPosition")),
                            nearestWaypointId = o.optInt("nearestWaypointId"),
                            arrivalRadius = o.optDouble("arrivalRadius", 1.0).toFloat(),
                        )
                    )
                }
            }

            val waypoints = mutableListOf<WaypointData>()
            root.optJSONArray("waypoints")?.let { arr ->
                for (i in 0 until arr.length()) {
                    val o = arr.getJSONObject(i)
                    val connected = mutableListOf<Int>()
                    o.optJSONArray("connectedWaypoints")?.let { c ->
                        for (j in 0 until c.length()) connected.add(c.getInt(j))
                    }
                    waypoints.add(
                        WaypointData(
                            id = o.optInt("id"),
                            position = NavPosition.fromJson(o.optJSONObject("position")),
                            connectedWaypoints = connected,
                        )
                    )
                }
            }

            val paths = mutableListOf<PrecomputedPath>()
            root.optJSONArray("paths")?.let { arr ->
                for (i in 0 until arr.length()) {
                    val o = arr.getJSONObject(i)
                    val wpPath = mutableListOf<Int>()
                    o.optJSONArray("waypointPath")?.let { p ->
                        for (j in 0 until p.length()) wpPath.add(p.getInt(j))
                    }
                    paths.add(
                        PrecomputedPath(
                            fromWaypointId = o.optInt("fromWaypointId"),
                            toPoiId = o.optInt("toPoiId"),
                            waypointPath = wpPath,
                            totalDistance = o.optDouble("totalDistance", 0.0).toFloat(),
                        )
                    )
                }
            }

            return NavigationData(
                mapCode = root.optString("mapCode", null),
                bounds = bounds,
                pois = pois,
                waypoints = waypoints,
                paths = paths,
            )
        }
    }
}
