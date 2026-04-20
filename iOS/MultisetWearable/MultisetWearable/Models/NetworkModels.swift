/*
Copyright (c) 2026 MultiSet AI. All rights reserved.
Licensed under the MultiSet License. You may not use this file except in compliance with the License. and you can't re-distribute this file without a prior notice
For license details, visit www.multiset.ai.
Redistribution in source or binary forms must retain this notice.
*/

import Foundation

// MARK: - Network Message Types

/// Shared protocol with iOS SDK multiplayer — must match exactly
enum MessageType: UInt8, Codable {
    case poseUpdate = 1
    case playerInfo = 2
}

struct PlayerInfo: Codable {
    let playerName: String
    let colorR: Float
    let colorG: Float
    let colorB: Float
}

struct PoseUpdate: Codable {
    let positionX: Float
    let positionY: Float
    let positionZ: Float
    let rotationX: Float
    let rotationY: Float
    let rotationZ: Float
    let rotationW: Float
    let isLocalized: Bool
}

struct NetworkMessage: Codable {
    let type: MessageType
    let senderID: String
    let payload: Data
}
