/*
Copyright (c) 2026 MultiSet AI. All rights reserved.
Licensed under the MultiSet License. You may not use this file except in compliance with the License. and you can't re-distribute this file without a prior notice
For license details, visit www.multiset.ai.
Redistribution in source or binary forms must retain this notice.
*/

// FeatureSelectionScreen - Post-connection landing that lets the user choose a demo
// experience. Mirrors the iOS FeatureSelectionView.

package com.multiset.wearable.vps.ui

import androidx.activity.compose.LocalActivity
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
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.statusBarsPadding
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.ChevronRight
import androidx.compose.material.icons.filled.Group
import androidx.compose.material.icons.filled.LinkOff
import androidx.compose.material.icons.filled.MyLocation
import androidx.compose.material.icons.filled.Navigation
import androidx.compose.material.icons.filled.Settings
import androidx.compose.material.icons.filled.Warning
import androidx.compose.material3.DropdownMenu
import androidx.compose.material3.DropdownMenuItem
import androidx.compose.material3.Icon
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.alpha
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.multiset.wearable.vps.localization.SDKConfig
import com.multiset.wearable.vps.wearables.WearablesViewModel

/** Demo experiences available after the glasses connect (mirrors iOS AppFeature). */
enum class AppFeature(
    val title: String,
    val description: String,
    val icon: ImageVector,
    val accent: Color,
    val requiresConfiguration: Boolean,
    val enabled: Boolean,
) {
    LOCALIZATION(
        "Localization Demo",
        "Capture images and test positioning with real-time pose data",
        Icons.Default.MyLocation,
        AppColor.AccentBlue,
        requiresConfiguration = true,
        enabled = true,
    ),

    NAVIGATION(
        "Navigation Demo",
        "Full navigation with audio-guided turn-by-turn directions",
        Icons.Default.Navigation,
        AppColor.AccentGreen,
        requiresConfiguration = true,
        enabled = true,
    ),

}

@Composable
fun FeatureSelectionScreen(
    viewModel: WearablesViewModel,
    onSelectFeature: (AppFeature) -> Unit,
    modifier: Modifier = Modifier,
) {
    val activity = LocalActivity.current
    var showSettings by remember { mutableStateOf(false) }
    var disconnectExpanded by remember { mutableStateOf(false) }
    val isConfigured = SDKConfig.isConfigured()

    Box(
        modifier =
            modifier
                .fillMaxSize()
                .background(
                    Brush.verticalGradient(
                        listOf(AppColor.DarkBackground, AppColor.CardBackground)
                    )
                ),
    ) {
        Column(
            modifier = Modifier
                .fillMaxSize()
                .statusBarsPadding()
                .padding(horizontal = 24.dp),
            horizontalAlignment = Alignment.CenterHorizontally,
        ) {
            // Top bar
            Row(
                modifier = Modifier
                    .fillMaxWidth()
                    .padding(top = 16.dp),
                horizontalArrangement = Arrangement.SpaceBetween,
                verticalAlignment = Alignment.CenterVertically,
            ) {
                Box {
                    Row(
                        verticalAlignment = Alignment.CenterVertically,
                        horizontalArrangement = Arrangement.spacedBy(6.dp),
                        modifier =
                            Modifier
                                .clip(RoundedCornerShape(50))
                                .background(AppColor.AccentGreen.copy(alpha = 0.15f))
                                .clickable { disconnectExpanded = true }
                                .padding(horizontal = 12.dp, vertical = 6.dp),
                    ) {
                        Box(
                            modifier =
                                Modifier
                                    .size(8.dp)
                                    .clip(CircleShape)
                                    .background(AppColor.AccentGreen)
                        )
                        Text(
                            text = "Glasses Paired",
                            color = AppColor.AccentGreen,
                            fontSize = 13.sp,
                            fontWeight = FontWeight.Medium,
                        )
                    }
                    DropdownMenu(
                        expanded = disconnectExpanded,
                        onDismissRequest = { disconnectExpanded = false },
                    ) {
                        DropdownMenuItem(
                            text = {
                                Row(
                                    verticalAlignment = Alignment.CenterVertically,
                                    horizontalArrangement = Arrangement.spacedBy(8.dp),
                                ) {
                                    Icon(
                                        imageVector = Icons.Default.LinkOff,
                                        contentDescription = null,
                                        tint = AppColor.Red,
                                        modifier = Modifier.size(18.dp),
                                    )
                                    Text("Disconnect Glasses", color = AppColor.Red)
                                }
                            },
                            onClick = {
                                disconnectExpanded = false
                                activity?.let { viewModel.startUnregistration(it) }
                            },
                        )
                    }
                }

                Box(
                    modifier = Modifier
                        .clickable { showSettings = true }
                        .padding(8.dp),
                ) {
                    Icon(
                        imageVector = Icons.Default.Settings,
                        contentDescription = "Settings",
                        tint = AppColor.TextSecondary,
                        modifier = Modifier.size(22.dp),
                    )
                }
            }

            Spacer(modifier = Modifier.weight(1f))

            // Logo + title
            Box(
                modifier =
                    Modifier
                        .size(90.dp)
                        .clip(CircleShape)
                        .background(AppColor.DeepBlue.copy(alpha = 0.2f)),
                contentAlignment = Alignment.Center,
            ) {
                Icon(
                    imageVector = Icons.Default.MyLocation,
                    contentDescription = null,
                    tint = AppColor.AccentBlue,
                    modifier = Modifier.size(40.dp),
                )
            }
            Spacer(modifier = Modifier.height(12.dp))
            Text(
                text = "MultiSet Wearable VPS",
                fontSize = 28.sp,
                fontWeight = FontWeight.Bold,
                color = AppColor.TextPrimary,
            )
            Spacer(modifier = Modifier.height(4.dp))
            Text(
                text = "Choose an experience below",
                fontSize = 15.sp,
                color = AppColor.TextSecondary,
            )

            Spacer(modifier = Modifier.height(28.dp))

            // Feature cards
            Column(
                modifier = Modifier.fillMaxWidth(),
                verticalArrangement = Arrangement.spacedBy(14.dp),
            ) {
                AppFeature.values().forEach { feature ->
                    val disabled =
                        !feature.enabled || (feature.requiresConfiguration && !isConfigured)
                    FeatureCard(
                        feature = feature,
                        disabled = disabled,
                        onClick = { if (!disabled) onSelectFeature(feature) },
                    )
                }

                if (!isConfigured) {
                    ConfigWarningBanner(onSetup = { showSettings = true })
                }
            }

            Spacer(modifier = Modifier.weight(1f))

            Text(
                text = "Select an experience to begin",
                fontSize = 13.sp,
                color = AppColor.TextSecondary,
                modifier = Modifier.padding(bottom = 32.dp),
            )
        }

        if (showSettings) {
            SettingsDialog(onDismiss = { showSettings = false })
        }
    }
}

@Composable
private fun FeatureCard(
    feature: AppFeature,
    disabled: Boolean,
    onClick: () -> Unit,
    modifier: Modifier = Modifier,
) {
    Row(
        modifier =
            modifier
                .fillMaxWidth()
                .clip(RoundedCornerShape(16.dp))
                .background(AppColor.CardBackground)
                .clickable(enabled = !disabled, onClick = onClick)
                .alpha(if (disabled) 0.5f else 1f)
                .padding(16.dp),
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.spacedBy(16.dp),
    ) {
        Box(
            modifier =
                Modifier
                    .size(56.dp)
                    .clip(RoundedCornerShape(14.dp))
                    .background(feature.accent.copy(alpha = 0.15f)),
            contentAlignment = Alignment.Center,
        ) {
            Icon(
                imageVector = feature.icon,
                contentDescription = null,
                tint = feature.accent,
                modifier = Modifier.size(24.dp),
            )
        }

        Column(modifier = Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(4.dp)) {
            Text(
                text = feature.title,
                fontSize = 17.sp,
                fontWeight = FontWeight.SemiBold,
                color = AppColor.TextPrimary,
            )
            Text(
                text = feature.description,
                fontSize = 13.sp,
                color = AppColor.TextSecondary,
                maxLines = 2,
            )
        }

        Icon(
            imageVector = Icons.Default.ChevronRight,
            contentDescription = null,
            tint = AppColor.TextSecondary,
            modifier = Modifier.size(14.dp),
        )
    }
}

@Composable
private fun ConfigWarningBanner(onSetup: () -> Unit, modifier: Modifier = Modifier) {
    Row(
        modifier =
            modifier
                .fillMaxWidth()
                .clip(RoundedCornerShape(12.dp))
                .background(AppColor.Yellow.copy(alpha = 0.15f))
                .padding(14.dp),
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.spacedBy(10.dp),
    ) {
        Icon(
            imageVector = Icons.Default.Warning,
            contentDescription = null,
            tint = AppColor.Yellow,
            modifier = Modifier.size(16.dp),
        )
        Text(
            text = "Configure API credentials and map in settings first",
            fontSize = 13.sp,
            color = AppColor.TextSecondary,
            modifier = Modifier.weight(1f),
        )
        Text(
            text = "Setup",
            fontSize = 13.sp,
            fontWeight = FontWeight.SemiBold,
            color = AppColor.AccentBlue,
            modifier = Modifier.clickable { onSetup() },
        )
    }
}
