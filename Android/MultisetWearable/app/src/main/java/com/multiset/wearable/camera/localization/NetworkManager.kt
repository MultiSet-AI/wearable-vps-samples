/*
Copyright (c) 2026 MultiSet AI. All rights reserved.
Licensed under the MultiSet License. You may not use this file except in compliance with the License. and you can't re-distribute this file without a prior notice
For license details, visit www.multiset.ai.
Redistribution in source or binary forms must retain this notice.
*/

package com.multiset.wearable.vps.localization

import android.util.Log
import com.multiset.wearable.vps.BuildConfig
import com.multiset.wearable.vps.network.RetryInterceptor
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import okhttp3.MediaType.Companion.toMediaType
import okhttp3.MultipartBody
import okhttp3.OkHttpClient
import okhttp3.Request
import okhttp3.RequestBody.Companion.toRequestBody
import org.json.JSONObject
import java.util.concurrent.TimeUnit

/**
 * Handles network requests for the Multiset Localization API
 * Uses single-frame localization via query-form endpoint
 *
 * Production optimizations:
 * - Reduced timeouts (15s connect, 30s read/write)
 * - Automatic retry with exponential backoff
 * - Conditional logging based on build type
 */
class NetworkManager {

    companion object {
        private const val TAG = "NetworkManager"

        // Conditional logging helpers
        private fun logD(message: String) {
            if (BuildConfig.ENABLE_VERBOSE_LOGGING) {
                Log.d(TAG, message)
            }
        }

        private fun logI(message: String) {
            Log.i(TAG, message) // Always log important info
        }

        private fun logE(message: String, e: Exception? = null) {
            if (e != null) {
                Log.e(TAG, message, e)
            } else {
                Log.e(TAG, message)
            }
        }

        @Volatile
        private var instance: NetworkManager? = null

        fun getInstance(): NetworkManager {
            return instance ?: synchronized(this) {
                instance ?: NetworkManager().also { instance = it }
            }
        }
    }

    // Production-ready OkHttpClient with reduced timeouts and retry logic
    private val client = OkHttpClient.Builder()
        .connectTimeout(15, TimeUnit.SECONDS)  // Reduced from 60s
        .readTimeout(30, TimeUnit.SECONDS)     // Reduced from 60s
        .writeTimeout(30, TimeUnit.SECONDS)    // Reduced from 60s
        .addInterceptor(RetryInterceptor(
            maxRetries = 3,
            initialDelayMs = 1000,
            retryOnCodes = setOf(408, 429, 500, 502, 503, 504)
        ))
        .build()

    private val authManager = AuthManager.getInstance()

    /**
     * Send a single-frame localization request
     * Uses the query-form endpoint with queryImage parameter
     */
    suspend fun sendLocalizationRequest(
        imageBytes: ByteArray,
        imageWidth: Int,
        imageHeight: Int,
        isRightHanded: Boolean = false
    ): Result<LocalizationResult> = withContext(Dispatchers.IO) {
        try {
            logD("Preparing localization request: ${imageBytes.size} bytes, ${imageWidth}x${imageHeight}")

            // Get auth token
            val tokenResult = authManager.getToken()
            if (tokenResult.isFailure) {
                return@withContext Result.failure(
                    tokenResult.exceptionOrNull() ?: Exception("Failed to get auth token")
                )
            }
            val token = tokenResult.getOrThrow()

            // Build multipart request for single frame
            val requestBody = buildSingleFrameBody(imageBytes, imageWidth, imageHeight, isRightHanded)

            val request = Request.Builder()
                .url(SDKConfig.QUERY_URL)
                .addHeader("Authorization", "Bearer $token")
                .post(requestBody)
                .build()

            logD("Sending localization request")

            val response = client.newCall(request).execute()
            val responseBody = response.body?.string()

            logD("Response code: ${response.code}")

            if (!response.isSuccessful) {
                // Only log detailed error in debug builds
                if (BuildConfig.ENABLE_VERBOSE_LOGGING) {
                    logE("Localization failed: ${response.code} - $responseBody")
                }
                return@withContext Result.failure(
                    Exception("Localization failed: ${response.code}")
                )
            }

            val json = JSONObject(responseBody ?: "{}")
            val result = LocalizationResult.fromJson(json)

            // Always log localization result
            logI("Localization result: poseFound=${result.poseFound}")
            if (result.poseFound && BuildConfig.ENABLE_VERBOSE_LOGGING) {
                result.estimatedPose?.let { pose ->
                    logD("Position: (${pose.position.x}, ${pose.position.y}, ${pose.position.z})")
                    logD("Rotation: (${pose.rotation.x}, ${pose.rotation.y}, ${pose.rotation.z}, ${pose.rotation.w})")
                }
            }

            Result.success(result)

        } catch (e: Exception) {
            logE("Localization error: ${e.message}")
            if (BuildConfig.ENABLE_VERBOSE_LOGGING) {
                logE("Localization error details", e)
            }
            Result.failure(e)
        }
    }

    /**
     * Build multipart request body for single-frame localization
     * Uses queryImage parameter as per the API specification
     */
    private fun buildSingleFrameBody(
        imageBytes: ByteArray,
        imageWidth: Int,
        imageHeight: Int,
        isRightHanded: Boolean = false
    ): MultipartBody {
        // Calculate camera intrinsics based on actual image dimensions
        val intrinsics = calculateIntrinsics(imageWidth, imageHeight)

        val builder = MultipartBody.Builder()
            .setType(MultipartBody.FORM)
            // Camera intrinsics. Left-handed (false) matches the iOS app and the Unity
            // navigation data coordinate system.
            .addFormDataPart("isRightHanded", if (isRightHanded) "true" else "false")
            .addFormDataPart("fx", intrinsics.fx.toString())
            .addFormDataPart("fy", intrinsics.fy.toString())
            .addFormDataPart("px", intrinsics.px.toString())
            .addFormDataPart("py", intrinsics.py.toString())
            .addFormDataPart("width", imageWidth.toString())
            .addFormDataPart("height", imageHeight.toString())

        // Add map code or map set code
        if (SDKConfig.MAP_CODE.isNotEmpty()) {
            builder.addFormDataPart("mapCode", SDKConfig.MAP_CODE)
            logD("Using mapCode: ${SDKConfig.MAP_CODE}")
        }
        if (SDKConfig.MAP_SET_CODE.isNotEmpty()) {
            builder.addFormDataPart("mapSetCode", SDKConfig.MAP_SET_CODE)
            logD("Using mapSetCode: ${SDKConfig.MAP_SET_CODE}")
        }

        // Add single image with "queryImage" field name
        builder.addFormDataPart(
            "queryImage",
            "frame.jpg",
            imageBytes.toRequestBody("image/jpeg".toMediaType())
        )

        logD("Request intrinsics: fx=${intrinsics.fx}, fy=${intrinsics.fy}, " +
                "px=${intrinsics.px}, py=${intrinsics.py}")

        return builder.build()
    }

    /**
     * Calculate camera intrinsics based on image dimensions
     * For Ray-Ban Meta glasses, the focal lengths should be equal (square pixels)
     * and scale uniformly based on image resolution
     */
    private fun calculateIntrinsics(width: Int, height: Int): CameraIntrinsics {
        val baseIntrinsics = SDKConfig.RayBanMetaIntrinsics

        logD("Calculating intrinsics for image: ${width}x${height}")
        logD("Base intrinsics: ${baseIntrinsics.WIDTH}x${baseIntrinsics.HEIGHT}, " +
                "fx=${baseIntrinsics.FX}, fy=${baseIntrinsics.FY}")

        // Full capture resolution (1080x1440) — use configured intrinsics directly
        if (width == baseIntrinsics.WIDTH && height == baseIntrinsics.HEIGHT) {
            logD("Using base intrinsics directly (full capture resolution)")
            return CameraIntrinsics(
                fx = baseIntrinsics.FX,
                fy = baseIntrinsics.FY,
                px = baseIntrinsics.PX,
                py = baseIntrinsics.PY
            )
        }

        // Half capture resolution (540x720) — scale focal lengths by 0.5, calibrated half PP
        if (width == baseIntrinsics.HALF_WIDTH && height == baseIntrinsics.HALF_HEIGHT) {
            logD("Using half-resolution intrinsics")
            return CameraIntrinsics(
                fx = baseIntrinsics.FX * 0.5f,
                fy = baseIntrinsics.FY * 0.5f,
                px = baseIntrinsics.HALF_PX,
                py = baseIntrinsics.HALF_PY
            )
        }

        // Medium streaming resolution (504x896) — pre-computed intrinsics
        if (width == baseIntrinsics.MEDIUM_WIDTH && height == baseIntrinsics.MEDIUM_HEIGHT) {
            logD("Using medium-resolution intrinsics")
            return CameraIntrinsics(
                fx = baseIntrinsics.MEDIUM_FX,
                fy = baseIntrinsics.MEDIUM_FY,
                px = baseIntrinsics.MEDIUM_PX,
                py = baseIntrinsics.MEDIUM_PY
            )
        }

        // Calculate uniform scale factor based on the larger dimension
        // This preserves the aspect ratio of focal lengths
        val baseAspect = baseIntrinsics.WIDTH.toFloat() / baseIntrinsics.HEIGHT
        val imageAspect = width.toFloat() / height

        val scale: Float
        val px: Float
        val py: Float

        if (kotlin.math.abs(baseAspect - imageAspect) < 0.05f) {
            // Similar aspect ratio - simple scaling
            scale = width.toFloat() / baseIntrinsics.WIDTH
            px = baseIntrinsics.PX * scale
            py = baseIntrinsics.PY * scale
            logD("Similar aspect ratio, scale: $scale")
        } else {
            // Different aspect ratio - use uniform scale and center principal point
            scale = minOf(
                width.toFloat() / baseIntrinsics.WIDTH,
                height.toFloat() / baseIntrinsics.HEIGHT
            )
            // Principal point at image center
            px = width / 2f
            py = height / 2f
            logD("Different aspect ratio, scale: $scale, centered principal point")
        }

        val result = CameraIntrinsics(
            fx = baseIntrinsics.FX * scale,
            fy = baseIntrinsics.FY * scale,  // Same as fx for square pixels
            px = px,
            py = py
        )

        logD("Calculated intrinsics: fx=${result.fx}, fy=${result.fy}")

        return result
    }

    /**
     * Camera intrinsics data class
     */
    private data class CameraIntrinsics(
        val fx: Float,
        val fy: Float,
        val px: Float,
        val py: Float
    )
}
