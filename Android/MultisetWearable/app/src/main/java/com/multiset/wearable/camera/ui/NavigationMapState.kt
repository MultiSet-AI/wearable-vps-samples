/*
Copyright (c) 2026 MultiSet AI. All rights reserved.
Licensed under the MultiSet License. You may not use this file except in compliance with the License. and you can't re-distribute this file without a prior notice
For license details, visit www.multiset.ai.
Redistribution in source or binary forms must retain this notice.
*/

// Map view state (zoom / pan / recenter), ported from the iOS NavigationMapViewModel's
// view-state methods. Held by remember{} and shared between the embedded and full-screen maps.

package com.multiset.wearable.vps.ui

import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableFloatStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.geometry.Size
import com.multiset.wearable.vps.navigation.MapBounds
import com.multiset.wearable.vps.navigation.MapCoordinateTransformer
import com.multiset.wearable.vps.navigation.NavPosition

class MapViewState {
    companion object {
        const val MIN_ZOOM = 0.3f
        const val MAX_ZOOM = 10.0f
    }

    var zoom by mutableFloatStateOf(1f)
        private set
    var pan by mutableStateOf(Offset.Zero)
    var isRecenterActive by mutableStateOf(false)
        private set
    var canvasSize by mutableStateOf(Size.Zero)

    fun applyZoom(factor: Float) {
        zoom = (zoom * factor).coerceIn(MIN_ZOOM, MAX_ZOOM)
    }

    fun reset() {
        isRecenterActive = false
        zoom = 1f
        pan = Offset.Zero
    }

    /** User started panning manually — leave recenter mode. */
    fun deactivateRecenter() {
        isRecenterActive = false
    }

    fun toggleRecenter(userPosition: NavPosition?, bounds: MapBounds?) {
        if (isRecenterActive) {
            isRecenterActive = false
        } else {
            isRecenterActive = true
            centerOnUser(userPosition, bounds)
        }
    }

    /** Compute the pan offset so the user lands at the canvas centre (center-anchored zoom). */
    fun centerOnUser(userPosition: NavPosition?, bounds: MapBounds?) {
        if (userPosition == null || bounds == null || canvasSize == Size.Zero) {
            pan = Offset.Zero
            return
        }
        val transformer = MapCoordinateTransformer(bounds, canvasSize, padding = 24f)
        val userScreen = transformer.toScreenPoint(userPosition)
        val center = Offset(canvasSize.width / 2f, canvasSize.height / 2f)
        pan = Offset(-(userScreen.x - center.x) * zoom, -(userScreen.y - center.y) * zoom)
    }
}

@Composable
fun rememberMapViewState(): MapViewState = remember { MapViewState() }
