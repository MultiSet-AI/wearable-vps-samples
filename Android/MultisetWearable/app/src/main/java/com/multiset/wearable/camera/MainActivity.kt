/*
Copyright (c) 2026 MultiSet AI. All rights reserved.
Licensed under the MultiSet License. You may not use this file except in compliance with the License. and you can't re-distribute this file without a prior notice
For license details, visit www.multiset.ai.
Redistribution in source or binary forms must retain this notice.
*/

// CameraAccess Sample App - Main Activity
//
// This is the main entry point for the CameraAccess sample application that demonstrates how to use
// the Meta Wearables Device Access Toolkit (DAT) to:
// - Initialize the DAT SDK
// - Handle device permissions (Bluetooth, Internet)
// - Request camera permissions from wearable devices (Ray-Ban Meta glasses)
// - Stream video and capture photos from connected wearable devices

package com.multiset.wearable.vps

import android.Manifest.permission.BLUETOOTH
import android.Manifest.permission.BLUETOOTH_CONNECT
import android.Manifest.permission.CAMERA
import android.Manifest.permission.INTERNET
import android.os.Bundle
import android.view.KeyEvent
import androidx.activity.ComponentActivity
import androidx.activity.compose.setContent
import androidx.activity.enableEdgeToEdge
import androidx.activity.result.contract.ActivityResultContracts.RequestMultiplePermissions
import androidx.activity.viewModels
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import com.meta.wearable.dat.core.Wearables
import com.meta.wearable.dat.core.types.Permission
import com.meta.wearable.dat.core.types.PermissionStatus
import com.multiset.wearable.vps.BuildConfig
import com.multiset.wearable.vps.input.GlassesButtonHandler
import com.multiset.wearable.vps.localization.SDKConfig
import com.multiset.wearable.vps.ui.CameraAccessScaffold
import com.multiset.wearable.vps.ui.SplashScreen
import com.multiset.wearable.vps.wearables.WearablesViewModel
import kotlin.coroutines.resume
import kotlinx.coroutines.CancellableContinuation
import kotlinx.coroutines.suspendCancellableCoroutine
import kotlinx.coroutines.sync.Mutex
import kotlinx.coroutines.sync.withLock

class MainActivity : ComponentActivity() {
  companion object {
    // Required Android permissions for the DAT SDK to function properly
    val PERMISSIONS: Array<String> = arrayOf(BLUETOOTH, BLUETOOTH_CONNECT, CAMERA, INTERNET)
  }

  val viewModel: com.multiset.wearable.vps.wearables.WearablesViewModel by viewModels()
  private var showSplash by mutableStateOf(true)

  private var permissionContinuation: CancellableContinuation<PermissionStatus>? = null
  private val permissionMutex = Mutex()
  // Requesting wearable device permissions via the Meta AI app
  private val permissionsResultLauncher =
      registerForActivityResult(Wearables.RequestPermissionContract()) { result ->
        val permissionStatus = result.getOrDefault(PermissionStatus.Denied)
        permissionContinuation?.resume(permissionStatus)
        permissionContinuation = null
      }

  // Convenience method to make a permission request in a sequential manner
  // Uses a Mutex to ensure requests are processed one at a time, preventing race conditions
  suspend fun requestWearablesPermission(permission: Permission): PermissionStatus {
    return permissionMutex.withLock {
      suspendCancellableCoroutine { continuation ->
        permissionContinuation = continuation
        continuation.invokeOnCancellation { permissionContinuation = null }
        permissionsResultLauncher.launch(permission)
      }
    }
  }

  override fun onCreate(savedInstanceState: Bundle?) {
    super.onCreate(savedInstanceState)
    enableEdgeToEdge()

    // Initialize glasses button handler to capture media button events
    _root_ide_package_.com.multiset.wearable.vps.input.GlassesButtonHandler.initialize(this)

    // First, ensure the app has necessary Android permissions
    checkPermissions {
      // Initialize the DAT SDK once the permissions are granted
      // This is REQUIRED before using any Wearables APIs
      Wearables.initialize(this)

      // Initialize Multiset SDK with config from multiset.properties (via BuildConfig).
      _root_ide_package_.com.multiset.wearable.vps.localization.SDKConfig.initialize(
          context = this,
          clientId = BuildConfig.MULTISET_CLIENT_ID,
          clientSecret = BuildConfig.MULTISET_CLIENT_SECRET,
          mapCode = BuildConfig.MULTISET_MAP_CODE,
          mapSetCode = BuildConfig.MULTISET_MAP_SET_CODE,
      )

      // Start observing Wearables state after SDK is initialized
      viewModel.startMonitoring()
    }

    setContent {
      if (showSplash) {
          _root_ide_package_.com.multiset.wearable.vps.ui.SplashScreen(
              onSplashComplete = { showSplash = false },
          )
      } else {
          _root_ide_package_.com.multiset.wearable.vps.ui.CameraAccessScaffold(
              viewModel = viewModel,
              onRequestWearablesPermission = ::requestWearablesPermission,
          )
      }
    }
  }

  override fun onDestroy() {
    super.onDestroy()
    // Release glasses button handler resources
    _root_ide_package_.com.multiset.wearable.vps.input.GlassesButtonHandler.release()
  }

  fun checkPermissions(onPermissionsGranted: () -> Unit) {
    registerForActivityResult(RequestMultiplePermissions()) { permissionsResult ->
          val granted = permissionsResult.entries.all { it.value }
          if (granted) {
            onPermissionsGranted()
          } else {
            viewModel.setRecentError(
                "Allow All Permissions (Bluetooth, Bluetooth Connect, Internet)"
            )
          }
        }
        .launch(PERMISSIONS)
  }

  /**
   * Capture hardware key events from connected devices (Meta Ray-Ban glasses).
   * The glasses button sends KeyEvents that we forward to GlassesButtonHandler.
   */
  override fun onKeyDown(keyCode: Int, event: KeyEvent?): Boolean {
    // Try to handle as glasses button press
    if (_root_ide_package_.com.multiset.wearable.vps.input.GlassesButtonHandler.handleKeyEvent(keyCode, event)) {
      return true  // Event consumed
    }
    return super.onKeyDown(keyCode, event)
  }
}
