import Foundation
import AVFoundation

/// Represents a speech voice with its properties
public struct SpeechVoice: Sendable, Equatable, Identifiable {
    /// Unique identifier for the voice
    public let id: String
    
    /// Voice name (e.g., "Alex", "Samantha")
    public let name: String
    
    /// Language code (e.g., "en-US")
    public let language: String
    
    /// Language display name (e.g., "English (United States)")
    public let languageDisplayName: String
    
    /// Whether this is the default voice for its language
    public let isDefault: Bool
    
    /// Voice quality (enhanced or default)
    public let quality: VoiceQuality
    
    /// Gender of the voice (if available)
    public let gender: VoiceGender?
    
    public init(
        id: String,
        name: String,
        language: String,
        languageDisplayName: String,
        isDefault: Bool = false,
        quality: VoiceQuality = .default,
        gender: VoiceGender? = nil
    ) {
        self.id = id
        self.name = name
        self.language = language
        self.languageDisplayName = languageDisplayName
        self.isDefault = isDefault
        self.quality = quality
        self.gender = gender
    }
    
    /// Create from AVSpeechSynthesisVoice
    public init(from voice: AVSpeechSynthesisVoice) {
        self.id = voice.identifier
        self.name = voice.name
        self.language = voice.language
        self.languageDisplayName = Locale.current.localizedString(forLanguageCode: voice.language) ?? voice.language
        // Check if this is the default voice for its language
        let defaultVoice = AVSpeechSynthesisVoice(language: voice.language)
        self.isDefault = defaultVoice?.identifier == voice.identifier
        self.quality = voice.quality == .enhanced ? .enhanced : .default
        self.gender = nil // AVSpeechSynthesisVoice doesn't expose gender directly
    }
}

/// Voice quality level
public enum VoiceQuality: String, Sendable, Equatable {
    case `default` = "default"
    case enhanced = "enhanced"
}

/// Voice gender
public enum VoiceGender: String, Sendable, Equatable {
    case male
    case female
    case neutral
}

/// Voice selection criteria
public struct VoiceSelectionCriteria: Sendable, Equatable {
    /// Language code (e.g., "en-US")
    public let language: String?
    
    /// Voice quality preference
    public let quality: VoiceQuality?
    
    /// Gender preference
    public let gender: VoiceGender?
    
    /// Specific voice identifier to use
    public let voiceIdentifier: String?
    
    /// Name of the voice to use (partial match)
    public let voiceName: String?
    
    public init(
        language: String? = nil,
        quality: VoiceQuality? = nil,
        gender: VoiceGender? = nil,
        voiceIdentifier: String? = nil,
        voiceName: String? = nil
    ) {
        self.language = language
        self.quality = quality
        self.gender = gender
        self.voiceIdentifier = voiceIdentifier
        self.voiceName = voiceName
    }
    
    /// Default English voice
    public static let englishDefault = VoiceSelectionCriteria(language: "en-US")
    
    /// Enhanced English voice
    public static let englishEnhanced = VoiceSelectionCriteria(language: "en-US", quality: .enhanced)
}

/// Speech rate configuration
public struct SpeechRate: Sendable, Equatable {
    /// Rate value (0.0 to 1.0, where 0.5 is normal)
    public let value: Float
    
    /// Named rate preset
    public let preset: RatePreset?
    
    public init(value: Float, preset: RatePreset? = nil) {
        self.value = max(0.0, min(1.0, value))
        self.preset = preset
    }
    
    /// Rate presets
    public enum RatePreset: String, Sendable, CaseIterable {
        case xSlow = "x-slow"
        case slow = "slow"
        case normal = "normal"
        case fast = "fast"
        case xFast = "x-fast"
        
        /// Get rate value for preset (0.0-1.0 scale)
        public var rateValue: Float {
            switch self {
            case .xSlow: return 0.3
            case .slow: return 0.4
            case .normal: return 0.5
            case .fast: return 0.55
            case .xFast: return 0.6
            }
        }
    }
    
    /// Create from preset
    public static func from(preset: RatePreset) -> SpeechRate {
        SpeechRate(value: preset.rateValue, preset: preset)
    }
    
    /// Common presets
    public static let slow = SpeechRate.from(preset: .slow)
    public static let normal = SpeechRate.from(preset: .normal)
    public static let fast = SpeechRate.from(preset: .fast)
}

/// Pitch configuration
public struct SpeechPitch: Sendable, Equatable {
    /// Pitch value (0.5 to 2.0, where 1.0 is normal)
    public let value: Float
    
    /// Named pitch preset
    public let preset: PitchPreset?
    
    public init(value: Float, preset: PitchPreset? = nil) {
        self.value = max(0.5, min(2.0, value))
        self.preset = preset
    }
    
    /// Pitch presets
    public enum PitchPreset: String, Sendable, CaseIterable {
        case xLow = "x-low"
        case low = "low"
        case normal = "normal"
        case high = "high"
        case xHigh = "x-high"
        
        /// Get pitch value for preset (0.5-2.0 scale)
        public var pitchValue: Float {
            switch self {
            case .xLow: return 0.6
            case .low: return 0.8
            case .normal: return 1.0
            case .high: return 1.2
            case .xHigh: return 1.4
            }
        }
    }
    
    /// Create from preset
    public static func from(preset: PitchPreset) -> SpeechPitch {
        SpeechPitch(value: preset.pitchValue, preset: preset)
    }
    
    /// Common presets
    public static let normal = SpeechPitch.from(preset: .normal)
}

/// Volume configuration
public struct SpeechVolume: Sendable, Equatable {
    /// Volume value (0.0 to 1.0)
    public let value: Float
    
    public init(value: Float) {
        self.value = max(0.0, min(1.0, value))
    }
    
    /// Common values
    public static let silent = SpeechVolume(value: 0.0)
    public static let low = SpeechVolume(value: 0.3)
    public static let medium = SpeechVolume(value: 0.6)
    public static let loud = SpeechVolume(value: 1.0)
}

/// Voice configuration including all speech parameters
public struct VoiceConfiguration: Sendable, Equatable {
    /// Selected voice
    public let voice: SpeechVoice
    
    /// Speech rate
    public let rate: SpeechRate
    
    /// Pitch
    public let pitch: SpeechPitch
    
    /// Volume
    public let volume: SpeechVolume
    
    /// Pre-phoneme delay (seconds)
    public let prePhonemeDelay: Double?
    
    /// Post-phoneme delay (seconds)
    public let postPhonemeDelay: Double?
    
    public init(
        voice: SpeechVoice,
        rate: SpeechRate = .normal,
        pitch: SpeechPitch = .normal,
        volume: SpeechVolume = .loud,
        prePhonemeDelay: Double? = nil,
        postPhonemeDelay: Double? = nil
    ) {
        self.voice = voice
        self.rate = rate
        self.pitch = pitch
        self.volume = volume
        self.prePhonemeDelay = prePhonemeDelay
        self.postPhonemeDelay = postPhonemeDelay
    }
    
    /// Create a default English configuration
    public static let englishDefault = VoiceConfiguration(
        voice: SpeechVoice(
            id: AVSpeechSynthesisVoice(language: "en-US")?.identifier ?? "",
            name: AVSpeechSynthesisVoice(language: "en-US")?.name ?? "Default",
            language: "en-US",
            languageDisplayName: "English (United States)",
            isDefault: true
        )
    )
}

/// Tool for managing voice selection and speech rate control
///
/// Provides functionality to select voices based on criteria, control speech
/// rate, pitch, and volume, and manage voice configurations for text-to-speech.
///
/// Phase 3: API Integration — MiniMax API client, Claude API, model management, multimodal
/// Section: 3.4
/// Task: Voice selection and rate control
///
/// Usage:
///
///   let tool = VoiceControlTool()
///   
///   // Get all available voices
///   let voices = await tool.getAvailableVoices()
///   
///   // Select a voice by criteria
///   let voice = await tool.selectVoice(criteria: .englishEnhanced)
///   
///   // Get a voice configuration with custom rate
///   let config = await tool.getConfiguration(
///       criteria: .englishDefault,
///       rate: .fast,
///       pitch: .normal
///   )
///
public actor VoiceControlTool: Sendable {
    
    /// Default quality for voice selection when not specified
    private let preferredQuality: VoiceQuality = .enhanced
    
    public init() {}
    
    // MARK: - Voice Selection
    
    /// Get all available voices
    /// - Returns: Array of available SpeechVoice objects
    public func getAvailableVoices() -> [SpeechVoice] {
        AVSpeechSynthesisVoice.speechVoices().map { SpeechVoice(from: $0) }
    }
    
    /// Get voices filtered by criteria
    /// - Parameter criteria: Selection criteria
    /// - Returns: Array of matching voices
    public func getVoices(matching criteria: VoiceSelectionCriteria) -> [SpeechVoice] {
        var voices = AVSpeechSynthesisVoice.speechVoices().map { SpeechVoice(from: $0) }
        
        // Filter by language
        if let language = criteria.language {
            voices = voices.filter { $0.language.hasPrefix(language) }
        }
        
        // Filter by quality
        if let quality = criteria.quality {
            voices = voices.filter { $0.quality == quality }
        }
        
        // Filter by specific voice identifier
        if let voiceId = criteria.voiceIdentifier {
            voices = voices.filter { $0.id == voiceId }
            return voices
        }
        
        // Filter by voice name (partial match)
        if let name = criteria.voiceName {
            voices = voices.filter { $0.name.lowercased().contains(name.lowercased()) }
        }
        
        return voices
    }
    
    /// Select a single voice based on criteria
    /// - Parameter criteria: Selection criteria
    /// - Returns: The best matching voice, or nil if none found
    public func selectVoice(matching criteria: VoiceSelectionCriteria) -> SpeechVoice? {
        let voices = getVoices(matching: criteria)
        
        // Prefer default voices, then enhanced quality
        return voices.first { $0.isDefault }
            ?? voices.first { $0.quality == .enhanced }
            ?? voices.first
    }
    
    /// Get the default voice for a language
    /// - Parameter language: Language code (e.g., "en-US")
    /// - Returns: Default voice for the language
    public func getDefaultVoice(for language: String) -> SpeechVoice? {
        AVSpeechSynthesisVoice(language: language).map { SpeechVoice(from: $0) }
    }
    
    /// Get available languages
    /// - Returns: Array of language codes with available voices
    public func getAvailableLanguages() -> [String] {
        let voices = AVSpeechSynthesisVoice.speechVoices()
        let languages = Set(voices.map { $0.language })
        return Array(languages).sorted()
    }
    
    // MARK: - Configuration
    
    /// Get a voice configuration with specified parameters
    /// - Parameters:
    ///   - criteria: Voice selection criteria
    ///   - rate: Speech rate (defaults to normal)
    ///   - pitch: Speech pitch (defaults to normal)
    ///   - volume: Speech volume (defaults to loud)
    /// - Returns: VoiceConfiguration with selected voice and parameters
    public func getConfiguration(
        criteria: VoiceSelectionCriteria,
        rate: SpeechRate = .normal,
        pitch: SpeechPitch = .normal,
        volume: SpeechVolume = .loud
    ) -> VoiceConfiguration? {
        guard let voice = selectVoice(matching: criteria) else {
            return nil
        }
        
        return VoiceConfiguration(
            voice: voice,
            rate: rate,
            pitch: pitch,
            volume: volume
        )
    }
    
    /// Create a configuration with a specific voice identifier
    /// - Parameters:
    ///   - voiceIdentifier: The voice identifier
    ///   - rate: Speech rate
    ///   - pitch: Speech pitch
    ///   - volume: Speech volume
    /// - Returns: VoiceConfiguration or nil if voice not found
    public func getConfiguration(
        voiceIdentifier: String,
        rate: SpeechRate = .normal,
        pitch: SpeechPitch = .normal,
        volume: SpeechVolume = .loud
    ) -> VoiceConfiguration? {
        let criteria = VoiceSelectionCriteria(voiceIdentifier: voiceIdentifier)
        return getConfiguration(criteria: criteria, rate: rate, pitch: pitch, volume: volume)
    }
    
    // MARK: - Rate/Pitch/Volume Helpers
    
    /// Convert rate from AVSpeechUtterance minimum/maximum to 0-1 scale
    /// - Parameter utteranceRate: Rate as used in AVSpeechUtterance
    /// - Returns: Normalized rate (0.0-1.0)
    public func normalizeRate(_ utteranceRate: Float) -> Float {
        // AVSpeechUtteranceMinimumSpeechRate = 0.0
        // AVSpeechUtteranceDefaultSpeechRate = 0.5
        // AVSpeechUtteranceMaximumSpeechRate = 1.0
        max(0.0, min(1.0, utteranceRate))
    }
    
    /// Convert normalized rate to AVSpeechUtterance rate
    /// - Parameter normalizedRate: Rate on 0-1 scale
    /// - Returns: AVSpeechUtterance compatible rate
    public func denormalizeRate(_ normalizedRate: Float) -> Float {
        // Scale from 0-1 to AVSpeechUtterance range
        // This maps 0-1 to roughly 0.3-0.6 which is a comfortable range
        let minRate = AVSpeechUtteranceDefaultSpeechRate * 0.5
        let maxRate = AVSpeechUtteranceDefaultSpeechRate * 1.5
        return minRate + (normalizedRate * (maxRate - minRate))
    }
    
    /// Get rate from speech rate value
    public func getSpeechRate(value: Float) -> SpeechRate {
        SpeechRate(value: value)
    }
    
    /// Get pitch from pitch value
    public func getSpeechPitch(value: Float) -> SpeechPitch {
        SpeechPitch(value: value)
    }
}

// MARK: - Static Convenience Methods

extension VoiceControlTool {
    
    /// Get all available voices (convenience method)
    public static func voices() async -> [SpeechVoice] {
        await VoiceControlTool().getAvailableVoices()
    }
    
    /// Select a voice by criteria (convenience method)
    public static func selectVoice(criteria: VoiceSelectionCriteria) async -> SpeechVoice? {
        await VoiceControlTool().selectVoice(matching: criteria)
    }
    
    /// Get a voice configuration (convenience method)
    public static func configuration(
        criteria: VoiceSelectionCriteria,
        rate: SpeechRate = .normal,
        pitch: SpeechPitch = .normal,
        volume: SpeechVolume = .loud
    ) async -> VoiceConfiguration? {
        await VoiceControlTool().getConfiguration(criteria: criteria, rate: rate, pitch: pitch, volume: volume)
    }
}
