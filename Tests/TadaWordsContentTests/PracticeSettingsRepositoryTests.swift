import Foundation
import TadaWordsContent
import TadaWordsDomain
import XCTest

final class PracticeSettingsRepositoryTests: XCTestCase {
    func testMissingFileReturnsNilAndDoesNotFabricateDefaults() async throws {
        let snapshotURL = try makeSnapshotURL()
        let repository = LocalJSONPracticeSettingsRepository(
            snapshotURL: snapshotURL
        )

        let settings = try await repository.settings(for: Self.firstProfileID)

        XCTAssertNil(settings)
        XCTAssertFalse(FileManager.default.fileExists(atPath: snapshotURL.path))
    }

    func testProfilesStayIsolatedWhenOneIsUpdatedAndDeleted() async throws {
        let repository = InMemoryPracticeSettingsRepository()
        let first = settings(
            profileID: Self.firstProfileID,
            readNewLimit: 5
        )
        let second = settings(
            profileID: Self.secondProfileID,
            readNewLimit: 8
        )
        try await repository.save(first)
        try await repository.save(second)

        let updatedFirst = settings(
            profileID: first.profileID,
            readNewLimit: 9
        )
        try await repository.save(updatedFirst)

        let storedFirst = try await repository.settings(for: first.profileID)
        let storedSecond = try await repository.settings(for: second.profileID)
        XCTAssertEqual(storedFirst, updatedFirst)
        XCTAssertEqual(storedSecond, second)

        try await repository.delete(for: first.profileID)
        let deletedFirst = try await repository.settings(for: first.profileID)
        let preservedSecond = try await repository.settings(for: second.profileID)
        XCTAssertNil(deletedFirst)
        XCTAssertEqual(preservedSecond, second)
    }

    func testUpdateAndOtherProfileSurviveRepositoryRestart() async throws {
        let snapshotURL = try makeSnapshotURL()
        let repository = LocalJSONPracticeSettingsRepository(
            snapshotURL: snapshotURL
        )
        let originalFirst = settings(
            profileID: Self.firstProfileID,
            readNewLimit: 5
        )
        let updatedFirst = settings(
            profileID: Self.firstProfileID,
            readNewLimit: 11,
            order: .reviewThenNew
        )
        let second = settings(
            profileID: Self.secondProfileID,
            readNewLimit: 7
        )
        try await repository.save(originalFirst)
        try await repository.save(second)
        try await repository.save(updatedFirst)

        let restarted = LocalJSONPracticeSettingsRepository(
            snapshotURL: snapshotURL
        )
        let restoredFirst = try await restarted.settings(
            for: Self.firstProfileID
        )
        let restoredSecond = try await restarted.settings(
            for: Self.secondProfileID
        )

        XCTAssertEqual(restoredFirst, updatedFirst)
        XCTAssertEqual(restoredSecond, second)
    }

    func testAudioPreferencesSurviveRepositoryRestart() async throws {
        let snapshotURL = try makeSnapshotURL()
        let repository = LocalJSONPracticeSettingsRepository(
            snapshotURL: snapshotURL
        )
        let expected = ProfilePracticeSettings(
            profileID: Self.firstProfileID,
            audio: AudioPreferences(
                voiceEnabled: false,
                musicEnabled: false,
                soundEffectsEnabled: true
            )
        )

        try await repository.save(expected)

        let restarted = LocalJSONPracticeSettingsRepository(
            snapshotURL: snapshotURL
        )
        let restored = try await restarted.settings(for: Self.firstProfileID)
        XCTAssertEqual(restored?.audio, expected.audio)
    }

    func testIdenticalSaveAndMissingDeleteDoNotRewriteSnapshot() async throws {
        let snapshotURL = try makeSnapshotURL()
        let repository = LocalJSONPracticeSettingsRepository(
            snapshotURL: snapshotURL
        )
        let savedSettings = settings(
            profileID: Self.firstProfileID,
            readNewLimit: 6
        )
        try await repository.save(savedSettings)
        let savedData = try Data(contentsOf: snapshotURL)

        try await repository.save(savedSettings)
        XCTAssertEqual(try Data(contentsOf: snapshotURL), savedData)

        try await repository.delete(for: Self.secondProfileID)
        XCTAssertEqual(try Data(contentsOf: snapshotURL), savedData)

        try await repository.delete(for: Self.firstProfileID)
        let deletedData = try Data(contentsOf: snapshotURL)
        XCTAssertNotEqual(deletedData, savedData)
        try await repository.delete(for: Self.firstProfileID)
        XCTAssertEqual(try Data(contentsOf: snapshotURL), deletedData)
    }

    func testCorruptFileIsPreservedLatchedAndReloadableAfterRepair()
        async throws
    {
        let snapshotURL = try makeSnapshotURL()
        let corruptData = Data("not valid settings json".utf8)
        try corruptData.write(to: snapshotURL)
        let repository = LocalJSONPracticeSettingsRepository(
            snapshotURL: snapshotURL
        )

        await assertInvalidJSON {
            _ = try await repository.settings(for: Self.firstProfileID)
        }
        await assertInvalidJSON {
            try await repository.save(
                Self.makeSettings(
                    profileID: Self.firstProfileID,
                    readNewLimit: 5
                )
            )
        }
        XCTAssertEqual(try Data(contentsOf: snapshotURL), corruptData)

        try encodeSnapshot(PracticeSettingsSnapshot(settings: [])).write(
            to: snapshotURL
        )
        await assertInvalidJSON {
            _ = try await repository.settings(for: Self.firstProfileID)
        }

        try await repository.reloadFromDisk()
        let restored = try await repository.settings(for: Self.firstProfileID)
        XCTAssertNil(restored)
    }

    func testDuplicateProfileSnapshotIsTypedInvalidAndPreserved() async throws {
        let snapshotURL = try makeSnapshotURL()
        let first = settings(
            profileID: Self.firstProfileID,
            readNewLimit: 5
        )
        let duplicate = settings(
            profileID: Self.firstProfileID,
            readNewLimit: 10
        )
        let invalidData = try encodeSnapshot(
            PracticeSettingsSnapshot(settings: [first, duplicate])
        )
        try invalidData.write(to: snapshotURL)
        let repository = LocalJSONPracticeSettingsRepository(
            snapshotURL: snapshotURL
        )

        do {
            _ = try await repository.settings(for: Self.firstProfileID)
            XCTFail("Expected duplicate-profile settings")
        } catch let error as LocalPracticeSettingsRepositoryError {
            XCTAssertEqual(
                error,
                .invalidSnapshot(
                    snapshotURL: snapshotURL,
                    issue: .duplicateProfileID(Self.firstProfileID)
                )
            )
        }

        XCTAssertEqual(try Data(contentsOf: snapshotURL), invalidData)
    }

    func testUnsupportedSchemaIsTypedAndPreserved() async throws {
        let snapshotURL = try makeSnapshotURL()
        let unsupportedData = try encodeSnapshot(
            PracticeSettingsSnapshot(schemaVersion: 999, settings: [])
        )
        try unsupportedData.write(to: snapshotURL)
        let repository = LocalJSONPracticeSettingsRepository(
            snapshotURL: snapshotURL
        )

        do {
            _ = try await repository.settings(for: Self.firstProfileID)
            XCTFail("Expected unsupported settings schema")
        } catch let error as LocalPracticeSettingsRepositoryError {
            XCTAssertEqual(
                error,
                .unsupportedSchemaVersion(
                    snapshotURL: snapshotURL,
                    found: 999,
                    supported: PracticeSettingsSnapshot.currentSchemaVersion
                )
            )
        }

        XCTAssertEqual(try Data(contentsOf: snapshotURL), unsupportedData)
    }

    func testConcurrentSavesAreCompleteStableAndRestartable() async throws {
        let snapshotURL = try makeSnapshotURL()
        let repository = LocalJSONPracticeSettingsRepository(
            snapshotURL: snapshotURL
        )
        let allSettings = (0..<32).map { offset in
            Self.makeSettings(
                profileID: ProfileID(),
                readNewLimit: offset
            )
        }

        try await withThrowingTaskGroup(of: Void.self) { group in
            for settings in allSettings {
                group.addTask {
                    try await repository.save(settings)
                }
            }
            try await group.waitForAll()
        }

        let restarted = LocalJSONPracticeSettingsRepository(
            snapshotURL: snapshotURL
        )
        for expected in allSettings {
            let restored = try await restarted.settings(for: expected.profileID)
            XCTAssertEqual(restored, expected)
        }

        let snapshot = try decodeSnapshot(at: snapshotURL)
        let expectedIDs = allSettings.map(\.profileID).sorted(by: idOrder)
        XCTAssertEqual(snapshot.settings.map(\.profileID), expectedIDs)
        let leftoverFiles = try FileManager.default.contentsOfDirectory(
            atPath: snapshotURL.deletingLastPathComponent().path
        ).filter { $0.hasSuffix(".tmp") }
        XCTAssertTrue(leftoverFiles.isEmpty)
    }

    func testWriteFailureDoesNotCommitCandidateToActorState() async throws {
        let snapshotURL = try makeSnapshotURL()
        let repository = LocalJSONPracticeSettingsRepository(
            snapshotURL: snapshotURL
        )
        let initial = try await repository.settings(for: Self.firstProfileID)
        XCTAssertNil(initial)

        let blockingParent = snapshotURL.deletingLastPathComponent()
        try FileManager.default.removeItem(at: blockingParent)
        try Data("keep me".utf8).write(to: blockingParent)

        do {
            try await repository.save(
                settings(
                    profileID: Self.firstProfileID,
                    readNewLimit: 5
                )
            )
            XCTFail("Expected an atomic-write failure")
        } catch let error as LocalPracticeSettingsRepositoryError {
            guard case .writeFailed = error else {
                return XCTFail("Unexpected error: \(error)")
            }
        }

        let afterFailure = try await repository.settings(
            for: Self.firstProfileID
        )
        XCTAssertNil(afterFailure)
        XCTAssertEqual(
            try Data(contentsOf: blockingParent),
            Data("keep me".utf8)
        )
    }

    private static let firstProfileID = ProfileID(
        rawValue: UUID(uuidString: "92000000-0000-0000-0000-000000000001")!
    )
    private static let secondProfileID = ProfileID(
        rawValue: UUID(uuidString: "92000000-0000-0000-0000-000000000002")!
    )

    private static func makeSettings(
        profileID: ProfileID,
        readNewLimit: Int,
        order: QuestContentOrder = .newThenReview
    ) -> ProfilePracticeSettings {
        ProfilePracticeSettings(
            profileID: profileID,
            read: LearningRouteSettings(
                newWordLimit: readNewLimit,
                reviewWordLimit: 4,
                contentOrder: order,
                emergencyAfterSeconds: 180
            ),
            write: LearningRouteSettings(
                newWordLimit: 3,
                reviewWordLimit: 6,
                contentOrder: .reviewThenNew,
                emergencyAfterSeconds: 300
            )
        )
    }

    private func settings(
        profileID: ProfileID,
        readNewLimit: Int,
        order: QuestContentOrder = .newThenReview
    ) -> ProfilePracticeSettings {
        Self.makeSettings(
            profileID: profileID,
            readNewLimit: readNewLimit,
            order: order
        )
    }

    private func idOrder(_ lhs: ProfileID, _ rhs: ProfileID) -> Bool {
        lhs.rawValue.uuidString < rhs.rawValue.uuidString
    }

    private func makeSnapshotURL() throws -> URL {
        let directoryURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(
                "TadaWordsPracticeSettingsTests-\(UUID().uuidString)",
                isDirectory: true
            )
        try FileManager.default.createDirectory(
            at: directoryURL,
            withIntermediateDirectories: true
        )
        addTeardownBlock {
            try? FileManager.default.removeItem(at: directoryURL)
        }
        return directoryURL.appendingPathComponent("practice-settings.json")
    }

    private func encodeSnapshot(
        _ snapshot: PracticeSettingsSnapshot
    ) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return try encoder.encode(snapshot)
    }

    private func decodeSnapshot(
        at snapshotURL: URL
    ) throws -> PracticeSettingsSnapshot {
        try JSONDecoder().decode(
            PracticeSettingsSnapshot.self,
            from: Data(contentsOf: snapshotURL)
        )
    }

    private func assertInvalidJSON(
        operation: () async throws -> Void
    ) async {
        do {
            try await operation()
            XCTFail("Expected invalid settings JSON")
        } catch let error as LocalPracticeSettingsRepositoryError {
            guard case .invalidJSON = error else {
                return XCTFail("Unexpected error: \(error)")
            }
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }
}
