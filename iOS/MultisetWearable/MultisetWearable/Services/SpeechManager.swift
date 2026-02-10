/*
Copyright (c) 2026 MultiSet AI. All rights reserved.
Licensed under the MultiSet License. You may not use this file except in compliance with the License. and you can't re-distribute this file without a prior notice
For license details, visit www.multiset.ai.
Redistribution in source or binary forms must retain this notice.
*/

import AVFoundation
import os.log

/// Manages text-to-speech functionality for audio feedback
/// Audio will play through connected Ray-Ban Meta glasses when available
@MainActor
final class SpeechManager: NSObject {

    // MARK: - Singleton
    static let shared = SpeechManager()

    // MARK: - Properties
    private let synthesizer = AVSpeechSynthesizer()
    private let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "MultiSetWearable", category: "SpeechManager")
    private var isReady = false

    // MARK: - Predefined Messages
    enum Message {
        case capturing
        case localizationSuccessful
        case localizationFailed
        case localizationError
        case pleaseWait
        case cameraStarting
        case notConfigured

        var text: String {
            switch self {
            case .capturing:
                return "Localizing"
            case .localizationSuccessful:
                return "Localization successful"
            case .localizationFailed:
                return "Localization failed. Please try again."
            case .localizationError:
                return "Localization error. Please try again."
            case .pleaseWait:
                return "Please wait, localization in progress"
            case .cameraStarting:
                return "Please wait, camera is starting"
            case .notConfigured:
                return "Please configure API credentials in settings"
            }
        }
    }

    // MARK: - Initialization
    private override init() {
        super.init()
        synthesizer.delegate = self
        configureAudioSession()
        isReady = true
        logger.debug("SpeechManager initialized")
    }

    // MARK: - Public Methods

    /// Speak a predefined message
    func speak(_ message: Message) {
        speak(message.text)
    }

    /// Speak custom text
    func speak(_ text: String) {
        guard isReady else {
            logger.warning("SpeechManager not ready")
            return
        }

        // Stop any current speech
        if synthesizer.isSpeaking {
            synthesizer.stopSpeaking(at: .immediate)
        }

        let utterance = AVSpeechUtterance(string: text)
        utterance.voice = AVSpeechSynthesisVoice(language: "en-US")
        utterance.rate = AVSpeechUtteranceDefaultSpeechRate
        utterance.pitchMultiplier = 1.0
        utterance.volume = 1.0

        logger.debug("Speaking: \(text)")
        synthesizer.speak(utterance)
    }

    /// Stop current speech immediately
    func stopSpeaking() {
        if synthesizer.isSpeaking {
            synthesizer.stopSpeaking(at: .immediate)
        }
    }

    /// Check if currently speaking
    var isSpeaking: Bool {
        synthesizer.isSpeaking
    }

    // MARK: - Private Methods

    private func configureAudioSession() {
        do {
            let audioSession = AVAudioSession.sharedInstance()
            // Use playback category to allow audio through Bluetooth devices
            // duckOthers lowers other audio (like music) during speech
            // mixWithOthers allows speech to play alongside other audio
            try audioSession.setCategory(
                .playback,
                mode: .voicePrompt,
                options: [.allowBluetoothA2DP, .duckOthers, .mixWithOthers]
            )
            try audioSession.setActive(true, options: .notifyOthersOnDeactivation)
            logger.debug("Audio session configured")
        } catch {
            logger.error("Failed to configure audio session: \(error.localizedDescription)")
        }
    }
}

// MARK: - AVSpeechSynthesizerDelegate
extension SpeechManager: @preconcurrency AVSpeechSynthesizerDelegate {
    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didStart utterance: AVSpeechUtterance) {
        logger.debug("Speech started")
    }

    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
        logger.debug("Speech finished")
    }

    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didCancel utterance: AVSpeechUtterance) {
        logger.debug("Speech cancelled")
    }
}
