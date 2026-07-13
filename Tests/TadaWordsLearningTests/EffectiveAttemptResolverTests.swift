import TadaWordsDomain
import XCTest

@testable import TadaWordsLearning

final class EffectiveAttemptResolverTests: XCTestCase {
    func testLatestCorrectionWinsWithDeterministicIdentifierTieBreak() {
        let original = TestFixture.attempt(
            number: 1,
            wordNumber: 1,
            outcome: .incorrect
        )
        let lowIDCorrection = AttemptCorrectionEvent(
            id: TestFixture.correctionID(1),
            originalAttemptID: original.id,
            correctedOutcome: .incorrect,
            reason: .guardianOverride,
            correctedAt: TestFixture.now.addingTimeInterval(10)
        )
        let highIDCorrection = AttemptCorrectionEvent(
            id: TestFixture.correctionID(2),
            originalAttemptID: original.id,
            correctedOutcome: .correct,
            reason: .guardianOverride,
            correctedAt: TestFixture.now.addingTimeInterval(10)
        )

        let effective = EffectiveAttemptResolver().resolve(
            original,
            corrections: [highIDCorrection, lowIDCorrection]
        )

        XCTAssertEqual(effective.outcome, .correct)
        XCTAssertEqual(effective.appliedCorrection?.id, highIDCorrection.id)
        XCTAssertEqual(original.outcome, .incorrect)
    }

    func testProgressRebuildUsesCorrectionWithoutMutatingAttempt() throws {
        let original = TestFixture.attempt(
            number: 1,
            wordNumber: 1,
            outcome: .incorrect
        )
        let correction = AttemptCorrectionEvent(
            originalAttemptID: original.id,
            correctedOutcome: .correct,
            reason: .guardianOverride,
            correctedAt: TestFixture.now.addingTimeInterval(1)
        )

        let progress = try WordProgressReducer().rebuild(
            profileID: TestFixture.profileID,
            wordPromptID: TestFixture.wordID(1),
            learningMode: .read,
            from: [original, original],
            corrections: [correction]
        )

        XCTAssertEqual(progress.firstIndependentAttemptCount, 1)
        XCTAssertEqual(progress.firstIndependentCorrectCount, 1)
        XCTAssertEqual(progress.memoryState.consecutiveIndependentSuccesses, 1)
        XCTAssertEqual(progress.memoryState.lapseCount, 0)
        XCTAssertEqual(original.outcome, .incorrect)
    }

    func testTechnicalCorrectionDoesNotChangeTechnicalEvidenceIntoMastery() throws {
        let technical = TestFixture.attempt(
            number: 1,
            wordNumber: 1,
            evidence: .technicalRetry,
            outcome: .technicalFailure(.noUsableAudio)
        )
        let correction = AttemptCorrectionEvent(
            originalAttemptID: technical.id,
            correctedOutcome: .correct,
            reason: .guardianOverride,
            correctedAt: TestFixture.now.addingTimeInterval(1)
        )

        let progress = try WordProgressReducer().rebuild(
            profileID: TestFixture.profileID,
            wordPromptID: TestFixture.wordID(1),
            learningMode: .read,
            from: [technical],
            corrections: [correction]
        )

        XCTAssertEqual(progress.firstIndependentAttemptCount, 0)
        XCTAssertEqual(progress.memoryState, .unstarted)
        XCTAssertEqual(progress.lastEncounterAt, technical.occurredAt)
    }
}
