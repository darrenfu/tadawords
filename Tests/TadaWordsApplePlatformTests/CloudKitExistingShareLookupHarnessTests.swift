@preconcurrency import CloudKit
import Foundation
import XCTest

@testable import TadaWordsApplePlatform

final class CloudKitExistingShareLookupHarnessTests: XCTestCase {
    @MainActor
    func testOwnerAccessEnsuresRecoverableShareBeforeReadingRoot() async throws {
        let records = accessRecords()
        var events: [String] = []

        let loaded = try await CloudKitFamilyAccessShareLoader.load(
            scope: .privateDatabase,
            ensureOwnerShare: {
                events.append("ensure-owner-share")
            },
            fetchRoot: {
                events.append("fetch-root")
                return records.root
            },
            fetchRecord: { recordID in
                events.append("fetch-share")
                XCTAssertEqual(recordID, records.share.recordID)
                return records.share
            }
        )

        XCTAssertEqual(loaded.recordID, records.share.recordID)
        XCTAssertEqual(
            events,
            ["ensure-owner-share", "fetch-root", "fetch-share"]
        )
    }

    @MainActor
    func testParticipantAccessNeverCreatesAPrivateOwnerShare() async throws {
        let records = accessRecords()
        var events: [String] = []

        let loaded = try await CloudKitFamilyAccessShareLoader.load(
            scope: .sharedDatabase,
            ensureOwnerShare: {
                events.append("unexpected-owner-create")
                XCTFail("A shared participant must never create a private owner share")
            },
            fetchRoot: {
                events.append("fetch-root")
                return records.root
            },
            fetchRecord: { _ in
                events.append("fetch-share")
                return records.share
            }
        )

        XCTAssertEqual(loaded.recordID, records.share.recordID)
        XCTAssertEqual(events, ["fetch-root", "fetch-share"])
    }

    @MainActor
    func testTransientOwnerPreparationFailureDoesNotReadOrRecreateAgain() async {
        var events: [String] = []

        do {
            _ = try await CloudKitFamilyAccessShareLoader.load(
                scope: .privateDatabase,
                ensureOwnerShare: {
                    events.append("ensure-owner-share")
                    throw AccessLoaderTestError.transient
                },
                fetchRoot: {
                    events.append("unexpected-root-fetch")
                    throw AccessLoaderTestError.transient
                },
                fetchRecord: { _ in
                    events.append("unexpected-share-fetch")
                    throw AccessLoaderTestError.transient
                }
            )
            XCTFail("Expected the transport's transient error to propagate")
        } catch {
            XCTAssertEqual(error as? AccessLoaderTestError, .transient)
        }

        XCTAssertEqual(events, ["ensure-owner-share"])
    }

    func testTransientPerRecordFailureIsPropagatedInsteadOfRecreatingShare()
        throws
    {
        let recordID = shareRecordID()
        let networkError = cloudError(.networkFailure)
        let result: Result<CKRecord, any Error> = .failure(networkError)

        XCTAssertThrowsError(
            try CloudKitExistingShareLookup.url(
                from: result,
                recordID: recordID
            )
        ) { error in
            XCTAssertEqual((error as? CKError)?.code, .networkFailure)
        }
    }

    func testConfirmedMissingShareIsTheOnlyFailureThatAllowsRecreation()
        throws
    {
        let recordID = shareRecordID()
        let missingError = cloudError(.unknownItem)
        let result: Result<CKRecord, any Error> = .failure(missingError)

        XCTAssertNil(
            try CloudKitExistingShareLookup.url(
                from: result,
                recordID: recordID
            )
        )
    }

    func testMissingPerRecordResultFailsClosed() {
        let recordID = shareRecordID()

        XCTAssertThrowsError(
            try CloudKitExistingShareLookup.url(
                from: nil,
                recordID: recordID
            )
        ) { error in
            guard case CloudKitFamilySyncError.operationFailed = error else {
                return XCTFail("Expected an operation failure, got \(error)")
            }
        }
    }

    private func shareRecordID() -> CKRecord.ID {
        CKRecord.ID(
            recordName: "share",
            zoneID: CKRecordZone.ID(
                zoneName: "TadaProfile-test",
                ownerName: CKCurrentUserDefaultName
            )
        )
    }

    @MainActor
    private func accessRecords() -> (root: CKRecord, share: CKShare) {
        let root = CKRecord(
            recordType: "TadaProfileRoot",
            recordID: CKRecord.ID(
                recordName: "root",
                zoneID: CKRecordZone.ID(zoneName: "TadaProfile-test")
            )
        )
        return (root, CKShare(rootRecord: root))
    }

    private func cloudError(_ code: CKError.Code) -> CKError {
        CKError(
            _nsError: NSError(
                domain: CKErrorDomain,
                code: code.rawValue
            )
        )
    }
}

private enum AccessLoaderTestError: Error, Equatable {
    case transient
}
