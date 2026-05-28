/*
Copyright (c) 2026 MultiSet AI. All rights reserved.
Licensed under the MultiSet License. You may not use this file except in compliance with the License. and you can't re-distribute this file without a prior notice
For license details, visit www.multiset.ai.
Redistribution in source or binary forms must retain this notice.
*/

package com.multiset.wearable.vps.ui

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Check
import androidx.compose.material.icons.filled.CheckCircle
import androidx.compose.material.icons.filled.Close
import androidx.compose.material.icons.filled.Key
import androidx.compose.material.icons.filled.Map
import androidx.compose.material.icons.filled.Settings
import androidx.compose.material.icons.filled.Warning
import androidx.compose.material3.Button
import androidx.compose.material3.ButtonDefaults
import androidx.compose.material3.Card
import androidx.compose.material3.CardDefaults
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.ModalBottomSheet
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.OutlinedTextFieldDefaults
import androidx.compose.material3.Text
import androidx.compose.material3.rememberModalBottomSheetState
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.multiset.wearable.vps.localization.SDKConfig

/**
 * Settings dialog for configuring map codes at runtime.
 *
 * Credentials are intentionally not editable here — they are sourced from BuildConfig
 * (MULTISET_CLIENT_ID / MULTISET_CLIENT_SECRET) at build time. This section only
 * surfaces their configured/not-configured status, matching the iOS app.
 */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun SettingsDialog(
    onDismiss: () -> Unit,
    modifier: Modifier = Modifier,
) {
    val sheetState = rememberModalBottomSheetState(skipPartiallyExpanded = true)
    val scrollState = rememberScrollState()

    var mapCode by remember { mutableStateOf(SDKConfig.MAP_CODE) }
    var mapSetCode by remember { mutableStateOf(SDKConfig.MAP_SET_CODE) }

    val hasCredentials = SDKConfig.hasCredentials()
    val isReadyToLocalize = hasCredentials && (mapCode.isNotBlank() || mapSetCode.isNotBlank())

    ModalBottomSheet(
        onDismissRequest = onDismiss,
        sheetState = sheetState,
        containerColor = Color(0xFF1C1C1E),
        modifier = modifier,
    ) {
        Column(
            modifier = Modifier
                .fillMaxWidth()
                .verticalScroll(scrollState)
                .padding(horizontal = 24.dp)
                .padding(bottom = 32.dp),
        ) {
            // Header
            Row(
                modifier = Modifier.fillMaxWidth(),
                horizontalArrangement = Arrangement.SpaceBetween,
                verticalAlignment = Alignment.CenterVertically,
            ) {
                Row(
                    verticalAlignment = Alignment.CenterVertically,
                    horizontalArrangement = Arrangement.spacedBy(12.dp),
                ) {
                    Icon(
                        imageVector = Icons.Default.Settings,
                        contentDescription = null,
                        tint = AppColor.DeepBlue,
                        modifier = Modifier.size(28.dp),
                    )
                    Text(
                        text = "Localization Settings",
                        fontSize = 22.sp,
                        fontWeight = FontWeight.Bold,
                        color = Color.White,
                    )
                }
                IconButton(onClick = onDismiss) {
                    Icon(
                        imageVector = Icons.Default.Close,
                        contentDescription = "Close",
                        tint = Color.Gray,
                    )
                }
            }

            Spacer(modifier = Modifier.height(24.dp))

            // API Credentials section — read-only status, set via BuildConfig at build time.
            SectionHeader(icon = Icons.Default.Key, title = "API Credentials")

            Spacer(modifier = Modifier.height(12.dp))

            StatusRow(
                label = "API Status",
                isOk = hasCredentials,
                okText = "Configured",
                notOkText = "Not Configured",
                notOkIcon = Icons.Default.Warning,
                notOkTint = AppColor.Yellow,
            )

            if (!hasCredentials) {
                Spacer(modifier = Modifier.height(8.dp))
                Text(
                    text = "Add MULTISET_CLIENT_ID and MULTISET_CLIENT_SECRET to multiset.properties at the project root, then rebuild the app.",
                    color = Color.Gray,
                    fontSize = 12.sp,
                )
            }

            Spacer(modifier = Modifier.height(24.dp))
            HorizontalDivider(color = Color.Gray.copy(alpha = 0.3f))
            Spacer(modifier = Modifier.height(24.dp))

            // Map Configuration Section
            SectionHeader(icon = Icons.Default.Map, title = "Map Configuration")

            Spacer(modifier = Modifier.height(8.dp))

            Text(
                text = "Enter either a map code for single map localization, or a map set code for multi-map localization.",
                color = Color.Gray,
                fontSize = 13.sp,
            )

            Spacer(modifier = Modifier.height(12.dp))

            SettingsTextField(
                value = mapCode,
                onValueChange = { mapCode = it },
                label = "Map Code",
                placeholder = "e.g., MAP_XXXXXXXXXX",
            )

            Spacer(modifier = Modifier.height(12.dp))

            SettingsTextField(
                value = mapSetCode,
                onValueChange = { mapSetCode = it },
                label = "Map Set Code",
                placeholder = "e.g., MAPSET_XXXXXXXXXX",
            )

            Spacer(modifier = Modifier.height(24.dp))
            HorizontalDivider(color = Color.Gray.copy(alpha = 0.3f))
            Spacer(modifier = Modifier.height(24.dp))

            // Ready-to-localize composite status (mirrors iOS Status section).
            SectionHeader(icon = Icons.Default.CheckCircle, title = "Status")

            Spacer(modifier = Modifier.height(12.dp))

            StatusRow(
                label = "Ready to Localize",
                isOk = isReadyToLocalize,
                okText = "Yes",
                notOkText = "No",
                notOkIcon = Icons.Default.Close,
                notOkTint = AppColor.Red,
            )

            if (!isReadyToLocalize) {
                Spacer(modifier = Modifier.height(8.dp))
                if (!hasCredentials) {
                    HintRow("Missing API credentials")
                }
                if (mapCode.isBlank() && mapSetCode.isBlank()) {
                    HintRow("Missing map code")
                }
            }

            Spacer(modifier = Modifier.height(32.dp))

            Button(
                onClick = {
                    SDKConfig.updateMapCodes(mapCode, mapSetCode)
                    SDKConfig.saveSettings()
                    onDismiss()
                },
                colors = ButtonDefaults.buttonColors(containerColor = AppColor.Green),
                modifier = Modifier
                    .fillMaxWidth()
                    .height(52.dp),
            ) {
                Icon(
                    imageVector = Icons.Default.Check,
                    contentDescription = null,
                    modifier = Modifier.size(20.dp),
                )
                Spacer(modifier = Modifier.width(8.dp))
                Text("Save Settings", fontWeight = FontWeight.SemiBold)
            }

            Spacer(modifier = Modifier.height(16.dp))
        }
    }
}

@Composable
private fun SectionHeader(
    icon: ImageVector,
    title: String,
    modifier: Modifier = Modifier,
) {
    Row(
        modifier = modifier,
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.spacedBy(8.dp),
    ) {
        Icon(
            imageVector = icon,
            contentDescription = null,
            tint = AppColor.DeepBlue,
            modifier = Modifier.size(20.dp),
        )
        Text(
            text = title,
            fontSize = 16.sp,
            fontWeight = FontWeight.SemiBold,
            color = Color.White,
        )
    }
}

@Composable
private fun StatusRow(
    label: String,
    isOk: Boolean,
    okText: String,
    notOkText: String,
    notOkIcon: ImageVector,
    notOkTint: Color,
) {
    Card(
        colors = CardDefaults.cardColors(containerColor = Color.White.copy(alpha = 0.04f)),
        shape = RoundedCornerShape(10.dp),
        modifier = Modifier.fillMaxWidth(),
    ) {
        Row(
            modifier = Modifier
                .fillMaxWidth()
                .padding(horizontal = 14.dp, vertical = 12.dp),
            verticalAlignment = Alignment.CenterVertically,
            horizontalArrangement = Arrangement.SpaceBetween,
        ) {
            Text(label, color = Color.White, fontSize = 14.sp)
            Row(
                verticalAlignment = Alignment.CenterVertically,
                horizontalArrangement = Arrangement.spacedBy(6.dp),
            ) {
                Icon(
                    imageVector = if (isOk) Icons.Default.CheckCircle else notOkIcon,
                    contentDescription = null,
                    tint = if (isOk) AppColor.Green else notOkTint,
                    modifier = Modifier.size(18.dp),
                )
                Text(
                    text = if (isOk) okText else notOkText,
                    color = if (isOk) AppColor.Green else notOkTint,
                    fontSize = 14.sp,
                    fontWeight = FontWeight.Medium,
                )
            }
        }
    }
}

@Composable
private fun HintRow(message: String) {
    Row(
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.spacedBy(6.dp),
        modifier = Modifier.padding(vertical = 2.dp),
    ) {
        Icon(
            imageVector = Icons.Default.Warning,
            contentDescription = null,
            tint = AppColor.Yellow,
            modifier = Modifier.size(14.dp),
        )
        Text(message, color = AppColor.Yellow, fontSize = 12.sp)
    }
}

@Composable
private fun SettingsTextField(
    value: String,
    onValueChange: (String) -> Unit,
    label: String,
    placeholder: String,
    modifier: Modifier = Modifier,
) {
    OutlinedTextField(
        value = value,
        onValueChange = onValueChange,
        label = { Text(label) },
        placeholder = { Text(placeholder, color = Color.Gray.copy(alpha = 0.5f)) },
        singleLine = true,
        colors = OutlinedTextFieldDefaults.colors(
            focusedTextColor = Color.White,
            unfocusedTextColor = Color.White,
            focusedBorderColor = AppColor.DeepBlue,
            unfocusedBorderColor = Color.Gray.copy(alpha = 0.5f),
            focusedLabelColor = AppColor.DeepBlue,
            unfocusedLabelColor = Color.Gray,
            cursorColor = AppColor.DeepBlue,
        ),
        modifier = modifier.fillMaxWidth(),
    )
}
