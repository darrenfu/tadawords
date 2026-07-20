import Foundation
import TadaWordsContent
import TadaWordsDomain
import XCTest

final class ChildSessionRepositoryTests: XCTestCase {
    func testFutureSchemaCannotBeRepairedByASelectionWrite() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true
        )
        defer { try? FileManager.default.removeItem(at: directory) }
        let snapshotURL = directory.appendingPathComponent("child-session.json")
        let original = try JSONEncoder().encode(
            ChildSessionSnapshot(
                schemaVersion: ChildSessionSnapshot.currentSchemaVersion + 1,
                lastSelectedProfileID: ProfileID()
            )
        )
        try original.write(to: snapshotURL)
        let repository = LocalJSONChildSessionRepository(
            snapshotURL: snapshotURL
        )

        do {
            try await repository.saveLastSelectedProfileID(ProfileID())
            XCTFail("A future child-session schema must not be overwritten.")
        } catch let error as LocalChildSessionRepositoryError {
            guard case .unsupportedSchemaVersion = error else {
                return XCTFail("Unexpected error: \(error)")
            }
        }
        XCTAssertEqual(try Data(contentsOf: snapshotURL), original)
    }

    func testSelectionSurvivesRepositoryRestartAndCanBeCleared() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true
        )
        defer { try? FileManager.default.removeItem(at: directory) }
        let snapshotURL = directory.appendingPathComponent("child-session.json")
        let profileID = ProfileID()

        let first = LocalJSONChildSessionRepository(snapshotURL: snapshotURL)
        try await first.saveLastSelectedProfileID(profileID)

        let restarted = LocalJSONChildSessionRepository(snapshotURL: snapshotURL)
        let restartedProfileID = try await restarted.lastSelectedProfileID()
        XCTAssertEqual(restartedProfileID, profileID)
        try await restarted.clearLastSelectedProfileID()

        let cleared = LocalJSONChildSessionRepository(snapshotURL: snapshotURL)
        let clearedProfileID = try await cleared.lastSelectedProfileID()
        XCTAssertNil(clearedProfileID)
    }

    func testFailedAtomicWriteKeepsPreviouslyLoadedSelection() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true
        )
        defer { try? FileManager.default.removeItem(at: directory) }
        let snapshotURL = directory.appendingPathComponent("child-session.json")
        let originalID = ProfileID()
        let replacementID = ProfileID()
        let repository = LocalJSONChildSessionRepository(snapshotURL: snapshotURL)
        try await repository.saveLastSelectedProfileID(originalID)
        try FileManager.default.setAttributes(
            [.posixPermissions: 0o500],
            ofItemAtPath: directory.path
        )
        defer {
            try? FileManager.default.setAttributes(
                [.posixPermissions: 0o700],
                ofItemAtPath: directory.path
            )
        }

        do {
            try await repository.saveLastSelectedProfileID(replacementID)
            XCTFail("Expected the unwritable directory to reject the snapshot.")
        } catch is LocalChildSessionRepositoryError {
            // Expected.
        }
        let persistedProfileID = try await repository.lastSelectedProfileID()
        XCTAssertEqual(persistedProfileID, originalID)
    }
}
