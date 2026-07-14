import Foundation
import TadaWordsDomain
import XCTest

final class AudioPreferencePolicyTests: XCTestCase {
    func testReducedSoundKeepsLearningFeedbackAndRemovesDecorativeCues() {
        let preferences = AudioPreferences(reducedSoundEnabled: true)

        XCTAssertTrue(AudioPreferencePolicy.shouldPlay(.correct, preferences: preferences))
        XCTAssertTrue(AudioPreferencePolicy.shouldPlay(.validRetry, preferences: preferences))
        XCTAssertTrue(
            AudioPreferencePolicy.shouldPlay(.technicalRetry, preferences: preferences)
        )
        XCTAssertFalse(AudioPreferencePolicy.shouldPlay(.click, preferences: preferences))
        XCTAssertFalse(
            AudioPreferencePolicy.shouldPlay(.star(index: 0), preferences: preferences)
        )
        XCTAssertFalse(AudioPreferencePolicy.shouldPlay(.reward, preferences: preferences))
        XCTAssertFalse(
            AudioPreferencePolicy.shouldPlay(
                .writing(tool: .pencil),
                preferences: preferences
            )
        )
        XCTAssertFalse(
            AudioPreferencePolicy.allowsDecorativeSoundEffects(preferences: preferences)
        )
    }

    func testNormalSoundKeepsEveryFunctionalCue() {
        let preferences = AudioPreferences()
        let cues: [FunctionalAudioCue] = [
            .click,
            .correct,
            .validRetry,
            .technicalRetry,
            .star(index: 2),
            .reward,
            .writing(tool: .brush),
        ]

        XCTAssertTrue(
            cues.allSatisfy {
                AudioPreferencePolicy.shouldPlay($0, preferences: preferences)
            }
        )
        XCTAssertTrue(
            AudioPreferencePolicy.allowsDecorativeSoundEffects(preferences: preferences)
        )
    }

    func testDisabledSoundEffectsOverrideEssentialLearningFeedback() {
        let preferences = AudioPreferences(
            soundEffectsEnabled: false,
            reducedSoundEnabled: true
        )

        XCTAssertFalse(AudioPreferencePolicy.shouldPlay(.correct, preferences: preferences))
        XCTAssertFalse(
            AudioPreferencePolicy.shouldPlay(.technicalRetry, preferences: preferences)
        )
        XCTAssertFalse(
            AudioPreferencePolicy.shouldPlay(
                .writing(tool: .chalk),
                preferences: preferences
            )
        )
    }

    func testCalmEmergencyPreferenceSuppressesRequestedUrgencyLayer() {
        XCTAssertTrue(
            AudioPreferencePolicy.emergencyLayerIsEnabled(
                requested: true,
                preferences: AudioPreferences(calmEmergencyEnabled: false)
            )
        )
        XCTAssertFalse(
            AudioPreferencePolicy.emergencyLayerIsEnabled(
                requested: true,
                preferences: AudioPreferences(calmEmergencyEnabled: true)
            )
        )
        XCTAssertFalse(
            AudioPreferencePolicy.emergencyLayerIsEnabled(
                requested: false,
                preferences: AudioPreferences(calmEmergencyEnabled: false)
            )
        )
    }

    func testLegacyVoiceStyleIsIgnoredDuringCanonicalVoiceMigration() throws {
        let legacy = Data(
            #"{"voiceEnabled":true,"musicEnabled":false,"soundEffectsEnabled":true,"reducedSoundEnabled":false,"calmEmergencyEnabled":false,"spokenVoiceStyle":"brightMan"}"#
                .utf8
        )

        let decoded = try JSONDecoder().decode(AudioPreferences.self, from: legacy)

        XCTAssertTrue(decoded.voiceEnabled)
        XCTAssertFalse(decoded.musicEnabled)
        XCTAssertEqual(
            decoded,
            AudioPreferences(musicEnabled: false)
        )
    }

    func testSavingPreferencesDropsLegacyVoiceStyleField() throws {
        let encoded = try JSONEncoder().encode(AudioPreferences())
        let object = try XCTUnwrap(
            JSONSerialization.jsonObject(with: encoded) as? [String: Any]
        )

        XCTAssertNil(object["spokenVoiceStyle"])
    }
}
