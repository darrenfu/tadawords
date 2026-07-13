import Foundation
import TadaWordsDomain
import XCTest

@testable import TadaWordsFeatures

final class PersistedQuestRecoveryTests: XCTestCase {
    func testTechnicalMoveOnNeedsAllThreePersistedEvents() throws {
        let fixture = try Fixture()
        let partial = (0..<2).map { fixture.technicalAttempt(number: $0 + 1) }
        let complete = partial + [fixture.technicalAttempt(number: 3)]

        let partialRecovery = try PersistedQuestRecoveryResolver().resolve(
            plan: fixture.plan,
            attempts: partial
        )
        let completeRecovery = try PersistedQuestRecoveryResolver().resolve(
            plan: fixture.plan,
            attempts: complete
        )

        XCTAssertEqual(partialRecovery.nextItemIndex, 0)
        XCTAssertTrue(partialRecovery.completedWordIDs.isEmpty)
        XCTAssertEqual(completeRecovery.nextItemIndex, 1)
        XCTAssertEqual(completeRecovery.completedWordIDs, [fixture.prompt.id])
    }

    func testLaterWordEvidenceAfterIncompletePrefixFailsClosed() throws {
        let fixture = try Fixture(wordCount: 2)
        let laterWordAttempt = fixture.correctAttempt(
            number: 1,
            prompt: fixture.prompts[1]
        )

        XCTAssertThrowsError(
            try PersistedQuestRecoveryResolver().resolve(
                plan: fixture.plan,
                attempts: [laterWordAttempt]
            )
        ) { error in
            XCTAssertEqual(
                error as? PersistedQuestRecoveryError,
                .inconsistentEvidence
            )
        }
    }

    func testWriteTwoIncorrectSubmissionsAreATerminalCheckpoint() throws {
        let fixture = try Fixture(mode: .write)
        let attempts = [
            fixture.incorrectAttempt(number: 1, evidence: .firstIndependentAttempt),
            fixture.feedbackExposure(number: 2),
            fixture.incorrectAttempt(number: 3, evidence: .guidedRetry),
        ]

        let recovery = try PersistedQuestRecoveryResolver().resolve(
            plan: fixture.plan,
            attempts: attempts
        )

        XCTAssertEqual(recovery.nextItemIndex, 1)
    }

    func testWriteSecondUncertainSubmissionIsATerminalCheckpoint() throws {
        let fixture = try Fixture(mode: .write)
        let attempts = [
            fixture.uncertainAttempt(number: 1),
            fixture.feedbackExposure(number: 2),
            fixture.uncertainAttempt(number: 3),
        ]

        let recovery = try PersistedQuestRecoveryResolver().resolve(
            plan: fixture.plan,
            attempts: attempts
        )

        XCTAssertEqual(recovery.nextItemIndex, 1)
    }

    private struct Fixture {
        let profileID = ProfileID(
            rawValue: UUID(uuidString: "91000000-0000-0000-0000-000000000001")!
        )
        let questID = QuestID(
            rawValue: UUID(uuidString: "92000000-0000-0000-0000-000000000001")!
        )
        let prompts: [WordPrompt]
        let plan: QuestPlan

        var prompt: WordPrompt { prompts[0] }

        init(wordCount: Int = 1, mode: LearningMode = .read) throws {
            prompts = try (1...wordCount).map { number in
                try WordPrompt(
                    id: WordPromptID(
                        rawValue: UUID(
                            uuidString: String(
                                format:
                                    "93000000-0000-0000-0000-%012X",
                                number
                            )
                        )!
                    ),
                    learningMode: mode,
                    text: number == 1 ? "cat" : "dog"
                )
            }
            plan = QuestPlan(
                id: questID,
                profileID: profileID,
                configuration: mode == .read ? .defaultRead : .defaultWrite,
                reviewWordIDs: [],
                newWordIDs: prompts.map(\.id),
                createdAt: Date(timeIntervalSince1970: 100)
            )
        }

        func technicalAttempt(number: Int) -> AttemptEvent {
            AttemptEvent(
                id: attemptID(number),
                questID: questID,
                profileID: profileID,
                wordPromptID: prompt.id,
                learningMode: .read,
                evidence: .technicalRetry,
                outcome: .technicalFailure(.serviceUnavailable),
                occurredAt: Date(timeIntervalSince1970: TimeInterval(number))
            )
        }

        func correctAttempt(number: Int, prompt: WordPrompt) -> AttemptEvent {
            AttemptEvent(
                id: attemptID(number),
                questID: questID,
                profileID: profileID,
                wordPromptID: prompt.id,
                learningMode: .read,
                evidence: .firstIndependentAttempt,
                outcome: .correct,
                occurredAt: Date(timeIntervalSince1970: TimeInterval(number))
            )
        }

        func incorrectAttempt(
            number: Int,
            evidence: EncounterEvidence
        ) -> AttemptEvent {
            AttemptEvent(
                id: attemptID(number),
                questID: questID,
                profileID: profileID,
                wordPromptID: prompt.id,
                learningMode: prompt.learningMode,
                evidence: evidence,
                outcome: .incorrect,
                occurredAt: Date(timeIntervalSince1970: TimeInterval(number))
            )
        }

        func uncertainAttempt(number: Int) -> AttemptEvent {
            AttemptEvent(
                id: attemptID(number),
                questID: questID,
                profileID: profileID,
                wordPromptID: prompt.id,
                learningMode: prompt.learningMode,
                evidence: .recognitionUncertain,
                outcome: .recognitionUncertain,
                occurredAt: Date(timeIntervalSince1970: TimeInterval(number))
            )
        }

        func feedbackExposure(number: Int) -> AttemptEvent {
            AttemptEvent(
                id: attemptID(number),
                questID: questID,
                profileID: profileID,
                wordPromptID: prompt.id,
                learningMode: prompt.learningMode,
                evidence: .feedbackExposed,
                outcome: .skipped,
                occurredAt: Date(timeIntervalSince1970: TimeInterval(number))
            )
        }

        private func attemptID(_ number: Int) -> AttemptID {
            AttemptID(
                rawValue: UUID(
                    uuidString: String(
                        format: "94000000-0000-0000-0000-%012X",
                        number
                    )
                )!
            )
        }
    }
}
