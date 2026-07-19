import Foundation
import TadaWordsDomain
import XCTest

@testable import TadaWordsContent

final class FamilySyncJournalDurabilityHarnessTests: XCTestCase {
    func testPendingChangeAndAcknowledgedManifestSurviveRepositoryRestart() async throws {
        let fixture = try JournalHarnessFixture()
        defer { fixture.remove() }
        let now = Date(timeIntervalSince1970: 2_100_000_000)
        let raw = fixture.record(name: "profile", payload: "Mia", at: now)

        let firstRepository = fixture.repository()
        let firstVersioned = try await firstRepository.reconcileLocalRecords(
            [raw],
            deviceID: "device-a",
            now: now
        )
        let firstPending = try await firstRepository.pendingChanges(
            using: firstVersioned,
            now: now
        )
        let firstOperation = try XCTUnwrap(firstPending.first)

        let restartedWithPending = fixture.repository()
        let replayed = try await restartedWithPending.pendingChanges(
            using: firstVersioned,
            now: now
        )
        XCTAssertEqual(replayed, [firstOperation])
        let restartedStatus = try await restartedWithPending.durableStatus()
        XCTAssertEqual(restartedStatus.pendingCount, 1)

        try await restartedWithPending.recordTransportResult(
            acknowledged: [FamilySyncChangeAcknowledgement(operation: firstOperation)],
            failures: [],
            at: now.addingTimeInterval(1)
        )

        let restartedAfterAcknowledgement = fixture.repository()
        let stableVersioned = try await restartedAfterAcknowledgement.reconcileLocalRecords(
            [raw],
            deviceID: "device-a",
            now: now.addingTimeInterval(2)
        )
        let afterAcknowledgement = try await restartedAfterAcknowledgement.pendingChanges(
            using: stableVersioned,
            now: now.addingTimeInterval(2)
        )
        XCTAssertTrue(afterAcknowledgement.isEmpty)
        XCTAssertEqual(
            stableVersioned.first?.logicalRevision, firstVersioned.first?.logicalRevision)
    }

    func testOnlyMatchingRevisionAndOperationCanAcknowledgeNewestOutboxEntry() async throws {
        let fixture = try JournalHarnessFixture()
        defer { fixture.remove() }
        let now = Date(timeIntervalSince1970: 2_100_000_100)
        let repository = fixture.repository()
        let firstVersion = try await repository.reconcileLocalRecords(
            [fixture.record(name: "profile", payload: "first", at: now)],
            deviceID: "device-a",
            now: now
        )
        let firstPending = try await repository.pendingChanges(
            using: firstVersion,
            now: now
        )
        let staleOperation = try XCTUnwrap(firstPending.first)
        let secondVersion = try await repository.reconcileLocalRecords(
            [
                fixture.record(
                    name: "profile",
                    payload: "second",
                    at: now.addingTimeInterval(1)
                )
            ],
            deviceID: "device-a",
            now: now.addingTimeInterval(1)
        )
        let newestPending = try await repository.pendingChanges(
            using: secondVersion,
            now: now.addingTimeInterval(1)
        )
        let newestOperation = try XCTUnwrap(newestPending.first)
        XCTAssertGreaterThan(newestOperation.revision, staleOperation.revision)

        try await repository.recordTransportResult(
            acknowledged: [FamilySyncChangeAcknowledgement(operation: staleOperation)],
            failures: [],
            at: now.addingTimeInterval(2)
        )
        var remaining = try await repository.pendingChanges(
            using: secondVersion,
            now: now.addingTimeInterval(2)
        )
        XCTAssertEqual(remaining, [newestOperation])

        let wrongOperationAcknowledgement = FamilySyncChangeAcknowledgement(
            key: newestOperation.key,
            revision: newestOperation.revision,
            operation: .delete
        )
        try await repository.recordTransportResult(
            acknowledged: [wrongOperationAcknowledgement],
            failures: [],
            at: now.addingTimeInterval(3)
        )
        remaining = try await repository.pendingChanges(
            using: secondVersion,
            now: now.addingTimeInterval(3)
        )
        XCTAssertEqual(remaining, [newestOperation])

        try await repository.recordTransportResult(
            acknowledged: [FamilySyncChangeAcknowledgement(operation: newestOperation)],
            failures: [],
            at: now.addingTimeInterval(4)
        )
        remaining = try await repository.pendingChanges(
            using: secondVersion,
            now: now.addingTimeInterval(4)
        )
        XCTAssertTrue(remaining.isEmpty)
    }

    func testPartialSuccessAcknowledgesOneChangeAndBacksOffOnlyFailedChange() async throws {
        let fixture = try JournalHarnessFixture()
        defer { fixture.remove() }
        let now = Date(timeIntervalSince1970: 2_100_000_200)
        let repository = fixture.repository()
        let versioned = try await repository.reconcileLocalRecords(
            [
                fixture.record(name: "profile-a", payload: "A", at: now),
                fixture.record(name: "profile-b", payload: "B", at: now),
            ],
            deviceID: "device-a",
            now: now
        )
        let operations = try await repository.pendingChanges(using: versioned, now: now)
        XCTAssertEqual(operations.count, 2)
        let acknowledgedOperation = operations[0]
        let failedOperation = operations[1]

        try await repository.recordTransportResult(
            acknowledged: [
                FamilySyncChangeAcknowledgement(operation: acknowledgedOperation)
            ],
            failures: [
                FamilySyncTransportFailure(
                    key: failedOperation.key,
                    category: .server,
                    retryAfter: 30
                )
            ],
            at: now
        )

        let status = try await repository.durableStatus()
        XCTAssertEqual(status.pendingCount, 1)
        XCTAssertEqual(status.errorCategory, .server)
        let beforeRetry = try await repository.pendingChanges(
            using: versioned,
            now: now.addingTimeInterval(29)
        )
        let atRetry = try await repository.pendingChanges(
            using: versioned,
            now: now.addingTimeInterval(30)
        )
        XCTAssertTrue(beforeRetry.isEmpty)
        XCTAssertEqual(atRetry, [failedOperation])
    }

    func testRetryBackoffGrowsDeterministicallyAndCapsImmediateRetries() async throws {
        let fixture = try JournalHarnessFixture()
        defer { fixture.remove() }
        let now = Date(timeIntervalSince1970: 2_100_000_300)
        let repository = fixture.repository()
        let versioned = try await repository.reconcileLocalRecords(
            [fixture.record(name: "profile", payload: "Mia", at: now)],
            deviceID: "device-a",
            now: now
        )
        let initialPending = try await repository.pendingChanges(
            using: versioned,
            now: now
        )
        let operation = try XCTUnwrap(initialPending.first)
        let failure = FamilySyncTransportFailure(
            key: operation.key,
            category: .connectivity
        )

        try await repository.recordTransportResult(
            acknowledged: [],
            failures: [failure],
            at: now
        )
        let beforeFirstRetry = try await repository.pendingChanges(
            using: versioned,
            now: now.addingTimeInterval(3)
        )
        let atFirstRetry = try await repository.pendingChanges(
            using: versioned,
            now: now.addingTimeInterval(7)
        )
        XCTAssertTrue(beforeFirstRetry.isEmpty)
        XCTAssertEqual(atFirstRetry, [operation])

        try await repository.recordTransportResult(
            acknowledged: [],
            failures: [failure],
            at: now.addingTimeInterval(7)
        )
        let beforeSecondRetry = try await repository.pendingChanges(
            using: versioned,
            now: now.addingTimeInterval(14)
        )
        let atSecondRetry = try await repository.pendingChanges(
            using: versioned,
            now: now.addingTimeInterval(20)
        )
        XCTAssertTrue(beforeSecondRetry.isEmpty)
        XCTAssertEqual(atSecondRetry, [operation])

        let snapshotData = try Data(contentsOf: fixture.snapshotURL)
        let snapshot = try InspectableSnapshotJSONCodec.makeDecoder().decode(
            FamilySyncJournalSnapshot.self,
            from: snapshotData
        )
        XCTAssertEqual(snapshot.outbox.first?.retryCount, 2)
        XCTAssertEqual(snapshot.outbox.first?.errorCategory, .connectivity)
    }

    func testCorruptSnapshotFailsClosedWithoutReplacingForensicBytes() async throws {
        let fixture = try JournalHarnessFixture()
        defer { fixture.remove() }
        let corruptBytes = Data("not-a-family-sync-journal".utf8)
        try corruptBytes.write(to: fixture.snapshotURL, options: .atomic)
        let repository = fixture.repository()

        do {
            _ = try await repository.durableStatus()
            XCTFail("A corrupt journal must never be treated as an empty outbox")
        } catch let error as FamilySyncJournalError {
            guard case .invalidJSON(let snapshotURL, _) = error else {
                return XCTFail("Unexpected journal error: \(error)")
            }
            XCTAssertEqual(snapshotURL, fixture.snapshotURL)
        }

        XCTAssertEqual(try Data(contentsOf: fixture.snapshotURL), corruptBytes)
    }
}

private struct JournalHarnessFixture {
    let directory: URL
    let snapshotURL: URL
    let profileID = ProfileID()

    init() throws {
        directory = FileManager.default.temporaryDirectory.appendingPathComponent(
            "TadaFamilySyncJournalHarness-\(UUID().uuidString)",
            isDirectory: true
        )
        try FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true
        )
        snapshotURL = directory.appendingPathComponent("journal.json")
    }

    func repository() -> LocalJSONFamilySyncJournalRepository {
        LocalJSONFamilySyncJournalRepository(snapshotURL: snapshotURL)
    }

    func record(name: String, payload: String, at date: Date) -> FamilySyncRecord {
        FamilySyncRecord(
            recordName: name,
            profileID: profileID,
            kind: .profile,
            payload: Data(payload.utf8),
            updatedAt: date,
            deviceID: "raw-device"
        )
    }

    func remove() {
        try? FileManager.default.removeItem(at: directory)
    }
}
