import Foundation
import TadaWordsContent
import XCTest

final class FamilySyncPreferenceRepositoryTests: XCTestCase {
    func testMissingPreferenceDefaultsToOptOut() async throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let repository = LocalJSONFamilySyncPreferenceRepository(
            snapshotURL: directory.appendingPathComponent("family-sync.json")
        )

        let isEnabled = try await repository.isEnabled()
        XCTAssertFalse(isEnabled)
    }

    func testExplicitOptInAndOptOutPersistAcrossRestart() async throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let snapshotURL = directory.appendingPathComponent("family-sync.json")
        let consentDate = Date(timeIntervalSince1970: 1_735_689_600)
        let first = LocalJSONFamilySyncPreferenceRepository(snapshotURL: snapshotURL)

        try await first.setEnabled(true, updatedAt: consentDate)

        let enabledRestart = LocalJSONFamilySyncPreferenceRepository(snapshotURL: snapshotURL)
        let isEnabledAfterRestart = try await enabledRestart.isEnabled()
        XCTAssertTrue(isEnabledAfterRestart)
        let enabledSnapshot = try decodeSnapshot(at: snapshotURL)
        XCTAssertEqual(
            enabledSnapshot.disclosureVersion,
            FamilySyncPreferenceSnapshot.currentDisclosureVersion
        )
        XCTAssertEqual(enabledSnapshot.consentedAt, consentDate)

        try await enabledRestart.setEnabled(
            false,
            updatedAt: consentDate.addingTimeInterval(10)
        )

        let disabledRestart = LocalJSONFamilySyncPreferenceRepository(snapshotURL: snapshotURL)
        let isEnabledAfterOptOut = try await disabledRestart.isEnabled()
        XCTAssertFalse(isEnabledAfterOptOut)
    }

    func testStaleDisclosureFailsClosedUntilExplicitlyEnabledAgain() async throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let snapshotURL = directory.appendingPathComponent("family-sync.json")
        let stale = FamilySyncPreferenceSnapshot(
            isEnabled: true,
            disclosureVersion: 0,
            consentedAt: Date(timeIntervalSince1970: 1_735_689_600),
            updatedAt: Date(timeIntervalSince1970: 1_735_689_600)
        )
        try write(stale, to: snapshotURL)
        let repository = LocalJSONFamilySyncPreferenceRepository(snapshotURL: snapshotURL)

        let stalePreferenceIsEnabled = try await repository.isEnabled()
        XCTAssertFalse(stalePreferenceIsEnabled)

        try await repository.setEnabled(
            true,
            updatedAt: Date(timeIntervalSince1970: 1_735_689_700)
        )
        let refreshedPreferenceIsEnabled = try await repository.isEnabled()
        XCTAssertTrue(refreshedPreferenceIsEnabled)
    }

    private func decodeSnapshot(at url: URL) throws -> FamilySyncPreferenceSnapshot {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .secondsSince1970
        return try decoder.decode(
            FamilySyncPreferenceSnapshot.self,
            from: Data(contentsOf: url)
        )
    }

    private func write(
        _ snapshot: FamilySyncPreferenceSnapshot,
        to url: URL
    ) throws {
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .secondsSince1970
        try encoder.encode(snapshot).write(to: url, options: .atomic)
    }

    private func temporaryDirectory() throws -> URL {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(
            "TadaWordsFamilySyncPreference-\(UUID().uuidString)",
            isDirectory: true
        )
        try FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true
        )
        return directory
    }
}
