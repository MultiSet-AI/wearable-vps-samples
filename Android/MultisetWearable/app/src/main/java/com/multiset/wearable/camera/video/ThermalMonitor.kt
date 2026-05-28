/*
Copyright (c) 2026 MultiSet AI. All rights reserved.
Licensed under the MultiSet License. You may not use this file except in compliance with the License. and you can't re-distribute this file without a prior notice
For license details, visit www.multiset.ai.
Redistribution in source or binary forms must retain this notice.
*/

package com.multiset.wearable.vps.video

import android.content.Context
import android.os.PowerManager
import android.util.Log
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import java.util.concurrent.Executor

/**
 * Monitors device thermal state and provides adaptive FPS recommendations.
 *
 * Uses Android's PowerManager thermal API (available on Android 10+) to detect
 * when the device is heating up and recommend frame rate reductions to prevent
 * thermal throttling and improve user experience.
 */
class ThermalMonitor(context: Context) {
    companion object {
        private const val TAG = "ThermalMonitor"
        private const val BASE_FPS = 24
    }

    enum class ThermalLevel {
        NONE,       // Normal operation - full FPS
        LIGHT,      // Slight throttling - reduce to 20 FPS
        MODERATE,   // Moderate throttling - reduce to 15 FPS
        SEVERE,     // Severe throttling - reduce to 10 FPS
        CRITICAL,   // Critical throttling - reduce to 5 FPS
        EMERGENCY,  // Emergency - reduce to 2 FPS
        SHUTDOWN    // Device shutting down - stop streaming
    }

    private val powerManager = context.getSystemService(Context.POWER_SERVICE) as? PowerManager
    private val mainExecutor: Executor = context.mainExecutor

    private val _thermalLevel = MutableStateFlow(ThermalLevel.NONE)
    val thermalLevel: StateFlow<ThermalLevel> = _thermalLevel.asStateFlow()

    private val _recommendedFps = MutableStateFlow(BASE_FPS)
    val recommendedFps: StateFlow<Int> = _recommendedFps.asStateFlow()

    private val _shouldPauseStreaming = MutableStateFlow(false)
    val shouldPauseStreaming: StateFlow<Boolean> = _shouldPauseStreaming.asStateFlow()

    private var thermalStatusListener: PowerManager.OnThermalStatusChangedListener? = null
    private var isRegistered = false

    init {
        registerThermalListener()
    }

    private fun registerThermalListener() {
        if (powerManager == null) {
            Log.w(TAG, "PowerManager not available, thermal monitoring disabled")
            return
        }

        try {
            val listener = PowerManager.OnThermalStatusChangedListener { status ->
                handleThermalStatusChange(status)
            }

            powerManager.addThermalStatusListener(mainExecutor, listener)
            thermalStatusListener = listener
            isRegistered = true

            // Get initial thermal status
            val currentStatus = powerManager.currentThermalStatus
            handleThermalStatusChange(currentStatus)

            Log.d(TAG, "Thermal monitoring registered, initial status: $currentStatus")
        } catch (e: Exception) {
            Log.e(TAG, "Failed to register thermal listener", e)
        }
    }

    private fun handleThermalStatusChange(status: Int) {
        val level = mapThermalStatus(status)
        val previousLevel = _thermalLevel.value

        _thermalLevel.value = level
        _recommendedFps.value = getRecommendedFps(level)
        _shouldPauseStreaming.value = level == ThermalLevel.SHUTDOWN

        if (level != previousLevel) {
            Log.i(TAG, "Thermal status changed: $previousLevel -> $level, " +
                    "recommended FPS: ${_recommendedFps.value}")
        }
    }

    private fun mapThermalStatus(status: Int): ThermalLevel {
        return when (status) {
            PowerManager.THERMAL_STATUS_NONE -> ThermalLevel.NONE
            PowerManager.THERMAL_STATUS_LIGHT -> ThermalLevel.LIGHT
            PowerManager.THERMAL_STATUS_MODERATE -> ThermalLevel.MODERATE
            PowerManager.THERMAL_STATUS_SEVERE -> ThermalLevel.SEVERE
            PowerManager.THERMAL_STATUS_CRITICAL -> ThermalLevel.CRITICAL
            PowerManager.THERMAL_STATUS_EMERGENCY -> ThermalLevel.EMERGENCY
            PowerManager.THERMAL_STATUS_SHUTDOWN -> ThermalLevel.SHUTDOWN
            else -> ThermalLevel.NONE
        }
    }

    private fun getRecommendedFps(level: ThermalLevel): Int {
        return when (level) {
            ThermalLevel.NONE -> 24
            ThermalLevel.LIGHT -> 20
            ThermalLevel.MODERATE -> 15
            ThermalLevel.SEVERE -> 10
            ThermalLevel.CRITICAL -> 5
            ThermalLevel.EMERGENCY -> 2
            ThermalLevel.SHUTDOWN -> 0
        }
    }

    /**
     * Determine if a frame should be dropped based on thermal state.
     *
     * This uses probabilistic frame dropping to smoothly reduce frame rate
     * without sudden jumps.
     *
     * @param currentFps The current target FPS (usually 24)
     * @return true if the frame should be dropped
     */
    fun shouldDropFrame(currentFps: Int = BASE_FPS): Boolean {
        val recommended = _recommendedFps.value

        // Never drop if we're at or below recommended
        if (currentFps <= recommended) return false

        // Emergency/shutdown - drop almost everything
        if (_thermalLevel.value == ThermalLevel.SHUTDOWN) return true
        if (_thermalLevel.value == ThermalLevel.EMERGENCY) {
            return Math.random() > 0.1 // Keep only ~10% of frames
        }

        // Probabilistic dropping to achieve target FPS
        // dropRatio = (currentFps - recommended) / currentFps
        val dropRatio = (currentFps - recommended).toDouble() / currentFps
        return Math.random() < dropRatio
    }

    /**
     * Get a human-readable description of current thermal state.
     */
    fun getStatusDescription(): String {
        return when (_thermalLevel.value) {
            ThermalLevel.NONE -> "Normal"
            ThermalLevel.LIGHT -> "Warm - slightly reducing frame rate"
            ThermalLevel.MODERATE -> "Hot - reducing frame rate to 15 FPS"
            ThermalLevel.SEVERE -> "Very hot - reducing frame rate to 10 FPS"
            ThermalLevel.CRITICAL -> "Critical temperature - minimal frame rate"
            ThermalLevel.EMERGENCY -> "Emergency - please stop streaming"
            ThermalLevel.SHUTDOWN -> "Device overheating - streaming paused"
        }
    }

    /**
     * Check if device is in a concerning thermal state.
     */
    fun isThermalConcern(): Boolean {
        return _thermalLevel.value >= ThermalLevel.MODERATE
    }

    /**
     * Release resources and unregister listener.
     */
    fun release() {
        if (isRegistered && thermalStatusListener != null) {
            try {
                powerManager?.removeThermalStatusListener(thermalStatusListener!!)
                Log.d(TAG, "Thermal listener unregistered")
            } catch (e: Exception) {
                Log.w(TAG, "Error unregistering thermal listener", e)
            }
        }
        thermalStatusListener = null
        isRegistered = false
    }
}
