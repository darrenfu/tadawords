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
            runKind: .practiceAgain,
            replayWordCount: 2
        )

        XCTAssertFalse(result.showsNewCollectible)
        XCTAssertTrue(result.showsReplayAction)
        XCTAssertEqual(result.replayActionLabel, "Replay 2 tricky words")
    }

    func testPerfectResultDoesNotOfferAnEmptyReplay() {
        let result = QuestResultViewState(
            mode: .write,
            score: QuestScore(
                points: 100,
                firstIndependentCorrectCount: 3,
                firstIndependentAttemptCount: 3,
                stars: QuestStars(earned: Set(QuestStar.allCases)),
                personalPaceAssessment: .calibrating(
                    sampleCount: 0,
                    requiredSampleCount: 3
                )
            ),
            replayWordCount: 0
        )

        XCTAssertFalse(result.showsReplayAction)
        XCTAssertEqual(result.paceLabel, "Learning your pace")
    }

    func testPerfectFirstTryExplainsPaceBonusWhenTimingIsUnavailable() {
        let result = QuestResultViewState(
            mode: .read,
            score: QuestScore(
                points: 100,
                firstIndependentCorrectCount: 2,
                firstIndependentAttemptCount: 2,
                stars: QuestStars(earned: Set(QuestStar.allCases)),
                personalPaceAssessment: .unavailable
            )
        )

        XCTAssertEqual(result.paceLabel, "Perfect first try")
    }
}
