/*
Copyright (c) 2026 MultiSet AI. All rights reserved.
Licensed under the MultiSet License. You may not use this file except in compliance with the License. and you can't re-distribute this file without a prior notice
For license details, visit www.multiset.ai.
Redistribution in source or binary forms must retain this notice.
*/

import AVFoundation
import os.log

/// Service for playing navigation audio instructions through Bluetooth
@MainActor
final class NavigationAudioService: NSObject {

    // MARK: - Singleton

    static let shared = NavigationAudioService()

    // MARK: - Properties

    private let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "MultiSetWearable", category: "NavigationAudioService")
    private var audioPlayer: AVAudioPlayer?
    private var lastInstruction: NavigationInstruction?
    private var lastInstructionTime: Date = .distantPast

    /// Minimum interval between same instructions (prevents audio spam)
    private let minimumInstructionInterval: TimeInterval = 3.0

    /// Minimum interval between any instructions
    private let minimumAnyInstructionInterval: TimeInterval = 1.5

    /// Whether audio is currently playing
    var isPlaying: Bool {
        audioPlayer?.isPlaying ?? false
    }

    // MARK: - Initialization

    private override init() {
        super.init()
        configureAudioSession()
    }

    // MARK: - Public Methods

    /// Play a navigation instruction audio
    /// - Parameters:
    ///   - instruction: The instruction to play
    ///   - force: If true, plays immediately regardless of cooldown
    func playInstruction(_ instruction: NavigationInstruction, force: Bool = false) {
        // Check cooldown unless forced
        if !force {
            let timeSinceLastInstruction = Date().timeIntervalSince(lastInstructionTime)

            // Don't repeat the same instruction too quickly
            if instruction == lastInstruction && timeSinceLastInstruction < minimumInstructionInterval {
                logger.debug("Skipping instruction \(instruction.rawValue) - same instruction cooldown")
                return
            }

            // Don't play any instruction too quickly
            if timeSinceLastInstruction < minimumAnyInstructionInterval {
                logger.debug("Skipping instruction \(instruction.rawValue) - general cooldown")
                return
            }
        }

        // Find audio file in bundle
        guard let audioURL = Bundle.main.url(forResource: instruction.audioFileName, withExtension: "mp3") else {
            logger.error("Audio file not found: \(instruction.audioFileName).mp3")
            // Fallback to speech synthesis
            fallbackToSpeech(instruction)
            return
        }

        do {
            // Stop any currently playing audio
            audioPlayer?.stop()

            // Create and configure player
            audioPlayer = try AVAudioPlayer(contentsOf: audioURL)
            audioPlayer?.delegate = self
            audioPlayer?.prepareToPlay()
            audioPlayer?.play()

            lastInstruction = instruction
            lastInstructionTime = Date()

            logger.debug("Playing: \(instruction.audioFileName)")
        } catch {
            logger.error("Failed to play audio: \(error.localizedDescription)")
            fallbackToSpeech(instruction)
        }
    }

    /// Stop any currently playing audio
    func stopAudio() {
        audioPlayer?.stop()
        audioPlayer = nil
    }

    /// Reset cooldown timers (useful when starting new navigation)
    func resetCooldowns() {
        lastInstruction = nil
        lastInstructionTime = .distantPast
    }

    /// Play localization audio (localizing, success, or failure)
    /// - Parameter type: The localization audio type to play
    func playLocalizationAudio(_ type: LocalizationAudioType) {
        // Stop any currently playing audio
        audioPlayer?.stop()

        guard let audioURL = Bundle.main.url(forResource: type.fileName, withExtension: "mp3") else {
            logger.error("Localization audio file not found: \(type.fileName).mp3")
            // Fallback to speech
            SpeechManager.shared.speak(type.fallbackText)
            return
        }

        do {
            audioPlayer = try AVAudioPlayer(contentsOf: audioURL)
            audioPlayer?.delegate = self
            audioPlayer?.prepareToPlay()
            audioPlayer?.play()
            logger.debug("Playing: \(type.fileName)")
        } catch {
            logger.error("Failed to play localization audio: \(error.localizedDescription)")
            SpeechManager.shared.speak(type.fallbackText)
        }
    }

    /// Play any audio file by name (without extension)
    /// - Parameter fileName: The audio file name without .mp3 extension
    func playAudioFile(_ fileName: String) {
        audioPlayer?.stop()

        guard let audioURL = Bundle.main.url(forResource: fileName, withExtension: "mp3") else {
            logger.error("Audio file not found: \(fileName).mp3")
            return
        }

        do {
            audioPlayer = try AVAudioPlayer(contentsOf: audioURL)
            audioPlayer?.delegate = self
            audioPlayer?.prepareToPlay()
            audioPlayer?.play()
            logger.info("Playing audio: \(fileName)")
        } catch {
            logger.error("Failed to play audio: \(error.localizedDescription)")
        }
    }

    // MARK: - Private Methods

    private func configureAudioSession() {
        do {
            let audioSession = AVAudioSession.sharedInstance()
            // Use playback category with duckOthers to lower music volume during navigation
            // mixWithOthers allows navigation audio to play alongside other audio
            try audioSession.setCategory(
                .playback,
                mode: .voicePrompt,
                options: [.allowBluetoothA2DP, .duckOthers, .mixWithOthers]
            )
            try audioSession.setActive(true, options: .notifyOthersOnDeactivation)
            logger.debug("Audio session configured for navigation")
        } catch {
            logger.error("Failed to configure audio session: \(error.localizedDescription)")
        }
    }

    /// Fallback to text-to-speech if audio file not available
    private func fallbackToSpeech(_ instruction: NavigationInstruction) {
        SpeechManager.shared.speak(instruction.description)
    }
}

// MARK: - AVAudioPlayerDelegate

extension NavigationAudioService: AVAudioPlayerDelegate {
    nonisolated func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        Task { @MainActor in
            self.logger.debug("Audio finished playing (success: \(flag))")
        }
    }

    nonisolated func audioPlayerDecodeErrorDidOccur(_ player: AVAudioPlayer, error: Error?) {
        Task { @MainActor in
            if let error = error {
                self.logger.error("Audio decode error: \(error.localizedDescription)")
            }
        }
    }
}
