/*
Copyright (c) 2026 MultiSet AI. All rights reserved.
Licensed under the MultiSet License. You may not use this file except in compliance with the License. and you can't re-distribute this file without a prior notice
For license details, visit www.multiset.ai.
Redistribution in source or binary forms must retain this notice.
*/

package com.multiset.wearable.vps.network

import android.util.Log
import com.multiset.wearable.vps.BuildConfig
import okhttp3.Interceptor
import okhttp3.Response
import java.io.IOException
import kotlin.math.min
import kotlin.math.pow

/**
 * OkHttp interceptor that implements exponential backoff retry logic.
 *
 * Automatically retries failed requests with increasing delays:
 * - 1st retry: ~1 second delay
 * - 2nd retry: ~2 seconds delay
 * - 3rd retry: ~4 seconds delay
 *
 * Retries on:
 * - Network failures (IOException)
 * - Server errors (5xx)
 * - Request timeout (408)
 * - Too many requests (429)
 */
class RetryInterceptor(
    private val maxRetries: Int = 3,
    private val initialDelayMs: Long = 1000,
    private val maxDelayMs: Long = 30000,
    private val retryOnCodes: Set<Int> = setOf(408, 429, 500, 502, 503, 504)
) : Interceptor {

    companion object {
        private const val TAG = "RetryInterceptor"

        private fun logD(message: String) {
            if (BuildConfig.ENABLE_VERBOSE_LOGGING) {
                Log.d(TAG, message)
            }
        }

        private fun logW(message: String, e: Exception? = null) {
            if (BuildConfig.ENABLE_VERBOSE_LOGGING) {
                if (e != null) {
                    Log.w(TAG, message, e)
                } else {
                    Log.w(TAG, message)
                }
            }
        }
    }

    override fun intercept(chain: Interceptor.Chain): Response {
        val request = chain.request()
        var lastException: IOException? = null
        var response: Response? = null

        for (attempt in 0..maxRetries) {
            try {
                // Close previous response if retrying
                response?.close()

                if (attempt > 0) {
                    logD("Retry attempt $attempt for ${request.url}")
                }

                response = chain.proceed(request)

                // Success or non-retryable error
                if (response.isSuccessful || !retryOnCodes.contains(response.code)) {
                    return response
                }

                // Retryable error - log and prepare for retry
                if (attempt < maxRetries) {
                    val delay = calculateDelay(attempt)
                    logW("Request failed with ${response.code}, retrying in ${delay}ms " +
                            "(attempt ${attempt + 1}/$maxRetries)")
                    response.close()

                    try {
                        Thread.sleep(delay)
                    } catch (ie: InterruptedException) {
                        Thread.currentThread().interrupt()
                        throw IOException("Retry interrupted", ie)
                    }
                }
            } catch (e: IOException) {
                lastException = e

                if (attempt < maxRetries) {
                    val delay = calculateDelay(attempt)
                    logW("Request failed with exception, retrying in ${delay}ms " +
                            "(attempt ${attempt + 1}/$maxRetries)", e)

                    try {
                        Thread.sleep(delay)
                    } catch (ie: InterruptedException) {
                        Thread.currentThread().interrupt()
                        throw IOException("Retry interrupted", ie)
                    }
                }
            }
        }

        // All retries exhausted
        return response ?: throw lastException
            ?: IOException("Request failed after $maxRetries retries")
    }

    /**
     * Calculate delay with exponential backoff and jitter.
     *
     * Formula: delay = min(initialDelay * 2^attempt + jitter, maxDelay)
     * Jitter adds 0-30% randomness to prevent thundering herd
     */
    private fun calculateDelay(attempt: Int): Long {
        val exponentialDelay = initialDelayMs * 2.0.pow(attempt).toLong()
        val jitter = (Math.random() * 0.3 * exponentialDelay).toLong()
        return min(exponentialDelay + jitter, maxDelayMs)
    }
}
