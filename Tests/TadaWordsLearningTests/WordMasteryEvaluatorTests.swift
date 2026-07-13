import Foundation
import TadaWordsDomain
import XCTest

@testable import TadaWordsLearning

final class WordMasteryEvaluatorTests: XCTestCase {
    private let utc = TimeZone(secondsFromGMT: 0)!

    func testOneSuccessIsLearningEvenWithStrongMemory() {
        let progress = makeProgress(successDayOffsets: [0], stabilityDays: 100)

        XCTAssertEqual(
            WordMasteryEvaluator().status(
                for: progress,
                asOf: TestFixture.now,
                timeZone: utc
            ),
            .learning
        )
    }

    func testThreeSuccessesOnSameDayDoNotSatisfyCrossDayRule() {
        let progress = makeProgress(
            successDayOffsets: [0, 0, 0],
            stabilityDays: 100
        )

        XCTAssertEqual(
            WordMasteryEvaluator().status(
                for: progress,
                asOf: TestFixture.now,
                timeZone: utc
            ),
            .learning
        )
    }

    func testThreeCrossDaySuccessesStillNeedFourteenDayRecall() {
        let weak = makeProgress(successDayOffsets: [-2, -1, 0], stabilityDays: 3)
        let strong = makeProgress(successDayOffsets: [-2, -1, 0], stabilityDays: 100)

        XCTAssertEqual(
            WordMasteryEvaluator().status(
                for: weak,
                asOf: TestFixture.now,
                timeZone: utc
            ),
            .learning
        )
        XCTAssertEqual(
            WordMasteryEvaluator().status(
                for: strong,
                asOf: TestFixture.now,
                timeZone: utc
            ),
            .mastered
        )
    }

    private func makeProgress(
        successDayOffsets: [Int],
        stabilityDays: Double
    ) -> WordProgress {
        WordProgress(
            profileID: TestFixture.profileID,
            wordPromptID: TestFixture.wordID(1),
            learningMode: .read,
            memoryState: MemoryState(
                stabilityDays: stabilityDays,
                difficulty: 0.2,
                nextReviewAt: nil,
                lastIndependentAttemptAt: TestFixture.now,
                consecutiveIndependentSuccesses: successDayOffsets.count,
                lapseCount: 0
            ),
            firstIndependentAttemptCount: successDayOffsets.count,
            firstIndependentCorrectCount: successDayOffsets.count,
            independentSuccessDates: successDayOffsets.map {
                TestFixture.now.addingTimeInterval(TimeInterval($0) * 86_400)
            }
        )
    }
}
