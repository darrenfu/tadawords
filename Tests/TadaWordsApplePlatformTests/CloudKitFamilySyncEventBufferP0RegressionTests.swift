@preconcurrency import CloudKit
import Foundation
import TadaWordsDomain
import XCTest

@testable import TadaWordsApplePlatform

final class CloudKitFamilySyncEventBufferP0RegressionTests: XCTestCase {
    func testReplacementAccountRootLatchesBeforeHigherRevisionChildCanApply()
        async throws
    {
        let fixture = try EventBufferP0Fixture()
        defer { fixture.remove() }
        let store = CloudKitFamilyMetadataStore(
            snapshotURL: fixture.metadataURL
        )
        try store.confirm(accountRecordName: "origin-account")
        try store.save(binding: fixture.ownerBinding)

        let child = fixture.childRecord(
            profileID: fixture.ownerProfileID,
            recordName: "higher-revision-child",
            payload: "replacement-account-payload",
            revisionCounter: 99
        )
        let cloudChild = try CloudKitFamilyRecordCodec.cloudRecord(
            for: child,
            recordID: CKRecord.ID(
                recordName: child.recordName,
                zoneID: fixture.ownerZoneID
            ),
            rootRecordID: fixture.ownerRootRecordID,
            scope: .privateDatabase,
            metadataStore: store
        )

        XCTAssertEqual(
            try store.accountGate(currentAccountRecordName: "replacement-account"),
            .requiresConfirmation(.switchedAccounts)
        )
        try store.confirm(accountRecordName: "replacement-account")
        let retainedBinding = store.binding(for: fixture.ownerProfileID)
        let snapshotBeforeCallback = try Data(contentsOf: fixture.metadataURL)

        let replacementRoot = CKRecord(
            recordType: CloudKitFamilyRecordCodec.Schema.rootRecordType,
            recordID: fixture.ownerRootRecordID
        )
        replacementRoot[CloudKitFamilyRecordCodec.Schema.profileID] =
            fixture.ownerProfileID.rawValue.uuidString as NSString
        let buffer = CloudKitFamilySyncEventBuffer(metadataStore: store)

        await buffer.handle(
            .fetchedRecords([cloudChild, replacementRoot]),
            scope: .privateDatabase,
            generation: 1,
            now: fixture.now
        )
        let result = await buffer.drain()

        XCTAssertEqual(result.accountChange, .switchedAccounts)
        XCTAssertTrue(result.records.isEmpty)
        XCTAssertTrue(result.deletions.isEmpty)
        XCTAssertTrue(result.acknowledged.isEmpty)
        XCTAssertTrue(result.failures.isEmpty)
        XCTAssertTrue(result.receiptIDs.isEmpty)
        XCTAssertTrue(result.receipts.isEmpty)
        XCTAssertEqual(result.quarantinedRecordCount, 0)
        XCTAssertFalse(result.requiresFetchPass)
        XCTAssertTrue(store.inboxEntries().isEmpty)
        XCTAssertEqual(store.binding(for: fixture.ownerProfileID), retainedBinding)
        XCTAssertEqual(retainedBinding.originAccountRecordName, "origin-account")
        XCTAssertEqual(retainedBinding.erasureRoute, .owner)
        XCTAssertEqual(
            try Data(contentsOf: fixture.metadataURL),
            snapshotBeforeCallback,
            "An old-account callback must not mutate durable metadata"
        )
    }

    func testDeletionLedgerCallbackStagesRecoveryWithoutExposingTerminalRecord()
        async throws
    {
        let fixture = try EventBufferP0Fixture()
        defer { fixture.remove() }
        let store = CloudKitFamilyMetadataStore(
            snapshotURL: fixture.metadataURL
        )
        try store.confirm(accountRecordName: "owner-account")
        let ledger = try CloudKitFamilyDeletionLedgerCodec.cloudRecord(
            for: fixture.ownerDeletionRecord(revisionCounter: 41)
        )
        let buffer = CloudKitFamilySyncEventBuffer(metadataStore: store)

        await buffer.handle(
            .fetchedRecords([ledger]),
            scope: .privateDatabase,
            generation: 1,
            now: fixture.now
        )
        let result = await buffer.drain()
        let durableEntry = try XCTUnwrap(store.inboxEntries().first)
        let stagedRecord = try XCTUnwrap(durableEntry.record)
        let recoveryBinding = store.binding(for: fixture.ownerProfileID)

        XCTAssertNil(result.accountChange)
        XCTAssertTrue(result.records.isEmpty)
        XCTAssertTrue(result.deletions.isEmpty)
        XCTAssertTrue(result.acknowledged.isEmpty)
        XCTAssertTrue(result.failures.isEmpty)
        XCTAssertTrue(result.receiptIDs.isEmpty)
        XCTAssertTrue(result.receipts.isEmpty)
        XCTAssertEqual(result.quarantinedRecordCount, 0)
        XCTAssertTrue(result.requiresFetchPass)
        XCTAssertEqual(store.inboxEntries().count, 1)
        XCTAssertEqual(stagedRecord.kind, .profileDeletion)
        XCTAssertTrue(stagedRecord.isDeleted)
        XCTAssertEqual(stagedRecord.profileID, fixture.ownerProfileID)
        XCTAssertFalse(store.hasAcknowledgedTerminalRemoval(stagedRecord))
        XCTAssertEqual(recoveryBinding.state, .privateOwner)
        XCTAssertEqual(recoveryBinding.erasureRoute, .owner)
        XCTAssertEqual(recoveryBinding.originAccountRecordName, "owner-account")
        XCTAssertEqual(recoveryBinding.zoneID, fixture.ownerZoneID)

        let restarted = CloudKitFamilyMetadataStore(
            snapshotURL: fixture.metadataURL
        )
        XCTAssertEqual(restarted.inboxEntries(), [durableEntry])
        XCTAssertEqual(
            restarted.binding(for: fixture.ownerProfileID),
            recoveryBinding
        )
        XCTAssertEqual(
            restarted.binding(for: fixture.ownerProfileID).state,
            .privateOwner,
            "The event callback cannot claim terminal deletion before zone erasure"
        )
    }

    @MainActor
    func testStagedOwnerLedgerSurvivesRestartAndErasesBeforeAtomicCommitAndReplay()
        async throws
    {
        let fixture = try EventBufferP0Fixture()
        defer { fixture.remove() }
        let firstStore = CloudKitFamilyMetadataStore(
            snapshotURL: fixture.metadataURL
        )
        try firstStore.confirm(accountRecordName: "owner-account")
        try firstStore.save(binding: fixture.ownerBinding)
        let ledger = try CloudKitFamilyDeletionLedgerCodec.cloudRecord(
            for: fixture.ownerDeletionRecord(revisionCounter: 42)
        )
        let firstBuffer = CloudKitFamilySyncEventBuffer(
            metadataStore: firstStore
        )

        await firstBuffer.handle(
            .fetchedRecords([ledger]),
            scope: .privateDatabase,
            generation: 1,
            now: fixture.now
        )
        let stagedResult = await firstBuffer.drain()
        XCTAssertTrue(stagedResult.requiresFetchPass)
        XCTAssertTrue(stagedResult.records.isEmpty)

        let restartedStore = CloudKitFamilyMetadataStore(
            snapshotURL: fixture.metadataURL
        )
        let stagedEntry = try XCTUnwrap(restartedStore.inboxEntries().first)
        let recovery = try XCTUnwrap(
            restartedStore.pendingOwnerDeletionLedgerRecoveries().first
        )
        let stagedRecord = recovery.record
        let bindingBeforeRecovery = recovery.binding
        XCTAssertEqual(
            recovery.recordID,
            CloudKitFamilyDeletionLedgerCodec.recordID(
                for: fixture.ownerProfileID
            )
        )
        XCTAssertEqual(bindingBeforeRecovery.state, .privateOwner)

        var events: [String] = []
        let receiptID = try await CloudKitOwnerDeletionRecoveryExecutor().recover(
            eraseZone: {
                events.append("erase-owner-payload-zone")
                XCTAssertEqual(
                    restartedStore.binding(for: fixture.ownerProfileID).state,
                    .privateOwner
                )
                XCTAssertEqual(
                    restartedStore.inboxEntries().map(\.receiptID),
                    [stagedEntry.receiptID]
                )
            },
            commitRecovery: {
                events.append("commit-terminal-recovery")
                return try restartedStore.commitOwnerDeletionLedgerRecovery(
                    record: stagedRecord,
                    recordID: recovery.recordID,
                    previous: bindingBeforeRecovery,
                    receivedAt: recovery.receivedAt
                )
            }
        )

        XCTAssertTrue(
            try restartedStore.pendingOwnerDeletionLedgerRecoveries().isEmpty,
            "A crash after atomic commit must resume with inbox replay, not erase again"
        )
        events.append("replay-durable-inbox")
        let restartedBuffer = CloudKitFamilySyncEventBuffer(
            metadataStore: restartedStore
        )
        await restartedBuffer.replay(
            restartedStore.inboxEntries(),
            generation: 1
        )
        let replayed = await restartedBuffer.drain()

        XCTAssertEqual(
            events,
            [
                "erase-owner-payload-zone",
                "commit-terminal-recovery",
                "replay-durable-inbox",
            ]
        )
        XCTAssertEqual(receiptID, stagedEntry.receiptID)
        XCTAssertEqual(
            restartedStore.binding(for: fixture.ownerProfileID).state,
            .ownerDeleted
        )
        XCTAssertEqual(replayed.records, [stagedRecord])
        XCTAssertEqual(replayed.receiptIDs, [receiptID])
        XCTAssertFalse(replayed.requiresFetchPass)
    }

    @MainActor
    func testStagedOwnerLedgerEraseFailureCannotCommitOrReplayAfterRestart()
        async throws
    {
        let fixture = try EventBufferP0Fixture()
        defer { fixture.remove() }
        let firstStore = CloudKitFamilyMetadataStore(
            snapshotURL: fixture.metadataURL
        )
        try firstStore.confirm(accountRecordName: "owner-account")
        try firstStore.save(binding: fixture.ownerBinding)
        let ledger = try CloudKitFamilyDeletionLedgerCodec.cloudRecord(
            for: fixture.ownerDeletionRecord(revisionCounter: 43)
        )
        let firstBuffer = CloudKitFamilySyncEventBuffer(
            metadataStore: firstStore
        )

        await firstBuffer.handle(
            .fetchedRecords([ledger]),
            scope: .privateDatabase,
            generation: 1,
            now: fixture.now
        )
        _ = await firstBuffer.drain()

        let restartedStore = CloudKitFamilyMetadataStore(
            snapshotURL: fixture.metadataURL
        )
        let durableEntriesBeforeRecovery = restartedStore.inboxEntries()
        let bindingBeforeRecovery = restartedStore.binding(
            for: fixture.ownerProfileID
        )
        var didAttemptCommit = false

        do {
            _ = try await CloudKitOwnerDeletionRecoveryExecutor().recover(
                eraseZone: {
                    throw EventBufferP0RecoveryError.zoneEraseFailed
                },
                commitRecovery: {
                    didAttemptCommit = true
                    return UUID()
                }
            )
            XCTFail("A failed owner-zone erase must fail closed")
        } catch {
            XCTAssertEqual(
                error as? EventBufferP0RecoveryError,
                .zoneEraseFailed
            )
        }

        XCTAssertFalse(didAttemptCommit)
        XCTAssertEqual(
            restartedStore.binding(for: fixture.ownerProfileID),
            bindingBeforeRecovery
        )
        XCTAssertEqual(bindingBeforeRecovery.state, .privateOwner)
        XCTAssertEqual(
            restartedStore.inboxEntries(),
            durableEntriesBeforeRecovery,
            "The staged ledger must remain durable for a later retry"
        )
        XCTAssertEqual(
            try restartedStore.pendingOwnerDeletionLedgerRecoveries().count,
            1
        )
    }

    func testRemoteRootDeletionStagesOwnerAndParticipantWithoutTerminalExposure()
        async throws
    {
        let fixture = try EventBufferP0Fixture()
        defer { fixture.remove() }
        let store = CloudKitFamilyMetadataStore(
            snapshotURL: fixture.metadataURL
        )
        try store.confirm(accountRecordName: "family-account")
        try store.save(binding: fixture.ownerBinding)
        try store.save(binding: fixture.participantBinding)
        let buffer = CloudKitFamilySyncEventBuffer(metadataStore: store)

        await buffer.handle(
            .fetchedDeletions([fixture.ownerRootRecordID]),
            scope: .privateDatabase,
            generation: 1,
            now: fixture.now
        )
        let ownerResult = await buffer.drain()

        XCTAssertTrue(ownerResult.records.isEmpty)
        XCTAssertTrue(ownerResult.receiptIDs.isEmpty)
        XCTAssertTrue(ownerResult.requiresFetchPass)
        XCTAssertEqual(
            store.binding(for: fixture.ownerProfileID).state,
            .privateOwner
        )
        XCTAssertEqual(
            store.binding(for: fixture.ownerProfileID).erasureRoute,
            .owner
        )

        await buffer.handle(
            .fetchedDeletions([fixture.participantRootRecordID]),
            scope: .sharedDatabase,
            generation: 1,
            now: fixture.now.addingTimeInterval(1)
        )
        let participantResult = await buffer.drain()

        XCTAssertTrue(participantResult.records.isEmpty)
        XCTAssertTrue(participantResult.receiptIDs.isEmpty)
        XCTAssertTrue(participantResult.requiresFetchPass)
        XCTAssertEqual(
            store.binding(for: fixture.participantProfileID).state,
            .sharedParticipant
        )
        XCTAssertEqual(
            store.binding(for: fixture.participantProfileID).erasureRoute,
            .participant
        )

        let restarted = CloudKitFamilyMetadataStore(
            snapshotURL: fixture.metadataURL
        )
        XCTAssertEqual(
            restarted.binding(for: fixture.ownerProfileID).state,
            .privateOwner
        )
        XCTAssertEqual(
            restarted.binding(for: fixture.ownerProfileID).erasureRoute,
            .owner
        )
        XCTAssertEqual(
            restarted.binding(for: fixture.participantProfileID).state,
            .sharedParticipant
        )
        XCTAssertEqual(
            restarted.binding(for: fixture.participantProfileID).erasureRoute,
            .participant
        )
        XCTAssertTrue(
            try restarted.pendingOwnerDeletionLedgerRecoveries().isEmpty,
            "Profile-zone root receipts must never be misclassified as control ledgers"
        )
        let pendingRoots = try restarted.pendingRemoteRootRemovalRecoveries()
        XCTAssertEqual(pendingRoots.count, 2)
        XCTAssertEqual(
            Set(pendingRoots.map { $0.record.profileID }),
            [fixture.ownerProfileID, fixture.participantProfileID]
        )
        XCTAssertTrue(
            restarted.inboxEntries().allSatisfy {
                $0.terminalEvidence == .rootRecordDeletion
            }
        )
    }

    func testDeletionChildOfRejectedAlternateRootCannotApply() async throws {
        let fixture = try EventBufferP0Fixture()
        defer { fixture.remove() }
        let store = CloudKitFamilyMetadataStore(
            snapshotURL: fixture.metadataURL
        )
        try store.confirm(accountRecordName: "owner-account")
        try store.save(binding: fixture.ownerBinding)
        let originalBinding = store.binding(for: fixture.ownerProfileID)
        let alternateRootID = CKRecord.ID(
            recordName: "alternate-profile-root",
            zoneID: fixture.ownerZoneID
        )
        let alternateRoot = CKRecord(
            recordType: CloudKitFamilyRecordCodec.Schema.rootRecordType,
            recordID: alternateRootID
        )
        alternateRoot[CloudKitFamilyRecordCodec.Schema.profileID] =
            fixture.ownerProfileID.rawValue.uuidString as NSString
        let deletion = try fixture.ownerDeletionRecord(revisionCounter: 88)
        let alternateChild = try CloudKitFamilyRecordCodec.cloudRecord(
            for: deletion,
            recordID: CKRecord.ID(
                recordName: deletion.recordName,
                zoneID: fixture.ownerZoneID
            ),
            rootRecordID: alternateRootID,
            scope: .privateDatabase,
            metadataStore: store
        )
        let buffer = CloudKitFamilySyncEventBuffer(metadataStore: store)

        await buffer.handle(
            .fetchedRecords([alternateRoot, alternateChild]),
            scope: .privateDatabase,
            generation: 1,
            now: fixture.now
        )
        let result = await buffer.drain()

        XCTAssertTrue(result.records.isEmpty)
        XCTAssertTrue(result.deletions.isEmpty)
        XCTAssertTrue(result.receiptIDs.isEmpty)
        XCTAssertTrue(result.receipts.isEmpty)
        XCTAssertEqual(result.quarantinedRecordCount, 2)
        XCTAssertTrue(store.inboxEntries().isEmpty)
        XCTAssertEqual(
            store.binding(for: fixture.ownerProfileID),
            originalBinding
        )
        XCTAssertEqual(originalBinding.state, .privateOwner)
    }
}

private enum EventBufferP0RecoveryError: Error, Equatable {
    case zoneEraseFailed
}

private struct EventBufferP0Fixture {
    let directory: URL
    let metadataURL: URL
    let ownerProfileID = ProfileID()
    let participantProfileID = ProfileID()
    let now = Date(timeIntervalSince1970: 2_174_000_000)

    var ownerZoneID: CKRecordZone.ID {
        CKRecordZone.ID(
            zoneName: "TadaProfile-\(ownerProfileID.rawValue.uuidString)",
            ownerName: CKCurrentUserDefaultName
        )
    }

    var participantZoneID: CKRecordZone.ID {
        CKRecordZone.ID(
            zoneName: "SharedP0RegressionZone",
            ownerName: "share-owner"
        )
    }

    var ownerRootRecordID: CKRecord.ID {
        CKRecord.ID(
            recordName: "profile-root-\(ownerProfileID.rawValue.uuidString)",
            zoneID: ownerZoneID
        )
    }

    var participantRootRecordID: CKRecord.ID {
        CKRecord.ID(
            recordName: "shared-profile-root",
            zoneID: participantZoneID
        )
    }

    var ownerBinding: ProfileCloudBinding {
        ProfileCloudBinding(
            profileID: ownerProfileID,
            state: .privateOwner,
            zoneName: ownerZoneID.zoneName,
            ownerName: ownerZoneID.ownerName,
            rootRecordName: ownerRootRecordID.recordName
        )
    }

    var participantBinding: ProfileCloudBinding {
        ProfileCloudBinding(
            profileID: participantProfileID,
            state: .sharedParticipant,
            zoneName: participantZoneID.zoneName,
            ownerName: participantZoneID.ownerName,
            rootRecordName: participantRootRecordID.recordName
        )
    }

    init() throws {
        directory = FileManager.default.temporaryDirectory.appendingPathComponent(
            "TadaEventBufferP0-\(UUID().uuidString)",
            isDirectory: true
        )
        try FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true
        )
        metadataURL = directory.appendingPathComponent("metadata.json")
    }

    func childRecord(
        profileID: ProfileID,
        recordName: String,
        payload: String,
        revisionCounter: UInt64
    ) -> FamilySyncRecord {
        FamilySyncRecord(
            recordName: recordName,
            profileID: profileID,
            kind: .wordPoolEntry,
            payload: Data(payload.utf8),
            updatedAt: now,
            deviceID: "remote-device",
            logicalRevision: FamilySyncLogicalRevision(
                counter: revisionCounter,
                deviceID: "remote-device"
            )
        )
    }

    func ownerDeletionRecord(revisionCounter: UInt64) throws -> FamilySyncRecord {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .secondsSince1970
        encoder.outputFormatting = [.sortedKeys]
        return FamilySyncRecord(
            recordName: "profile-\(ownerProfileID)",
            profileID: ownerProfileID,
            kind: .profileDeletion,
            payload: try encoder.encode(
                ProfileDeletionTombstone(
                    profileID: ownerProfileID,
                    deletedAt: now
                )
            ),
            updatedAt: now,
            deviceID: "owner-device",
            isDeleted: true,
            logicalRevision: FamilySyncLogicalRevision(
                counter: revisionCounter,
                deviceID: "owner-device"
            )
        )
    }

    func remove() {
        try? FileManager.default.removeItem(at: directory)
    }
}
