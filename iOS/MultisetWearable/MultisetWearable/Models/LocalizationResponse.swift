/*
Copyright (c) 2026 MultiSet AI. All rights reserved.
Licensed under the MultiSet License. You may not use this file except in compliance with the License. and you can't re-distribute this file without a prior notice
For license details, visit www.multiset.ai.
Redistribution in source or binary forms must retain this notice.
*/

import Foundation

/// Response models for the Multiset Localization API

struct LocalizationResult: Decodable {
    let poseFound: Bool
    let estimatedPose: EstimatedPose?
    let trackingPose: TrackingPose?
    let mapCodes: [String]?
    let confidence: Float?
    let message: String?

    // Root-level position/rotation (actual API response format)
    let position: Position?
    let rotation: Rotation?

    init(
        poseFound: Bool,
        estimatedPose: EstimatedPose? = nil,
        trackingPose: TrackingPose? = nil,
        mapCodes: [String]? = nil,
        confidence: Float? = nil,
        message: String? = nil,
        position: Position? = nil,
        rotation: Rotation? = nil
    ) {
        self.poseFound = poseFound
        self.estimatedPose = estimatedPose
        self.trackingPose = trackingPose
        self.mapCodes = mapCodes
        self.confidence = confidence
        self.message = message
        self.position = position
        self.rotation = rotation
    }

    /// Returns the pose position from either root level or estimatedPose
    var posePosition: Position? {
        position ?? estimatedPose?.position ?? trackingPose?.position
    }

    /// Returns the pose rotation from either root level or estimatedPose
    var poseRotation: Rotation? {
        rotation ?? estimatedPose?.rotation ?? trackingPose?.rotation
    }

    /// User-friendly result message
    var displayMessage: String {
        if poseFound {
            if let confidence = confidence {
                return String(format: "Localization successful (%.0f%% confidence)", confidence * 100)
            }
            return "Localization successful"
        } else {
            return message ?? "Pose not found"
        }
    }
}

struct EstimatedPose: Decodable {
    let position: Position
    let rotation: Rotation
}

struct TrackingPose: Decodable {
    let position: Position
    let rotation: Rotation
}

struct Position: Decodable {
    let x: Float
    let y: Float
    let z: Float

    var description: String {
        String(format: "(%.2f, %.2f, %.2f)", x, y, z)
    }

    /// Distance from map origin in meters
    var distanceFromOrigin: Float {
        sqrt(x * x + y * y + z * z)
    }
}

struct Rotation: Codable {
    let x: Float
    let y: Float
    let z: Float
    let w: Float

    var description: String {
        String(format: "(%.2f, %.2f, %.2f, %.2f)", x, y, z, w)
    }

    /// Legacy conversion (no longer needed since isRightHanded=false)
    /// API now returns left-handed coordinates directly matching Unity
    var toUnityLeftHanded: Rotation {
        self  // No conversion needed
    }
}
