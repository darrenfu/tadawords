import TadaWordsDomain
import XCTest

@testable import TadaWordsLearning

final class ReviewPriorityTests: XCTestCase {
    func testGuardianRequeuedLearnedWordRisesWithinDueClass() {
        let now = Date(timeIntervalSince1970: 10_000)
        let ordinary = ReviewPriorityCandidate(
            wordPromptID: WordPromptID(),
            nextReviewAt: now.addingTimeInterval(-100),
            predictedRecall: 0.2,
            lapseCount: 0,
            independentIncorrectRate: 0
        )
        let requeued = ReviewPriorityCandidate(
            wordPromptID: WordPromptID(),
            nextReviewAt: now.addingTimeInterval(-100),
            predictedRecall: 0.8,
            lapseCount: 0,
            independentIncorrectRate: 0,
            guardianRequeuedAt: now
        )

        XCTAssertEqual(
            ReviewPriorityRanker().ranked([ordinary, requeued], asOf: now)
                .first?.wordPromptID,
            requeued.wordPromptID
        )
    }

    func testDueStatusOutranksExtremeWeakSignals() {
        let due = ReviewPriorityCandidate(
            wordPromptID: TestFixture.wordID(1),
            nextReviewAt: TestFixture.now.addingTimeInterval(-60),
            predictedRecall: 0.80,
            lapseCount: 0,
            independentIncorrectRate: 0,
            paceRatio: 1,
            replayCount: 0
        )
        let futureButSlow = ReviewPriorityCandidate(
            wordPromptID: TestFixture.wordID(2),
            nextReviewAt: TestFixture.now.addingTimeInterval(60),
            predictedRecall: 0.01,
            lapseCount: 50,
            independentIncorrectRate: 1,
            paceRatio: 20,
            replayCount: 50
        )

        let ranked = ReviewPriorityRanker().ranked(
            [futureButSlow, due],
            asOf: TestFixture.now
        )

        XCTAssertEqual(ranked.map(\.wordPromptID), [due.wordPromptID, futureButSlow.wordPromptID])
    }

    func testLowestPredictedRecallPrecedesErrorsAndPace() {
        let lowestRecall = ReviewPriorityCandidate(
            wordPromptID: TestFixture.wordID(1),
            nextReviewAt: TestFixture.now.addingTimeInterval(-3_600),
            predictedRecall: 0.20,
            lapseCount: 0,
            independentIncorrectRate: 0
        )
        let recentWithProblems = ReviewPriorityCandidate(
            wordPromptID: TestFixture.wordID(2),
            nextReviewAt: TestFixture.now.addingTimeInterval(-10),
            predictedRecall: 0.70,
            lapseCount: 10,
            independentIncorrectRate: 1,
            paceRatio: 10,
            replayCount: 10
        )

        let ranked = ReviewPriorityRanker().ranked(
            [recentWithProblems, lowestRecall],
            asOf: TestFixture.now
        )

        XCTAssertEqual(ranked.first?.wordPromptID, lowestRecall.wordPromptID)
    }

    func testErrorPaceReplayAndHelpBreakRecallTiesInThatOrder() {
        let baseline = ReviewPriorityCandidate(
            wordPromptID: TestFixture.wordID(1),
            nextReviewAt: TestFixture.now,
            predictedRecall: 0.50,
            lapseCount: 1,
            independentIncorrectRate: 0,
            paceRatio: 1,
            replayCount: 0
        )
        let errorProne = ReviewPriorityCandidate(
            wordPromptID: TestFixture.wordID(2),
            nextReviewAt: TestFixture.now,
            predictedRecall: 0.50,
            lapseCount: 1,
            independentIncorrectRate: 0.75
        )
        let slower = ReviewPriorityCandidate(
            wordPromptID: TestFixture.wordID(3),
            nextReviewAt: TestFixture.now,
            predictedRecall: 0.50,
            lapseCount: 1,
            independentIncorrectRate: 0,
            paceRatio: 2
        )
        let replayed = ReviewPriorityCandidate(
            wordPromptID: TestFixture.wordID(4),
            nextReviewAt: TestFixture.now,
            predictedRecall: 0.50,
            lapseCount: 1,
            independentIncorrectRate: 0,
            paceRatio: 1,
            replayCount: 5
        )
        let helped = ReviewPriorityCandidate(
            wordPromptID: TestFixture.wordID(5),
            nextReviewAt: TestFixture.now,
            predictedRecall: 0.50,
            lapseCount: 1,
            independentIncorrectRate: 0,
            paceRatio: 1,
            helpCount: 5
        )

        let ranked = ReviewPriorityRanker().ranked(
            [baseline, helped, replayed, slower, errorProne],
            asOf: TestFixture.now
        )

        XCTAssertEqual(
            ranked.map(\.wordPromptID),
            [errorProne, slower, replayed, helped, baseline].map(\.wordPromptID)
        )
    }
}
