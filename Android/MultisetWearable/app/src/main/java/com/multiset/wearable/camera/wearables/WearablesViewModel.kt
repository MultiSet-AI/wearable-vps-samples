/*
Copyright (c) 2026 MultiSet AI. All rights reserved.
Licensed under the MultiSet License. You may not use this file except in compliance with the License. and you can't re-distribute this file without a prior notice
For license details, visit www.multiset.ai.
Redistribution in source or binary forms must retain this notice.
*/

// WearablesViewModel - Core DAT SDK Integration
//
// This ViewModel demonstrates the core DAT API patterns for:
// - Device registration and unregistration using the DAT SDK
// - Permission management for wearable devices
// - Device discovery and state management
// - Firmware / glasses-app update handling

package com.multiset.wearable.vps.wearables

import android.app.Activity
import android.app.Application
import android.util.Log
import androidx.lifecycle.AndroidViewModel
import androidx.lifecycle.viewModelScope
import com.meta.wearable.dat.core.Wearables
import com.meta.wearable.dat.core.selectors.AutoDeviceSelector
import com.meta.wearable.dat.core.selectors.DeviceSelector
import com.meta.wearable.dat.core.types.DeviceCompatibility
import com.meta.wearable.dat.core.types.DeviceIdentifier
import com.meta.wearable.dat.core.types.Permission
import com.meta.wearable.dat.core.types.PermissionStatus
import com.meta.wearable.dat.core.types.RegistrationState
import kotlinx.collections.immutable.toImmutableList
import kotlinx.coroutines.Job
import kotlinx.coroutines.delay
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.flow.update
import kotlinx.coroutines.launch

class WearablesViewModel(application: Application) : AndroidViewModel(application) {
  companion object {
    private const val TAG = "WearablesViewModel"
  }

  private val _uiState = MutableStateFlow(WearablesUiState())
  val uiState: StateFlow<WearablesUiState> = _uiState.asStateFlow()

  // AutoDeviceSelector automatically selects the first available wearable device
  val deviceSelector: DeviceSelector by lazy { AutoDeviceSelector() }
  private var deviceSelectorJob: Job? = null

  private var monitoringStarted = false
  private val deviceMonitoringJobs = mutableMapOf<DeviceIdentifier, Job>()
  private val deviceCompatibility = mutableMapOf<DeviceIdentifier, DeviceCompatibility>()

  /**
   * Begin observing Wearables state. Call this once after Android permissions have been granted and
   * [Wearables.initialize] has run.
   */
  fun startMonitoring() {
    // Permissions are granted by the time monitoring starts, so registration is now allowed.
    _uiState.update { it.copy(canRegister = true) }

    if (monitoringStarted) {
      return
    }
    monitoringStarted = true

    // Monitor device selector for active device
    deviceSelectorJob =
        viewModelScope.launch {
          deviceSelector.activeDeviceFlow().collect { device ->
            _uiState.update { it.copy(hasActiveDevice = device != null) }
          }
        }

    // This allows the app to react to registration changes (registered, unregistered, etc.)
    viewModelScope.launch {
      Wearables.registrationState.collect { value ->
        Log.d(TAG, "Registration state changed: $value")
        val previousState = _uiState.value.registrationState
        val showGettingStartedSheet =
            value == RegistrationState.REGISTERED && previousState == RegistrationState.REGISTERING

        // Reset streaming state when device becomes unavailable
        val shouldResetStreaming = value == RegistrationState.UNAVAILABLE

        _uiState.update {
          it.copy(
              registrationState = value,
              isGettingStartedSheetVisible = showGettingStartedSheet,
              isStreaming = if (shouldResetStreaming) false else it.isStreaming,
          )
        }
      }
    }
    // This automatically updates when devices are discovered, connected, or disconnected
    viewModelScope.launch {
      Wearables.devices.collect { value ->
        Log.d(TAG, "Devices updated: ${value.size} devices - $value")
        _uiState.update { it.copy(devices = value.toList().toImmutableList()) }
        // Monitor device metadata for compatibility issues
        monitorDeviceCompatibility(value)
      }
    }
  }

  private fun monitorDeviceCompatibility(devices: Set<DeviceIdentifier>) {
    // Cancel monitoring jobs for devices that are no longer in the list
    val removedDevices = deviceMonitoringJobs.keys - devices
    removedDevices.forEach { deviceId ->
      deviceMonitoringJobs[deviceId]?.cancel()
      deviceMonitoringJobs.remove(deviceId)
      deviceCompatibility.remove(deviceId)
    }
    updateFirmwareUpdateRequired()

    // Start monitoring jobs only for new devices (not already being monitored)
    val newDevices = devices - deviceMonitoringJobs.keys
    newDevices.forEach { deviceId ->
      val job =
          viewModelScope.launch {
            Wearables.devicesMetadata[deviceId]?.collect { metadata ->
              deviceCompatibility[deviceId] = metadata.compatibility
              updateFirmwareUpdateRequired()
              if (metadata.compatibility == DeviceCompatibility.DEVICE_UPDATE_REQUIRED) {
                val deviceName = metadata.name.ifEmpty { deviceId }
                setRecentError("Device '$deviceName' requires an update to work with this app")
              }
            }
          }
      deviceMonitoringJobs[deviceId] = job
    }
  }

  fun startRegistration(activity: Activity) {
    Log.d(TAG, "startRegistration() called")
    Wearables.startRegistration(activity)
  }

  fun startUnregistration(activity: Activity) {
    Log.d(TAG, "startUnregistration() called")
    // Reset streaming state before unregistering
    _uiState.update { it.copy(isStreaming = false) }
    Wearables.startUnregistration(activity)
  }

  fun openFirmwareUpdate(activity: Activity) {
    Wearables.openFirmwareUpdate(activity).onFailure { error, _ -> setRecentError(error.description) }
  }

  fun openDATGlassesAppUpdate(activity: Activity) {
    Wearables.openDATGlassesAppUpdate(activity).onFailure { error, _ ->
      setRecentError(error.description)
    }
  }

  fun navigateToStreaming(onRequestWearablesPermission: suspend (Permission) -> PermissionStatus) {
    viewModelScope.launch {
      val permission = Permission.CAMERA // Camera permission is required for streaming

      // Retry permission check with exponential backoff
      // This handles the race condition when device just registered but isn't fully ready
      val maxRetries = 3
      var lastError: String? = null

      for (attempt in 0 until maxRetries) {
        if (attempt > 0) {
          // Exponential backoff: 500ms, 1000ms, 2000ms
          val delayMs = 500L * (1 shl (attempt - 1))
          Log.d(TAG, "Retry attempt $attempt after ${delayMs}ms delay...")
          delay(delayMs)
        }

        val result = Wearables.checkPermissionStatus(permission)

        var shouldRetry = false
        result.onFailure { error, _ ->
          Log.w(TAG, "Permission check error (attempt ${attempt + 1}/$maxRetries): ${error.description}")
          lastError = error.description
          // Retry on errors that indicate device not fully ready
          shouldRetry = attempt < maxRetries - 1
        }

        if (shouldRetry) {
          continue
        }

        if (result.isFailure) {
          // Final failure after all retries
          setRecentError("Permission check error: $lastError")
          return@launch
        }

        val permissionStatus = result.getOrNull()
        if (permissionStatus == PermissionStatus.Granted) {
          _uiState.update { it.copy(isStreaming = true) }
          return@launch
        }

        // Request permission
        val requestedPermissionStatus = onRequestWearablesPermission(permission)
        when (requestedPermissionStatus) {
          PermissionStatus.Denied -> {
            setRecentError("Permission denied")
          }
          PermissionStatus.Granted -> {
            _uiState.update { it.copy(isStreaming = true) }
          }
        }
        return@launch // Exit loop after successful permission check/request
      }
    }
  }

  fun navigateToDeviceSelection() {
    _uiState.update { it.copy(isStreaming = false) }
  }

  fun clearRecentError() {
    _uiState.update { it.copy(recentError = null) }
  }

  fun setRecentError(error: String) {
    _uiState.update { it.copy(recentError = error) }
  }

  internal fun setDatAppUpdateRequired(required: Boolean) {
    _uiState.update { it.copy(isDatAppUpdateRequired = required) }
  }

  fun showGettingStartedSheet() {
    _uiState.update { it.copy(isGettingStartedSheetVisible = true) }
  }

  fun hideGettingStartedSheet() {
    _uiState.update { it.copy(isGettingStartedSheetVisible = false) }
  }

  override fun onCleared() {
    super.onCleared()
    // Cancel all device monitoring jobs when ViewModel is cleared
    deviceMonitoringJobs.values.forEach { it.cancel() }
    deviceMonitoringJobs.clear()
    deviceSelectorJob?.cancel()
  }

  private fun updateFirmwareUpdateRequired() {
    val isRequired =
        deviceCompatibility.values.any { it == DeviceCompatibility.DEVICE_UPDATE_REQUIRED }
    _uiState.update { it.copy(isFirmwareUpdateRequired = isRequired) }
  }
}
