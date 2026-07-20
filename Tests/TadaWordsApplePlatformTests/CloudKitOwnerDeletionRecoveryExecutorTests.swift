@preconcurrency import CloudKit
import Foundation
import TadaWordsDomain
import XCTest

@testable import TadaWordsApplePlatform

final class CloudKitOwnerDeletionRecoveryExecutorTests: XCTestCase {
    func testOwnerLedgerFetchProofRejectsMissingPerItemResult() {
        let recordID = CloudKitFamilyDeletionLedgerCodec.recordID(
            for: ProfileID()
        )
        let incompleteResults: [CKRecord.ID: Result<CKRecord, any Error>] = [:]

        XCTAssertThrowsError(
            try CloudKitOwnerDeletionLedgerFetchProof.records(
                requestedRecordIDs: [recordID],
                results: incompleteResults
            )
        ) { error in
            guard
                case .operationFailed(let message) =
                    error as? CloudKitFamilySyncError
            else {
                return XCTFail("Expected a fail-closed ledger fetch proof error")
            }
            XCTAssertTrue(message.contains(recordID.recordName))
        }
    }

    func testOwnerLedgerFetchProofAcceptsExplicitUnknownItemAbsence() throws {
        let recordID = CloudKitFamilyDeletionLedgerCodec.recordID(
            for: ProfileID()
        )
        let results: [CKRecord.ID: Result<CKRecord, any Error>] = [
            recordID: .failure(cloudError(.unknownItem))
        ]

        XCTAssertEqual(
            try CloudKitOwnerDeletionLedgerFetchProof.records(
                requestedRecordIDs: [recordID],
                results: results
            ),
            []
        )
    }

    func testTerminalDeletionProofRejectsMissingPerItemResult() {
        XCTAssertThrowsError(
            try CloudKitTerminalDeletionProof.require(
                nil,
                acceptingAbsenceCodes: [.unknownItem],
                operation: "proof unavailable"
            )
        ) { error in
            guard
                case .operationFailed(let message) =
                    error as? CloudKitFamilySyncError
            else {
                return XCTFail("Expected a fail-closed missing-proof error")
            }
            XCTAssertEqual(message, "proof unavailable")
        }
    }

    func testTerminalDeletionProofAcceptsOnlySuccessOrExplicitAbsence() {
        let success: Result<Void, any Error> = .success(())
        let absent: Result<Void, any Error> = .failure(
            cloudError(.zoneNotFound)
        )
        let transient: Result<Void, any Error> = .failure(
            cloudError(.networkFailure)
        )

        XCTAssertNoThrow(
            try CloudKitTerminalDeletionProof.require(
                success,
                acceptingAbsenceCodes: [.zoneNotFound],
                operation: "unused"
            )
        )
        XCTAssertNoThrow(
            try CloudKitTerminalDeletionProof.require(
                absent,
                acceptingAbsenceCodes: [.zoneNotFound],
                operation: "unused"
            )
        )
        XCTAssertThrowsError(
            try CloudKitTerminalDeletionProof.require(
                transient,
                acceptingAbsenceCodes: [.zoneNotFound],
                operation: "unused"
            )
        ) { error in
            XCTAssertEqual((error as? CKError)?.code, .networkFailure)
        }
    }

    @MainActor
    func testRecoveryErasesZoneBeforeAtomicReceiptAndTerminalCommit() async throws {
        var events: [String] = []
        let expectedReceiptID = UUID()

        let receiptID = try await CloudKitOwnerDeletionRecoveryExecutor().recover(
            eraseZone: {
                events.append("erase-zone")
            },
            commitRecovery: {
                events.append("commit-recovery")
                return expectedReceiptID
            }
        )

        XCTAssertEqual(receiptID, expectedReceiptID)
        XCTAssertEqual(
            events,
            ["erase-zone", "commit-recovery"]
        )
    }

    @MainActor
    func testEraseFailureStopsBeforeReceiptOrTerminalState() async {
        var events: [String] = []

        do {
            _ = try await CloudKitOwnerDeletionRecoveryExecutor().recover(
                eraseZone: {
                    events.append("erase-zone")
                    throw RecoveryExecutorTestError.erase
                },
                commitRecovery: {
                    events.append("unexpected-commit")
                    return UUID()
                }
            )
            XCTFail("Recovery should surface the zone erasure failure")
        } catch {
            XCTAssertEqual(error as? RecoveryExecutorTestError, .erase)
        }

        XCTAssertEqual(events, ["erase-zone"])
    }

    @MainActor
    func testAtomicCommitFailureSurfacesAfterZoneErasure() async {
        var events: [String] = []

        do {
            _ = try await CloudKitOwnerDeletionRecoveryExecutor().recover(
                eraseZone: {
                    events.append("erase-zone")
                },
                commitRecovery: {
                    events.append("commit-recovery")
                    throw RecoveryExecutorTestError.commit
                }
            )
            XCTFail("Recovery should surface the durable receipt failure")
        } catch {
            XCTAssertEqual(error as? RecoveryExecutorTestError, .commit)
        }

        XCTAssertEqual(events, ["erase-zone", "commit-recovery"])
    }

    @MainActor
    func testCommitFailureCanRetryAfterIdempotentZoneErase() async throws {
        var events: [String] = []
        let stableReceiptID = UUID()
        var zoneWasErased = false
        var commitAttemptCount = 0

        func recover() async throws -> UUID {
            try await CloudKitOwnerDeletionRecoveryExecutor().recover(
                eraseZone: {
                    if zoneWasErased {
                        events.append("erase-zone-noop")
                    } else {
                        zoneWasErased = true
                        events.append("erase-zone")
                    }
                },
                commitRecovery: {
                    commitAttemptCount += 1
                    events.append("commit-recovery-\(commitAttemptCount)")
                    if commitAttemptCount == 1 {
                        throw RecoveryExecutorTestError.commit
                    }
                    return stableReceiptID
                }
            )
        }

        do {
            _ = try await recover()
            XCTFail("The first atomic recovery commit should fail")
        } catch {
            XCTAssertEqual(error as? RecoveryExecutorTestError, .commit)
        }

        XCTAssertTrue(zoneWasErased)

        let retriedReceiptID = try await recover()

        XCTAssertEqual(retriedReceiptID, stableReceiptID)
        XCTAssertEqual(
            events,
            [
                "erase-zone",
                "commit-recovery-1",
                "erase-zone-noop",
                "commit-recovery-2",
            ]
        )
    }
}

private func cloudError(_ code: CKError.Code) -> CKError {
    CKError(
        _nsError: NSError(
            domain: CKErrorDomain,
            code: code.rawValue
        )
    )
}

private enum RecoveryExecutorTestError: Error, Equatable {
    case erase
    case commit
}
