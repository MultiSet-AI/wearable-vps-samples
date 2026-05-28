/*
Copyright (c) 2026 MultiSet AI. All rights reserved.
Licensed under the MultiSet License. You may not use this file except in compliance with the License. and you can't re-distribute this file without a prior notice
For license details, visit www.multiset.ai.
Redistribution in source or binary forms must retain this notice.
*/

// 2D navigation map — ported from the iOS MapCanvasView.swift, drawn with a Compose Canvas:
// floor plane, waypoint graph, active route (covered/remaining + progress dots), POI markers,
// and the user position + heading arrow. InteractiveMap adds pinch-zoom and pan.

package com.multiset.wearable.vps.ui

import androidx.compose.animation.core.Animatable
import androidx.compose.animation.core.LinearEasing
import androidx.compose.animation.core.RepeatMode
import androidx.compose.animation.core.animateFloat
import androidx.compose.animation.core.infiniteRepeatable
import androidx.compose.animation.core.rememberInfiniteTransition
import androidx.compose.animation.core.tween
import androidx.compose.foundation.Canvas
import androidx.compose.foundation.background
import androidx.compose.foundation.gestures.detectTapGestures
import androidx.compose.foundation.gestures.detectTransformGestures
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.geometry.CornerRadius
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.geometry.Size
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.Path
import androidx.compose.ui.graphics.PathEffect
import androidx.compose.ui.graphics.drawscope.DrawScope
import androidx.compose.ui.graphics.drawscope.Stroke
import androidx.compose.ui.graphics.graphicsLayer
import androidx.compose.ui.input.pointer.pointerInput
import androidx.compose.ui.layout.layout
import androidx.compose.ui.layout.onSizeChanged
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.multiset.wearable.vps.localization.Rotation
import com.multiset.wearable.vps.navigation.MapBounds
import com.multiset.wearable.vps.navigation.MapCoordinateTransformer
import com.multiset.wearable.vps.navigation.NavPosition
import com.multiset.wearable.vps.navigation.NavigationPOI
import com.multiset.wearable.vps.navigation.WaypointData
import kotlin.math.atan2
import kotlin.math.cos
import kotlin.math.hypot
import kotlin.math.min
import kotlin.math.roundToInt
import kotlin.math.sin
import kotlinx.coroutines.launch

/** Snapshot of everything the map needs to render. */
data class MapRenderData(
    val bounds: MapBounds?,
    val waypoints: List<WaypointData>,
    val pois: List<com.multiset.wearable.vps.navigation.NavigationPOI>,
    val userPosition: NavPosition?,
    val userRotation: Rotation?,
    val activePath: List<Int>?,
    val destinationPoiId: Int?,
    val currentWaypointIndex: Int,
)

/**
 * Map with pinch-to-zoom (dampened, center-anchored), pan, tap-to-select POIs, and POI labels
 * when zoomed in — used both embedded and full-screen. Mirrors the iOS InteractiveMapView.
 */
@Composable
fun InteractiveMap(
    data: MapRenderData,
    mapState: MapViewState,
    modifier: Modifier = Modifier,
    showLabels: Boolean = true,
    onPoiTap: ((NavigationPOI) -> Unit)? = null,
) {
    // Smoothly animate the user marker (position + heading) between localization updates,
    // instead of jumping. Heading takes the shortest angular path.
    val animX = remember { Animatable(0f) }
    val animZ = remember { Animatable(0f) }
    val animHeading = remember { Animatable(0f) }
    var posInitialized by remember { mutableStateOf(false) }
    var headingInitialized by remember { mutableStateOf(false) }

    val target = data.userPosition
    val targetHeading = data.userRotation?.let { headingFromRotation(it) }

    LaunchedEffect(target?.x, target?.z) {
        val t = target ?: return@LaunchedEffect
        if (!posInitialized) {
            animX.snapTo(t.x); animZ.snapTo(t.z); posInitialized = true
        } else {
            launch { animX.animateTo(t.x, tween(380, easing = LinearEasing)) }
            launch { animZ.animateTo(t.z, tween(380, easing = LinearEasing)) }
        }
    }
    LaunchedEffect(targetHeading) {
        val th = targetHeading ?: return@LaunchedEffect
        if (!headingInitialized) {
            animHeading.snapTo(th); headingInitialized = true
        } else {
            var delta = (th - animHeading.value) % 360f
            if (delta > 180f) delta -= 360f
            if (delta < -180f) delta += 360f
            animHeading.animateTo(animHeading.value + delta, tween(260, easing = LinearEasing))
        }
    }

    val pulseTransition = rememberInfiniteTransition(label = "userPulse")
    val pulse by
        pulseTransition.animateFloat(
            initialValue = 0f,
            targetValue = 1f,
            animationSpec = infiniteRepeatable(tween(1500, easing = LinearEasing), RepeatMode.Restart),
            label = "pulse",
        )

    val renderData =
        if (target != null) data.copy(userPosition = NavPosition(animX.value, target.y, animZ.value)) else data
    val headingOverride = if (targetHeading != null) animHeading.value else null

    Box(
        modifier =
            modifier
                .clip(RoundedCornerShape(12.dp))
                .background(AppColor.DarkBackgroundEnd)
                .onSizeChanged { mapState.canvasSize = Size(it.width.toFloat(), it.height.toFloat()) }
                .pointerInput(Unit) {
                    detectTransformGestures { _, pan, gestureZoom, _ ->
                        // Dampen pinch sensitivity like iOS (0.4).
                        val dampened = 1f + (gestureZoom - 1f) * 0.4f
                        mapState.applyZoom(dampened)
                        if (mapState.isRecenterActive) mapState.deactivateRecenter()
                        mapState.pan += pan
                    }
                }
                .pointerInput(onPoiTap, data.bounds, data.pois) {
                    if (onPoiTap != null) {
                        detectTapGestures { tap -> hitTestPoi(tap, data, mapState)?.let(onPoiTap) }
                    }
                }
    ) {
        NavigationMapCanvas(
            data = renderData,
            zoom = mapState.zoom,
            userHeadingOverrideDeg = headingOverride,
            pulse = pulse,
            modifier =
                Modifier.fillMaxSize().graphicsLayer {
                    scaleX = mapState.zoom
                    scaleY = mapState.zoom
                    translationX = mapState.pan.x
                    translationY = mapState.pan.y
                },
        )
        if (showLabels) {
            PoiLabels(data, mapState)
        }
    }
}

/** Reverse the pan + center-anchored scale and hit-test POIs (tapRadius 40 / zoom, like iOS). */
private fun hitTestPoi(tap: Offset, data: MapRenderData, mapState: MapViewState): NavigationPOI? {
    val bounds = data.bounds ?: return null
    val size = mapState.canvasSize
    if (size == Size.Zero) return null
    val transformer = MapCoordinateTransformer(bounds, size, padding = 24f)
    val center = Offset(size.width / 2f, size.height / 2f)
    var adj = Offset(tap.x - mapState.pan.x, tap.y - mapState.pan.y)
    adj = Offset(center.x + (adj.x - center.x) / mapState.zoom, center.y + (adj.y - center.y) / mapState.zoom)
    val tapRadius = 40f / mapState.zoom
    return data.pois.firstOrNull { hypot(adj.x - transformer.toScreenPoint(it.position).x, adj.y - transformer.toScreenPoint(it.position).y) <= tapRadius }
}

@Composable
private fun PoiLabels(data: MapRenderData, mapState: MapViewState) {
    val bounds = data.bounds ?: return
    val size = mapState.canvasSize
    if (size == Size.Zero) return
    val transformer = MapCoordinateTransformer(bounds, size, padding = 24f)
    val center = Offset(size.width / 2f, size.height / 2f)
    Box(modifier = Modifier.fillMaxSize()) {
        for (poi in data.pois) {
            val base = transformer.toScreenPoint(poi.position)
            // Match the canvas's center-anchored zoom + pan, then sit the label above the dot.
            val sx = center.x + (base.x - center.x) * mapState.zoom + mapState.pan.x
            val dotY = center.y + (base.y - center.y) * mapState.zoom + mapState.pan.y
            val isDest = data.destinationPoiId == poi.id
            Text(
                text = poi.name,
                fontSize = 10.sp,
                fontWeight = FontWeight.Medium,
                color = if (isDest) AppColor.AccentGreen else AppColor.TextPrimary,
                modifier =
                    Modifier
                        // Center the label horizontally on the POI and place it just above the marker.
                        .layout { measurable, constraints ->
                            val placeable = measurable.measure(constraints)
                            layout(placeable.width, placeable.height) {
                                placeable.place(
                                    (sx - placeable.width / 2f).roundToInt(),
                                    (dotY - 22f - placeable.height).roundToInt(),
                                )
                            }
                        }
                        .clip(RoundedCornerShape(4.dp))
                        .background(AppColor.CardBackground.copy(alpha = 0.9f))
                        .padding(horizontal = 6.dp, vertical = 2.dp),
            )
        }
    }
}

@Composable
fun NavigationMapCanvas(
    data: MapRenderData,
    zoom: Float,
    modifier: Modifier = Modifier,
    userHeadingOverrideDeg: Float? = null,
    pulse: Float = 0f,
) {
    val bounds = data.bounds
    Canvas(modifier = modifier) {
        if (bounds == null) return@Canvas
        val transformer = MapCoordinateTransformer(bounds, Size(size.width, size.height), padding = 24f)
        // Keep marker sizes roughly constant on screen as the layer scales (matches iOS inverseZoom).
        val inv = min(1f / zoom.coerceAtLeast(0.5f), 1.5f)

        drawFloorPlane(data.waypoints, transformer)
        drawConnections(data.waypoints, transformer)
        drawActivePath(data, transformer)
        drawWaypoints(data.waypoints, transformer, inv)
        drawPois(data, transformer, inv)
        drawUserMarker(data, transformer, inv, userHeadingOverrideDeg, pulse)
    }
}

private fun DrawScope.drawFloorPlane(waypoints: List<WaypointData>, t: MapCoordinateTransformer) {
    if (waypoints.isEmpty()) return
    var minX = Float.MAX_VALUE
    var maxX = -Float.MAX_VALUE
    var minY = Float.MAX_VALUE
    var maxY = -Float.MAX_VALUE
    for (wp in waypoints) {
        val p = t.toScreenPoint(wp.position)
        minX = min(minX, p.x); maxX = maxOf(maxX, p.x)
        minY = min(minY, p.y); maxY = maxOf(maxY, p.y)
    }
    val pad = 16f
    minX -= pad; maxX += pad; minY -= pad; maxY += pad
    drawRoundRect(
        color = floorGrey(0.09f),
        topLeft = Offset(minX, minY),
        size = Size(maxX - minX, maxY - minY),
        cornerRadius = CornerRadius(12f, 12f),
    )
    drawRoundRect(
        color = Color.White.copy(alpha = 0.06f),
        topLeft = Offset(minX, minY),
        size = Size(maxX - minX, maxY - minY),
        cornerRadius = CornerRadius(12f, 12f),
        style = Stroke(width = 1f),
    )
}

private fun DrawScope.drawConnections(waypoints: List<WaypointData>, t: MapCoordinateTransformer) {
    val byId = waypoints.associateBy { it.id }
    for (wp in waypoints) {
        val from = t.toScreenPoint(wp.position)
        for (connectedId in wp.connectedWaypoints) {
            if (wp.id >= connectedId) continue
            val other = byId[connectedId] ?: continue
            drawLine(Color.White.copy(alpha = 0.08f), from, t.toScreenPoint(other.position), strokeWidth = 0.5f)
        }
    }
}

private fun DrawScope.drawActivePath(data: MapRenderData, t: MapCoordinateTransformer) {
    val pathIds = data.activePath ?: return
    if (pathIds.size < 2) return
    val byId = data.waypoints.associateBy { it.id }
    val green = AppColor.AccentGreen
    val idx = data.currentWaypointIndex

    // Covered (completed) portion — dashed
    if (idx > 0) {
        val covered = Path()
        var first = true
        for (i in 0 until min(idx + 1, pathIds.size)) {
            val wp = byId[pathIds[i]] ?: continue
            val p = t.toScreenPoint(wp.position)
            if (first) { covered.moveTo(p.x, p.y); first = false } else covered.lineTo(p.x, p.y)
        }
        drawPath(
            covered,
            color = Color.White.copy(alpha = 0.25f),
            style = Stroke(width = 2.8f, pathEffect = PathEffect.dashPathEffect(floatArrayOf(6f, 4f))),
        )
    }

    // Remaining active portion — glow + line
    val active = Path()
    var first = true
    for (i in idx until pathIds.size) {
        val wp = byId[pathIds[i]] ?: continue
        val p = t.toScreenPoint(wp.position)
        if (first) { active.moveTo(p.x, p.y); first = false } else active.lineTo(p.x, p.y)
    }
    drawPath(active, color = green.copy(alpha = 0.15f), style = Stroke(width = 12f))
    drawPath(active, color = green, style = Stroke(width = 4f))

    // Progress dots
    pathIds.forEachIndexed { i, id ->
        val wp = byId[id] ?: return@forEachIndexed
        val p = t.toScreenPoint(wp.position)
        when {
            i < idx -> {
                drawCircle(Color.White.copy(alpha = 0.25f), radius = 4f, center = p)
                drawCircle(Color.White.copy(alpha = 0.6f), radius = 2f, center = p)
            }
            i == idx -> {
                drawCircle(green.copy(alpha = 0.4f), radius = 6f, center = p)
                drawCircle(green, radius = 3f, center = p)
            }
        }
    }
}

private fun DrawScope.drawWaypoints(waypoints: List<WaypointData>, t: MapCoordinateTransformer, inv: Float) {
    val radius = (2f * inv).coerceIn(1f, 3f)
    for (wp in waypoints) {
        drawCircle(Color.White.copy(alpha = 0.15f), radius = radius, center = t.toScreenPoint(wp.position))
    }
}

private fun DrawScope.drawPois(data: MapRenderData, t: MapCoordinateTransformer, inv: Float) {
    for (poi in data.pois) {
        val p = t.toScreenPoint(poi.position)
        val isDest = data.destinationPoiId == poi.id
        val color = poiColor(poi.type)
        val radius = (if (isDest) 24f else 18f) * inv
        // Shadow
        drawCircle(Color.Black.copy(alpha = 0.3f), radius = radius + 9f * inv, center = Offset(p.x, p.y + 1f))
        if (isDest) drawCircle(color.copy(alpha = 0.25f), radius = 36f * inv, center = p)
        // White border ring
        drawCircle(Color.White.copy(alpha = 0.9f), radius = radius + 3.75f, center = p)
        // Main circle
        drawCircle(color, radius = radius, center = p)
    }
}

private fun DrawScope.drawUserMarker(
    data: MapRenderData,
    t: MapCoordinateTransformer,
    inv: Float,
    headingOverrideDeg: Float?,
    pulse: Float,
) {
    val position = data.userPosition ?: return
    val p = t.toScreenPoint(position)
    val blue = AppColor.AccentBlue
    val outer = 24f * inv
    val inner = 16.5f * inv
    // Animated pulse ring: expands outward and fades, repeating.
    drawCircle(blue.copy(alpha = (1f - pulse) * 0.35f), radius = (21f + pulse * 33f) * inv, center = p)
    drawCircle(blue.copy(alpha = 0.12f), radius = 39f * inv, center = p) // base soft ring
    drawCircle(Color.Black.copy(alpha = 0.25f), radius = outer, center = Offset(p.x, p.y + 1f)) // shadow
    drawCircle(Color.White, radius = outer, center = p)
    drawCircle(blue, radius = inner, center = p)
    drawCircle(Color.White.copy(alpha = 0.8f), radius = inner, center = p, style = Stroke(width = 3f * inv))
    drawCircle(Color.White, radius = 4.5f * inv, center = p)

    val angleDeg = headingOverrideDeg ?: data.userRotation?.let { t.headingDegrees(it) }
    if (angleDeg != null) {
        val rad = Math.toRadians(angleDeg.toDouble()).toFloat()
        val len = 33f * inv
        val baseOffset = (15f * inv) / 2f
        val tip = Offset(p.x + sin(rad) * len, p.y - cos(rad) * len)
        val b1 = Offset(p.x + cos(rad) * baseOffset, p.y + sin(rad) * baseOffset)
        val b2 = Offset(p.x - cos(rad) * baseOffset, p.y - sin(rad) * baseOffset)
        val arrow = Path().apply {
            moveTo(tip.x, tip.y); lineTo(b1.x, b1.y); lineTo(b2.x, b2.y); close()
        }
        drawPath(arrow, color = blue)
        drawPath(arrow, color = Color.White.copy(alpha = 0.7f), style = Stroke(width = 2.25f * inv))
    }
}

/** Heading in degrees (clockwise from +Z/up) from a quaternion, matching MapCoordinateTransformer. */
private fun headingFromRotation(r: com.multiset.wearable.vps.localization.Rotation): Float {
    val forwardX = 2f * (r.x * r.z + r.w * r.y)
    val forwardZ = 1f - 2f * (r.x * r.x + r.y * r.y)
    return Math.toDegrees(atan2(forwardX, forwardZ).toDouble()).toFloat()
}

private fun poiColor(type: String): Color =
    when (type.lowercase()) {
        "room" -> AppColor.AccentBlue
        "foodarea" -> AppColor.AccentGreen
        "exit" -> AppColor.AccentPurple
        "information" -> AppColor.Yellow
        else -> AppColor.TextSecondary
    }

// Grey helper matching iOS Color(white:) for the floor fill.
private fun floorGrey(white: Float): Color = Color(white, white, white, 1f)
