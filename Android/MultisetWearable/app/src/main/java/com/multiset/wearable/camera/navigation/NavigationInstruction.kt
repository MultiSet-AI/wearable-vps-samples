/*
Copyright (c) 2026 MultiSet AI. All rights reserved.
Licensed under the MultiSet License. You may not use this file except in compliance with the License. and you can't re-distribute this file without a prior notice
For license details, visit www.multiset.ai.
Redistribution in source or binary forms must retain this notice.
*/

// Navigation + localization audio cue types, ported from the iOS NavigationInstruction.swift.
// `audioFileName` is the res/raw resource base name (e.g. R.raw.move_forward).

package com.multiset.wearable.vps.navigation

enum class NavigationInstruction(val audioFileName: String, val description: String) {
    MOVE_FORWARD("move_forward", "Move forward"),
    TURN_LEFT("turn_left", "Turn left"),
    TURN_RIGHT("turn_right", "Turn right"),
    SLIGHT_LEFT("slight_left", "Slight left"),
    SLIGHT_RIGHT("slight_right", "Slight right"),
    TURN_AROUND("turn_around", "Turn around"),
    DESTINATION_REACHED("destination_reached", "You have arrived"),
    NAVIGATION_STARTED("navigation_started", "Navigation started"),
    RECALCULATING("recalculating", "Recalculating route"),
}

enum class LocalizationAudioType(val audioFileName: String, val fallbackText: String) {
    LOCALIZING("localizing", "Localizing"),
    SUCCESS("localization_successful", "Localization successful"),
    FAILED("localization_failed", "Localization failed"),
}
