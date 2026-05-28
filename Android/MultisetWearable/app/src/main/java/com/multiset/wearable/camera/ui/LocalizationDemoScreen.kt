/*
Copyright (c) 2026 MultiSet AI. All rights reserved.
Licensed under the MultiSet License. You may not use this file except in compliance with the License. and you can't re-distribute this file without a prior notice
For license details, visit www.multiset.ai.
Redistribution in source or binary forms must retain this notice.
*/

// LocalizationDemoScreen - Live-stream localization demo, mirroring the iOS
// LocalizationDemoView: a landing page, then a full-screen camera preview with a Localize
// button and a sliding pose result panel.

package com.multiset.wearable.vps.ui

import androidx.activity.ComponentActivity
import androidx.activity.compose.LocalActivity
import androidx.compose.animation.AnimatedVisibility
import androidx.compose.animation.core.animateFloatAsState
import androidx.compose.animation.fadeIn
import androidx.compose.animation.fadeOut
import androidx.compose.animation.slideInVertically
import androidx.compose.animation.slideOutVertically
import androidx.compose.foundation.Image
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
import androidx.compose.material.icons.filled.CameraAlt
import androidx.compose.material.icons.filled.CheckCircle
import androidx.compose.material.icons.filled.ChevronLeft
import androidx.compose.material.icons.filled.Close
import androidx.compose.material.icons.filled.HourglassEmpty
import androidx.compose.material.icons.filled.LocationOn
import androidx.compose.material.icons.filled.Map
import androidx.compose.material.icons.filled.MyLocation
import androidx.compose.material.icons.filled.Settings
import androidx.compose.material.icons.filled.SwapVert
import androidx.compose.material3.Button
import androidx.compose.material3.ButtonDefaults
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.Icon
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.DisposableEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.key
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.draw.scale
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.asImageBitmap
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.res.painterResource
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import androidx.lifecycle.viewmodel.compose.viewModel
import com.multiset.wearable.vps.R
import com.meta.wearable.dat.core.types.Permission
import com.meta.wearable.dat.core.types.PermissionStatus
import com.multiset.wearable.vps.localization.SDKConfig
import com.multiset.wearable.vps.stream.LocalizationStatus
import com.multiset.wearable.vps.stream.StreamSessionViewModel
import com.multiset.wearable.vps.stream.StreamingStatus
import com.multiset.wearable.vps.wearables.WearablesViewModel
import kotlin.math.sqrt
import kotlinx.coroutines.launch
import androidx.compose.runtime.rememberCoroutineScope

@Composable
fun LocalizationDemoScreen(
    wearablesViewModel: WearablesViewModel,
    onRequestWearablesPermission: suspend (Permission) -> PermissionStatus,
    onDismiss: () -> Unit,
    modifier: Modifier = Modifier,
) {
    val activity = LocalActivity.current as ComponentActivity
    val viewModel: StreamSessionViewModel =
        viewModel(
            key = "stream_localization",
            factory =
                StreamSessionViewModel.Factory(
                    application = activity.application,
                    wearablesViewModel = wearablesViewModel,
                    enableLocalization = true,
                ),
        )
    val uiState by viewModel.uiState.collectAsStateWithLifecycle()
    val scope = rememberCoroutineScope()
    var showSettings by remember { mutableStateOf(false) }
    var showDetails by remember { mutableStateOf(false) }

    DisposableEffect(Unit) { onDispose { viewModel.stopSession() } }

    Box(
        modifier =
            modifier.fillMaxSize().background(
                if (uiState.isStreaming) Color.Black.let { Brush.verticalGradient(listOf(it, it)) }
                else Brush.verticalGradient(listOf(AppColor.DarkBackground, AppColor.DarkBackgroundEnd))
            )
    ) {
        when (uiState.streamingStatus) {
            StreamingStatus.STOPPED ->
                LandingPage(
                    hasActiveDevice = uiState.hasActiveDevice,
                    onBack = onDismiss,
                    onSettings = { showSettings = true },
                    onStart = { scope.launch { viewModel.startSession(onRequestWearablesPermission) } },
                )
            StreamingStatus.WAITING ->
                WaitingPage(onCancel = { viewModel.stopSession() })
            StreamingStatus.STREAMING ->
                StreamingPage(
                    viewModel = viewModel,
                    onClose = { viewModel.stopSession() },
                    onSettings = { showSettings = true },
                    onDetails = { showDetails = true },
                )
        }
    }

    if (showSettings) {
        SettingsDialog(onDismiss = { showSettings = false })
    }
    if (showDetails && uiState.localizationResult != null) {
        PhotoPreviewSheet(
            photo = uiState.capturedPhoto,
            result = uiState.localizationResult!!,
            onDismiss = { showDetails = false },
        )
    }
}

// MARK: - Landing

@Composable
private fun LandingPage(
    hasActiveDevice: Boolean,
    onBack: () -> Unit,
    onSettings: () -> Unit,
    onStart: () -> Unit,
) {
    Column(
        modifier = Modifier.fillMaxSize().statusBarsPadding().navigationBarsPadding().padding(horizontal = 24.dp),
        horizontalAlignment = Alignment.CenterHorizontally,
    ) {
        DemoTopBar(onBack = onBack, onSettings = onSettings)

        Spacer(modifier = Modifier.weight(1f))

        Box(
            modifier = Modifier.size(80.dp).clip(CircleShape).background(AppColor.AccentBlue.copy(alpha = 0.15f)),
            contentAlignment = Alignment.Center,
        ) {
            Icon(Icons.Default.MyLocation, null, tint = AppColor.AccentBlue, modifier = Modifier.size(36.dp))
        }
        Spacer(modifier = Modifier.height(10.dp))
        Text("Localization", fontSize = 28.sp, fontWeight = FontWeight.Bold, color = AppColor.TextPrimary)
        Text("Visual positioning with Ray-Ban Meta", fontSize = 14.sp, color = AppColor.TextSecondary)
        Spacer(modifier = Modifier.height(4.dp))
        Text(
            "Capture images from your glasses camera and get precise position and orientation data.",
            fontSize = 13.sp,
            color = AppColor.TextSecondary.copy(alpha = 0.8f),
            textAlign = TextAlign.Center,
            modifier = Modifier.padding(horizontal = 8.dp),
        )

        Spacer(modifier = Modifier.height(16.dp))

        // Status chips: device readiness + map code (matches iOS status row)
        Row(
            horizontalArrangement = Arrangement.spacedBy(12.dp),
            verticalAlignment = Alignment.CenterVertically,
        ) {
            val deviceColor = if (hasActiveDevice) AppColor.AccentGreen else AppColor.Yellow
            Row(
                verticalAlignment = Alignment.CenterVertically,
                horizontalArrangement = Arrangement.spacedBy(6.dp),
                modifier =
                    Modifier.clip(RoundedCornerShape(50))
                        .background(deviceColor.copy(alpha = 0.15f))
                        .padding(horizontal = 12.dp, vertical = 8.dp),
            ) {
                Icon(
                    if (hasActiveDevice) Icons.Default.CheckCircle else Icons.Default.HourglassEmpty,
                    null,
                    tint = deviceColor,
                    modifier = Modifier.size(14.dp),
                )
                Text(
                    if (hasActiveDevice) "Device Ready" else "Waiting...",
                    color = deviceColor,
                    fontSize = 12.sp,
                    fontWeight = FontWeight.Medium,
                )
            }
            if (SDKConfig.MAP_CODE.isNotEmpty() || SDKConfig.MAP_SET_CODE.isNotEmpty()) {
                Row(
                    verticalAlignment = Alignment.CenterVertically,
                    horizontalArrangement = Arrangement.spacedBy(6.dp),
                    modifier =
                        Modifier.clip(RoundedCornerShape(50))
                            .background(AppColor.AccentPurple.copy(alpha = 0.15f))
                            .padding(horizontal = 12.dp, vertical = 8.dp),
                ) {
                    Icon(Icons.Default.Map, null, tint = AppColor.AccentPurple, modifier = Modifier.size(14.dp))
                    Text(
                        SDKConfig.MAP_CODE.ifEmpty { SDKConfig.MAP_SET_CODE },
                        color = AppColor.AccentPurple,
                        fontSize = 12.sp,
                        fontFamily = FontFamily.Monospace,
                    )
                }
            }
        }

        Spacer(modifier = Modifier.height(20.dp))

        HowItWorksCard(
            steps =
                listOf(
                    Triple(Icons.Default.CameraAlt, AppColor.AccentBlue, "Capture" to "Take photo"),
                    Triple(Icons.Default.SwapVert, AppColor.AccentPurple, "Process" to "Send to API"),
                    Triple(Icons.Default.LocationOn, AppColor.AccentGreen, "Localize" to "Get position"),
                )
        )

        Spacer(modifier = Modifier.weight(1f))

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
            Icon(Icons.Default.MyLocation, null, modifier = Modifier.size(20.dp), tint = Color.White)
            Spacer(modifier = Modifier.width(10.dp))
            Text("Open Localization", fontSize = 17.sp, fontWeight = FontWeight.SemiBold, color = Color.White)
        }
        Spacer(modifier = Modifier.height(8.dp))
        Text(
            if (hasActiveDevice) "Starts camera stream for localization testing"
            else "Waiting for glasses to become active...",
            fontSize = 11.sp,
            color = AppColor.TextSecondary,
        )
        Spacer(modifier = Modifier.height(28.dp))
    }
}

// MARK: - Waiting

@Composable
private fun WaitingPage(onCancel: () -> Unit) {
    Column(
        modifier = Modifier.fillMaxSize().navigationBarsPadding(),
        horizontalAlignment = Alignment.CenterHorizontally,
        verticalArrangement = Arrangement.Center,
    ) {
        CircularProgressIndicator(color = AppColor.AccentBlue)
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

// MARK: - Streaming

@Composable
private fun StreamingPage(
    viewModel: StreamSessionViewModel,
    onClose: () -> Unit,
    onSettings: () -> Unit,
    onDetails: () -> Unit,
) {
    val uiState by viewModel.uiState.collectAsStateWithLifecycle()

    Box(modifier = Modifier.fillMaxSize()) {
        val frame = uiState.videoFrame
        if (frame != null && uiState.hasReceivedFirstFrame) {
            key(uiState.videoFrameCount) {
                Image(
                    bitmap = frame.asImageBitmap(),
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

        // Top overlay
        Row(
            modifier = Modifier.fillMaxWidth().statusBarsPadding().padding(16.dp),
            horizontalArrangement = Arrangement.SpaceBetween,
        ) {
            OverlayCircleButton(Icons.Default.Close, "Close", onClose)
            OverlayCircleButton(Icons.Default.Settings, "Settings", onSettings)
        }

        // Bottom: result panel + localize button
        Column(
            modifier = Modifier.align(Alignment.BottomCenter).fillMaxWidth().navigationBarsPadding(),
            horizontalAlignment = Alignment.CenterHorizontally,
        ) {
            AnimatedVisibility(
                visible =
                    uiState.localizationStatus == LocalizationStatus.SUCCESS ||
                        uiState.localizationStatus == LocalizationStatus.FAILURE,
                enter = slideInVertically { it } + fadeIn(),
                exit = slideOutVertically { it } + fadeOut(),
            ) {
                ResultPanel(
                    success = uiState.localizationStatus == LocalizationStatus.SUCCESS,
                    result = uiState.localizationResult,
                    onDetails = onDetails,
                    modifier = Modifier.padding(horizontal = 16.dp, vertical = 8.dp),
                )
            }

            LocalizeButton(isLocalizing = uiState.isLocalizing, onClick = { viewModel.localize() })
            Spacer(modifier = Modifier.height(40.dp))
        }
    }
}

@Composable
private fun ResultPanel(
    success: Boolean,
    result: com.multiset.wearable.vps.localization.LocalizationResult?,
    onDetails: () -> Unit,
    modifier: Modifier = Modifier,
) {
    Column(
        modifier =
            modifier
                .fillMaxWidth()
                .clip(RoundedCornerShape(16.dp))
                .background(AppColor.CardBackground.copy(alpha = 0.95f))
                .padding(16.dp),
        verticalArrangement = Arrangement.spacedBy(12.dp),
    ) {
        Row(verticalAlignment = Alignment.CenterVertically) {
            Icon(
                imageVector = if (success) Icons.Default.CheckCircle else Icons.Default.Close,
                contentDescription = null,
                tint = if (success) AppColor.AccentGreen else AppColor.AccentRed,
                modifier = Modifier.size(18.dp),
            )
            Spacer(modifier = Modifier.width(8.dp))
            Text(
                if (success) "Localized" else "Not Localized",
                color = AppColor.TextPrimary,
                fontSize = 16.sp,
                fontWeight = FontWeight.SemiBold,
            )
            Spacer(modifier = Modifier.weight(1f))
            if (success) {
                Text(
                    "Details",
                    color = AppColor.AccentBlue,
                    fontSize = 13.sp,
                    fontWeight = FontWeight.Medium,
                    modifier = Modifier.clickable { onDetails() },
                )
            }
        }

        val p = result?.posePosition
        if (success && p != null) {
            HorizontalDivider(color = AppColor.TextSecondary.copy(alpha = 0.3f))
            val distance = sqrt(p.x * p.x + p.y * p.y + p.z * p.z)
            ResultRow("Position", String.format("X: %.2f  Y: %.2f  Z: %.2f", p.x, p.y, p.z), AppColor.TextPrimary, mono = true)
            ResultRow("Distance", String.format("%.2f m from origin", distance), AppColor.AccentBlue)
            result.confidence?.let { c ->
                val color =
                    when {
                        c >= 0.7f -> AppColor.AccentGreen
                        c >= 0.4f -> AppColor.Yellow
                        else -> AppColor.AccentRed
                    }
                ResultRow("Confidence", String.format("%.0f%%", c * 100), color)
            }
        }
    }
}

@Composable
private fun ResultRow(label: String, value: String, valueColor: Color, mono: Boolean = false) {
    Row(modifier = Modifier.fillMaxWidth(), verticalAlignment = Alignment.CenterVertically) {
        Text(label, color = AppColor.TextSecondary, fontSize = 13.sp, fontWeight = FontWeight.Medium)
        Spacer(modifier = Modifier.weight(1f))
        Text(
            value,
            color = valueColor,
            fontSize = 13.sp,
            fontWeight = FontWeight.Medium,
            fontFamily = if (mono) FontFamily.Monospace else FontFamily.Default,
        )
    }
}

// MARK: - Localize button (circular shutter, matching iOS LocalizeButton)

@Composable
internal fun LocalizeButton(isLocalizing: Boolean, onClick: () -> Unit) {
    val scale by animateFloatAsState(if (isLocalizing) 0.95f else 1f, label = "localizeScale")
    Box(
        modifier =
            Modifier.size(72.dp).scale(scale).clip(CircleShape).clickable(enabled = !isLocalizing) {
                onClick()
            },
        contentAlignment = Alignment.Center,
    ) {
        Image(
            painter = painterResource(id = R.drawable.localization_button),
            contentDescription = null,
            modifier = Modifier.size(72.dp),
        )
        if (isLocalizing) {
            CircularProgressIndicator(color = Color.White, modifier = Modifier.size(36.dp), strokeWidth = 3.dp)
        }
    }
}

// MARK: - Shared bits

@Composable
internal fun DemoTopBar(onBack: () -> Unit, onSettings: (() -> Unit)? = null) {
    Row(
        modifier = Modifier.fillMaxWidth().padding(top = 16.dp),
        horizontalArrangement = Arrangement.SpaceBetween,
        verticalAlignment = Alignment.CenterVertically,
    ) {
        Row(
            verticalAlignment = Alignment.CenterVertically,
            horizontalArrangement = Arrangement.spacedBy(6.dp),
            modifier =
                Modifier.clip(RoundedCornerShape(50))
                    .background(AppColor.CardBackground)
                    .clickable { onBack() }
                    .padding(horizontal = 12.dp, vertical = 6.dp),
        ) {
            Icon(Icons.Default.ChevronLeft, null, tint = AppColor.TextPrimary, modifier = Modifier.size(18.dp))
            Text("Back", color = AppColor.TextPrimary, fontSize = 14.sp, fontWeight = FontWeight.Medium)
        }
        if (onSettings != null) {
            Icon(
                Icons.Default.Settings,
                "Settings",
                tint = AppColor.TextSecondary,
                modifier = Modifier.clickable { onSettings() }.padding(4.dp).size(22.dp),
            )
        }
    }
}

@Composable
internal fun OverlayCircleButton(icon: ImageVector, contentDescription: String, onClick: () -> Unit) {
    Box(
        modifier =
            Modifier.size(40.dp).clip(CircleShape).background(Color.Black.copy(alpha = 0.5f)).clickable { onClick() },
        contentAlignment = Alignment.Center,
    ) {
        Icon(icon, contentDescription, tint = Color.White, modifier = Modifier.size(18.dp))
    }
}

@Composable
internal fun HowItWorksCard(steps: List<Triple<ImageVector, Color, Pair<String, String>>>) {
    Column(
        modifier =
            Modifier.fillMaxWidth().clip(RoundedCornerShape(16.dp)).background(AppColor.CardBackground).padding(16.dp),
        verticalArrangement = Arrangement.spacedBy(12.dp),
    ) {
        Text("How it works", color = AppColor.TextSecondary, fontSize = 13.sp, fontWeight = FontWeight.SemiBold)
        Row(horizontalArrangement = Arrangement.spacedBy(12.dp), modifier = Modifier.fillMaxWidth()) {
            steps.forEach { (icon, color, text) ->
                Column(
                    modifier = Modifier.weight(1f),
                    horizontalAlignment = Alignment.CenterHorizontally,
                    verticalArrangement = Arrangement.spacedBy(6.dp),
                ) {
                    Box(
                        modifier = Modifier.size(40.dp).clip(CircleShape).background(color.copy(alpha = 0.15f)),
                        contentAlignment = Alignment.Center,
                    ) {
                        Icon(icon, null, tint = color, modifier = Modifier.size(16.dp))
                    }
                    Text(text.first, color = AppColor.TextPrimary, fontSize = 12.sp, fontWeight = FontWeight.SemiBold)
                    Text(text.second, color = AppColor.TextSecondary, fontSize = 10.sp)
                }
            }
        }
    }
}
