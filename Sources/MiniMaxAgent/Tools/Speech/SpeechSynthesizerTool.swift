import Foundation
import AVFoundation

/// Events emitted by the speech synthesizer
public enum SpeechSynthesizerEvent: Sendable, Equatable {
    case started
    case finished
    case cancelled
    case paused
    case continued
    case willSpeakRange(characterRange: Range<Int>, utterance: String)
    case errorOccurred(String)

    public static func == (lhs: SpeechSynthesizerEvent, rhs: SpeechSynthesizerEvent) -> Bool {
        switch (lhs, rhs) {
        case (.started, .started), (.finished, .finished), (.cancelled, .cancelled),
             (.paused, .paused), (.continued, .continued):
            return true
        case (.willSpeakRange(let a, let b), .willSpeakRange(let c, let d)):
            return a == c && b == d
        case (.errorOccurred(let a), .errorOccurred(let b)):
            return a == b
        default:
            return false
        }
    }
}

/// Configuration for speech synthesis
public struct SpeechSynthesisConfig: Sendable, Equatable {
    /// Voice identifier to use
    public let voiceIdentifier: String?

    /// Language code (used if voiceIdentifier is nil)
    public let language: String?

    /// Speech rate (0.0-1.0, 0.5 is normal)
    public let rate: Float

    /// Pitch multiplier (0.5-2.0, 1.0 is normal)
    public let pitch: Float

    /// Volume (0.0-1.0)
    public let volume: Float

    /// Whether to use enhanced voice quality if available
    public let preferEnhancedVoice: Bool

    public init(
        voiceIdentifier: String? = nil,
        language: String? = nil,
        rate: Float = 0.5,
        pitch: Float = 1.0,
        volume: Float = 1.0,
        preferEnhancedVoice: Bool = true
    ) {
        self.voiceIdentifier = voiceIdentifier
        self.language = language
        self.rate = max(0.0, min(1.0, rate))
        self.pitch = max(0.5, min(2.0, pitch))
        self.volume = max(0.0, min(1.0, volume))
        self.preferEnhancedVoice = preferEnhancedVoice
    }

    /// Default English configuration
    public static let englishDefault = SpeechSynthesisConfig(
        language: "en-US",
        rate: 0.5,
        pitch: 1.0,
        volume: 1.0
    )
}

/// Result of a speech synthesis operation
public struct SpeechSynthesisResult: Sendable, Equatable {
    /// Whether synthesis completed successfully
    public let success: Bool

    /// Text that was spoken
    public let text: String

    /// Voice identifier used
    public let voiceIdentifier: String

    /// Duration of the speech in seconds
    public let duration: TimeInterval

    /// Error message if failed
    public let error: String?

    public init(
        success: Bool,
        text: String,
        voiceIdentifier: String,
        duration: TimeInterval = 0,
        error: String? = nil
    ) {
        self.success = success
        self.text = text
        self.voiceIdentifier = voiceIdentifier
        self.duration = duration
        self.error = error
    }
}

/// Current state of the speech synthesizer
public enum SpeechSynthesizerState: Sendable, Equatable {
    case idle
    case speaking
    case paused
    case notStarted
}

/// Actor that wraps AVSpeechSynthesizer for text-to-speech functionality
///
/// Provides comprehensive speech synthesis including:
/// - Speaking, stopping, pausing, and resuming speech
/// - Event callbacks for progress and state changes
/// - Configuration of voice, rate, pitch, and volume
///
/// Phase 3: API Integration — MiniMax API client, Claude API, model management, multimodal
/// Section: 3.4
/// Task: AVSpeechSynthesizer integration
///
/// Usage:
///
///   let synthesizer = SpeechSynthesizerTool()
///   
///   // Speak text
///   let result = await synthesizer.speak("Hello, world!")
///   
///   // Speak with custom configuration
///   let config = SpeechSynthesisConfig(language: "en-GB", rate: 0.6)
///   let result = await synthesizer.speak("Hello from the UK!", config: config)
///   
///   // Control playback
///   await synthesizer.pause()
///   await synthesizer.continueSpeaking()
///   await synthesizer.stop()
///
public actor SpeechSynthesizerTool {

    // MARK: - Private Properties

    private let synthesizer: AVSpeechSynthesizer
    private var currentConfig: SpeechSynthesisConfig?
    private var currentUtterance: AVSpeechUtterance?
    private var state: SpeechSynthesizerState = .idle
    private var startTime: Date?
    private var eventStream: AsyncStream<SpeechSynthesizerEvent>.Continuation?
    private var speakContinuation: CheckedContinuation<SpeechSynthesisResult, Never>?
    private var currentText: String = ""
    private var currentVoiceId: String = ""
    private var delegateHolder: SpeechSynthesizerDelegateImpl?

    // MARK: - Initialization

    public init() {
        self.synthesizer = AVSpeechSynthesizer()
    }

    // MARK: - Public API

    /// Speak the given text
    /// - Parameters:
    ///   - text: Text to speak
    ///   - config: Synthesis configuration (uses defaults if nil)
    /// - Returns: Result of the synthesis operation
    public func speak(_ text: String, config: SpeechSynthesisConfig? = nil) async -> SpeechSynthesisResult {
        guard !text.isEmpty else {
            return SpeechSynthesisResult(
                success: false,
                text: text,
                voiceIdentifier: "",
                error: "Empty text provided"
            )
        }

        // Stop any ongoing speech
        if synthesizer.isSpeaking || synthesizer.isPaused {
            synthesizer.stopSpeaking(at: .immediate)
        }

        let synthesisConfig = config ?? SpeechSynthesisConfig.englishDefault
        currentConfig = synthesisConfig
        currentText = text

        // Create utterance
        let utterance = AVSpeechUtterance(string: text)

        // Configure voice
        if let voiceId = synthesisConfig.voiceIdentifier,
           let voice = AVSpeechSynthesisVoice(identifier: voiceId) {
            utterance.voice = voice
            currentVoiceId = voiceId
        } else if let language = synthesisConfig.language {
            let voices = AVSpeechSynthesisVoice.speechVoices().filter {
                $0.language.hasPrefix(language)
            }
            if synthesisConfig.preferEnhancedVoice,
               let enhanced = voices.first(where: { $0.quality == .enhanced }) {
                utterance.voice = enhanced
                currentVoiceId = enhanced.identifier
            } else if let defaultVoice = AVSpeechSynthesisVoice(language: language) {
                utterance.voice = defaultVoice
                currentVoiceId = defaultVoice.identifier
            } else if let first = voices.first {
                utterance.voice = first
                currentVoiceId = first.identifier
            } else {
                currentVoiceId = ""
            }
        } else {
            let defaultVoice = AVSpeechSynthesisVoice(language: "en-US")
            utterance.voice = defaultVoice
            currentVoiceId = defaultVoice?.identifier ?? ""
        }

        // Configure parameters
        utterance.rate = normalizedRateToUtteranceRate(synthesisConfig.rate)
        utterance.pitchMultiplier = synthesisConfig.pitch
        utterance.volume = synthesisConfig.volume

        currentUtterance = utterance
        state = .speaking
        startTime = Date()

        // Set up delegate
        let delegate = SpeechSynthesizerDelegateImpl { [weak self] event in
            Task { [weak self] in
                await self?.handleEvent(event)
            }
        }
        delegateHolder = delegate
        synthesizer.delegate = delegate

        // Speak and wait for completion
        synthesizer.speak(utterance)

        return await withCheckedContinuation { continuation in
            self.speakContinuation = continuation
        }
    }

    /// Speak text without waiting for completion
    /// - Parameters:
    ///   - text: Text to speak
    ///   - config: Synthesis configuration
    public func speakNonBlocking(_ text: String, config: SpeechSynthesisConfig? = nil) {
        guard !text.isEmpty else { return }

        if synthesizer.isSpeaking || synthesizer.isPaused {
            synthesizer.stopSpeaking(at: .immediate)
        }

        let synthesisConfig = config ?? SpeechSynthesisConfig.englishDefault
        currentConfig = synthesisConfig

        let utterance = AVSpeechUtterance(string: text)

        if let voiceId = synthesisConfig.voiceIdentifier,
           let voice = AVSpeechSynthesisVoice(identifier: voiceId) {
            utterance.voice = voice
        } else if let language = synthesisConfig.language {
            let voices = AVSpeechSynthesisVoice.speechVoices().filter {
                $0.language.hasPrefix(language)
            }
            if synthesisConfig.preferEnhancedVoice,
               let enhanced = voices.first(where: { $0.quality == .enhanced }) {
                utterance.voice = enhanced
            } else if let defaultVoice = AVSpeechSynthesisVoice(language: language) {
                utterance.voice = defaultVoice
            } else if let first = voices.first {
                utterance.voice = first
            }
        } else {
            utterance.voice = AVSpeechSynthesisVoice(language: "en-US")
        }

        utterance.rate = normalizedRateToUtteranceRate(synthesisConfig.rate)
        utterance.pitchMultiplier = synthesisConfig.pitch
        utterance.volume = synthesisConfig.volume

        currentUtterance = utterance
        state = .speaking
        startTime = Date()

        let delegate = SpeechSynthesizerDelegateImpl { [weak self] event in
            Task { [weak self] in
                await self?.handleEvent(event)
            }
        }
        delegateHolder = delegate
        synthesizer.delegate = delegate
        synthesizer.speak(utterance)
    }

    /// Stop current speech
    /// - Returns: Whether speech was stopped successfully
    @discardableResult
    public func stop() -> Bool {
        guard synthesizer.isSpeaking || synthesizer.isPaused else {
            state = .idle
            return true
        }

        let success = synthesizer.stopSpeaking(at: .immediate)
        state = .idle
        currentUtterance = nil

        // Resume any waiting continuation
        let duration = startTime.map { Date().timeIntervalSince($0) } ?? 0
        speakContinuation?.resume(returning: SpeechSynthesisResult(
            success: false,
            text: currentText,
            voiceIdentifier: currentVoiceId,
            duration: duration,
            error: "Stopped"
        ))
        speakContinuation = nil

        return success
    }

    /// Pause current speech
    /// - Returns: Whether speech was paused successfully
    @discardableResult
    public func pause() -> Bool {
        guard synthesizer.isSpeaking else { return false }

        let success = synthesizer.pauseSpeaking(at: .word)
        if success {
            state = .paused
        }
        return success
    }

    /// Continue speaking after pause
    /// - Returns: Whether speech was continued successfully
    @discardableResult
    public func continueSpeaking() -> Bool {
        guard synthesizer.isPaused else { return false }

        let success = synthesizer.continueSpeaking()
        if success {
            state = .speaking
        }
        return success
    }

    /// Get current synthesizer state
    public func getState() -> SpeechSynthesizerState {
        if synthesizer.isSpeaking {
            return .speaking
        } else if synthesizer.isPaused {
            return .paused
        } else if currentUtterance != nil {
            return .speaking
        }
        return .idle
    }

    /// Get events stream for monitoring synthesizer state
    public func events() -> AsyncStream<SpeechSynthesizerEvent> {
        AsyncStream { continuation in
            self.eventStream = continuation
            continuation.onTermination = { [weak self] _ in
                Task { [weak self] in
                    await self?.clearEventStream()
                }
            }
        }
    }

    /// Check if the synthesizer is currently speaking
    public func isSpeaking() -> Bool {
        synthesizer.isSpeaking
    }

    /// Check if the synthesizer is paused
    public func isPaused() -> Bool {
        synthesizer.isPaused
    }

    /// Get the currently used voice identifier
    public func getCurrentVoiceIdentifier() -> String? {
        currentUtterance?.voice?.identifier
    }

    // MARK: - Private Helpers

    private func normalizedRateToUtteranceRate(_ normalizedRate: Float) -> Float {
        // Map 0-1 range to AVSpeechUtterance rate range
        let minRate = AVSpeechUtteranceMinimumSpeechRate * 1.5
        let maxRate = AVSpeechUtteranceMaximumSpeechRate * 0.75
        let defaultRate = AVSpeechUtteranceDefaultSpeechRate

        if normalizedRate < 0.5 {
            return minRate + (normalizedRate * 2 * (defaultRate - minRate))
        } else {
            return defaultRate + ((normalizedRate - 0.5) * 2 * (maxRate - defaultRate))
        }
    }

    private func handleEvent(_ event: SpeechSynthesizerEvent) {
        eventStream?.yield(event)

        switch event {
        case .finished:
            state = .idle
            currentUtterance = nil
            let duration = startTime.map { Date().timeIntervalSince($0) } ?? 0
            speakContinuation?.resume(returning: SpeechSynthesisResult(
                success: true,
                text: currentText,
                voiceIdentifier: currentVoiceId,
                duration: duration
            ))
            speakContinuation = nil
            startTime = nil

        case .cancelled:
            state = .idle
            currentUtterance = nil
            let duration = startTime.map { Date().timeIntervalSince($0) } ?? 0
            speakContinuation?.resume(returning: SpeechSynthesisResult(
                success: false,
                text: currentText,
                voiceIdentifier: currentVoiceId,
                duration: duration,
                error: "Speech synthesis was cancelled"
            ))
            speakContinuation = nil
            startTime = nil

        case .paused:
            state = .paused

        case .continued:
            state = .speaking

        default:
            break
        }
    }

    private func clearEventStream() {
        eventStream?.finish()
        eventStream = nil
    }
}

// MARK: - Delegate Implementation

private final class SpeechSynthesizerDelegateImpl: NSObject, AVSpeechSynthesizerDelegate, @unchecked Sendable {
    private let onEvent: @Sendable (SpeechSynthesizerEvent) -> Void

    init(onEvent: @escaping @Sendable (SpeechSynthesizerEvent) -> Void) {
        self.onEvent = onEvent
    }

    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didStart utterance: AVSpeechUtterance) {
        onEvent(.started)
    }

    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
        onEvent(.finished)
    }

    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didCancel utterance: AVSpeechUtterance) {
        onEvent(.cancelled)
    }

    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didPause utterance: AVSpeechUtterance) {
        onEvent(.paused)
    }

    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didContinue utterance: AVSpeechUtterance) {
        onEvent(.continued)
    }

    func speechSynthesizer(
        _ synthesizer: AVSpeechSynthesizer,
        willSpeakRangeOfSpeechString characterRange: NSRange,
        utterance: AVSpeechUtterance
    ) {
        // Convert NSRange to Range<Int> (character positions)
        let text = utterance.speechString
        let length = (text as NSString).length
        let loc = characterRange.location
        let end = characterRange.location + characterRange.length
        // Clamp to valid range
        let clampedStart = max(0, min(loc, length))
        let clampedEnd = max(clampedStart, min(end, length))
        let range = clampedStart..<clampedEnd
        onEvent(.willSpeakRange(characterRange: range, utterance: text))
    }
}

// MARK: - Static Convenience Methods

extension SpeechSynthesizerTool {

    /// Speak text with default configuration (convenience method)
    /// - Parameter text: Text to speak
    /// - Returns: Result of synthesis
    public static func speak(_ text: String) async -> SpeechSynthesisResult {
        await SpeechSynthesizerTool().speak(text)
    }

    /// Speak text with custom configuration (convenience method)
    /// - Parameters:
    ///   - text: Text to speak
    ///   - config: Synthesis configuration
    /// - Returns: Result of synthesis
    public static func speak(_ text: String, config: SpeechSynthesisConfig) async -> SpeechSynthesisResult {
        await SpeechSynthesizerTool().speak(text, config: config)
    }

    /// Stop all speech (convenience method)
    public static func stopAll() async {
        await SpeechSynthesizerTool().stop()
    }

    /// Pause speech (convenience method)
    public static func pause() async {
        await SpeechSynthesizerTool().pause()
    }

    /// Continue speech (convenience method)
    public static func resume() async {
        await SpeechSynthesizerTool().continueSpeaking()
    }
}
