import Foundation
import TadaWordsDomain
import XCTest

@testable import TadaWordsGuardianFeatures

final class GuardianAttentionEvaluatorTests: XCTestCase {
    func testOrdersRealEvidenceByReasonAndSeverityAndCapsAtFive() throws {
        let profileID = ProfileID(rawValue: stableUUID(number: 1))
        let prompts = try (1...6).map { number in
            try WordPrompt(
                id: WordPromptID(rawValue: stableUUID(number: 100 + number)),
                learningMode: number > 4 ? .write : .read,
                text: "word\(letter(for: number))"
            )
        }
        let progress = [
            makeProgress(
                prompt: prompts[0],
                profileID: profileID,
                dueAt: now.addingTimeInterval(-3 * 86_400),
                attempts: 1,
                correct: 1
            ),
            makeProgress(
                prompt: prompts[1],
                profileID: profileID,
                dueAt: now.addingTimeInterval(-300),
                attempts: 1,
                correct: 1
            ),
            makeProgress(prompt: prompts[2], profileID: profileID, attempts: 4, correct: 1),
            makeProgress(prompt: prompts[3], profileID: profileID, attempts: 3, correct: 1),
            makeProgress(
                prompt: prompts[4],
                profileID: profileID,
                attempts: 2,
                correct: 2,
                totalSeconds: 40,
                timedAttempts: 2
            ),
            makeProgress(
                prompt: prompts[5],
                profileID: profileID,
                attempts: 2,
                correct: 2,
                totalSeconds: 30,
                timedAttempts: 2
            ),
        ]
        let attempts = prompts.enumerated().map { index, prompt in
            AttemptEvent(
                profileID: profileID,
                wordPromptID: prompt.id,
                learningMode: prompt.learningMode,
                evidence: .firstIndependentAttempt,
                outcome: .correct,
                occurredAt: now.addingTimeInterval(TimeInterval(index))
            )
        }

        let items = GuardianAttentionEvaluator().evaluate(
            activePrompts: prompts,
            progress: progress,
            attempts: attempts,
            profileID: profileID,
            now: now
        )

        XCTAssertEqual(items.count, 4)
        XCTAssertEqual(items.map(\.prompt.id), Array(prompts.prefix(4).map(\.id)))
        XCTAssertEqual(
            items.map(\.reason),
            [.reviewDue, .reviewDue, .missedOften, .missedOften]
        )
        XCTAssertEqual(items[0].whyNow, "Review is 3 days overdue.")
        XCTAssertEqual(items[2].whyNow, "Missed 3 of 4 first tries.")
    }

    func testSlowWarningUsesChildsComparablePersonalPaceBand() throws {
        let profileID = ProfileID(rawValue: stableUUID(number: 10))
        let baselinePrompt = try WordPrompt(
            id: WordPromptID(rawValue: stableUUID(number: 201)),
            learningMode: .read,
            text: "cat"
        )
        let slowPrompt = try WordPrompt(
            id: WordPromptID(rawValue: stableUUID(number: 202)),
            learningMode: .read,
            text: "dog"
        )
        let context = PaceContext(
            learningMode: .read,
            deviceClass: .tablet,
            inputMethod: .speech,
            wordLength: 3
        )
        let attempts =
            [2.0, 2.1, 2.2].enumerated().map { index, seconds in
                AttemptEvent(
                    profileID: profileID,
                    wordPromptID: baselinePrompt.id,
                    learningMode: .read,
                    evidence: .firstIndependentAttempt,
                    outcome: .correct,
                    timing: AttemptTiming(speechOnsetLatency: ElapsedTime(seconds: seconds)),
                    occurredAt: now.addingTimeInterval(TimeInterval(index)),
                    paceContext: context
                )
            }
            + [6.0, 6.4].enumerated().map { index, seconds in
                AttemptEvent(
                    profileID: profileID,
                    wordPromptID: slowPrompt.id,
                    learningMode: .read,
                    evidence: .firstIndependentAttempt,
                    outcome: .correct,
                    timing: AttemptTiming(speechOnsetLatency: ElapsedTime(seconds: seconds)),
                    occurredAt: now.addingTimeInterval(TimeInterval(10 + index)),
                    paceContext: context
                )
            }
        let progress = makeProgress(
            prompt: slowPrompt,
            profileID: profileID,
            attempts: 2,
            correct: 2,
            totalSeconds: 12.4,
            timedAttempts: 2
        )

        let items = GuardianAttentionEvaluator().evaluate(
            activePrompts: [slowPrompt],
            progress: [progress],
            attempts: attempts,
            profileID: profileID,
            now: now
        )

        XCTAssertEqual(items.map(\.reason), [.takingExtraTime])
        XCTAssertTrue(items[0].whyNow.contains("personal comfort range"))
    }

    func testIgnoresAnotherProfilesProgressAndAttempts() throws {
        let selectedProfileID = ProfileID(rawValue: stableUUID(number: 1))
        let otherProfileID = ProfileID(rawValue: stableUUID(number: 2))
        let prompt = try WordPrompt(
            id: WordPromptID(rawValue: stableUUID(number: 101)),
            learningMode: .read,
            text: "cat"
        )
        let otherProgress = makeProgress(
            prompt: prompt,
            profileID: otherProfileID,
            dueAt: now.addingTimeInterval(-86_400),
            attempts: 3,
            correct: 0
        )
        let otherAttempt = AttemptEvent(
            profileID: otherProfileID,
            wordPromptID: prompt.id,
            learningMode: .read,
            evidence: .firstIndependentAttempt,
            outcome: .incorrect,
            occurredAt: now
        )

        let items = GuardianAttentionEvaluator().evaluate(
            activePrompts: [prompt],
            progress: [otherProgress],
            attempts: [otherAttempt],
            profileID: selectedProfileID,
            now: now
        )

        XCTAssertTrue(items.isEmpty)
    }

    private let now = Date(timeIntervalSince1970: 2_000_000_000)

    private func makeProgress(
        prompt: WordPrompt,
        profileID: ProfileID,
        dueAt: Date? = nil,
        attempts: Int,
        correct: Int,
        totalSeconds: TimeInterval = 0,
        timedAttempts: Int = 0
    ) -> WordProgress {
        WordProgress(
            profileID: profileID,
            wordPromptID: prompt.id,
            learningMode: prompt.learningMode,
            memoryState: MemoryState(
                stabilityDays: 1,
                nextReviewAt: dueAt,
                lastIndependentAttemptAt: now.addingTimeInterval(-86_400)
            ),
            firstIndependentAttemptCount: attempts,
            firstIndependentCorrectCount: correct,
            firstIndependentResponseTimeTotal: ElapsedTime(seconds: totalSeconds),
            firstIndependentTimedAttemptCount: timedAttempts,
            lastEncounterAt: now
        )
    }

    private func letter(for number: Int) -> String {
        String(UnicodeScalar(96 + number)!)
    }

    private func stableUUID(number: Int) -> UUID {
        UUID(
            uuidString: String(
                format: "A1000000-0000-0000-0000-%012X",
                number
            )
        )!
    }
}
