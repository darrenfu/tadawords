import Foundation
import TadaWordsDomain
import XCTest

@testable import TadaWordsContent
@testable import TadaWordsGuardianFeatures

final class RepositoryGuardianWordStoreLegacyAliasHarnessTests: XCTestCase {
    func testLegacyAttemptProjectsToCanonicalAttentionFrequencyAndReportWithoutRewrite()
        async throws
    {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(
                "TadaGuardianLegacyEvidence-\(UUID().uuidString)",
                isDirectory: true
            )
        try FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true
        )
        defer { try? FileManager.default.removeItem(at: directory) }
        let now = Date(timeIntervalSince1970: 2_179_100_000)
        let profile = KidProfile(
            displayName: "Mia",
            avatar: .cartoonAnimal(assetID: "hare"),
            selectedWorld: .moonpetalKingdom,
            createdAt: now.addingTimeInterval(-86_400)
        )
        let legacyPrompt = try WordPrompt(
            learningMode: .read,
            text: "spark"
        )
        let legacyEntry = WordPoolEntry(
            profileID: profile.id,
            prompt: legacyPrompt,
            addedAt: now.addingTimeInterval(-3_600),
            source: .guardianManual
        )
        let wordPoolURL = directory.appendingPathComponent("word-pool.json")
        let encoder = InspectableSnapshotJSONCodec.makeEncoder()
        try encoder.encode(
            WordPoolSnapshot(schemaVersion: 1, entries: [legacyEntry])
        ).write(to: wordPoolURL)
        let words = LocalJSONWordPoolRepository(snapshotURL: wordPoolURL)
        let migratedEntries = try await words.entries(
            for: profile.id,
            learningMode: .read,
            includingInactive: true
        )
        let canonicalEntry = try XCTUnwrap(migratedEntries.first)
        XCTAssertNotEqual(canonicalEntry.prompt.id, legacyPrompt.id)
        XCTAssertTrue(canonicalEntry.resolves(promptID: legacyPrompt.id))

        let learningURL = directory.appendingPathComponent("learning.json")
        let learning = LocalJSONLearningRecordRepository(
            snapshotURL: learningURL
        )
        let attempt = AttemptEvent(
            profileID: profile.id,
            wordPromptID: legacyPrompt.id,
            learningMode: .read,
            evidence: .firstIndependentAttempt,
            outcome: .incorrect,
            occurredAt: now.addingTimeInterval(-10_800)
        )
        try await learning.append(attempt)
        try await learning.registerPromptAliases([
            WordPromptAlias(
                profileID: profile.id,
                learningMode: .read,
                legacyPromptID: legacyPrompt.id,
                canonicalPromptID: canonicalEntry.prompt.id
            )
        ])
        try await learning.save(
            WordProgress(
                profileID: profile.id,
                wordPromptID: canonicalEntry.prompt.id,
                learningMode: .read,
                memoryState: MemoryState(
                    stabilityDays: 0.1,
                    difficulty: 0.8,
                    nextReviewAt: now.addingTimeInterval(-1),
                    lastIndependentAttemptAt: attempt.occurredAt,
                    lapseCount: 1
                ),
                firstIndependentAttemptCount: 1,
                firstIndependentCorrectCount: 0,
                lastEncounterAt: attempt.occurredAt
            )
        )
        let store = RepositoryGuardianWordStore(
            profile: profile,
            wordPoolRepository: words,
            practiceSettingsRepository: InMemoryPracticeSettingsRepository(),
            learningRecordRepository: learning,
            clock: LegacyAliasClock(now: now),
            timeZone: .gmt
        )

        let dashboard = try await store.dashboardSnapshot()
        let report = try await store.report(for: .thirtyDays)

        XCTAssertEqual(
            dashboard.needsAttention.map(\.prompt.id),
            [canonicalEntry.prompt.id]
        )
        XCTAssertEqual(dashboard.needsAttention.first?.reason, .reviewDue)
        XCTAssertEqual(
            dashboard.practiceFrequencyByWordID[canonicalEntry.prompt.id],
            1
        )
        XCTAssertNil(dashboard.practiceFrequencyByWordID[legacyPrompt.id])
        XCTAssertEqual(report.trend.currentIndependentAttemptCount, 1)
        XCTAssertEqual(report.words.map(\.prompt.id), [canonicalEntry.prompt.id])
        XCTAssertEqual(report.words.first?.independentAttemptCount, 1)
        XCTAssertEqual(report.words.first?.correctCount, 0)
        XCTAssertEqual(report.words.first?.recentAttempts.map(\.id), [attempt.id])

        let durable = try InspectableSnapshotJSONCodec.makeDecoder().decode(
            LearningRecordSnapshot.self,
            from: Data(contentsOf: learningURL)
        )
        XCTAssertEqual(
            durable.attempts.first?.wordPromptID,
            legacyPrompt.id,
            "Guardian projection must never rewrite immutable attempt facts."
        )
    }

    func testQueuedLegacyPromptIDStillDeactivatesMigratedMembership()
        async throws
    {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(
                "TadaGuardianLegacyAlias-\(UUID().uuidString)",
                isDirectory: true
            )
        try FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true
        )
        defer { try? FileManager.default.removeItem(at: directory) }
        let now = Date(timeIntervalSince1970: 2_179_000_000)
        let profile = KidProfile(
            displayName: "Mia",
            avatar: .cartoonAnimal(assetID: "hare"),
            selectedWorld: .moonpetalKingdom,
            createdAt: now
        )
        let legacyPrompt = try WordPrompt(
            learningMode: .read,
            text: "cat"
        )
        let legacyEntry = WordPoolEntry(
            profileID: profile.id,
            prompt: legacyPrompt,
            addedAt: now,
            source: .guardianManual
        )
        let snapshotURL = directory.appendingPathComponent("word-pool.json")
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .secondsSince1970
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(
            WordPoolSnapshot(schemaVersion: 1, entries: [legacyEntry])
        ).write(to: snapshotURL)
        let repository = LocalJSONWordPoolRepository(
            snapshotURL: snapshotURL
        )
        let store = RepositoryGuardianWordStore(
            profile: profile,
            wordPoolRepository: repository,
            practiceSettingsRepository: InMemoryPracticeSettingsRepository(),
            clock: LegacyAliasClock(now: now),
            timeZone: .gmt
        )

        let migratedEntries = try await repository.entries(
            for: profile.id,
            learningMode: .read,
            includingInactive: true
        )
        let migrated = try XCTUnwrap(migratedEntries.first)
        XCTAssertNotEqual(migrated.prompt.id, legacyPrompt.id)
        XCTAssertTrue(migrated.resolves(promptID: legacyPrompt.id))

        let snapshot = try await store.setWordsActive(
            ids: [legacyPrompt.id],
            learningMode: .read,
            isActive: false
        )

        XCTAssertTrue(snapshot.readPool.isEmpty)
        let persistedEntries = try await repository.entries(
            for: profile.id,
            learningMode: .read,
            includingInactive: true
        )
        let persisted = try XCTUnwrap(persistedEntries.first)
        XCTAssertEqual(persisted.id, migrated.id)
        XCTAssertFalse(persisted.isActive)
    }
}

private struct LegacyAliasClock: AppClock {
    let now: Date
}
