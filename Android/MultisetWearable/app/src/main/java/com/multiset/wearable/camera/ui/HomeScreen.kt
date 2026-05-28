/*
Copyright (c) 2026 MultiSet AI. All rights reserved.
Licensed under the MultiSet License. You may not use this file except in compliance with the License. and you can't re-distribute this file without a prior notice
For license details, visit www.multiset.ai.
Redistribution in source or binary forms must retain this notice.
*/

// HomeScreen - Multiset VPS Demo Entry Point
//
// This screen showcases the Multiset Visual Positioning System (VPS) SDK
// integration with Meta Ray-Ban Smart Glasses. Users can configure SDK
// settings and connect their glasses to start localizing in mapped areas.

package com.multiset.wearable.vps.ui

import androidx.activity.compose.LocalActivity
import androidx.compose.animation.animateColorAsState
import androidx.compose.animation.core.tween
import androidx.compose.foundation.Image
import androidx.compose.foundation.background
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
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.CheckCircle
import androidx.compose.material.icons.filled.Error
import androidx.compose.material.icons.filled.Headphones
import androidx.compose.material.icons.filled.LocationOn
import androidx.compose.material.icons.filled.Map
import androidx.compose.material.icons.filled.Settings
import androidx.compose.material.icons.filled.Visibility
import androidx.compose.material.icons.outlined.RemoveRedEye
import androidx.compose.material3.Card
import androidx.compose.material3.CardDefaults
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.Surface
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.res.painterResource
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.multiset.wearable.vps.R
import com.multiset.wearable.vps.localization.AuthManager
import com.multiset.wearable.vps.localization.SDKConfig
import com.multiset.wearable.vps.wearables.WearablesViewModel

// Color palette for the home screen
private val DarkBackground = Color(0xFF0D1117)
private val CardBackground = Color(0xFF161B22)
private val AccentBlue = Color(0xFF58A6FF)
private val AccentGreen = Color(0xFF3FB950)
private val AccentPurple = Color(0xFF8B5CF6)
private val TextPrimary = Color(0xFFF0F6FC)
private val TextSecondary = Color(0xFF8B949E)

@Composable
fun HomeScreen(
    viewModel: WearablesViewModel,
    modifier: Modifier = Modifier,
) {
    val scrollState = rememberScrollState()
    var showSettingsDialog by remember { mutableStateOf(false) }
    val activity = LocalActivity.current

    // Check SDK configuration status
    val isConfigured = SDKConfig.isConfigured()
    val hasValidToken = AuthManager.getInstance().hasValidToken()

    Box(
        modifier = modifier
            .fillMaxSize()
            .background(
                Brush.verticalGradient(
                    colors = listOf(
                        DarkBackground,
                        Color(0xFF0A0E14),
                    )
                )
            ),
    ) {
        Column(
            modifier = Modifier
                .fillMaxSize()
                .verticalScroll(scrollState)
                .statusBarsPadding()
                .navigationBarsPadding()
                .padding(horizontal = 24.dp),
            horizontalAlignment = Alignment.CenterHorizontally,
        ) {
            // Top bar with settings
            Row(
                modifier = Modifier
                    .fillMaxWidth()
                    .padding(top = 8.dp),
                horizontalArrangement = Arrangement.End,
            ) {
                IconButton(
                    onClick = { showSettingsDialog = true },
                ) {
                    Icon(
                        imageVector = Icons.Default.Settings,
                        contentDescription = "Settings",
                        tint = TextSecondary,
                        modifier = Modifier.size(24.dp),
                    )
                }
            }

            Spacer(modifier = Modifier.height(16.dp))

            // Logo and Title
            Image(
                painter = painterResource(id = R.drawable.multiset_rayban),
                contentDescription = "Multiset Logo",
                modifier = Modifier.size(100.dp),
            )

            Spacer(modifier = Modifier.height(20.dp))

            Text(
                text = "Multiset Wearable",
                fontSize = 32.sp,
                fontWeight = FontWeight.Bold,
                color = TextPrimary,
            )

            Text(
                text = "Visual Positioning System",
                fontSize = 18.sp,
                color = TextSecondary,
                modifier = Modifier.padding(top = 4.dp),
            )

            Spacer(modifier = Modifier.height(12.dp))

            // SDK Status Badge
            SDKStatusBadge(
                isConfigured = isConfigured,
                hasValidToken = hasValidToken,
            )

            Spacer(modifier = Modifier.height(32.dp))

            // Feature Cards
            Text(
                text = "What you can do",
                fontSize = 18.sp,
                fontWeight = FontWeight.SemiBold,
                color = TextPrimary,
                modifier = Modifier
                    .fillMaxWidth()
                    .padding(bottom = 16.dp),
            )

            FeatureCard(
                icon = Icons.Default.LocationOn,
                iconColor = AccentBlue,
                title = "Precise Localization",
                description = "Know exactly where you are in pre-mapped indoor spaces using your glasses camera",
            )

            Spacer(modifier = Modifier.height(12.dp))

            FeatureCard(
                icon = Icons.Default.Headphones,
                iconColor = AccentGreen,
                title = "Audio Feedback",
                description = "Hear localization results through your glasses speakers - hands-free navigation",
            )

            Spacer(modifier = Modifier.height(12.dp))

            FeatureCard(
                icon = Icons.Default.Map,
                iconColor = AccentPurple,
                title = "Map Integration",
                description = "Connect to your Multiset maps and mapsets for accurate positioning",
            )

            Spacer(modifier = Modifier.height(12.dp))

            // Map Configuration Status
            if (isConfigured) {
                MapConfigCard(
                    mapCode = SDKConfig.MAP_CODE,
                    mapSetCode = SDKConfig.MAP_SET_CODE,
                )
                Spacer(modifier = Modifier.height(24.dp))
            }

            Spacer(modifier = Modifier.weight(1f))

            // Connect Button Section
            Column(
                horizontalAlignment = Alignment.CenterHorizontally,
                modifier = Modifier.padding(bottom = 24.dp),
            ) {
                if (!isConfigured) {
                    Card(
                        colors = CardDefaults.cardColors(
                            containerColor = AppColor.Yellow.copy(alpha = 0.15f),
                        ),
                        shape = RoundedCornerShape(12.dp),
                        modifier = Modifier
                            .fillMaxWidth()
                            .padding(bottom = 16.dp),
                    ) {
                        Row(
                            modifier = Modifier.padding(16.dp),
                            verticalAlignment = Alignment.CenterVertically,
                        ) {
                            Icon(
                                imageVector = Icons.Default.Error,
                                contentDescription = null,
                                tint = AppColor.Yellow,
                                modifier = Modifier.size(24.dp),
                            )
                            Spacer(modifier = Modifier.width(12.dp))
                            Column {
                                Text(
                                    text = "Configuration Required",
                                    fontWeight = FontWeight.SemiBold,
                                    color = AppColor.Yellow,
                                    fontSize = 14.sp,
                                )
                                Text(
                                    text = "Tap Settings to configure your API credentials and map code",
                                    color = TextSecondary,
                                    fontSize = 12.sp,
                                )
                            }
                        }
                    }
                }

                Text(
                    text = "You'll be redirected to Meta AI app to confirm connection",
                    color = TextSecondary,
                    fontSize = 13.sp,
                    textAlign = TextAlign.Center,
                    modifier = Modifier.padding(bottom = 16.dp),
                )

                SwitchButton(
                    label = "Connect My Glasses",
                    onClick = { activity?.let { viewModel.startRegistration(it) } },
                    enabled = isConfigured && activity != null,
                )

                Spacer(modifier = Modifier.height(12.dp))

                Row(
                    verticalAlignment = Alignment.CenterVertically,
                    horizontalArrangement = Arrangement.Center,
                ) {
                    Icon(
                        imageVector = Icons.Outlined.RemoveRedEye,
                        contentDescription = null,
                        tint = TextSecondary,
                        modifier = Modifier.size(16.dp),
                    )
                    Spacer(modifier = Modifier.width(6.dp))
                    Text(
                        text = "Supports Ray-Ban Meta Smart Glasses",
                        color = TextSecondary,
                        fontSize = 12.sp,
                    )
                }
            }
        }

        // Settings Dialog
        if (showSettingsDialog) {
            SettingsDialog(
                onDismiss = { showSettingsDialog = false },
            )
        }
    }
}

@Composable
private fun SDKStatusBadge(
    isConfigured: Boolean,
    hasValidToken: Boolean,
    modifier: Modifier = Modifier,
) {
    val statusText = when {
        !isConfigured -> "Not Configured"
        hasValidToken -> "Ready"
        else -> "Configured"
    }

    val statusColor by animateColorAsState(
        targetValue = when {
            !isConfigured -> AppColor.Yellow
            hasValidToken -> AccentGreen
            else -> AccentBlue
        },
        animationSpec = tween(300),
        label = "statusColor",
    )

    Surface(
        shape = RoundedCornerShape(20.dp),
        color = statusColor.copy(alpha = 0.15f),
        modifier = modifier,
    ) {
        Row(
            modifier = Modifier.padding(horizontal = 16.dp, vertical = 8.dp),
            verticalAlignment = Alignment.CenterVertically,
            horizontalArrangement = Arrangement.spacedBy(8.dp),
        ) {
            Box(
                modifier = Modifier
                    .size(8.dp)
                    .clip(CircleShape)
                    .background(statusColor),
            )
            Text(
                text = statusText,
                color = statusColor,
                fontSize = 13.sp,
                fontWeight = FontWeight.Medium,
            )
        }
    }
}

@Composable
private fun FeatureCard(
    icon: ImageVector,
    iconColor: Color,
    title: String,
    description: String,
    modifier: Modifier = Modifier,
) {
    Card(
        colors = CardDefaults.cardColors(
            containerColor = CardBackground,
        ),
        shape = RoundedCornerShape(16.dp),
        modifier = modifier.fillMaxWidth(),
    ) {
        Row(
            modifier = Modifier
                .fillMaxWidth()
                .padding(16.dp),
            verticalAlignment = Alignment.Top,
        ) {
            Box(
                modifier = Modifier
                    .size(44.dp)
                    .clip(RoundedCornerShape(12.dp))
                    .background(iconColor.copy(alpha = 0.15f)),
                contentAlignment = Alignment.Center,
            ) {
                Icon(
                    imageVector = icon,
                    contentDescription = null,
                    tint = iconColor,
                    modifier = Modifier.size(24.dp),
                )
            }

            Spacer(modifier = Modifier.width(16.dp))

            Column {
                Text(
                    text = title,
                    fontSize = 16.sp,
                    fontWeight = FontWeight.SemiBold,
                    color = TextPrimary,
                )
                Spacer(modifier = Modifier.height(4.dp))
                Text(
                    text = description,
                    fontSize = 14.sp,
                    color = TextSecondary,
                    lineHeight = 20.sp,
                )
            }
        }
    }
}

@Composable
private fun MapConfigCard(
    mapCode: String,
    mapSetCode: String,
    modifier: Modifier = Modifier,
) {
    val displayCode = when {
        mapCode.isNotEmpty() -> "Map: ${mapCode.take(20)}${if (mapCode.length > 20) "..." else ""}"
        mapSetCode.isNotEmpty() -> "MapSet: ${mapSetCode.take(20)}${if (mapSetCode.length > 20) "..." else ""}"
        else -> return
    }

    Card(
        colors = CardDefaults.cardColors(
            containerColor = AccentBlue.copy(alpha = 0.1f),
        ),
        shape = RoundedCornerShape(12.dp),
        modifier = modifier.fillMaxWidth(),
    ) {
        Row(
            modifier = Modifier.padding(16.dp),
            verticalAlignment = Alignment.CenterVertically,
        ) {
            Icon(
                imageVector = Icons.Default.CheckCircle,
                contentDescription = null,
                tint = AccentGreen,
                modifier = Modifier.size(20.dp),
            )
            Spacer(modifier = Modifier.width(12.dp))
            Column {
                Text(
                    text = "Active Map",
                    fontSize = 12.sp,
                    color = TextSecondary,
                )
                Text(
                    text = displayCode,
                    fontSize = 14.sp,
                    fontWeight = FontWeight.Medium,
                    color = TextPrimary,
                )
            }
        }
    }
}
