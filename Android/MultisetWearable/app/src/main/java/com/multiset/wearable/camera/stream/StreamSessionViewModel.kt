/*
Copyright (c) 2026 MultiSet AI. All rights reserved.
Licensed under the MultiSet License. You may not use this file except in compliance with the License. and you can't re-distribute this file without a prior notice
For license details, visit www.multiset.ai.
Redistribution in source or binary forms must retain this notice.
*/

// StreamSessionViewModel - Shared streaming engine for the Localization Demo and
// Record Video Stream features. Mirrors the iOS StreamSessionViewModel:
// - Manages the DAT 0.7.0 session/stream lifecycle (createSession -> addStream -> Stream)
// - Exposes the latest video frame as a Bitmap for live preview / recording
// - Performs single-frame VPS localization from the live stream (capture -> downscale -> API)

package com.multiset.wearable.vps.stream

import android.app.Application
import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.graphics.Matrix
import android.speech.tts.TextToSpeech
import android.util.Log
import androidx.exifinterface.media.ExifInterface
import androidx.lifecycle.AndroidViewModel
import androidx.lifecycle.ViewModel
import androidx.lifecycle.ViewModelProvider
import androidx.lifecycle.viewModelScope
import com.meta.wearable.dat.camera.Stream
import com.meta.wearable.dat.camera.addStream
import com.meta.wearable.dat.camera.types.PhotoData
import com.meta.wearable.dat.camera.types.StreamConfiguration
import com.meta.wearable.dat.camera.types.StreamState
import com.meta.wearable.dat.camera.types.VideoFrame
import com.meta.wearable.dat.camera.types.VideoQuality
import com.meta.wearable.dat.core.Wearables
import com.meta.wearable.dat.core.selectors.DeviceSelector
import com.meta.wearable.dat.core.session.DeviceSession
import com.meta.wearable.dat.core.session.DeviceSessionState
import com.meta.wearable.dat.core.types.DeviceSessionError
import com.meta.wearable.dat.core.types.Permission
import com.meta.wearable.dat.core.types.PermissionStatus
import com.multiset.wearable.vps.input.GlassesButtonHandler
import com.multiset.wearable.vps.localization.NetworkManager
import com.multiset.wearable.vps.localization.SDKConfig
import com.multiset.wearable.vps.navigation.AudioNavigationService
import com.multiset.wearable.vps.navigation.MapBounds
import com.multiset.wearable.vps.navigation.NavPosition
import com.multiset.wearable.vps.navigation.NavigationAudioService
import com.multiset.wearable.vps.navigation.NavigationDataService
import com.multiset.wearable.vps.navigation.NavigationPOI
import com.multiset.wearable.vps.navigation.NavigationState
import com.multiset.wearable.vps.video.ThermalMonitor
import com.multiset.wearable.vps.video.VideoFrameProcessor
import com.multiset.wearable.vps.wearables.WearablesViewModel
import java.io.ByteArrayInputStream
import java.io.ByteArrayOutputStream
import java.io.IOException
import java.util.Locale
import kotlinx.coroutines.Job
import kotlinx.coroutines.delay
import kotlinx.coroutines.isActive
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.flow.update
import kotlinx.coroutines.launch

class StreamSessionViewModel(
    application: Application,
    private val wearablesViewModel: WearablesViewModel,
    /** When true, wire up VPS localization (glasses-button trigger + TTS). */
    private val enableLocalization: Boolean,
) : AndroidViewModel(application), TextToSpeech.OnInitListener {

    companion object {
        private const val TAG = "StreamSessionViewModel"
        private const val JPEG_QUALITY = 85
        private const val MIN_CONFIDENCE = 0.4f
    }

    private val deviceSelector: DeviceSelector = wearablesViewModel.deviceSelector
    private val networkManager = NetworkManager.getInstance()

    private val _uiState = MutableStateFlow(StreamSessionUiState())
    val uiState: StateFlow<StreamSessionUiState> = _uiState.asStateFlow()

    private var session: DeviceSession? = null
    private var stream: Stream? = null

    private var sessionJob: Job? = null
    private var sessionStateJob: Job? = null
    private var videoJob: Job? = null
    private var stateJob: Job? = null
    private var errorJob: Job? = null
    private var sessionErrorJob: Job? = null
    private var deviceJob: Job? = null
    private var buttonJob: Job? = null
    private var localizeJob: Job? = null
    private var previousDeviceSessionState: DeviceSessionState? = null

    private val frameProcessor =
        VideoFrameProcessor(
            VideoFrameProcessor.ProcessorConfig(
                previewQuality = 60,
                captureQuality = 85,
                enableFrameDropping = true,
                logPerformanceStats = false,
            )
        )
    private val thermalMonitor = ThermalMonitor(application)

    private var lastPermissionCallback: (suspend (Permission) -> PermissionStatus)? = null

    // Text-to-Speech for audio feedback on the glasses (localization mode only)
    private var textToSpeech: TextToSpeech? = null
    private var isTtsReady = false

    // Navigation (Navigation Demo)
    private val navDataService = NavigationDataService(application)
    private val navAudioService = NavigationAudioService(application)
    private val navigationEngine = AudioNavigationService(navDataService, navAudioService, viewModelScope)
    val navigationState: StateFlow<NavigationState> = navigationEngine.state
    private var navLocalizeJob: Job? = null
    @Volatile private var isNavigating = false

    init {
        // Track active-device availability so screens can enable the start button.
        deviceJob =
            viewModelScope.launch {
                deviceSelector.activeDeviceFlow().collect { device ->
                    _uiState.update { it.copy(hasActiveDevice = device != null) }
                }
            }

        if (enableLocalization) {
            textToSpeech = TextToSpeech(application, this)
            startButtonListener()
        }
    }

    override fun onInit(status: Int) {
        if (status == TextToSpeech.SUCCESS) {
            val result = textToSpeech?.setLanguage(Locale.US)
            isTtsReady =
                result != TextToSpeech.LANG_MISSING_DATA && result != TextToSpeech.LANG_NOT_SUPPORTED
        } else {
            isTtsReady = false
        }
    }

    private fun speak(message: String) {
        if (isTtsReady) {
            textToSpeech?.speak(message, TextToSpeech.QUEUE_FLUSH, null, "stream_session")
        }
    }

    /** Listen for the glasses hardware button and trigger localization when possible. */
    private fun startButtonListener() {
        buttonJob?.cancel()
        buttonJob =
            viewModelScope.launch {
                GlassesButtonHandler.buttonPressEvents.collect {
                    if (canLocalize()) {
                        speak("Capturing")
                        localize()
                    }
                }
            }
    }

    // MARK: - Session lifecycle

    /** Check camera permission, then start the device session + camera stream. */
    fun startSession(onRequestWearablesPermission: suspend (Permission) -> PermissionStatus) {
        lastPermissionCallback = onRequestWearablesPermission
        if (_uiState.value.streamingStatus != StreamingStatus.STOPPED) return

        sessionJob?.cancel()
        sessionJob =
            viewModelScope.launch {
                if (!requestCameraPermission(onRequestWearablesPermission)) return@launch

                _uiState.update { it.copy(streamingStatus = StreamingStatus.WAITING, errorMessage = null) }

                previousDeviceSessionState = null
                Wearables.createSession(deviceSelector)
                    .onSuccess { createdSession ->
                        session = createdSession
                        sessionErrorJob =
                            viewModelScope.launch { createdSession.errors.collect { handleSessionError(it) } }
                        createdSession.start()
                    }
                    .onFailure { error, _ ->
                        setError(error.description)
                        _uiState.update { it.copy(streamingStatus = StreamingStatus.STOPPED) }
                    }
                if (session == null) return@launch

                // Keep collecting device-session state for the session's lifetime. The active
                // subscription holds the device-session lease alive; ending it (e.g. via first{})
                // drops the lease and closes the stream. Add the stream once STARTED.
                startStreamInternal()
            }
    }

    private fun startStreamInternal() {
        sessionStateJob?.cancel()
        sessionStateJob =
            viewModelScope.launch {
                session?.state?.collect { currentState ->
                    val prev = previousDeviceSessionState
                    previousDeviceSessionState = currentState

                    if (currentState == DeviceSessionState.STARTED) {
                        // PAUSED -> STARTED is a device-initiated resume; keep the existing stream.
                        if (prev == DeviceSessionState.PAUSED && stream != null) return@collect

                        videoJob?.cancel()
                        stateJob?.cancel()
                        errorJob?.cancel()
                        stream?.stop()
                        stream = null

                        session
                            ?.addStream(StreamConfiguration(videoQuality = VideoQuality.MEDIUM, frameRate = 24))
                            ?.onSuccess { addedStream ->
                                stream = addedStream
                                videoJob =
                                    viewModelScope.launch {
                                        addedStream.videoStream.collect { handleVideoFrame(it) }
                                    }
                                stateJob =
                                    viewModelScope.launch {
                                        addedStream.state.collect { handleStreamState(it) }
                                    }
                                errorJob =
                                    viewModelScope.launch {
                                        addedStream.errorStream.collect { error ->
                                            Log.e(TAG, "Stream error: $error (${error.description})")
                                        }
                                    }
                                addedStream.start()

                                // Pre-warm the auth token so the first localization is fast.
                                if (enableLocalization) {
                                    viewModelScope.launch {
                                        com.multiset.wearable.vps.localization.AuthManager.getInstance().getToken()
                                    }
                                }
                            }
                            ?.onFailure { error, _ ->
                                Log.e(TAG, "Failed to add stream: ${error.description}")
                                setError("Failed to start camera stream. Please try again.")
                                stopSession()
                            }
                    }
                    // PAUSED: tap-gesture pause — keep the stream alive for resume.
                }
            }
    }

    private fun handleStreamState(streamState: StreamState) {
        Log.d(TAG, "Stream state: $streamState")
        when (streamState) {
            StreamState.STREAMING ->
                _uiState.update { it.copy(streamingStatus = StreamingStatus.STREAMING) }
            StreamState.CLOSED -> {
                if (_uiState.value.streamingStatus != StreamingStatus.STOPPED) stopSession()
            }
            else ->
                if (_uiState.value.streamingStatus == StreamingStatus.STOPPED) {
                    _uiState.update { it.copy(streamingStatus = StreamingStatus.WAITING) }
                }
        }
    }

    fun stopSession() {
        if (isNavigating) stopNavigation()
        videoJob?.cancel(); videoJob = null
        stateJob?.cancel(); stateJob = null
        errorJob?.cancel(); errorJob = null
        sessionErrorJob?.cancel(); sessionErrorJob = null
        sessionStateJob?.cancel(); sessionStateJob = null
        localizeJob?.cancel(); localizeJob = null
        previousDeviceSessionState = null
        stream?.stop()
        stream = null
        session?.stop()
        session = null
        _uiState.update {
            it.copy(
                streamingStatus = StreamingStatus.STOPPED,
                videoFrame = null,
                hasReceivedFirstFrame = false,
                localizationStatus = LocalizationStatus.IDLE,
                localizationResult = null,
            )
        }
    }

    private suspend fun requestCameraPermission(
        onRequest: suspend (Permission) -> PermissionStatus
    ): Boolean {
        val maxRetries = 3
        for (attempt in 0 until maxRetries) {
            if (attempt > 0) delay(500L * (1 shl (attempt - 1)))
            val result = Wearables.checkPermissionStatus(Permission.CAMERA)
            var shouldRetry = false
            result.onFailure { _, _ -> shouldRetry = attempt < maxRetries - 1 }
            if (shouldRetry) continue
            if (result.isFailure) {
                setError("Camera permission check failed.")
                _uiState.update { it.copy(streamingStatus = StreamingStatus.STOPPED) }
                return false
            }
            if (result.getOrNull() == PermissionStatus.Granted) return true
            return when (onRequest(Permission.CAMERA)) {
                PermissionStatus.Granted -> true
                PermissionStatus.Denied -> {
                    setError("Camera permission denied. Please grant it in the Meta AI app.")
                    _uiState.update { it.copy(streamingStatus = StreamingStatus.STOPPED) }
                    false
                }
            }
        }
        return false
    }

    private fun handleSessionError(error: DeviceSessionError) {
        Log.e(TAG, "Session error: ${error.description}")
        if (error == DeviceSessionError.DAT_APP_ON_THE_GLASSES_UPDATE_REQUIRED) {
            wearablesViewModel.setDatAppUpdateRequired(true)
        }
        setError(error.description)
        stopSession()
    }

    private fun handleVideoFrame(videoFrame: VideoFrame) {
        if (thermalMonitor.shouldDropFrame()) return
        val bitmap = frameProcessor.processForPreview(videoFrame) ?: return
        _uiState.update {
            it.copy(
                videoFrame = bitmap,
                videoFrameCount = it.videoFrameCount + 1,
                hasReceivedFirstFrame = true,
            )
        }
    }

    // MARK: - Localization

    private fun canLocalize(): Boolean =
        enableLocalization &&
            SDKConfig.isConfigured() &&
            _uiState.value.streamingStatus == StreamingStatus.STREAMING &&
            !_uiState.value.isLocalizing

    fun localize() {
        if (!canLocalize()) {
            if (!SDKConfig.isConfigured()) {
                setError("Please configure API credentials and a map code in settings.")
            }
            return
        }

        localizeJob?.cancel()
        localizeJob =
            viewModelScope.launch {
                while (true) {
                    _uiState.update {
                        it.copy(localizationStatus = LocalizationStatus.CAPTURING, errorMessage = null)
                    }

                    val photo = stream?.capturePhoto()?.getOrNull()
                    if (photo == null) {
                        _uiState.update { it.copy(localizationStatus = LocalizationStatus.ERROR) }
                        speak("Capture failed. Please try again.")
                        return@launch
                    }

                    val full = processPhotoData(photo)
                    // Downscale by 0.5 before upload (API rejects images with max side > 1280).
                    val half = Bitmap.createScaledBitmap(full, full.width / 2, full.height / 2, true)
                    _uiState.update {
                        it.copy(capturedPhoto = half, localizationStatus = LocalizationStatus.LOCALIZING)
                    }

                    val jpeg = bitmapToJpeg(half)
                    val result =
                        networkManager.sendLocalizationRequest(
                            imageBytes = jpeg,
                            imageWidth = half.width,
                            imageHeight = half.height,
                        )

                    var retry = false
                    result
                        .onSuccess { r ->
                            val confidence = r.confidence ?: 1.0f
                            if (r.poseFound && confidence < MIN_CONFIDENCE) {
                                // Confidence too low — retry with a fresh frame.
                                Log.d(TAG, "Low confidence ${"%.0f".format(confidence * 100)}%, retrying")
                                retry = true
                            } else if (r.poseFound) {
                                _uiState.update {
                                    it.copy(
                                        localizationStatus = LocalizationStatus.SUCCESS,
                                        localizationResult = r,
                                    )
                                }
                                // Feed the navigation engine so the 2D map shows the user
                                // position + heading even before navigation starts.
                                val pos = r.posePosition
                                val rot = r.poseRotation
                                if (pos != null && rot != null) navigationEngine.updatePosition(pos, rot)
                                speak("Localization successful")
                            } else {
                                _uiState.update {
                                    it.copy(
                                        localizationStatus = LocalizationStatus.FAILURE,
                                        localizationResult = r,
                                    )
                                }
                                speak("Localization failed. Please try again.")
                            }
                        }
                        .onFailure { error ->
                            Log.e(TAG, "Localization failed", error)
                            _uiState.update {
                                it.copy(
                                    localizationStatus = LocalizationStatus.ERROR,
                                    errorMessage = error.message ?: "Localization failed.",
                                )
                            }
                            speak("Localization error. Please try again.")
                        }

                    if (retry && _uiState.value.streamingStatus == StreamingStatus.STREAMING) {
                        _uiState.update { it.copy(localizationStatus = LocalizationStatus.IDLE) }
                        delay(100)
                        continue
                    }
                    return@launch
                }
            }
    }

    fun clearLocalizationResult() {
        _uiState.update {
            it.copy(localizationStatus = LocalizationStatus.IDLE, localizationResult = null)
        }
    }

    // MARK: - Navigation

    fun navigationPOIs(): List<NavigationPOI> = navDataService.getPOIs()

    fun navBounds(): MapBounds? = navDataService.bounds

    fun navWaypoints(): List<com.multiset.wearable.vps.navigation.WaypointData> =
        navDataService.getAllWaypoints()

    /** Reload navigation data for the currently-configured map code (e.g. after it changed). */
    fun reloadNavigationData() = navDataService.reload()

    /** Current user position from the latest localization (for sorting POIs by distance). */
    fun currentUserNavPosition(): NavPosition? =
        _uiState.value.localizationResult?.posePosition?.let { NavPosition.from(it) }

    fun startNavigation(poiId: Int) {
        val result = _uiState.value.localizationResult
        val position = result?.posePosition
        val rotation = result?.poseRotation
        if (position == null || rotation == null) {
            setError("Please localize before starting navigation.")
            return
        }
        navigationEngine.updatePosition(position, rotation)
        if (!navigationEngine.startNavigation(poiId)) {
            setError("Couldn't find a route to that destination. Try localizing again.")
            return
        }
        isNavigating = true
        startNavLocalizationLoop()
    }

    fun stopNavigation() {
        navigationEngine.stopNavigation()
        isNavigating = false
        navLocalizeJob?.cancel()
        navLocalizeJob = null
    }

    /**
     * Continuous localization during navigation using the live video frame directly. This
     * skips the Bluetooth capturePhoto round-trip, matching the iOS localizeForNavigation().
     */
    private fun startNavLocalizationLoop() {
        navLocalizeJob?.cancel()
        navLocalizeJob =
            viewModelScope.launch {
                while (isActive && isNavigating) {
                    if (_uiState.value.streamingStatus == StreamingStatus.STREAMING) {
                        val frame = _uiState.value.videoFrame
                        if (frame != null && !frame.isRecycled) {
                            val jpeg = bitmapToJpeg(frame)
                            networkManager
                                .sendLocalizationRequest(
                                    imageBytes = jpeg,
                                    imageWidth = frame.width,
                                    imageHeight = frame.height,
                                    isRightHanded = false,
                                )
                                .onSuccess { r ->
                                    if (r.poseFound) {
                                        val pos = r.posePosition
                                        val rot = r.poseRotation
                                        if (pos != null && rot != null) navigationEngine.updatePosition(pos, rot)
                                        _uiState.update { it.copy(localizationResult = r) }
                                    }
                                }
                            // The engine stops itself on arrival.
                            if (!navigationEngine.isNavigating) {
                                isNavigating = false
                                break
                            }
                        }
                    }
                    delay(50)
                }
            }
    }

    private fun setError(message: String) {
        _uiState.update { it.copy(errorMessage = message) }
    }

    fun clearError() {
        _uiState.update { it.copy(errorMessage = null) }
    }

    // MARK: - Photo decoding (HEIC + EXIF orientation)

    private fun processPhotoData(photo: PhotoData): Bitmap =
        when (photo) {
            is PhotoData.Bitmap -> photo.bitmap
            is PhotoData.HEIC -> {
                val byteArray = ByteArray(photo.data.remaining())
                photo.data.get(byteArray)
                val transform = getTransform(getExifInfo(byteArray))
                applyTransform(BitmapFactory.decodeByteArray(byteArray, 0, byteArray.size), transform)
            }
        }

    private fun bitmapToJpeg(bitmap: Bitmap): ByteArray {
        val out = ByteArrayOutputStream()
        bitmap.compress(Bitmap.CompressFormat.JPEG, JPEG_QUALITY, out)
        return out.toByteArray()
    }

    private fun getExifInfo(heicBytes: ByteArray): ExifInterface? =
        try {
            ByteArrayInputStream(heicBytes).use { ExifInterface(it) }
        } catch (e: IOException) {
            null
        }

    private fun getTransform(exifInfo: ExifInterface?): Matrix {
        val matrix = Matrix()
        if (exifInfo == null) return matrix
        when (
            exifInfo.getAttributeInt(ExifInterface.TAG_ORIENTATION, ExifInterface.ORIENTATION_NORMAL)
        ) {
            ExifInterface.ORIENTATION_FLIP_HORIZONTAL -> matrix.postScale(-1f, 1f)
            ExifInterface.ORIENTATION_ROTATE_180 -> matrix.postRotate(180f)
            ExifInterface.ORIENTATION_FLIP_VERTICAL -> matrix.postScale(1f, -1f)
            ExifInterface.ORIENTATION_TRANSPOSE -> {
                matrix.postRotate(90f)
                matrix.postScale(-1f, 1f)
            }
            ExifInterface.ORIENTATION_ROTATE_90 -> matrix.postRotate(90f)
            ExifInterface.ORIENTATION_TRANSVERSE -> {
                matrix.postRotate(270f)
                matrix.postScale(-1f, 1f)
            }
            ExifInterface.ORIENTATION_ROTATE_270 -> matrix.postRotate(270f)
        }
        return matrix
    }

    private fun applyTransform(bitmap: Bitmap, matrix: Matrix): Bitmap {
        if (matrix.isIdentity) return bitmap
        return try {
            Bitmap.createBitmap(bitmap, 0, 0, bitmap.width, bitmap.height, matrix, true)
        } catch (e: OutOfMemoryError) {
            bitmap
        }
    }

    override fun onCleared() {
        super.onCleared()
        stopNavigation()
        navAudioService.stopAudio()
        stopSession()
        deviceJob?.cancel()
        buttonJob?.cancel()
        frameProcessor.release()
        thermalMonitor.release()
        textToSpeech?.stop()
        textToSpeech?.shutdown()
        textToSpeech = null
        isTtsReady = false
    }

    class Factory(
        private val application: Application,
        private val wearablesViewModel: WearablesViewModel,
        private val enableLocalization: Boolean,
    ) : ViewModelProvider.Factory {
        override fun <T : ViewModel> create(modelClass: Class<T>): T {
            if (modelClass.isAssignableFrom(StreamSessionViewModel::class.java)) {
                @Suppress("UNCHECKED_CAST")
                return StreamSessionViewModel(application, wearablesViewModel, enableLocalization) as T
            }
            throw IllegalArgumentException("Unknown ViewModel class")
        }
    }
}
