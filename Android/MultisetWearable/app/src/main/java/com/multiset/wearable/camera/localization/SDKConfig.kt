/*
Copyright (c) 2026 MultiSet AI. All rights reserved.
Licensed under the MultiSet License. You may not use this file except in compliance with the License. and you can't re-distribute this file without a prior notice
For license details, visit www.multiset.ai.
Redistribution in source or binary forms must retain this notice.
*/

package com.multiset.wearable.vps.localization

import android.content.Context
import android.content.SharedPreferences
import android.util.Log
import kotlin.math.atan
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow

/**
 * Configuration for the Multiset Localization SDK
 */
object SDKConfig {
    private const val TAG = "SDKConfig"
    private const val PREFS_NAME = "metacamera_sdk_prefs"

    // API Endpoints
    const val AUTH_URL = "https://api.multiset.ai/v1/m2m/token"
    const val QUERY_URL = "https://api.multiset.ai/v1/vps/map/query-form"

    // Authentication credentials - sourced from BuildConfig at app start; not user-editable.
    var CLIENT_ID = ""
        private set
    var CLIENT_SECRET = ""
        private set

    // Map configuration - Set one of these based on your use case
    var MAP_CODE = ""      // For single map localization
    var MAP_SET_CODE = ""  // For mapset localization

    // Keys for SharedPreferences
    private const val KEY_MAP_CODE = "map_code"
    private const val KEY_MAP_SET_CODE = "map_set_code"

    // Bumped whenever the map code/mapset changes, so observers (e.g. the navigation map)
    // can refresh instantly.
    private val _mapConfigVersion = MutableStateFlow(0)
    val mapConfigVersion: StateFlow<Int> = _mapConfigVersion.asStateFlow()

    /**
     * Camera intrinsics presets for Ray-Ban Meta glasses.
     * Since official documentation is limited, these are calculated estimates
     * based on different assumed horizontal field-of-view values.
     *
     * Formula: fx = width / (2 * tan(hFOV/2))
     */
    enum class IntrinsicsPreset(
        val displayName: String,
        val focalLength: Float,
        val estimatedFovDegrees: Int,
        val description: String
    ) {
        // Calibrated from 3K video, scaled to the 1080x1440 capture resolution.
        // Mirrors the iOS app's calibrated intrinsics (recommended default).
        CALIBRATED(
            "Calibrated (Recommended)",
            844.5f,
            65,
            "Calibrated from 3K video (~65 deg FOV)"
        ),

        // Wide FOV presets (focal lengths computed for 1080px width)
        WIDE_100_DEG(
            "Wide 100 deg FOV",
            454.0f,
            100,
            "Calculated for ~100 deg horizontal FOV"
        ),
        WIDE_90_DEG(
            "Wide 90 deg FOV",
            540.0f,
            90,
            "Calculated for ~90 deg horizontal FOV"
        ),

        // Moderate FOV presets
        MODERATE_80_DEG(
            "Moderate 80 deg FOV",
            643.0f,
            80,
            "Calculated for ~80 deg horizontal FOV"
        ),
        MODERATE_70_DEG(
            "Moderate 70 deg FOV",
            771.0f,
            70,
            "Calculated for ~70 deg horizontal FOV"
        ),

        DEFAULT_64_DEG(
            "Default (64 deg FOV)",
            864.0f,
            64,
            "Calculated for ~64 deg horizontal FOV"
        ),

        // Narrow FOV presets - if camera has narrower lens
        NARROW_56_DEG(
            "Narrow 56 deg FOV",
            1017.0f,
            56,
            "Calculated for ~56 deg horizontal FOV"
        ),

        // Custom - user can set their own values
        CUSTOM(
            "Custom",
            0f,
            0,
            "User-defined focal length"
        )
    }

    /**
     * Ray-Ban Meta camera intrinsics - now configurable for tuning
     */
    object RayBanMetaIntrinsics {
        // Full capture resolution (1080x1440). Calibrated from 3K video (1632x2176)
        // and scaled to the capture resolution — mirrors the iOS app's calibrated values.
        const val WIDTH = 1080
        const val HEIGHT = 1440

        // Mutable focal lengths - default to the calibrated values; adjustable via presets
        var FX = 844.5f
            private set
        var FY = 845.8f
            private set

        // Calibrated principal point (slightly off-center, as is typical)
        const val PX: Float = 540.7f  // 817.052 * 0.6618
        const val PY: Float = 727.5f  // 1099.243 * 0.6618

        const val IS_RIGHT_HANDED = true

        // Half capture resolution (540x720) — captured JPEG is downscaled 0.5 before upload
        const val HALF_WIDTH = 540
        const val HALF_HEIGHT = 720
        const val HALF_PX: Float = 270.35f  // 540.7 * 0.5
        const val HALF_PY: Float = 363.75f  // 727.5 * 0.5

        // Medium streaming resolution (504x896) — pre-computed (9:16 center-crop of sensor)
        const val MEDIUM_WIDTH = 504
        const val MEDIUM_HEIGHT = 896
        const val MEDIUM_FX: Float = 525.5f
        const val MEDIUM_FY: Float = 526.3f
        const val MEDIUM_PX: Float = 252.0f
        const val MEDIUM_PY: Float = 448.0f

        var currentPreset: IntrinsicsPreset = IntrinsicsPreset.CALIBRATED
            private set

        /**
         * Apply a preset to the intrinsics
         */
        fun applyPreset(preset: IntrinsicsPreset) {
            when (preset) {
                IntrinsicsPreset.CUSTOM -> {
                    // Custom values are set via setCustomIntrinsics
                    currentPreset = preset
                    return
                }
                IntrinsicsPreset.CALIBRATED -> {
                    // Calibrated fx/fy differ slightly; use the measured pair
                    FX = 844.5f
                    FY = 845.8f
                }
                else -> {
                    FX = preset.focalLength
                    FY = preset.focalLength
                }
            }
            currentPreset = preset
            Log.i(TAG, "Applied intrinsics preset: ${preset.displayName} (fx=$FX, fy=$FY)")
        }

        /**
         * Set custom intrinsics values
         */
        fun setCustomIntrinsics(fx: Float, fy: Float = fx) {
            FX = fx
            FY = fy
            currentPreset = IntrinsicsPreset.CUSTOM
            Log.i(TAG, "Applied custom intrinsics: fx=$FX, fy=$FY")
        }

        /**
         * Calculate horizontal FOV from current focal length
         * FOV = 2 * atan(width / (2 * fx))
         */
        fun getHorizontalFovDegrees(): Float {
            val fovRadians = 2 * atan(WIDTH.toDouble() / (2 * FX))
            return Math.toDegrees(fovRadians).toFloat()
        }

        /**
         * Calculate focal length from desired horizontal FOV
         * fx = width / (2 * tan(hFOV/2))
         */
        fun calculateFocalLengthForFov(fovDegrees: Float): Float {
            val fovRadians = Math.toRadians(fovDegrees.toDouble())
            return (WIDTH / (2 * kotlin.math.tan(fovRadians / 2))).toFloat()
        }
    }

    private var prefs: SharedPreferences? = null
    private var isInitialized = false

    /**
     * Initialize SDK configuration.
     * Call this from MainActivity after app starts.
     *
     * @param context Application context
     * @param clientId Default client ID from BuildConfig (multiset.properties)
     * @param clientSecret Default client secret from BuildConfig (multiset.properties)
     * @param mapCode Default map code from BuildConfig (multiset.properties)
     * @param mapSetCode Default map set code from BuildConfig (multiset.properties)
     */
    fun initialize(
        context: Context,
        clientId: String,
        clientSecret: String,
        mapCode: String = "",
        mapSetCode: String = "",
    ) {
        prefs = context.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)

        // Credentials come from BuildConfig only — set at build time, never user-editable at runtime.
        CLIENT_ID = clientId
        CLIENT_SECRET = clientSecret

        // Map codes: prefer user-saved value (in-app Settings), fall back to BuildConfig defaults.
        MAP_CODE = prefs?.getString(KEY_MAP_CODE, mapCode) ?: mapCode
        MAP_SET_CODE = prefs?.getString(KEY_MAP_SET_CODE, mapSetCode) ?: mapSetCode
        _mapConfigVersion.value++

        loadStoredIntrinsics()

        isInitialized = true
        Log.i(TAG, "SDK initialized - intrinsics fx=${RayBanMetaIntrinsics.FX}, " +
                "preset=${RayBanMetaIntrinsics.currentPreset.displayName}")
        Log.i(TAG, "Credentials loaded: clientId=${if (CLIENT_ID.isNotEmpty()) "***" else "empty"}, " +
                "mapCode=${MAP_CODE.take(10)}...")
    }

    /**
     * Update map codes at runtime
     */
    fun updateMapCodes(mapCode: String, mapSetCode: String) {
        MAP_CODE = mapCode.trim()
        MAP_SET_CODE = mapSetCode.trim()
        _mapConfigVersion.value++
        Log.i(TAG, "Map codes updated: mapCode=${MAP_CODE.take(16)}, mapSetCode=${MAP_SET_CODE.take(16)}")
    }

    /**
     * Save all settings to SharedPreferences
     */
    fun saveSettings() {
        prefs?.edit()?.apply {
            putString(KEY_MAP_CODE, MAP_CODE)
            putString(KEY_MAP_SET_CODE, MAP_SET_CODE)
            apply()
        }
        Log.d(TAG, "Settings saved to SharedPreferences")
    }

    /**
     * Load intrinsics from SharedPreferences
     */
    private fun loadStoredIntrinsics() {
        prefs?.let { p ->
            val presetName = p.getString("intrinsics_preset", IntrinsicsPreset.CALIBRATED.name)
            val preset = IntrinsicsPreset.values().find { it.name == presetName }
                ?: IntrinsicsPreset.CALIBRATED

            if (preset == IntrinsicsPreset.CUSTOM) {
                val fx = p.getFloat("intrinsics_fx", 844.5f)
                val fy = p.getFloat("intrinsics_fy", 845.8f)
                RayBanMetaIntrinsics.setCustomIntrinsics(fx, fy)
            } else {
                RayBanMetaIntrinsics.applyPreset(preset)
            }
        }
    }

    /**
     * Save current intrinsics to SharedPreferences
     */
    fun saveIntrinsics() {
        prefs?.edit()?.apply {
            putString("intrinsics_preset", RayBanMetaIntrinsics.currentPreset.name)
            if (RayBanMetaIntrinsics.currentPreset == IntrinsicsPreset.CUSTOM) {
                putFloat("intrinsics_fx", RayBanMetaIntrinsics.FX)
                putFloat("intrinsics_fy", RayBanMetaIntrinsics.FY)
            }
            apply()
        }
        Log.d(TAG, "Saved intrinsics: preset=${RayBanMetaIntrinsics.currentPreset.name}, " +
                "fx=${RayBanMetaIntrinsics.FX}")
    }

    /**
     * Check if credentials were provided at build time
     */
    fun hasCredentials(): Boolean {
        return CLIENT_ID.isNotEmpty() && CLIENT_SECRET.isNotEmpty()
    }

    /**
     * Check if SDK is configured with valid credentials and a map
     */
    fun isConfigured(): Boolean {
        return hasCredentials() && (MAP_CODE.isNotEmpty() || MAP_SET_CODE.isNotEmpty())
    }

    /**
     * Get all available intrinsics presets
     */
    fun getAvailablePresets(): List<IntrinsicsPreset> {
        return IntrinsicsPreset.values().toList()
    }
}
