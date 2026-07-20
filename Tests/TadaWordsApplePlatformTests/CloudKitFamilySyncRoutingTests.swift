@preconcurrency import CloudKit
import Foundation
import TadaWordsDomain
import XCTest

@testable import TadaWordsApplePlatform

final class CloudKitFamilySyncRoutingTests: XCTestCase {
    func testTerminalDiscardRemovesOnlyDeletedProfilesOutgoingRecord()
        async throws
    {
        let fixture = try CloudRoutingFixture()
        defer { fixture.remove() }
        let deletedRecord = FamilySyncRecord(
            recordName: "deleted-profile-word",
            profileID: fixture.sharedProfileID,
            kind: .wordPoolEntry,
            payload: Data("deleted".utf8),
            updatedAt: Date(timeIntervalSince1970: 2_180_000_100),
            deviceID: "device"
        )
        let healthyRecord = FamilySyncRecord(
            recordName: "healthy-profile-word",
            profileID: fixture.privateProfileID,
            kind: .wordPoolEntry,
            payload: Data("healthy".utf8),
            updatedAt: Date(timeIntervalSince1970: 2_180_000_100),
            deviceID: "device"
        )
        let deletedZone = CKRecordZone.ID(
            zoneName: "DeletedOutgoingZone",
            ownerName: "owner"
        )
        let healthyZone = CKRecordZone.ID(
            zoneName: "HealthyOutgoingZone",
            ownerName: "owner"
        )
        let deletedID = CKRecord.ID(
            recordName: deletedRecord.recordName,
            zoneID: deletedZone
        )
        let healthyID = CKRecord.ID(
            recordName: healthyRecord.recordName,
            zoneID: healthyZone
        )
        let buffer = CloudKitFamilySyncEventBuffer(metadataStore: fixture.store)
        await buffer.register(
            CloudKitFamilyOutgoingChange(
                acknowledgement: FamilySyncChangeAcknowledgement(
                    operation: .save(deletedRecord)
                ),
                record: CKRecord(recordType: "FamilyItem", recordID: deletedID)
            ),
            recordID: deletedID,
            scope: .sharedDatabase,
            generation: 1
        )
        await buffer.register(
            CloudKitFamilyOutgoingChange(
                acknowledgement: FamilySyncChangeAcknowledgement(
                    operation: .save(healthyRecord)
                ),
                record: CKRecord(recordType: "FamilyItem", recordID: healthyID)
            ),
            recordID: healthyID,
            scope: .privateDatabase,
            generation: 1
        )

        await buffer.discardOutgoing(
            for: fixture.sharedProfileID,
            generation: 1
        )

        let removed = await buffer.record(
            for: deletedID,
            scope: .sharedDatabase,
            generation: 1
        )
        let retained = await buffer.record(
            for: healthyID,
            scope: .privateDatabase,
            generation: 1
        )
        XCTAssertNil(removed)
        XCTAssertNotNil(retained)
    }

    func testTerminalPendingPrunerRemovesOnlyMatchingProfileZone() {
        let deletedZone = CKRecordZone.ID(
            zoneName: "DeletedProfileZone",
            ownerName: CKCurrentUserDefaultName
        )
        let healthyZone = CKRecordZone.ID(
            zoneName: "HealthyProfileZone",
            ownerName: CKCurrentUserDefaultName
        )
        let deletedRecordID = CKRecord.ID(
            recordName: "word-deleted",
            zoneID: deletedZone
        )
        let healthyRecordID = CKRecord.ID(
            recordName: "word-healthy",
            zoneID: healthyZone
        )
        let recordChanges: [CKSyncEngine.PendingRecordZoneChange] = [
            .saveRecord(deletedRecordID),
            .deleteRecord(healthyRecordID),
        ]
        let databaseChanges: [CKSyncEngine.PendingDatabaseChange] = [
            .saveZone(CKRecordZone(zoneID: healthyZone)),
            .deleteZone(deletedZone),
        ]

        XCTAssertEqual(
            CloudKitFamilyTerminalPendingPruner.recordChanges(
                in: recordChanges,
                matching: deletedZone
            ),
            [.saveRecord(deletedRecordID)]
        )
        XCTAssertEqual(
            CloudKitFamilyTerminalPendingPruner.databaseChanges(
                in: databaseChanges,
                matching: deletedZone
            ),
            [.deleteZone(deletedZone)]
        )
    }

    func testPrivateOwnerBindingBuildsPrivateProviderRecordInPersistedOwnerZone()
        throws
    {
        let fixture = try CloudRoutingFixture()
        defer { fixture.remove() }
        let zoneID = CKRecordZone.ID(
            zoneName: "TadaPrivateProfile",
            ownerName: CKCurrentUserDefaultName
        )
        let rootID = CKRecord.ID(recordName: "private-root", zoneID: zoneID)
        try fixture.store.save(
            binding: ProfileCloudBinding(
                profileID: fixture.privateProfileID,
                state: .privateOwner,
                zoneName: zoneID.zoneName,
                ownerName: zoneID.ownerName,
                rootRecordName: rootID.recordName
            )
        )

        let restarted = CloudKitFamilyMetadataStore(
            snapshotURL: fixture.metadataURL
        )
        let destination = try XCTUnwrap(
            CloudKitFamilyWriteRoutePlanner.destination(
                for: restarted.binding(for: fixture.privateProfileID)
            )
        )
        let cloudRecord = try fixture.cloudRecord(
            profileID: fixture.privateProfileID,
            destination: destination,
            metadataStore: restarted
        )

        XCTAssertEqual(destination.scope, .privateDatabase)
        XCTAssertEqual(cloudRecord.recordID.zoneID, zoneID)
        XCTAssertEqual(cloudRecord.parent?.recordID, rootID)
    }

    func testSharedParticipantBindingBuildsSharedProviderRecordInOwnersZone()
        throws
    {
        let fixture = try CloudRoutingFixture()
        defer { fixture.remove() }
        let ownerZone = CKRecordZone.ID(
            zoneName: "SharedFamilyZone",
            ownerName: "_owner-account-record_"
        )
        let ownerRoot = CKRecord.ID(
            recordName: "shared-owner-root",
            zoneID: ownerZone
        )
        try fixture.store.save(
            binding: ProfileCloudBinding(
                profileID: fixture.sharedProfileID,
                state: .sharedParticipant,
                zoneName: ownerZone.zoneName,
                ownerName: ownerZone.ownerName,
                rootRecordName: ownerRoot.recordName
            )
        )

        let restarted = CloudKitFamilyMetadataStore(
            snapshotURL: fixture.metadataURL
        )
        let destination = try XCTUnwrap(
            CloudKitFamilyWriteRoutePlanner.destination(
                for: restarted.binding(for: fixture.sharedProfileID)
            )
        )
        let cloudRecord = try fixture.cloudRecord(
            profileID: fixture.sharedProfileID,
            destination: destination,
            metadataStore: restarted
        )

        XCTAssertEqual(destination.scope, .sharedDatabase)
        XCTAssertEqual(cloudRecord.recordID.zoneID, ownerZone)
        XCTAssertEqual(cloudRecord.parent?.recordID, ownerRoot)
    }

    func testAccessManagementRoutesOwnerAndParticipantToTheirBoundDatabase() throws {
        let ownerProfileID = ProfileID()
        let participantProfileID = ProfileID()
        let ownerZone = CKRecordZone.ID(
            zoneName: "OwnerAccessZone",
            ownerName: CKCurrentUserDefaultName
        )
        let participantZone = CKRecordZone.ID(
            zoneName: "ParticipantAccessZone",
            ownerName: "_family-owner_"
        )
        let owner = ProfileCloudBinding(
            profileID: ownerProfileID,
            state: .privateOwner,
            zoneName: ownerZone.zoneName,
            ownerName: ownerZone.ownerName,
            rootRecordName: "owner-root"
        )
        let participant = ProfileCloudBinding(
            profileID: participantProfileID,
            state: .sharedParticipant,
            zoneName: participantZone.zoneName,
            ownerName: participantZone.ownerName,
            rootRecordName: "participant-root"
        )

        let ownerLocation = try XCTUnwrap(
            CloudKitFamilyAccessRoutePlanner.location(for: owner)
        )
        let participantLocation = try XCTUnwrap(
            CloudKitFamilyAccessRoutePlanner.location(for: participant)
        )

        XCTAssertEqual(ownerLocation.scope, .privateDatabase)
        XCTAssertEqual(ownerLocation.rootRecordID.zoneID, ownerZone)
        XCTAssertEqual(participantLocation.scope, .sharedDatabase)
        XCTAssertEqual(participantLocation.rootRecordID.zoneID, participantZone)
    }

    func testRevokedSharedBindingHasNoWriteDestinationOrPrivateFallback()
        throws
    {
        let fixture = try CloudRoutingFixture()
        defer { fixture.remove() }
        let formerOwnerZone = CKRecordZone.ID(
            zoneName: "RevokedSharedZone",
            ownerName: "_former-owner_"
        )
        try fixture.store.save(
            binding: ProfileCloudBinding(
                profileID: fixture.sharedProfileID,
                state: .sharedParticipant,
                zoneName: formerOwnerZone.zoneName,
                ownerName: formerOwnerZone.ownerName,
                rootRecordName: "former-root"
            )
        )
        try fixture.store.revokeBinding(for: formerOwnerZone)

        let restarted = CloudKitFamilyMetadataStore(
            snapshotURL: fixture.metadataURL
        )
        let binding = restarted.binding(for: fixture.sharedProfileID)

        XCTAssertEqual(binding.state, .revoked)
        XCTAssertNil(binding.databaseScope)
        XCTAssertNil(CloudKitFamilyWriteRoutePlanner.destination(for: binding))
        XCTAssertNil(CloudKitFamilyAccessRoutePlanner.location(for: binding))
    }

    func testMalformedSharedRouteIsBlockedWhileUnrelatedPrivateRouteStillProvidesRecord()
        throws
    {
        let fixture = try CloudRoutingFixture()
        defer { fixture.remove() }
        let malformedShared = ProfileCloudBinding(
            profileID: fixture.sharedProfileID,
            state: .sharedParticipant,
            zoneName: "SharedWithoutRoot",
            ownerName: "_other-owner_",
            rootRecordName: nil
        )
        let privateZone = CKRecordZone.ID(
            zoneName: "HealthyPrivateZone",
            ownerName: CKCurrentUserDefaultName
        )
        let healthyPrivate = ProfileCloudBinding(
            profileID: fixture.privateProfileID,
            state: .privateOwner,
            zoneName: privateZone.zoneName,
            ownerName: privateZone.ownerName,
            rootRecordName: "healthy-private-root"
        )
        XCTAssertNil(
            CloudKitFamilyWriteRoutePlanner.destination(for: malformedShared)
        )
        XCTAssertThrowsError(
            try fixture.store.save(binding: malformedShared)
        ) { error in
            XCTAssertEqual(
                error as? CloudKitFamilyPersistenceError,
                .corruptMetadata
            )
        }
        try fixture.store.save(binding: healthyPrivate)
        let restarted = CloudKitFamilyMetadataStore(
            snapshotURL: fixture.metadataURL
        )

        let allowed = try XCTUnwrap(
            CloudKitFamilyWriteRoutePlanner.destination(
                for: restarted.binding(for: fixture.privateProfileID)
            )
        )
        let privateRecord = try fixture.cloudRecord(
            profileID: fixture.privateProfileID,
            destination: allowed,
            metadataStore: restarted
        )

        XCTAssertEqual(
            restarted.binding(for: fixture.sharedProfileID),
            .unbound(fixture.sharedProfileID)
        )
        XCTAssertEqual(allowed.scope, .privateDatabase)
        XCTAssertEqual(privateRecord.recordID.zoneID, privateZone)
        XCTAssertEqual(
            privateRecord.parent?.recordID.recordName,
            "healthy-private-root"
        )
    }
}

private struct CloudRoutingFixture {
    let directory: URL
    let metadataURL: URL
    let store: CloudKitFamilyMetadataStore
    let privateProfileID = ProfileID()
    let sharedProfileID = ProfileID()

    init() throws {
        directory = FileManager.default.temporaryDirectory.appendingPathComponent(
            "TadaCloudRouting-\(UUID().uuidString)",
            isDirectory: true
        )
        try FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true
        )
        metadataURL = directory.appendingPathComponent("metadata.json")
        store = CloudKitFamilyMetadataStore(snapshotURL: metadataURL)
        try store.confirm(accountRecordName: "routing-account")
    }

    func cloudRecord(
        profileID: ProfileID,
        destination: CloudKitFamilyWriteDestination,
        metadataStore: CloudKitFamilyMetadataStore
    ) throws -> CKRecord {
        let familyRecord = FamilySyncRecord(
            recordName: "profile-\(profileID)",
            profileID: profileID,
            kind: .wordPoolEntry,
            payload: Data("routing-payload".utf8),
            updatedAt: Date(timeIntervalSince1970: 2_180_000_000),
            deviceID: "routing-device"
        )
        return try CloudKitFamilyRecordCodec.cloudRecord(
            for: familyRecord,
            recordID: CKRecord.ID(
                recordName: familyRecord.recordName,
                zoneID: destination.zoneID
            ),
            rootRecordID: destination.rootRecordID,
            scope: destination.scope,
            metadataStore: metadataStore
        )
    }

    func remove() {
        try? FileManager.default.removeItem(at: directory)
    }
}
