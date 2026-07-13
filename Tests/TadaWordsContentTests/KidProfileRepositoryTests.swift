import Foundation
import TadaWordsContent
import TadaWordsDomain
import XCTest

final class KidProfileRepositoryTests: XCTestCase {
    func testMissingFileLoadsEmptyAndIsCreatedOnlyBySave() async throws {
        let snapshotURL = try makeSnapshotURL()
        let repository = LocalJSONKidProfileRepository(
            snapshotURL: snapshotURL
        )

        let initialProfiles = try await repository.profiles()
        let missingProfile = try await repository.profile(id: Self.firstID)
        XCTAssertEqual(initialProfiles, [])
        XCTAssertNil(missingProfile)
        XCTAssertFalse(FileManager.default.fileExists(atPath: snapshotURL.path))

        try await repository.save(Self.fullProfile)

        XCTAssertTrue(FileManager.default.fileExists(atPath: snapshotURL.path))
        let text = try String(contentsOf: snapshotURL, encoding: .utf8)
        XCTAssertTrue(text.contains("\"schemaVersion\""))
        XCTAssertTrue(text.contains("\"profiles\""))
        XCTAssertTrue(text.contains("Mia"))
    }

    func testRestartPreservesCompleteProfileAndStableIdentity() async throws {
        let snapshotURL = try makeSnapshotURL()
        let firstRepository = LocalJSONKidProfileRepository(
            snapshotURL: snapshotURL
        )
        try await firstRepository.save(Self.fullProfile)

        let restartedRepository = LocalJSONKidProfileRepository(
            snapshotURL: snapshotURL
        )

        let restoredProfile = try await restartedRepository.profile(
            id: Self.fullProfile.id
        )
        let restoredProfiles = try await restartedRepository.profiles()
        XCTAssertEqual(restoredProfile, Self.fullProfile)
        XCTAssertEqual(restoredProfiles, [Self.fullProfile])
    }

    func testProfilesUseCreatedAtThenIDOrderingAcrossRestart() async throws {
        let snapshotURL = try makeSnapshotURL()
        let repository = LocalJSONKidProfileRepository(
            snapshotURL: snapshotURL
        )
        let sharedDate = Date(timeIntervalSince1970: 2_100_000_000)
        let earlier = profile(
            id: Self.thirdID,
            name: "Earlier",
            createdAt: sharedDate.addingTimeInterval(-1)
        )
        let lowerID = profile(
            id: Self.firstID,
            name: "Lower ID",
            createdAt: sharedDate
        )
        let higherID = profile(
            id: Self.secondID,
            name: "Higher ID",
            createdAt: sharedDate
        )

        try await repository.save(higherID)
        try await repository.save(earlier)
        try await repository.save(lowerID)

        let expected = [earlier, lowerID, higherID]
        let storedProfiles = try await repository.profiles()
        XCTAssertEqual(storedProfiles, expected)
        let restartedRepository = LocalJSONKidProfileRepository(
            snapshotURL: snapshotURL
        )
        let restoredProfiles = try await restartedRepository.profiles()
        XCTAssertEqual(restoredProfiles, expected)
    }

    func testUpsertCanChangeMutableProfileChoicesWithoutChangingIdentity()
        async throws
    {
        let snapshotURL = try makeSnapshotURL()
        let repository = LocalJSONKidProfileRepository(
            snapshotURL: snapshotURL
        )
        let original = profile(
            id: Self.firstID,
            name: "Mia",
            createdAt: Self.creationDate
        )
        let updated = KidProfile(
            id: original.id,
            displayName: "Mimi",
            avatar: .photo(assetID: "portrait-2", source: .camera),
            selectedWorld: .pawsAndPines,
            voiceprintStatus: .needsRefresh,
            createdAt: original.createdAt
        )

        try await repository.save(original)
        try await repository.save(updated)

        let updatedProfiles = try await repository.profiles()
        let restartedRepository = LocalJSONKidProfileRepository(
            snapshotURL: snapshotURL
        )
        let restoredProfile = try await restartedRepository.profile(
            id: original.id
        )
        XCTAssertEqual(updatedProfiles, [updated])
        XCTAssertEqual(restoredProfile, updated)
    }

    func testIdenticalSaveAndMissingDeleteDoNotRewriteSnapshot() async throws {
        let snapshotURL = try makeSnapshotURL()
        let repository = LocalJSONKidProfileRepository(
            snapshotURL: snapshotURL
        )
        try await repository.save(Self.fullProfile)
        let savedData = try Data(contentsOf: snapshotURL)

        try await repository.save(Self.fullProfile)
        XCTAssertEqual(try Data(contentsOf: snapshotURL), savedData)

        try await repository.delete(id: Self.secondID)
        XCTAssertEqual(try Data(contentsOf: snapshotURL), savedData)

        try await repository.delete(id: Self.fullProfile.id)
        let deletedData = try Data(contentsOf: snapshotURL)
        XCTAssertNotEqual(deletedData, savedData)
        try await repository.delete(id: Self.fullProfile.id)
        XCTAssertEqual(try Data(contentsOf: snapshotURL), deletedData)
    }

    func testDifferentCreatedAtForExistingIDIsTypedConflictAndDoesNotMutate()
        async throws
    {
        let snapshotURL = try makeSnapshotURL()
        let repository = LocalJSONKidProfileRepository(
            snapshotURL: snapshotURL
        )
        let original = profile(
            id: Self.firstID,
            name: "Mia",
            createdAt: Self.creationDate
        )
        let conflicting = profile(
            id: original.id,
            name: "Replacement",
            createdAt: Self.creationDate.addingTimeInterval(1)
        )
        try await repository.save(original)
        let originalData = try Data(contentsOf: snapshotURL)

        do {
            try await repository.save(conflicting)
            XCTFail("Expected a created-at conflict")
        } catch let error as KidProfileRepositoryError {
            XCTAssertEqual(
                error,
                .conflictingCreatedAt(
                    profileID: original.id,
                    existing: original.createdAt,
                    incoming: conflicting.createdAt
                )
            )
        }

        let profilesAfterConflict = try await repository.profiles()
        XCTAssertEqual(profilesAfterConflict, [original])
        XCTAssertEqual(try Data(contentsOf: snapshotURL), originalData)
    }

    func testProfilesRemainIsolatedAcrossLookupUpdateAndDelete() async throws {
        let repository = InMemoryKidProfileRepository()
        let first = profile(
            id: Self.firstID,
            name: "Mia",
            createdAt: Self.creationDate
        )
        let second = profile(
            id: Self.secondID,
            name: "Leo",
            createdAt: Self.creationDate.addingTimeInterval(1)
        )
        try await repository.save(first)
        try await repository.save(second)

        let updatedFirst = KidProfile(
            id: first.id,
            displayName: "Mimi",
            avatar: .cartoonAnimal(assetID: "fox"),
            selectedWorld: .buildItBay,
            voiceprintStatus: .notEnrolled,
            createdAt: first.createdAt
        )
        try await repository.save(updatedFirst)

        let storedFirst = try await repository.profile(id: first.id)
        let storedSecond = try await repository.profile(id: second.id)
        XCTAssertEqual(storedFirst, updatedFirst)
        XCTAssertEqual(storedSecond, second)
        try await repository.delete(id: first.id)
        let deletedFirst = try await repository.profile(id: first.id)
        let remainingProfiles = try await repository.profiles()
        XCTAssertNil(deletedFirst)
        XCTAssertEqual(remainingProfiles, [second])
    }

    func testCorruptFileIsPreservedLatchedAndReloadableAfterRepair()
        async throws
    {
        let snapshotURL = try makeSnapshotURL()
        let corruptData = Data("{ definitely not json".utf8)
        try corruptData.write(to: snapshotURL)
        let repository = LocalJSONKidProfileRepository(
            snapshotURL: snapshotURL
        )

        await assertInvalidJSON {
            _ = try await repository.profiles()
        }
        await assertInvalidJSON {
            try await repository.save(Self.fullProfile)
        }
        XCTAssertEqual(try Data(contentsOf: snapshotURL), corruptData)

        try encodeSnapshot(KidProfileSnapshot(profiles: [])).write(
            to: snapshotURL
        )
        await assertInvalidJSON {
            _ = try await repository.profiles()
        }

        try await repository.reloadFromDisk()
        let restoredProfiles = try await repository.profiles()
        XCTAssertEqual(restoredProfiles, [])
    }

    func testDuplicateProfileSnapshotIsTypedInvalidAndPreserved() async throws {
        let snapshotURL = try makeSnapshotURL()
        let duplicate = profile(
            id: Self.fullProfile.id,
            name: "Duplicate",
            createdAt: Self.fullProfile.createdAt
        )
        let invalidData = try encodeSnapshot(
            KidProfileSnapshot(profiles: [Self.fullProfile, duplicate])
        )
        try invalidData.write(to: snapshotURL)
        let repository = LocalJSONKidProfileRepository(
            snapshotURL: snapshotURL
        )

        do {
            _ = try await repository.profiles()
            XCTFail("Expected a duplicate-profile error")
        } catch let error as LocalKidProfileRepositoryError {
            XCTAssertEqual(
                error,
                .invalidSnapshot(
                    snapshotURL: snapshotURL,
                    issue: .duplicateProfileID(Self.fullProfile.id)
                )
            )
        }

        XCTAssertEqual(try Data(contentsOf: snapshotURL), invalidData)
    }

    func testUnsupportedSchemaIsTypedAndPreserved() async throws {
        let snapshotURL = try makeSnapshotURL()
        let unsupportedData = try encodeSnapshot(
            KidProfileSnapshot(schemaVersion: 999, profiles: [])
        )
        try unsupportedData.write(to: snapshotURL)
        let repository = LocalJSONKidProfileRepository(
            snapshotURL: snapshotURL
        )

        do {
            _ = try await repository.profiles()
            XCTFail("Expected an unsupported-schema error")
        } catch let error as LocalKidProfileRepositoryError {
            XCTAssertEqual(
                error,
                .unsupportedSchemaVersion(
                    snapshotURL: snapshotURL,
                    found: 999,
                    supported: KidProfileSnapshot.currentSchemaVersion
                )
            )
        }

        XCTAssertEqual(try Data(contentsOf: snapshotURL), unsupportedData)
    }

    func testWriteFailureDoesNotCommitCandidateToActorState() async throws {
        let snapshotURL = try makeSnapshotURL()
        let repository = LocalJSONKidProfileRepository(
            snapshotURL: snapshotURL
        )
        let initialProfiles = try await repository.profiles()
        XCTAssertEqual(initialProfiles, [])

        let blockingParent = snapshotURL.deletingLastPathComponent()
        try FileManager.default.removeItem(at: blockingParent)
        try Data("keep me".utf8).write(to: blockingParent)

        do {
            try await repository.save(Self.fullProfile)
            XCTFail("Expected an atomic-write failure")
        } catch let error as LocalKidProfileRepositoryError {
            guard case .writeFailed = error else {
                return XCTFail("Unexpected error: \(error)")
            }
        }

        let profilesAfterFailure = try await repository.profiles()
        XCTAssertEqual(profilesAfterFailure, [])
        XCTAssertEqual(
            try Data(contentsOf: blockingParent),
            Data("keep me".utf8)
        )
    }

    func testConcurrentSavesAreCompleteOrderedAndRestartable() async throws {
        let snapshotURL = try makeSnapshotURL()
        let repository = LocalJSONKidProfileRepository(
            snapshotURL: snapshotURL
        )
        let baseDate = Date(timeIntervalSince1970: 2_200_000_000)
        let profiles = (0..<32).map { offset in
            profile(
                id: ProfileID(),
                name: "Kid \(offset)",
                createdAt: baseDate.addingTimeInterval(Double(offset % 4))
            )
        }

        try await withThrowingTaskGroup(of: Void.self) { group in
            for profile in profiles {
                group.addTask {
                    try await repository.save(profile)
                }
            }
            try await group.waitForAll()
        }

        let stored = try await repository.profiles()
        XCTAssertEqual(Set(stored), Set(profiles))
        XCTAssertEqual(stored, stableOrder(profiles))
        let restartedRepository = LocalJSONKidProfileRepository(
            snapshotURL: snapshotURL
        )
        let restoredProfiles = try await restartedRepository.profiles()
        XCTAssertEqual(restoredProfiles, stored)

        let leftoverFiles = try FileManager.default.contentsOfDirectory(
            atPath: snapshotURL.deletingLastPathComponent().path
        ).filter { $0.hasSuffix(".tmp") }
        XCTAssertTrue(leftoverFiles.isEmpty)
    }

    private static let firstID = ProfileID(
        rawValue: UUID(uuidString: "00000000-0000-0000-0000-000000000001")!
    )
    private static let secondID = ProfileID(
        rawValue: UUID(uuidString: "00000000-0000-0000-0000-000000000002")!
    )
    private static let thirdID = ProfileID(
        rawValue: UUID(uuidString: "00000000-0000-0000-0000-000000000003")!
    )
    private static let creationDate = Date(
        timeIntervalSince1970: 2_000_000_000.123_456
    )
    private static let enrollmentDate = Date(
        timeIntervalSince1970: 2_000_000_030.654_321
    )
    private static let fullProfile = KidProfile(
        id: firstID,
        displayName: "Mia",
        avatar: .photo(assetID: "portrait-1", source: .photoLibrary),
        selectedWorld: .moonpetalKingdom,
        voiceprintStatus: .enrolled(
            modelVersion: "voiceprint-v1",
            enrolledAt: enrollmentDate
        ),
        createdAt: creationDate
    )

    private static func profile(
        id: ProfileID,
        name: String,
        createdAt: Date
    ) -> KidProfile {
        KidProfile(
            id: id,
            displayName: name,
            avatar: .cartoonAnimal(assetID: "otter"),
            selectedWorld: .buildItBay,
            createdAt: createdAt
        )
    }

    private func profile(
        id: ProfileID,
        name: String,
        createdAt: Date
    ) -> KidProfile {
        Self.profile(id: id, name: name, createdAt: createdAt)
    }

    private func stableOrder(_ profiles: [KidProfile]) -> [KidProfile] {
        profiles.sorted { lhs, rhs in
            if lhs.createdAt != rhs.createdAt {
                return lhs.createdAt < rhs.createdAt
            }
            return lhs.id.rawValue.uuidString < rhs.id.rawValue.uuidString
        }
    }

    private func makeSnapshotURL() throws -> URL {
        let directoryURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(
                "TadaWordsKidProfileTests-\(UUID().uuidString)",
                isDirectory: true
            )
        try FileManager.default.createDirectory(
            at: directoryURL,
            withIntermediateDirectories: true
        )
        addTeardownBlock {
            try? FileManager.default.removeItem(at: directoryURL)
        }
        return directoryURL.appendingPathComponent("kid-profiles.json")
    }

    private func encodeSnapshot(_ snapshot: KidProfileSnapshot) throws -> Data {
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
        } catch let error as LocalKidProfileRepositoryError {
            guard case .invalidJSON = error else {
                return XCTFail("Unexpected error: \(error)")
            }
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }
}
