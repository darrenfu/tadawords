import Foundation
import TadaWordsDomain
import XCTest

@testable import TadaWordsContent

final class RepositoryFamilySyncWordBusinessKeyHarnessTests: XCTestCase {
    func testIndependentSameWordUUIDsUseStableKeyAndConvergeWithoutDuplicate()
        async throws
    {
        let fixture = try WordBusinessKeyHarnessFixture()
        defer { fixture.remove() }
        try await fixture.profiles.save(fixture.profile)
        let entryA = try fixture.entry(
            text: "Dog",
            addedAt: fixture.now,
            position: 0
        )
        let entryB = try fixture.entry(
            text: "dog",
            addedAt: fixture.now.addingTimeInterval(10),
            position: 1
        )
        XCTAssertNotEqual(entryA.id, entryB.id)
        XCTAssertNotEqual(entryA.prompt.id, entryB.prompt.id)
        XCTAssertEqual(entryA.poolIdentity, entryB.poolIdentity)

        let recordA = try await fixture.export(
            entryA,
            snapshotName: "device-a.json",
            deviceID: "device-a"
        )
        let recordB = try await fixture.export(
            entryB,
            snapshotName: "device-b.json",
            deviceID: "device-b"
        )
        XCTAssertEqual(
            recordA.recordName,
            recordB.recordName,
            "Word records need a stable Profile x Mode x normalized-word key, not a random entry UUID"
        )

        let forward = try await fixture.apply(
            [recordA, recordB],
            snapshotName: "forward.json"
        )
        let reverse = try await fixture.apply(
            [recordB, recordA],
            snapshotName: "reverse.json"
        )
        let forwardSnapshot = try InspectableSnapshotJSONCodec.makeDecoder()
            .decode(WordPoolSnapshot.self, from: forward)
        let reverseSnapshot = try InspectableSnapshotJSONCodec.makeDecoder()
            .decode(WordPoolSnapshot.self, from: reverse)
        XCTAssertEqual(
            reverse,
            forward,
            "Independent entry and prompt UUIDs must collapse to one deterministic canonical word membership. Forward entries: \(forwardSnapshot.entries). Reverse entries: \(reverseSnapshot.entries)"
        )
        XCTAssertEqual(forwardSnapshot.entries.count, 1)
        XCTAssertEqual(forwardSnapshot.entries[0].normalizedText, "dog")
    }

    func testLegacyUUIDRecordAliasMigratesToCanonicalWordKeyAfterRestart()
        async throws
    {
        let fixture = try WordBusinessKeyHarnessFixture()
        defer { fixture.remove() }
        try await fixture.profiles.save(fixture.profile)
        let entry = try fixture.entry(
            text: "train",
            addedAt: fixture.now,
            position: 0
        )
        let canonical = try await fixture.export(
            entry,
            snapshotName: "canonical-source.json",
            deviceID: "new-device"
        )
        let legacyName = "word-entry-\(entry.id)"
        let legacy = FamilySyncRecord(
            recordName: legacyName,
            profileID: canonical.profileID,
            kind: canonical.kind,
            payload: canonical.payload,
            updatedAt: canonical.updatedAt,
            deviceID: "legacy-device",
            schemaVersion: canonical.schemaVersion,
            minimumReadableVersion: canonical.minimumReadableVersion,
            logicalRevision: FamilySyncLogicalRevision(
                counter: 1,
                deviceID: "legacy-device"
            )
        )
        let targetURL = fixture.directory.appendingPathComponent("legacy-target.json")
        var words = LocalJSONWordPoolRepository(snapshotURL: targetURL)
        var store = fixture.store(words: words, deviceID: "target")
        try await store.validate([legacy], for: fixture.profile.id)
        try await store.apply([legacy], for: fixture.profile.id)

        words = LocalJSONWordPoolRepository(snapshotURL: targetURL)
        store = fixture.store(words: words, deviceID: "target")
        let exported = try await store.records(for: fixture.profile.id).filter {
            $0.kind == .wordPoolEntry
        }

        XCTAssertEqual(exported.count, 1)
        XCTAssertEqual(exported[0].recordName, canonical.recordName)
        XCTAssertNotEqual(
            exported[0].recordName,
            legacyName,
            "A legacy physical UUID alias must not remain the canonical sync key"
        )
    }

    func testHigherLogicalRevisionInactiveWinnerSurvivesRestartAndReExport()
        async throws
    {
        let fixture = try WordBusinessKeyHarnessFixture()
        defer { fixture.remove() }
        try await fixture.profiles.save(fixture.profile)
        let activeWithLaterQueue = try fixture.canonicalEntry(
            text: "rocket",
            isActive: true,
            lastQueuedAt: fixture.now.addingTimeInterval(500),
            position: 9
        )
        let inactiveLogicalWinner = try fixture.canonicalEntry(
            text: "rocket",
            isActive: false,
            lastQueuedAt: fixture.now,
            position: 0
        )
        let localRecord = try fixture.record(
            entry: activeWithLaterQueue,
            revision: FamilySyncLogicalRevision(
                counter: 1,
                deviceID: "device-a"
            )
        )
        let remoteRecord = try fixture.record(
            entry: inactiveLogicalWinner,
            revision: FamilySyncLogicalRevision(
                counter: 9,
                deviceID: "device-b"
            )
        )
        let snapshotURL = fixture.directory.appendingPathComponent(
            "revision-inactive.json"
        )

        try await fixture.apply([localRecord, remoteRecord], to: snapshotURL)
        let restartedWords = LocalJSONWordPoolRepository(snapshotURL: snapshotURL)
        let entries = try await restartedWords.entries(
            for: fixture.profile.id,
            learningMode: .read,
            includingInactive: true
        )
        let restartedStore = fixture.store(
            words: restartedWords,
            deviceID: "restarted"
        )
        let restartedRecords = try await restartedStore.records(
            for: fixture.profile.id
        )
        let exported = try XCTUnwrap(
            restartedRecords.first { $0.kind == .wordPoolEntry }
        )

        XCTAssertEqual(entries.count, 1)
        XCTAssertFalse(
            entries[0].isActive,
            "A later queue timestamp is not conflict authority over a higher logical revision"
        )
        XCTAssertEqual(
            exported.logicalRevision,
            remoteRecord.logicalRevision,
            "The per-entry winning revision must survive repository restart and re-export"
        )
    }

    func testRemoveReactivateAndMoveConvergeByPersistedRevisionInEveryOrder()
        async throws
    {
        let fixture = try WordBusinessKeyHarnessFixture()
        defer { fixture.remove() }
        try await fixture.profiles.save(fixture.profile)
        let remove = try fixture.record(
            entry: fixture.canonicalEntry(
                text: "castle",
                isActive: false,
                lastQueuedAt: fixture.now.addingTimeInterval(500),
                position: 1
            ),
            revision: FamilySyncLogicalRevision(
                counter: 2,
                deviceID: "device-a"
            )
        )
        let reactivate = try fixture.record(
            entry: fixture.canonicalEntry(
                text: "castle",
                isActive: true,
                lastQueuedAt: fixture.now.addingTimeInterval(200),
                position: 3
            ),
            revision: FamilySyncLogicalRevision(
                counter: 3,
                deviceID: "device-b"
            )
        )
        let move = try fixture.record(
            entry: fixture.canonicalEntry(
                text: "castle",
                isActive: true,
                lastQueuedAt: fixture.now.addingTimeInterval(100),
                position: 8
            ),
            revision: FamilySyncLogicalRevision(
                counter: 4,
                deviceID: "device-c"
            )
        )
        let permutations = [
            [remove, reactivate, move],
            [remove, move, reactivate],
            [reactivate, remove, move],
            [reactivate, move, remove],
            [move, remove, reactivate],
            [move, reactivate, remove],
        ]
        var baseline: Data?

        for (index, order) in permutations.enumerated() {
            let snapshotURL = fixture.directory.appendingPathComponent(
                "revision-permutation-\(index).json"
            )
            try await fixture.apply(order, to: snapshotURL)
            let bytes = try Data(contentsOf: snapshotURL)
            if let baseline {
                XCTAssertEqual(
                    bytes,
                    baseline,
                    "Remove/reactivate/move must be byte-equivalent for every delivery order"
                )
            } else {
                baseline = bytes
            }
            let restartedWords = LocalJSONWordPoolRepository(
                snapshotURL: snapshotURL
            )
            let restartedEntries = try await restartedWords.entries(
                for: fixture.profile.id,
                learningMode: .read,
                includingInactive: true
            )
            let entry = try XCTUnwrap(
                restartedEntries.first
            )
            let restartedRecords = try await fixture.store(
                words: restartedWords,
                deviceID: "restart"
            ).records(for: fixture.profile.id)
            let exported = try XCTUnwrap(
                restartedRecords.first { $0.kind == .wordPoolEntry }
            )
            XCTAssertTrue(entry.isActive)
            XCTAssertEqual(entry.positionInLastBatch, 8)
            XCTAssertEqual(exported.logicalRevision, move.logicalRevision)
        }
    }
}

private struct WordBusinessKeyHarnessFixture {
    let directory: URL
    let now = Date(timeIntervalSince1970: 2_170_000_000)
    let profile: KidProfile
    let profiles = InMemoryKidProfileRepository()
    let settings: LocalJSONPracticeSettingsRepository
    let learning: LocalJSONLearningRecordRepository
    let daily: LocalJSONDailyQuestRepository
    let tombstones = InMemoryProfileDeletionTombstoneRepository()

    init() throws {
        directory = FileManager.default.temporaryDirectory.appendingPathComponent(
            "TadaWordBusinessKeyHarness-\(UUID().uuidString)",
            isDirectory: true
        )
        try FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true
        )
        profile = KidProfile(
            displayName: "Word Key",
            avatar: .cartoonAnimal(assetID: "fox"),
            selectedWorld: .moonpetalKingdom,
            createdAt: now
        )
        settings = LocalJSONPracticeSettingsRepository(
            snapshotURL: directory.appendingPathComponent("settings.json")
        )
        learning = LocalJSONLearningRecordRepository(
            snapshotURL: directory.appendingPathComponent("learning.json")
        )
        daily = LocalJSONDailyQuestRepository(
            snapshotURL: directory.appendingPathComponent("daily.json")
        )
    }

    func entry(
        text: String,
        addedAt: Date,
        position: Int
    ) throws -> WordPoolEntry {
        WordPoolEntry(
            profileID: profile.id,
            prompt: try WordPrompt(learningMode: .read, text: text),
            addedAt: addedAt,
            source: .guardianManual,
            positionInLastBatch: position
        )
    }

    func canonicalEntry(
        text: String,
        isActive: Bool,
        lastQueuedAt: Date,
        position: Int
    ) throws -> WordPoolEntry {
        let normalized = try EnglishWordNormalizer.normalize(text)
        let prompt = try WordPrompt(
            id: WordPoolStableIdentity.promptID(
                profileID: profile.id,
                learningMode: .read,
                normalizedText: normalized
            ),
            learningMode: .read,
            text: text
        )
        return WordPoolEntry(
            id: WordPoolStableIdentity.entryID(
                profileID: profile.id,
                learningMode: .read,
                normalizedText: normalized
            ),
            profileID: profile.id,
            prompt: prompt,
            addedAt: now,
            source: .guardianManual,
            isActive: isActive,
            lastQueuedAt: lastQueuedAt,
            positionInLastBatch: position
        )
    }

    func record(
        entry: WordPoolEntry,
        revision: FamilySyncLogicalRevision
    ) throws -> FamilySyncRecord {
        FamilySyncRecord(
            recordName: "word-entry-\(entry.id)",
            profileID: profile.id,
            kind: .wordPoolEntry,
            payload: try InspectableSnapshotJSONCodec.makeEncoder().encode(entry),
            updatedAt: entry.lastQueuedAt,
            deviceID: revision.deviceID,
            logicalRevision: revision
        )
    }

    func store(
        words: LocalJSONWordPoolRepository,
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

    func export(
        _ entry: WordPoolEntry,
        snapshotName: String,
        deviceID: String
    ) async throws -> FamilySyncRecord {
        let words = LocalJSONWordPoolRepository(
            snapshotURL: directory.appendingPathComponent(snapshotName)
        )
        try await words.mergeSynced(entry)
        let records = try await store(words: words, deviceID: deviceID)
            .records(for: profile.id)
        return try XCTUnwrap(records.first { $0.kind == .wordPoolEntry })
    }

    func apply(
        _ records: [FamilySyncRecord],
        snapshotName: String
    ) async throws -> Data {
        let url = directory.appendingPathComponent(snapshotName)
        for record in records {
            let words = LocalJSONWordPoolRepository(snapshotURL: url)
            let store = store(words: words, deviceID: "target")
            try await store.validate([record], for: profile.id)
            try await store.apply([record], for: profile.id)
        }
        return try Data(contentsOf: url)
    }

    func apply(
        _ records: [FamilySyncRecord],
        to snapshotURL: URL
    ) async throws {
        for record in records {
            let words = LocalJSONWordPoolRepository(snapshotURL: snapshotURL)
            let store = store(words: words, deviceID: "target")
            try await store.validate([record], for: profile.id)
            try await store.apply([record], for: profile.id)
        }
    }

    func remove() {
        try? FileManager.default.removeItem(at: directory)
    }
}
