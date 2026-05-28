/*
Copyright (c) 2026 MultiSet AI. All rights reserved.
Licensed under the MultiSet License. You may not use this file except in compliance with the License. and you can't re-distribute this file without a prior notice
For license details, visit www.multiset.ai.
Redistribution in source or binary forms must retain this notice.
*/

// Plays navigation/localization audio cues (res/raw MP3s), ported from the iOS
// NavigationAudioService.swift. Uses NAVIGATION_GUIDANCE audio attributes so cues duck
// other audio and route to the connected output (e.g. the glasses). Same cooldown rules
// as iOS: 3s for the same instruction, 1.5s between any instructions.

package com.multiset.wearable.vps.navigation

import android.content.Context
import android.media.AudioAttributes
import android.media.MediaPlayer
import android.util.Log

class NavigationAudioService(private val context: Context) {

    companion object {
        private const val TAG = "NavigationAudioService"
        private const val MIN_SAME_INSTRUCTION_INTERVAL_MS = 3000L
        private const val MIN_ANY_INSTRUCTION_INTERVAL_MS = 1500L
    }

    private val audioAttributes =
        AudioAttributes.Builder()
            .setUsage(AudioAttributes.USAGE_ASSISTANCE_NAVIGATION_GUIDANCE)
            .setContentType(AudioAttributes.CONTENT_TYPE_SPEECH)
            .build()

    private var player: MediaPlayer? = null
    private var lastInstruction: NavigationInstruction? = null
    private var lastInstructionTime: Long = 0L

    /** Play a navigation instruction, honoring cooldowns unless [force]. */
    fun playInstruction(instruction: NavigationInstruction, force: Boolean = false) {
        if (!force) {
            val elapsed = System.currentTimeMillis() - lastInstructionTime
            if (instruction == lastInstruction && elapsed < MIN_SAME_INSTRUCTION_INTERVAL_MS) return
            if (elapsed < MIN_ANY_INSTRUCTION_INTERVAL_MS) return
        }
        if (playRaw(instruction.audioFileName)) {
            lastInstruction = instruction
            lastInstructionTime = System.currentTimeMillis()
        }
    }

    /** Play a localization cue (localizing / success / failed). */
    fun playLocalizationAudio(type: LocalizationAudioType) {
        playRaw(type.audioFileName)
    }

    fun stopAudio() {
        try {
            player?.stop()
        } catch (e: IllegalStateException) {
            // ignore
        }
        player?.release()
        player = null
    }

    fun resetCooldowns() {
        lastInstruction = null
        lastInstructionTime = 0L
    }

    private fun playRaw(name: String): Boolean {
        val resId = context.resources.getIdentifier(name, "raw", context.packageName)
        if (resId == 0) {
            Log.e(TAG, "Audio resource not found: $name")
            return false
        }
        return try {
            player?.release()
            player =
                MediaPlayer().apply {
                    setAudioAttributes(audioAttributes)
                    val afd = context.resources.openRawResourceFd(resId)
                    setDataSource(afd.fileDescriptor, afd.startOffset, afd.length)
                    afd.close()
                    setOnCompletionListener { mp ->
                        mp.release()
                        if (player === mp) player = null
                    }
                    prepare()
                    start()
                }
            true
        } catch (e: Exception) {
            Log.e(TAG, "Failed to play $name: ${e.message}")
            false
        }
    }
}
