/*
Copyright (c) 2026 MultiSet AI. All rights reserved.
Licensed under the MultiSet License. You may not use this file except in compliance with the License. and you can't re-distribute this file without a prior notice
For license details, visit www.multiset.ai.
Redistribution in source or binary forms must retain this notice.
*/

// NonStreamScreen - DAT Device Selection and Setup
//
// This screen demonstrates DAT device management and pre-streaming setup. It handles device
// registration status, camera permissions, and stream readiness.

package com.multiset.wearable.vps.ui

import androidx.activity.compose.LocalActivity
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
import androidx.compose.foundation.layout.systemBarsPadding
import androidx.compose.foundation.layout.width
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.LinkOff
import androidx.compose.material3.DropdownMenu
import androidx.compose.material3.DropdownMenuItem
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.ModalBottomSheet
import androidx.compose.material3.Text
import androidx.compose.material3.darkColorScheme
import androidx.compose.material3.rememberModalBottomSheetState
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.res.painterResource
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import com.meta.wearable.dat.core.types.Permission
import com.meta.wearable.dat.core.types.PermissionStatus
import com.meta.wearable.dat.core.types.RegistrationState
import com.multiset.wearable.vps.R
import com.multiset.wearable.vps.wearables.WearablesViewModel
import kotlinx.coroutines.launch

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun NonStreamScreen(
    viewModel: WearablesViewModel,
    onRequestWearablesPermission: suspend (Permission) -> PermissionStatus,
    modifier: Modifier = Modifier,
) {
  val uiState by viewModel.uiState.collectAsStateWithLifecycle()
  val gettingStartedSheetState = rememberModalBottomSheetState(skipPartiallyExpanded = true)
  val scope = rememberCoroutineScope()
  var dropdownExpanded by remember { mutableStateOf(false) }
  val activity = LocalActivity.current
  val isDisconnectEnabled = uiState.registrationState == RegistrationState.REGISTERED

  MaterialTheme(colorScheme = darkColorScheme()) {
    Box(
        modifier = modifier.fillMaxSize().background(Color.Black).padding(all = 24.dp),
        contentAlignment = Alignment.Center,
    ) {
      Box(modifier = Modifier.align(Alignment.TopEnd).systemBarsPadding()) {
        IconButton(onClick = { dropdownExpanded = true }) {
          Icon(
              imageVector = Icons.Default.LinkOff,
              contentDescription = "DisconnectIcon",
              tint = Color.White,
              modifier = Modifier.size(28.dp),
          )
        }

        DropdownMenu(
            expanded = dropdownExpanded,
            onDismissRequest = { dropdownExpanded = false },
        ) {
          DropdownMenuItem(
              text = {
                Text(
                    stringResource(R.string.unregister_button_title),
                    color = if (isDisconnectEnabled) AppColor.Red else Color.Gray,
                )
              },
              enabled = isDisconnectEnabled,
              onClick = {
                activity?.let { viewModel.startUnregistration(it) }
                dropdownExpanded = false
              },
              modifier = Modifier.height(30.dp),
          )
        }
      }

      Column(
          horizontalAlignment = Alignment.CenterHorizontally,
          verticalArrangement = Arrangement.spacedBy(8.dp),
      ) {
        Icon(
            painter = painterResource(id = R.drawable.camera_access_icon),
            contentDescription = stringResource(R.string.camera_access_icon_description),
            tint = Color.White,
            modifier = Modifier.size(80.dp * LocalDensity.current.density),
        )
        Text(
            text = stringResource(R.string.non_stream_screen_title),
            style = MaterialTheme.typography.headlineSmall,
            fontWeight = FontWeight.Bold,
            textAlign = TextAlign.Center,
            color = Color.White,
        )
        Text(
            text = stringResource(R.string.non_stream_screen_description),
            textAlign = TextAlign.Center,
            color = Color.White,
        )
      }

      Column(
          modifier = Modifier.align(Alignment.BottomCenter).navigationBarsPadding(),
          horizontalAlignment = Alignment.CenterHorizontally,
      ) {
        if (!uiState.hasActiveDevice) {
          Row(
              horizontalArrangement = Arrangement.spacedBy(8.dp),
              verticalAlignment = Alignment.CenterVertically,
              modifier = Modifier.padding(bottom = 12.dp),
          ) {
            Icon(
                painter = painterResource(id = R.drawable.hourglass_icon),
                contentDescription = "Waiting for device",
                tint = Color.White.copy(alpha = 0.7f),
                modifier = Modifier.size(16.dp),
            )
            Text(
                text = stringResource(R.string.waiting_for_active_device),
                style = MaterialTheme.typography.bodyMedium,
                color = Color.White.copy(alpha = 0.7f),
            )
          }
        }

        // Start Streaming Button
        SwitchButton(
            label = stringResource(R.string.stream_button_title),
            onClick = { viewModel.navigateToStreaming(onRequestWearablesPermission) },
            enabled = uiState.hasActiveDevice,
        )
      }

      // Getting Started Sheet
      if (uiState.isGettingStartedSheetVisible) {
        ModalBottomSheet(
            onDismissRequest = { viewModel.hideGettingStartedSheet() },
            sheetState = gettingStartedSheetState,
        ) {
          GettingStartedSheetContent(
              onContinue = {
                scope.launch {
                  gettingStartedSheetState.hide()
                  viewModel.hideGettingStartedSheet()
                }
              }
          )
        }
      }
    }
  }
}

@Composable
private fun GettingStartedSheetContent(onContinue: () -> Unit, modifier: Modifier = Modifier) {
  Column(
      modifier = modifier.fillMaxWidth().padding(horizontal = 24.dp).padding(bottom = 24.dp),
      horizontalAlignment = Alignment.CenterHorizontally,
      verticalArrangement = Arrangement.spacedBy(24.dp),
  ) {
    Text(
        text = stringResource(R.string.getting_started_title),
        style = MaterialTheme.typography.titleLarge,
        fontWeight = FontWeight.SemiBold,
        textAlign = TextAlign.Center,
    )

    Column(
        verticalArrangement = Arrangement.spacedBy(12.dp),
        modifier = Modifier.fillMaxWidth().padding(8.dp).padding(bottom = 16.dp),
    ) {
      TipItem(
          iconResId = R.drawable.video_icon,
          text = stringResource(R.string.getting_started_tip_permission),
      )
      TipItem(
          iconResId = R.drawable.tap_icon,
          text = stringResource(R.string.getting_started_tip_photo),
      )
      TipItem(
          iconResId = R.drawable.smart_glasses_icon,
          text = stringResource(R.string.getting_started_tip_led),
      )
    }

    SwitchButton(
        label = stringResource(R.string.getting_started_continue),
        onClick = onContinue,
        modifier = Modifier.navigationBarsPadding(),
    )
  }
}

@Composable
private fun TipItem(iconResId: Int, text: String, modifier: Modifier = Modifier) {
  Row(modifier = modifier.fillMaxWidth()) {
    Icon(
        painter = painterResource(id = iconResId),
        contentDescription = "Getting started tip icon",
        modifier = Modifier.padding(start = 4.dp, top = 4.dp).width(24.dp),
    )
    Spacer(modifier = Modifier.width(10.dp))
    Text(text = text)
  }
}
