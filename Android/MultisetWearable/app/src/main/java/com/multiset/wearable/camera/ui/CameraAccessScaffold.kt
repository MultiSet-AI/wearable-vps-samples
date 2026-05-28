/*
Copyright (c) 2026 MultiSet AI. All rights reserved.
Licensed under the MultiSet License. You may not use this file except in compliance with the License. and you can't re-distribute this file without a prior notice
For license details, visit www.multiset.ai.
Redistribution in source or binary forms must retain this notice.
*/

// CameraAccessScaffold - DAT Application Navigation Orchestrator
//
// Navigation:
// - HomeScreen: when NOT registered — initial registration UI.
// - FeatureSelectionScreen: when registered and no feature chosen — the demo menu.
// - LocalizationDemoScreen / NavigationDemoScreen: when a feature is chosen.

package com.multiset.wearable.vps.ui

import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.navigationBarsPadding
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Error
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Snackbar
import androidx.compose.material3.SnackbarHost
import androidx.compose.material3.SnackbarHostState
import androidx.compose.material3.Surface
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.unit.dp
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import com.meta.wearable.dat.core.types.Permission
import com.meta.wearable.dat.core.types.PermissionStatus
import com.multiset.wearable.vps.wearables.WearablesViewModel

@Composable
fun CameraAccessScaffold(
    viewModel: WearablesViewModel,
    onRequestWearablesPermission: suspend (Permission) -> PermissionStatus,
    modifier: Modifier = Modifier,
) {
    val uiState by viewModel.uiState.collectAsStateWithLifecycle()
    val snackbarHostState = remember { SnackbarHostState() }

    var selectedFeature by remember { mutableStateOf<AppFeature?>(null) }

    // Reset feature selection if the glasses disconnect.
    LaunchedEffect(uiState.isRegistered) {
        if (!uiState.isRegistered) selectedFeature = null
    }

    // Observe recent errors and show snackbar
    LaunchedEffect(uiState.recentError) {
        uiState.recentError?.let { errorMessage ->
            snackbarHostState.showSnackbar(errorMessage)
            viewModel.clearRecentError()
        }
    }

    Surface(modifier = modifier.fillMaxSize(), color = MaterialTheme.colorScheme.background) {
        Box(modifier = Modifier.fillMaxSize()) {
            if (uiState.isRegistered) {
                when (selectedFeature) {
                    AppFeature.LOCALIZATION ->
                        LocalizationDemoScreen(
                            wearablesViewModel = viewModel,
                            onRequestWearablesPermission = onRequestWearablesPermission,
                            onDismiss = { selectedFeature = null },
                        )
                    AppFeature.NAVIGATION ->
                        NavigationDemoScreen(
                            wearablesViewModel = viewModel,
                            onRequestWearablesPermission = onRequestWearablesPermission,
                            onDismiss = { selectedFeature = null },
                        )
                    else ->
                        FeatureSelectionScreen(
                            viewModel = viewModel,
                            onSelectFeature = { selectedFeature = it },
                        )
                }
            } else {
                HomeScreen(viewModel = viewModel)
            }

            SnackbarHost(
                hostState = snackbarHostState,
                modifier =
                    Modifier.align(Alignment.BottomCenter)
                        .navigationBarsPadding()
                        .padding(horizontal = 16.dp, vertical = 32.dp),
                snackbar = { data ->
                    Snackbar(
                        shape = RoundedCornerShape(24.dp),
                        containerColor = MaterialTheme.colorScheme.errorContainer,
                        contentColor = MaterialTheme.colorScheme.onErrorContainer,
                    ) {
                        Row(verticalAlignment = Alignment.CenterVertically) {
                            Icon(
                                imageVector = Icons.Default.Error,
                                contentDescription = "Camera Access error",
                                tint = MaterialTheme.colorScheme.error,
                            )
                            Spacer(modifier = Modifier.width(8.dp))
                            Text(data.visuals.message)
                        }
                    }
                },
            )
        }
    }
}
