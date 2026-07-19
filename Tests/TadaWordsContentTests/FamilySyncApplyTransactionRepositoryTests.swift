import Foundation
import TadaWordsDomain
import XCTest

@testable import TadaWordsContent

final class FamilySyncApplyTransactionRepositoryTests: XCTestCase {
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

    func remove() {
        try? FileManager.default.removeItem(at: directory)
    }
}
