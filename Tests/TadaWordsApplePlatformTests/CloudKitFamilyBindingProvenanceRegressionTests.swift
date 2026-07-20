@preconcurrency import CloudKit
import Foundation
import TadaWordsDomain
import XCTest

@testable import TadaWordsApplePlatform

final class CloudKitFamilyBindingProvenanceRegressionTests: XCTestCase {
    func testSameZoneDifferentProfileCollisionPreservesOriginalBindingAndBytes()
        throws
    {
        let fixture = try CloudKitBindingProvenanceFixture()
        defer { fixture.remove() }
        let metadataURL = fixture.metadataURL(named: "zone-collision")
        let store = CloudKitFamilyMetadataStore(snapshotURL: metadataURL)
        try store.confirm(accountRecordName: "account-a")
        let originalProfileID = ProfileID()
        let collidingProfileID = ProfileID()
        let zoneID = fixture.zoneID(named: "owner-zone")
        try store.save(
            binding: fixture.binding(
                profileID: originalProfileID,
                state: .privateOwner,
                zoneID: zoneID,
                rootRecordName: "original-root"
            )
        )
        let originalBinding = store.binding(for: originalProfileID)
        let originalBytes = try Data(contentsOf: metadataURL)

        assertBindingConflict {
            try store.save(
                binding: fixture.binding(
                    profileID: collidingProfileID,
                    state: .privateOwner,
                    zoneID: zoneID,
                    rootRecordName: "colliding-root"
                )
            )
        }

        XCTAssertEqual(try Data(contentsOf: metadataURL), originalBytes)
        let restarted = CloudKitFamilyMetadataStore(snapshotURL: metadataURL)
        XCTAssertEqual(restarted.binding(for: originalProfileID), originalBinding)
        XCTAssertEqual(
            restarted.binding(for: collidingProfileID),
            .unbound(collidingProfileID)
        )
        XCTAssertEqual(restarted.binding(for: zoneID), originalBinding)
    }

    func testRouteAndZoneReplacementAttemptsLeaveOwnerAndParticipantUnchanged()
        throws
    {
        let fixture = try CloudKitBindingProvenanceFixture()
        defer { fixture.remove() }
        let store = CloudKitFamilyMetadataStore(
            snapshotURL: fixture.metadataURL(named: "replacement")
        )
        try store.confirm(accountRecordName: "account-a")
        let ownerProfileID = ProfileID()
        let participantProfileID = ProfileID()
        let ownerZoneID = fixture.zoneID(named: "owner-zone")
        let participantZoneID = fixture.zoneID(
            named: "participant-zone",
            ownerName: "shared-zone-owner"
        )
        try store.save(
            binding: fixture.binding(
                profileID: ownerProfileID,
                state: .privateOwner,
                zoneID: ownerZoneID,
                rootRecordName: "owner-root"
            )
        )
        try store.save(
            binding: fixture.binding(
                profileID: participantProfileID,
                state: .sharedParticipant,
                zoneID: participantZoneID,
                rootRecordName: "participant-root"
            )
        )
        let originalOwner = store.binding(for: ownerProfileID)
        let originalParticipant = store.binding(for: participantProfileID)

        assertBindingConflict {
            try store.save(
                binding: fixture.binding(
                    profileID: ownerProfileID,
                    state: .sharedParticipant,
                    zoneID: ownerZoneID,
                    rootRecordName: "owner-root"
                )
            )
        }
        assertBindingConflict {
            try store.save(
                binding: fixture.binding(
                    profileID: ownerProfileID,
                    state: .privateOwner,
                    zoneID: fixture.zoneID(named: "replacement-owner-zone"),
                    rootRecordName: "owner-root"
                )
            )
        }
        assertBindingConflict {
            try store.save(
                binding: fixture.binding(
                    profileID: participantProfileID,
                    state: .privateOwner,
                    zoneID: participantZoneID,
                    rootRecordName: "participant-root"
                )
            )
        }
        assertBindingConflict {
            try store.save(
                binding: fixture.binding(
                    profileID: participantProfileID,
                    state: .sharedParticipant,
                    zoneID: fixture.zoneID(
                        named: "replacement-participant-zone",
                        ownerName: "shared-zone-owner"
                    ),
                    rootRecordName: "participant-root"
                )
            )
        }

        XCTAssertEqual(store.binding(for: ownerProfileID), originalOwner)
        XCTAssertEqual(
            store.binding(for: participantProfileID),
            originalParticipant
        )
    }

    func testFreshOwnerLedgerRecoveryDurablyStampsAccountAndOwnerProvenance()
        throws
    {
        let fixture = try CloudKitBindingProvenanceFixture()
        defer { fixture.remove() }
        let metadataURL = fixture.metadataURL(named: "fresh-recovery")
        let store = CloudKitFamilyMetadataStore(snapshotURL: metadataURL)
        try store.confirm(accountRecordName: "account-a")
        let profileID = ProfileID()
        let zoneID = fixture.zoneID(named: "recovery-owner-zone")

        let preparation = try store.prepareOwnerDeletionLedgerRecovery(
            profileID: profileID,
            zoneID: zoneID,
            rootRecordName: "recovery-root"
        )
        let recovered = preparation.binding

        XCTAssertTrue(preparation.wasCreated)
        XCTAssertEqual(recovered.state, .privateOwner)
        XCTAssertEqual(recovered.zoneID, zoneID)
        XCTAssertEqual(recovered.rootRecordName, "recovery-root")
        XCTAssertEqual(recovered.originAccountRecordName, "account-a")
        XCTAssertEqual(recovered.originErasureRoute, .owner)
        XCTAssertEqual(recovered.erasureRoute, .owner)
        let restarted = CloudKitFamilyMetadataStore(snapshotURL: metadataURL)
        XCTAssertEqual(restarted.binding(for: profileID), recovered)
        XCTAssertTrue(
            restarted.isBindingAuthorizedForConfirmedAccount(recovered)
        )
    }

    func testOwnerLedgerRecoveryRejectsParticipantRouteWithoutMutation() throws {
        let fixture = try CloudKitBindingProvenanceFixture()
        defer { fixture.remove() }
        let metadataURL = fixture.metadataURL(named: "participant-recovery")
        let store = CloudKitFamilyMetadataStore(snapshotURL: metadataURL)
        try store.confirm(accountRecordName: "account-a")
        let profileID = ProfileID()
        let sharedZoneID = fixture.zoneID(
            named: "shared-zone",
            ownerName: "shared-zone-owner"
        )
        try store.save(
            binding: fixture.binding(
                profileID: profileID,
                state: .sharedParticipant,
                zoneID: sharedZoneID,
                rootRecordName: "shared-root"
            )
        )
        let originalBinding = store.binding(for: profileID)
        let originalBytes = try Data(contentsOf: metadataURL)

        assertBindingConflict {
            _ = try store.prepareOwnerDeletionLedgerRecovery(
                profileID: profileID,
                zoneID: sharedZoneID,
                rootRecordName: "shared-root"
            )
        }

        XCTAssertEqual(store.binding(for: profileID), originalBinding)
        XCTAssertEqual(try Data(contentsOf: metadataURL), originalBytes)
    }

    func testOwnerLedgerRecoveryRejectsBindingFromAnotherConfirmedAccount()
        throws
    {
        let fixture = try CloudKitBindingProvenanceFixture()
        defer { fixture.remove() }
        let metadataURL = fixture.metadataURL(named: "foreign-recovery")
        let store = CloudKitFamilyMetadataStore(snapshotURL: metadataURL)
        try store.confirm(accountRecordName: "account-a")
        let profileID = ProfileID()
        let zoneID = fixture.zoneID(named: "foreign-owner-zone")
        try store.save(
            binding: fixture.binding(
                profileID: profileID,
                state: .privateOwner,
                zoneID: zoneID,
                rootRecordName: "foreign-root"
            )
        )
        let originalBinding = store.binding(for: profileID)
        XCTAssertEqual(
            try store.confirm(accountRecordName: "account-b"),
            .switchedAccounts
        )

        XCTAssertThrowsError(
            try store.prepareOwnerDeletionLedgerRecovery(
                profileID: profileID,
                zoneID: zoneID,
                rootRecordName: "foreign-root"
            )
        ) { error in
            XCTAssertEqual(
                error as? CloudKitFamilyPersistenceError,
                .accountBindingMismatch
            )
        }

        XCTAssertEqual(store.binding(for: profileID), originalBinding)
        XCTAssertEqual(originalBinding.originAccountRecordName, "account-a")
        XCTAssertFalse(
            store.isBindingAuthorizedForConfirmedAccount(originalBinding)
        )
    }

    func testOwnerLedgerRecoveryAtomicallyCommitsReceiptAndTerminalBinding()
        throws
    {
        let fixture = try CloudKitBindingProvenanceFixture()
        defer { fixture.remove() }
        let metadataURL = fixture.metadataURL(named: "atomic-recovery")
        let store = CloudKitFamilyMetadataStore(snapshotURL: metadataURL)
        try store.confirm(accountRecordName: "account-a")
        let profileID = ProfileID()
        let zoneID = fixture.zoneID(named: "atomic-recovery-zone")
        try store.save(
            binding: fixture.binding(
                profileID: profileID,
                state: .privateOwner,
                zoneID: zoneID,
                rootRecordName: "atomic-recovery-root"
            )
        )
        let previous = store.binding(for: profileID)
        let deletion = try fixture.deletionRecord(profileID: profileID)
        let recordID = CloudKitFamilyDeletionLedgerCodec.recordID(
            for: profileID
        )

        let receiptID = try store.commitOwnerDeletionLedgerRecovery(
            record: deletion,
            recordID: recordID,
            previous: previous,
            receivedAt: deletion.updatedAt
        )

        XCTAssertEqual(store.binding(for: profileID).state, .ownerDeleted)
        XCTAssertEqual(store.binding(for: profileID).erasureRoute, .owner)
        XCTAssertEqual(store.inboxEntries().map(\.receiptID), [receiptID])
        XCTAssertEqual(store.inboxEntries().first?.record, deletion)
        let restarted = CloudKitFamilyMetadataStore(snapshotURL: metadataURL)
        XCTAssertEqual(restarted.binding(for: profileID).state, .ownerDeleted)
        XCTAssertEqual(restarted.inboxEntries().map(\.receiptID), [receiptID])
    }

    func testOwnerLedgerRecoveryCommitRejectsMidFlightAccountSwitchWithoutWrite()
        throws
    {
        let fixture = try CloudKitBindingProvenanceFixture()
        defer { fixture.remove() }
        let metadataURL = fixture.metadataURL(named: "recovery-account-switch")
        let store = CloudKitFamilyMetadataStore(snapshotURL: metadataURL)
        try store.confirm(accountRecordName: "account-a")
        let profileID = ProfileID()
        let zoneID = fixture.zoneID(named: "account-switch-zone")
        try store.save(
            binding: fixture.binding(
                profileID: profileID,
                state: .privateOwner,
                zoneID: zoneID,
                rootRecordName: "account-switch-root"
            )
        )
        let previous = store.binding(for: profileID)
        let deletion = try fixture.deletionRecord(profileID: profileID)

        XCTAssertEqual(
            try store.confirm(accountRecordName: "account-b"),
            .switchedAccounts
        )
        let bytesAfterSwitch = try Data(contentsOf: metadataURL)

        XCTAssertThrowsError(
            try store.commitOwnerDeletionLedgerRecovery(
                record: deletion,
                recordID: CloudKitFamilyDeletionLedgerCodec.recordID(
                    for: profileID
                ),
                previous: previous,
                receivedAt: deletion.updatedAt
            )
        ) { error in
            XCTAssertEqual(
                error as? CloudKitFamilyPersistenceError,
                .accountBindingMismatch
            )
        }

        XCTAssertEqual(try Data(contentsOf: metadataURL), bytesAfterSwitch)
        XCTAssertEqual(store.binding(for: profileID), previous)
        XCTAssertTrue(store.inboxEntries().isEmpty)
    }

    func testAcknowledgedTerminalRemovalDoesNotCreateAnotherInboxReceipt()
        throws
    {
        let fixture = try CloudKitBindingProvenanceFixture()
        defer { fixture.remove() }
        let metadataURL = fixture.metadataURL(named: "terminal-ack")
        let store = CloudKitFamilyMetadataStore(snapshotURL: metadataURL)
        try store.confirm(accountRecordName: "account-a")
        let profileID = ProfileID()
        let zoneID = fixture.zoneID(named: "terminal-owner-zone")
        let rootRecordName = "terminal-owner-root"
        try store.save(
            binding: fixture.binding(
                profileID: profileID,
                state: .privateOwner,
                zoneID: zoneID,
                rootRecordName: rootRecordName
            )
        )
        let deletedAt = Date(timeIntervalSince1970: 2_174_000_000)
        let revision = FamilySyncLogicalRevision(
            counter: 17,
            deviceID: "owner-device"
        )
        let deletion = FamilySyncRecord(
            recordName: rootRecordName,
            profileID: profileID,
            kind: .profileDeletion,
            payload: try JSONEncoder().encode(
                ProfileDeletionTombstone(
                    profileID: profileID,
                    deletedAt: deletedAt
                )
            ),
            updatedAt: deletedAt,
            deviceID: revision.deviceID,
            isDeleted: true,
            logicalRevision: revision
        )
        let recordID = CKRecord.ID(
            recordName: rootRecordName,
            zoneID: zoneID
        )

        let firstReceipt = try XCTUnwrap(
            store.commitRemoteProfileRemoval(
                record: deletion,
                recordID: recordID,
                scope: .privateDatabase,
                receivedAt: deletedAt
            )
        )
        XCTAssertEqual(store.inboxEntries().map(\.receiptID), [firstReceipt])
        try store.acknowledgeInbox(receiptIDs: [firstReceipt])

        let restarted = CloudKitFamilyMetadataStore(snapshotURL: metadataURL)
        XCTAssertTrue(restarted.hasAcknowledgedTerminalRemoval(deletion))
        XCTAssertTrue(restarted.inboxEntries().isEmpty)
        XCTAssertNil(
            try restarted.commitRemoteProfileRemoval(
                record: deletion,
                recordID: recordID,
                scope: .privateDatabase,
                receivedAt: deletedAt.addingTimeInterval(300)
            )
        )
        XCTAssertTrue(restarted.inboxEntries().isEmpty)
        XCTAssertEqual(restarted.binding(for: profileID).state, .ownerDeleted)
    }

    private func assertBindingConflict(
        _ operation: () throws -> Void,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        XCTAssertThrowsError(try operation(), file: file, line: line) { error in
            XCTAssertEqual(
                error as? CloudKitFamilyPersistenceError,
                .bindingConflict,
                file: file,
                line: line
            )
        }
    }
}

private struct CloudKitBindingProvenanceFixture {
    let directory: URL

    init() throws {
        directory = FileManager.default.temporaryDirectory.appendingPathComponent(
            "TadaCloudBindingProvenance-\(UUID().uuidString)",
            isDirectory: true
        )
        try FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true
        )
    }

    func metadataURL(named name: String) -> URL {
        directory.appendingPathComponent("\(name).json")
    }

    func zoneID(
        named name: String,
        ownerName: String = CKCurrentUserDefaultName
    ) -> CKRecordZone.ID {
        CKRecordZone.ID(zoneName: name, ownerName: ownerName)
    }

    func binding(
        profileID: ProfileID,
        state: ProfileCloudBindingState,
        zoneID: CKRecordZone.ID,
        rootRecordName: String
    ) -> ProfileCloudBinding {
        ProfileCloudBinding(
            profileID: profileID,
            state: state,
            zoneName: zoneID.zoneName,
            ownerName: zoneID.ownerName,
            rootRecordName: rootRecordName
        )
    }

    func deletionRecord(profileID: ProfileID) throws -> FamilySyncRecord {
        let deletedAt = Date(timeIntervalSince1970: 2_174_000_000)
        return FamilySyncRecord(
            recordName: "profile-\(profileID)",
            profileID: profileID,
            kind: .profileDeletion,
            payload: try JSONEncoder().encode(
                ProfileDeletionTombstone(
                    profileID: profileID,
                    deletedAt: deletedAt
                )
            ),
            updatedAt: deletedAt,
            deviceID: "owner-device",
            isDeleted: true,
            logicalRevision: FamilySyncLogicalRevision(
                counter: 23,
                deviceID: "owner-device"
            )
        )
    }

    func remove() {
        try? FileManager.default.removeItem(at: directory)
    }
}
