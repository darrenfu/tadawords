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
}
