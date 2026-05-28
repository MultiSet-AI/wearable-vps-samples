/*
Copyright (c) 2026 MultiSet AI. All rights reserved.
Licensed under the MultiSet License. You may not use this file except in compliance with the License. and you can't re-distribute this file without a prior notice
For license details, visit www.multiset.ai.
Redistribution in source or binary forms must retain this notice.
*/

package com.multiset.wearable.vps.localization

import org.json.JSONObject

/**
 * Response models for the Multiset Localization API
 */

data class Position(
    val x: Float,
    val y: Float,
    val z: Float
)

data class Rotation(
    val x: Float,
    val y: Float,
    val z: Float,
    val w: Float
)

data class EstimatedPose(
    val position: Position,
    val rotation: Rotation
)

data class TrackingPose(
    val position: Position,
    val rotation: Rotation
)

data class LocalizationResult(
    val poseFound: Boolean,
    /** Root-level pose, when the API returns it there (preferred, matching iOS). */
    val position: Position? = null,
    val rotation: Rotation? = null,
    val estimatedPose: EstimatedPose? = null,
    val trackingPose: TrackingPose? = null,
    val mapIds: List<String> = emptyList(),
    val confidence: Float? = null,
    val message: String? = null
) {
    /** Resolved pose position: root → estimatedPose → trackingPose (matches iOS posePosition). */
    val posePosition: Position?
        get() = position ?: estimatedPose?.position ?: trackingPose?.position

    /** Resolved pose rotation: root → estimatedPose → trackingPose (matches iOS poseRotation). */
    val poseRotation: Rotation?
        get() = rotation ?: estimatedPose?.rotation ?: trackingPose?.rotation

    companion object {
        private fun parsePosition(o: JSONObject?): Position? =
            o?.let {
                Position(
                    it.optDouble("x", 0.0).toFloat(),
                    it.optDouble("y", 0.0).toFloat(),
                    it.optDouble("z", 0.0).toFloat(),
                )
            }

        private fun parseRotation(o: JSONObject?): Rotation? =
            o?.let {
                Rotation(
                    it.optDouble("x", 0.0).toFloat(),
                    it.optDouble("y", 0.0).toFloat(),
                    it.optDouble("z", 0.0).toFloat(),
                    it.optDouble("w", 1.0).toFloat(),
                )
            }

        fun fromJson(json: JSONObject): LocalizationResult {
            val poseFound = json.optBoolean("poseFound", false)

            if (!poseFound) {
                return LocalizationResult(
                    poseFound = false,
                    message = json.optString("message", "Pose not found")
                )
            }

            // Root-level pose (some responses return position/rotation at the top level).
            val rootPosition = parsePosition(json.optJSONObject("position"))
            val rootRotation = parseRotation(json.optJSONObject("rotation"))

            val estimatedPoseJson = json.optJSONObject("estimatedPose")
            val trackingPoseJson = json.optJSONObject("trackingPose")

            val estimatedPose = estimatedPoseJson?.let { epJson ->
                val posJson = epJson.optJSONObject("position")
                val rotJson = epJson.optJSONObject("rotation")

                EstimatedPose(
                    position = Position(
                        x = posJson?.optDouble("x", 0.0)?.toFloat() ?: 0f,
                        y = posJson?.optDouble("y", 0.0)?.toFloat() ?: 0f,
                        z = posJson?.optDouble("z", 0.0)?.toFloat() ?: 0f
                    ),
                    rotation = Rotation(
                        x = rotJson?.optDouble("x", 0.0)?.toFloat() ?: 0f,
                        y = rotJson?.optDouble("y", 0.0)?.toFloat() ?: 0f,
                        z = rotJson?.optDouble("z", 0.0)?.toFloat() ?: 0f,
                        w = rotJson?.optDouble("w", 1.0)?.toFloat() ?: 1f
                    )
                )
            }

            val trackingPose = trackingPoseJson?.let { tpJson ->
                val posJson = tpJson.optJSONObject("position")
                val rotJson = tpJson.optJSONObject("rotation")

                TrackingPose(
                    position = Position(
                        x = posJson?.optDouble("x", 0.0)?.toFloat() ?: 0f,
                        y = posJson?.optDouble("y", 0.0)?.toFloat() ?: 0f,
                        z = posJson?.optDouble("z", 0.0)?.toFloat() ?: 0f
                    ),
                    rotation = Rotation(
                        x = rotJson?.optDouble("x", 0.0)?.toFloat() ?: 0f,
                        y = rotJson?.optDouble("y", 0.0)?.toFloat() ?: 0f,
                        z = rotJson?.optDouble("z", 0.0)?.toFloat() ?: 0f,
                        w = rotJson?.optDouble("w", 1.0)?.toFloat() ?: 1f
                    )
                )
            }

            val mapIds = mutableListOf<String>()
            json.optJSONArray("mapIds")?.let { array ->
                for (i in 0 until array.length()) {
                    mapIds.add(array.getString(i))
                }
            }

            // Parse confidence value
            val confidence = if (json.has("confidence")) {
                json.optDouble("confidence", 0.0).toFloat()
            } else {
                null
            }

            return LocalizationResult(
                poseFound = true,
                position = rootPosition,
                rotation = rootRotation,
                estimatedPose = estimatedPose,
                trackingPose = trackingPose,
                mapIds = mapIds,
                confidence = confidence
            )
        }
    }
}

