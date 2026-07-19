import Foundation
import TadaWordsContent
import TadaWordsDomain
import XCTest

final class FamilySyncJournalRepositoryTests: XCTestCase {
    func testOutboxSurvivesRestartAndStaleAcknowledgementCannotClearNewerWrite()
        async throws
    {
        let fixture = try JournalFixture()
        defer { fixture.remove() }
        let firstRepository = LocalJSONFamilySyncJournalRepository(
            snapshotURL: fixture.url
        )
        let first = try await firstRepository.reconcileLocalRecords(
            [fixture.record("cat")],
            deviceID: "device-a",
            now: fixture.now
        )[0]
        try await firstRepository.recordTransportResult(
            acknowledged: [
                FamilySyncChangeAcknowledgement(
                    operation: .save(first)
                )
            ],
            failures: [],
            at: fixture.now
        )

        let second = try await firstRepository.reconcileLocalRecords(
            [fixture.record("dog")],
            deviceID: "device-a",
            now: fixture.now.addingTimeInterval(1)
        )[0]
        XCTAssertGreaterThan(second.logicalRevision, first.logicalRevision)
        try await firstRepository.recordTransportResult(
            acknowledged: [
                FamilySyncChangeAcknowledgement(
                    operation: .save(first)
                )
            ],
            failures: [],
            at: fixture.now.addingTimeInterval(2)
        )

        let restarted = LocalJSONFamilySyncJournalRepository(
            snapshotURL: fixture.url
        )
        let status = try await restarted.durableStatus()
        let pending = try await restarted.pendingChanges(
            using: [second],
            now: fixture.now.addingTimeInterval(3)
        )
        XCTAssertEqual(status.pendingCount, 1)
        XCTAssertEqual(pending.map(\.revision), [second.logicalRevision])
    }

    func testPartialFailureBacksOffOnlyFailedKey() async throws {
        let fixture = try JournalFixture()
        defer { fixture.remove() }
        let repository = LocalJSONFamilySyncJournalRepository(
            snapshotURL: fixture.url
        )
        let records = try await repository.reconcileLocalRecords(
            [fixture.record("cat", suffix: "a"), fixture.record("dog", suffix: "b")],
            deviceID: "device-a",
            now: fixture.now
        )
        let acknowledged = records[0]
        let failed = records[1]
        try await repository.recordTransportResult(
            acknowledged: [
                FamilySyncChangeAcknowledgement(operation: .save(acknowledged))
            ],
            failures: [
                FamilySyncTransportFailure(
                    key: FamilySyncChangeKey(
                        profileID: failed.profileID,
                        recordName: failed.recordName
                    ),
                    category: .connectivity,
                    retryAfter: 30
                )
            ],
            at: fixture.now
        )

        let beforeRetry = try await repository.pendingChanges(
            using: records,
            now: fixture.now.addingTimeInterval(29)
        )
        XCTAssertTrue(beforeRetry.isEmpty)
        let retried = try await repository.pendingChanges(
            using: records,
            now: fixture.now.addingTimeInterval(31)
        )
        let status = try await repository.durableStatus()
        XCTAssertEqual(retried.map(\.key.recordName), [failed.recordName])
        XCTAssertEqual(status.pendingCount, 1)
        XCTAssertEqual(status.condition, .waitingForConnection)
        XCTAssertEqual(status.errorCategory, .connectivity)
        XCTAssertEqual(status.retryCount, 1)
        XCTAssertEqual(
            status.nextRetryAt,
            fixture.now.addingTimeInterval(30)
        )
    }

    func testPhysicalDeletionNeverClearsNewerLocalValue() async throws {
        let fixture = try JournalFixture()
        defer { fixture.remove() }
        let repository = LocalJSONFamilySyncJournalRepository(
            snapshotURL: fixture.url
        )
        let record = try await repository.reconcileLocalRecords(
            [fixture.record("cat")],
            deviceID: "device-a",
            now: fixture.now
        )[0]
        let key = FamilySyncChangeKey(
            profileID: record.profileID,
            recordName: record.recordName
        )
        try await repository.recordAppliedRemote(
            records: [],
            deletions: [FamilySyncRemoteDeletion(key: key)],
            at: fixture.now.addingTimeInterval(1)
        )

        let pending = try await repository.pendingChanges(
            using: [record],
            now: fixture.now.addingTimeInterval(2)
        )
        XCTAssertEqual(pending, [.save(record)])
    }

    func testCorruptSnapshotFailsClosedWithoutReplacement() async throws {
        let fixture = try JournalFixture()
        defer { fixture.remove() }
        let bytes = Data("not-json".utf8)
        try bytes.write(to: fixture.url, options: .atomic)
        let repository = LocalJSONFamilySyncJournalRepository(
            snapshotURL: fixture.url
        )

        do {
            _ = try await repository.durableStatus()
            XCTFail("Expected invalid JSON")
        } catch let error as FamilySyncJournalError {
            guard case .invalidJSON(let url, _) = error else {
                return XCTFail("Unexpected error: \(error)")
            }
            XCTAssertEqual(url, fixture.url)
        }
        XCTAssertEqual(try Data(contentsOf: fixture.url), bytes)
    }

    func testAccountChangeRequeuesProfileDeletionAsSemanticSave() async throws {
        let fixture = try JournalFixture()
        defer { fixture.remove() }
        let repository = LocalJSONFamilySyncJournalRepository(
            snapshotURL: fixture.url
        )
        let tombstone = ProfileDeletionTombstone(
            profileID: fixture.profileID,
            deletedAt: fixture.now
        )
        let raw = FamilySyncRecord(
            recordName: "profile-\(fixture.profileID)",
            profileID: fixture.profileID,
            kind: .profileDeletion,
            payload: try JSONEncoder().encode(tombstone),
            updatedAt: fixture.now,
            deviceID: "raw-device",
            isDeleted: true
        )
        let versioned = try await repository.reconcileLocalRecords(
            [raw],
            deviceID: "device-a",
            now: fixture.now
        )
        try await repository.recordTransportResult(
            acknowledged: [
                FamilySyncChangeAcknowledgement(operation: .save(versioned[0]))
            ],
            failures: [],
            at: fixture.now
        )

        try await repository.invalidateAcknowledgementsForAccountChange(
            at: fixture.now.addingTimeInterval(1)
        )
        let pending = try await repository.pendingChanges(
            using: versioned,
            now: fixture.now.addingTimeInterval(2)
        )
        let status = try await repository.durableStatus()
        XCTAssertEqual(pending, [.save(versioned[0])])
        XCTAssertEqual(status.condition, .iCloudUnavailable)
        XCTAssertEqual(status.errorCategory, .account)
        XCTAssertNil(status.lastSuccessAt)
    }
}

private struct JournalFixture {
    let directory: URL
    let url: URL
    let profileID = ProfileID(
        rawValue: UUID(uuidString: "11111111-2222-3333-4444-555555555555")!
    )
    let now = Date(timeIntervalSince1970: 1_000)

    init() throws {
        directory = FileManager.default.temporaryDirectory.appendingPathComponent(
            "TadaWordsFamilySyncJournal-\(UUID().uuidString)",
            isDirectory: true
        )
        try FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true
        )
        url = directory.appendingPathComponent("journal.json")
    }

    func record(_ payload: String, suffix: String = "profile") -> FamilySyncRecord {
        FamilySyncRecord(
            recordName: "\(suffix)-\(profileID)",
            profileID: profileID,
            kind: .profile,
            payload: Data(payload.utf8),
            updatedAt: now,
            deviceID: "raw-device"
        )
    }

    func remove() {
        try? FileManager.default.removeItem(at: directory)
    }
}
