import Foundation

/// Parent-controlled audio preferences stored with each child profile.
public struct AudioPreferences: Codable, Hashable, Sendable {
    public let voiceEnabled: Bool
    public let musicEnabled: Bool
    public let soundEffectsEnabled: Bool
    public let reducedSoundEnabled: Bool
    public let calmEmergencyEnabled: Bool

    public init(
        voiceEnabled: Bool = true,
        musicEnabled: Bool = true,
        soundEffectsEnabled: Bool = true,
        reducedSoundEnabled: Bool = false,
        calmEmergencyEnabled: Bool = false
    ) {
        self.voiceEnabled = voiceEnabled
        self.musicEnabled = musicEnabled
        self.soundEffectsEnabled = soundEffectsEnabled
        self.reducedSoundEnabled = reducedSoundEnabled
        self.calmEmergencyEnabled = calmEmergencyEnabled
    }

    public static let `default` = AudioPreferences()

    private enum CodingKeys: String, CodingKey {
        case voiceEnabled
        case musicEnabled
        case soundEffectsEnabled
        case reducedSoundEnabled
        case calmEmergencyEnabled
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            voiceEnabled: try container.decodeIfPresent(
                Bool.self,
                forKey: .voiceEnabled
            ) ?? true,
            musicEnabled: try container.decodeIfPresent(
                Bool.self,
                forKey: .musicEnabled
            ) ?? true,
            soundEffectsEnabled: try container.decodeIfPresent(
                Bool.self,
                forKey: .soundEffectsEnabled
            ) ?? true,
            reducedSoundEnabled: try container.decodeIfPresent(
                Bool.self,
                forKey: .reducedSoundEnabled
            ) ?? false,
            calmEmergencyEnabled: try container.decodeIfPresent(
                Bool.self,
                forKey: .calmEmergencyEnabled
            ) ?? false
        )
    }
}

/// Stable product meanings. Platform adapters choose a world-specific timbre
/// without changing what the child learns from each cue.
public enum FunctionalAudioCue: Hashable, Sendable {
    case click
    case correct
    case validRetry
    case technicalRetry
    case star(index: Int)
    case reward
}

/// Keeps the meaning of the parent audio controls independent from the
/// platform renderer. Reduced sound removes decorative cues while preserving
/// the immediate feedback a child needs to understand a learning attempt.
public enum AudioPreferencePolicy {
    public static func allowsDecorativeSoundEffects(
        preferences: AudioPreferences
    ) -> Bool {
        preferences.soundEffectsEnabled && !preferences.reducedSoundEnabled
    }

    public static func shouldPlay(
        _ cue: FunctionalAudioCue,
        preferences: AudioPreferences
    ) -> Bool {
        guard preferences.soundEffectsEnabled else { return false }
        guard preferences.reducedSoundEnabled else { return true }

        return switch cue {
        case .correct, .validRetry, .technicalRetry:
            true
        case .click, .star, .reward:
            false
        }
    }

    public static func emergencyLayerIsEnabled(
        requested: Bool,
        preferences: AudioPreferences
    ) -> Bool {
        requested && !preferences.calmEmergencyEnabled
    }
}

/// Owns non-verbal app audio. Feature code never imports AVFoundation and the
/// app composes one explicit instance instead of relying on a global singleton.
public protocol AudioExperienceService: Sendable {
    func playLaunchSignature() async

    /// Applies a world's preferences without starting its score. Launch code
    /// uses this before the spoken brand mark so it does not render music that
    /// would immediately be stopped.
    func configure(world: WorldTheme, preferences: AudioPreferences) async
    func activate(world: WorldTheme, preferences: AudioPreferences) async
    func stopAmbientAudio() async
    func play(_ cue: FunctionalAudioCue) async

    /// Adds a gentle rhythmic layer when the quest timer enters rescue time.
    /// The layer changes urgency without raising the music's peak level.
    func setEmergencyMode(_ isEnabled: Bool) async

    /// Returns false when the parent disabled Voice.
    func prepareForVoicePrompt() async -> Bool
    func finishVoicePrompt() async

    /// Stops music and non-essential effects before microphone capture.
    func prepareForRecording() async
    func finishRecording() async
    func setApplicationActive(_ isActive: Bool) async
}

public struct SilentAudioExperienceService: AudioExperienceService {
    public init() {}

    public func playLaunchSignature() async {}
    public func configure(world: WorldTheme, preferences: AudioPreferences) async {
        _ = world
        _ = preferences
    }
    public func activate(world: WorldTheme, preferences: AudioPreferences) async {
        _ = world
        _ = preferences
    }
    public func stopAmbientAudio() async {}
    public func play(_ cue: FunctionalAudioCue) async { _ = cue }
    public func setEmergencyMode(_ isEnabled: Bool) async { _ = isEnabled }
    public func prepareForVoicePrompt() async -> Bool { true }
    public func finishVoicePrompt() async {}
    public func prepareForRecording() async {}
    public func finishRecording() async {}
    public func setApplicationActive(_ isActive: Bool) async { _ = isActive }
}

/// Existing test doubles and alternate adapters do not need to implement an
/// urgency layer unless they render ambient music.
extension AudioExperienceService {
    public func configure(world: WorldTheme, preferences: AudioPreferences) async {
        await activate(world: world, preferences: preferences)
        await stopAmbientAudio()
    }

    public func setEmergencyMode(_ isEnabled: Bool) async { _ = isEnabled }
}
