/*
Copyright (c) 2026 MultiSet AI. All rights reserved.
Licensed under the MultiSet License. You may not use this file except in compliance with the License. and you can't re-distribute this file without a prior notice
For license details, visit www.multiset.ai.
Redistribution in source or binary forms must retain this notice.
*/

package com.multiset.wearable.vps.localization

/**
 * Data class representing the multipart form data payload for localization API
 */
data class LocalizationPayload(
    val imageData: ByteArray,
    val imageMimeType: String,
    val deviceName: String,
    val deviceId: String,
    val timestamp: Long,
) {
    override fun equals(other: Any?): Boolean {
        if (this === other) return true
        if (javaClass != other?.javaClass) return false
        other as LocalizationPayload
        return imageData.contentEquals(other.imageData) &&
               imageMimeType == other.imageMimeType &&
               deviceName == other.deviceName &&
               deviceId == other.deviceId &&
               timestamp == other.timestamp
    }

    override fun hashCode(): Int {
        var result = imageData.contentHashCode()
        result = 31 * result + imageMimeType.hashCode()
        result = 31 * result + deviceName.hashCode()
        result = 31 * result + deviceId.hashCode()
        result = 31 * result + timestamp.hashCode()
        return result
    }

    override fun toString(): String {
        return "LocalizationPayload(" +
               "imageSize=${imageData.size} bytes, " +
               "mimeType=$imageMimeType, " +
               "deviceName=$deviceName, " +
               "deviceId=$deviceId, " +
               "timestamp=$timestamp)"
    }
}
