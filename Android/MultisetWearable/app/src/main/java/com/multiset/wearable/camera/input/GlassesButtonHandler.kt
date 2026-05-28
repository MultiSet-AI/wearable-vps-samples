/*
Copyright (c) 2026 MultiSet AI. All rights reserved.
Licensed under the MultiSet License. You may not use this file except in compliance with the License. and you can't re-distribute this file without a prior notice
For license details, visit www.multiset.ai.
Redistribution in source or binary forms must retain this notice.
*/

package com.multiset.wearable.vps.input

import android.content.Context
import android.media.AudioAttributes
import android.media.AudioFocusRequest
import android.media.AudioManager
import android.os.Build
import android.support.v4.media.session.MediaSessionCompat
import android.support.v4.media.session.PlaybackStateCompat
import android.util.Log
import android.view.KeyEvent
import kotlinx.coroutines.flow.MutableSharedFlow
import kotlinx.coroutines.flow.SharedFlow
import kotlinx.coroutines.flow.asSharedFlow

/**
 * Handles physical button presses from Meta Ray-Ban glasses.
 *
 * Uses MediaSession to capture media button events from Bluetooth devices.
 * The glasses button typically sends media key events that need to be
 * intercepted via MediaSession rather than onKeyDown().
 *
 * Usage:
 * - Call initialize() from Activity.onCreate()
 * - Call release() from Activity.onDestroy()
 * - Collect buttonPressEvents flow in ViewModels to react to button presses
 */
object GlassesButtonHandler {

    private const val TAG = "GlassesButtonHandler"
    private const val MEDIA_SESSION_TAG = "MetaCameraMediaSession"

    private var mediaSession: MediaSessionCompat? = null
    private var audioManager: AudioManager? = null
    private var audioFocusRequest: AudioFocusRequest? = null
    private var isInitialized = false

    private val _buttonPressEvents = MutableSharedFlow<com.multiset.wearable.vps.input.ButtonPressEvent>(
        extraBufferCapacity = 1  // Buffer one event to avoid losing events
    )

    /**
     * Flow of button press events from the glasses
     */
    val buttonPressEvents: SharedFlow<com.multiset.wearable.vps.input.ButtonPressEvent> = _buttonPressEvents.asSharedFlow()

    /**
     * Initialize the MediaSession to capture button events.
     * Call this from Activity.onCreate()
     */
    fun initialize(context: Context) {
        if (isInitialized) {
            Log.d(TAG, "Already initialized")
            return
        }

        Log.d(TAG, "Initializing GlassesButtonHandler with MediaSession")

        audioManager = context.getSystemService(Context.AUDIO_SERVICE) as AudioManager

        // Create MediaSession
        mediaSession = MediaSessionCompat(context, MEDIA_SESSION_TAG).apply {
            // Set callback to handle media button events
            setCallback(object : MediaSessionCompat.Callback() {
                override fun onMediaButtonEvent(mediaButtonEvent: android.content.Intent?): Boolean {
                    val keyEvent = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
                        mediaButtonEvent?.getParcelableExtra(
                            android.content.Intent.EXTRA_KEY_EVENT,
                            KeyEvent::class.java
                        )
                    } else {
                        @Suppress("DEPRECATION")
                        mediaButtonEvent?.getParcelableExtra(android.content.Intent.EXTRA_KEY_EVENT)
                    }

                    keyEvent?.let { event ->
                        if (event.action == KeyEvent.ACTION_DOWN) {
                            Log.d(TAG, "MediaSession received button: keyCode=${event.keyCode}")
                            handleButtonPress(event.keyCode, event.device?.name)
                            return true
                        }
                    }
                    return super.onMediaButtonEvent(mediaButtonEvent)
                }

                override fun onPlay() {
                    Log.d(TAG, "MediaSession onPlay")
                    handleButtonPress(KeyEvent.KEYCODE_MEDIA_PLAY, "MediaSession")
                }

                override fun onPause() {
                    Log.d(TAG, "MediaSession onPause")
                    handleButtonPress(KeyEvent.KEYCODE_MEDIA_PAUSE, "MediaSession")
                }

                override fun onStop() {
                    Log.d(TAG, "MediaSession onStop")
                    handleButtonPress(KeyEvent.KEYCODE_MEDIA_STOP, "MediaSession")
                }
            })

            // Set playback state to make the session active
            setPlaybackState(
                PlaybackStateCompat.Builder()
                    .setState(PlaybackStateCompat.STATE_PLAYING, 0, 1f)
                    .setActions(
                        PlaybackStateCompat.ACTION_PLAY or
                        PlaybackStateCompat.ACTION_PAUSE or
                        PlaybackStateCompat.ACTION_PLAY_PAUSE or
                        PlaybackStateCompat.ACTION_STOP
                    )
                    .build()
            )

            // Activate the session
            isActive = true
        }

        // Request audio focus to ensure we receive media button events
        requestAudioFocus()

        isInitialized = true
        Log.d(TAG, "GlassesButtonHandler initialized successfully")
    }

    /**
     * Request audio focus to capture media button events
     */
    private fun requestAudioFocus() {
        audioManager?.let { am ->
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                audioFocusRequest = AudioFocusRequest.Builder(AudioManager.AUDIOFOCUS_GAIN)
                    .setAudioAttributes(
                        AudioAttributes.Builder()
                            .setUsage(AudioAttributes.USAGE_MEDIA)
                            .setContentType(AudioAttributes.CONTENT_TYPE_UNKNOWN)
                            .build()
                    )
                    .setOnAudioFocusChangeListener { focusChange ->
                        Log.d(TAG, "Audio focus changed: $focusChange")
                    }
                    .build()
                am.requestAudioFocus(audioFocusRequest!!)
            } else {
                @Suppress("DEPRECATION")
                am.requestAudioFocus(
                    { focusChange -> Log.d(TAG, "Audio focus changed: $focusChange") },
                    AudioManager.STREAM_MUSIC,
                    AudioManager.AUDIOFOCUS_GAIN
                )
            }
        }
    }

    /**
     * Release resources. Call this from Activity.onDestroy()
     */
    fun release() {
        Log.d(TAG, "Releasing GlassesButtonHandler")

        mediaSession?.apply {
            isActive = false
            release()
        }
        mediaSession = null

        // Abandon audio focus
        audioManager?.let { am ->
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                audioFocusRequest?.let { am.abandonAudioFocusRequest(it) }
            } else {
                @Suppress("DEPRECATION")
                am.abandonAudioFocus(null)
            }
        }
        audioFocusRequest = null
        audioManager = null

        isInitialized = false
    }

    /**
     * Handle a button press and emit event
     */
    private fun handleButtonPress(keyCode: Int, deviceName: String?) {
        Log.d(TAG, "Button pressed: keyCode=$keyCode, device=$deviceName")

        val buttonEvent = _root_ide_package_.com.multiset.wearable.vps.input.ButtonPressEvent(
            keyCode = keyCode,
            deviceName = deviceName,
            timestamp = System.currentTimeMillis()
        )

        _buttonPressEvents.tryEmit(buttonEvent)
    }

    /**
     * Handle a KeyEvent from onKeyDown (fallback for non-media keys)
     */
    fun handleKeyEvent(keyCode: Int, event: KeyEvent?): Boolean {
        if (event?.action != KeyEvent.ACTION_DOWN) {
            return false
        }

        // Handle camera button directly (not a media button)
        if (keyCode == KeyEvent.KEYCODE_CAMERA) {
            Log.d(TAG, "Camera button pressed via KeyEvent")
            handleButtonPress(keyCode, event.device?.name)
            return true
        }

        return false
    }
}

/**
 * Represents a button press event from the glasses
 */
data class ButtonPressEvent(
    val keyCode: Int,
    val deviceName: String?,
    val timestamp: Long
)
