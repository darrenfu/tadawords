import Foundation
import TadaWordsContent
import TadaWordsDomain
import XCTest

final class LocalJSONWordPoolRepositoryTests: XCTestCase {
    func testMissingFileLoadsEmptyAndIsCreatedOnlyByMutation() async throws {
        let snapshotURL = try makeSnapshotURL()
        let repository = LocalJSONWordPoolRepository(snapshotURL: snapshotURL)

        let initialEntries = try await repository.entries(
            for: ContentTestFixture.profileID,
            learningMode: .read,
            includingInactive: true
        )
        XCTAssertTrue(initialEntries.isEmpty)
        XCTAssertFalse(FileManager.default.fileExists(atPath: snapshotURL.path))

        _ = try await ManualWordPoolImporter(repository: repository).importBatch(
            "cat",
            profileID: ContentTestFixture.profileID,
            learningMode: .read,
            addedAt: ContentTestFixture.day
        )

        XCTAssertTrue(FileManager.default.fileExists(atPath: snapshotURL.path))
        let snapshotText = try String(contentsOf: snapshotURL, encoding: .utf8)
        XCTAssertTrue(snapshotText.contains("\"schemaVersion\""))
        XCTAssertTrue(snapshotText.contains("\"entries\""))
        XCTAssertTrue(snapshotText.contains("\"cat\""))
    }

    func testRestartPreservesIdentityTimestampsActiveStateModesAndProfiles()
        async throws
    {
        let snapshotURL = try makeSnapshotURL()
        let firstRepository = LocalJSONWordPoolRepository(
            snapshotURL: snapshotURL
        )
        let importer = ManualWordPoolImporter(repository: firstRepository)
        let fractionalDate = Date(timeIntervalSince1970: 2_000_000_000.123_456)

        let readResult = try await importer.importBatch(
            "cat dog",
            profileID: ContentTestFixture.profileID,
            learningMode: .read,
            addedAt: fractionalDate
        )
        _ = try await importer.importBatch(
            "cat",
            profileID: ContentTestFixture.profileID,
            learningMode: .write,
            addedAt: fractionalDate.addingTimeInterval(1)
        )
        _ = try await importer.importBatch(
            "owl",
            profileID: ContentTestFixture.secondProfileID,
            learningMode: .read,
            addedAt: fractionalDate.addingTimeInterval(2)
        )
        let dog = try XCTUnwrap(
            readResult.inserted.first { $0.normalizedText == "dog" }
        )
        _ = try await firstRepository.setActive(false, entryID: dog.id)

        let expectedRead = try await firstRepository.entries(
            for: ContentTestFixture.profileID,
            learningMode: .read,
            includingInactive: true
        )
        let restartedRepository = LocalJSONWordPoolRepository(
            snapshotURL: snapshotURL
        )
        let restoredRead = try await restartedRepository.entries(
            for: ContentTestFixture.profileID,
            learningMode: .read,
            includingInactive: true
        )
        let restoredWrite = try await restartedRepository.entries(
            for: ContentTestFixture.profileID,
            learningMode: .write,
            includingInactive: true
        )
        let restoredOtherProfile = try await restartedRepository.entries(
            for: ContentTestFixture.secondProfileID,
            learningMode: .read,
            includingInactive: true
        )

        XCTAssertEqual(restoredRead, expectedRead)
        XCTAssertEqual(restoredRead.map(\.normalizedText), ["cat", "dog"])
        let restoredFirstAddedAt = try XCTUnwrap(restoredRead.first?.addedAt)
        XCTAssertEqual(
            restoredFirstAddedAt.timeIntervalSince1970,
            fractionalDate.timeIntervalSince1970,
            accuracy: 0.000_001
        )
        XCTAssertEqual(restoredRead.first { $0.id == dog.id }?.isActive, false)
        XCTAssertEqual(restoredWrite.map(\.normalizedText), ["cat"])
        XCTAssertEqual(restoredOtherProfile.map(\.normalizedText), ["owl"])
    }

    func testRestartedRepositoryClassifiesAndRequeuesActiveDuplicate()
        async throws
    {
        let snapshotURL = try makeSnapshotURL()
        let firstDate = ContentTestFixture.day.addingTimeInterval(-86_400)
        let secondDate = ContentTestFixture.day
        let firstRepository = LocalJSONWordPoolRepository(
            snapshotURL: snapshotURL
        )
        let originalResult = try await ManualWordPoolImporter(
            repository: firstRepository
        ).importBatch(
            "Cat",
            profileID: ContentTestFixture.profileID,
            learningMode: .read,
            addedAt: firstDate
        )
        let original = try XCTUnwrap(originalResult.inserted.first)

        let restartedRepository = LocalJSONWordPoolRepository(
            snapshotURL: snapshotURL
        )
        let duplicateResult = try await ManualWordPoolImporter(
            repository: restartedRepository
        ).importBatch(
            "123 ＣＡＴ",
            profileID: ContentTestFixture.profileID,
            learningMode: .read,
            addedAt: secondDate
        )
        let requeued = try XCTUnwrap(duplicateResult.alreadyActive.first)

        XCTAssertEqual(requeued.id, original.id)
        XCTAssertEqual(requeued.prompt.id, original.prompt.id)
        XCTAssertEqual(requeued.addedAt, original.addedAt)
        XCTAssertEqual(requeued.source, original.source)
        XCTAssertEqual(requeued.lastQueuedAt, secondDate)
        XCTAssertEqual(requeued.positionInLastBatch, 1)
        XCTAssertTrue(requeued.isActive)
        XCTAssertTrue(duplicateResult.inserted.isEmpty)
        XCTAssertTrue(duplicateResult.reactivated.isEmpty)

        let secondRestart = LocalJSONWordPoolRepository(
            snapshotURL: snapshotURL
        )
        let entries = try await secondRestart.entries(
            for: ContentTestFixture.profileID,
            learningMode: .read,
            includingInactive: true
        )
        XCTAssertEqual(entries, [requeued])
    }

    func testRestartedRepositoryReactivatesInactiveEntryWithExactIdentity()
        async throws
    {
        let snapshotURL = try makeSnapshotURL()
        let firstDate = ContentTestFixture.day.addingTimeInterval(-86_400)
        let secondDate = ContentTestFixture.day
        let firstRepository = LocalJSONWordPoolRepository(
            snapshotURL: snapshotURL
        )
        let originalResult = try await ManualWordPoolImporter(
            repository: firstRepository
        ).importBatch(
            "Cat",
            profileID: ContentTestFixture.profileID,
            learningMode: .read,
            addedAt: firstDate
        )
        let original = try XCTUnwrap(originalResult.inserted.first)
        _ = try await firstRepository.setActive(false, entryID: original.id)

        let restartedRepository = LocalJSONWordPoolRepository(
            snapshotURL: snapshotURL
        )
        let restoredResult = try await ManualWordPoolImporter(
            repository: restartedRepository
        ).importBatch(
            "cat",
            profileID: ContentTestFixture.profileID,
            learningMode: .read,
            addedAt: secondDate
        )
        let restored = try XCTUnwrap(restoredResult.reactivated.first)

        XCTAssertEqual(restored.id, original.id)
        XCTAssertEqual(restored.prompt.id, original.prompt.id)
        XCTAssertEqual(restored.addedAt, original.addedAt)
        XCTAssertEqual(restored.source, original.source)
        XCTAssertEqual(restored.lastQueuedAt, secondDate)
        XCTAssertTrue(restored.isActive)
        XCTAssertTrue(restoredResult.inserted.isEmpty)
        XCTAssertTrue(restoredResult.alreadyActive.isEmpty)

        let secondRestart = LocalJSONWordPoolRepository(
            snapshotURL: snapshotURL
        )
        let entries = try await secondRestart.entries(
            for: ContentTestFixture.profileID,
            learningMode: .read,
            includingInactive: true
        )
        XCTAssertEqual(entries, [restored])
    }

    func testConcurrentWritesRemainDeduplicatedAndRestartable() async throws {
        let snapshotURL = try makeSnapshotURL()
        let repository = LocalJSONWordPoolRepository(snapshotURL: snapshotURL)
        let importer = ManualWordPoolImporter(repository: repository)

        let results = await withTaskGroup(
            of: ManualWordPoolImportResult?.self,
            returning: [ManualWordPoolImportResult].self
        ) { group in
            for offset in 0..<24 {
                group.addTask {
                    let result = try? await importer.importBatch(
                        "cat",
                        profileID: ContentTestFixture.profileID,
                        learningMode: .read,
                        addedAt: ContentTestFixture.day.addingTimeInterval(
                            Double(offset)
                        )
                    )
                    return result
                }
            }

            var results: [ManualWordPoolImportResult] = []
            for await result in group {
                if let result { results.append(result) }
            }
            return results
        }

        let inserted = results.flatMap(\.inserted)
        let reactivated = results.flatMap(\.reactivated)
        let alreadyActive = results.flatMap(\.alreadyActive)
        XCTAssertEqual(results.count, 24)
        XCTAssertEqual(inserted.count, 1)
        XCTAssertTrue(reactivated.isEmpty)
        XCTAssertEqual(alreadyActive.count, 23)
        XCTAssertEqual(Set((inserted + alreadyActive).map(\.id)).count, 1)
        let restartedRepository = LocalJSONWordPoolRepository(
            snapshotURL: snapshotURL
        )
        let entries = try await restartedRepository.entries(
            for: ContentTestFixture.profileID,
            learningMode: .read,
            includingInactive: true
        )
        XCTAssertEqual(entries.count, 1)
        XCTAssertEqual(entries.first?.id, inserted.first?.id)
        XCTAssertEqual(
            entries.first?.lastQueuedAt,
            ContentTestFixture.day.addingTimeInterval(23)
        )
        let leftoverFiles = try FileManager.default.contentsOfDirectory(
            atPath: snapshotURL.deletingLastPathComponent().path
        ).filter { $0.hasSuffix(".tmp") }
        XCTAssertTrue(leftoverFiles.isEmpty)
    }

    func testCorruptFileIsLatchedPreservedAndExplicitlyReloadableAfterRepair()
        async throws
    {
        let snapshotURL = try makeSnapshotURL()
        let corruptData = Data("{ definitely not json".utf8)
        try corruptData.write(to: snapshotURL)
        let repository = LocalJSONWordPoolRepository(snapshotURL: snapshotURL)

        await assertInvalidJSON {
            _ = try await repository.entries(
                for: ContentTestFixture.profileID,
                learningMode: .read,
                includingInactive: true
            )
        }
        await assertInvalidJSON {
            _ = try await ManualWordPoolImporter(
                repository: repository
            ).importBatch(
                "cat",
                profileID: ContentTestFixture.profileID,
                learningMode: .read,
                addedAt: ContentTestFixture.day
            )
        }
        XCTAssertEqual(try Data(contentsOf: snapshotURL), corruptData)

        try encodeSnapshot(WordPoolSnapshot(entries: [])).write(to: snapshotURL)
        await assertInvalidJSON {
            _ = try await repository.entries(
                for: ContentTestFixture.profileID,
                learningMode: .read,
                includingInactive: true
            )
        }

        try await repository.reloadFromDisk()
        let recoveredEntries = try await repository.entries(
            for: ContentTestFixture.profileID,
            learningMode: .read,
            includingInactive: true
        )
        XCTAssertTrue(recoveredEntries.isEmpty)
    }

    func testUnsupportedSchemaIsReportedAndNeverOverwritten() async throws {
        let snapshotURL = try makeSnapshotURL()
        let unsupportedData = try encodeSnapshot(
            WordPoolSnapshot(schemaVersion: 999, entries: [])
        )
        try unsupportedData.write(to: snapshotURL)
        let repository = LocalJSONWordPoolRepository(snapshotURL: snapshotURL)

        do {
            _ = try await ManualWordPoolImporter(
                repository: repository
            ).importBatch(
                "cat",
                profileID: ContentTestFixture.profileID,
                learningMode: .read,
                addedAt: ContentTestFixture.day
            )
            XCTFail("Expected an unsupported-schema error")
        } catch let error as LocalWordPoolRepositoryError {
            guard case .unsupportedSchemaVersion(_, 999, 2) = error else {
                return XCTFail("Unexpected error: \(error)")
            }
        }

        XCTAssertEqual(try Data(contentsOf: snapshotURL), unsupportedData)
    }

    func testDuplicateIdentitySnapshotIsRejectedWithoutDataLoss() async throws {
        let snapshotURL = try makeSnapshotURL()
        let first = try ContentTestFixture.entry(
            "cat",
            number: 1,
            addedAt: ContentTestFixture.day
        )
        let duplicate = try ContentTestFixture.entry(
            "CAT",
            number: 2,
            addedAt: ContentTestFixture.day.addingTimeInterval(1)
        )
        let invalidData = try encodeSnapshot(
            WordPoolSnapshot(entries: [first, duplicate])
        )
        try invalidData.write(to: snapshotURL)
        let repository = LocalJSONWordPoolRepository(snapshotURL: snapshotURL)

        do {
            _ = try await repository.entries(
                for: ContentTestFixture.profileID,
                learningMode: .read,
                includingInactive: true
            )
            XCTFail("Expected a duplicate-identity error")
        } catch let error as LocalWordPoolRepositoryError {
            guard case .invalidSnapshot(_, .duplicatePoolIdentity) = error else {
                return XCTFail("Unexpected error: \(error)")
            }
        }

        XCTAssertEqual(try Data(contentsOf: snapshotURL), invalidData)
    }

    func testWriteFailureDoesNotCommitCandidateToActorState() async throws {
        let snapshotURL = try makeSnapshotURL()
        let repository = LocalJSONWordPoolRepository(
            snapshotURL: snapshotURL
        )
        let initiallyEmpty = try await repository.entries(
            for: ContentTestFixture.profileID,
            learningMode: .read,
            includingInactive: true
        )
        XCTAssertTrue(initiallyEmpty.isEmpty)

        let blockingParent = snapshotURL.deletingLastPathComponent()
        try FileManager.default.removeItem(at: blockingParent)
        try Data("keep me".utf8).write(to: blockingParent)

        do {
            _ = try await ManualWordPoolImporter(
                repository: repository
            ).importBatch(
                "cat",
                profileID: ContentTestFixture.profileID,
                learningMode: .read,
                addedAt: ContentTestFixture.day
            )
            XCTFail("Expected an atomic-write failure")
        } catch let error as LocalWordPoolRepositoryError {
            guard case .writeFailed = error else {
                return XCTFail("Unexpected error: \(error)")
            }
        }

        let entries = try await repository.entries(
            for: ContentTestFixture.profileID,
            learningMode: .read,
            includingInactive: true
        )
        XCTAssertTrue(entries.isEmpty)
        XCTAssertEqual(
            try Data(contentsOf: blockingParent),
            Data("keep me".utf8)
        )
    }

    func testStableSnapshotEncodingDoesNotChangeForOlderDuplicateEvent()
        async throws
    {
        let snapshotURL = try makeSnapshotURL()
        let repository = LocalJSONWordPoolRepository(snapshotURL: snapshotURL)
        let importer = ManualWordPoolImporter(repository: repository)
        _ = try await importer.importBatch(
            "dog cat",
            profileID: ContentTestFixture.profileID,
            learningMode: .read,
            addedAt: ContentTestFixture.day
        )
        let originalData = try Data(contentsOf: snapshotURL)

        let restartedRepository = LocalJSONWordPoolRepository(
            snapshotURL: snapshotURL
        )
        _ = try await ManualWordPoolImporter(
            repository: restartedRepository
        ).importBatch(
            "dog",
            profileID: ContentTestFixture.profileID,
            learningMode: .read,
            addedAt: ContentTestFixture.day.addingTimeInterval(-60)
        )

        XCTAssertEqual(try Data(contentsOf: snapshotURL), originalData)
    }

    func testIndependentDevicesDeriveSameEntryAndPromptIDs() async throws {
        let firstURL = try makeSnapshotURL()
        let secondURL = try makeSnapshotURL()
        let first = try await ManualWordPoolImporter(
            repository: LocalJSONWordPoolRepository(snapshotURL: firstURL)
        ).importBatch(
            "Dog",
            profileID: ContentTestFixture.profileID,
            learningMode: .read,
            addedAt: ContentTestFixture.day
        )
        let second = try await ManualWordPoolImporter(
            repository: LocalJSONWordPoolRepository(snapshotURL: secondURL)
        ).importBatch(
            "ＤＯＧ",
            profileID: ContentTestFixture.profileID,
            learningMode: .read,
            addedAt: ContentTestFixture.day.addingTimeInterval(30)
        )

        let firstEntry = try XCTUnwrap(first.inserted.first)
        let secondEntry = try XCTUnwrap(second.inserted.first)
        XCTAssertEqual(firstEntry.id, secondEntry.id)
        XCTAssertEqual(firstEntry.prompt.id, secondEntry.prompt.id)
        XCTAssertTrue(firstEntry.legacyEntryIDs.isEmpty)
        XCTAssertTrue(firstEntry.legacyPromptIDs.isEmpty)

        let write = try await ManualWordPoolImporter(
            repository: LocalJSONWordPoolRepository(
                snapshotURL: try makeSnapshotURL()
            )
        ).importBatch(
            "dog",
            profileID: ContentTestFixture.profileID,
            learningMode: .write,
            addedAt: ContentTestFixture.day
        )
        XCTAssertNotEqual(write.inserted.first?.id, firstEntry.id)
        XCTAssertNotEqual(write.inserted.first?.prompt.id, firstEntry.prompt.id)
    }

    func testV1SnapshotMigratesAtomicallyAndLegacyIDsStillResolve()
        async throws
    {
        let snapshotURL = try makeSnapshotURL()
        let legacy = try ContentTestFixture.entry(
            "Cat",
            number: 41,
            addedAt: ContentTestFixture.day
        )
        try encodeSnapshot(
            WordPoolSnapshot(schemaVersion: 1, entries: [legacy])
        ).write(to: snapshotURL)

        let repository = LocalJSONWordPoolRepository(snapshotURL: snapshotURL)
        let migratedEntries = try await repository.entries(
            for: ContentTestFixture.profileID,
            learningMode: .read,
            includingInactive: true
        )
        let migrated = try XCTUnwrap(migratedEntries.first)

        XCTAssertNotEqual(migrated.id, legacy.id)
        XCTAssertNotEqual(migrated.prompt.id, legacy.prompt.id)
        XCTAssertTrue(migrated.resolves(entryID: legacy.id))
        XCTAssertTrue(migrated.resolves(promptID: legacy.prompt.id))

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .secondsSince1970
        let persisted = try decoder.decode(
            WordPoolSnapshot.self,
            from: Data(contentsOf: snapshotURL)
        )
        XCTAssertEqual(persisted.schemaVersion, 2)
        XCTAssertEqual(persisted.entries, [migrated])

        let updatedThroughLegacyID = try await repository.setActive(
            false,
            entryID: legacy.id
        )
        XCTAssertEqual(updatedThroughLegacyID.id, migrated.id)
        XCTAssertFalse(updatedThroughLegacyID.isActive)

        let restarted = LocalJSONWordPoolRepository(snapshotURL: snapshotURL)
        let afterRestart = try await restarted.entries(
            for: ContentTestFixture.profileID,
            learningMode: .read,
            includingInactive: true
        )
        XCTAssertEqual(afterRestart, [updatedThroughLegacyID])
    }

    func testV1DuplicateBusinessIdentityCollapsesWithoutLosingAliases()
        async throws
    {
        let snapshotURL = try makeSnapshotURL()
        let first = try ContentTestFixture.entry(
            "cat",
            number: 51,
            addedAt: ContentTestFixture.day,
            lastQueuedAt: ContentTestFixture.day,
            isActive: true,
            position: 0
        )
        let second = try ContentTestFixture.entry(
            "CAT",
            number: 52,
            addedAt: ContentTestFixture.day.addingTimeInterval(10),
            lastQueuedAt: ContentTestFixture.day.addingTimeInterval(20),
            isActive: false,
            position: 3
        )
        try encodeSnapshot(
            WordPoolSnapshot(schemaVersion: 1, entries: [first, second])
        ).write(to: snapshotURL)

        let repository = LocalJSONWordPoolRepository(snapshotURL: snapshotURL)
        let entries = try await repository.entries(
            for: ContentTestFixture.profileID,
            learningMode: .read,
            includingInactive: true
        )

        let migrated = try XCTUnwrap(entries.first)
        XCTAssertEqual(entries.count, 1)
        XCTAssertEqual(Set(migrated.legacyEntryIDs), [first.id, second.id])
        XCTAssertEqual(
            Set(migrated.legacyPromptIDs),
            [first.prompt.id, second.prompt.id]
        )
        XCTAssertEqual(migrated.addedAt, first.addedAt)
        XCTAssertEqual(migrated.lastQueuedAt, second.lastQueuedAt)
        XCTAssertEqual(migrated.positionInLastBatch, second.positionInLastBatch)
        XCTAssertFalse(migrated.isActive)
    }

    func testSyncedLegacyAliasesMergeIntoOneCanonicalMembership()
        async throws
    {
        let repository = LocalJSONWordPoolRepository(
            snapshotURL: try makeSnapshotURL()
        )
        let first = try ContentTestFixture.entry(
            "train",
            number: 61,
            addedAt: ContentTestFixture.day
        )
        let second = try ContentTestFixture.entry(
            "TRAIN",
            number: 62,
            addedAt: ContentTestFixture.day.addingTimeInterval(30),
            position: 2
        )

        try await repository.mergeSynced(first)
        try await repository.mergeSynced(second)
        let entries = try await repository.entries(
            for: ContentTestFixture.profileID,
            learningMode: .read,
            includingInactive: true
        )

        let merged = try XCTUnwrap(entries.first)
        XCTAssertEqual(entries.count, 1)
        XCTAssertEqual(Set(merged.legacyEntryIDs), [first.id, second.id])
        XCTAssertEqual(
            Set(merged.legacyPromptIDs),
            [first.prompt.id, second.prompt.id]
        )
        XCTAssertEqual(merged.lastQueuedAt, second.lastQueuedAt)
        XCTAssertEqual(merged.positionInLastBatch, 2)
    }

    private func makeSnapshotURL() throws -> URL {
        let directoryURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(
                "TadaWordsContentTests-\(UUID().uuidString)",
                isDirectory: true
            )
        try FileManager.default.createDirectory(
            at: directoryURL,
            withIntermediateDirectories: true
        )
        addTeardownBlock {
            try? FileManager.default.removeItem(at: directoryURL)
        }
        return directoryURL.appendingPathComponent("word-pool.json")
    }

    private func encodeSnapshot(_ snapshot: WordPoolSnapshot) throws -> Data {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .secondsSince1970
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return try encoder.encode(snapshot)
    }

    private func assertInvalidJSON(
        operation: () async throws -> Void
    ) async {
        do {
            try await operation()
            XCTFail("Expected an invalid-JSON error")
        } catch let error as LocalWordPoolRepositoryError {
            guard case .invalidJSON = error else {
                return XCTFail("Unexpected error: \(error)")
            }
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }
}
