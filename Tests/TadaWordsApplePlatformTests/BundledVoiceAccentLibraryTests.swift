import TadaWordsDomain
import XCTest

@testable import TadaWordsApplePlatform

final class BundledVoiceAccentLibraryTests: XCTestCase {
    func testProductionAuroraPackContainsTheDesignedTransitionSet() throws {
        let library = BundledVoiceAccentLibrary.production()

        XCTAssertNotNil(library.launch)
        XCTAssertEqual(library.correct.count, 5)
        XCTAssertFalse(
            library.correct.contains {
                $0.lastPathComponent == "ta-da.m4a"
            }
        )
        XCTAssertNotNil(library.questComplete)
    }

    func testQuestFeedbackTransitionsNeverLayerSpokenPraise() {
        XCTAssertFalse(
            SpokenAccentPolicy.allows(.correct, preferences: .default)
        )
        XCTAssertFalse(
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
