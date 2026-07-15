import TadaWordsDomain
import XCTest

@testable import TadaWordsLearning

final class WordProgressReducerSignalTests: XCTestCase {
    func testRebuildDerivesTimingReplayHelpAndUncertainSignalsFromUniqueEvents() throws {
        let firstCorrect = TestFixture.attempt(
            number: 1,
            wordNumber: 1,
            outcome: .correct,
            at: TestFixture.now,
            responseSeconds: 4,
            replayCount: 1
        )
        let helped = TestFixture.attempt(
            number: 2,
            wordNumber: 1,
            evidence: .helped,
            outcome: .correct,
            at: TestFixture.now.addingTimeInterval(1),
            responseSeconds: 2,
            replayCount: 2
        )
        let uncertain = TestFixture.attempt(
            number: 3,
            wordNumber: 1,
            evidence: .recognitionUncertain,
            outcome: .recognitionUncertain,
            at: TestFixture.now.addingTimeInterval(2),
            replayCount: 1
        )
        let laterIncorrect = TestFixture.attempt(
            number: 4,
            wordNumber: 1,
            outcome: .incorrect,
            at: TestFixture.now.addingTimeInterval(3),
            responseSeconds: 8,
            replayCount: 3
        )

        let progress = try WordProgressReducer().rebuild(
            profileID: TestFixture.profileID,
            wordPromptID: TestFixture.wordID(1),
            learningMode: .read,
            from: [laterIncorrect, uncertain, helped, firstCorrect, firstCorrect]
        )

        XCTAssertEqual(progress.firstIndependentAttemptCount, 2)
        XCTAssertEqual(progress.firstIndependentCorrectCount, 1)
        XCTAssertEqual(progress.firstIndependentResponseTimeTotal.seconds, 12)
        XCTAssertEqual(progress.firstIndependentTimedAttemptCount, 2)
        XCTAssertEqual(progress.firstIndependentMeanResponseTime?.seconds, 6)
        XCTAssertEqual(progress.totalReplayCount, 7)
        XCTAssertEqual(progress.helpedAttemptCount, 1)
        XCTAssertEqual(progress.uncertainAttemptCount, 1)
        XCTAssertEqual(progress.independentSuccessDates, [TestFixture.now])
    }

    func testMissingTimingIsExcludedFromMeanWithoutLosingAccuracyAttempt() throws {
        let untimed = TestFixture.attempt(
            number: 1,
            wordNumber: 1,
            outcome: .correct,
            responseSeconds: nil
        )

        let progress = try WordProgressReducer().rebuild(
            profileID: TestFixture.profileID,
            wordPromptID: TestFixture.wordID(1),
            learningMode: .read,
            from: [untimed]
        )

        XCTAssertEqual(progress.firstIndependentAttemptCount, 1)
        XCTAssertEqual(progress.firstIndependentTimedAttemptCount, 0)
        XCTAssertNil(progress.firstIndependentMeanResponseTime)
    }

    func testLetterKeyboardTimingDoesNotPolluteHandwritingAggregateOrSlowPenalty()
        throws
    {
        let handwritingContext = TestFixture.paceContext(
            mode: .write,
            wordLength: 3
        )
        let keyboardContext = PaceContext(
            learningMode: .write,
            deviceClass: .tablet,
            inputMethod: .letterKeyboard,
            wordLength: 3
        )
        let handwriting = TestFixture.attempt(
            number: 1,
            wordNumber: 1,
            mode: .write,
            outcome: .correct,
            at: TestFixture.now,
            responseSeconds: 8,
            paceContext: handwritingContext
        )
        let typedAt = TestFixture.now.addingTimeInterval(86_400)
        let slowTyped = TestFixture.attempt(
            number: 2,
            wordNumber: 1,
            mode: .write,
            outcome: .correct,
            at: typedAt,
            responseSeconds: 80,
            paceContext: keyboardContext
        )
        let untimedTyped = TestFixture.attempt(
            number: 3,
            wordNumber: 1,
            mode: .write,
            outcome: .correct,
            at: typedAt,
            responseSeconds: nil,
            paceContext: keyboardContext
        )

        let timedProgress = try WordProgressReducer().rebuild(
            profileID: TestFixture.profileID,
            wordPromptID: TestFixture.wordID(1),
            learningMode: .write,
            from: [handwriting, slowTyped]
        )
        let untimedProgress = try WordProgressReducer().rebuild(
            profileID: TestFixture.profileID,
            wordPromptID: TestFixture.wordID(1),
            learningMode: .write,
            from: [handwriting, untimedTyped]
        )

        XCTAssertEqual(timedProgress.firstIndependentAttemptCount, 2)
        XCTAssertEqual(timedProgress.firstIndependentCorrectCount, 2)
        XCTAssertEqual(timedProgress.firstIndependentTimedAttemptCount, 1)
        XCTAssertEqual(timedProgress.firstIndependentResponseTimeTotal.seconds, 8)
        XCTAssertEqual(timedProgress.firstIndependentMeanResponseTime?.seconds, 8)
        XCTAssertEqual(timedProgress.memoryState, untimedProgress.memoryState)
    }
}
