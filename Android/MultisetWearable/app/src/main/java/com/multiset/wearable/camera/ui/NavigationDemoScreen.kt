/*
Copyright (c) 2026 MultiSet AI. All rights reserved.
Licensed under the MultiSet License. You may not use this file except in compliance with the License. and you can't re-distribute this file without a prior notice
For license details, visit www.multiset.ai.
Redistribution in source or binary forms must retain this notice.
*/

// NavigationDemoScreen - Audio turn-by-turn navigation, mirroring the iOS navigation flow
// (NonStreamView/StreamView + POIListView + NavigationStatusView + the 2D map). Landing →
// stream → localize → choose destination → active navigation with instruction banner + map.

package com.multiset.wearable.vps.ui

import androidx.activity.ComponentActivity
import androidx.activity.compose.LocalActivity
import androidx.compose.animation.AnimatedVisibility
import androidx.compose.animation.core.RepeatMode
import androidx.compose.animation.core.animateFloat
import androidx.compose.animation.core.infiniteRepeatable
import androidx.compose.animation.core.rememberInfiniteTransition
import androidx.compose.animation.core.tween
import androidx.compose.foundation.Image
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxHeight
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.navigationBarsPadding
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.statusBarsPadding
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.ArrowUpward
import androidx.compose.material.icons.filled.CheckCircle
import androidx.compose.material.icons.filled.ChevronRight
import androidx.compose.material.icons.filled.Close
import androidx.compose.material.icons.filled.DirectionsWalk
import androidx.compose.material.icons.filled.Hearing
import androidx.compose.material.icons.filled.HourglassEmpty
import androidx.compose.material.icons.filled.Info
import androidx.compose.material.icons.filled.KeyboardArrowDown
import androidx.compose.material.icons.filled.KeyboardArrowUp
import androidx.compose.material.icons.filled.Map
import androidx.compose.material.icons.filled.MeetingRoom
import androidx.compose.material.icons.filled.MyLocation
import androidx.compose.material.icons.filled.Navigation
import androidx.compose.material.icons.filled.Place
import androidx.compose.material.icons.filled.Refresh
import androidx.compose.material.icons.filled.Restaurant
import androidx.compose.material.icons.filled.Settings
import androidx.compose.material.icons.filled.TurnLeft
import androidx.compose.material.icons.filled.TurnRight
import androidx.compose.material.icons.filled.TurnSlightLeft
import androidx.compose.material.icons.filled.TurnSlightRight
import androidx.compose.material.icons.filled.UTurnLeft
import androidx.compose.material.icons.filled.Warning
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.Button
import androidx.compose.material3.ButtonDefaults
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.TextButton
import androidx.compose.material3.Icon
import androidx.compose.material3.LinearProgressIndicator
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.DisposableEffect
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.asImageBitmap
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.compose.ui.window.Dialog
import androidx.compose.ui.window.DialogProperties
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import androidx.lifecycle.viewmodel.compose.viewModel
import com.meta.wearable.dat.core.types.Permission
import com.meta.wearable.dat.core.types.PermissionStatus
import com.multiset.wearable.vps.localization.SDKConfig
import com.multiset.wearable.vps.navigation.NavPosition
import com.multiset.wearable.vps.navigation.NavigationInstruction
import com.multiset.wearable.vps.navigation.NavigationPOI
import com.multiset.wearable.vps.stream.StreamSessionViewModel
import com.multiset.wearable.vps.stream.StreamingStatus
import com.multiset.wearable.vps.wearables.WearablesViewModel
import kotlin.math.sqrt
import kotlinx.coroutines.launch
import androidx.compose.runtime.rememberCoroutineScope

@Composable
fun NavigationDemoScreen(
    wearablesViewModel: WearablesViewModel,
    onRequestWearablesPermission: suspend (Permission) -> PermissionStatus,
    onDismiss: () -> Unit,
    modifier: Modifier = Modifier,
) {
    val activity = LocalActivity.current as ComponentActivity
    val viewModel: StreamSessionViewModel =
        viewModel(
            key = "stream_navigation",
            factory =
                StreamSessionViewModel.Factory(
                    application = activity.application,
                    wearablesViewModel = wearablesViewModel,
                    enableLocalization = true,
                ),
        )
    val uiState by viewModel.uiState.collectAsStateWithLifecycle()
    val navState by viewModel.navigationState.collectAsStateWithLifecycle()
    val scope = rememberCoroutineScope()
    val mapState = rememberMapViewState()
    var showPoiList by remember { mutableStateOf(false) }
    var showFullMap by remember { mutableStateOf(false) }
    var showSettings by remember { mutableStateOf(false) }
    var showPhotoPreview by remember { mutableStateOf(false) }
    var showStopConfirm by remember { mutableStateOf(false) }

    DisposableEffect(Unit) {
        onDispose {
            viewModel.stopNavigation()
            viewModel.stopSession()
        }
    }

    // Refresh navigation data + map instantly when the configured map code changes.
    val mapConfigVersion by SDKConfig.mapConfigVersion.collectAsStateWithLifecycle()
    LaunchedEffect(mapConfigVersion) { viewModel.reloadNavigationData() }

    // Auto-open the full-screen map when navigation starts (matches iOS).
    LaunchedEffect(navState.isNavigating) {
        if (navState.isNavigating) showFullMap = true
    }

    fun mapData() =
        MapRenderData(
            bounds = viewModel.navBounds(),
            waypoints = viewModel.navWaypoints(),
            pois = viewModel.navigationPOIs(),
            userPosition = navState.userPosition,
            userRotation = navState.userRotation,
            activePath = navState.navigationPath,
            destinationPoiId = navState.destination?.id,
            currentWaypointIndex = navState.currentWaypointIndex,
        )

    val originDistance =
        uiState.localizationResult?.posePosition?.let { sqrt(it.x * it.x + it.y * it.y + it.z * it.z) }

    Box(
        modifier =
            modifier.fillMaxSize().background(
                if (uiState.isStreaming) Brush.verticalGradient(listOf(Color.Black, Color.Black))
                else Brush.verticalGradient(listOf(AppColor.DarkBackground, AppColor.DarkBackgroundEnd))
            )
    ) {
        when (uiState.streamingStatus) {
            StreamingStatus.STOPPED ->
                NavLandingPage(
                    hasActiveDevice = uiState.hasActiveDevice,
                    mapData = mapData(),
                    onBack = onDismiss,
                    onSettings = { showSettings = true },
                    onStart = { scope.launch { viewModel.startSession(onRequestWearablesPermission) } },
                )
            StreamingStatus.WAITING -> NavWaitingPage(onCancel = { viewModel.stopSession() })
            StreamingStatus.STREAMING ->
                NavStreamingPage(
                    navState = navState,
                    isLocalized = uiState.localizationResult?.poseFound == true,
                    isLocalizing = uiState.isLocalizing,
                    originDistance = originDistance,
                    videoFrame = uiState.videoFrame,
                    videoFrameCount = uiState.videoFrameCount,
                    hasFrame = uiState.hasReceivedFirstFrame,
                    mapData = mapData(),
                    mapState = mapState,
                    errorMessage = uiState.errorMessage,
                    onLocalize = { viewModel.localize() },
                    onShowPoiList = { showPoiList = true },
                    onShowMap = { showFullMap = true },
                    onShowSettings = { showSettings = true },
                    onShowPhotoPreview = { showPhotoPreview = true },
                    onStopNavigation = { viewModel.stopNavigation() },
                    onStopRequested = { showStopConfirm = true },
                    onClearError = { viewModel.clearError() },
                )
        }
    }

    if (showPoiList) {
        POIListSheet(
            pois = viewModel.navigationPOIs(),
            userPosition = viewModel.currentUserNavPosition(),
            isLocalized = uiState.localizationResult?.poseFound == true,
            onSelect = { id ->
                showPoiList = false
                viewModel.startNavigation(id)
            },
            onDismiss = { showPoiList = false },
        )
    }

    if (showFullMap) {
        FullScreenMapView(
            data = mapData(),
            mapState = mapState,
            isNavigating = navState.isNavigating,
            currentInstruction = navState.currentInstruction,
            isLocalized = uiState.localizationResult?.poseFound == true,
            onStartNavigation = { viewModel.startNavigation(it) },
            onStopNavigation = { viewModel.stopNavigation() },
            onDismiss = { showFullMap = false },
        )
    }

    if (showSettings) {
        SettingsDialog(onDismiss = { showSettings = false })
    }

    if (showPhotoPreview && uiState.localizationResult != null) {
        PhotoPreviewSheet(
            photo = uiState.capturedPhoto,
            result = uiState.localizationResult!!,
            onDismiss = { showPhotoPreview = false },
        )
    }

    if (showStopConfirm) {
        AlertDialog(
            onDismissRequest = { showStopConfirm = false },
            containerColor = AppColor.CardBackground,
            title = { Text("Close Navigation?", color = AppColor.TextPrimary) },
            text = {
                Text(
                    "This will stop the camera stream and end any active navigation.",
                    color = AppColor.TextSecondary,
                )
            },
            confirmButton = {
                TextButton(
                    onClick = {
                        showStopConfirm = false
                        viewModel.stopNavigation()
                        viewModel.stopSession()
                        onDismiss()
                    }
                ) {
                    Text("Close", color = AppColor.Red)
                }
            },
            dismissButton = {
                TextButton(onClick = { showStopConfirm = false }) {
                    Text("Cancel", color = AppColor.TextPrimary)
                }
            },
        )
    }
}

// MARK: - Landing

@Composable
private fun NavLandingPage(
    hasActiveDevice: Boolean,
    mapData: MapRenderData,
    onBack: () -> Unit,
    onSettings: () -> Unit,
    onStart: () -> Unit,
) {
    Column(
        modifier =
            Modifier.fillMaxSize()
                .statusBarsPadding()
                .navigationBarsPadding()
                .verticalScroll(rememberScrollState())
                .padding(horizontal = 24.dp),
        horizontalAlignment = Alignment.CenterHorizontally,
    ) {
        DemoTopBar(onBack = onBack, onSettings = onSettings)
        Spacer(modifier = Modifier.height(20.dp))
        Box(
            modifier = Modifier.size(80.dp).clip(CircleShape).background(AppColor.AccentBlue.copy(alpha = 0.15f)),
            contentAlignment = Alignment.Center,
        ) {
            Icon(Icons.Default.Navigation, null, tint = AppColor.AccentBlue, modifier = Modifier.size(36.dp))
        }
        Spacer(modifier = Modifier.height(10.dp))
        Text("Navigation", fontSize = 28.sp, fontWeight = FontWeight.Bold, color = AppColor.TextPrimary)
        Text("Audio-guided wayfinding with Ray-Ban Meta", fontSize = 14.sp, color = AppColor.TextSecondary)
        Spacer(modifier = Modifier.height(4.dp))
        Text(
            "Navigate hands-free using your glasses camera for localization and receive turn-by-turn audio instructions.",
            fontSize = 13.sp,
            color = AppColor.TextSecondary.copy(alpha = 0.8f),
            textAlign = TextAlign.Center,
            modifier = Modifier.padding(horizontal = 8.dp),
        )
        Spacer(modifier = Modifier.height(16.dp))

        // Status chips: device readiness + map code
        Row(horizontalArrangement = Arrangement.spacedBy(12.dp), verticalAlignment = Alignment.CenterVertically) {
            val deviceColor = if (hasActiveDevice) AppColor.AccentGreen else AppColor.Yellow
            Row(
                verticalAlignment = Alignment.CenterVertically,
                horizontalArrangement = Arrangement.spacedBy(6.dp),
                modifier =
                    Modifier.clip(RoundedCornerShape(50)).background(deviceColor.copy(alpha = 0.15f)).padding(horizontal = 12.dp, vertical = 8.dp),
            ) {
                Icon(if (hasActiveDevice) Icons.Default.CheckCircle else Icons.Default.HourglassEmpty, null, tint = deviceColor, modifier = Modifier.size(14.dp))
                Text(if (hasActiveDevice) "Device Ready" else "Waiting...", color = deviceColor, fontSize = 12.sp, fontWeight = FontWeight.Medium)
            }
            if (SDKConfig.MAP_CODE.isNotEmpty()) {
                Row(
                    verticalAlignment = Alignment.CenterVertically,
                    horizontalArrangement = Arrangement.spacedBy(6.dp),
                    modifier =
                        Modifier.clip(RoundedCornerShape(50)).background(AppColor.AccentPurple.copy(alpha = 0.15f)).padding(horizontal = 12.dp, vertical = 8.dp),
                ) {
                    Icon(Icons.Default.Map, null, tint = AppColor.AccentPurple, modifier = Modifier.size(12.dp))
                    Text(SDKConfig.MAP_CODE, color = AppColor.AccentPurple, fontSize = 12.sp, fontFamily = androidx.compose.ui.text.font.FontFamily.Monospace)
                }
            }
        }

        Spacer(modifier = Modifier.height(16.dp))
        HowItWorksCard(
            steps =
                listOf(
                    Triple(Icons.Default.MyLocation, AppColor.AccentBlue, "Localize" to "Find position"),
                    Triple(Icons.Default.Navigation, AppColor.AccentGreen, "Navigate" to "Pick destination"),
                    Triple(Icons.Default.Hearing, AppColor.AccentPurple, "Listen" to "Follow audio"),
                )
        )

        if (mapData.bounds != null) {
            Spacer(modifier = Modifier.height(16.dp))
            MapPreviewCard(data = mapData, modifier = Modifier.fillMaxWidth())
        }

        Spacer(modifier = Modifier.height(24.dp))
        Button(
            onClick = onStart,
            enabled = hasActiveDevice,
            colors =
                ButtonDefaults.buttonColors(
                    containerColor = AppColor.DeepBlue,
                    disabledContainerColor = AppColor.DeepBlue.copy(alpha = 0.5f),
                ),
            shape = RoundedCornerShape(14.dp),
            modifier = Modifier.fillMaxWidth().height(54.dp),
        ) {
            Icon(Icons.Default.Navigation, null, modifier = Modifier.size(20.dp), tint = Color.White)
            Spacer(modifier = Modifier.width(10.dp))
            Text("Open Navigation", fontSize = 17.sp, fontWeight = FontWeight.SemiBold, color = Color.White)
        }
        Spacer(modifier = Modifier.height(8.dp))
        Text(
            if (hasActiveDevice) "Starts camera stream for localization" else "Waiting for glasses to become active...",
            fontSize = 11.sp,
            color = AppColor.TextSecondary,
        )
        Spacer(modifier = Modifier.height(28.dp))
    }
}

@Composable
private fun NavWaitingPage(onCancel: () -> Unit) {
    Column(
        modifier = Modifier.fillMaxSize().navigationBarsPadding(),
        horizontalAlignment = Alignment.CenterHorizontally,
        verticalArrangement = Arrangement.Center,
    ) {
        CircularProgressIndicator(color = AppColor.AccentGreen)
        Spacer(modifier = Modifier.height(16.dp))
        Text("Starting camera stream...", fontSize = 15.sp, color = AppColor.TextSecondary)
        Spacer(modifier = Modifier.height(32.dp))
        Text(
            "Cancel",
            color = AppColor.TextPrimary,
            modifier =
                Modifier.clip(RoundedCornerShape(10.dp))
                    .background(AppColor.CardBackground)
                    .clickable { onCancel() }
                    .padding(horizontal = 24.dp, vertical = 12.dp),
        )
    }
}

// MARK: - Streaming + active navigation

@Composable
private fun NavStreamingPage(
    navState: com.multiset.wearable.vps.navigation.NavigationState,
    isLocalized: Boolean,
    isLocalizing: Boolean,
    originDistance: Float?,
    videoFrame: android.graphics.Bitmap?,
    videoFrameCount: Int,
    hasFrame: Boolean,
    mapData: MapRenderData,
    mapState: MapViewState,
    errorMessage: String?,
    onLocalize: () -> Unit,
    onShowPoiList: () -> Unit,
    onShowMap: () -> Unit,
    onShowSettings: () -> Unit,
    onShowPhotoPreview: () -> Unit,
    onStopNavigation: () -> Unit,
    onStopRequested: () -> Unit,
    onClearError: () -> Unit,
) {
    // Auto-dismiss transient errors after a few seconds.
    LaunchedEffect(errorMessage) {
        if (errorMessage != null) {
            kotlinx.coroutines.delay(3500)
            onClearError()
        }
    }
    Box(modifier = Modifier.fillMaxSize()) {
        if (videoFrame != null && hasFrame) {
            androidx.compose.runtime.key(videoFrameCount) {
                Image(
                    bitmap = videoFrame.asImageBitmap(),
                    contentDescription = "Live stream",
                    modifier = Modifier.fillMaxSize(),
                    contentScale = ContentScale.Crop,
                )
            }
        } else {
            Column(
                modifier = Modifier.fillMaxSize(),
                horizontalAlignment = Alignment.CenterHorizontally,
                verticalArrangement = Arrangement.Center,
            ) {
                CircularProgressIndicator(color = Color.White)
                Spacer(modifier = Modifier.height(12.dp))
                Text("Waiting for video...", color = Color.White.copy(alpha = 0.7f), fontSize = 14.sp)
            }
        }

        // Top bar: localized "Origin" capsule + map + settings, then nav status banner
        Column(modifier = Modifier.fillMaxWidth().statusBarsPadding().padding(top = 8.dp)) {
            Row(
                modifier = Modifier.fillMaxWidth().padding(horizontal = 16.dp),
                verticalAlignment = Alignment.CenterVertically,
                horizontalArrangement = Arrangement.SpaceBetween,
            ) {
                if (isLocalized) {
                    Row(
                        verticalAlignment = Alignment.CenterVertically,
                        horizontalArrangement = Arrangement.spacedBy(6.dp),
                        modifier =
                            Modifier.clip(RoundedCornerShape(50))
                                .background(AppColor.AccentGreen.copy(alpha = 0.8f))
                                .clickable { onShowPhotoPreview() }
                                .padding(horizontal = 12.dp, vertical = 8.dp),
                    ) {
                        Icon(Icons.Default.CheckCircle, null, tint = Color.White, modifier = Modifier.size(16.dp))
                        Text(
                            "Origin: %.1f m".format(originDistance ?: 0f),
                            color = Color.White,
                            fontSize = 14.sp,
                            fontWeight = FontWeight.Medium,
                        )
                    }
                } else {
                    Spacer(modifier = Modifier.width(1.dp))
                }
                Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                    OverlayCircleButton(Icons.Default.Map, "Map", onShowMap)
                    OverlayCircleButton(Icons.Default.Settings, "Settings", onShowSettings)
                }
            }
            if (navState.isNavigating) {
                Spacer(modifier = Modifier.height(8.dp))
                NavigationStatusBanner(navState = navState, onStopNavigation = onStopNavigation)
            }
            if (errorMessage != null) {
                Spacer(modifier = Modifier.height(8.dp))
                Row(
                    modifier =
                        Modifier.fillMaxWidth()
                            .padding(horizontal = 16.dp)
                            .clip(RoundedCornerShape(12.dp))
                            .background(Color.Black.copy(alpha = 0.85f))
                            .padding(12.dp),
                    verticalAlignment = Alignment.CenterVertically,
                    horizontalArrangement = Arrangement.spacedBy(8.dp),
                ) {
                    Icon(Icons.Default.Warning, null, tint = AppColor.Yellow, modifier = Modifier.size(16.dp))
                    Text(errorMessage, color = Color.White, fontSize = 13.sp, modifier = Modifier.weight(1f))
                }
            }
        }

        // Embedded map (after localization or while navigating), above the bottom controls
        if (isLocalized || navState.isNavigating) {
            Box(
                modifier =
                    Modifier.align(Alignment.BottomCenter)
                        .fillMaxWidth()
                        .navigationBarsPadding()
                        .padding(bottom = 150.dp, start = 16.dp, end = 16.dp),
            ) {
                NavigationMapView(
                    data = mapData,
                    mapState = mapState,
                    isNavigating = navState.isNavigating,
                    onFullScreen = onShowMap,
                    modifier = Modifier.fillMaxWidth(),
                )
            }
        }

        // Bottom controls: Stop | Localize | POI list, with direction guidance during nav
        Column(
            modifier = Modifier.align(Alignment.BottomCenter).fillMaxWidth().navigationBarsPadding().padding(bottom = 24.dp),
            horizontalAlignment = Alignment.CenterHorizontally,
            verticalArrangement = Arrangement.spacedBy(16.dp),
        ) {
            if (navState.isNavigating) {
                DirectionGuidanceIcon(navState.currentInstruction)
            }
            Row(
                modifier = Modifier.fillMaxWidth().padding(horizontal = 40.dp),
                verticalAlignment = Alignment.CenterVertically,
                horizontalArrangement = Arrangement.SpaceBetween,
            ) {
                CircleControlButton(Icons.Default.Close, Color.White.copy(alpha = 0.25f)) { onStopRequested() }
                LocalizeButton(isLocalizing = isLocalizing, onClick = onLocalize)
                CircleControlButton(
                    if (navState.isNavigating) Icons.Default.MyLocation else Icons.Default.Place,
                    if (navState.isNavigating) AppColor.AccentGreen.copy(alpha = 0.8f) else Color.White.copy(alpha = 0.25f),
                ) { onShowPoiList() }
            }
        }
    }
}

@Composable
private fun CircleControlButton(icon: ImageVector, background: Color, onClick: () -> Unit) {
    Box(
        modifier = Modifier.size(50.dp).clip(CircleShape).background(background).clickable { onClick() },
        contentAlignment = Alignment.Center,
    ) {
        Icon(icon, null, tint = Color.White, modifier = Modifier.size(22.dp))
    }
}

/** Instruction icon + label shown above the controls during navigation (iOS DirectionGuidanceIcon). */
@Composable
private fun DirectionGuidanceIcon(instruction: NavigationInstruction?) {
    if (instruction == null) return
    Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(8.dp)) {
        Box(contentAlignment = Alignment.Center) {
            Box(modifier = Modifier.size(48.dp).clip(CircleShape).background(AppColor.AccentGreen.copy(alpha = 0.3f)))
            Box(modifier = Modifier.size(36.dp).clip(CircleShape).background(AppColor.AccentGreen), contentAlignment = Alignment.Center) {
                Icon(instructionIcon(instruction), null, tint = Color.White, modifier = Modifier.size(18.dp))
            }
        }
        Text(
            instruction.description,
            fontSize = 14.sp,
            fontWeight = FontWeight.SemiBold,
            color = Color.White,
            modifier =
                Modifier.clip(RoundedCornerShape(16.dp))
                    .background(AppColor.CardBackground.copy(alpha = 0.9f))
                    .padding(horizontal = 12.dp, vertical = 8.dp),
        )
    }
}

// MARK: - Status banner (compact + expandable), matching iOS NavigationStatusView

@Composable
private fun NavigationStatusBanner(
    navState: com.multiset.wearable.vps.navigation.NavigationState,
    onStopNavigation: () -> Unit,
) {
    var expanded by remember { mutableStateOf(false) }
    val transition = rememberInfiniteTransition(label = "navPulse")
    val pulseAlpha by
        transition.animateFloat(
            initialValue = 0.3f,
            targetValue = 0.6f,
            animationSpec = infiniteRepeatable(tween(900), RepeatMode.Reverse),
            label = "pulse",
        )

    Column(
        modifier =
            Modifier.fillMaxWidth()
                .padding(horizontal = 16.dp)
                .clip(RoundedCornerShape(20.dp))
                .background(AppColor.CardBackground),
    ) {
        Row(
            modifier =
                Modifier.fillMaxWidth().clickable { expanded = !expanded }.padding(horizontal = 16.dp, vertical = 12.dp),
            verticalAlignment = Alignment.CenterVertically,
            horizontalArrangement = Arrangement.spacedBy(12.dp),
        ) {
            Box(contentAlignment = Alignment.Center) {
                Box(modifier = Modifier.size(40.dp).clip(CircleShape).background(AppColor.AccentGreen.copy(alpha = pulseAlpha)))
                Box(modifier = Modifier.size(28.dp).clip(CircleShape).background(AppColor.AccentGreen), contentAlignment = Alignment.Center) {
                    navState.currentInstruction?.let {
                        Icon(instructionIcon(it), null, tint = Color.White, modifier = Modifier.size(14.dp))
                    }
                }
            }
            Column(modifier = Modifier.weight(1f)) {
                navState.destination?.let {
                    Text(it.name, fontSize = 15.sp, fontWeight = FontWeight.SemiBold, color = AppColor.TextPrimary)
                }
                Text("%.1f m remaining".format(navState.remainingDistance), fontSize = 12.sp, color = AppColor.TextSecondary)
            }
            navState.currentInstruction?.let {
                Text(
                    it.description,
                    fontSize = 13.sp,
                    fontWeight = FontWeight.Medium,
                    color = AppColor.AccentGreen,
                    modifier =
                        Modifier.clip(RoundedCornerShape(12.dp))
                            .background(AppColor.AccentGreen.copy(alpha = 0.15f))
                            .padding(horizontal = 10.dp, vertical = 6.dp),
                )
            }
            Icon(
                if (expanded) Icons.Default.KeyboardArrowUp else Icons.Default.KeyboardArrowDown,
                null,
                tint = AppColor.TextSecondary,
                modifier = Modifier.size(16.dp),
            )
        }

        AnimatedVisibility(visible = expanded) {
            Column(modifier = Modifier.padding(horizontal = 16.dp).padding(bottom = 16.dp), verticalArrangement = Arrangement.spacedBy(16.dp)) {
                HorizontalDivider(color = Color.White.copy(alpha = 0.1f))
                Row(modifier = Modifier.fillMaxWidth(), verticalAlignment = Alignment.CenterVertically) {
                    Text("Progress", fontSize = 13.sp, color = AppColor.TextSecondary)
                    Spacer(modifier = Modifier.weight(1f))
                    Text(
                        "${navState.currentWaypointIndex + 1} of ${navState.totalWaypoints} waypoints",
                        fontSize = 13.sp,
                        fontWeight = FontWeight.Medium,
                        color = AppColor.TextPrimary,
                    )
                }
                val progress =
                    if (navState.totalWaypoints > 0)
                        (navState.currentWaypointIndex + 1).toFloat() / navState.totalWaypoints
                    else 0f
                LinearProgressIndicator(
                    progress = { progress },
                    color = AppColor.AccentGreen,
                    trackColor = Color.White.copy(alpha = 0.1f),
                    modifier = Modifier.fillMaxWidth().height(6.dp).clip(RoundedCornerShape(3.dp)),
                )
                Button(
                    onClick = onStopNavigation,
                    colors = ButtonDefaults.buttonColors(containerColor = AppColor.Red),
                    shape = RoundedCornerShape(12.dp),
                    modifier = Modifier.fillMaxWidth().height(46.dp),
                ) {
                    Icon(Icons.Default.Close, null, tint = Color.White, modifier = Modifier.size(18.dp))
                    Spacer(modifier = Modifier.width(8.dp))
                    Text("Stop Navigation", fontSize = 15.sp, fontWeight = FontWeight.SemiBold, color = Color.White)
                }
            }
        }
    }
}

// MARK: - POI list sheet

@Composable
private fun POIListSheet(
    pois: List<NavigationPOI>,
    userPosition: NavPosition?,
    isLocalized: Boolean,
    onSelect: (Int) -> Unit,
    onDismiss: () -> Unit,
) {
    val sorted =
        remember(pois, userPosition) {
            if (userPosition != null) pois.sortedBy { userPosition.distance2D(it.position) } else pois
        }
    var showToast by remember { mutableStateOf(false) }
    LaunchedEffect(showToast) {
        if (showToast) {
            kotlinx.coroutines.delay(2500)
            showToast = false
        }
    }
    Dialog(onDismissRequest = onDismiss, properties = DialogProperties(usePlatformDefaultWidth = false)) {
        Box(modifier = Modifier.fillMaxSize().background(Color.Black.copy(alpha = 0.5f)).clickable { onDismiss() }) {
            Column(
                modifier =
                    Modifier.align(Alignment.BottomCenter)
                        .fillMaxWidth()
                        .fillMaxHeight(0.7f)
                        .clip(RoundedCornerShape(topStart = 24.dp, topEnd = 24.dp))
                        .background(AppColor.DarkBackground)
                        .clickable(enabled = false) {},
            ) {
                Box(
                    modifier =
                        Modifier.align(Alignment.CenterHorizontally)
                            .padding(top = 12.dp, bottom = 8.dp)
                            .width(36.dp)
                            .height(5.dp)
                            .clip(RoundedCornerShape(50))
                            .background(Color.White.copy(alpha = 0.3f))
                )
                Row(
                    modifier = Modifier.fillMaxWidth().padding(horizontal = 20.dp, vertical = 8.dp),
                    verticalAlignment = Alignment.CenterVertically,
                ) {
                    Column(modifier = Modifier.weight(1f)) {
                        Text("Navigate to", fontSize = 24.sp, fontWeight = FontWeight.Bold, color = AppColor.TextPrimary)
                        Text("${pois.size} destinations available", fontSize = 14.sp, color = AppColor.TextSecondary)
                    }
                    Icon(
                        Icons.Default.Close,
                        "Close",
                        tint = AppColor.TextSecondary,
                        modifier = Modifier.size(28.dp).clickable { onDismiss() },
                    )
                }
                LazyColumn(
                    modifier = Modifier.fillMaxWidth().padding(horizontal = 20.dp),
                    verticalArrangement = Arrangement.spacedBy(12.dp),
                ) {
                    items(sorted) { poi ->
                        val distance = userPosition?.distance2D(poi.position)
                        POICard(
                            poi = poi,
                            distance = distance,
                            onTap = { if (isLocalized) onSelect(poi.id) else showToast = true },
                        )
                    }
                }
            }

            // Toast: prompt to localize first (matches iOS).
            AnimatedVisibility(
                visible = showToast,
                modifier = Modifier.align(Alignment.TopCenter).statusBarsPadding().padding(top = 80.dp),
            ) {
                Row(
                    modifier =
                        Modifier.clip(RoundedCornerShape(25.dp))
                            .background(Color.Black.copy(alpha = 0.85f))
                            .padding(horizontal = 20.dp, vertical = 14.dp),
                    verticalAlignment = Alignment.CenterVertically,
                    horizontalArrangement = Arrangement.spacedBy(10.dp),
                ) {
                    Icon(Icons.Default.MyLocation, null, tint = AppColor.Yellow, modifier = Modifier.size(16.dp))
                    Text("Localize first to start Navigation", color = Color.White, fontSize = 14.sp, fontWeight = FontWeight.Medium)
                }
            }
        }
    }
}

@Composable
private fun POICard(poi: NavigationPOI, distance: Float?, onTap: () -> Unit) {
    val color = poiTypeColor(poi.type)
    Row(
        modifier =
            Modifier.fillMaxWidth().clip(RoundedCornerShape(16.dp)).background(AppColor.CardBackground).clickable { onTap() }.padding(16.dp),
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.spacedBy(16.dp),
    ) {
        Box(
            modifier = Modifier.size(50.dp).clip(CircleShape).background(color.copy(alpha = 0.15f)),
            contentAlignment = Alignment.Center,
        ) {
            Icon(poiTypeIcon(poi.type), null, tint = color, modifier = Modifier.size(20.dp))
        }
        Column(modifier = Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(4.dp)) {
            Text(poi.name, fontSize = 17.sp, fontWeight = FontWeight.SemiBold, color = AppColor.TextPrimary)
            Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                Text(poi.type, fontSize = 13.sp, color = AppColor.TextSecondary)
                if (distance != null) {
                    Text("•", color = AppColor.TextSecondary, fontSize = 13.sp)
                    Text("%.1f m".format(distance), fontSize = 13.sp, fontWeight = FontWeight.Medium, color = AppColor.AccentBlue)
                }
            }
        }
        Icon(Icons.Default.ChevronRight, null, tint = AppColor.TextSecondary, modifier = Modifier.size(14.dp))
    }
}

// MARK: - Icon / color mapping

internal fun instructionIcon(instruction: NavigationInstruction): ImageVector =
    when (instruction) {
        NavigationInstruction.MOVE_FORWARD -> Icons.Default.ArrowUpward
        NavigationInstruction.TURN_LEFT -> Icons.Default.TurnLeft
        NavigationInstruction.TURN_RIGHT -> Icons.Default.TurnRight
        NavigationInstruction.SLIGHT_LEFT -> Icons.Default.TurnSlightLeft
        NavigationInstruction.SLIGHT_RIGHT -> Icons.Default.TurnSlightRight
        NavigationInstruction.TURN_AROUND -> Icons.Default.UTurnLeft
        NavigationInstruction.DESTINATION_REACHED -> Icons.Default.CheckCircle
        NavigationInstruction.NAVIGATION_STARTED -> Icons.Default.Navigation
        NavigationInstruction.RECALCULATING -> Icons.Default.Refresh
    }

internal fun poiTypeIcon(type: String): ImageVector =
    when (type.lowercase()) {
        "room" -> Icons.Default.MeetingRoom
        "foodarea" -> Icons.Default.Restaurant
        "exit" -> Icons.Default.DirectionsWalk
        "information" -> Icons.Default.Info
        else -> Icons.Default.Place
    }

internal fun poiTypeColor(type: String): Color =
    when (type.lowercase()) {
        "room" -> AppColor.AccentBlue
        "foodarea" -> AppColor.AccentGreen
        "exit" -> AppColor.AccentPurple
        "information" -> AppColor.Yellow
        else -> AppColor.TextSecondary
    }
