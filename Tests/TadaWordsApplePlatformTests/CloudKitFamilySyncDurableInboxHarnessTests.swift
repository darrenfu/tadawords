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

    func testConflictProtectionSurvivesDiagnosticEvictionAndCompatibilityReplay()
        throws
    {
        let fixture = try CloudInboxHarnessFixture()
        defer { fixture.remove() }
        let store = try fixture.configuredStore()
        let record = fixture.record(
            name: "evicted-conflict",
            payload: "must-remain-blocked"
        )
        let recordID = fixture.recordID(name: record.recordName)
        let receiptID = try store.appendInbox(
            record: record,
            recordID: recordID,
            scope: .privateDatabase,
            receivedAt: fixture.now
        )
        try store.quarantine(
            CloudKitFamilyQuarantineEntry(
                id: UUID(),
                scope: .privateDatabase,
                recordName: recordID.recordName,
                zoneName: recordID.zoneID.zoneName,
                ownerName: recordID.zoneID.ownerName,
                reason: .conflict,
                envelopeData: Data("immutable-conflict".utf8),
                quarantinedAt: fixture.now
            )
        )
        for index in 0..<200 {
            try store.quarantine(
                CloudKitFamilyQuarantineEntry(
                    id: UUID(),
                    scope: .privateDatabase,
                    recordName: "compatibility-\(index)",
                    zoneName: fixture.zoneID.zoneName,
                    ownerName: fixture.zoneID.ownerName,
                    reason: .compatibility,
                    envelopeData: nil,
                    quarantinedAt: fixture.now.addingTimeInterval(
                        Double(index + 1)
                    )
                )
            )
        }

        let restarted = CloudKitFamilyMetadataStore(
            snapshotURL: fixture.metadataURL
        )
        XCTAssertEqual(restarted.quarantinedCount(), 200)
        XCTAssertTrue(
            restarted.isConflictQuarantined(
                recordID: recordID,
                scope: .privateDatabase
            ),
            "Evicting diagnostic bytes must not erase a proven conflict disposition"
        )
        XCTAssertTrue(
            restarted.isQuarantined(
                recordID: recordID,
                scope: .privateDatabase
            )
        )

        try restarted.quarantineInbox(
            receiptIDs: [receiptID],
            category: .compatibility,
            at: fixture.now.addingTimeInterval(299)
        )
        let afterInboxQuarantine = CloudKitFamilyMetadataStore(
            snapshotURL: fixture.metadataURL
        )
        XCTAssertTrue(afterInboxQuarantine.inboxEntries().isEmpty)
        XCTAssertTrue(
            afterInboxQuarantine.isConflictQuarantined(
                recordID: recordID,
                scope: .privateDatabase
            ),
            "Quarantining an older receipt cannot downgrade a later conflict disposition"
        )

        try afterInboxQuarantine.quarantine(
            CloudKitFamilyQuarantineEntry(
                id: UUID(),
                scope: .privateDatabase,
                recordName: recordID.recordName,
                zoneName: recordID.zoneID.zoneName,
                ownerName: recordID.zoneID.ownerName,
                reason: .compatibility,
                envelopeData: Data("later-compatibility-envelope".utf8),
                quarantinedAt: fixture.now.addingTimeInterval(300)
            )
        )

        let replayed = CloudKitFamilyMetadataStore(
            snapshotURL: fixture.metadataURL
        )
        XCTAssertTrue(
            replayed.isConflictQuarantined(
                recordID: recordID,
                scope: .privateDatabase
            ),
            "A later compatibility callback cannot downgrade the durable conflict lock"
        )
        XCTAssertThrowsError(
            try replayed.appendInboxReplacingQuarantine(
                record: record,
                recordID: recordID,
                scope: .privateDatabase,
                receivedAt: fixture.now.addingTimeInterval(301)
            )
        ) { error in
            XCTAssertEqual(
                error as? CloudKitFamilyPersistenceError,
                .conflictProtectedRecord
            )
        }
    }

    func testReceiptQuarantineCannotDowngradeVisibleConflictDisposition() throws {
        let fixture = try CloudInboxHarnessFixture()
        defer { fixture.remove() }
        let store = try fixture.configuredStore()
        let record = fixture.record(
            name: "visible-conflict",
            payload: "older-inbox-envelope"
        )
        let recordID = fixture.recordID(name: record.recordName)
        let receiptID = try store.appendInbox(
            record: record,
            recordID: recordID,
            scope: .privateDatabase,
            receivedAt: fixture.now
        )
        try store.quarantine(
            CloudKitFamilyQuarantineEntry(
                id: UUID(),
                scope: .privateDatabase,
                recordName: recordID.recordName,
                zoneName: recordID.zoneID.zoneName,
                ownerName: recordID.zoneID.ownerName,
                reason: .conflict,
                envelopeData: Data("newer-conflicting-envelope".utf8),
                quarantinedAt: fixture.now.addingTimeInterval(1)
            )
        )

        try store.quarantineInbox(
            receiptIDs: [receiptID],
            category: .compatibility,
            at: fixture.now.addingTimeInterval(2)
        )

        let restarted = CloudKitFamilyMetadataStore(
            snapshotURL: fixture.metadataURL
        )
        XCTAssertTrue(restarted.inboxEntries().isEmpty)
        XCTAssertTrue(
            restarted.isConflictQuarantined(
                recordID: recordID,
                scope: .privateDatabase
            )
        )
        XCTAssertThrowsError(
            try restarted.appendInboxReplacingQuarantine(
                record: record,
                recordID: recordID,
                scope: .privateDatabase,
                receivedAt: fixture.now.addingTimeInterval(3)
            )
        ) { error in
            XCTAssertEqual(
                error as? CloudKitFamilyPersistenceError,
                .conflictProtectedRecord
            )
        }
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

    func testAppendInboxCannotClearDurableConflictProtection() throws {
        let fixture = try CloudInboxHarnessFixture()
        defer { fixture.remove() }
        let store = try fixture.configuredStore()
        let record = fixture.record(
            name: "conflict-protected-record",
            payload: "must-stay-blocked"
        )
        let recordID = fixture.recordID(name: record.recordName)
        try store.quarantine(
            CloudKitFamilyQuarantineEntry(
                id: UUID(),
                scope: .privateDatabase,
                recordName: recordID.recordName,
                zoneName: recordID.zoneID.zoneName,
                ownerName: recordID.zoneID.ownerName,
                reason: .conflict,
                envelopeData: Data("conflicting-envelope".utf8),
                quarantinedAt: fixture.now
            )
        )
        let quarantineCount = store.quarantinedCount()

        XCTAssertThrowsError(
            try store.appendInboxReplacingQuarantine(
                record: record,
                recordID: recordID,
                scope: .privateDatabase,
                receivedAt: fixture.now.addingTimeInterval(1)
            )
        ) { error in
            XCTAssertEqual(
                error as? CloudKitFamilyPersistenceError,
                .conflictProtectedRecord
            )
        }

        let restarted = CloudKitFamilyMetadataStore(
            snapshotURL: fixture.metadataURL
        )
        XCTAssertTrue(restarted.inboxEntries().isEmpty)
        XCTAssertEqual(restarted.quarantinedCount(), quarantineCount)
        XCTAssertTrue(
            restarted.isConflictQuarantined(
                recordID: recordID,
                scope: .privateDatabase
            )
        )
        XCTAssertTrue(
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

    func testAtomicConflictWriteFailureRetriesFailClosedInSameProcess()
        async throws
    {
        for kind in StagedConflictKind.allCases {
            try await assertAtomicConflictWriteFailureRetriesInSameProcess(
                kind: kind
            )
        }
    }

    func testAtomicConflictWriteFailureReplaysFailClosedFromOldCursorAfterRelaunch()
        async throws
    {
        for kind in StagedConflictKind.allCases {
            try await assertAtomicConflictWriteFailureReplaysAfterRelaunch(
                kind: kind
            )
        }
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
            kind: .wordPoolEntry,
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
        try store.confirm(accountRecordName: "account-a")
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

    func testItemBeforeRootAcrossCallbacksDefersThenPersistsPrivateCursor()
        async throws
    {
        let fixture = try CloudInboxHarnessFixture()
        defer { fixture.remove() }
        let store = try fixture.unboundStore()
        let record = fixture.record(payload: "cross-callback-private")
        let item = try fixture.cloudRecord(for: record, store: store)
        let root = fixture.rootCloudRecord()
        let stateStore = fixture.stateStore()
        let advanced = try fixture.serialization("private-after-item")
        let buffer = CloudKitFamilySyncEventBuffer(metadataStore: store)

        await buffer.handle(
            .fetchedRecords([item]),
            scope: .privateDatabase,
            generation: 1,
            now: fixture.now
        )
        await buffer.persistEngineState(
            advanced,
            scope: .privateDatabase,
            generation: 1,
            stateStore: stateStore
        )

        XCTAssertNil(stateStore.load(.privateDatabase))
        let canPersistBeforeRoot = await buffer.canPersistEngineState(1)
        XCTAssertFalse(canPersistBeforeRoot)
        XCTAssertTrue(store.inboxEntries().isEmpty)
        let beforeRoot = await buffer.drain()
        XCTAssertTrue(beforeRoot.records.isEmpty)
        XCTAssertEqual(beforeRoot.quarantinedRecordCount, 0)

        await buffer.handle(
            .fetchedRecords([root]),
            scope: .privateDatabase,
            generation: 1,
            now: fixture.now.addingTimeInterval(1)
        )
        await buffer.handle(
            .finishedFetchingZone(fixture.zoneID, succeeded: true),
            scope: .privateDatabase,
            generation: 1,
            now: fixture.now.addingTimeInterval(2)
        )
        let result = await buffer.drain()

        XCTAssertEqual(result.records, [record])
        XCTAssertEqual(store.inboxEntries().map(\.record), [record])
        XCTAssertEqual(store.binding(for: fixture.profileID).state, .privateOwner)
        XCTAssertEqual(
            try fixture.encoded(stateStore.load(.privateDatabase)),
            try fixture.encoded(advanced)
        )
    }

    func testProcessRestartReplaysItemBecausePreRootCursorWasNotPersisted()
        async throws
    {
        let fixture = try CloudInboxHarnessFixture()
        defer { fixture.remove() }
        let store = try fixture.unboundStore()
        let record = fixture.record(payload: "restart-replay")
        let item = try fixture.cloudRecord(for: record, store: store)
        let root = fixture.rootCloudRecord()
        let stateStore = fixture.stateStore()
        let unsafe = try fixture.serialization("must-not-survive-crash")

        let firstProcess = CloudKitFamilySyncEventBuffer(metadataStore: store)
        await firstProcess.handle(
            .fetchedRecords([item]),
            scope: .privateDatabase,
            generation: 1,
            now: fixture.now
        )
        await firstProcess.persistEngineState(
            unsafe,
            scope: .privateDatabase,
            generation: 1,
            stateStore: stateStore
        )
        XCTAssertNil(stateStore.load(.privateDatabase))

        // A new buffer represents a process relaunch from the still-old token.
        let restarted = CloudKitFamilySyncEventBuffer(metadataStore: store)
        await restarted.handle(
            .fetchedRecords([item]),
            scope: .privateDatabase,
            generation: 1,
            now: fixture.now.addingTimeInterval(1)
        )
        await restarted.handle(
            .fetchedRecords([root]),
            scope: .privateDatabase,
            generation: 1,
            now: fixture.now.addingTimeInterval(2)
        )
        let replayed = await restarted.drain()

        XCTAssertEqual(replayed.records, [record])
        XCTAssertEqual(store.inboxEntries().map(\.record), [record])
    }

    func testSharedAndPrivatePreRootStagingAndCursorsRemainScopeIsolated()
        async throws
    {
        let fixture = try CloudInboxHarnessFixture()
        defer { fixture.remove() }
        let store = try fixture.unboundStore()
        let privateRecord = fixture.record(payload: "private")
        let privateItem = try fixture.cloudRecord(for: privateRecord, store: store)
        let sharedProfileID = ProfileID()
        let shared = try fixture.discoveryRecords(
            profileID: sharedProfileID,
            payload: "shared",
            ownerName: "shared-owner",
            scope: .sharedDatabase,
            store: store
        )
        let stateStore = fixture.stateStore()
        let privateState = try fixture.serialization("private-deferred")
        let sharedState = try fixture.serialization("shared-deferred")
        let buffer = CloudKitFamilySyncEventBuffer(metadataStore: store)

        await buffer.handle(
            .fetchedRecords([privateItem]),
            scope: .privateDatabase,
            generation: 1,
            now: fixture.now
        )
        await buffer.handle(
            .fetchedRecords([shared.item]),
            scope: .sharedDatabase,
            generation: 1,
            now: fixture.now
        )
        await buffer.persistEngineState(
            privateState,
            scope: .privateDatabase,
            generation: 1,
            stateStore: stateStore
        )
        await buffer.persistEngineState(
            sharedState,
            scope: .sharedDatabase,
            generation: 1,
            stateStore: stateStore
        )

        await buffer.handle(
            .fetchedRecords([shared.root]),
            scope: .sharedDatabase,
            generation: 1,
            now: fixture.now.addingTimeInterval(1)
        )

        XCTAssertNil(stateStore.load(.privateDatabase))
        XCTAssertEqual(
            try fixture.encoded(stateStore.load(.sharedDatabase)),
            try fixture.encoded(sharedState)
        )
        XCTAssertEqual(store.binding(for: sharedProfileID).state, .sharedParticipant)
        XCTAssertEqual(store.binding(for: fixture.profileID).state, .unbound)

        await buffer.handle(
            .fetchedRecords([fixture.rootCloudRecord()]),
            scope: .privateDatabase,
            generation: 1,
            now: fixture.now.addingTimeInterval(2)
        )
        let result = await buffer.drain()

        XCTAssertEqual(Set(result.records), [privateRecord, shared.record])
        XCTAssertEqual(
            try fixture.encoded(stateStore.load(.privateDatabase)),
            try fixture.encoded(privateState)
        )
    }

    func testSuccessfulZoneBoundaryQuarantinesRootlessItemBeforeAdvancingCursor()
        async throws
    {
        let fixture = try CloudInboxHarnessFixture()
        defer { fixture.remove() }
        let store = try fixture.unboundStore()
        let record = fixture.record(payload: "root-never-arrives")
        let item = try fixture.cloudRecord(for: record, store: store)
        let stateStore = fixture.stateStore()
        let advanced = try fixture.serialization("rootless-quarantined")
        let buffer = CloudKitFamilySyncEventBuffer(metadataStore: store)

        await buffer.handle(
            .fetchedRecords([item]),
            scope: .privateDatabase,
            generation: 1,
            now: fixture.now
        )
        await buffer.persistEngineState(
            advanced,
            scope: .privateDatabase,
            generation: 1,
            stateStore: stateStore
        )
        XCTAssertNil(stateStore.load(.privateDatabase))

        await buffer.handle(
            .finishedFetchingZone(fixture.zoneID, succeeded: true),
            scope: .privateDatabase,
            generation: 1,
            now: fixture.now.addingTimeInterval(1)
        )
        let result = await buffer.drain()

        XCTAssertTrue(result.records.isEmpty)
        XCTAssertEqual(result.quarantinedRecordCount, 1)
        XCTAssertTrue(store.inboxEntries().isEmpty)
        XCTAssertEqual(store.binding(for: fixture.profileID).state, .unbound)
        XCTAssertTrue(
            store.isQuarantined(
                recordID: item.recordID,
                scope: .privateDatabase
            )
        )
        XCTAssertEqual(
            try fixture.encoded(stateStore.load(.privateDatabase)),
            try fixture.encoded(advanced)
        )
    }

    func testRootlessQuarantineWriteFailureRetriesBeforeAdvancingCursor()
        async throws
    {
        let fixture = try CloudInboxHarnessFixture()
        defer { fixture.remove() }
        let store = try fixture.unboundStore()
        let item = try fixture.cloudRecord(
            for: fixture.record(payload: "rootless-retry"),
            store: store
        )
        let stateStore = fixture.stateStore()
        let advanced = try fixture.serialization("rootless-retry")
        let writablePermissions = 0o755
        let readOnlyPermissions = 0o555
        defer {
            try? FileManager.default.setAttributes(
                [.posixPermissions: writablePermissions],
                ofItemAtPath: fixture.directory.path
            )
        }
        let buffer = CloudKitFamilySyncEventBuffer(metadataStore: store)

        await buffer.handle(
            .fetchedRecords([item]),
            scope: .privateDatabase,
            generation: 1,
            now: fixture.now
        )
        await buffer.persistEngineState(
            advanced,
            scope: .privateDatabase,
            generation: 1,
            stateStore: stateStore
        )
        try FileManager.default.setAttributes(
            [.posixPermissions: readOnlyPermissions],
            ofItemAtPath: fixture.directory.path
        )
        await buffer.handle(
            .finishedFetchingZone(fixture.zoneID, succeeded: true),
            scope: .privateDatabase,
            generation: 1,
            now: fixture.now.addingTimeInterval(1)
        )
        let failed = await buffer.drain()

        XCTAssertEqual(failed.failures.map(\.category), [.corruptState])
        XCTAssertNil(stateStore.load(.privateDatabase))
        XCTAssertFalse(
            store.isQuarantined(
                recordID: item.recordID,
                scope: .privateDatabase
            )
        )

        try FileManager.default.setAttributes(
            [.posixPermissions: writablePermissions],
            ofItemAtPath: fixture.directory.path
        )
        let recovered = await buffer.retryStagedUnboundRecords(generation: 1)
        let retry = await buffer.drain()

        XCTAssertTrue(recovered)
        XCTAssertTrue(retry.failures.isEmpty)
        XCTAssertEqual(retry.quarantinedRecordCount, 1)
        XCTAssertTrue(
            store.isQuarantined(
                recordID: item.recordID,
                scope: .privateDatabase
            )
        )
        XCTAssertEqual(
            try fixture.encoded(stateStore.load(.privateDatabase)),
            try fixture.encoded(advanced)
        )
    }

    func testFailedZoneBoundaryKeepsRootlessItemRetryableUntilRootArrives()
        async throws
    {
        let fixture = try CloudInboxHarnessFixture()
        defer { fixture.remove() }
        let store = try fixture.unboundStore()
        let record = fixture.record(payload: "retryable-root")
        let item = try fixture.cloudRecord(for: record, store: store)
        let stateStore = fixture.stateStore()
        let advanced = try fixture.serialization("retryable-deferred")
        let buffer = CloudKitFamilySyncEventBuffer(metadataStore: store)

        await buffer.handle(
            .fetchedRecords([item]),
            scope: .privateDatabase,
            generation: 1,
            now: fixture.now
        )
        await buffer.persistEngineState(
            advanced,
            scope: .privateDatabase,
            generation: 1,
            stateStore: stateStore
        )
        await buffer.handle(
            .finishedFetchingZone(fixture.zoneID, succeeded: false),
            scope: .privateDatabase,
            generation: 1,
            now: fixture.now.addingTimeInterval(1)
        )

        XCTAssertNil(stateStore.load(.privateDatabase))
        XCTAssertTrue(store.inboxEntries().isEmpty)

        await buffer.handle(
            .fetchedRecords([fixture.rootCloudRecord()]),
            scope: .privateDatabase,
            generation: 1,
            now: fixture.now.addingTimeInterval(2)
        )
        let result = await buffer.drain()

        XCTAssertEqual(result.records, [record])
        XCTAssertEqual(result.quarantinedRecordCount, 0)
        XCTAssertEqual(
            try fixture.encoded(stateStore.load(.privateDatabase)),
            try fixture.encoded(advanced)
        )
    }

    func testPartialPromotionWriteFailureRetriesRemainingInSameProcess()
        async throws
    {
        let fixture = try CloudInboxHarnessFixture()
        defer { fixture.remove() }
        let store = try fixture.unboundStore()
        let firstRecord = fixture.record(
            name: "first-same-process",
            payload: "first"
        )
        let secondRecord = fixture.record(
            name: "second-same-process",
            payload: "second"
        )
        let firstItem = try fixture.cloudRecord(for: firstRecord, store: store)
        let secondItem = try fixture.cloudRecord(for: secondRecord, store: store)
        let stateStore = fixture.stateStore()
        let advanced = try fixture.serialization("same-process-promotion")
        let writablePermissions = 0o755
        let readOnlyPermissions = 0o555
        defer {
            try? FileManager.default.setAttributes(
                [.posixPermissions: writablePermissions],
                ofItemAtPath: fixture.directory.path
            )
        }
        let buffer = CloudKitFamilySyncEventBuffer(
            metadataStore: store,
            beforePromotingStagedRecord: { index in
                guard index == 1 else { return }
                try? FileManager.default.setAttributes(
                    [.posixPermissions: readOnlyPermissions],
                    ofItemAtPath: fixture.directory.path
                )
            }
        )

        await buffer.handle(
            .fetchedRecords([firstItem, secondItem]),
            scope: .privateDatabase,
            generation: 1,
            now: fixture.now
        )
        await buffer.persistEngineState(
            advanced,
            scope: .privateDatabase,
            generation: 1,
            stateStore: stateStore
        )
        await buffer.handle(
            .fetchedRecords([fixture.rootCloudRecord()]),
            scope: .privateDatabase,
            generation: 1,
            now: fixture.now.addingTimeInterval(1)
        )
        await buffer.handle(
            .finishedFetchingZone(fixture.zoneID, succeeded: true),
            scope: .privateDatabase,
            generation: 1,
            now: fixture.now.addingTimeInterval(2)
        )
        let partial = await buffer.drain()

        XCTAssertEqual(partial.records, [firstRecord])
        XCTAssertEqual(partial.failures.map(\.category), [.corruptState])
        XCTAssertEqual(partial.quarantinedRecordCount, 0)
        XCTAssertNil(stateStore.load(.privateDatabase))
        XCTAssertEqual(store.inboxEntries().map(\.record), [firstRecord])

        try FileManager.default.setAttributes(
            [.posixPermissions: writablePermissions],
            ofItemAtPath: fixture.directory.path
        )
        let recovered = await buffer.retryStagedUnboundRecords(generation: 1)
        let retry = await buffer.drain()

        XCTAssertTrue(recovered)
        XCTAssertEqual(retry.records, [secondRecord])
        XCTAssertTrue(retry.failures.isEmpty)
        XCTAssertEqual(
            Set(store.inboxEntries().compactMap(\.record)),
            [firstRecord, secondRecord]
        )
        XCTAssertEqual(
            try fixture.encoded(stateStore.load(.privateDatabase)),
            try fixture.encoded(advanced)
        )
    }

    func testPartialPromotionWriteFailureReplaysIdempotentlyFromOldCursor()
        async throws
    {
        let fixture = try CloudInboxHarnessFixture()
        defer { fixture.remove() }
        let store = try fixture.unboundStore()
        let firstRecord = fixture.record(
            name: "first-after-root",
            payload: "first"
        )
        let secondRecord = fixture.record(
            name: "second-after-root",
            payload: "second"
        )
        let firstItem = try fixture.cloudRecord(for: firstRecord, store: store)
        let secondItem = try fixture.cloudRecord(for: secondRecord, store: store)
        let stateStore = fixture.stateStore()
        let unsafe = try fixture.serialization("partial-promotion")
        let writablePermissions = 0o755
        let readOnlyPermissions = 0o555
        defer {
            try? FileManager.default.setAttributes(
                [.posixPermissions: writablePermissions],
                ofItemAtPath: fixture.directory.path
            )
        }
        let buffer = CloudKitFamilySyncEventBuffer(
            metadataStore: store,
            beforePromotingStagedRecord: { index in
                guard index == 1 else { return }
                try? FileManager.default.setAttributes(
                    [.posixPermissions: readOnlyPermissions],
                    ofItemAtPath: fixture.directory.path
                )
            }
        )

        await buffer.handle(
            .fetchedRecords([firstItem, secondItem]),
            scope: .privateDatabase,
            generation: 1,
            now: fixture.now
        )
        await buffer.persistEngineState(
            unsafe,
            scope: .privateDatabase,
            generation: 1,
            stateStore: stateStore
        )
        await buffer.handle(
            .fetchedRecords([fixture.rootCloudRecord()]),
            scope: .privateDatabase,
            generation: 1,
            now: fixture.now.addingTimeInterval(1)
        )
        await buffer.handle(
            .finishedFetchingZone(fixture.zoneID, succeeded: true),
            scope: .privateDatabase,
            generation: 1,
            now: fixture.now.addingTimeInterval(2)
        )
        let partial = await buffer.drain()

        try FileManager.default.setAttributes(
            [.posixPermissions: writablePermissions],
            ofItemAtPath: fixture.directory.path
        )
        XCTAssertEqual(partial.records, [firstRecord])
        XCTAssertEqual(partial.failures.map(\.category), [.corruptState])
        XCTAssertEqual(partial.quarantinedRecordCount, 0)
        XCTAssertNil(stateStore.load(.privateDatabase))
        XCTAssertEqual(store.inboxEntries().map(\.record), [firstRecord])

        let restartedStore = CloudKitFamilyMetadataStore(
            snapshotURL: fixture.metadataURL
        )
        let restarted = CloudKitFamilySyncEventBuffer(
            metadataStore: restartedStore
        )
        await restarted.handle(
            .fetchedRecords([firstItem, secondItem]),
            scope: .privateDatabase,
            generation: 1,
            now: fixture.now.addingTimeInterval(2)
        )
        let replayed = await restarted.drain()

        XCTAssertEqual(Set(replayed.records), [firstRecord, secondRecord])
        XCTAssertEqual(
            Set(restartedStore.inboxEntries().compactMap(\.record)),
            [firstRecord, secondRecord]
        )
    }

    func testMalformedRouteCannotStageOrForgeBindingAndAccountBoundaryDropsStaging()
        async throws
    {
        let fixture = try CloudInboxHarnessFixture()
        defer { fixture.remove() }
        let store = try fixture.unboundStore()
        let record = fixture.record(payload: "hostile-route")
        let hostileItem = try fixture.cloudRecord(for: record, store: store)
        hostileItem.parent = CKRecord.Reference(
            recordID: CKRecord.ID(
                recordName: "not-the-deterministic-root",
                zoneID: fixture.zoneID
            ),
            action: .none
        )
        let hostileRoot = CKRecord(
            recordType: CloudKitFamilyRecordCodec.Schema.rootRecordType,
            recordID: CKRecord.ID(
                recordName: "not-the-deterministic-root",
                zoneID: fixture.zoneID
            )
        )
        hostileRoot[CloudKitFamilyRecordCodec.Schema.profileID] =
            fixture.profileID.rawValue.uuidString as NSString
        let buffer = CloudKitFamilySyncEventBuffer(metadataStore: store)

        await buffer.handle(
            .fetchedRecords([hostileItem, hostileRoot]),
            scope: .privateDatabase,
            generation: 1,
            now: fixture.now
        )
        let hostile = await buffer.drain()

        XCTAssertTrue(hostile.records.isEmpty)
        XCTAssertEqual(hostile.quarantinedRecordCount, 2)
        XCTAssertEqual(store.binding(for: fixture.profileID).state, .unbound)
        XCTAssertTrue(store.inboxEntries().isEmpty)

        let validItem = try fixture.cloudRecord(for: record, store: store)
        let stateStore = fixture.stateStore()
        let unsafe = try fixture.serialization("old-account-staged")
        await buffer.handle(
            .fetchedRecords([validItem]),
            scope: .privateDatabase,
            generation: 1,
            now: fixture.now.addingTimeInterval(1)
        )
        await buffer.persistEngineState(
            unsafe,
            scope: .privateDatabase,
            generation: 1,
            stateStore: stateStore
        )
        await buffer.handle(
            .accountChange(.switchedAccounts),
            scope: .privateDatabase,
            generation: 1,
            now: fixture.now.addingTimeInterval(2)
        )
        await buffer.handle(
            .fetchedRecords([fixture.rootCloudRecord()]),
            scope: .privateDatabase,
            generation: 1,
            now: fixture.now.addingTimeInterval(3)
        )
        let sealed = await buffer.drain()

        XCTAssertEqual(sealed.accountChange, .switchedAccounts)
        XCTAssertTrue(sealed.records.isEmpty)
        XCTAssertTrue(store.inboxEntries().isEmpty)
        XCTAssertNil(stateStore.load(.privateDatabase))
    }

    func testAccountSwitchDropsOldBytesButPreservesFailClosedBindingProvenance()
        async throws
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
                rootRecordName: "shared-family-root"
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
            kind: .wordPoolEntry,
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
        let retainedOwner = restarted.binding(for: fixture.profileID)
        let retainedParticipant = restarted.binding(for: sharedProfileID)
        XCTAssertEqual(retainedOwner.state, .privateOwner)
        XCTAssertEqual(retainedOwner.originAccountRecordName, "account-a")
        XCTAssertEqual(retainedOwner.erasureRoute, .owner)
        XCTAssertEqual(retainedParticipant.state, .sharedParticipant)
        XCTAssertEqual(retainedParticipant.originAccountRecordName, "account-a")
        XCTAssertEqual(retainedParticipant.erasureRoute, .participant)
        XCTAssertFalse(
            restarted.isBindingAuthorizedForConfirmedAccount(retainedOwner)
        )
        XCTAssertFalse(
            restarted.isBindingAuthorizedForConfirmedAccount(retainedParticipant)
        )

        // Confirmation invokes account invalidation again. It must preserve
        // the old route without authorizing it for the replacement account.
        try restarted.confirm(accountRecordName: "account-b")
        let confirmed = CloudKitFamilyMetadataStore(
            snapshotURL: fixture.metadataURL
        )
        XCTAssertEqual(confirmed.binding(for: fixture.profileID), retainedOwner)
        XCTAssertEqual(confirmed.binding(for: sharedProfileID), retainedParticipant)
        XCTAssertFalse(
            confirmed.isBindingAuthorizedForConfirmedAccount(retainedOwner)
        )

        let replacementAccountRoot = CKRecord(
            recordType: CloudKitFamilyRecordCodec.Schema.rootRecordType,
            recordID: fixture.rootRecordID
        )
        replacementAccountRoot[CloudKitFamilyRecordCodec.Schema.profileID] =
            fixture.profileID.rawValue.uuidString as NSString
        let buffer = CloudKitFamilySyncEventBuffer(metadataStore: confirmed)
        await buffer.handle(
            .fetchedRecords([replacementAccountRoot]),
            scope: .privateDatabase,
            generation: 1,
            now: fixture.now
        )
        let blocked = await buffer.drain()
        XCTAssertEqual(blocked.accountChange, .switchedAccounts)
        XCTAssertEqual(confirmed.binding(for: fixture.profileID), retainedOwner)

        // Returning to the origin account re-authorizes the exact retained
        // owner/participant route; no private fallback or route rewrite occurs.
        try confirmed.confirm(accountRecordName: "account-a")
        let returned = CloudKitFamilyMetadataStore(snapshotURL: fixture.metadataURL)
        XCTAssertTrue(
            returned.isBindingAuthorizedForConfirmedAccount(
                returned.binding(for: fixture.profileID)
            )
        )
        XCTAssertTrue(
            returned.isBindingAuthorizedForConfirmedAccount(
                returned.binding(for: sharedProfileID)
            )
        )
    }

    func testV1ActiveBindingsMigrateOriginAccountAndRouteBeforeUse() throws {
        let fixture = try CloudInboxHarnessFixture()
        defer { fixture.remove() }
        let participantID = ProfileID()
        let legacy = LegacyCloudMetadataSnapshot(
            schemaVersion: 1,
            confirmedAccountRecordName: "account-a",
            requiresAccountConfirmation: false,
            bindings: [
                ProfileCloudBinding(
                    profileID: fixture.profileID,
                    state: .privateOwner,
                    zoneName: fixture.zoneID.zoneName,
                    ownerName: fixture.zoneID.ownerName,
                    rootRecordName: fixture.rootRecordID.recordName
                ),
                ProfileCloudBinding(
                    profileID: participantID,
                    state: .sharedParticipant,
                    zoneName: "SharedLegacyZone",
                    ownerName: "legacy-owner",
                    rootRecordName: "legacy-root"
                ),
            ]
        )
        try JSONEncoder().encode(legacy).write(
            to: fixture.metadataURL,
            options: .atomic
        )
        let store = CloudKitFamilyMetadataStore(snapshotURL: fixture.metadataURL)

        XCTAssertEqual(
            try store.accountGate(currentAccountRecordName: "account-a"),
            .authorized
        )
        let owner = store.binding(for: fixture.profileID)
        let participant = store.binding(for: participantID)
        XCTAssertEqual(owner.originAccountRecordName, "account-a")
        XCTAssertEqual(owner.originErasureRoute, .owner)
        XCTAssertEqual(participant.originAccountRecordName, "account-a")
        XCTAssertEqual(participant.originErasureRoute, .participant)
        XCTAssertTrue(store.isBindingAuthorizedForConfirmedAccount(owner))
        XCTAssertTrue(store.isBindingAuthorizedForConfirmedAccount(participant))

        let persistedObject = try XCTUnwrap(
            try JSONSerialization.jsonObject(
                with: Data(contentsOf: fixture.metadataURL)
            ) as? [String: Any]
        )
        XCTAssertEqual(persistedObject["schemaVersion"] as? Int, 2)
        let restarted = CloudKitFamilyMetadataStore(snapshotURL: fixture.metadataURL)
        XCTAssertEqual(restarted.binding(for: fixture.profileID), owner)
        XCTAssertEqual(restarted.binding(for: participantID), participant)
    }

    func testV1PersistedUnboundCannotBeClaimedByReplacementAccountRoot()
        async throws
    {
        let fixture = try CloudInboxHarnessFixture()
        defer { fixture.remove() }
        let legacy = LegacyCloudMetadataSnapshot(
            schemaVersion: 1,
            confirmedAccountRecordName: "account-a",
            requiresAccountConfirmation: false,
            bindings: [.unbound(fixture.profileID)]
        )
        try JSONEncoder().encode(legacy).write(
            to: fixture.metadataURL,
            options: .atomic
        )
        let store = CloudKitFamilyMetadataStore(snapshotURL: fixture.metadataURL)
        XCTAssertEqual(
            try store.accountGate(currentAccountRecordName: "account-b"),
            .requiresConfirmation(.switchedAccounts)
        )
        try store.confirm(accountRecordName: "account-b")

        let replacementAccountRoot = CKRecord(
            recordType: CloudKitFamilyRecordCodec.Schema.rootRecordType,
            recordID: fixture.rootRecordID
        )
        replacementAccountRoot[CloudKitFamilyRecordCodec.Schema.profileID] =
            fixture.profileID.rawValue.uuidString as NSString
        let buffer = CloudKitFamilySyncEventBuffer(metadataStore: store)
        await buffer.handle(
            .fetchedRecords([replacementAccountRoot]),
            scope: .privateDatabase,
            generation: 1,
            now: fixture.now
        )
        let blocked = await buffer.drain()
        let retained = store.binding(for: fixture.profileID)

        XCTAssertEqual(blocked.accountChange, .switchedAccounts)
        XCTAssertEqual(retained.state, .unbound)
        XCTAssertNil(retained.originAccountRecordName)
        XCTAssertEqual(retained.erasureRoute, .unresolved)
    }

    func testPersistedActiveBindingWithoutProvenanceIsCorruptAndPreserved()
        throws
    {
        let fixture = try CloudInboxHarnessFixture()
        defer { fixture.remove() }
        let ambiguous = LegacyCloudMetadataSnapshot(
            schemaVersion: 2,
            confirmedAccountRecordName: "account-a",
            requiresAccountConfirmation: false,
            bindings: [
                ProfileCloudBinding(
                    profileID: fixture.profileID,
                    state: .privateOwner,
                    zoneName: fixture.zoneID.zoneName,
                    ownerName: fixture.zoneID.ownerName,
                    rootRecordName: fixture.rootRecordID.recordName
                )
            ]
        )
        let ambiguousBytes = try JSONEncoder().encode(ambiguous)
        try ambiguousBytes.write(
            to: fixture.metadataURL,
            options: .atomic
        )
        let store = CloudKitFamilyMetadataStore(snapshotURL: fixture.metadataURL)
        XCTAssertThrowsError(
            try store.accountGate(currentAccountRecordName: "account-b")
        ) { error in
            XCTAssertEqual(
                error as? CloudKitFamilyPersistenceError,
                .corruptMetadata
            )
        }
        XCTAssertThrowsError(
            try store.confirm(accountRecordName: "account-b")
        ) { error in
            XCTAssertEqual(
                error as? CloudKitFamilyPersistenceError,
                .corruptMetadata
            )
        }
        XCTAssertEqual(
            try Data(contentsOf: fixture.metadataURL),
            ambiguousBytes
        )
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
        let store = try fixture.configuredStore(
            accountRecordName: "old-account"
        )
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
        let store = CloudKitFamilyMetadataStore(
            snapshotURL: fixture.metadataURL
        )

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

    func testRealAccountChangeSealsBufferedPayloadBeforeFetchCanExposeIt()
        async throws
    {
        let fixture = try CloudInboxHarnessFixture()
        defer { fixture.remove() }
        let store = try fixture.configuredStore(accountRecordName: "account-a")
        let incomingRecord = fixture.record(
            name: "incoming-before-boundary",
            payload: "account-a-incoming"
        )
        let incomingCloud = try fixture.cloudRecord(
            for: incomingRecord,
            store: store
        )
        let outgoingRecord = fixture.record(
            name: "outgoing-before-boundary",
            payload: "account-a-outgoing"
        )
        let outgoingCloud = try fixture.cloudRecord(
            for: outgoingRecord,
            store: store
        )
        let outgoingAcknowledgement = FamilySyncChangeAcknowledgement(
            operation: .save(outgoingRecord)
        )
        let buffer = CloudKitFamilySyncEventBuffer(metadataStore: store)

        await buffer.handle(
            .fetchedRecords([incomingCloud]),
            scope: .privateDatabase,
            generation: 1,
            now: fixture.now
        )
        await buffer.handle(
            .fetchedDeletions([
                fixture.recordID(name: "deleted-before-boundary")
            ]),
            scope: .privateDatabase,
            generation: 1,
            now: fixture.now.addingTimeInterval(1)
        )
        await buffer.register(
            CloudKitFamilyOutgoingChange(
                acknowledgement: outgoingAcknowledgement,
                record: outgoingCloud
            ),
            recordID: outgoingCloud.recordID,
            scope: .privateDatabase,
            generation: 1
        )
        await buffer.handle(
            .sentRecords(saved: [outgoingCloud], failed: []),
            scope: .privateDatabase,
            generation: 1,
            now: fixture.now.addingTimeInterval(2)
        )

        await buffer.handle(
            .accountChange(.switchedAccounts),
            scope: .privateDatabase,
            generation: 1,
            now: fixture.now.addingTimeInterval(3)
        )
        let result = await buffer.drain()

        XCTAssertEqual(result.accountChange, .switchedAccounts)
        XCTAssertTrue(result.records.isEmpty)
        XCTAssertTrue(result.deletions.isEmpty)
        XCTAssertTrue(result.acknowledged.isEmpty)
        XCTAssertTrue(result.receiptIDs.isEmpty)
        XCTAssertTrue(result.receipts.isEmpty)
        XCTAssertFalse(result.requiresFetchPass)
        XCTAssertTrue(store.inboxEntries().isEmpty)
    }

    func testSameAccountSignedInKeepsDurablyBufferedFetchAvailable()
        async throws
    {
        let fixture = try CloudInboxHarnessFixture()
        defer { fixture.remove() }
        let store = try fixture.configuredStore(accountRecordName: "account-a")
        let record = fixture.record(
            name: "same-account-buffered",
            payload: "durable-account-a-payload"
        )
        let cloudRecord = try fixture.cloudRecord(for: record, store: store)
        let buffer = CloudKitFamilySyncEventBuffer(metadataStore: store)

        await buffer.handle(
            .fetchedRecords([cloudRecord]),
            scope: .privateDatabase,
            generation: 1,
            now: fixture.now
        )
        let durableEntries = store.inboxEntries()
        XCTAssertEqual(durableEntries.count, 1)
        let durableEntry = try XCTUnwrap(durableEntries.first)

        await buffer.handle(
            .accountChange(.signedIn(recordName: "account-a")),
            scope: .privateDatabase,
            generation: 1,
            now: fixture.now.addingTimeInterval(1)
        )
        let result = await buffer.drain()

        XCTAssertNil(result.accountChange)
        XCTAssertEqual(result.records, [record])
        XCTAssertEqual(result.receiptIDs, [durableEntry.receiptID])
        XCTAssertEqual(result.receipts.map(\.id), [durableEntry.receiptID])
        XCTAssertTrue(result.deletions.isEmpty)
        XCTAssertTrue(result.acknowledged.isEmpty)
        XCTAssertFalse(result.requiresFetchPass)
        XCTAssertEqual(store.inboxEntries(), [durableEntry])
    }

    func testReplayCannotReinsertCapturedOldAccountInboxAfterBoundaryLatch()
        async throws
    {
        let fixture = try CloudInboxHarnessFixture()
        defer { fixture.remove() }
        let store = try fixture.configuredStore(accountRecordName: "account-a")
        let oldRecord = fixture.record(payload: "captured-account-a-payload")
        _ = try store.appendInbox(
            record: oldRecord,
            recordID: fixture.recordID(name: oldRecord.recordName),
            scope: .privateDatabase,
            receivedAt: fixture.now
        )
        let capturedBeforeBoundary = store.inboxEntries()
        XCTAssertEqual(capturedBeforeBoundary.count, 1)
        let buffer = CloudKitFamilySyncEventBuffer(metadataStore: store)

        await buffer.handle(
            .accountChange(.switchedAccounts),
            scope: .privateDatabase,
            generation: 1,
            now: fixture.now.addingTimeInterval(1)
        )
        await buffer.replay(capturedBeforeBoundary, generation: 1)
        let result = await buffer.drain()

        XCTAssertEqual(result.accountChange, .switchedAccounts)
        XCTAssertTrue(result.records.isEmpty)
        XCTAssertTrue(result.deletions.isEmpty)
        XCTAssertTrue(result.receiptIDs.isEmpty)
        XCTAssertTrue(result.receipts.isEmpty)
        XCTAssertTrue(store.inboxEntries().isEmpty)
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

    private enum StagedConflictKind: CaseIterable {
        case sameRevision
        case immutable
    }

    private func assertAtomicConflictWriteFailureRetriesInSameProcess(
        kind: StagedConflictKind,
        file: StaticString = #filePath,
        line: UInt = #line
    ) async throws {
        let fixture = try CloudInboxHarnessFixture()
        defer { fixture.remove() }
        let store = try fixture.unboundStore()
        let variants = stagedConflictVariants(kind: kind, fixture: fixture)
        let firstCloud = try fixture.cloudRecord(for: variants.first, store: store)
        let secondCloud = try fixture.cloudRecord(for: variants.second, store: store)
        let stateStore = fixture.stateStore()
        let advanced = try fixture.serialization("conflict-same-process-\(kind)")
        let writablePermissions = 0o755
        let readOnlyPermissions = 0o555
        defer {
            try? FileManager.default.setAttributes(
                [.posixPermissions: writablePermissions],
                ofItemAtPath: fixture.directory.path
            )
        }
        let buffer = CloudKitFamilySyncEventBuffer(
            metadataStore: store,
            beforePromotingStagedRecord: { index in
                guard index == 1 else { return }
                try? FileManager.default.setAttributes(
                    [.posixPermissions: readOnlyPermissions],
                    ofItemAtPath: fixture.directory.path
                )
            }
        )

        await buffer.handle(
            .fetchedRecords([firstCloud, secondCloud]),
            scope: .privateDatabase,
            generation: 1,
            now: fixture.now
        )
        await buffer.persistEngineState(
            advanced,
            scope: .privateDatabase,
            generation: 1,
            stateStore: stateStore
        )
        await buffer.handle(
            .fetchedRecords([fixture.rootCloudRecord()]),
            scope: .privateDatabase,
            generation: 1,
            now: fixture.now.addingTimeInterval(1)
        )
        let failed = await buffer.drain()

        XCTAssertTrue(failed.records.isEmpty, file: file, line: line)
        XCTAssertTrue(failed.receiptIDs.isEmpty, file: file, line: line)
        XCTAssertTrue(failed.receipts.isEmpty, file: file, line: line)
        XCTAssertEqual(
            failed.failures.map(\.category),
            [.corruptState],
            file: file,
            line: line
        )
        XCTAssertNil(stateStore.load(.privateDatabase), file: file, line: line)
        XCTAssertEqual(store.inboxEntries().map(\.record), [variants.first])
        XCTAssertFalse(
            store.isConflictQuarantined(
                recordID: firstCloud.recordID,
                scope: .privateDatabase
            ),
            file: file,
            line: line
        )

        try FileManager.default.setAttributes(
            [.posixPermissions: writablePermissions],
            ofItemAtPath: fixture.directory.path
        )
        let recovered = await buffer.retryStagedUnboundRecords(generation: 1)
        let retried = await buffer.drain()

        XCTAssertTrue(recovered, file: file, line: line)
        assertConflictRemainsFailClosed(
            result: retried,
            store: store,
            recordID: firstCloud.recordID,
            file: file,
            line: line
        )
        XCTAssertEqual(
            try fixture.encoded(stateStore.load(.privateDatabase)),
            try fixture.encoded(advanced),
            "The deferred cursor may advance only after the atomic conflict write succeeds",
            file: file,
            line: line
        )

        XCTAssertThrowsError(
            try store.appendInboxReplacingQuarantine(
                record: variants.second,
                recordID: secondCloud.recordID,
                scope: .privateDatabase,
                receivedAt: fixture.now.addingTimeInterval(2)
            )
        ) { error in
            XCTAssertEqual(
                error as? CloudKitFamilyPersistenceError,
                .conflictProtectedRecord,
                file: file,
                line: line
            )
        }
        XCTAssertTrue(store.inboxEntries().isEmpty, file: file, line: line)
        XCTAssertTrue(
            store.isConflictQuarantined(
                recordID: secondCloud.recordID,
                scope: .privateDatabase
            ),
            file: file,
            line: line
        )
    }

    private func assertAtomicConflictWriteFailureReplaysAfterRelaunch(
        kind: StagedConflictKind,
        file: StaticString = #filePath,
        line: UInt = #line
    ) async throws {
        let fixture = try CloudInboxHarnessFixture()
        defer { fixture.remove() }
        let store = try fixture.unboundStore()
        let variants = stagedConflictVariants(kind: kind, fixture: fixture)
        let firstCloud = try fixture.cloudRecord(for: variants.first, store: store)
        let secondCloud = try fixture.cloudRecord(for: variants.second, store: store)
        let stateStore = fixture.stateStore()
        let advanced = try fixture.serialization("conflict-relaunch-\(kind)")
        let writablePermissions = 0o755
        let readOnlyPermissions = 0o555
        defer {
            try? FileManager.default.setAttributes(
                [.posixPermissions: writablePermissions],
                ofItemAtPath: fixture.directory.path
            )
        }
        let firstProcess = CloudKitFamilySyncEventBuffer(
            metadataStore: store,
            beforePromotingStagedRecord: { index in
                guard index == 1 else { return }
                try? FileManager.default.setAttributes(
                    [.posixPermissions: readOnlyPermissions],
                    ofItemAtPath: fixture.directory.path
                )
            }
        )

        await firstProcess.handle(
            .fetchedRecords([firstCloud, secondCloud]),
            scope: .privateDatabase,
            generation: 1,
            now: fixture.now
        )
        await firstProcess.persistEngineState(
            advanced,
            scope: .privateDatabase,
            generation: 1,
            stateStore: stateStore
        )
        await firstProcess.handle(
            .fetchedRecords([fixture.rootCloudRecord()]),
            scope: .privateDatabase,
            generation: 1,
            now: fixture.now.addingTimeInterval(1)
        )
        let failed = await firstProcess.drain()

        XCTAssertTrue(failed.records.isEmpty, file: file, line: line)
        XCTAssertTrue(failed.receiptIDs.isEmpty, file: file, line: line)
        XCTAssertEqual(
            failed.failures.map(\.category),
            [.corruptState],
            file: file,
            line: line
        )
        XCTAssertNil(stateStore.load(.privateDatabase), file: file, line: line)

        try FileManager.default.setAttributes(
            [.posixPermissions: writablePermissions],
            ofItemAtPath: fixture.directory.path
        )
        let restartedStore = CloudKitFamilyMetadataStore(
            snapshotURL: fixture.metadataURL
        )
        let restarted = CloudKitFamilySyncEventBuffer(
            metadataStore: restartedStore
        )
        await restarted.replay(
            restartedStore.replayableInboxEntries(),
            generation: 1
        )
        await restarted.handle(
            .fetchedRecords([firstCloud, secondCloud]),
            scope: .privateDatabase,
            generation: 1,
            now: fixture.now.addingTimeInterval(2)
        )
        await restarted.persistEngineState(
            advanced,
            scope: .privateDatabase,
            generation: 1,
            stateStore: stateStore
        )
        let replayed = await restarted.drain()

        assertConflictRemainsFailClosed(
            result: replayed,
            store: restartedStore,
            recordID: firstCloud.recordID,
            file: file,
            line: line
        )
        XCTAssertEqual(
            try fixture.encoded(stateStore.load(.privateDatabase)),
            try fixture.encoded(advanced),
            "Relaunch must replay from the old cursor before persisting its replacement",
            file: file,
            line: line
        )
    }

    private func stagedConflictVariants(
        kind: StagedConflictKind,
        fixture: CloudInboxHarnessFixture
    ) -> (first: FamilySyncRecord, second: FamilySyncRecord) {
        let recordName = "staged-conflict-\(kind)"
        switch kind {
        case .sameRevision:
            let revision = FamilySyncLogicalRevision(
                counter: 7,
                deviceID: "same-revision-device"
            )
            return (
                fixture.record(
                    name: recordName,
                    payload: "first-revision-payload",
                    revision: revision
                ),
                fixture.record(
                    name: recordName,
                    payload: "second-revision-payload",
                    revision: revision
                )
            )
        case .immutable:
            return (
                FamilySyncRecord(
                    recordName: recordName,
                    profileID: fixture.profileID,
                    kind: .attempt,
                    payload: Data("first-immutable-payload".utf8),
                    updatedAt: fixture.now,
                    deviceID: "immutable-device-a",
                    logicalRevision: FamilySyncLogicalRevision(
                        counter: 1,
                        deviceID: "immutable-device-a"
                    )
                ),
                FamilySyncRecord(
                    recordName: recordName,
                    profileID: fixture.profileID,
                    kind: .attempt,
                    payload: Data("second-immutable-payload".utf8),
                    updatedAt: fixture.now.addingTimeInterval(1),
                    deviceID: "immutable-device-b",
                    logicalRevision: FamilySyncLogicalRevision(
                        counter: 2,
                        deviceID: "immutable-device-b"
                    )
                )
            )
        }
    }

    private func assertConflictRemainsFailClosed(
        result: FamilySyncTransportResult,
        store: CloudKitFamilyMetadataStore,
        recordID: CKRecord.ID,
        file: StaticString,
        line: UInt
    ) {
        XCTAssertTrue(result.records.isEmpty, file: file, line: line)
        XCTAssertTrue(result.deletions.isEmpty, file: file, line: line)
        XCTAssertTrue(result.receiptIDs.isEmpty, file: file, line: line)
        XCTAssertTrue(result.receipts.isEmpty, file: file, line: line)
        XCTAssertTrue(result.acknowledged.isEmpty, file: file, line: line)
        XCTAssertTrue(result.failures.isEmpty, file: file, line: line)
        XCTAssertTrue(store.inboxEntries().isEmpty, file: file, line: line)
        XCTAssertEqual(store.quarantinedCount(), 1, file: file, line: line)
        XCTAssertTrue(
            store.isConflictQuarantined(
                recordID: recordID,
                scope: .privateDatabase
            ),
            file: file,
            line: line
        )
        XCTAssertTrue(
            store.isQuarantined(
                recordID: recordID,
                scope: .privateDatabase
            ),
            file: file,
            line: line
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
            kind: .wordPoolEntry,
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

    func testReplacementAccountChildDeletionCannotUseOriginAccountBinding()
        async throws
    {
        let fixture = try CloudInboxHarnessFixture()
        defer { fixture.remove() }
        let store = try fixture.configuredStore()
        let retainedBinding = store.binding(for: fixture.profileID)
        try store.confirm(accountRecordName: "account-b")
        let bytesBeforeCallback = try Data(contentsOf: fixture.metadataURL)
        let buffer = CloudKitFamilySyncEventBuffer(metadataStore: store)

        await buffer.handle(
            .fetchedDeletions([fixture.recordID(name: "stale-child")]),
            scope: .privateDatabase,
            generation: 1,
            now: fixture.now
        )
        let blocked = await buffer.drain()

        XCTAssertEqual(blocked.accountChange, .switchedAccounts)
        XCTAssertTrue(blocked.records.isEmpty)
        XCTAssertTrue(blocked.deletions.isEmpty)
        XCTAssertTrue(blocked.receiptIDs.isEmpty)
        XCTAssertTrue(store.inboxEntries().isEmpty)
        XCTAssertEqual(store.binding(for: fixture.profileID), retainedBinding)
        XCTAssertEqual(
            try Data(contentsOf: fixture.metadataURL),
            bytesBeforeCallback,
            "A replacement-account callback must not mutate origin-account metadata."
        )
    }

    func testTerminalOwnerIgnoresLateChildDeletionWithoutReemittingReceipt()
        async throws
    {
        let fixture = try CloudInboxHarnessFixture()
        defer { fixture.remove() }
        let store = try fixture.configuredStore()
        let owner = store.binding(for: fixture.profileID)
        try store.markOwnerDeleted(
            profileID: fixture.profileID,
            previous: owner
        )
        let bytesBeforeCallback = try Data(contentsOf: fixture.metadataURL)
        let buffer = CloudKitFamilySyncEventBuffer(metadataStore: store)

        await buffer.handle(
            .fetchedDeletions([fixture.recordID(name: "late-child")]),
            scope: .privateDatabase,
            generation: 1,
            now: fixture.now
        )
        let ignored = await buffer.drain()

        XCTAssertNil(ignored.accountChange)
        XCTAssertTrue(ignored.records.isEmpty)
        XCTAssertTrue(ignored.deletions.isEmpty)
        XCTAssertTrue(ignored.receiptIDs.isEmpty)
        XCTAssertTrue(ignored.receipts.isEmpty)
        XCTAssertTrue(ignored.failures.isEmpty)
        XCTAssertEqual(ignored.quarantinedRecordCount, 0)
        XCTAssertTrue(store.inboxEntries().isEmpty)
        XCTAssertEqual(
            try Data(contentsOf: fixture.metadataURL),
            bytesBeforeCallback
        )
    }

    func testTerminalParticipantAbsorbsQueuedChildDeletionWithoutQuarantine()
        async throws
    {
        let fixture = try CloudInboxHarnessFixture()
        defer { fixture.remove() }
        let store = CloudKitFamilyMetadataStore(snapshotURL: fixture.metadataURL)
        try store.confirm(accountRecordName: "account-a")
        let sharedZoneID = CKRecordZone.ID(
            zoneName: "SharedTerminalParticipantZone",
            ownerName: "share-owner"
        )
        let sharedRootID = CKRecord.ID(
            recordName: "shared-profile-root",
            zoneID: sharedZoneID
        )
        try store.save(
            binding: ProfileCloudBinding(
                profileID: fixture.profileID,
                state: .sharedParticipant,
                zoneName: sharedZoneID.zoneName,
                ownerName: sharedZoneID.ownerName,
                rootRecordName: sharedRootID.recordName
            )
        )
        let participant = store.binding(for: fixture.profileID)
        try store.markParticipantLeft(
            profileID: fixture.profileID,
            previous: participant
        )
        let bytesBeforeCallback = try Data(contentsOf: fixture.metadataURL)
        let buffer = CloudKitFamilySyncEventBuffer(metadataStore: store)

        await buffer.handle(
            .fetchedDeletions([
                CKRecord.ID(
                    recordName: "late-shared-child",
                    zoneID: sharedZoneID
                )
            ]),
            scope: .sharedDatabase,
            generation: 1,
            now: fixture.now
        )
        let ignored = await buffer.drain()

        XCTAssertNil(ignored.accountChange)
        XCTAssertTrue(ignored.records.isEmpty)
        XCTAssertTrue(ignored.deletions.isEmpty)
        XCTAssertTrue(ignored.receiptIDs.isEmpty)
        XCTAssertTrue(ignored.receipts.isEmpty)
        XCTAssertTrue(ignored.failures.isEmpty)
        XCTAssertEqual(ignored.quarantinedRecordCount, 0)
        XCTAssertTrue(store.inboxEntries().isEmpty)
        XCTAssertEqual(
            try Data(contentsOf: fixture.metadataURL),
            bytesBeforeCallback
        )
    }
}

private struct LegacyCloudMetadataSnapshot: Encodable {
    let schemaVersion: Int
    let confirmedAccountRecordName: String?
    let requiresAccountConfirmation: Bool
    let bindings: [ProfileCloudBinding]
    let systemFields: [Int] = []
    let quarantined: [Int] = []
    let protectedRecordKeys: [Int] = []
    let inbox: [Int] = []
}

private struct CloudInboxHarnessFixture {
    struct DiscoveryRecords {
        let record: FamilySyncRecord
        let item: CKRecord
        let root: CKRecord
    }

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
            zoneName: CloudKitDeterministicProfileRoute.zoneName(
                for: profileID
            ),
            ownerName: CKCurrentUserDefaultName
        )
        rootRecordID = CKRecord.ID(
            recordName: CloudKitDeterministicProfileRoute.rootRecordName(
                for: profileID
            ),
            zoneID: zoneID
        )
    }

    func configuredStore(
        accountRecordName: String? = "account-a"
    ) throws -> CloudKitFamilyMetadataStore {
        let store = CloudKitFamilyMetadataStore(snapshotURL: metadataURL)
        if let accountRecordName {
            try store.confirm(accountRecordName: accountRecordName)
        }
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

    func unboundStore(
        accountRecordName: String = "account-a"
    ) throws -> CloudKitFamilyMetadataStore {
        let store = CloudKitFamilyMetadataStore(snapshotURL: metadataURL)
        try store.confirm(accountRecordName: accountRecordName)
        return store
    }

    func rootCloudRecord() -> CKRecord {
        let root = CKRecord(
            recordType: CloudKitFamilyRecordCodec.Schema.rootRecordType,
            recordID: rootRecordID
        )
        root[CloudKitFamilyRecordCodec.Schema.profileID] =
            profileID.rawValue.uuidString as NSString
        return root
    }

    func discoveryRecords(
        profileID: ProfileID,
        payload: String,
        ownerName: String,
        scope: CloudKitFamilyDatabaseScope,
        store: CloudKitFamilyMetadataStore
    ) throws -> DiscoveryRecords {
        let zoneID = CKRecordZone.ID(
            zoneName: CloudKitDeterministicProfileRoute.zoneName(for: profileID),
            ownerName: ownerName
        )
        let rootID = CKRecord.ID(
            recordName: CloudKitDeterministicProfileRoute.rootRecordName(
                for: profileID
            ),
            zoneID: zoneID
        )
        let record = FamilySyncRecord(
            recordName: "profile-\(profileID)",
            profileID: profileID,
            kind: .wordPoolEntry,
            payload: Data(payload.utf8),
            updatedAt: now,
            deviceID: "remote",
            logicalRevision: FamilySyncLogicalRevision(
                counter: 1,
                deviceID: "remote"
            )
        )
        let item = try CloudKitFamilyRecordCodec.cloudRecord(
            for: record,
            recordID: CKRecord.ID(
                recordName: record.recordName,
                zoneID: zoneID
            ),
            rootRecordID: rootID,
            scope: scope,
            metadataStore: store
        )
        let root = CKRecord(
            recordType: CloudKitFamilyRecordCodec.Schema.rootRecordType,
            recordID: rootID
        )
        root[CloudKitFamilyRecordCodec.Schema.profileID] =
            profileID.rawValue.uuidString as NSString
        return DiscoveryRecords(record: record, item: item, root: root)
    }

    func stateStore() -> CloudKitFamilySyncStateStore {
        CloudKitFamilySyncStateStore(
            directory: directory.appendingPathComponent(
                "deferred-engine-state",
                isDirectory: true
            )
        )
    }

    func serialization(
        _ marker: String
    ) throws -> CKSyncEngine.State.Serialization {
        let data = Data(marker.utf8).base64EncodedString()
        return try JSONDecoder().decode(
            CKSyncEngine.State.Serialization.self,
            from: Data(#"{"data":"\#(data)"}"#.utf8)
        )
    }

    func encoded(
        _ serialization: CKSyncEngine.State.Serialization?
    ) throws -> Data? {
        try serialization.map { try JSONEncoder().encode($0) }
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
            kind: .wordPoolEntry,
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
