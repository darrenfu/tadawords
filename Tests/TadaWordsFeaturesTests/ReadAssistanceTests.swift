import XCTest

@testable import TadaWordsFeatures

final class ReadAssistanceTests: XCTestCase {
    func testHelpStaysHiddenUntilTwoValidWrongAnswers() {
        XCTAssertFalse(
            ReadAssistancePolicy.shouldReveal(
                validIncorrectAttemptCount: 0,
                isComplete: false
            )
        )
        XCTAssertFalse(
            ReadAssistancePolicy.shouldReveal(
                validIncorrectAttemptCount: 1,
                isComplete: false
            )
        )
        XCTAssertTrue(
            ReadAssistancePolicy.shouldReveal(
                validIncorrectAttemptCount: 2,
                isComplete: false
            )
        )
    }

    func testHelpIsNotLeftVisibleAfterCompletion() {
        XCTAssertFalse(
            ReadAssistancePolicy.shouldReveal(
                validIncorrectAttemptCount: 3,
                isComplete: true
            )
        )
    }

    func testPictureCatalogNormalizesKnownWordsAndDoesNotGuess() {
        XCTAssertEqual(
            WordPictureHintCatalog.hint(for: "  DOG!  "),
            WordPictureHint(glyph: "🐶", accessibilityLabel: "a dog")
        )
        XCTAssertNil(WordPictureHintCatalog.hint(for: "read"))
    }
}
