import Foundation
import TadaWordsDomain
import XCTest

@testable import TadaWordsContent

final class FamilySyncApplyTransactionRepositoryTests: XCTestCase {
    func testUnadoptedProfileIDsIncludeChildOnlyAndMixedPendingBatches()
        async throws
    {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let childOnlyID = ProfileID()
        let mixedDeletionID = ProfileID()
        let repository = LocalJSONFamilySyncApplyTransactionRepository(
            snapshotURL: fixture.url
        )
        let childStart = try await repository.begin(
            profileID: childOnlyID,
            records: [fixture.record(profileID: childOnlyID, counter: 1)],
            at: fixture.now
        )
        _ = try await repository.markCommitted(
            transactionID: try XCTUnwrap(childStart.pendingValue).id,
            at: fixture.now
        )
        _ = try await repository.begin(
            profileID: mixedDeletionID,
            records: [
                fixture.record(profileID: mixedDeletionID, counter: 2),
                try fixture.deletionRecord(profileID: mixedDeletionID),
            ],
            at: fixture.now
        )

        let profileIDs = try await repository.unadoptedProfileIDs()
        XCTAssertEqual(profileIDs, [childOnlyID, mixedDeletionID])

        try await repository.discardUnadoptedProfileState()
        let hasUnadoptedState = try await repository.hasUnadoptedProfileState()
        XCTAssertFalse(hasUnadoptedState)
    }

    func testFirstRunRediscoveryDiscardAllowsRefetchButRetainsDeletionReceipt()
        async throws
    {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let unadoptedProfileID = ProfileID()
        let deletedProfileID = ProfileID()
        let repository = LocalJSONFamilySyncApplyTransactionRepository(
            snapshotURL: fixture.url
        )
        let unadoptedRecords = [
            fixture.record(profileID: unadoptedProfileID, counter: 1)
        ]
        let unadoptedStart = try await repository.begin(
            profileID: unadoptedProfileID,
            records: unadoptedRecords,
            at: fixture.now
        )
        _ = try await repository.markCommitted(
            transactionID: try XCTUnwrap(unadoptedStart.pendingValue).id,
            at: fixture.now
        )
        let deletionStart = try await repository.begin(
            profileID: deletedProfileID,
            records: [try fixture.deletionRecord(profileID: deletedProfileID)],
            at: fixture.now
        )
        let deletionReceipt = try await repository.markCommitted(
            transactionID: try XCTUnwrap(deletionStart.pendingValue).id,
            at: fixture.now
        )
        try await repository.discardUnadoptedProfileState()

        let persisted = try InspectableSnapshotJSONCodec.makeDecoder().decode(
            FamilySyncApplyTransactionSnapshot.self,
            from: Data(contentsOf: fixture.url)
        )
        XCTAssertTrue(persisted.pending.isEmpty)
        XCTAssertEqual(persisted.lastCommitted, [deletionReceipt])
        let refetched = try await repository.begin(
            profileID: unadoptedProfileID,
            records: unadoptedRecords,
            at: fixture.now.addingTimeInterval(1)
        )
        XCTAssertNotNil(refetched.pendingValue)
    }

    func testFirstRunRediscoveryDiscardStripsPrivatePayloadFromPendingDeletion()
        async throws
    {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let deletedProfileID = ProfileID()
        let privateRecord = fixture.record(
            profileID: deletedProfileID,
            counter: 2
        )
        let deletionRecord = try fixture.deletionRecord(
            profileID: deletedProfileID
        )
        let repository = LocalJSONFamilySyncApplyTransactionRepository(
            snapshotURL: fixture.url
        )
        let start = try await repository.begin(
            profileID: deletedProfileID,
            records: [privateRecord, deletionRecord],
            at: fixture.now
        )
        let originalTransactionID = try XCTUnwrap(start.pendingValue).id

        try await repository.discardUnadoptedProfileState()

        let pending = try await repository.pendingTransactions()
        let retained = try XCTUnwrap(pending.first)
        let hasUnadoptedState =
            try await repository
            .hasUnadoptedProfileState()
        XCTAssertEqual(retained.id, originalTransactionID)
        XCTAssertEqual(retained.records, [deletionRecord])
        XCTAssertFalse(hasUnadoptedState)
    }

    func testPendingPayloadSurvivesRestartThenCommitLeavesOnlyMinimalReceipt()
        async throws
    {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let profileID = ProfileID()
        let records = [fixture.record(profileID: profileID, counter: 4)]
        var repository = LocalJSONFamilySyncApplyTransactionRepository(
            snapshotURL: fixture.url
        )

        let started = try await repository.begin(
            profileID: profileID,
            records: records,
            at: fixture.now
        )
        let pending = try XCTUnwrap(started.pendingValue)

        repository = LocalJSONFamilySyncApplyTransactionRepository(
            snapshotURL: fixture.url
        )
        let restartedPending = try await repository.pendingTransactions()
        XCTAssertEqual(
            restartedPending,
            [pending]
        )
        let receipt = try await repository.markCommitted(
            transactionID: pending.id,
            at: fixture.now.addingTimeInterval(1)
        )

        XCTAssertEqual(receipt.profileID, profileID)
        XCTAssertEqual(receipt.recordCount, 1)
        XCTAssertEqual(receipt.affectedKinds, [.profile])
        XCTAssertFalse(receipt.deletedProfile)
        let remainingPending = try await repository.pendingTransactions()
        XCTAssertTrue(remainingPending.isEmpty)

        let persisted = try InspectableSnapshotJSONCodec.makeDecoder().decode(
            FamilySyncApplyTransactionSnapshot.self,
            from: Data(contentsOf: fixture.url)
        )
        XCTAssertTrue(persisted.pending.isEmpty)
        XCTAssertEqual(persisted.lastCommitted, [receipt])
    }

    func testBeginIsIdempotentBeforeAndAfterCommit() async throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let profileID = ProfileID()
        let records = [fixture.record(profileID: profileID, counter: 1)]
        let repository = LocalJSONFamilySyncApplyTransactionRepository(
            snapshotURL: fixture.url
        )
        let tokenBefore = try await repository.committedReceiptToken()

        let first = try await repository.begin(
            profileID: profileID,
            records: records,
            at: fixture.now
        )
        let second = try await repository.begin(
            profileID: profileID,
            records: records,
            at: fixture.now.addingTimeInterval(1)
        )
        XCTAssertEqual(second, first)
        let transaction = try XCTUnwrap(first.pendingValue)
        let receipt = try await repository.markCommitted(
            transactionID: transaction.id,
            at: fixture.now.addingTimeInterval(2)
        )
        let tokenAfter = try await repository.committedReceiptToken()
        XCTAssertNotEqual(tokenAfter, tokenBefore)

        let afterCommit = try await repository.begin(
            profileID: profileID,
            records: records,
            at: fixture.now.addingTimeInterval(3)
        )
        XCTAssertEqual(afterCommit, .alreadyCommitted(receipt))
        let tokenAfterReplay = try await repository.committedReceiptToken()
        XCTAssertEqual(
            tokenAfterReplay,
            tokenAfter,
            "Idempotent replay must not report phantom background data."
        )
    }

    func testDifferentBatchCannotReplaceUnfinishedPayload() async throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let profileID = ProfileID()
        let repository = LocalJSONFamilySyncApplyTransactionRepository(
            snapshotURL: fixture.url
        )
        let original = fixture.record(profileID: profileID, counter: 1)
        let replacement = fixture.record(profileID: profileID, counter: 2)
        _ = try await repository.begin(
            profileID: profileID,
            records: [original],
            at: fixture.now
        )

        do {
            _ = try await repository.begin(
                profileID: profileID,
                records: [replacement],
                at: fixture.now
            )
            XCTFail("Expected the unfinished batch to remain authoritative")
        } catch {
            XCTAssertEqual(
                error as? FamilySyncApplyTransactionError,
                .pendingBatchConflict(profileID)
            )
        }
        let pending = try await repository.pendingTransactions()
        XCTAssertEqual(pending.first?.records, [original])
    }

    func testReceiptStreamReplaysDurableStateToLateSubscriber() async throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let profileID = ProfileID()
        let repository = LocalJSONFamilySyncApplyTransactionRepository(
            snapshotURL: fixture.url
        )
        let start = try await repository.begin(
            profileID: profileID,
            records: [fixture.record(profileID: profileID, counter: 8)],
            at: fixture.now
        )
        let transaction = try XCTUnwrap(start.pendingValue)
        let committed = try await repository.markCommitted(
            transactionID: transaction.id,
            at: fixture.now.addingTimeInterval(1)
        )

        let restarted = LocalJSONFamilySyncApplyTransactionRepository(
            snapshotURL: fixture.url
        )
        let stream = await restarted.committedReceipts()
        var iterator = stream.makeAsyncIterator()
        let replayed = await iterator.next()

        XCTAssertEqual(replayed, committed)
    }

    func testCorruptSnapshotFailsClosedAndPreservesOriginalBytes() async throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let corrupt = Data("not-json-do-not-replace".utf8)
        try corrupt.write(to: fixture.url)
        let repository = LocalJSONFamilySyncApplyTransactionRepository(
            snapshotURL: fixture.url
        )

        do {
            _ = try await repository.pendingTransactions()
            XCTFail("Expected corrupt state to fail closed")
        } catch {
            XCTAssertEqual(
                error as? FamilySyncApplyTransactionError,
                .corruptSnapshot
            )
        }
        XCTAssertEqual(try Data(contentsOf: fixture.url), corrupt)
    }
}

extension FamilySyncApplyTransactionStart {
    fileprivate var pendingValue: FamilySyncPendingApplyTransaction? {
        guard case .pending(let transaction) = self else { return nil }
        return transaction
    }
}

private struct Fixture {
    let directory: URL
    let url: URL
    let now = Date(timeIntervalSince1970: 2_180_000_000)

    init() throws {
        directory = FileManager.default.temporaryDirectory.appendingPathComponent(
            "TadaApplyTransaction-\(UUID().uuidString)",
            isDirectory: true
        )
        try FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true
        )
        url = directory.appendingPathComponent("apply-transactions.json")
    }

    func record(
        profileID: ProfileID,
        counter: UInt64
    ) -> FamilySyncRecord {
        FamilySyncRecord(
            recordName: "profile-\(profileID)",
            profileID: profileID,
            kind: .profile,
            payload: Data("private-profile-payload-\(counter)".utf8),
            updatedAt: now,
            deviceID: "remote",
            logicalRevision: FamilySyncLogicalRevision(
                counter: counter,
                deviceID: "remote"
            )
        )
    }

    func deletionRecord(profileID: ProfileID) throws -> FamilySyncRecord {
        let tombstone = ProfileDeletionTombstone(
            profileID: profileID,
            deletedAt: now
        )
        return FamilySyncRecord(
            recordName: "profile-\(profileID)",
            profileID: profileID,
            kind: .profileDeletion,
            payload: try JSONEncoder().encode(tombstone),
            updatedAt: now,
            deviceID: "remote",
            isDeleted: true,
            logicalRevision: FamilySyncLogicalRevision(
                counter: 1,
                deviceID: "remote"
            )
        )
    }

    func remove() {
        try? FileManager.default.removeItem(at: directory)
    }
}
