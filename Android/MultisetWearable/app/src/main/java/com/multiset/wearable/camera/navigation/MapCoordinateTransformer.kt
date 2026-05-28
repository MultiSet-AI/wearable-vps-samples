/*
Copyright (c) 2026 MultiSet AI. All rights reserved.
Licensed under the MultiSet License. You may not use this file except in compliance with the License. and you can't re-distribute this file without a prior notice
For license details, visit www.multiset.ai.
Redistribution in source or binary forms must retain this notice.
*/

// Transforms navigation map coordinates (NavPosition X-Z plane) to Compose canvas offsets
// for the 2D map. Ported from the iOS MapCoordinateTransformer.swift.
//
// Mapping: Map +X (right) -> Screen +X (right); Map +Z (forward) -> Screen -Y (up), so
// forward points up on the map.

package com.multiset.wearable.vps.navigation

import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.geometry.Size
import com.multiset.wearable.vps.localization.Rotation
import kotlin.math.atan2
import kotlin.math.min

class MapCoordinateTransformer(
    private val bounds: MapBounds,
    private val canvasSize: Size,
    private val padding: Float = 20f,
) {
    private val mapWidth: Float = bounds.max.x - bounds.min.x
    private val mapHeight: Float = bounds.max.z - bounds.min.z
    val scale: Float
    private val offset: Offset

    init {
        val availableWidth = canvasSize.width - padding * 2
        val availableHeight = canvasSize.height - padding * 2
        val scaleX = if (mapWidth > 0f) availableWidth / mapWidth else 1f
        val scaleY = if (mapHeight > 0f) availableHeight / mapHeight else 1f
        scale = min(scaleX, scaleY)
        val scaledW = mapWidth * scale
        val scaledH = mapHeight * scale
        offset = Offset((canvasSize.width - scaledW) / 2f, (canvasSize.height - scaledH) / 2f)
    }

    /** Transform a NavPosition (X-Z) to a screen point. */
    fun toScreenPoint(position: NavPosition): Offset {
        val normalizedX = position.x - bounds.min.x
        val normalizedZ = position.z - bounds.min.z
        val invertedZ = mapHeight - normalizedZ // +Z points up
        return Offset(offset.x + normalizedX * scale, offset.y + invertedZ * scale)
    }

    fun toScreenDistance(worldDistance: Float): Float = worldDistance * scale

    /**
     * Heading for the user arrow, in degrees clockwise from "up" (screen -Y), derived from
     * the quaternion's forward vector. 0° = pointing up on the map.
     */
    fun headingDegrees(rotation: Rotation): Float {
        val forwardX = 2.0f * (rotation.x * rotation.z + rotation.w * rotation.y)
        val forwardZ = 1.0f - 2.0f * (rotation.x * rotation.x + rotation.y * rotation.y)
        val radians = atan2(forwardX, forwardZ)
        return Math.toDegrees(radians.toDouble()).toFloat()
    }
}
