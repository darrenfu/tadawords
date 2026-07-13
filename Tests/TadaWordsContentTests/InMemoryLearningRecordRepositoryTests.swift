import Foundation
import TadaWordsContent
import TadaWordsDomain
import XCTest

final class InMemoryLearningRecordRepositoryTests: XCTestCase {
    func testInMemoryAndLocalAdaptersHaveMatchingRepositorySemantics()
        async throws
    {
        let snapshotURL = try makeSnapshotURL()
        let inMemory = InMemoryLearningRecordRepository()
        let local = LocalJSONLearningRecordRepository(snapshotURL: snapshotURL)

        let inMemoryResult = try await exercise(repository: inMemory)
        let localResult = try await exercise(repository: local)

        XCTAssertEqual(inMemoryResult, localResult)
    }

    func testIdenticalMutationsAreIdempotentAndConflictsStayTyped()
        async throws
    {
        let repository = InMemoryLearningRecordRepository()
        let event = attempt(outcome: .incorrect)
        let appendedCorrection = correction(
            attemptID: event.id,
            outcome: .correct
        )
        let savedProgress = progress(correctCount: 1)

        try await repository.append(event)
        try await repository.append(event)
        try await repository.append(appendedCorrection)
        try await repository.append(appendedCorrection)
        try await repository.save(savedProgress)
        try await repository.save(savedProgress)

        let attempts = try await repository.attempts(
            for: event.profileID,
            wordPromptID: event.wordPromptID
        )
        let corrections = try await repository.corrections(for: event.id)
        let storedProgress = try await repository.progress(
            for: savedProgress.profileID,
            wordPromptID: savedProgress.wordPromptID
        )
        XCTAssertEqual(attempts, [event])
        XCTAssertEqual(corrections, [appendedCorrection])
        XCTAssertEqual(storedProgress, savedProgress)

        let conflictingEvent = AttemptEvent(
            id: event.id,
            questID: event.questID,
            profileID: event.profileID,
            wordPromptID: event.wordPromptID,
            learningMode: event.learningMode,
            evidence: event.evidence,
            outcome: .correct,
            occurredAt: event.occurredAt
        )
        do {
            try await repository.append(conflictingEvent)
            XCTFail("Expected a conflicting attempt ID")
        } catch {
            XCTAssertEqual(
                error as? LearningRecordRepositoryError,
                .conflictingAttemptID(event.id)
            )
        }

        let conflictingCorrection = AttemptCorrectionEvent(
            id: appendedCorrection.id,
            originalAttemptID: appendedCorrection.originalAttemptID,
            correctedOutcome: .incorrect,
            reason: appendedCorrection.reason,
            correctedAt: appendedCorrection.correctedAt
        )
        do {
            try await repository.append(conflictingCorrection)
            XCTFail("Expected a conflicting correction ID")
        } catch {
            XCTAssertEqual(
                error as? LearningRecordRepositoryError,
                .conflictingCorrectionID(appendedCorrection.id)
            )
        }
    }

    private struct RepositoryResult: Equatable {
        let attempts: [AttemptEvent]
        let corrections: [AttemptCorrectionEvent]
        let progress: WordProgress?
    }

    private func exercise(
        repository: any AttemptEventRepository & WordProgressRepository
    ) async throws -> RepositoryResult {
        let late = attempt(
            number: 2,
            outcome: .incorrect,
            at: ContentTestFixture.day.addingTimeInterval(2)
        )
        let early = attempt(
            number: 1,
            outcome: .correct,
            at: ContentTestFixture.day.addingTimeInterval(1)
        )
        let appendedCorrection = correction(
            attemptID: late.id,
            outcome: .correct
        )
        let savedProgress = progress(correctCount: 2)

        try await repository.append(late)
        try await repository.append(early)
        try await repository.append(appendedCorrection)
        try await repository.save(savedProgress)

        return try await RepositoryResult(
            attempts: repository.attempts(
                for: ContentTestFixture.profileID,
                wordPromptID: ContentTestFixture.wordID(1)
            ),
            corrections: repository.corrections(for: late.id),
            progress: repository.progress(
                for: ContentTestFixture.profileID,
                wordPromptID: ContentTestFixture.wordID(1)
            )
        )
    }

    private func attempt(
        number: Int = 1,
        outcome: AttemptOutcome,
        at date: Date = ContentTestFixture.day
    ) -> AttemptEvent {
        AttemptEvent(
            id: AttemptID(rawValue: stableUUID(prefix: "81", number: number)),
            questID: QuestID(
                rawValue: stableUUID(prefix: "82", number: number)
            ),
            profileID: ContentTestFixture.profileID,
            wordPromptID: ContentTestFixture.wordID(1),
            learningMode: .read,
            evidence: .firstIndependentAttempt,
            outcome: outcome,
            occurredAt: date
        )
    }

    private func correction(
        attemptID: AttemptID,
        outcome: AttemptOutcome
    ) -> AttemptCorrectionEvent {
        AttemptCorrectionEvent(
            id: AttemptCorrectionID(
                rawValue: stableUUID(prefix: "83", number: 1)
            ),
            originalAttemptID: attemptID,
            correctedOutcome: outcome,
            reason: .guardianOverride,
            correctedAt: ContentTestFixture.day.addingTimeInterval(3)
        )
    }

    private func progress(correctCount: Int) -> WordProgress {
        WordProgress(
            profileID: ContentTestFixture.profileID,
            wordPromptID: ContentTestFixture.wordID(1),
            learningMode: .read,
            memoryState: MemoryState(
                stabilityDays: Double(correctCount),
                difficulty: 0.4,
                nextReviewAt: ContentTestFixture.day.addingTimeInterval(86_400),
                lastIndependentAttemptAt: ContentTestFixture.day,
                consecutiveIndependentSuccesses: correctCount,
                lapseCount: 0
            ),
            firstIndependentAttemptCount: max(1, correctCount),
            firstIndependentCorrectCount: correctCount,
            lastEncounterAt: ContentTestFixture.day
        )
    }

    private func stableUUID(prefix: String, number: Int) -> UUID {
        let suffix = String(format: "%012X", number)
        return UUID(
            uuidString: "\(prefix)000000-0000-0000-0000-\(suffix)"
        )!
    }

    private func makeSnapshotURL() throws -> URL {
        let directoryURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(
                "TadaWordsInMemoryLearningTests-\(UUID().uuidString)",
                isDirectory: true
            )
        try FileManager.default.createDirectory(
            at: directoryURL,
            withIntermediateDirectories: true
        )
        addTeardownBlock {
            try? FileManager.default.removeItem(at: directoryURL)
        }
        return directoryURL.appendingPathComponent("learning-records.json")
    }
}
