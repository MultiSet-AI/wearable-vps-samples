/*
Copyright (c) 2026 MultiSet AI. All rights reserved.
Licensed under the MultiSet License. You may not use this file except in compliance with the License. and you can't re-distribute this file without a prior notice
For license details, visit www.multiset.ai.
Redistribution in source or binary forms must retain this notice.
*/

package com.multiset.wearable.vps.stream

import android.graphics.Bitmap
import com.multiset.wearable.vps.localization.LocalizationResult

/** High-level streaming lifecycle, mirroring the iOS StreamingStatus. */
enum class StreamingStatus { STOPPED, WAITING, STREAMING }

/** Localization progress, mirroring the iOS LocalizationStatus. */
enum class LocalizationStatus { IDLE, CAPTURING, LOCALIZING, SUCCESS, FAILURE, ERROR }

/**
 * UI state for [StreamSessionViewModel] — the shared engine behind the Localization Demo
 * and Record Video Stream screens.
 */
data class StreamSessionUiState(
    val streamingStatus: StreamingStatus = StreamingStatus.STOPPED,
    val videoFrame: Bitmap? = null,
    val videoFrameCount: Int = 0,
    val hasReceivedFirstFrame: Boolean = false,
    val hasActiveDevice: Boolean = false,
    val localizationStatus: LocalizationStatus = LocalizationStatus.IDLE,
    val localizationResult: LocalizationResult? = null,
    val capturedPhoto: Bitmap? = null,
    val errorMessage: String? = null,
) {
    val isStreaming: Boolean
        get() = streamingStatus != StreamingStatus.STOPPED

    val isLocalizing: Boolean
        get() = localizationStatus == LocalizationStatus.CAPTURING ||
            localizationStatus == LocalizationStatus.LOCALIZING
}
