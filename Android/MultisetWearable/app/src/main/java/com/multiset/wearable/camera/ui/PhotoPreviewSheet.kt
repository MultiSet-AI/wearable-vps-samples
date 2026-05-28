/*
Copyright (c) 2026 MultiSet AI. All rights reserved.
Licensed under the MultiSet License. You may not use this file except in compliance with the License. and you can't re-distribute this file without a prior notice
For license details, visit www.multiset.ai.
Redistribution in source or binary forms must retain this notice.
*/

// PhotoPreviewSheet - Full-screen localization result detail view, mirroring the iOS
// PhotoPreviewView: the captured photo, a status card with distance-from-origin, and a
// details card with colour-coded position/rotation and the map code.

package com.multiset.wearable.vps.ui

import android.graphics.Bitmap
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
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.statusBarsPadding
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.CheckCircle
import androidx.compose.material.icons.filled.Close
import androidx.compose.material.icons.filled.LocationOn
import androidx.compose.material.icons.filled.Map
import androidx.compose.material3.Icon
import androidx.compose.material3.Surface
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.asImageBitmap
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.compose.ui.window.Dialog
import androidx.compose.ui.window.DialogProperties
import com.multiset.wearable.vps.localization.LocalizationResult
import com.multiset.wearable.vps.localization.SDKConfig
import kotlin.math.sqrt

@Composable
fun PhotoPreviewSheet(
    photo: Bitmap?,
    result: LocalizationResult,
    onDismiss: () -> Unit,
) {
    val success = result.poseFound

    Dialog(
        onDismissRequest = onDismiss,
        properties = DialogProperties(usePlatformDefaultWidth = false),
    ) {
        Surface(modifier = Modifier.fillMaxSize(), color = AppColor.DarkBackground) {
            Column(modifier = Modifier.fillMaxSize().statusBarsPadding()) {
                // Header
                Row(
                    modifier = Modifier.fillMaxWidth().padding(horizontal = 20.dp, vertical = 16.dp),
                    horizontalArrangement = Arrangement.SpaceBetween,
                    verticalAlignment = Alignment.CenterVertically,
                ) {
                    Text(
                        "Localization Result",
                        fontSize = 20.sp,
                        fontWeight = FontWeight.Bold,
                        color = AppColor.TextPrimary,
                    )
                    Icon(
                        Icons.Default.Close,
                        "Close",
                        tint = AppColor.TextSecondary,
                        modifier = Modifier.size(28.dp).clickable { onDismiss() },
                    )
                }

                Column(
                    modifier =
                        Modifier.fillMaxWidth()
                            .verticalScroll(rememberScrollState())
                            .padding(horizontal = 20.dp)
                            .padding(bottom = 32.dp),
                    horizontalAlignment = Alignment.CenterHorizontally,
                ) {
                    // Captured photo
                    if (photo != null) {
                        Image(
                            bitmap = photo.asImageBitmap(),
                            contentDescription = "Captured photo",
                            modifier =
                                Modifier.fillMaxWidth().heightIn(max = 280.dp).clip(RoundedCornerShape(16.dp)),
                            contentScale = ContentScale.Fit,
                        )
                        Spacer(modifier = Modifier.size(24.dp))
                    }

                    // Status card
                    Column(
                        modifier =
                            Modifier.fillMaxWidth().clip(RoundedCornerShape(20.dp)).background(AppColor.CardBackground).padding(20.dp),
                        verticalArrangement = Arrangement.spacedBy(16.dp),
                    ) {
                        Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(12.dp)) {
                            Box(
                                modifier =
                                    Modifier.size(56.dp)
                                        .clip(CircleShape)
                                        .background((if (success) AppColor.AccentGreen else AppColor.Yellow).copy(alpha = 0.15f)),
                                contentAlignment = Alignment.Center,
                            ) {
                                Icon(
                                    if (success) Icons.Default.CheckCircle else Icons.Default.Close,
                                    null,
                                    tint = if (success) AppColor.AccentGreen else AppColor.Yellow,
                                    modifier = Modifier.size(28.dp),
                                )
                            }
                            Column(verticalArrangement = Arrangement.spacedBy(4.dp)) {
                                Text(
                                    if (success) "Localization Successful" else "Localization Failed",
                                    fontSize = 18.sp,
                                    fontWeight = FontWeight.SemiBold,
                                    color = AppColor.TextPrimary,
                                )
                                if (success) {
                                    result.confidence?.let {
                                        Text("%.0f%% confidence".format(it * 100), fontSize = 14.sp, color = AppColor.AccentGreen)
                                    }
                                } else {
                                    Text("Pose not found in mapped area", fontSize = 14.sp, color = AppColor.TextSecondary)
                                }
                            }
                        }

                        val statusPos = result.posePosition
                        if (success && statusPos != null) {
                            val distance = sqrt(statusPos.x * statusPos.x + statusPos.y * statusPos.y + statusPos.z * statusPos.z)
                            androidx.compose.material3.HorizontalDivider(color = Color.White.copy(alpha = 0.1f))
                            Row(verticalAlignment = Alignment.CenterVertically) {
                                Column(modifier = Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(4.dp)) {
                                    Text("Distance from Origin", fontSize = 13.sp, color = AppColor.TextSecondary)
                                    Text("%.2f m".format(distance), fontSize = 32.sp, fontWeight = FontWeight.Bold, color = AppColor.AccentGreen)
                                }
                                Icon(Icons.Default.LocationOn, null, tint = AppColor.AccentGreen.copy(alpha = 0.5f), modifier = Modifier.size(24.dp))
                            }
                        }
                    }

                    // Details card
                    val detailPos = result.posePosition
                    val detailRot = result.poseRotation
                    if (success && detailPos != null) {
                        Spacer(modifier = Modifier.size(24.dp))
                        Column(
                            modifier =
                                Modifier.fillMaxWidth().clip(RoundedCornerShape(20.dp)).background(AppColor.CardBackground).padding(20.dp),
                            verticalArrangement = Arrangement.spacedBy(16.dp),
                        ) {
                            Text("Position & Orientation", fontSize = 16.sp, fontWeight = FontWeight.SemiBold, color = AppColor.TextPrimary)

                            Text("POSITION", fontSize = 11.sp, fontWeight = FontWeight.Medium, color = AppColor.TextSecondary)
                            Row(horizontalArrangement = Arrangement.spacedBy(12.dp)) {
                                CoordinateChip("X", detailPos.x, AppColor.AccentBlue, Modifier.weight(1f))
                                CoordinateChip("Y", detailPos.y, AppColor.AccentGreen, Modifier.weight(1f))
                                CoordinateChip("Z", detailPos.z, AppColor.AccentPurple, Modifier.weight(1f))
                            }

                            if (detailRot != null) {
                                androidx.compose.material3.HorizontalDivider(color = Color.White.copy(alpha = 0.1f))

                                Text("ROTATION (QUATERNION)", fontSize = 11.sp, fontWeight = FontWeight.Medium, color = AppColor.TextSecondary)
                                Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                                    CoordinateChip("X", detailRot.x, AppColor.TextSecondary, Modifier.weight(1f))
                                    CoordinateChip("Y", detailRot.y, AppColor.TextSecondary, Modifier.weight(1f))
                                    CoordinateChip("Z", detailRot.z, AppColor.TextSecondary, Modifier.weight(1f))
                                    CoordinateChip("W", detailRot.w, AppColor.TextSecondary, Modifier.weight(1f))
                                }
                            }

                            val mapCode = SDKConfig.MAP_CODE.ifEmpty { SDKConfig.MAP_SET_CODE }
                            if (mapCode.isNotEmpty()) {
                                androidx.compose.material3.HorizontalDivider(color = Color.White.copy(alpha = 0.1f))
                                Row(verticalAlignment = Alignment.CenterVertically) {
                                    Column(modifier = Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(4.dp)) {
                                        Text("MAP CODE", fontSize = 11.sp, fontWeight = FontWeight.Medium, color = AppColor.TextSecondary)
                                        Text(mapCode, fontSize = 15.sp, fontWeight = FontWeight.Medium, fontFamily = FontFamily.Monospace, color = AppColor.TextPrimary)
                                    }
                                    Icon(Icons.Default.Map, null, tint = AppColor.TextSecondary.copy(alpha = 0.5f), modifier = Modifier.size(20.dp))
                                }
                            }
                        }
                    }
                }
            }
        }
    }
}

@Composable
private fun CoordinateChip(label: String, value: Float, color: Color, modifier: Modifier = Modifier) {
    Column(
        modifier = modifier.clip(RoundedCornerShape(10.dp)).background(color.copy(alpha = 0.1f)).padding(vertical = 10.dp),
        horizontalAlignment = Alignment.CenterHorizontally,
        verticalArrangement = Arrangement.spacedBy(4.dp),
    ) {
        Text(label, fontSize = 11.sp, fontWeight = FontWeight.SemiBold, color = color)
        Text("%.3f".format(value), fontSize = 14.sp, fontWeight = FontWeight.Medium, fontFamily = FontFamily.Monospace, color = AppColor.TextPrimary)
    }
}
