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

    func testRestartedRepositoryDeduplicatesAndRequeuesExistingEntry()
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
            "ＣＡＴ",
            profileID: ContentTestFixture.profileID,
            learningMode: .read,
            addedAt: secondDate
        )
        let requeued = try XCTUnwrap(duplicateResult.requeuedExisting.first)

        XCTAssertEqual(requeued.id, original.id)
        XCTAssertEqual(requeued.prompt.id, original.prompt.id)
        XCTAssertEqual(requeued.addedAt, firstDate)
        XCTAssertEqual(requeued.lastQueuedAt, secondDate)

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

    func testConcurrentWritesRemainDeduplicatedAndRestartable() async throws {
        let snapshotURL = try makeSnapshotURL()
        let repository = LocalJSONWordPoolRepository(snapshotURL: snapshotURL)
        let importer = ManualWordPoolImporter(repository: repository)

        let returnedIDs = await withTaskGroup(
            of: WordPoolEntryID?.self,
            returning: [WordPoolEntryID].self
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
                    return result?.inserted.first?.id
                        ?? result?.requeuedExisting.first?.id
                }
            }

            var ids: [WordPoolEntryID] = []
            for await id in group {
                if let id { ids.append(id) }
            }
            return ids
        }

        XCTAssertEqual(returnedIDs.count, 24)
        XCTAssertEqual(Set(returnedIDs).count, 1)
        let restartedRepository = LocalJSONWordPoolRepository(
            snapshotURL: snapshotURL
        )
        let entries = try await restartedRepository.entries(
            for: ContentTestFixture.profileID,
            learningMode: .read,
            includingInactive: true
        )
        XCTAssertEqual(entries.count, 1)
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
            guard case .unsupportedSchemaVersion(_, 999, 1) = error else {
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
