/*
Copyright (c) 2026 MultiSet AI. All rights reserved.
Licensed under the MultiSet License. You may not use this file except in compliance with the License. and you can't re-distribute this file without a prior notice
For license details, visit www.multiset.ai.
Redistribution in source or binary forms must retain this notice.
*/

package com.multiset.wearable.vps.localization

import android.graphics.Bitmap

/**
 * Represents the current state of the localization process
 */
enum class LocalizationState {
    IDLE,           // Ready to localize
    CAPTURING,      // Photo capture in progress
    LOCALIZING,     // Sending to API
    SUCCESS,        // Localization successful
    FAILED,         // Localization failed (pose not found)
    ERROR           // An error occurred
}

data class LocalizationUiState(
    val state: LocalizationState = LocalizationState.IDLE,
    val capturedPhoto: Bitmap? = null,      // Captured photo for localization
    val errorMessage: String? = null,
    val deviceName: String? = null,
    val deviceId: String? = null,
    val localizationResult: LocalizationResult? = null,
) {
    val isLocalizing: Boolean = state == LocalizationState.CAPTURING ||
                                state == LocalizationState.LOCALIZING

    val canLocalize: Boolean = state == LocalizationState.IDLE ||
                               state == LocalizationState.SUCCESS ||
                               state == LocalizationState.FAILED ||
                               state == LocalizationState.ERROR

    val statusText: String = when (state) {
        LocalizationState.IDLE -> "Ready"
        LocalizationState.CAPTURING -> "Capturing..."
        LocalizationState.LOCALIZING -> "Localizing..."
        LocalizationState.SUCCESS -> "Localized"
        LocalizationState.FAILED -> "Not Found"
        LocalizationState.ERROR -> "Error"
    }
}
