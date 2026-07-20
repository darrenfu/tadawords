@preconcurrency import CloudKit
import Foundation
import TadaWordsDomain
import XCTest

@testable import TadaWordsApplePlatform

final class CloudKitFamilyDeletionSemanticsHarnessTests: XCTestCase {
    func testOwnerTerminalMarkAtomicallyPurgesOnlyTargetTransportBytesAcrossRestart()
        throws
    {
        let fixture = try CloudDeletionSemanticsFixture()
        defer { fixture.remove() }
        let store = CloudKitFamilyMetadataStore(
            snapshotURL: fixture.metadataURL
        )
        try store.confirm(accountRecordName: "account-a")
        let targetBinding = ProfileCloudBinding(
            profileID: fixture.profileID,
            state: .privateOwner,
            zoneName: fixture.ownerZoneID.zoneName,
            ownerName: fixture.ownerZoneID.ownerName,
            rootRecordName: "target-root"
        )
        let unrelatedBinding = ProfileCloudBinding(
            profileID: fixture.unrelatedProfileID,
            state: .sharedParticipant,
            zoneName: fixture.unrelatedZoneID.zoneName,
            ownerName: fixture.unrelatedZoneID.ownerName,
            rootRecordName: "unrelated-root"
        )
        try store.save(binding: targetBinding)
        try store.save(binding: unrelatedBinding)
        let persistedTargetBinding = store.binding(for: fixture.profileID)
        let persistedUnrelatedBinding = store.binding(
            for: fixture.unrelatedProfileID
        )

        let targetRecordID = CKRecord.ID(
            recordName: "target-child-record",
            zoneID: fixture.ownerZoneID
        )
        let unrelatedRecordID = CKRecord.ID(
            recordName: "unrelated-child-record",
            zoneID: fixture.unrelatedZoneID
        )
        try store.saveSystemFields(
            for: CKRecord(recordType: "FamilySync", recordID: targetRecordID),
            scope: .privateDatabase
        )
        try store.saveSystemFields(
            for: CKRecord(recordType: "FamilySync", recordID: unrelatedRecordID),
            scope: .sharedDatabase
        )

        let targetPayload = Data(
            "TARGET_CHILD_NICKNAME_AND_PHOTO_BYTES".utf8
        )
        let unrelatedPayload = Data("UNRELATED_CHILD_PAYLOAD".utf8)
        _ = try store.appendInbox(
            record: fixture.record(
                profileID: fixture.profileID,
                recordName: targetRecordID.recordName,
                payload: targetPayload
            ),
            recordID: targetRecordID,
            scope: .privateDatabase,
            receivedAt: fixture.now
        )
        _ = try store.appendInbox(
            record: fixture.record(
                profileID: fixture.unrelatedProfileID,
                recordName: unrelatedRecordID.recordName,
                payload: unrelatedPayload
            ),
            recordID: unrelatedRecordID,
            scope: .sharedDatabase,
            receivedAt: fixture.now
        )

        let targetQuarantineBytes = Data(
            "TARGET_CHILD_QUARANTINED_ENVELOPE".utf8
        )
        let unrelatedQuarantineBytes = Data(
            "UNRELATED_QUARANTINED_ENVELOPE".utf8
        )
        try store.quarantine(
            fixture.quarantine(
                recordID: targetRecordID,
                scope: .privateDatabase,
                envelopeData: targetQuarantineBytes
            )
        )
        try store.quarantine(
            fixture.quarantine(
                recordID: unrelatedRecordID,
                scope: .sharedDatabase,
                envelopeData: unrelatedQuarantineBytes
            )
        )

        try store.markOwnerDeleted(
            profileID: fixture.profileID,
            previous: persistedTargetBinding
        )

        // Recreate the store to prove the terminal state and byte purge were
        // committed in one crash-safe snapshot, rather than only in memory.
        let restarted = CloudKitFamilyMetadataStore(
            snapshotURL: fixture.metadataURL
        )
        let terminal = restarted.binding(for: fixture.profileID)
        XCTAssertEqual(terminal.state, .ownerDeleted)
        XCTAssertEqual(terminal.zoneID, fixture.ownerZoneID)
        XCTAssertEqual(
            restarted.binding(for: fixture.unrelatedProfileID),
            persistedUnrelatedBinding
        )

        XCTAssertNil(
            restarted.restoredRecord(
                id: targetRecordID,
                scope: .privateDatabase
            )
        )
        XCTAssertNotNil(
            restarted.restoredRecord(
                id: unrelatedRecordID,
                scope: .sharedDatabase
            )
        )
        XCTAssertFalse(
            restarted.isQuarantined(
                recordID: targetRecordID,
                scope: .privateDatabase
            )
        )
        XCTAssertTrue(
            restarted.isQuarantined(
                recordID: unrelatedRecordID,
                scope: .sharedDatabase
            )
        )
        XCTAssertEqual(restarted.quarantinedCount(), 1)
        XCTAssertEqual(
            restarted.inboxEntries().map(\.record?.profileID),
            [fixture.unrelatedProfileID]
        )

        let persistedJSON = try String(
            contentsOf: fixture.metadataURL,
            encoding: .utf8
        )
        XCTAssertFalse(
            persistedJSON.contains(targetPayload.base64EncodedString()),
            "Terminal deletion must not retain child payload bytes"
        )
        XCTAssertFalse(
            persistedJSON.contains(
                targetQuarantineBytes.base64EncodedString()
            ),
            "Terminal deletion must not retain quarantined child bytes"
        )
        XCTAssertTrue(
            persistedJSON.contains(unrelatedPayload.base64EncodedString()),
            "Purging one child must not erase another child's durable inbox"
        )
        XCTAssertTrue(
            persistedJSON.contains(
                unrelatedQuarantineBytes.base64EncodedString()
            ),
            "Purging one child must not erase another child's quarantine"
        )
    }

    func testParticipantTerminalMarkPurgesTargetInboxAcrossRestart() throws {
        let fixture = try CloudDeletionSemanticsFixture()
        defer { fixture.remove() }
        let store = CloudKitFamilyMetadataStore(
            snapshotURL: fixture.metadataURL
        )
        try store.confirm(accountRecordName: "account-a")
        let binding = ProfileCloudBinding(
            profileID: fixture.profileID,
            state: .sharedParticipant,
            zoneName: fixture.sharedZoneID.zoneName,
            ownerName: fixture.sharedZoneID.ownerName,
            rootRecordName: "shared-profile-root"
        )
        try store.save(binding: binding)
        let persistedBinding = store.binding(for: fixture.profileID)
        let recordID = CKRecord.ID(
            recordName: "participant-child-record",
            zoneID: fixture.sharedZoneID
        )
        _ = try store.appendInbox(
            record: fixture.record(
                profileID: fixture.profileID,
                recordName: recordID.recordName,
                payload: Data("PARTICIPANT_CHILD_BYTES".utf8)
            ),
            recordID: recordID,
            scope: .sharedDatabase,
            receivedAt: fixture.now
        )

        try store.markParticipantLeft(
            profileID: fixture.profileID,
            previous: persistedBinding
        )

        let restarted = CloudKitFamilyMetadataStore(
            snapshotURL: fixture.metadataURL
        )
        XCTAssertEqual(
            restarted.binding(for: fixture.profileID).state,
            .participantLeft
        )
        XCTAssertTrue(restarted.inboxEntries().isEmpty)
        XCTAssertFalse(
            try String(contentsOf: fixture.metadataURL, encoding: .utf8)
                .contains(Data("PARTICIPANT_CHILD_BYTES".utf8).base64EncodedString())
        )
    }

    func testOwnerDeletionLedgerContainsOnlyPrivacyMinimalApplicationFields()
        throws
    {
        let profileID = ProfileID()
        let deletedAt = Date(timeIntervalSince1970: 2_173_000_000)
        let payload = try JSONEncoder().encode(
            ProfileDeletionTombstone(
                profileID: profileID,
                deletedAt: deletedAt
            )
        )
        let revision = FamilySyncLogicalRevision(
            counter: 42,
            deviceID: "owner-device"
        )
        let tombstone = FamilySyncRecord(
            recordName: "profile-\(profileID)",
            profileID: profileID,
            kind: .profileDeletion,
            payload: payload,
            updatedAt: deletedAt,
            deviceID: revision.deviceID,
            isDeleted: true,
            logicalRevision: revision
        )

        let cloudRecord = try CloudKitFamilyDeletionLedgerCodec.cloudRecord(
            for: tombstone
        )
        let applicationFields = Set(cloudRecord.allKeys())

        XCTAssertEqual(
            applicationFields,
            CloudKitFamilyDeletionLedgerCodec.allowedApplicationFieldNames
        )
        XCTAssertFalse(applicationFields.contains("nickname"))
        XCTAssertFalse(applicationFields.contains("avatar"))
        XCTAssertFalse(applicationFields.contains("payload"))
        XCTAssertFalse(applicationFields.contains("asset"))
        let decoded = try XCTUnwrap(
            CloudKitFamilyDeletionLedgerCodec.familyRecord(from: cloudRecord)
        )
        XCTAssertEqual(decoded.profileID, profileID)
        XCTAssertEqual(decoded.kind, .profileDeletion)
        XCTAssertTrue(decoded.isDeleted)
        XCTAssertEqual(decoded.logicalRevision, revision)
    }

    func testFutureEnvelopeVersionStillDecodesAsReadableTerminalLedger()
        throws
    {
        let profileID = ProfileID()
        let revision = FamilySyncLogicalRevision(
            counter: 77,
            deviceID: "future-owner-device"
        )
        let payload = try JSONEncoder().encode(
            ProfileDeletionTombstone(
                profileID: profileID,
                deletedAt: Date(timeIntervalSince1970: 2_173_000_500)
            )
        )
        let tombstone = FamilySyncRecord(
            recordName: "profile-\(profileID)",
            profileID: profileID,
            kind: .profileDeletion,
            payload: payload,
            updatedAt: Date(timeIntervalSince1970: 2_173_000_500),
            deviceID: revision.deviceID,
            isDeleted: true,
            logicalRevision: revision
        )
        let ledger = try CloudKitFamilyDeletionLedgerCodec.cloudRecord(
            for: tombstone
        )
        ledger[
            CloudKitFamilyDeletionLedgerCodec.Schema.envelopeSchemaVersion
        ] = NSNumber(value: FamilySyncRecord.currentSchemaVersion + 50)

        let decoded = try XCTUnwrap(
            CloudKitFamilyDeletionLedgerCodec.familyRecord(from: ledger)
        )

        XCTAssertEqual(decoded.schemaVersion, FamilySyncRecord.currentSchemaVersion)
        XCTAssertEqual(decoded.logicalRevision, revision)
        XCTAssertNoThrow(try decoded.validateCompatibility())
    }

    func testDeletionLedgerRejectsProfileIDThatDoesNotMatchItsRecordID()
        throws
    {
        let profileID = ProfileID()
        let deletedAt = Date(timeIntervalSince1970: 2_173_000_550)
        let tombstone = FamilySyncRecord(
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
            isDeleted: true
        )
        let ledger = try CloudKitFamilyDeletionLedgerCodec.cloudRecord(
            for: tombstone
        )
        let mismatchedProfileID = ProfileID()
        ledger[CloudKitFamilyDeletionLedgerCodec.Schema.profileID] =
            mismatchedProfileID.rawValue.uuidString as NSString

        XCTAssertNotEqual(
            ledger.recordID,
            CloudKitFamilyDeletionLedgerCodec.recordID(
                for: mismatchedProfileID
            )
        )
        XCTAssertNil(
            CloudKitFamilyDeletionLedgerCodec.familyRecord(from: ledger),
            "A deletion ledger must not tombstone a Profile other than the one named by its deterministic record ID."
        )
    }

    func testLedgerWithUnexpectedChildFieldIsRejectedUntilSanitized() throws {
        let profileID = ProfileID()
        let payload = try JSONEncoder().encode(
            ProfileDeletionTombstone(
                profileID: profileID,
                deletedAt: Date(timeIntervalSince1970: 2_173_000_600)
            )
        )
        let tombstone = FamilySyncRecord(
            recordName: "profile-\(profileID)",
            profileID: profileID,
            kind: .profileDeletion,
            payload: payload,
            updatedAt: Date(timeIntervalSince1970: 2_173_000_600),
            deviceID: "owner-device",
            isDeleted: true
        )
        let ledger = try CloudKitFamilyDeletionLedgerCodec.cloudRecord(
            for: tombstone
        )
        ledger["nickname"] = "must-not-survive" as NSString

        XCTAssertNil(
            CloudKitFamilyDeletionLedgerCodec.familyRecord(from: ledger)
        )
        XCTAssertTrue(
            CloudKitFamilyDeletionLedgerCodec
                .removeUnexpectedApplicationFields(from: ledger)
        )
        XCTAssertEqual(
            Set(ledger.allKeys()),
            CloudKitFamilyDeletionLedgerCodec.allowedApplicationFieldNames
        )
        XCTAssertNotNil(
            CloudKitFamilyDeletionLedgerCodec.familyRecord(from: ledger)
        )
    }

    func testParticipantLeaveCanNeverSelectOwnerGlobalDeletionLedger() {
        let profileID = ProfileID()
        let shared = ProfileCloudBinding(
            profileID: profileID,
            state: .sharedParticipant,
            zoneName: "SharedProfile",
            ownerName: "another-owner",
            rootRecordName: "shared-root"
        )
        let participantLeft = ProfileCloudBinding(
            profileID: profileID,
            state: .participantLeft,
            zoneName: shared.zoneName,
            ownerName: shared.ownerName,
            rootRecordName: shared.rootRecordName
        )

        XCTAssertEqual(
            CloudKitFamilyProfileRemovalPlanner.mode(
                for: shared,
                isOriginAccountAuthorized: true
            ),
            .participantLeave
        )
        XCTAssertEqual(
            CloudKitFamilyProfileRemovalPlanner.mode(
                for: participantLeft,
                isOriginAccountAuthorized: true
            ),
            .alreadyTerminal(.participant)
        )
        XCTAssertNotEqual(
            CloudKitFamilyProfileRemovalPlanner.mode(
                for: shared,
                isOriginAccountAuthorized: true
            ),
            .ownerGlobalDeletion,
            "A participant device has no authority to publish the owner's global deletion ledger"
        )
    }

    func testUnboundOrWrongAccountRemovalFailsClosedWithoutOwnerAuthority() {
        let profileID = ProfileID()
        let unbound = ProfileCloudBinding.unbound(profileID)
        let owner = ProfileCloudBinding(
            profileID: profileID,
            state: .privateOwner,
            zoneName: "OwnerZone",
            ownerName: CKCurrentUserDefaultName,
            rootRecordName: "root",
            originAccountRecordName: "account-a",
            originErasureRoute: .owner
        )

        XCTAssertEqual(
            CloudKitFamilyProfileRemovalPlanner.mode(
                for: unbound,
                isOriginAccountAuthorized: true
            ),
            .accountBlocked(.unresolved)
        )
        XCTAssertEqual(
            CloudKitFamilyProfileRemovalPlanner.mode(
                for: owner,
                isOriginAccountAuthorized: false
            ),
            .accountBlocked(.owner)
        )
        XCTAssertEqual(
            CloudKitFamilyProfileRemovalPlanner.bindingPlan(
                for: unbound,
                hasPersistedBinding: false
            ),
            .prepareOwnerBinding,
            "A never-synchronized local Profile must first establish a durable owner route."
        )
        XCTAssertEqual(
            CloudKitFamilyProfileRemovalPlanner.bindingPlan(
                for: unbound,
                hasPersistedBinding: true
            ),
            .usePersisted(unbound),
            "A persisted ambiguous route must never be converted into a new-account owner."
        )
    }

    @MainActor
    func testSharedZoneRevocationDurablyEmitsLocalProfilePurgeAcrossRestart()
        async throws
    {
        let fixture = try CloudDeletionSemanticsFixture()
        defer { fixture.remove() }
        let firstStore = CloudKitFamilyMetadataStore(
            snapshotURL: fixture.metadataURL
        )
        try firstStore.confirm(accountRecordName: "account-a")
        try firstStore.save(
            binding: ProfileCloudBinding(
                profileID: fixture.profileID,
                state: .sharedParticipant,
                zoneName: fixture.sharedZoneID.zoneName,
                ownerName: fixture.sharedZoneID.ownerName,
                rootRecordName: "shared-profile-root"
            )
        )
        let firstBuffer = CloudKitFamilySyncEventBuffer(
            metadataStore: firstStore
        )

        await firstBuffer.handle(
            .deletedZones([fixture.sharedZoneID]),
            scope: .sharedDatabase,
            generation: 1,
            now: fixture.now
        )
        let firstResult = await firstBuffer.drain()

        XCTAssertTrue(firstResult.records.isEmpty)
        XCTAssertTrue(firstResult.receiptIDs.isEmpty)
        XCTAssertTrue(firstResult.requiresFetchPass)
        XCTAssertEqual(firstStore.inboxEntries().count, 1)
        XCTAssertEqual(
            firstStore.binding(for: fixture.profileID).state,
            .sharedParticipant
        )

        let restartedStore = CloudKitFamilyMetadataStore(
            snapshotURL: fixture.metadataURL
        )
        try await completeProvenZoneRecovery(restartedStore)
        let purge = try XCTUnwrap(
            restartedStore.replayableInboxEntries().first?.record
        )
        let restartedBuffer = CloudKitFamilySyncEventBuffer(
            metadataStore: restartedStore
        )
        await restartedBuffer.replay(
            restartedStore.replayableInboxEntries(),
            generation: 1
        )
        let replayed = await restartedBuffer.drain()

        XCTAssertEqual(replayed.records, [purge])
        XCTAssertEqual(
            replayed.receiptIDs,
            Set(restartedStore.replayableInboxEntries().map(\.receiptID))
        )
        XCTAssertEqual(
            restartedStore.binding(for: fixture.profileID).state,
            .revoked
        )
    }

    @MainActor
    func testSharedZoneRevocationPurgesChildBytesButPreservesMinimalDeletionBarrier()
        async throws
    {
        let fixture = try CloudDeletionSemanticsFixture()
        defer { fixture.remove() }
        let store = CloudKitFamilyMetadataStore(
            snapshotURL: fixture.metadataURL
        )
        try store.confirm(accountRecordName: "account-a")
        try store.save(
            binding: ProfileCloudBinding(
                profileID: fixture.profileID,
                state: .sharedParticipant,
                zoneName: fixture.sharedZoneID.zoneName,
                ownerName: fixture.sharedZoneID.ownerName,
                rootRecordName: "shared-profile-root"
            )
        )
        let childRecordID = CKRecord.ID(
            recordName: "stale-child-payload",
            zoneID: fixture.sharedZoneID
        )
        let childPayload = Data("SHARED_CHILD_PHOTO_AND_NAME".utf8)
        try store.saveSystemFields(
            for: CKRecord(recordType: "FamilySync", recordID: childRecordID),
            scope: .sharedDatabase
        )
        _ = try store.appendInbox(
            record: fixture.record(
                profileID: fixture.profileID,
                recordName: childRecordID.recordName,
                payload: childPayload
            ),
            recordID: childRecordID,
            scope: .sharedDatabase,
            receivedAt: fixture.now
        )
        try store.quarantine(
            fixture.quarantine(
                recordID: childRecordID,
                scope: .sharedDatabase,
                envelopeData: Data("SHARED_CHILD_QUARANTINE".utf8)
            )
        )

        let buffer = CloudKitFamilySyncEventBuffer(metadataStore: store)
        await buffer.handle(
            .deletedZones([fixture.sharedZoneID]),
            scope: .sharedDatabase,
            generation: 1,
            now: fixture.now
        )
        let result = await buffer.drain()
        XCTAssertTrue(result.records.isEmpty)
        XCTAssertTrue(result.receiptIDs.isEmpty)
        try await completeProvenZoneRecovery(store)

        let restarted = CloudKitFamilyMetadataStore(
            snapshotURL: fixture.metadataURL
        )
        let durable = try XCTUnwrap(restarted.replayableInboxEntries().only)
        let removal = try XCTUnwrap(durable.record)
        XCTAssertEqual(removal.kind, .profileDeletion)
        XCTAssertTrue(removal.isDeleted)
        XCTAssertEqual(removal.profileID, fixture.profileID)
        XCTAssertEqual(
            try JSONDecoder().decode(
                ProfileDeletionTombstone.self,
                from: removal.payload
            ).profileID,
            fixture.profileID
        )
        XCTAssertNil(
            restarted.restoredRecord(
                id: childRecordID,
                scope: .sharedDatabase
            )
        )
        XCTAssertFalse(
            restarted.isQuarantined(
                recordID: childRecordID,
                scope: .sharedDatabase
            )
        )
        XCTAssertEqual(restarted.quarantinedCount(), 0)
        XCTAssertFalse(
            try String(contentsOf: fixture.metadataURL, encoding: .utf8)
                .contains(childPayload.base64EncodedString())
        )
    }

    func testSameAccountReconfirmationPreservesOnlyTerminalDeletionBarrierAcrossRestart()
        throws
    {
        let fixture = try CloudDeletionSemanticsFixture()
        defer { fixture.remove() }
        let store = CloudKitFamilyMetadataStore(
            snapshotURL: fixture.metadataURL
        )
        try store.confirm(accountRecordName: "same-account")
        let revokedBinding = ProfileCloudBinding(
            profileID: fixture.profileID,
            state: .sharedParticipant,
            zoneName: fixture.sharedZoneID.zoneName,
            ownerName: fixture.sharedZoneID.ownerName,
            rootRecordName: "shared-profile-root"
        )
        try store.save(binding: revokedBinding)
        try store.save(
            binding: ProfileCloudBinding(
                profileID: fixture.unrelatedProfileID,
                state: .privateOwner,
                zoneName: fixture.unrelatedZoneID.zoneName,
                ownerName: fixture.unrelatedZoneID.ownerName,
                rootRecordName: "unrelated-root"
            )
        )

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .secondsSince1970
        encoder.outputFormatting = [.sortedKeys]
        let terminalRecord = FamilySyncRecord(
            recordName: "profile-\(fixture.profileID)",
            profileID: fixture.profileID,
            kind: .profileDeletion,
            payload: try encoder.encode(
                ProfileDeletionTombstone(
                    profileID: fixture.profileID,
                    deletedAt: Date(timeIntervalSince1970: 0)
                )
            ),
            updatedAt: Date(timeIntervalSince1970: 0),
            deviceID: "cloud-share-revocation",
            isDeleted: true,
            logicalRevision: FamilySyncLogicalRevision(
                counter: 0,
                deviceID: "cloud-share-revocation"
            )
        )
        let terminalRecordID = CKRecord.ID(
            recordName: "shared-profile-root",
            zoneID: fixture.sharedZoneID
        )
        let terminalReceipt = try store.appendInbox(
            record: terminalRecord,
            recordID: terminalRecordID,
            scope: .sharedDatabase,
            receivedAt: fixture.now
        )
        let unrelatedPayload = Data("STALE_UNRELATED_CALLBACK_BYTES".utf8)
        _ = try store.appendInbox(
            record: fixture.record(
                profileID: fixture.unrelatedProfileID,
                recordName: "unrelated-stale-callback",
                payload: unrelatedPayload
            ),
            recordID: CKRecord.ID(
                recordName: "unrelated-stale-callback",
                zoneID: fixture.unrelatedZoneID
            ),
            scope: .privateDatabase,
            receivedAt: fixture.now
        )
        try store.revokeBinding(for: fixture.sharedZoneID)
        XCTAssertEqual(store.inboxEntries().count, 2)

        try store.requireAccountConfirmation()
        try store.confirm(accountRecordName: "same-account")

        let restarted = CloudKitFamilyMetadataStore(
            snapshotURL: fixture.metadataURL
        )
        XCTAssertEqual(
            restarted.inboxEntries().map(\.receiptID),
            [terminalReceipt]
        )
        XCTAssertEqual(restarted.inboxEntries().first?.record, terminalRecord)
        XCTAssertEqual(
            restarted.binding(for: fixture.profileID).state,
            .revoked
        )
        XCTAssertFalse(
            try String(contentsOf: fixture.metadataURL, encoding: .utf8)
                .contains(unrelatedPayload.base64EncodedString())
        )
    }

    @MainActor
    func testRepeatedSharedZoneRevocationAcrossRestartKeepsOneStablePurgeReceipt()
        async throws
    {
        let fixture = try CloudDeletionSemanticsFixture()
        defer { fixture.remove() }
        let firstStore = CloudKitFamilyMetadataStore(
            snapshotURL: fixture.metadataURL
        )
        try firstStore.confirm(accountRecordName: "account-a")
        try firstStore.save(
            binding: ProfileCloudBinding(
                profileID: fixture.profileID,
                state: .sharedParticipant,
                zoneName: fixture.sharedZoneID.zoneName,
                ownerName: fixture.sharedZoneID.ownerName,
                rootRecordName: "shared-profile-root"
            )
        )
        let firstBuffer = CloudKitFamilySyncEventBuffer(
            metadataStore: firstStore
        )
        await firstBuffer.handle(
            .deletedZones([fixture.sharedZoneID]),
            scope: .sharedDatabase,
            generation: 1,
            now: fixture.now
        )
        let staged = await firstBuffer.drain()
        XCTAssertTrue(staged.records.isEmpty)
        try await completeProvenZoneRecovery(firstStore)
        let firstEntry = try XCTUnwrap(
            firstStore.replayableInboxEntries().first
        )
        let firstReceipt = firstEntry.receiptID
        let firstRecord = try XCTUnwrap(firstEntry.record)

        let restartedStore = CloudKitFamilyMetadataStore(
            snapshotURL: fixture.metadataURL
        )
        let restartedBuffer = CloudKitFamilySyncEventBuffer(
            metadataStore: restartedStore
        )
        await restartedBuffer.handle(
            .deletedZones([fixture.sharedZoneID]),
            scope: .sharedDatabase,
            generation: 1,
            now: fixture.now.addingTimeInterval(300)
        )
        await restartedBuffer.replay(
            restartedStore.replayableInboxEntries(),
            generation: 1
        )
        let repeated = await restartedBuffer.drain()

        XCTAssertEqual(
            restartedStore.inboxEntries().count,
            1,
            "A retry/restart must not create a second terminal purge fact"
        )
        XCTAssertEqual(repeated.receiptIDs, [firstReceipt])
        XCTAssertEqual(repeated.records, [firstRecord])
        XCTAssertEqual(
            restartedStore.binding(for: fixture.profileID).state,
            .revoked
        )
    }

    @MainActor
    private func completeProvenZoneRecovery(
        _ store: CloudKitFamilyMetadataStore
    ) async throws {
        let recovery = try XCTUnwrap(
            store.pendingRemoteZoneRemovalRecoveries().only
        )
        _ = try await CloudKitProvenZoneDeletionRecoveryExecutor().recover(
            verifyOriginAccount: {},
            purgeLocalSources: {},
            commit: {
                try store.commitRemoteProfileRemoval(
                    record: recovery.record,
                    recordID: recovery.recordID,
                    scope: recovery.scope,
                    receivedAt: recovery.receivedAt,
                    terminalEvidence: .zoneDeletion
                )
            }
        )
    }
}

extension Collection {
    fileprivate var only: Element? {
        count == 1 ? first : nil
    }
}

private struct CloudDeletionSemanticsFixture {
    let directory: URL
    let metadataURL: URL
    let profileID = ProfileID()
    let unrelatedProfileID = ProfileID()
    let now = Date(timeIntervalSince1970: 2_173_000_100)
    let ownerZoneID = CKRecordZone.ID(
        zoneName: "OwnerDeletionHarness",
        ownerName: CKCurrentUserDefaultName
    )
    let sharedZoneID = CKRecordZone.ID(
        zoneName: "SharedDeletionHarness",
        ownerName: "shared-owner"
    )
    let unrelatedZoneID = CKRecordZone.ID(
        zoneName: "UnrelatedDeletionHarness",
        ownerName: "unrelated-owner"
    )

    init() throws {
        directory = FileManager.default.temporaryDirectory.appendingPathComponent(
            "TadaCloudDeletionSemantics-\(UUID().uuidString)",
            isDirectory: true
        )
        try FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true
        )
        metadataURL = directory.appendingPathComponent("metadata.json")
    }

    func remove() {
        try? FileManager.default.removeItem(at: directory)
    }

    func record(
        profileID: ProfileID,
        recordName: String,
        payload: Data
    ) -> FamilySyncRecord {
        FamilySyncRecord(
            recordName: recordName,
            profileID: profileID,
            kind: .profile,
            payload: payload,
            updatedAt: now,
            deviceID: "deletion-harness",
            logicalRevision: FamilySyncLogicalRevision(
                counter: 1,
                deviceID: "deletion-harness"
            )
        )
    }

    func quarantine(
        recordID: CKRecord.ID,
        scope: CloudKitFamilyDatabaseScope,
        envelopeData: Data
    ) -> CloudKitFamilyQuarantineEntry {
        CloudKitFamilyQuarantineEntry(
            id: UUID(),
            scope: scope,
            recordName: recordID.recordName,
            zoneName: recordID.zoneID.zoneName,
            ownerName: recordID.zoneID.ownerName,
            reason: .compatibility,
            envelopeData: envelopeData,
            quarantinedAt: now
        )
    }
}
