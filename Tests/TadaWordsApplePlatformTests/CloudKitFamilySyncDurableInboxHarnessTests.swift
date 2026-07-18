@preconcurrency import CloudKit
import Foundation
import TadaWordsDomain
import XCTest

@testable import TadaWordsApplePlatform

final class CloudKitFamilySyncDurableInboxHarnessTests: XCTestCase {
    func testInboxSaveDedupesOnlyAnExactEnvelope() throws {
        let fixture = try CloudInboxHarnessFixture()
        defer { fixture.remove() }
        let store = try fixture.configuredStore()
        let original = fixture.record(payload: "same-payload")
        let changedDeletionFlag = FamilySyncRecord(
            recordName: original.recordName,
            profileID: original.profileID,
            kind: original.kind,
            payload: original.payload,
            updatedAt: original.updatedAt,
            deviceID: original.deviceID,
            isDeleted: true,
            schemaVersion: original.schemaVersion,
            minimumReadableVersion: original.minimumReadableVersion,
            logicalRevision: original.logicalRevision
        )
        let changedSchema = FamilySyncRecord(
            recordName: original.recordName,
            profileID: original.profileID,
            kind: original.kind,
            payload: original.payload,
            updatedAt: original.updatedAt,
            deviceID: original.deviceID,
            isDeleted: original.isDeleted,
            schemaVersion: original.schemaVersion + 1,
            minimumReadableVersion: original.minimumReadableVersion,
            logicalRevision: original.logicalRevision
        )
        let recordID = fixture.recordID(name: original.recordName)

        let originalReceipt = try store.appendInbox(
            record: original,
            recordID: recordID,
            scope: .privateDatabase,
            receivedAt: fixture.now
        )
        let exactDuplicateReceipt = try store.appendInbox(
            record: original,
            recordID: recordID,
            scope: .privateDatabase,
            receivedAt: fixture.now.addingTimeInterval(1)
        )
        let deletionReceipt = try store.appendInbox(
            record: changedDeletionFlag,
            recordID: recordID,
            scope: .privateDatabase,
            receivedAt: fixture.now.addingTimeInterval(2)
        )
        let schemaReceipt = try store.appendInbox(
            record: changedSchema,
            recordID: recordID,
            scope: .privateDatabase,
            receivedAt: fixture.now.addingTimeInterval(3)
        )

        XCTAssertEqual(exactDuplicateReceipt, originalReceipt)
        XCTAssertNotEqual(deletionReceipt, originalReceipt)
        XCTAssertNotEqual(schemaReceipt, originalReceipt)
        XCTAssertNotEqual(schemaReceipt, deletionReceipt)
        XCTAssertEqual(
            CloudKitFamilyMetadataStore(snapshotURL: fixture.metadataURL)
                .inboxEntries().map(\.record),
            [original, changedDeletionFlag, changedSchema]
        )
    }

    func testQuarantineEvictionAlsoRemovesItsInvisibleRecordLock() throws {
        let fixture = try CloudInboxHarnessFixture()
        defer { fixture.remove() }
        let store = try fixture.configuredStore()
        for index in 0...200 {
            try store.quarantine(
                CloudKitFamilyQuarantineEntry(
                    id: UUID(),
                    scope: .privateDatabase,
                    recordName: "quarantine-\(index)",
                    zoneName: fixture.zoneID.zoneName,
                    ownerName: fixture.zoneID.ownerName,
                    reason: .compatibility,
                    envelopeData: nil,
                    quarantinedAt: fixture.now.addingTimeInterval(
                        Double(index)
                    )
                )
            )
        }

        let restarted = CloudKitFamilyMetadataStore(
            snapshotURL: fixture.metadataURL
        )
        XCTAssertEqual(restarted.quarantinedCount(), 200)
        XCTAssertFalse(
            restarted.isQuarantined(
                recordID: fixture.recordID(name: "quarantine-0"),
                scope: .privateDatabase
            ),
            "Evicted diagnostics must not leave a permanent hidden lock"
        )
        XCTAssertTrue(
            restarted.isQuarantined(
                recordID: fixture.recordID(name: "quarantine-1"),
                scope: .privateDatabase
            )
        )
        XCTAssertTrue(
            restarted.isQuarantined(
                recordID: fixture.recordID(name: "quarantine-200"),
                scope: .privateDatabase
            )
        )
    }

    func testDurableValidReplacementAtomicallyClearsPriorQuarantine() throws {
        let fixture = try CloudInboxHarnessFixture()
        defer { fixture.remove() }
        let store = try fixture.configuredStore()
        let record = fixture.record(
            name: "repaired-record",
            payload: "valid replacement"
        )
        let recordID = fixture.recordID(name: record.recordName)
        try store.quarantine(
            CloudKitFamilyQuarantineEntry(
                id: UUID(),
                scope: .privateDatabase,
                recordName: recordID.recordName,
                zoneName: recordID.zoneID.zoneName,
                ownerName: recordID.zoneID.ownerName,
                reason: .compatibility,
                envelopeData: Data("old corrupt envelope".utf8),
                quarantinedAt: fixture.now
            )
        )

        let receipt = try store.appendInboxReplacingQuarantine(
            record: record,
            recordID: recordID,
            scope: .privateDatabase,
            receivedAt: fixture.now.addingTimeInterval(1)
        )

        let restarted = CloudKitFamilyMetadataStore(
            snapshotURL: fixture.metadataURL
        )
        XCTAssertEqual(restarted.inboxEntries().map(\.receiptID), [receipt])
        XCTAssertEqual(restarted.inboxEntries().first?.record, record)
        XCTAssertEqual(restarted.quarantinedCount(), 0)
        XCTAssertFalse(
            restarted.isQuarantined(
                recordID: recordID,
                scope: .privateDatabase
            )
        )
    }

    func testInboxSaveAndDeletionReplayAcrossRestartUntilEachReceiptIsAcknowledged()
        async throws
    {
        let fixture = try CloudInboxHarnessFixture()
        defer { fixture.remove() }
        let store = try fixture.configuredStore()
        let record = fixture.record(payload: "Mia")
        let saveID = fixture.recordID(name: record.recordName)
        let deletionKey = FamilySyncChangeKey(
            profileID: fixture.profileID,
            recordName: "word-old"
        )
        let deleteID = fixture.recordID(name: deletionKey.recordName)
        let saveReceipt = try store.appendInbox(
            record: record,
            recordID: saveID,
            scope: .privateDatabase,
            receivedAt: fixture.now
        )
        let duplicateSaveReceipt = try store.appendInbox(
            record: record,
            recordID: saveID,
            scope: .privateDatabase,
            receivedAt: fixture.now.addingTimeInterval(1)
        )
        let deleteReceipt = try store.appendInbox(
            deletionKey: deletionKey,
            recordID: deleteID,
            scope: .privateDatabase,
            receivedAt: fixture.now
        )
        let duplicateDeleteReceipt = try store.appendInbox(
            deletionKey: deletionKey,
            recordID: deleteID,
            scope: .privateDatabase,
            receivedAt: fixture.now.addingTimeInterval(1)
        )
        XCTAssertEqual(duplicateSaveReceipt, saveReceipt)
        XCTAssertEqual(duplicateDeleteReceipt, deleteReceipt)

        let restarted = CloudKitFamilyMetadataStore(snapshotURL: fixture.metadataURL)
        let durableEntries = restarted.inboxEntries()
        XCTAssertEqual(durableEntries.count, 2)
        let buffer = CloudKitFamilySyncEventBuffer(metadataStore: restarted)
        await buffer.replay(durableEntries, generation: 1)
        let replayed = await buffer.drain()
        XCTAssertEqual(replayed.records, [record])
        XCTAssertEqual(replayed.deletions, [FamilySyncRemoteDeletion(key: deletionKey)])
        XCTAssertEqual(replayed.receiptIDs, [saveReceipt, deleteReceipt])
        XCTAssertEqual(Set(replayed.receipts.map(\.id)), replayed.receiptIDs)

        try restarted.acknowledgeInbox(receiptIDs: [saveReceipt])
        let afterPartialAck = CloudKitFamilyMetadataStore(
            snapshotURL: fixture.metadataURL
        ).inboxEntries()
        XCTAssertEqual(afterPartialAck.map(\.receiptID), [deleteReceipt])

        try restarted.acknowledgeInbox(receiptIDs: [deleteReceipt])
        let afterFullAck = CloudKitFamilyMetadataStore(
            snapshotURL: fixture.metadataURL
        ).inboxEntries()
        XCTAssertTrue(afterFullAck.isEmpty)
    }

    func testFetchedRecordIsNotExposedWhenDurableInboxWriteFails() async throws {
        let fixture = try CloudInboxHarnessFixture()
        defer { fixture.remove() }
        let store = try fixture.configuredStore()
        let record = fixture.record(payload: "must-be-durable")
        let cloudRecord = try fixture.cloudRecord(for: record, store: store)
        let buffer = CloudKitFamilySyncEventBuffer(metadataStore: store)

        try FileManager.default.removeItem(at: fixture.directory)
        try Data("blocks-directory-recreation".utf8).write(
            to: fixture.directory,
            options: .atomic
        )
        await buffer.handle(
            .fetchedRecords([cloudRecord]),
            scope: .privateDatabase,
            generation: 1,
            now: fixture.now
        )
        let result = await buffer.drain()
        let canPersistState = await buffer.canPersistEngineState(1)

        XCTAssertTrue(result.records.isEmpty)
        XCTAssertTrue(result.receiptIDs.isEmpty)
        XCTAssertEqual(result.failures.map(\.category), [.corruptState])
        XCTAssertFalse(canPersistState)
    }

    func testSameRevisionWithDifferentChecksumQuarantinesConflictingRecordInEitherOrder()
        async throws
    {
        try await assertSameRevisionConflict(first: "alpha", second: "beta")
        try await assertSameRevisionConflict(first: "beta", second: "alpha")
    }

    func testGoodRecordAppliesWhileWrongProfileAndMalformedEnvelopeAreQuarantined()
        async throws
    {
        let fixture = try CloudInboxHarnessFixture()
        defer { fixture.remove() }
        let store = try fixture.configuredStore()
        let good = fixture.record(name: "good", payload: "good")
        let goodCloud = try fixture.cloudRecord(for: good, store: store)

        let wrongProfile = ProfileID()
        let wrong = FamilySyncRecord(
            recordName: "wrong-profile",
            profileID: wrongProfile,
            kind: .profile,
            payload: Data("wrong".utf8),
            updatedAt: fixture.now,
            deviceID: "remote",
            logicalRevision: FamilySyncLogicalRevision(
                counter: 1,
                deviceID: "remote"
            )
        )
        let wrongID = fixture.recordID(name: wrong.recordName)
        let wrongCloud = try CloudKitFamilyRecordCodec.cloudRecord(
            for: wrong,
            recordID: wrongID,
            rootRecordID: fixture.rootRecordID,
            scope: .privateDatabase,
            metadataStore: store
        )

        let malformedID = fixture.recordID(name: "malformed")
        let malformed = CKRecord(
            recordType: CloudKitFamilyRecordCodec.Schema.itemRecordType,
            recordID: malformedID
        )
        malformed[CloudKitFamilyRecordCodec.Schema.profileID] =
            fixture.profileID.rawValue.uuidString as NSString
        malformed[CloudKitFamilyRecordCodec.Schema.kind] =
            FamilySyncRecordKind.profile.rawValue as NSString
        malformed[CloudKitFamilyRecordCodec.Schema.schemaVersion] = NSNumber(value: 2)
        malformed[CloudKitFamilyRecordCodec.Schema.envelope] =
            Data("not-an-envelope".utf8) as NSData

        let buffer = CloudKitFamilySyncEventBuffer(metadataStore: store)
        await buffer.handle(
            .fetchedRecords([wrongCloud, goodCloud, malformed]),
            scope: .privateDatabase,
            generation: 1,
            now: fixture.now
        )
        let result = await buffer.drain()

        XCTAssertEqual(result.records, [good])
        XCTAssertEqual(result.quarantinedRecordCount, 2)
        XCTAssertEqual(store.inboxEntries().count, 1)
        XCTAssertTrue(
            store.isQuarantined(
                recordID: wrongID,
                scope: .privateDatabase
            )
        )
        XCTAssertTrue(
            store.isQuarantined(
                recordID: malformedID,
                scope: .privateDatabase
            )
        )
    }

    func testOversizedLegacyV1PayloadIsQuarantinedBeforeDurableInbox()
        async throws
    {
        let fixture = try CloudInboxHarnessFixture()
        defer { fixture.remove() }
        let store = try fixture.configuredStore()
        let legacyID = fixture.recordID(name: "oversized-legacy-v1")
        let legacy = CKRecord(
            recordType: CloudKitFamilyRecordCodec.Schema.itemRecordType,
            recordID: legacyID
        )
        legacy[CloudKitFamilyRecordCodec.Schema.profileID] =
            fixture.profileID.rawValue.uuidString as NSString
        legacy[CloudKitFamilyRecordCodec.Schema.kind] =
            FamilySyncRecordKind.profile.rawValue as NSString
        legacy[CloudKitFamilyRecordCodec.Schema.payload] =
            Data(
                repeating: 0x41,
                count: FamilySyncRecord.maximumPayloadSize + 1
            ) as NSData
        legacy[CloudKitFamilyRecordCodec.Schema.updatedAt] = fixture.now as NSDate
        legacy[CloudKitFamilyRecordCodec.Schema.deviceID] = "legacy-device" as NSString
        legacy[CloudKitFamilyRecordCodec.Schema.isDeleted] = NSNumber(value: false)
        let buffer = CloudKitFamilySyncEventBuffer(metadataStore: store)

        await buffer.handle(
            .fetchedRecords([legacy]),
            scope: .privateDatabase,
            generation: 1,
            now: fixture.now
        )
        let result = await buffer.drain()

        XCTAssertTrue(result.records.isEmpty)
        XCTAssertTrue(result.receiptIDs.isEmpty)
        XCTAssertEqual(result.quarantinedRecordCount, 1)
        XCTAssertTrue(store.inboxEntries().isEmpty)
        XCTAssertTrue(
            store.isQuarantined(
                recordID: legacyID,
                scope: .privateDatabase
            )
        )
    }

    func testCorrectedFetchReplacesFutureQuarantineAndBecomesDurable()
        async throws
    {
        let fixture = try CloudInboxHarnessFixture()
        defer { fixture.remove() }
        let store = try fixture.configuredStore()
        let corrected = fixture.record(
            name: "corrected-after-upgrade",
            payload: "valid-current-payload"
        )
        let recordID = fixture.recordID(name: corrected.recordName)
        let future = FamilySyncRecord(
            recordName: corrected.recordName,
            profileID: corrected.profileID,
            kind: corrected.kind,
            payload: Data("future-payload".utf8),
            updatedAt: fixture.now,
            deviceID: "future-device",
            schemaVersion: FamilySyncRecord.currentSchemaVersion + 1
        )
        let futureCloud = CKRecord(
            recordType: CloudKitFamilyRecordCodec.Schema.itemRecordType,
            recordID: recordID
        )
        futureCloud[CloudKitFamilyRecordCodec.Schema.profileID] =
            fixture.profileID.rawValue.uuidString as NSString
        futureCloud[CloudKitFamilyRecordCodec.Schema.kind] =
            future.kind.rawValue as NSString
        futureCloud[CloudKitFamilyRecordCodec.Schema.schemaVersion] = NSNumber(
            value: future.schemaVersion
        )
        futureCloud[CloudKitFamilyRecordCodec.Schema.envelope] =
            try JSONEncoder()
            .encode(FamilySyncEnvelope(record: future)) as NSData
        let buffer = CloudKitFamilySyncEventBuffer(metadataStore: store)

        await buffer.handle(
            .fetchedRecords([futureCloud]),
            scope: .privateDatabase,
            generation: 1,
            now: fixture.now
        )
        let rejected = await buffer.drain()
        XCTAssertTrue(rejected.records.isEmpty)
        XCTAssertEqual(rejected.quarantinedRecordCount, 1)
        XCTAssertTrue(store.inboxEntries().isEmpty)
        XCTAssertTrue(
            store.isQuarantined(
                recordID: recordID,
                scope: .privateDatabase
            )
        )

        let correctedCloud = try fixture.cloudRecord(for: corrected, store: store)
        await buffer.handle(
            .fetchedRecords([correctedCloud]),
            scope: .privateDatabase,
            generation: 1,
            now: fixture.now.addingTimeInterval(1)
        )
        let accepted = await buffer.drain()
        let restarted = CloudKitFamilyMetadataStore(
            snapshotURL: fixture.metadataURL
        )

        XCTAssertEqual(accepted.records, [corrected])
        XCTAssertEqual(accepted.receiptIDs.count, 1)
        XCTAssertEqual(restarted.inboxEntries().map(\.record), [corrected])
        XCTAssertEqual(restarted.quarantinedCount(), 0)
        XCTAssertFalse(
            restarted.isQuarantined(
                recordID: recordID,
                scope: .privateDatabase
            )
        )
    }

    func testItemArrivingBeforeRootInOneCallbackUsesNewlyBoundRoute()
        async throws
    {
        let fixture = try CloudInboxHarnessFixture()
        defer { fixture.remove() }
        let store = CloudKitFamilyMetadataStore(snapshotURL: fixture.metadataURL)
        let record = fixture.record(payload: "first-device-payload")
        let item = try fixture.cloudRecord(for: record, store: store)
        let root = CKRecord(
            recordType: CloudKitFamilyRecordCodec.Schema.rootRecordType,
            recordID: fixture.rootRecordID
        )
        root[CloudKitFamilyRecordCodec.Schema.profileID] =
            fixture.profileID.rawValue.uuidString as NSString
        let buffer = CloudKitFamilySyncEventBuffer(metadataStore: store)

        await buffer.handle(
            .fetchedRecords([item, root]),
            scope: .privateDatabase,
            generation: 1,
            now: fixture.now
        )
        let result = await buffer.drain()

        XCTAssertEqual(result.records, [record])
        XCTAssertEqual(store.inboxEntries().count, 1)
        XCTAssertEqual(store.binding(for: fixture.profileID).state, .privateOwner)
        XCTAssertEqual(
            store.binding(for: fixture.profileID).rootRecordID,
            fixture.rootRecordID
        )
    }

    func testAccountSwitchDropsOldAccountInboxAndNeverRebindsSharedProfileAsPrivate()
        throws
    {
        let fixture = try CloudInboxHarnessFixture()
        defer { fixture.remove() }
        let store = try fixture.configuredStore()
        try store.confirm(accountRecordName: "account-a")
        let sharedProfileID = ProfileID()
        let sharedZoneID = CKRecordZone.ID(
            zoneName: "SharedFamily",
            ownerName: "other-owner"
        )
        try store.save(
            binding: ProfileCloudBinding(
                profileID: sharedProfileID,
                state: .sharedParticipant,
                zoneName: sharedZoneID.zoneName,
                ownerName: sharedZoneID.ownerName,
                rootRecordName: nil
            )
        )
        let privateRecord = fixture.record(payload: "private")
        _ = try store.appendInbox(
            record: privateRecord,
            recordID: fixture.recordID(name: privateRecord.recordName),
            scope: .privateDatabase,
            receivedAt: fixture.now
        )
        let sharedRecord = FamilySyncRecord(
            recordName: "shared-profile",
            profileID: sharedProfileID,
            kind: .profile,
            payload: Data("shared".utf8),
            updatedAt: fixture.now,
            deviceID: "remote"
        )
        _ = try store.appendInbox(
            record: sharedRecord,
            recordID: CKRecord.ID(
                recordName: sharedRecord.recordName,
                zoneID: sharedZoneID
            ),
            scope: .sharedDatabase,
            receivedAt: fixture.now
        )

        let gate = try store.accountGate(currentAccountRecordName: "account-b")
        XCTAssertEqual(gate, .requiresConfirmation(.switchedAccounts))

        let restarted = CloudKitFamilyMetadataStore(snapshotURL: fixture.metadataURL)
        XCTAssertTrue(restarted.inboxEntries().isEmpty)
        XCTAssertEqual(restarted.binding(for: fixture.profileID).state, .unbound)
        XCTAssertEqual(restarted.binding(for: sharedProfileID).state, .revoked)
        XCTAssertNil(restarted.binding(for: sharedProfileID).databaseScope)

        // Confirmation invokes account invalidation again. A formerly shared
        // route must remain terminal through that second pass instead of
        // becoming `.unbound` and uploading the owner's Profile as a new
        // private copy in the participant's replacement account.
        try restarted.confirm(accountRecordName: "account-b")
        let confirmed = CloudKitFamilyMetadataStore(
            snapshotURL: fixture.metadataURL
        )
        XCTAssertEqual(confirmed.binding(for: sharedProfileID).state, .revoked)
        XCTAssertNil(confirmed.binding(for: sharedProfileID).databaseScope)
    }

    func testCorruptMetadataSnapshotFailsClosedAtAccountGate() throws {
        let fixture = try CloudInboxHarnessFixture()
        defer { fixture.remove() }
        let corruptBytes = Data("corrupt-cloudkit-metadata".utf8)
        try corruptBytes.write(
            to: fixture.metadataURL,
            options: .atomic
        )
        let store = CloudKitFamilyMetadataStore(snapshotURL: fixture.metadataURL)

        XCTAssertThrowsError(
            try store.accountGate(currentAccountRecordName: "account-a")
        ) { error in
            XCTAssertEqual(
                error as? CloudKitFamilyPersistenceError,
                .corruptMetadata
            )
        }
        XCTAssertEqual(try Data(contentsOf: fixture.metadataURL), corruptBytes)
    }

    func testServerRecordChangedForExactCommittedEnvelopeAcknowledgesInterruptedSave()
        async throws
    {
        let fixture = try CloudInboxHarnessFixture()
        defer { fixture.remove() }
        let store = try fixture.configuredStore()
        let record = fixture.record(payload: "already-committed")
        let pending = FamilySyncPendingOperation.save(record)
        let cloudRecord = try fixture.cloudRecord(for: record, store: store)
        let acknowledgement = FamilySyncChangeAcknowledgement(operation: pending)
        let buffer = CloudKitFamilySyncEventBuffer(metadataStore: store)
        await buffer.register(
            CloudKitFamilyOutgoingChange(
                acknowledgement: acknowledgement,
                record: cloudRecord
            ),
            recordID: cloudRecord.recordID,
            scope: .privateDatabase,
            generation: 1
        )
        let error = CKError(
            _nsError: NSError(
                domain: CKErrorDomain,
                code: CKError.Code.serverRecordChanged.rawValue,
                userInfo: [
                    CKRecordChangedErrorClientRecordKey: cloudRecord,
                    CKRecordChangedErrorServerRecordKey: cloudRecord,
                ]
            )
        )

        await buffer.handle(
            .sentRecords(saved: [], failed: [(cloudRecord, error)]),
            scope: .privateDatabase,
            generation: 1,
            now: fixture.now
        )
        let result = await buffer.drain()

        XCTAssertEqual(result.acknowledged, [acknowledgement])
        XCTAssertTrue(result.failures.isEmpty)
        XCTAssertNotNil(
            store.restoredRecord(
                id: cloudRecord.recordID,
                scope: .privateDatabase
            )
        )
    }

    func testServerRecordChangedRequiresExactSchemaAndUpdatedAtBeforeAcknowledging()
        async throws
    {
        try await assertNonExactServerValueIsNotAcknowledged(
            schemaVersion: 1,
            updatedAtOffset: 0
        )
        try await assertNonExactServerValueIsNotAcknowledged(
            schemaVersion: FamilySyncRecord.currentSchemaVersion,
            updatedAtOffset: 1
        )
    }

    func testOpaqueEngineStateRoundTripsPerDatabaseScopeAcrossStoreRestart()
        throws
    {
        let fixture = try CloudInboxHarnessFixture()
        defer { fixture.remove() }
        let stateDirectory = fixture.directory.appendingPathComponent(
            "engine-state",
            isDirectory: true
        )
        let privateSerialization = try JSONDecoder().decode(
            CKSyncEngine.State.Serialization.self,
            from: Data(#"{"data":"cHJpdmF0ZS10b2tlbg=="}"#.utf8)
        )
        let sharedSerialization = try JSONDecoder().decode(
            CKSyncEngine.State.Serialization.self,
            from: Data(#"{"data":"c2hhcmVkLXRva2Vu"}"#.utf8)
        )
        let store = CloudKitFamilySyncStateStore(directory: stateDirectory)
        XCTAssertTrue(store.save(privateSerialization, scope: .privateDatabase))
        XCTAssertTrue(store.save(sharedSerialization, scope: .sharedDatabase))

        let restarted = CloudKitFamilySyncStateStore(directory: stateDirectory)
        let privateRestored = try XCTUnwrap(restarted.load(.privateDatabase))
        let sharedRestored = try XCTUnwrap(restarted.load(.sharedDatabase))

        XCTAssertEqual(
            try JSONEncoder().encode(privateRestored),
            try JSONEncoder().encode(privateSerialization)
        )
        XCTAssertEqual(
            try JSONEncoder().encode(sharedRestored),
            try JSONEncoder().encode(sharedSerialization)
        )
        XCTAssertNotEqual(
            try JSONEncoder().encode(privateRestored),
            try JSONEncoder().encode(sharedRestored),
            "Private and shared CKSyncEngine tokens must never cross scopes"
        )
    }

    func testCorruptPrivateEngineStateIsIsolatedAndRecoveredWithoutTouchingSharedBytes()
        throws
    {
        let fixture = try CloudInboxHarnessFixture()
        defer { fixture.remove() }
        let stateDirectory = fixture.directory.appendingPathComponent(
            "corrupt-engine-state",
            isDirectory: true
        )
        try FileManager.default.createDirectory(
            at: stateDirectory,
            withIntermediateDirectories: true
        )
        let privateURL = stateDirectory.appendingPathComponent(
            "privateDatabase-engine-state.json"
        )
        let sharedURL = stateDirectory.appendingPathComponent(
            "sharedDatabase-engine-state.json"
        )
        let corruptPrivate = Data("corrupt-private-engine-state".utf8)
        let untouchedShared = Data("unread-shared-sentinel".utf8)
        try corruptPrivate.write(to: privateURL, options: .atomic)
        try untouchedShared.write(to: sharedURL, options: .atomic)
        let store = CloudKitFamilySyncStateStore(directory: stateDirectory)

        XCTAssertNil(store.load(.privateDatabase))
        XCTAssertTrue(store.recoveredCorruptState())
        XCTAssertFalse(FileManager.default.fileExists(atPath: privateURL.path))
        XCTAssertEqual(try Data(contentsOf: sharedURL), untouchedShared)
    }

    func testFailedKeyCannotLeakStaleOutgoingIntoLaterUnrelatedSend()
        async throws
    {
        let fixture = try CloudInboxHarnessFixture()
        defer { fixture.remove() }
        let store = try fixture.configuredStore()
        let failedRecord = fixture.record(name: "failed-key", payload: "failed")
        let unrelatedRecord = fixture.record(
            name: "unrelated-key",
            payload: "unrelated"
        )
        let failedCloud = try fixture.cloudRecord(for: failedRecord, store: store)
        let unrelatedCloud = try fixture.cloudRecord(
            for: unrelatedRecord,
            store: store
        )
        let failedAcknowledgement = FamilySyncChangeAcknowledgement(
            operation: .save(failedRecord)
        )
        let unrelatedAcknowledgement = FamilySyncChangeAcknowledgement(
            operation: .save(unrelatedRecord)
        )
        let buffer = CloudKitFamilySyncEventBuffer(metadataStore: store)
        await buffer.register(
            CloudKitFamilyOutgoingChange(
                acknowledgement: failedAcknowledgement,
                record: failedCloud
            ),
            recordID: failedCloud.recordID,
            scope: .privateDatabase,
            generation: 1
        )
        let networkError = CKError(
            _nsError: NSError(
                domain: CKErrorDomain,
                code: CKError.Code.networkFailure.rawValue
            )
        )
        await buffer.handle(
            .sentRecords(saved: [], failed: [(failedCloud, networkError)]),
            scope: .privateDatabase,
            generation: 1,
            now: fixture.now
        )
        let failedResult = await buffer.drain()
        let staleRecord = await buffer.record(
            for: failedCloud.recordID,
            scope: .privateDatabase,
            generation: 1
        )
        XCTAssertEqual(failedResult.failures.map(\.category), [.connectivity])
        XCTAssertNil(staleRecord)

        await buffer.register(
            CloudKitFamilyOutgoingChange(
                acknowledgement: unrelatedAcknowledgement,
                record: unrelatedCloud
            ),
            recordID: unrelatedCloud.recordID,
            scope: .privateDatabase,
            generation: 1
        )
        await buffer.handle(
            .sentRecords(saved: [failedCloud, unrelatedCloud], failed: []),
            scope: .privateDatabase,
            generation: 1,
            now: fixture.now
        )
        let unrelatedResult = await buffer.drain()

        XCTAssertEqual(unrelatedResult.acknowledged, [unrelatedAcknowledgement])
        XCTAssertFalse(unrelatedResult.acknowledged.contains(failedAcknowledgement))
    }

    func testOldAccountCallbacksCannotReplayAcrossNewAccountConfirmation()
        async throws
    {
        let fixture = try CloudInboxHarnessFixture()
        defer { fixture.remove() }
        let store = try fixture.configuredStore()
        try store.confirm(accountRecordName: "old-account")
        let oldRecord = fixture.record(payload: "old-account-payload")
        let oldCloud = try fixture.cloudRecord(for: oldRecord, store: store)
        let buffer = CloudKitFamilySyncEventBuffer(metadataStore: store)
        await buffer.handle(
            .fetchedRecords([oldCloud]),
            scope: .privateDatabase,
            generation: 1,
            now: fixture.now
        )
        XCTAssertEqual(store.inboxEntries().count, 1)

        let newGeneration = await buffer.nextGeneration()
        XCTAssertEqual(newGeneration, 2)
        try store.confirm(accountRecordName: "new-account")
        XCTAssertTrue(store.inboxEntries().isEmpty)
        await buffer.handle(
            .fetchedRecords([oldCloud]),
            scope: .privateDatabase,
            generation: 1,
            now: fixture.now.addingTimeInterval(1)
        )

        let restarted = CloudKitFamilyMetadataStore(snapshotURL: fixture.metadataURL)
        let replayBuffer = CloudKitFamilySyncEventBuffer(metadataStore: restarted)
        await replayBuffer.replay(restarted.inboxEntries(), generation: 1)
        let replayed = await replayBuffer.drain()
        XCTAssertTrue(replayed.records.isEmpty)
        XCTAssertTrue(replayed.receiptIDs.isEmpty)
        XCTAssertTrue(restarted.inboxEntries().isEmpty)
    }

    func testAccountConfirmationReportsOnlyAChangedAccountGeneration() throws {
        let fixture = try CloudInboxHarnessFixture()
        defer { fixture.remove() }
        let store = try fixture.configuredStore()

        XCTAssertEqual(
            try store.confirm(accountRecordName: "account-a"),
            .signedIn
        )
        try store.requireAccountConfirmation()
        XCTAssertNil(
            try store.confirm(accountRecordName: "account-a"),
            "Reauthorizing the same account must not requeue every acknowledged record"
        )
        try store.requireAccountConfirmation()
        XCTAssertEqual(
            try store.confirm(accountRecordName: "account-b"),
            .switchedAccounts
        )
    }

    func testOldGenerationAccountCallbackCannotInvalidateConfirmedAccount()
        async throws
    {
        let fixture = try CloudInboxHarnessFixture()
        defer { fixture.remove() }
        let store = try fixture.configuredStore()
        try store.confirm(accountRecordName: "new-account")
        let buffer = CloudKitFamilySyncEventBuffer(metadataStore: store)
        let newGeneration = await buffer.nextGeneration()

        await buffer.handle(
            .accountChange(.signedOut),
            scope: .privateDatabase,
            generation: newGeneration - 1,
            now: fixture.now
        )

        XCTAssertEqual(
            try store.accountGate(currentAccountRecordName: "new-account"),
            .authorized,
            "A late callback from a replaced engine must not mutate new-account metadata"
        )
    }

    func testAccountBoundaryRejectsLaterCallbacksFromSameEngineGeneration()
        async throws
    {
        let fixture = try CloudInboxHarnessFixture()
        defer { fixture.remove() }
        let store = try fixture.configuredStore()
        try store.confirm(accountRecordName: "old-account")
        let oldRecord = fixture.record(payload: "old-account-payload")
        let oldCloud = try fixture.cloudRecord(for: oldRecord, store: store)
        let buffer = CloudKitFamilySyncEventBuffer(metadataStore: store)

        await buffer.handle(
            .accountChange(.switchedAccounts),
            scope: .privateDatabase,
            generation: 1,
            now: fixture.now
        )
        await buffer.handle(
            .fetchedRecords([oldCloud]),
            scope: .privateDatabase,
            generation: 1,
            now: fixture.now.addingTimeInterval(1)
        )
        let firstDrain = await buffer.drain()
        let secondDrain = await buffer.drain()

        XCTAssertEqual(firstDrain.accountChange, .switchedAccounts)
        XCTAssertEqual(secondDrain.accountChange, .switchedAccounts)
        XCTAssertTrue(firstDrain.records.isEmpty)
        XCTAssertTrue(store.inboxEntries().isEmpty)
    }

    func testThreeOrMoreImmutableVariantsForOneUUIDAreAllQuarantined()
        async throws
    {
        try await assertImmutableVariantSetIsFullyQuarantined(
            payloads: ["alpha", "beta", "gamma", "delta"]
        )
        try await assertImmutableVariantSetIsFullyQuarantined(
            payloads: ["delta", "gamma", "beta", "alpha"]
        )
    }

    private func assertSameRevisionConflict(
        first firstPayload: String,
        second secondPayload: String,
        file: StaticString = #filePath,
        line: UInt = #line
    ) async throws {
        let fixture = try CloudInboxHarnessFixture()
        defer { fixture.remove() }
        let store = try fixture.configuredStore()
        let revision = FamilySyncLogicalRevision(counter: 7, deviceID: "remote")
        let first = fixture.record(payload: firstPayload, revision: revision)
        let second = fixture.record(payload: secondPayload, revision: revision)
        let firstCloud = try fixture.cloudRecord(for: first, store: store)
        let secondCloud = try fixture.cloudRecord(for: second, store: store)
        let buffer = CloudKitFamilySyncEventBuffer(metadataStore: store)

        await buffer.handle(
            .fetchedRecords([firstCloud, secondCloud]),
            scope: .privateDatabase,
            generation: 1,
            now: fixture.now
        )
        let result = await buffer.drain()

        XCTAssertTrue(result.records.isEmpty, file: file, line: line)
        XCTAssertEqual(result.quarantinedRecordCount, 2, file: file, line: line)
        XCTAssertTrue(result.receiptIDs.isEmpty, file: file, line: line)
        XCTAssertTrue(store.inboxEntries().isEmpty, file: file, line: line)
        XCTAssertTrue(
            store.isQuarantined(
                recordID: fixture.recordID(name: first.recordName),
                scope: .privateDatabase
            ),
            file: file,
            line: line
        )
    }

    private func assertNonExactServerValueIsNotAcknowledged(
        schemaVersion: Int,
        updatedAtOffset: TimeInterval,
        file: StaticString = #filePath,
        line: UInt = #line
    ) async throws {
        let fixture = try CloudInboxHarnessFixture()
        defer { fixture.remove() }
        let store = try fixture.configuredStore()
        let revision = FamilySyncLogicalRevision(counter: 4, deviceID: "remote")
        let expected = FamilySyncRecord(
            recordName: "profile",
            profileID: fixture.profileID,
            kind: .profile,
            payload: Data("same-payload".utf8),
            updatedAt: fixture.now,
            deviceID: revision.deviceID,
            logicalRevision: revision
        )
        let server = FamilySyncRecord(
            recordName: expected.recordName,
            profileID: expected.profileID,
            kind: expected.kind,
            payload: expected.payload,
            updatedAt: fixture.now.addingTimeInterval(updatedAtOffset),
            deviceID: revision.deviceID,
            schemaVersion: schemaVersion,
            minimumReadableVersion: expected.minimumReadableVersion,
            logicalRevision: revision
        )
        XCTAssertNotEqual(expected, server, file: file, line: line)
        let expectedCloud = try fixture.cloudRecord(for: expected, store: store)
        let serverCloud = try fixture.cloudRecord(for: server, store: store)
        let acknowledgement = FamilySyncChangeAcknowledgement(
            operation: .save(expected)
        )
        let buffer = CloudKitFamilySyncEventBuffer(metadataStore: store)
        await buffer.register(
            CloudKitFamilyOutgoingChange(
                acknowledgement: acknowledgement,
                record: expectedCloud
            ),
            recordID: expectedCloud.recordID,
            scope: .privateDatabase,
            generation: 1
        )
        let error = CKError(
            _nsError: NSError(
                domain: CKErrorDomain,
                code: CKError.Code.serverRecordChanged.rawValue,
                userInfo: [
                    CKRecordChangedErrorClientRecordKey: expectedCloud,
                    CKRecordChangedErrorServerRecordKey: serverCloud,
                ]
            )
        )

        await buffer.handle(
            .sentRecords(saved: [], failed: [(expectedCloud, error)]),
            scope: .privateDatabase,
            generation: 1,
            now: fixture.now
        )
        let result = await buffer.drain()

        XCTAssertTrue(result.acknowledged.isEmpty, file: file, line: line)
        XCTAssertEqual(
            result.failures.map(\.category),
            [.conflict],
            file: file,
            line: line
        )
        XCTAssertEqual(store.inboxEntries().map(\.record), [server], file: file, line: line)
    }

    private func assertImmutableVariantSetIsFullyQuarantined(
        payloads: [String],
        file: StaticString = #filePath,
        line: UInt = #line
    ) async throws {
        let fixture = try CloudInboxHarnessFixture()
        defer { fixture.remove() }
        let store = try fixture.configuredStore()
        let records = payloads.enumerated().map { index, payload in
            FamilySyncRecord(
                recordName: "attempt-stable-uuid",
                profileID: fixture.profileID,
                kind: .attempt,
                payload: Data(payload.utf8),
                updatedAt: fixture.now.addingTimeInterval(Double(index)),
                deviceID: "device-\(index)",
                logicalRevision: FamilySyncLogicalRevision(
                    counter: UInt64(index + 1),
                    deviceID: "device-\(index)"
                )
            )
        }
        let cloudRecords = try records.map {
            try fixture.cloudRecord(for: $0, store: store)
        }
        let buffer = CloudKitFamilySyncEventBuffer(metadataStore: store)

        await buffer.handle(
            .fetchedRecords(cloudRecords),
            scope: .privateDatabase,
            generation: 1,
            now: fixture.now
        )
        let result = await buffer.drain()

        XCTAssertTrue(result.records.isEmpty, file: file, line: line)
        XCTAssertTrue(result.receiptIDs.isEmpty, file: file, line: line)
        XCTAssertTrue(store.inboxEntries().isEmpty, file: file, line: line)
        XCTAssertEqual(
            result.quarantinedRecordCount,
            payloads.count,
            "Once an immutable UUID conflicts, no later variant may pass through",
            file: file,
            line: line
        )
        XCTAssertTrue(
            store.isQuarantined(
                recordID: fixture.recordID(name: "attempt-stable-uuid"),
                scope: .privateDatabase
            ),
            file: file,
            line: line
        )
    }
}

private struct CloudInboxHarnessFixture {
    let directory: URL
    let metadataURL: URL
    let profileID = ProfileID()
    let now = Date(timeIntervalSince1970: 2_120_000_000)
    let zoneID: CKRecordZone.ID
    let rootRecordID: CKRecord.ID

    init() throws {
        directory = FileManager.default.temporaryDirectory.appendingPathComponent(
            "TadaCloudInboxHarness-\(UUID().uuidString)",
            isDirectory: true
        )
        try FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true
        )
        metadataURL = directory.appendingPathComponent("metadata.json")
        zoneID = CKRecordZone.ID(
            zoneName: "TadaCloudInboxHarnessZone",
            ownerName: CKCurrentUserDefaultName
        )
        rootRecordID = CKRecord.ID(
            recordName: "profile-root",
            zoneID: zoneID
        )
    }

    func configuredStore() throws -> CloudKitFamilyMetadataStore {
        let store = CloudKitFamilyMetadataStore(snapshotURL: metadataURL)
        try store.save(
            binding: ProfileCloudBinding(
                profileID: profileID,
                state: .privateOwner,
                zoneName: zoneID.zoneName,
                ownerName: zoneID.ownerName,
                rootRecordName: rootRecordID.recordName
            )
        )
        return store
    }

    func record(
        name: String = "profile",
        payload: String,
        revision: FamilySyncLogicalRevision = FamilySyncLogicalRevision(
            counter: 1,
            deviceID: "remote"
        )
    ) -> FamilySyncRecord {
        FamilySyncRecord(
            recordName: name,
            profileID: profileID,
            kind: .profile,
            payload: Data(payload.utf8),
            updatedAt: now,
            deviceID: revision.deviceID,
            logicalRevision: revision
        )
    }

    func recordID(name: String) -> CKRecord.ID {
        CKRecord.ID(recordName: name, zoneID: zoneID)
    }

    func cloudRecord(
        for record: FamilySyncRecord,
        store: CloudKitFamilyMetadataStore
    ) throws -> CKRecord {
        try CloudKitFamilyRecordCodec.cloudRecord(
            for: record,
            recordID: recordID(name: record.recordName),
            rootRecordID: rootRecordID,
            scope: .privateDatabase,
            metadataStore: store
        )
    }

    func remove() {
        try? FileManager.default.removeItem(at: directory)
    }
}
