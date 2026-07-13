import TadaWordsDomain
import XCTest

@testable import TadaWordsFeatures

final class QuestPresentationTests: XCTestCase {
    func testReadStudyPromptOnlyDemonstratesNewWords() {
        XCTAssertTrue(ReadStudyPromptPolicy.shouldDemonstrate(source: .new))
        XCTAssertFalse(ReadStudyPromptPolicy.shouldDemonstrate(source: .review))
    }

    func testFirstTryAccuracyIsNotScoredWithoutIndependentAttempts() {
        let result = QuestResultViewState(
            mode: .read,
            score: QuestScore(
                points: 0,
                firstIndependentCorrectCount: 0,
                firstIndependentAttemptCount: 0,
                stars: QuestStars(earned: [.completion]),
                personalPaceAssessment: .unavailable
            )
        )

        XCTAssertNil(result.firstTryAccuracyPercentage)
    }

    func testFirstTryAccuracyUsesRoundedPercentageWhenScored() {
        let result = QuestResultViewState(
            mode: .write,
            score: QuestScore(
                points: 20,
                firstIndependentCorrectCount: 2,
                firstIndependentAttemptCount: 3,
                stars: QuestStars(earned: [.completion, .accuracy]),
                personalPaceAssessment: .withinPersonalBand
            )
        )

        XCTAssertEqual(result.firstTryAccuracyPercentage, 67)
    }
}
