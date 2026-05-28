/*
Copyright (c) 2026 MultiSet AI. All rights reserved.
Licensed under the MultiSet License. You may not use this file except in compliance with the License. and you can't re-distribute this file without a prior notice
For license details, visit www.multiset.ai.
Redistribution in source or binary forms must retain this notice.
*/

// Embedded + full-screen 2D navigation map, ported from the iOS NavigationMapView and
// FullScreenMapView: collapsible map card with header + mini controls, and a full-screen
// view with zoom/recenter/reset controls, a legend (browsing) or nav-control bar
// (navigating), and a POI detail sheet with a Navigate action.

package com.multiset.wearable.vps.ui

import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.navigationBarsPadding
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.statusBarsPadding
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Add
import androidx.compose.material.icons.filled.Close
import androidx.compose.material.icons.filled.DirectionsWalk
import androidx.compose.material.icons.filled.ExpandLess
import androidx.compose.material.icons.filled.ExpandMore
import androidx.compose.material.icons.filled.Fullscreen
import androidx.compose.material.icons.filled.Map
import androidx.compose.material.icons.filled.MeetingRoom
import androidx.compose.material.icons.filled.MyLocation
import androidx.compose.material.icons.filled.Refresh
import androidx.compose.material.icons.filled.Remove
import androidx.compose.material.icons.filled.Restaurant
import androidx.compose.material3.Button
import androidx.compose.material3.ButtonDefaults
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.Icon
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.compose.ui.window.Dialog
import androidx.compose.ui.window.DialogProperties
import com.multiset.wearable.vps.navigation.NavigationInstruction
import com.multiset.wearable.vps.navigation.NavigationPOI

// MARK: - Static map preview (landing page)

@Composable
fun MapPreviewCard(data: MapRenderData, modifier: Modifier = Modifier) {
    Column(modifier = modifier.clip(RoundedCornerShape(16.dp)).background(AppColor.CardBackground)) {
        Row(
            modifier = Modifier.fillMaxWidth().padding(horizontal = 12.dp, vertical = 10.dp),
            verticalAlignment = Alignment.CenterVertically,
            horizontalArrangement = Arrangement.spacedBy(8.dp),
        ) {
            Icon(Icons.Default.Map, null, tint = AppColor.AccentBlue, modifier = Modifier.size(14.dp))
            Text("Map Preview", fontSize = 14.sp, fontWeight = FontWeight.SemiBold, color = AppColor.TextPrimary)
            Spacer(modifier = Modifier.weight(1f))
            Text("${data.pois.size} destinations", fontSize = 12.sp, color = AppColor.TextSecondary)
        }
        Box(modifier = Modifier.fillMaxWidth().height(180.dp)) {
            NavigationMapCanvas(data = data, zoom = 1f, modifier = Modifier.fillMaxSize())
        }
    }
}

// MARK: - Embedded collapsible map card

@Composable
fun NavigationMapView(
    data: MapRenderData,
    mapState: MapViewState,
    isNavigating: Boolean,
    onFullScreen: () -> Unit,
    modifier: Modifier = Modifier,
) {
    var expanded by remember { mutableStateOf(false) }
    LaunchedEffect(data.userPosition) {
        if (mapState.isRecenterActive) mapState.centerOnUser(data.userPosition, data.bounds)
    }

    Column(modifier = modifier.clip(RoundedCornerShape(16.dp)).background(AppColor.CardBackground)) {
        // Header
        Row(
            modifier = Modifier.fillMaxWidth().padding(horizontal = 12.dp, vertical = 10.dp),
            verticalAlignment = Alignment.CenterVertically,
            horizontalArrangement = Arrangement.spacedBy(8.dp),
        ) {
            Icon(Icons.Default.Map, null, tint = AppColor.AccentBlue, modifier = Modifier.size(14.dp))
            Text("Navigation Map", fontSize = 14.sp, fontWeight = FontWeight.SemiBold, color = AppColor.TextPrimary)
            Spacer(modifier = Modifier.weight(1f))
            if (isNavigating) {
                Row(
                    verticalAlignment = Alignment.CenterVertically,
                    horizontalArrangement = Arrangement.spacedBy(4.dp),
                    modifier =
                        Modifier.clip(RoundedCornerShape(8.dp))
                            .background(AppColor.AccentGreen.copy(alpha = 0.15f))
                            .padding(horizontal = 8.dp, vertical = 4.dp),
                ) {
                    Box(modifier = Modifier.size(6.dp).clip(CircleShape).background(AppColor.AccentGreen))
                    Text("Navigating", fontSize = 11.sp, fontWeight = FontWeight.Medium, color = AppColor.AccentGreen)
                }
            }
            Icon(
                if (expanded) Icons.Default.ExpandLess else Icons.Default.ExpandMore,
                "Toggle map size",
                tint = AppColor.TextSecondary,
                modifier = Modifier.size(20.dp).clickable { expanded = !expanded },
            )
        }

        // Map + mini controls
        Box(modifier = Modifier.fillMaxWidth().height(if (expanded) 280.dp else 160.dp)) {
            InteractiveMap(
                data = data,
                mapState = mapState,
                showLabels = true,
                onPoiTap = { onFullScreen() },
                modifier = Modifier.fillMaxSize(),
            )
            Column(
                modifier = Modifier.align(Alignment.TopEnd).padding(8.dp),
                verticalArrangement = Arrangement.spacedBy(6.dp),
            ) {
                MiniMapButton(Icons.Default.Fullscreen) { onFullScreen() }
                MiniMapButton(Icons.Default.Add) { mapState.applyZoom(1.3f) }
                MiniMapButton(Icons.Default.Remove) { mapState.applyZoom(0.77f) }
                MiniMapButton(Icons.Default.MyLocation) { mapState.centerOnUser(data.userPosition, data.bounds) }
            }
        }
    }
}

@Composable
private fun MiniMapButton(icon: ImageVector, onClick: () -> Unit) {
    Box(
        modifier = Modifier.size(28.dp).clip(CircleShape).background(Color.Black.copy(alpha = 0.5f)).clickable { onClick() },
        contentAlignment = Alignment.Center,
    ) {
        Icon(icon, null, tint = Color.White, modifier = Modifier.size(14.dp))
    }
}

// MARK: - Full-screen map

@Composable
fun FullScreenMapView(
    data: MapRenderData,
    mapState: MapViewState,
    isNavigating: Boolean,
    currentInstruction: NavigationInstruction?,
    isLocalized: Boolean,
    onStartNavigation: (Int) -> Unit,
    onStopNavigation: () -> Unit,
    onDismiss: () -> Unit,
) {
    var selectedPoi by remember { mutableStateOf<NavigationPOI?>(null) }
    val destinationName = data.pois.firstOrNull { it.id == data.destinationPoiId }?.name
    LaunchedEffect(data.userPosition) {
        if (mapState.isRecenterActive) mapState.centerOnUser(data.userPosition, data.bounds)
    }

    Dialog(onDismissRequest = onDismiss, properties = DialogProperties(usePlatformDefaultWidth = false)) {
        Box(modifier = Modifier.fillMaxSize().background(AppColor.DarkBackground)) {
            Column(modifier = Modifier.fillMaxSize().statusBarsPadding()) {
                // Header
                Row(
                    modifier = Modifier.fillMaxWidth().background(AppColor.CardBackground).padding(horizontal = 16.dp, vertical = 12.dp),
                    verticalAlignment = Alignment.CenterVertically,
                ) {
                    Icon(
                        Icons.Default.Close,
                        "Close",
                        tint = AppColor.TextSecondary,
                        modifier = Modifier.size(28.dp).clickable { onDismiss() },
                    )
                    Column(modifier = Modifier.weight(1f), horizontalAlignment = Alignment.CenterHorizontally) {
                        Text("Navigation Map", fontSize = 18.sp, fontWeight = FontWeight.Bold, color = AppColor.TextPrimary)
                        if (isNavigating && destinationName != null) {
                            Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(4.dp)) {
                                Box(modifier = Modifier.size(6.dp).clip(CircleShape).background(AppColor.AccentGreen))
                                Text("Navigating to $destinationName", fontSize = 12.sp, fontWeight = FontWeight.Medium, color = AppColor.AccentGreen)
                            }
                        }
                    }
                    Spacer(modifier = Modifier.size(28.dp))
                }

                // Map + controls
                Box(modifier = Modifier.fillMaxWidth().weight(1f)) {
                    InteractiveMap(
                        data = data,
                        mapState = mapState,
                        showLabels = true,
                        onPoiTap = { selectedPoi = it },
                        modifier = Modifier.fillMaxSize().padding(12.dp),
                    )
                    Column(
                        modifier = Modifier.align(Alignment.TopEnd).padding(top = 20.dp, end = 20.dp),
                        verticalArrangement = Arrangement.spacedBy(8.dp),
                    ) {
                        MapControlButton(Icons.Default.Add) { mapState.applyZoom(1.5f) }
                        MapControlButton(Icons.Default.Remove) { mapState.applyZoom(0.67f) }
                        MapControlButton(Icons.Default.MyLocation, active = mapState.isRecenterActive) {
                            mapState.toggleRecenter(data.userPosition, data.bounds)
                        }
                        MapControlButton(Icons.Default.Refresh) { mapState.reset() }
                    }
                }

                // Bottom bar: nav controls or legend
                if (isNavigating) {
                    NavControlBar(currentInstruction, destinationName, onStop = { onStopNavigation(); onDismiss() })
                } else {
                    LegendBar()
                }
            }

            // POI detail overlay
            selectedPoi?.let { poi ->
                val distance = data.userPosition?.distance2D(poi.position)
                PoiDetailSheet(
                    poi = poi,
                    distance = distance,
                    isLocalized = isLocalized,
                    onCancel = { selectedPoi = null },
                    onNavigate = {
                        selectedPoi = null
                        onStartNavigation(poi.id)
                        onDismiss()
                    },
                )
            }
        }
    }
}

@Composable
private fun MapControlButton(icon: ImageVector, active: Boolean = false, onClick: () -> Unit) {
    Box(
        modifier = Modifier.size(32.dp).clip(CircleShape).background(AppColor.CardBackground.copy(alpha = 0.9f)).clickable { onClick() },
        contentAlignment = Alignment.Center,
    ) {
        Icon(icon, null, tint = if (active) AppColor.AccentBlue else Color.White, modifier = Modifier.size(16.dp))
    }
}

@Composable
private fun NavControlBar(instruction: NavigationInstruction?, destinationName: String?, onStop: () -> Unit) {
    Row(
        modifier = Modifier.fillMaxWidth().background(AppColor.CardBackground).navigationBarsPadding().padding(horizontal = 16.dp, vertical = 12.dp),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        if (instruction != null) {
            Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(10.dp), modifier = Modifier.weight(1f)) {
                Box(contentAlignment = Alignment.Center) {
                    Box(modifier = Modifier.size(44.dp).clip(CircleShape).background(AppColor.AccentGreen.copy(alpha = 0.2f)))
                    Box(modifier = Modifier.size(32.dp).clip(CircleShape).background(AppColor.AccentGreen), contentAlignment = Alignment.Center) {
                        Icon(instructionIcon(instruction), null, tint = Color.White, modifier = Modifier.size(16.dp))
                    }
                }
                Column {
                    Text(instruction.description, fontSize = 14.sp, fontWeight = FontWeight.SemiBold, color = AppColor.TextPrimary)
                    if (destinationName != null) Text("To $destinationName", fontSize = 12.sp, color = AppColor.TextSecondary)
                }
            }
        } else {
            Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(8.dp), modifier = Modifier.weight(1f)) {
                CircularProgressIndicator(modifier = Modifier.size(18.dp), color = AppColor.AccentGreen, strokeWidth = 2.dp)
                Text("Calculating route...", fontSize = 14.sp, fontWeight = FontWeight.Medium, color = AppColor.TextSecondary)
            }
        }
        Button(
            onClick = onStop,
            colors = ButtonDefaults.buttonColors(containerColor = AppColor.AccentRed.copy(alpha = 0.9f)),
            shape = RoundedCornerShape(20.dp),
        ) {
            Icon(Icons.Default.Close, null, tint = Color.White, modifier = Modifier.size(12.dp))
            Spacer(modifier = Modifier.width(6.dp))
            Text("Stop", fontSize = 13.sp, fontWeight = FontWeight.SemiBold, color = Color.White)
        }
    }
}

@Composable
private fun LegendBar() {
    Row(
        modifier = Modifier.fillMaxWidth().background(AppColor.CardBackground).navigationBarsPadding().padding(horizontal = 16.dp, vertical = 10.dp),
        horizontalArrangement = Arrangement.spacedBy(16.dp),
    ) {
        LegendItem(AppColor.AccentBlue, Icons.Default.MeetingRoom, "Room")
        LegendItem(AppColor.AccentGreen, Icons.Default.Restaurant, "Food")
        LegendItem(AppColor.AccentPurple, Icons.Default.DirectionsWalk, "Exit")
        LegendItem(AppColor.AccentBlue, Icons.Default.MyLocation, "You")
    }
}

@Composable
private fun LegendItem(color: Color, icon: ImageVector, label: String) {
    Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(4.dp)) {
        Icon(icon, null, tint = color, modifier = Modifier.size(12.dp))
        Text(label, fontSize = 11.sp, fontWeight = FontWeight.Medium, color = AppColor.TextSecondary)
    }
}

@Composable
private fun PoiDetailSheet(
    poi: NavigationPOI,
    distance: Float?,
    isLocalized: Boolean,
    onCancel: () -> Unit,
    onNavigate: () -> Unit,
) {
    Box(modifier = Modifier.fillMaxSize().background(Color.Black.copy(alpha = 0.3f)).clickable { onCancel() }) {
        Column(
            modifier =
                Modifier.align(Alignment.BottomCenter)
                    .fillMaxWidth()
                    .clip(RoundedCornerShape(topStart = 20.dp, topEnd = 20.dp))
                    .background(AppColor.CardBackground)
                    .navigationBarsPadding()
                    .clickable(enabled = false) {}
                    .padding(16.dp),
            verticalArrangement = Arrangement.spacedBy(16.dp),
        ) {
            Box(
                modifier = Modifier.align(Alignment.CenterHorizontally).width(36.dp).height(4.dp).clip(RoundedCornerShape(50)).background(AppColor.TextSecondary.copy(alpha = 0.5f))
            )
            Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(12.dp)) {
                Box(modifier = Modifier.size(48.dp).clip(CircleShape).background(poiTypeColor(poi.type)), contentAlignment = Alignment.Center) {
                    Icon(poiTypeIcon(poi.type), null, tint = Color.White, modifier = Modifier.size(20.dp))
                }
                Column(modifier = Modifier.weight(1f)) {
                    Text(poi.name, fontSize = 18.sp, fontWeight = FontWeight.Bold, color = AppColor.TextPrimary)
                    Text(poi.type.replaceFirstChar { it.uppercase() }, fontSize = 13.sp, fontWeight = FontWeight.Medium, color = AppColor.TextSecondary)
                    if (distance != null) {
                        Text("%.1f m away".format(distance), fontSize = 13.sp, fontWeight = FontWeight.Medium, color = AppColor.AccentBlue)
                    }
                }
            }
            Row(horizontalArrangement = Arrangement.spacedBy(12.dp)) {
                Button(
                    onClick = onCancel,
                    colors = ButtonDefaults.buttonColors(containerColor = AppColor.DarkBackground),
                    shape = RoundedCornerShape(12.dp),
                    modifier = Modifier.weight(1f).height(48.dp),
                ) {
                    Text("Cancel", fontSize = 15.sp, fontWeight = FontWeight.SemiBold, color = AppColor.TextPrimary)
                }
                Button(
                    onClick = { if (isLocalized) onNavigate() },
                    enabled = isLocalized,
                    colors =
                        ButtonDefaults.buttonColors(
                            containerColor = AppColor.AccentGreen,
                            disabledContainerColor = AppColor.TextSecondary,
                        ),
                    shape = RoundedCornerShape(12.dp),
                    modifier = Modifier.weight(1f).height(48.dp),
                ) {
                    Icon(Icons.Default.MyLocation, null, tint = Color.White, modifier = Modifier.size(16.dp))
                    Spacer(modifier = Modifier.width(6.dp))
                    Text("Navigate", fontSize = 15.sp, fontWeight = FontWeight.SemiBold, color = Color.White)
                }
            }
        }
    }
}
