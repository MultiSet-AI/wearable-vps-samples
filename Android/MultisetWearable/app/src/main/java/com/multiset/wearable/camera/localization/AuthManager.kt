/*
Copyright (c) 2026 MultiSet AI. All rights reserved.
Licensed under the MultiSet License. You may not use this file except in compliance with the License. and you can't re-distribute this file without a prior notice
For license details, visit www.multiset.ai.
Redistribution in source or binary forms must retain this notice.
*/

package com.multiset.wearable.vps.localization

import android.util.Base64
import android.util.Log
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import okhttp3.MediaType.Companion.toMediaType
import okhttp3.OkHttpClient
import okhttp3.Request
import okhttp3.RequestBody.Companion.toRequestBody
import org.json.JSONObject
import java.util.concurrent.TimeUnit

/**
 * Manages authentication with the Multiset API
 */
class AuthManager {

    companion object {
        private const val TAG = "AuthManager"

        @Volatile
        private var instance: AuthManager? = null

        fun getInstance(): AuthManager {
            return instance ?: synchronized(this) {
                instance ?: AuthManager().also { instance = it }
            }
        }
    }

    private val client = OkHttpClient.Builder()
        .connectTimeout(30, TimeUnit.SECONDS)
        .readTimeout(30, TimeUnit.SECONDS)
        .writeTimeout(30, TimeUnit.SECONDS)
        .build()

    private var cachedToken: String? = null
    private var tokenExpiry: Long = 0

    /**
     * Get authentication token, using cached token if still valid
     */
    suspend fun getToken(): Result<String> = withContext(Dispatchers.IO) {
        // Return cached token if still valid (with 5 minute buffer)
        cachedToken?.let { token ->
            if (System.currentTimeMillis() < tokenExpiry - 300000) {
                return@withContext Result.success(token)
            }
        }

        // Fetch new token
        return@withContext fetchNewToken()
    }

    /**
     * Fetch a new authentication token from the API
     */
    private suspend fun fetchNewToken(): Result<String> = withContext(Dispatchers.IO) {
        try {
            if (!SDKConfig.isConfigured()) {
                return@withContext Result.failure(
                    IllegalStateException("SDK not configured. Call SDKConfig.configure() first.")
                )
            }

            val credentials = "${SDKConfig.CLIENT_ID}:${SDKConfig.CLIENT_SECRET}"
            val authData = Base64.encodeToString(credentials.toByteArray(), Base64.NO_WRAP)

            val requestBody = "".toRequestBody("application/json".toMediaType())

            val request = Request.Builder()
                .url(SDKConfig.AUTH_URL)
                .addHeader("Authorization", "Basic $authData")
                .post(requestBody)
                .build()

            Log.d(TAG, "Requesting authentication token...")

            val response = client.newCall(request).execute()
            val responseBody = response.body?.string()

            if (!response.isSuccessful) {
                Log.e(TAG, "Auth failed with code: ${response.code}, body: $responseBody")
                return@withContext Result.failure(
                    Exception("Authentication failed: ${response.code}")
                )
            }

            val json = JSONObject(responseBody ?: "{}")
            val token = json.optString("token", "")

            if (token.isEmpty()) {
                Log.e(TAG, "No token in response: $responseBody")
                return@withContext Result.failure(
                    Exception("No token received from server")
                )
            }

            // Cache token for 1 hour (typical token validity)
            cachedToken = token
            tokenExpiry = System.currentTimeMillis() + 3600000

            Log.d(TAG, "Authentication successful, token cached")
            Result.success(token)

        } catch (e: Exception) {
            Log.e(TAG, "Authentication error", e)
            Result.failure(e)
        }
    }

    /**
     * Clear cached token (for logout or token refresh)
     */
    fun clearToken() {
        cachedToken = null
        tokenExpiry = 0
    }

    /**
     * Force re-authentication with current credentials
     * Clears cached token and fetches a new one
     */
    suspend fun forceReauthenticate(): Result<String> {
        Log.d(TAG, "Force re-authentication requested")
        clearToken()
        return fetchNewToken()
    }

    /**
     * Check if we have a valid cached token
     */
    fun hasValidToken(): Boolean {
        return cachedToken != null && System.currentTimeMillis() < tokenExpiry - 300000
    }
}
