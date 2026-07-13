import TadaWordsDomain
import XCTest

@testable import TadaWordsLearning

final class AdaptiveRetrievalSchedulerTests: XCTestCase {
    func testRetriesStudyAndTechnicalEvidenceDoNotUpdateMemory() {
        let initial = MemoryState(
            stabilityDays: 2,
            difficulty: 0.5,
            nextReviewAt: TestFixture.now,
            lastIndependentAttemptAt: nil,
            consecutiveIndependentSuccesses: 1,
            lapseCount: 0
        )
        let excluded: [(EncounterEvidence, AttemptOutcome)] = [
            (.studyExposed, .correct),
            (.unaidedRetry, .correct),
            (.guidedRetry, .correct),
            (.technicalRetry, .technicalFailure(.noUsableAudio)),
            (.recognitionUncertain, .recognitionUncertain),
        ]

        for (index, item) in excluded.enumerated() {
            let attempt = TestFixture.attempt(
                number: index + 1,
                wordNumber: 1,
                evidence: item.0,
                outcome: item.1
            )
            XCTAssertEqual(
                AdaptiveRetrievalScheduler().updatedMemoryState(
                    from: initial,
                    using: attempt
                ),
                initial
            )
        }
    }

    func testFirstSuccessStartsOneDayStability() throws {
        let attempt = TestFixture.attempt(
            number: 1,
            wordNumber: 1,
            outcome: .correct
        )

        let state = AdaptiveRetrievalScheduler().updatedMemoryState(
            from: .unstarted,
            using: attempt
        )

        XCTAssertEqual(state.stabilityDays, 1, accuracy: 0.0001)
        XCTAssertEqual(state.difficulty, 0.46, accuracy: 0.0001)
        XCTAssertEqual(state.consecutiveIndependentSuccesses, 1)
        XCTAssertEqual(state.lapseCount, 0)
        let expectedInterval = -log(0.80) * 86_400
        XCTAssertEqual(
            state.nextReviewAt?.timeIntervalSince(TestFixture.now) ?? -1,
            expectedInterval,
            accuracy: 0.0001
        )
        XCTAssertEqual(
            state.predictedRecall(at: try XCTUnwrap(state.nextReviewAt)),
            0.80,
            accuracy: 0.000_001
        )
    }

    func testLapseShortensIntervalAndIncreasesDifficulty() {
        let current = MemoryState(
            stabilityDays: 10,
            difficulty: 0.4,
            nextReviewAt: TestFixture.now,
            lastIndependentAttemptAt: TestFixture.now.addingTimeInterval(-86_400),
            consecutiveIndependentSuccesses: 4,
            lapseCount: 2
        )
        let attempt = TestFixture.attempt(
            number: 1,
            wordNumber: 1,
            outcome: .incorrect
        )

        let state = AdaptiveRetrievalScheduler().updatedMemoryState(
            from: current,
            using: attempt
        )

        XCTAssertEqual(state.stabilityDays, 1, accuracy: 0.0001)
        XCTAssertEqual(state.difficulty, 0.5, accuracy: 0.0001)
        XCTAssertEqual(state.consecutiveIndependentSuccesses, 0)
        XCTAssertEqual(state.lapseCount, 3)
        XCTAssertEqual(
            state.nextReviewAt?.timeIntervalSince(TestFixture.now) ?? -1,
            -log(0.80) * 86_400,
            accuracy: 0.0001
        )
    }

    func testPredictedRecallUsesExactEbbinghausEquation() {
        let state = MemoryState(
            stabilityDays: 2,
            lastIndependentAttemptAt: TestFixture.now
        )

        XCTAssertEqual(state.predictedRecall(at: TestFixture.now), 1, accuracy: 0.000_001)
        XCTAssertEqual(
            state.predictedRecall(
                at: TestFixture.now.addingTimeInterval(86_400)
            ),
            exp(-0.5),
            accuracy: 0.000_001
        )
        XCTAssertEqual(
            MemoryState.unstarted.predictedRecall(at: TestFixture.now),
            0
        )
    }

    func testTargetRecallThresholdTransparentlyDeterminesDueDate() throws {
        let scheduler = AdaptiveRetrievalScheduler(
            policy: AdaptiveRetrievalPolicy(targetRecallThreshold: 0.50)
        )
        let attempt = TestFixture.attempt(
            number: 1,
            wordNumber: 1,
            outcome: .correct
        )

        let state = scheduler.updatedMemoryState(from: .unstarted, using: attempt)

        XCTAssertEqual(scheduler.policy.targetRecallThreshold, 0.50)
        XCTAssertEqual(
            state.nextReviewAt?.timeIntervalSince(TestFixture.now) ?? -1,
            log(2) * 86_400,
            accuracy: 0.0001
        )
        XCTAssertEqual(
            state.predictedRecall(at: try XCTUnwrap(state.nextReviewAt)),
            0.50,
            accuracy: 0.000_001
        )
    }

    func testReplayMakesCorrectRecallMoreConservative() {
        let fast = TestFixture.attempt(
            number: 1,
            wordNumber: 1,
            outcome: .correct,
            responseSeconds: 1,
            replayCount: 0
        )
        let slow = TestFixture.attempt(
            number: 2,
            wordNumber: 1,
            outcome: .correct,
            responseSeconds: 30,
            replayCount: 8
        )

        let scheduler = AdaptiveRetrievalScheduler()
        let withoutReplay = scheduler.updatedMemoryState(from: .unstarted, using: fast)
        let withReplay = scheduler.updatedMemoryState(from: .unstarted, using: slow)

        XCTAssertLessThan(withReplay.stabilityDays, withoutReplay.stabilityDays)
        XCTAssertGreaterThan(withReplay.difficulty, withoutReplay.difficulty)
    }

    func testHelpWeakensMemoryWithoutPretendingAnIndependentAttemptOccurred() {
        let initial = MemoryState(
            stabilityDays: 10,
            difficulty: 0.3,
            nextReviewAt: TestFixture.now.addingTimeInterval(86_400),
            lastIndependentAttemptAt: TestFixture.now,
            consecutiveIndependentSuccesses: 4,
            lapseCount: 0
        )
        let help = TestFixture.attempt(
            number: 1,
            wordNumber: 1,
            evidence: .helped,
            outcome: .skipped,
            at: TestFixture.now.addingTimeInterval(10),
            responseSeconds: nil
        )

        let updated = AdaptiveRetrievalScheduler().updatedMemoryState(
            from: initial,
            using: help
        )

        XCTAssertLessThan(updated.stabilityDays, initial.stabilityDays)
        XCTAssertGreaterThan(updated.difficulty, initial.difficulty)
        XCTAssertEqual(updated.lastIndependentAttemptAt, initial.lastIndependentAttemptAt)
        XCTAssertEqual(updated.consecutiveIndependentSuccesses, 0)
    }

    func testSlowResponseIsJudgedAgainstComparableChildHistory() {
        let attempt = TestFixture.attempt(
            number: 1,
            wordNumber: 1,
            outcome: .correct,
            responseSeconds: 8
        )
        let scheduler = AdaptiveRetrievalScheduler()
        let ordinary = scheduler.updatedMemoryState(
            from: .unstarted,
            using: EffectiveAttempt(
                original: attempt,
                outcome: .correct,
                appliedCorrection: nil
            ),
            signalContext: RetrievalSignalContext(
                comparableMeanResponseTime: ElapsedTime(seconds: 8)
            )
        )
        let relativelySlow = scheduler.updatedMemoryState(
            from: .unstarted,
            using: EffectiveAttempt(
                original: attempt,
                outcome: .correct,
                appliedCorrection: nil
            ),
            signalContext: RetrievalSignalContext(
                comparableMeanResponseTime: ElapsedTime(seconds: 2)
            )
        )

        XCTAssertLessThan(relativelySlow.stabilityDays, ordinary.stabilityDays)
        XCTAssertGreaterThan(relativelySlow.difficulty, ordinary.difficulty)
    }
}
