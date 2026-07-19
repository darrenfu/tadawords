import Foundation
import TadaWordsDomain
import XCTest

@testable import TadaWordsContent

final class RepositoryFamilySyncPromptAliasMigrationHarnessTests: XCTestCase {
    func testV1RandomPromptMigrationRetainsHistoryUnderCanonicalPromptAfterRestart()
        async throws
    {
        let fixture = try PromptAliasMigrationHarnessFixture(name: "local")
        defer { fixture.remove() }
        try await fixture.seedLegacyLocalState()

        let firstWords = LocalJSONWordPoolRepository(
            snapshotURL: fixture.wordPoolURL
        )
        let firstLearning = LocalJSONLearningRecordRepository(
            snapshotURL: fixture.learningURL
        )
        let firstStore = fixture.store(
            words: firstWords,
            learning: firstLearning,
            deviceID: "device-a"
        )

        _ = try await firstStore.records(for: fixture.profile.id)

        let restartedWords = LocalJSONWordPoolRepository(
            snapshotURL: fixture.wordPoolURL
        )
        let restartedEntries = try await restartedWords.entries(
            for: fixture.profile.id,
            learningMode: .read,
            includingInactive: true
        )
        let migratedEntry = try XCTUnwrap(restartedEntries.first)
        XCTAssertEqual(migratedEntry.prompt.id, fixture.canonicalPromptID)
        XCTAssertTrue(migratedEntry.legacyPromptIDs.contains(fixture.legacyPromptID))

        let restartedLearning = LocalJSONLearningRecordRepository(
            snapshotURL: fixture.learningURL
        )
        let attempts = try await restartedLearning.attempts(
            for: fixture.profile.id,
            wordPromptID: fixture.canonicalPromptID
        )
        let progress = try await restartedLearning.progress(
            for: fixture.profile.id,
            wordPromptID: fixture.canonicalPromptID
        )

        XCTAssertEqual(
            attempts.map(\.id),
            [fixture.attempt.id],
            "Migrating a pool ID must not reset immutable attempt history"
        )
        XCTAssertEqual(progress?.wordPromptID, fixture.canonicalPromptID)
        XCTAssertEqual(progress?.firstIndependentAttemptCount, 1)
        XCTAssertEqual(progress?.firstIndependentCorrectCount, 1)
    }

    func testRemoteLegacyAttemptProjectsUnderCanonicalPromptUsingSyncedAlias()
        async throws
    {
        let source = try PromptAliasMigrationHarnessFixture(name: "source")
        let target = try PromptAliasMigrationHarnessFixture(
            name: "target",
            profile: source.profile,
            legacyPromptID: source.legacyPromptID,
            legacyEntryID: source.legacyEntryID
        )
        defer {
            source.remove()
            target.remove()
        }
        try await source.seedLegacyLocalState()
        try await target.profiles.save(source.profile)

        let sourceStore = source.store(
            words: LocalJSONWordPoolRepository(snapshotURL: source.wordPoolURL),
            learning: LocalJSONLearningRecordRepository(
                snapshotURL: source.learningURL
            ),
            deviceID: "source-device"
        )
        let sourceRecords = try await sourceStore.records(for: source.profile.id)
        let wordRecord = try XCTUnwrap(
            sourceRecords.first { $0.kind == .wordPoolEntry }
        )
        let oldAttemptRecord = try source.oldAttemptRecord()

        var targetWords = LocalJSONWordPoolRepository(
            snapshotURL: target.wordPoolURL
        )
        var targetLearning = LocalJSONLearningRecordRepository(
            snapshotURL: target.learningURL
        )
        var targetStore = target.store(
            words: targetWords,
            learning: targetLearning,
            deviceID: "target-device"
        )
        try await targetStore.validate([wordRecord], for: target.profile.id)
        try await targetStore.apply([wordRecord], for: target.profile.id)

        targetWords = LocalJSONWordPoolRepository(snapshotURL: target.wordPoolURL)
        targetLearning = LocalJSONLearningRecordRepository(
            snapshotURL: target.learningURL
        )
        targetStore = target.store(
            words: targetWords,
            learning: targetLearning,
            deviceID: "target-after-restart"
        )
        try await targetStore.validate([oldAttemptRecord], for: target.profile.id)
        try await targetStore.apply([oldAttemptRecord], for: target.profile.id)

        let targetEntries = try await targetWords.entries(
            for: target.profile.id,
            learningMode: .read,
            includingInactive: true
        )
        let targetEntry = try XCTUnwrap(targetEntries.first)
        XCTAssertTrue(
            targetEntry.legacyPromptIDs.contains(source.legacyPromptID),
            "The old prompt alias is synchronized as part of the canonical word membership"
        )

        let canonicalAttempts = try await targetLearning.attempts(
            for: target.profile.id,
            wordPromptID: source.canonicalPromptID
        )
        let canonicalProgress = try await targetLearning.progress(
            for: target.profile.id,
            wordPromptID: source.canonicalPromptID
        )
        XCTAssertEqual(canonicalAttempts.map(\.id), [source.attempt.id])
        XCTAssertEqual(canonicalProgress?.wordPromptID, source.canonicalPromptID)
        XCTAssertEqual(canonicalProgress?.firstIndependentCorrectCount, 1)
    }

    func testLegacyAttemptAndCanonicalAliasConvergeForEveryArrivalOrderAcrossRestart()
        async throws
    {
        let source = try PromptAliasMigrationHarnessFixture(name: "permutation-source")
        defer { source.remove() }
        try await source.seedLegacyLocalState()
        let sourceStore = source.store(
            words: LocalJSONWordPoolRepository(snapshotURL: source.wordPoolURL),
            learning: LocalJSONLearningRecordRepository(
                snapshotURL: source.learningURL
            ),
            deviceID: "source-device"
        )
        let sourceRecords = try await sourceStore.records(for: source.profile.id)
        let wordRecord = try XCTUnwrap(
            sourceRecords.first { $0.kind == .wordPoolEntry }
        )
        let attemptRecord = try source.oldAttemptRecord()
        let arrivalBatches: [[[FamilySyncRecord]]] = [
            [[wordRecord], [attemptRecord]],
            [[attemptRecord], [wordRecord]],
            [[wordRecord, attemptRecord]],
            [[attemptRecord, wordRecord]],
        ]
        var baselineLearningBytes: Data?

        for (index, batches) in arrivalBatches.enumerated() {
            let target = try PromptAliasMigrationHarnessFixture(
                name: "permutation-target-\(index)",
                profile: source.profile,
                legacyPromptID: source.legacyPromptID,
                legacyEntryID: source.legacyEntryID
            )
            defer { target.remove() }
            try await target.profiles.save(source.profile)

            for batch in batches {
                let words = LocalJSONWordPoolRepository(
                    snapshotURL: target.wordPoolURL
                )
                let learning = LocalJSONLearningRecordRepository(
                    snapshotURL: target.learningURL
                )
                let store = target.store(
                    words: words,
                    learning: learning,
                    deviceID: "target-device"
                )
                try await store.validate(batch, for: target.profile.id)
                try await store.apply(batch, for: target.profile.id)
            }

            let restartedLearning = LocalJSONLearningRecordRepository(
                snapshotURL: target.learningURL
            )
            let attempts = try await restartedLearning.attempts(
                for: target.profile.id,
                wordPromptID: source.canonicalPromptID
            )
            let progress = try await restartedLearning.progress(
                for: target.profile.id,
                wordPromptID: source.canonicalPromptID
            )
            XCTAssertEqual(
                attempts.map(\.id),
                [source.attempt.id],
                "Permutation \(index) lost the old immutable attempt"
            )
            XCTAssertEqual(progress?.firstIndependentAttemptCount, 1)
            XCTAssertEqual(progress?.firstIndependentCorrectCount, 1)
            let learningBytes = try Data(contentsOf: target.learningURL)
            if let baselineLearningBytes {
                XCTAssertEqual(
                    learningBytes,
                    baselineLearningBytes,
                    "Alias/attempt delivery order must converge to one canonical durable projection"
                )
            } else {
                baselineLearningBytes = learningBytes
            }
        }
    }
}

private struct PromptAliasMigrationHarnessFixture {
    let directory: URL
    let wordPoolURL: URL
    let learningURL: URL
    let now = Date(timeIntervalSince1970: 2_171_000_000)
    let profile: KidProfile
    let legacyPromptID: WordPromptID
    let legacyEntryID: WordPoolEntryID
    let legacyEntry: WordPoolEntry
    let attempt: AttemptEvent
    let profiles = InMemoryKidProfileRepository()
    let settings: LocalJSONPracticeSettingsRepository
    let daily: LocalJSONDailyQuestRepository
    let tombstones = InMemoryProfileDeletionTombstoneRepository()

    init(
        name: String,
        profile: KidProfile? = nil,
        legacyPromptID: WordPromptID = WordPromptID(),
        legacyEntryID: WordPoolEntryID = WordPoolEntryID()
    ) throws {
        directory = FileManager.default.temporaryDirectory.appendingPathComponent(
            "TadaPromptAliasHarness-\(name)-\(UUID().uuidString)",
            isDirectory: true
        )
        try FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true
        )
        wordPoolURL = directory.appendingPathComponent("word-pool.json")
        learningURL = directory.appendingPathComponent("learning.json")
        let resolvedProfile =
            profile
            ?? KidProfile(
                displayName: "Alias Kid",
                avatar: .cartoonAnimal(assetID: "fox"),
                selectedWorld: .moonpetalKingdom,
                createdAt: now
            )
        self.profile = resolvedProfile
        self.legacyPromptID = legacyPromptID
        self.legacyEntryID = legacyEntryID
        let prompt = try WordPrompt(
            id: legacyPromptID,
            learningMode: .read,
            text: "train"
        )
        legacyEntry = WordPoolEntry(
            id: legacyEntryID,
            profileID: resolvedProfile.id,
            prompt: prompt,
            addedAt: now,
            source: .guardianManual
        )
        attempt = AttemptEvent(
            profileID: resolvedProfile.id,
            wordPromptID: legacyPromptID,
            learningMode: .read,
            evidence: .firstIndependentAttempt,
            outcome: .correct,
            timing: AttemptTiming(
                totalResponseTime: ElapsedTime(seconds: 2.5)
            ),
            occurredAt: now.addingTimeInterval(30)
        )
        settings = LocalJSONPracticeSettingsRepository(
            snapshotURL: directory.appendingPathComponent("settings.json")
        )
        daily = LocalJSONDailyQuestRepository(
            snapshotURL: directory.appendingPathComponent("daily.json")
        )
    }

    var canonicalPromptID: WordPromptID {
        WordPoolStableIdentity.promptID(
            profileID: profile.id,
            learningMode: .read,
            normalizedText: "train"
        )
    }

    func seedLegacyLocalState() async throws {
        try await profiles.save(profile)
        try InspectableSnapshotJSONCodec.makeEncoder().encode(
            WordPoolSnapshot(schemaVersion: 1, entries: [legacyEntry])
        ).write(to: wordPoolURL)
        let legacyProgress = WordProgress(
            profileID: profile.id,
            wordPromptID: legacyPromptID,
            learningMode: .read,
            firstIndependentAttemptCount: 1,
            firstIndependentCorrectCount: 1,
            lastEncounterAt: attempt.occurredAt
        )
        try InspectableSnapshotJSONCodec.makeEncoder().encode(
            LearningRecordSnapshot(
                schemaVersion: 1,
                attempts: [attempt],
                corrections: [],
                progress: [legacyProgress]
            )
        ).write(to: learningURL)
    }

    func store(
        words: LocalJSONWordPoolRepository,
        learning: LocalJSONLearningRecordRepository,
        deviceID: String
    ) -> RepositoryFamilySyncRecordStore {
        RepositoryFamilySyncRecordStore(
            profileRepository: profiles,
            wordPoolRepository: words,
            practiceSettingsRepository: settings,
            learningRepository: learning,
            dailyQuestRepository: daily,
            tombstoneRepository: tombstones,
            deviceID: deviceID
        )
    }

    func oldAttemptRecord(
        deviceID: String = "legacy-device"
    ) throws -> FamilySyncRecord {
        FamilySyncRecord(
            recordName: "attempt-\(attempt.id)",
            profileID: profile.id,
            kind: .attempt,
            payload: try InspectableSnapshotJSONCodec.makeEncoder().encode(
                attempt
            ),
            updatedAt: attempt.occurredAt,
            deviceID: deviceID,
            logicalRevision: FamilySyncLogicalRevision(
                counter: 2,
                deviceID: deviceID
            )
        )
    }

    func remove() {
        try? FileManager.default.removeItem(at: directory)
    }
}
