import TadaWordsDomain
import XCTest

@testable import TadaWordsFeatures

final class QuestPresentationTests: XCTestCase {
    func testReadPermissionTimingResetsForFirstPromptAndAfterDenial() {
        XCTAssertTrue(
            ReadPermissionTimingPolicy.shouldResetResponseClock(
                hasRequestedPermission: false,
                wasPreviouslyDenied: false
            )
        )
        XCTAssertTrue(
            ReadPermissionTimingPolicy.shouldResetResponseClock(
                hasRequestedPermission: true,
                wasPreviouslyDenied: true
            )
        )
        XCTAssertFalse(
            ReadPermissionTimingPolicy.shouldResetResponseClock(
                hasRequestedPermission: true,
                wasPreviouslyDenied: false
            )
        )
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

    func testPracticePowerUpResultExposesReplayAction() {
        let result = QuestResultViewState(
            mode: .read,
            score: QuestScore(
                points: 40,
                firstIndependentCorrectCount: 1,
                firstIndependentAttemptCount: 1,
                stars: QuestStars(earned: [.completion]),
                personalPaceAssessment: .withinPersonalBand
            ),
            runKind: .practiceAgain
        )

        XCTAssertFalse(result.showsNewCollectible)
        XCTAssertTrue(result.showsReplayAction)
    }
}
