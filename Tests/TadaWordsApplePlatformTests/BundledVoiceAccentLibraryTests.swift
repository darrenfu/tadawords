import TadaWordsDomain
import XCTest

@testable import TadaWordsApplePlatform

final class BundledVoiceAccentLibraryTests: XCTestCase {
    func testProductionAuroraPackContainsTheDesignedTransitionSet() throws {
        let library = BundledVoiceAccentLibrary.production()

        XCTAssertNotNil(library.launch)
        XCTAssertEqual(library.correct.count, 6)
        XCTAssertNotNil(library.questComplete)
    }

    func testSpokenTransitionsRespectVoiceAndReducedSoundPreferences() {
        XCTAssertTrue(
            SpokenAccentPolicy.allows(.correct, preferences: .default)
        )
        XCTAssertTrue(
            SpokenAccentPolicy.allows(.reward, preferences: .default)
        )
        XCTAssertFalse(
            SpokenAccentPolicy.allows(
                .correct,
                preferences: AudioPreferences(voiceEnabled: false)
            )
        )
        XCTAssertFalse(
            SpokenAccentPolicy.allows(
                .correct,
                preferences: AudioPreferences(reducedSoundEnabled: true)
            )
        )
        XCTAssertFalse(
            SpokenAccentPolicy.allows(.validRetry, preferences: .default)
        )
        XCTAssertFalse(
            SpokenAccentPolicy.allows(.star(index: 0), preferences: .default)
        )
    }
}
