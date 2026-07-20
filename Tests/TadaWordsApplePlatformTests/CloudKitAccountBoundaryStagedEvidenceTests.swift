@preconcurrency import CloudKit
import Foundation
import TadaWordsDomain
import XCTest

@testable import TadaWordsApplePlatform

final class CloudKitAccountBoundaryStagedEvidenceTests: XCTestCase {
    func testRootAndZoneEvidenceSurvivesSameAccountReconfirmation()
        throws
    {
        for evidence in [StagedEvidence.root, .zone] {
            let fixture = try AccountBoundaryEvidenceFixture(
                name: "same-account-\(evidence)"
            )
            defer { fixture.remove() }
            let store = fixture.store()
            try fixture.configureOriginAccount(in: store)
            let receiptID = try fixture.stage(evidence, in: store)

            try store.requireAccountConfirmation()
            XCTAssertNil(
                try store.confirm(
                    accountRecordName: AccountBoundaryEvidenceFixture.originAccount
                )
            )

            let restarted = fixture.store()
            XCTAssertEqual(
                restarted.inboxEntries().map(\.receiptID),
                [receiptID],
                "Explicit \(evidence) evidence must survive same-account confirmation"
            )
            XCTAssertEqual(
                try fixture.pendingCount(for: evidence, in: restarted),
                1
            )
        }
    }

    func testOwnerRootAndZoneEvidenceIsDormantOnReplacementAccountAndRecoversOnce()
        throws
    {
        for evidence in StagedEvidence.allCases {
            let fixture = try AccountBoundaryEvidenceFixture(
                name: "account-round-trip-\(evidence)"
            )
            defer { fixture.remove() }
            let originStore = fixture.store()
            try fixture.configureOriginAccount(in: originStore)
            let receiptID = try fixture.stage(evidence, in: originStore)

            XCTAssertEqual(
                try originStore.confirm(
                    accountRecordName: AccountBoundaryEvidenceFixture.replacementAccount
                ),
                .switchedAccounts
            )

            let replacementStore = fixture.store()
            XCTAssertTrue(
                replacementStore.inboxEntries().isEmpty,
                "Foreign-account terminal evidence must not enter general replay"
            )
            try assertAllRecoveriesAreDormant(in: replacementStore)

            XCTAssertEqual(
                try replacementStore.confirm(
                    accountRecordName: AccountBoundaryEvidenceFixture.originAccount
                ),
                .switchedAccounts
            )

            // Exercise a second account round trip before recovery. Retention
            // must be idempotent, not append a new receipt on every seal.
            XCTAssertEqual(
                try replacementStore.confirm(
                    accountRecordName: AccountBoundaryEvidenceFixture.replacementAccount
                ),
                .switchedAccounts
            )
            try assertAllRecoveriesAreDormant(in: replacementStore)
            XCTAssertEqual(
                try replacementStore.confirm(
                    accountRecordName: AccountBoundaryEvidenceFixture.originAccount
                ),
                .switchedAccounts
            )

            let returnedStore = fixture.store()
            XCTAssertEqual(returnedStore.inboxEntries().map(\.receiptID), [receiptID])
            XCTAssertEqual(
                try fixture.pendingCount(for: evidence, in: returnedStore),
                1,
                "Origin account must recover exactly one \(evidence) item"
            )
            XCTAssertEqual(
                try fixture.commit(evidence, in: returnedStore),
                receiptID
            )
            XCTAssertEqual(
                try fixture.pendingCount(for: evidence, in: returnedStore),
                0,
                "Committed evidence must not remain a staged recovery"
            )
            XCTAssertEqual(returnedStore.inboxEntries().map(\.receiptID), [receiptID])
            XCTAssertEqual(
                returnedStore.binding(for: fixture.profileID).state,
                .ownerDeleted
            )
        }
    }

    func testAccountSwitchDropsGenericChildButRetainsExplicitRootEvidence()
        throws
    {
        let fixture = try AccountBoundaryEvidenceFixture(name: "generic-child")
        defer { fixture.remove() }
        let store = fixture.store()
        try fixture.configureOriginAccount(in: store)
        let child = fixture.childRecord()
        _ = try store.appendInbox(
            record: child,
            recordID: fixture.childRecordID,
            scope: .privateDatabase,
            receivedAt: fixture.now
        )
        let rootReceiptID = try fixture.stage(.root, in: store)

        XCTAssertEqual(
            try store.confirm(
                accountRecordName: AccountBoundaryEvidenceFixture.replacementAccount
            ),
            .switchedAccounts
        )
        XCTAssertTrue(store.inboxEntries().isEmpty)
        try assertAllRecoveriesAreDormant(in: store)

        XCTAssertEqual(
            try store.confirm(
                accountRecordName: AccountBoundaryEvidenceFixture.originAccount
            ),
            .switchedAccounts
        )
        let restarted = fixture.store()
        XCTAssertEqual(restarted.inboxEntries().map(\.receiptID), [rootReceiptID])
        XCTAssertEqual(try restarted.pendingRemoteRootRemovalRecoveries().count, 1)
        XCTAssertFalse(
            try String(contentsOf: fixture.metadataURL, encoding: .utf8)
                .contains(child.payload.base64EncodedString()),
            "Generic child bytes must not cross an account boundary"
        )
    }

    func testLegacyNilEvidenceOnActiveBindingIsNeverRetained() throws {
        for boundary in ConfirmationBoundary.allCases {
            let fixture = try AccountBoundaryEvidenceFixture(
                name: "legacy-nil-\(boundary)"
            )
            defer { fixture.remove() }
            let store = fixture.store()
            try fixture.configureOriginAccount(in: store)
            _ = try store.appendInbox(
                record: fixture.deletionRecord,
                recordID: fixture.rootRecordID,
                scope: .privateDatabase,
                receivedAt: fixture.now,
                terminalEvidence: nil
            )

            switch boundary {
            case .sameAccount:
                try store.requireAccountConfirmation()
                XCTAssertNil(
                    try store.confirm(
                        accountRecordName: AccountBoundaryEvidenceFixture.originAccount
                    )
                )
            case .accountRoundTrip:
                XCTAssertEqual(
                    try store.confirm(
                        accountRecordName:
                            AccountBoundaryEvidenceFixture.replacementAccount
                    ),
                    .switchedAccounts
                )
                XCTAssertEqual(
                    try store.confirm(
                        accountRecordName: AccountBoundaryEvidenceFixture.originAccount
                    ),
                    .switchedAccounts
                )
            }

            let restarted = fixture.store()
            XCTAssertTrue(restarted.inboxEntries().isEmpty)
            XCTAssertTrue(
                try restarted.pendingRemoteRootRemovalRecoveries().isEmpty
            )
            XCTAssertTrue(
                try restarted.pendingRemoteZoneRemovalRecoveries().isEmpty
            )
        }
    }

    func testAmbiguousRootAndZoneMarkersStayDormantAndDeduplicatedAcrossAccounts()
        throws
    {
        for evidence in [
            CloudKitAmbiguousRemoteRemovalEvidence.rootRecordDeletion,
            .zoneDeletion,
        ] {
            let fixture = try AccountBoundaryEvidenceFixture(
                name: "ambiguous-round-trip-\(evidence.rawValue)"
            )
            defer { fixture.remove() }
            let store = fixture.store()
            try fixture.configureOriginAccount(in: store)

            let markerID = try fixture.stageAmbiguous(evidence, in: store)
            XCTAssertEqual(
                try fixture.stageAmbiguous(evidence, in: store),
                markerID,
                "Repeated callback staging must keep one durable marker"
            )
            XCTAssertTrue(
                store.inboxEntries().isEmpty,
                "An unverified observation is never a replayable inbox record"
            )
            XCTAssertEqual(
                try store.pendingAmbiguousRemoteRemovalRevalidations().map(\.id),
                [markerID]
            )

            XCTAssertEqual(
                try store.confirm(
                    accountRecordName: AccountBoundaryEvidenceFixture.replacementAccount
                ),
                .switchedAccounts
            )
            let replacementStore = fixture.store()
            XCTAssertTrue(replacementStore.inboxEntries().isEmpty)
            XCTAssertTrue(
                try replacementStore
                    .pendingAmbiguousRemoteRemovalRevalidations().isEmpty,
                "A foreign account must not revalidate an origin-account marker"
            )

            XCTAssertEqual(
                try replacementStore.confirm(
                    accountRecordName: AccountBoundaryEvidenceFixture.originAccount
                ),
                .switchedAccounts
            )
            let returnedStore = fixture.store()
            let returned =
                try returnedStore.pendingAmbiguousRemoteRemovalRevalidations()
            XCTAssertEqual(returned.map(\.id), [markerID])
            XCTAssertEqual(returned.first?.evidence, evidence)
            XCTAssertTrue(returnedStore.inboxEntries().isEmpty)
        }
    }

    func testAmbiguousDirectProofCanCommitOrDiscardWithoutPrematureReplay()
        throws
    {
        for evidence in [
            CloudKitAmbiguousRemoteRemovalEvidence.rootRecordDeletion,
            .zoneDeletion,
        ] {
            for resolution in AmbiguousResolution.allCases {
                let fixture = try AccountBoundaryEvidenceFixture(
                    name: "ambiguous-\(evidence.rawValue)-\(resolution)"
                )
                defer { fixture.remove() }
                let store = fixture.store()
                try fixture.configureOriginAccount(in: store)
                _ = try fixture.stageAmbiguous(evidence, in: store)
                let marker = try XCTUnwrap(
                    store.pendingAmbiguousRemoteRemovalRevalidations().only
                )

                switch resolution {
                case .cloudObjectStillExists:
                    try store.discardAmbiguousRemoteRemoval(marker)
                    XCTAssertEqual(
                        store.binding(for: fixture.profileID).state,
                        .privateOwner
                    )
                    XCTAssertTrue(store.inboxEntries().isEmpty)
                case .cloudDeletionConfirmed:
                    let receiptID = try store.commitAmbiguousRemoteRemoval(
                        marker,
                        record: fixture.deletionRecord
                    )
                    XCTAssertEqual(
                        store.binding(for: fixture.profileID).state,
                        .ownerDeleted
                    )
                    XCTAssertEqual(
                        store.inboxEntries().map(\.receiptID),
                        [receiptID],
                        "Only direct absence proof may create a terminal receipt"
                    )
                }

                XCTAssertTrue(
                    try store.pendingAmbiguousRemoteRemovalRevalidations().isEmpty
                )
            }
        }
    }

    func testVerifierMismatchStagesAmbiguousMarkerBeforeLatchingAccountBoundary()
        async throws
    {
        for evidence in [
            CloudKitAmbiguousRemoteRemovalEvidence.rootRecordDeletion,
            .zoneDeletion,
        ] {
            let fixture = try AccountBoundaryEvidenceFixture(
                name: "verifier-mismatch-\(evidence.rawValue)"
            )
            defer { fixture.remove() }
            let store = fixture.store()
            try fixture.configureOriginAccount(in: store)
            let buffer = CloudKitFamilySyncEventBuffer(
                metadataStore: store,
                liveAccountVerifier: CloudKitLiveAccountVerifier { _ in
                    throw CloudKitFamilySyncError.accountBindingMismatch
                }
            )

            switch evidence {
            case .ownerDeletionLedger:
                XCTFail("This loop only exercises root and zone callbacks")
            case .rootRecordDeletion:
                await buffer.handle(
                    .fetchedDeletions([fixture.rootRecordID]),
                    scope: .privateDatabase,
                    generation: 1,
                    now: fixture.now
                )
            case .zoneDeletion:
                await buffer.handle(
                    .deletedZones([fixture.zoneID]),
                    scope: .privateDatabase,
                    generation: 1,
                    now: fixture.now
                )
            }
            let result = await buffer.drain()

            XCTAssertEqual(result.accountChange, .switchedAccounts)
            XCTAssertTrue(result.records.isEmpty)
            XCTAssertTrue(result.receiptIDs.isEmpty)
            XCTAssertTrue(store.inboxEntries().isEmpty)
            let markers = try store.pendingAmbiguousRemoteRemovalRevalidations()
            XCTAssertEqual(markers.count, 1)
            XCTAssertEqual(markers.first?.evidence, evidence)
            XCTAssertEqual(markers.first?.profileID, fixture.profileID)
        }
    }

    func testOwnerLedgerMarkerIsDurableBeforeVerifierMismatchWithoutInboxOrSystemFields()
        async throws
    {
        let fixture = try AccountBoundaryEvidenceFixture(
            name: "owner-ledger-verifier-mismatch"
        )
        defer { fixture.remove() }
        let store = fixture.store()
        try fixture.configureOriginAccount(in: store)
        let cloudLedger = try fixture.ownerDeletionLedgerCloudRecord
        let buffer = CloudKitFamilySyncEventBuffer(
            metadataStore: store,
            liveAccountVerifier: CloudKitLiveAccountVerifier { _ in
                throw CloudKitFamilySyncError.accountBindingMismatch
            }
        )

        await buffer.handle(
            .fetchedRecords([cloudLedger]),
            scope: .privateDatabase,
            generation: 1,
            now: fixture.now
        )
        let result = await buffer.drain()

        XCTAssertEqual(result.accountChange, .switchedAccounts)
        XCTAssertTrue(result.records.isEmpty)
        XCTAssertTrue(result.receiptIDs.isEmpty)
        XCTAssertTrue(store.inboxEntries().isEmpty)
        XCTAssertNil(
            store.restoredRecord(
                id: cloudLedger.recordID,
                scope: .privateDatabase
            ),
            "Unverified old-account system fields must never be saved"
        )
        let markers = try store.pendingAmbiguousRemoteRemovalRevalidations()
        XCTAssertEqual(markers.count, 1)
        XCTAssertEqual(markers.first?.evidence, .ownerDeletionLedger)
        XCTAssertEqual(markers.first?.profileID, fixture.profileID)
    }

    func testOwnerLedgerMarkerSurvivesGenerationAndSameAccountRebuildWithoutOldCallbackWrites()
        async throws
    {
        let fixture = try AccountBoundaryEvidenceFixture(
            name: "owner-ledger-generation-rebuild"
        )
        defer { fixture.remove() }
        let store = fixture.store()
        try fixture.configureOriginAccount(in: store)
        let cloudLedger = try fixture.ownerDeletionLedgerCloudRecord
        let verifierGate = AccountBoundaryVerifierGate()
        let buffer = CloudKitFamilySyncEventBuffer(
            metadataStore: store,
            liveAccountVerifier: CloudKitLiveAccountVerifier { _ in
                try await verifierGate.verify()
            }
        )

        let oldCallback = Task {
            await buffer.handle(
                .fetchedRecords([cloudLedger]),
                scope: .privateDatabase,
                generation: 1,
                now: fixture.now
            )
        }
        await verifierGate.waitUntilStarted()

        let markerBeforeRebuild = try XCTUnwrap(
            store.pendingAmbiguousRemoteRemovalRevalidations().only
        )
        XCTAssertEqual(markerBeforeRebuild.evidence, .ownerDeletionLedger)
        XCTAssertTrue(store.inboxEntries().isEmpty)

        let nextGeneration = await buffer.nextGeneration()
        XCTAssertEqual(nextGeneration, 2)
        await verifierGate.succeed()
        await oldCallback.value

        XCTAssertTrue(store.inboxEntries().isEmpty)
        XCTAssertNil(
            store.restoredRecord(
                id: cloudLedger.recordID,
                scope: .privateDatabase
            ),
            "A verifier result from an old generation must not save system fields"
        )
        XCTAssertEqual(
            try store.pendingAmbiguousRemoteRemovalRevalidations().map(\.id),
            [markerBeforeRebuild.id]
        )

        try store.requireAccountConfirmation()
        XCTAssertNil(
            try store.confirm(
                accountRecordName: AccountBoundaryEvidenceFixture.originAccount
            )
        )
        let restarted = fixture.store()
        XCTAssertEqual(
            try restarted.pendingAmbiguousRemoteRemovalRevalidations().map(\.id),
            [markerBeforeRebuild.id],
            "Same-account confirmation and process rebuild must retain the marker"
        )
        XCTAssertTrue(restarted.inboxEntries().isEmpty)
    }

    func testOldGenerationOwnerLedgerBatchCannotAppendLaterChildAfterVerifierAwait()
        async throws
    {
        let fixture = try AccountBoundaryEvidenceFixture(
            name: "owner-ledger-old-batch-child"
        )
        defer { fixture.remove() }
        let store = fixture.store()
        try fixture.configureOriginAccount(in: store)
        let cloudLedger = try fixture.ownerDeletionLedgerCloudRecord
        let cloudRoot = fixture.rootCloudRecord
        let child = fixture.childRecord()
        let cloudChild = try fixture.cloudRecord(for: child, in: store)
        let verifierGate = AccountBoundaryVerifierGate()
        let buffer = CloudKitFamilySyncEventBuffer(
            metadataStore: store,
            liveAccountVerifier: CloudKitLiveAccountVerifier { _ in
                try await verifierGate.verify()
            }
        )

        let oldBatch = Task {
            await buffer.handle(
                .fetchedRecords([cloudChild, cloudRoot, cloudLedger]),
                scope: .privateDatabase,
                generation: 1,
                now: fixture.now
            )
        }
        await verifierGate.waitUntilStarted()
        let markerID = try XCTUnwrap(
            store.pendingAmbiguousRemoteRemovalRevalidations().only
        ).id

        let newGeneration = await buffer.nextGeneration()
        XCTAssertEqual(newGeneration, 2)
        await verifierGate.succeed()
        await oldBatch.value

        XCTAssertTrue(
            store.inboxEntries().isEmpty,
            "The remainder of an old-generation fetched-record batch must be abandoned"
        )
        XCTAssertNil(
            store.restoredRecord(
                id: cloudChild.recordID,
                scope: .privateDatabase
            )
        )
        XCTAssertNil(
            store.restoredRecord(
                id: cloudRoot.recordID,
                scope: .privateDatabase
            ),
            "The old batch must stop before its root modification too"
        )
        XCTAssertEqual(
            try store.pendingAmbiguousRemoteRemovalRevalidations().map(\.id),
            [markerID],
            "Only the fact durably staged before the await may survive"
        )
        let result = await buffer.drain()
        XCTAssertTrue(result.records.isEmpty)
        XCTAssertTrue(result.receiptIDs.isEmpty)
    }

    func testOldGenerationRootDeletionBatchCannotAppendLaterChildDeletion()
        async throws
    {
        let fixture = try AccountBoundaryEvidenceFixture(
            name: "root-old-batch-child-deletion"
        )
        defer { fixture.remove() }
        let store = fixture.store()
        try fixture.configureOriginAccount(in: store)
        let verifierGate = AccountBoundaryVerifierGate()
        let buffer = CloudKitFamilySyncEventBuffer(
            metadataStore: store,
            liveAccountVerifier: CloudKitLiveAccountVerifier { _ in
                try await verifierGate.verify()
            }
        )

        let oldBatch = Task {
            await buffer.handle(
                .fetchedDeletions([
                    fixture.rootRecordID,
                    fixture.childRecordID,
                ]),
                scope: .privateDatabase,
                generation: 1,
                now: fixture.now
            )
        }
        await verifierGate.waitUntilStarted()
        let markerID = try XCTUnwrap(
            store.pendingAmbiguousRemoteRemovalRevalidations().only
        ).id

        let newGeneration = await buffer.nextGeneration()
        XCTAssertEqual(newGeneration, 2)
        await verifierGate.succeed()
        await oldBatch.value

        XCTAssertTrue(
            store.inboxEntries().isEmpty,
            "The remainder of an old-generation deletion batch must be abandoned"
        )
        XCTAssertEqual(
            try store.pendingAmbiguousRemoteRemovalRevalidations().map(\.id),
            [markerID]
        )
        let result = await buffer.drain()
        XCTAssertTrue(result.deletions.isEmpty)
        XCTAssertTrue(result.receiptIDs.isEmpty)
    }

    func testOldGenerationDeletedZonesBatchCannotStageItsNextZone() async throws {
        let fixture = try AccountBoundaryEvidenceFixture(
            name: "old-batch-multiple-deleted-zones"
        )
        defer { fixture.remove() }
        let store = fixture.store()
        try fixture.configureOriginAccount(in: store)
        let unrelatedBinding = try fixture.configureUnrelatedOriginBinding(
            in: store
        )
        let unrelatedZoneID = try XCTUnwrap(unrelatedBinding.zoneID)
        let verifierGate = AccountBoundaryVerifierGate()
        let buffer = CloudKitFamilySyncEventBuffer(
            metadataStore: store,
            liveAccountVerifier: CloudKitLiveAccountVerifier { _ in
                try await verifierGate.verify()
            }
        )

        let oldBatch = Task {
            await buffer.handle(
                .deletedZones([fixture.zoneID, unrelatedZoneID]),
                scope: .privateDatabase,
                generation: 1,
                now: fixture.now
            )
        }
        await verifierGate.waitUntilStarted()
        let firstMarker = try XCTUnwrap(
            store.pendingAmbiguousRemoteRemovalRevalidations().only
        )
        XCTAssertEqual(firstMarker.profileID, fixture.profileID)

        let newGeneration = await buffer.nextGeneration()
        XCTAssertEqual(newGeneration, 2)
        await verifierGate.succeed()
        await oldBatch.value

        XCTAssertEqual(
            try store.pendingAmbiguousRemoteRemovalRevalidations().map(\.id),
            [firstMarker.id],
            "No later zone in an old-generation batch may be staged"
        )
        XCTAssertTrue(store.inboxEntries().isEmpty)
        XCTAssertEqual(
            store.binding(for: unrelatedBinding.profileID),
            unrelatedBinding
        )
        XCTAssertTrue(try store.pendingRemoteZoneRemovalRecoveries().isEmpty)
    }

    func testOwnerLedgerStateUpdateDuringVerifierAwaitCannotLoseDurableMarker()
        async throws
    {
        let fixture = try AccountBoundaryEvidenceFixture(
            name: "owner-ledger-state-update-race"
        )
        defer { fixture.remove() }
        let store = fixture.store()
        try fixture.configureOriginAccount(in: store)
        let cloudLedger = try fixture.ownerDeletionLedgerCloudRecord
        let verifierGate = AccountBoundaryVerifierGate()
        let buffer = CloudKitFamilySyncEventBuffer(
            metadataStore: store,
            liveAccountVerifier: CloudKitLiveAccountVerifier { _ in
                try await verifierGate.verify()
            }
        )
        let stateStore = CloudKitFamilySyncStateStore(
            directory: fixture.directory.appendingPathComponent(
                "engine-state",
                isDirectory: true
            )
        )
        let serialization = try JSONDecoder().decode(
            CKSyncEngine.State.Serialization.self,
            from: Data(#"{"data":"bGVkZ2VyLWFkdmFuY2VkLXRva2Vu"}"#.utf8)
        )

        let callback = Task {
            await buffer.handle(
                .fetchedRecords([cloudLedger]),
                scope: .privateDatabase,
                generation: 1,
                now: fixture.now
            )
        }
        await verifierGate.waitUntilStarted()

        let durableMarkerID = try XCTUnwrap(
            store.pendingAmbiguousRemoteRemovalRevalidations().only
        ).id
        await buffer.persistEngineState(
            serialization,
            scope: .privateDatabase,
            generation: 1,
            stateStore: stateStore
        )
        XCTAssertNotNil(
            stateStore.load(.privateDatabase),
            "This reproduces a state token advancing while account verification is suspended"
        )

        await verifierGate.failWithAccountMismatch()
        await callback.value
        let result = await buffer.drain()

        XCTAssertEqual(result.accountChange, .switchedAccounts)
        XCTAssertTrue(store.inboxEntries().isEmpty)
        XCTAssertEqual(
            try store.pendingAmbiguousRemoteRemovalRevalidations().map(\.id),
            [durableMarkerID],
            "A persisted engine token cannot become the sole copy of the callback fact"
        )
        XCTAssertNil(
            store.restoredRecord(
                id: cloudLedger.recordID,
                scope: .privateDatabase
            )
        )
    }

    func testReturnedOriginPromotesOwnerLedgerOnlyAfterDirectControlRecordProof()
        throws
    {
        for proof in ControlLedgerProof.allCases {
            let fixture = try AccountBoundaryEvidenceFixture(
                name: "owner-ledger-direct-proof-\(proof)"
            )
            defer { fixture.remove() }
            let store = fixture.store()
            try fixture.configureOriginAccount(in: store)
            let markerID = try fixture.stageAmbiguous(
                .ownerDeletionLedger,
                in: store
            )

            XCTAssertEqual(
                try store.confirm(
                    accountRecordName: AccountBoundaryEvidenceFixture.replacementAccount
                ),
                .switchedAccounts
            )
            XCTAssertTrue(
                try store.pendingAmbiguousRemoteRemovalRevalidations().isEmpty
            )
            XCTAssertEqual(
                try store.confirm(
                    accountRecordName: AccountBoundaryEvidenceFixture.originAccount
                ),
                .switchedAccounts
            )

            let returnedStore = fixture.store()
            let marker = try XCTUnwrap(
                returnedStore.pendingAmbiguousRemoteRemovalRevalidations().only
            )
            XCTAssertEqual(marker.id, markerID)
            XCTAssertEqual(marker.evidence, .ownerDeletionLedger)

            switch proof {
            case .controlRecordExists:
                let receiptID = try returnedStore.promoteAmbiguousRemoteRemoval(
                    markerID: marker.id,
                    record: fixture.deletionRecord
                )
                let entry = try XCTUnwrap(returnedStore.inboxEntries().only)
                XCTAssertEqual(entry.receiptID, receiptID)
                XCTAssertEqual(entry.terminalEvidence, .ownerDeletionLedger)
                XCTAssertEqual(
                    entry.zoneName,
                    CloudKitFamilyDeletionLedgerCodec.controlZoneID.zoneName
                )
                XCTAssertEqual(
                    entry.ownerName,
                    CloudKitFamilyDeletionLedgerCodec.controlZoneID.ownerName
                )
                XCTAssertEqual(
                    try returnedStore.pendingOwnerDeletionLedgerRecoveries().count,
                    1
                )
            case .controlRecordAbsent:
                XCTAssertTrue(
                    try returnedStore
                        .discardAmbiguousOwnerDeletionLedgerAbsence(marker)
                )
                XCTAssertTrue(returnedStore.inboxEntries().isEmpty)
                XCTAssertTrue(
                    try returnedStore.pendingOwnerDeletionLedgerRecoveries().isEmpty
                )
            }

            XCTAssertTrue(
                try returnedStore.pendingAmbiguousRemoteRemovalRevalidations().isEmpty
            )
            XCTAssertEqual(
                returnedStore.binding(for: fixture.profileID).state,
                .privateOwner,
                "Control-ledger proof still requires payload-zone erasure before terminal state"
            )
        }
    }

    func testUnknownOwnerLedgerAbsentProofAtomicallyRemovesProvisionalBindingAfterRestart()
        async throws
    {
        let fixture = try AccountBoundaryEvidenceFixture(
            name: "unknown-owner-ledger-absent"
        )
        defer { fixture.remove() }
        let store = fixture.store()
        XCTAssertEqual(
            try store.confirm(
                accountRecordName: AccountBoundaryEvidenceFixture.originAccount
            ),
            .signedIn
        )
        let otherBinding = try fixture.configureUnrelatedOriginBinding(in: store)
        let cloudLedger = try fixture.ownerDeletionLedgerCloudRecord
        let buffer = CloudKitFamilySyncEventBuffer(
            metadataStore: store,
            liveAccountVerifier: CloudKitLiveAccountVerifier { _ in
                throw CloudKitFamilySyncError.accountBindingMismatch
            }
        )

        await buffer.handle(
            .fetchedRecords([cloudLedger]),
            scope: .privateDatabase,
            generation: 1,
            now: fixture.now
        )
        let mismatchResult = await buffer.drain()
        XCTAssertEqual(mismatchResult.accountChange, .switchedAccounts)
        let markerID = try XCTUnwrap(
            store.pendingAmbiguousRemoteRemovalRevalidations().only
        ).id
        XCTAssertTrue(store.hasPersistedBinding(for: fixture.profileID))
        XCTAssertEqual(
            store.binding(for: fixture.profileID).originAccountRecordName,
            AccountBoundaryEvidenceFixture.originAccount
        )

        XCTAssertEqual(
            try store.confirm(
                accountRecordName: AccountBoundaryEvidenceFixture.replacementAccount
            ),
            .switchedAccounts
        )
        let replacementStore = fixture.store()
        XCTAssertTrue(
            try replacementStore
                .pendingAmbiguousRemoteRemovalRevalidations().isEmpty,
            "The provisional origin binding and marker must remain dormant under B"
        )
        XCTAssertTrue(replacementStore.hasPersistedBinding(for: fixture.profileID))

        XCTAssertEqual(
            try replacementStore.confirm(
                accountRecordName: AccountBoundaryEvidenceFixture.originAccount
            ),
            .switchedAccounts
        )
        let returnedStore = fixture.store()
        let returnedMarker = try XCTUnwrap(
            returnedStore.pendingAmbiguousRemoteRemovalRevalidations().only
        )
        XCTAssertEqual(returnedMarker.id, markerID)

        XCTAssertTrue(
            try returnedStore.discardAmbiguousOwnerDeletionLedgerAbsence(
                returnedMarker
            )
        )

        XCTAssertFalse(
            returnedStore.hasPersistedBinding(for: fixture.profileID),
            "Exact control-record absence must roll back a callback-created binding"
        )
        XCTAssertEqual(
            returnedStore.binding(for: fixture.profileID).state,
            .unbound
        )
        XCTAssertTrue(
            try returnedStore.pendingAmbiguousRemoteRemovalRevalidations().isEmpty
        )
        XCTAssertEqual(
            returnedStore.binding(for: otherBinding.profileID),
            otherBinding,
            "Provisional cleanup must be Profile-scoped"
        )

        let finalRestart = fixture.store()
        XCTAssertFalse(finalRestart.hasPersistedBinding(for: fixture.profileID))
        XCTAssertEqual(
            finalRestart.binding(for: otherBinding.profileID),
            otherBinding
        )
    }

    func testExistingOwnerBindingSurvivesAbsentLedgerProof() async throws {
        let fixture = try AccountBoundaryEvidenceFixture(
            name: "existing-owner-ledger-absent"
        )
        defer { fixture.remove() }
        let store = fixture.store()
        try fixture.configureOriginAccount(in: store)
        let originalBinding = store.binding(for: fixture.profileID)
        let cloudLedger = try fixture.ownerDeletionLedgerCloudRecord
        let buffer = CloudKitFamilySyncEventBuffer(
            metadataStore: store,
            liveAccountVerifier: CloudKitLiveAccountVerifier { _ in
                throw CloudKitFamilySyncError.accountBindingMismatch
            }
        )

        await buffer.handle(
            .fetchedRecords([cloudLedger]),
            scope: .privateDatabase,
            generation: 1,
            now: fixture.now
        )
        _ = await buffer.drain()
        let marker = try XCTUnwrap(
            store.pendingAmbiguousRemoteRemovalRevalidations().only
        )

        XCTAssertTrue(
            try store.discardAmbiguousOwnerDeletionLedgerAbsence(marker)
        )

        XCTAssertTrue(store.hasPersistedBinding(for: fixture.profileID))
        XCTAssertEqual(store.binding(for: fixture.profileID), originalBinding)
        XCTAssertTrue(
            try store.pendingAmbiguousRemoteRemovalRevalidations().isEmpty
        )
    }

    func testUnknownOwnerLedgerExistingProofKeepsBindingAndStagesRecoveryAcrossRestart()
        async throws
    {
        let fixture = try AccountBoundaryEvidenceFixture(
            name: "unknown-owner-ledger-exists"
        )
        defer { fixture.remove() }
        let store = fixture.store()
        XCTAssertEqual(
            try store.confirm(
                accountRecordName: AccountBoundaryEvidenceFixture.originAccount
            ),
            .signedIn
        )
        let cloudLedger = try fixture.ownerDeletionLedgerCloudRecord
        let buffer = CloudKitFamilySyncEventBuffer(
            metadataStore: store,
            liveAccountVerifier: CloudKitLiveAccountVerifier { _ in
                throw CloudKitFamilySyncError.accountBindingMismatch
            }
        )

        await buffer.handle(
            .fetchedRecords([cloudLedger]),
            scope: .privateDatabase,
            generation: 1,
            now: fixture.now
        )
        _ = await buffer.drain()
        XCTAssertEqual(
            try store.confirm(
                accountRecordName: AccountBoundaryEvidenceFixture.replacementAccount
            ),
            .switchedAccounts
        )
        XCTAssertEqual(
            try store.confirm(
                accountRecordName: AccountBoundaryEvidenceFixture.originAccount
            ),
            .switchedAccounts
        )

        let returnedStore = fixture.store()
        let marker = try XCTUnwrap(
            returnedStore.pendingAmbiguousRemoteRemovalRevalidations().only
        )
        let receiptID = try returnedStore.promoteAmbiguousRemoteRemoval(
            markerID: marker.id,
            record: fixture.deletionRecord
        )

        XCTAssertTrue(returnedStore.hasPersistedBinding(for: fixture.profileID))
        XCTAssertEqual(
            returnedStore.binding(for: fixture.profileID).state,
            .privateOwner,
            "Ledger existence stages recovery; zone erasure still owns terminal commit"
        )
        XCTAssertEqual(
            returnedStore.inboxEntries().map(\.receiptID),
            [receiptID]
        )
        XCTAssertEqual(
            try returnedStore.pendingOwnerDeletionLedgerRecoveries().count,
            1
        )
        XCTAssertTrue(
            try returnedStore.pendingAmbiguousRemoteRemovalRevalidations().isEmpty
        )

        let finalRestart = fixture.store()
        XCTAssertTrue(finalRestart.hasPersistedBinding(for: fixture.profileID))
        XCTAssertEqual(finalRestart.inboxEntries().map(\.receiptID), [receiptID])
        XCTAssertEqual(
            try finalRestart.pendingOwnerDeletionLedgerRecoveries().count,
            1
        )
    }

    func testAtomicOwnerPreparationPublishesBindingAndMarkerAndPreservesProvisionalDedupe()
        throws
    {
        let fixture = try AccountBoundaryEvidenceFixture(
            name: "atomic-owner-binding-marker"
        )
        defer { fixture.remove() }
        let store = fixture.store()
        XCTAssertEqual(
            try store.confirm(
                accountRecordName: AccountBoundaryEvidenceFixture.originAccount
            ),
            .signedIn
        )

        let first =
            try store.prepareAndStageAmbiguousOwnerDeletionLedgerRecovery(
                profileID: fixture.profileID,
                zoneID: fixture.zoneID,
                rootRecordName: fixture.rootRecordID.recordName,
                receivedAt: fixture.now
            )

        XCTAssertTrue(first.provisionalBindingCreated)
        XCTAssertEqual(first.binding, store.binding(for: fixture.profileID))
        XCTAssertTrue(store.hasPersistedBinding(for: fixture.profileID))
        let firstMarker = try XCTUnwrap(
            store.pendingAmbiguousRemoteRemovalRevalidations().only
        )
        XCTAssertEqual(firstMarker.id, first.markerID)
        XCTAssertTrue(firstMarker.provisionalBindingCreated)

        let restarted = fixture.store()
        XCTAssertEqual(restarted.binding(for: fixture.profileID), first.binding)
        let restartedMarker = try XCTUnwrap(
            restarted.pendingAmbiguousRemoteRemovalRevalidations().only
        )
        XCTAssertEqual(restartedMarker.id, first.markerID)
        XCTAssertTrue(restartedMarker.provisionalBindingCreated)

        let redelivery =
            try restarted.prepareAndStageAmbiguousOwnerDeletionLedgerRecovery(
                profileID: fixture.profileID,
                zoneID: fixture.zoneID,
                rootRecordName: fixture.rootRecordID.recordName,
                receivedAt: fixture.now.addingTimeInterval(1)
            )

        XCTAssertEqual(redelivery.markerID, first.markerID)
        XCTAssertEqual(redelivery.binding, first.binding)
        XCTAssertTrue(
            redelivery.provisionalBindingCreated,
            "Redelivery must inherit durable creation provenance, not recompute false from the now-existing binding"
        )
        XCTAssertEqual(
            try restarted.pendingAmbiguousRemoteRemovalRevalidations().count,
            1
        )
        XCTAssertTrue(
            try XCTUnwrap(
                restarted.pendingAmbiguousRemoteRemovalRevalidations().only
            ).provisionalBindingCreated
        )
    }

    @MainActor
    func testDirectRevalidationRequiresOriginProofBothBeforeAndAfterFetch()
        async
    {
        for proof in [
            CloudKitRemoteRootRevalidationProof.exists,
            .rootMissing,
            .zoneMissing,
        ] {
            var events: [String] = []
            var verificationCount = 0

            do {
                _ = try await CloudKitAmbiguousRemoteRemovalRecoveryExecutor()
                    .resolve(
                        verifyOriginAccount: {
                            verificationCount += 1
                            events.append("verify-\(verificationCount)")
                            if verificationCount == 2 {
                                throw CloudKitFamilySyncError
                                    .accountBindingMismatch
                            }
                        },
                        fetchRootProof: {
                            events.append("fetch-direct-proof")
                            return proof
                        },
                        discardMarker: {
                            events.append("unexpected-discard")
                        },
                        recoverRootMissing: {
                            events.append("unexpected-root-recovery")
                        },
                        recoverZoneMissing: {
                            events.append("unexpected-zone-recovery")
                        }
                    )
                XCTFail("An account switch after fetch must block every mutation")
            } catch {
                guard
                    case .accountBindingMismatch =
                        error as? CloudKitFamilySyncError
                else {
                    return XCTFail("Expected the live account fence to fail")
                }
            }

            XCTAssertEqual(
                events,
                ["verify-1", "fetch-direct-proof", "verify-2"],
                "No proof result may mutate state after the origin account changes"
            )
        }
    }

    func testDirectRootFetchProofKeepsRootAndZoneAbsenceDistinct() throws {
        let fixture = try AccountBoundaryEvidenceFixture(
            name: "root-fetch-proof-classification"
        )
        defer { fixture.remove() }
        let existingRoot = CKRecord(
            recordType: CloudKitFamilyRecordCodec.Schema.rootRecordType,
            recordID: fixture.rootRecordID
        )

        XCTAssertEqual(
            try CloudKitRemoteRootFetchProof.proof(
                .success(existingRoot),
                scope: .privateDatabase,
                recordID: fixture.rootRecordID
            ),
            .exists
        )
        XCTAssertEqual(
            try CloudKitRemoteRootFetchProof.proof(
                .failure(accountBoundaryCloudError(.unknownItem)),
                scope: .privateDatabase,
                recordID: fixture.rootRecordID
            ),
            .rootMissing
        )
        XCTAssertEqual(
            try CloudKitRemoteRootFetchProof.proof(
                .failure(accountBoundaryCloudError(.zoneNotFound)),
                scope: .privateDatabase,
                recordID: fixture.rootRecordID
            ),
            .zoneMissing
        )
        XCTAssertEqual(
            try CloudKitRemoteRootFetchProof.proof(
                .failure(accountBoundaryCloudError(.permissionFailure)),
                scope: .sharedDatabase,
                recordID: fixture.rootRecordID
            ),
            .zoneMissing
        )
        XCTAssertThrowsError(
            try CloudKitRemoteRootFetchProof.proof(
                .failure(accountBoundaryCloudError(.permissionFailure)),
                scope: .privateDatabase,
                recordID: fixture.rootRecordID
            )
        )
        XCTAssertThrowsError(
            try CloudKitRemoteRootFetchProof.proof(
                nil,
                scope: .privateDatabase,
                recordID: fixture.rootRecordID
            )
        )
    }

    func testTerminalRootCommitClearsAllEvidenceMarkersAndKeepsOneReceipt()
        throws
    {
        let fixture = try AccountBoundaryEvidenceFixture(
            name: "multiple-marker-terminal-cleanup"
        )
        defer { fixture.remove() }
        let store = fixture.store()
        try fixture.configureOriginAccount(in: store)

        let ownerMarkerID = try fixture.stageAmbiguous(
            .ownerDeletionLedger,
            in: store
        )
        let rootMarkerID = try fixture.stageAmbiguous(
            .rootRecordDeletion,
            in: store
        )
        let zoneMarkerID = try fixture.stageAmbiguous(
            .zoneDeletion,
            in: store
        )
        XCTAssertEqual(
            try store.pendingAmbiguousRemoteRemovalRevalidations().count,
            3
        )

        _ = try store.promoteAmbiguousRemoteRemoval(
            markerID: ownerMarkerID,
            record: fixture.deletionRecord
        )
        let rootReceiptID = try store.promoteAmbiguousRemoteRemoval(
            markerID: rootMarkerID,
            record: fixture.deletionRecord
        )
        XCTAssertEqual(store.inboxEntries().count, 2)
        XCTAssertEqual(
            try store.pendingAmbiguousRemoteRemovalRevalidations().map(\.id),
            [zoneMarkerID]
        )

        let recovery = try XCTUnwrap(
            store.pendingRemoteRootRemovalRecoveries().only
        )
        XCTAssertEqual(
            try store.commitRemoteProfileRemoval(
                record: recovery.record,
                recordID: recovery.recordID,
                scope: recovery.scope,
                receivedAt: recovery.receivedAt,
                terminalEvidence: recovery.terminalEvidence
            ),
            rootReceiptID
        )

        let terminalEntries = store.inboxEntries()
        XCTAssertEqual(terminalEntries.map(\.receiptID), [rootReceiptID])
        XCTAssertEqual(terminalEntries.first?.terminalEvidence, .rootRecordDeletion)
        XCTAssertEqual(store.binding(for: fixture.profileID).state, .ownerDeleted)
        XCTAssertTrue(
            try store.pendingAmbiguousRemoteRemovalRevalidations().isEmpty
        )
        XCTAssertTrue(try store.pendingOwnerDeletionLedgerRecoveries().isEmpty)
        XCTAssertTrue(try store.pendingRemoteRootRemovalRecoveries().isEmpty)
        XCTAssertTrue(try store.pendingRemoteZoneRemovalRecoveries().isEmpty)

        let persisted = try String(
            contentsOf: fixture.metadataURL,
            encoding: .utf8
        )
        for markerID in [ownerMarkerID, rootMarkerID, zoneMarkerID] {
            XCTAssertFalse(
                persisted.contains(markerID.uuidString),
                "Terminal commit must physically remove every stale marker"
            )
        }
    }

    @MainActor
    func testVerifiedRootDeletionDoesNotPromoteDormantZoneMarkerAfterAccountRoundTrip()
        async throws
    {
        let fixture = try AccountBoundaryEvidenceFixture(
            name: "root-does-not-reuse-zone-marker"
        )
        defer { fixture.remove() }
        let originStore = fixture.store()
        try fixture.configureOriginAccount(in: originStore)

        let dormantZoneMarkerID = try fixture.stageAmbiguous(
            .zoneDeletion,
            in: originStore
        )
        XCTAssertEqual(
            try originStore.confirm(
                accountRecordName: AccountBoundaryEvidenceFixture.replacementAccount
            ),
            .switchedAccounts
        )
        XCTAssertTrue(
            try originStore.pendingAmbiguousRemoteRemovalRevalidations().isEmpty,
            "Origin-account evidence must remain dormant under a foreign account"
        )

        XCTAssertEqual(
            try originStore.confirm(
                accountRecordName: AccountBoundaryEvidenceFixture.originAccount
            ),
            .switchedAccounts
        )
        let returnedStore = fixture.store()
        XCTAssertEqual(
            try returnedStore.pendingAmbiguousRemoteRemovalRevalidations().map(\.id),
            [dormantZoneMarkerID]
        )

        let buffer = CloudKitFamilySyncEventBuffer(
            metadataStore: returnedStore,
            liveAccountVerifier: .noOp
        )
        await buffer.handle(
            .fetchedDeletions([fixture.rootRecordID]),
            scope: .privateDatabase,
            generation: 1,
            now: fixture.now.addingTimeInterval(1)
        )
        let result = await buffer.drain()

        XCTAssertNil(result.accountChange)
        XCTAssertTrue(result.records.isEmpty)
        XCTAssertTrue(result.receiptIDs.isEmpty)
        XCTAssertTrue(result.requiresFetchPass)
        let rootRecoveries =
            try returnedStore.pendingRemoteRootRemovalRecoveries()
        XCTAssertEqual(
            rootRecoveries.count,
            1,
            "Verified root deletion must stage root recovery, not reuse old zone evidence"
        )
        XCTAssertTrue(
            try returnedStore.pendingRemoteZoneRemovalRecoveries().isEmpty,
            "The dormant zone observation was never independently verified"
        )
        XCTAssertEqual(
            try returnedStore.pendingAmbiguousRemoteRemovalRevalidations().map(\.id),
            [dormantZoneMarkerID],
            "Root proof must not consume or promote the older zone marker"
        )

        let recovery = try XCTUnwrap(rootRecoveries.only)
        var events: [String] = []
        _ = try await CloudKitOwnerDeletionRecoveryExecutor().recover(
            verifyOriginAccount: {
                events.append("verify-origin")
            },
            persistLedger: {
                events.append("persist-ledger")
            },
            eraseZone: {
                events.append("erase-whole-zone")
            },
            purgeLocalSources: {
                events.append("purge-local-sources")
            },
            commitRecovery: {
                events.append("commit-root-recovery")
                return try XCTUnwrap(
                    returnedStore.commitRemoteProfileRemoval(
                        record: recovery.record,
                        recordID: recovery.recordID,
                        scope: recovery.scope,
                        receivedAt: recovery.receivedAt,
                        terminalEvidence: recovery.terminalEvidence
                    )
                )
            }
        )

        XCTAssertEqual(
            events,
            [
                "verify-origin",
                "persist-ledger",
                "verify-origin",
                "verify-origin",
                "erase-whole-zone",
                "verify-origin",
                "purge-local-sources",
                "verify-origin",
                "commit-root-recovery",
            ]
        )
        XCTAssertEqual(
            returnedStore.binding(for: fixture.profileID).state,
            .ownerDeleted
        )
        XCTAssertTrue(
            try returnedStore.pendingAmbiguousRemoteRemovalRevalidations().isEmpty,
            "Terminal root recovery must clear stale ambiguous observations"
        )
    }

    func testDuplicateOwnerLedgerAfterOwnerTerminalIsIgnored() async throws {
        let fixture = try AccountBoundaryEvidenceFixture(
            name: "duplicate-owner-ledger-after-terminal"
        )
        defer { fixture.remove() }
        let store = fixture.store()
        try fixture.configureOriginAccount(in: store)
        try store.markOwnerDeleted(profileID: fixture.profileID)
        let terminalBinding = store.binding(for: fixture.profileID)
        let buffer = CloudKitFamilySyncEventBuffer(metadataStore: store)

        await buffer.handle(
            .fetchedRecords([try fixture.ownerDeletionLedgerCloudRecord]),
            scope: .privateDatabase,
            generation: 1,
            now: fixture.now
        )
        let result = await buffer.drain()

        XCTAssertNil(result.accountChange)
        XCTAssertTrue(result.failures.isEmpty)
        XCTAssertTrue(result.records.isEmpty)
        XCTAssertTrue(result.receiptIDs.isEmpty)
        XCTAssertEqual(store.binding(for: fixture.profileID), terminalBinding)
        XCTAssertTrue(
            try store.pendingAmbiguousRemoteRemovalRevalidations().isEmpty
        )
    }

    private func assertAllRecoveriesAreDormant(
        in store: CloudKitFamilyMetadataStore,
        file: StaticString = #filePath,
        line: UInt = #line
    ) throws {
        XCTAssertTrue(
            try store.pendingOwnerDeletionLedgerRecoveries().isEmpty,
            file: file,
            line: line
        )
        XCTAssertTrue(
            try store.pendingRemoteRootRemovalRecoveries().isEmpty,
            file: file,
            line: line
        )
        XCTAssertTrue(
            try store.pendingRemoteZoneRemovalRecoveries().isEmpty,
            file: file,
            line: line
        )
    }
}

private enum StagedEvidence: String, CaseIterable, CustomStringConvertible {
    case ownerLedger
    case root
    case zone

    var description: String { rawValue }
}

private enum ConfirmationBoundary: String, CaseIterable, CustomStringConvertible {
    case sameAccount
    case accountRoundTrip

    var description: String { rawValue }
}

private enum AmbiguousResolution: String, CaseIterable, CustomStringConvertible {
    case cloudObjectStillExists
    case cloudDeletionConfirmed

    var description: String { rawValue }
}

private enum ControlLedgerProof: String, CaseIterable, CustomStringConvertible {
    case controlRecordExists
    case controlRecordAbsent

    var description: String { rawValue }
}

private actor AccountBoundaryVerifierGate {
    private enum Resolution: Equatable {
        case success
        case accountMismatch
    }

    private var started = false
    private var startWaiters: [CheckedContinuation<Void, Never>] = []
    private var verification: CheckedContinuation<Void, Error>?
    private var resolution: Resolution?

    func verify() async throws {
        if let resolution {
            if resolution == .accountMismatch {
                throw CloudKitFamilySyncError.accountBindingMismatch
            }
            return
        }
        started = true
        let waiters = startWaiters
        startWaiters.removeAll()
        for waiter in waiters { waiter.resume() }
        try await withCheckedThrowingContinuation { continuation in
            verification = continuation
        }
    }

    func waitUntilStarted() async {
        guard !started else { return }
        await withCheckedContinuation { continuation in
            startWaiters.append(continuation)
        }
    }

    func succeed() {
        resolution = .success
        verification?.resume()
        verification = nil
    }

    func failWithAccountMismatch() {
        resolution = .accountMismatch
        verification?.resume(
            throwing: CloudKitFamilySyncError.accountBindingMismatch
        )
        verification = nil
    }
}

private struct AccountBoundaryEvidenceFixture {
    static let originAccount = "account-boundary-origin"
    static let replacementAccount = "account-boundary-replacement"

    let directory: URL
    let metadataURL: URL
    let profileID = ProfileID()
    let now = Date(timeIntervalSince1970: 12_345)

    init(name: String) throws {
        directory = FileManager.default.temporaryDirectory.appendingPathComponent(
            "TadaWords-AccountBoundary-\(name)-\(UUID().uuidString)",
            isDirectory: true
        )
        try FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true
        )
        metadataURL = directory.appendingPathComponent("cloud-metadata.json")
    }

    var zoneID: CKRecordZone.ID {
        CKRecordZone.ID(
            zoneName: "TadaProfile-\(profileID.rawValue.uuidString)",
            ownerName: CKCurrentUserDefaultName
        )
    }

    var rootRecordID: CKRecord.ID {
        CKRecord.ID(
            recordName: "profile-root-\(profileID.rawValue.uuidString)",
            zoneID: zoneID
        )
    }

    var childRecordID: CKRecord.ID {
        CKRecord.ID(recordName: "private-child-\(profileID)", zoneID: zoneID)
    }

    var ownerDeletionLedgerCloudRecord: CKRecord {
        get throws {
            try CloudKitFamilyDeletionLedgerCodec.cloudRecord(
                for: deletionRecord
            )
        }
    }

    var rootCloudRecord: CKRecord {
        let root = CKRecord(
            recordType: CloudKitFamilyRecordCodec.Schema.rootRecordType,
            recordID: rootRecordID
        )
        root[CloudKitFamilyRecordCodec.Schema.profileID] =
            profileID.rawValue.uuidString as NSString
        return root
    }

    var deletionRecord: FamilySyncRecord {
        get throws {
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .secondsSince1970
            encoder.outputFormatting = [.sortedKeys]
            return FamilySyncRecord(
                recordName: "profile-\(profileID)",
                profileID: profileID,
                kind: .profileDeletion,
                payload: try encoder.encode(
                    ProfileDeletionTombstone(
                        profileID: profileID,
                        deletedAt: Date(timeIntervalSince1970: 0)
                    )
                ),
                updatedAt: Date(timeIntervalSince1970: 0),
                deviceID: "account-boundary-terminal",
                isDeleted: true,
                logicalRevision: FamilySyncLogicalRevision(
                    counter: 7,
                    deviceID: "account-boundary-terminal"
                )
            )
        }
    }

    func store() -> CloudKitFamilyMetadataStore {
        CloudKitFamilyMetadataStore(snapshotURL: metadataURL)
    }

    func configureOriginAccount(
        in store: CloudKitFamilyMetadataStore
    ) throws {
        XCTAssertEqual(
            try store.confirm(accountRecordName: Self.originAccount),
            .signedIn
        )
        try store.save(
            binding: ProfileCloudBinding(
                profileID: profileID,
                state: .privateOwner,
                zoneName: zoneID.zoneName,
                ownerName: zoneID.ownerName,
                rootRecordName: rootRecordID.recordName
            )
        )
    }

    func configureUnrelatedOriginBinding(
        in store: CloudKitFamilyMetadataStore
    ) throws -> ProfileCloudBinding {
        let unrelatedProfileID = ProfileID()
        let unrelatedZoneID = CKRecordZone.ID(
            zoneName: "TadaProfile-\(unrelatedProfileID.rawValue.uuidString)",
            ownerName: CKCurrentUserDefaultName
        )
        let binding = ProfileCloudBinding(
            profileID: unrelatedProfileID,
            state: .privateOwner,
            zoneName: unrelatedZoneID.zoneName,
            ownerName: unrelatedZoneID.ownerName,
            rootRecordName:
                "profile-root-\(unrelatedProfileID.rawValue.uuidString)"
        )
        try store.save(binding: binding)
        return store.binding(for: unrelatedProfileID)
    }

    func stage(
        _ evidence: StagedEvidence,
        in store: CloudKitFamilyMetadataStore
    ) throws -> UUID {
        let record = try deletionRecord
        switch evidence {
        case .ownerLedger:
            return try store.appendInbox(
                record: record,
                recordID: CloudKitFamilyDeletionLedgerCodec.recordID(
                    for: profileID
                ),
                scope: .privateDatabase,
                receivedAt: now,
                terminalEvidence: .ownerDeletionLedger
            )
        case .root:
            return try store.stageRemoteRootProfileRemoval(
                record: record,
                recordID: rootRecordID,
                scope: .privateDatabase,
                receivedAt: now
            )
        case .zone:
            return try store.stageRemoteZoneProfileRemoval(
                record: record,
                recordID: rootRecordID,
                scope: .privateDatabase,
                receivedAt: now
            )
        }
    }

    func stageAmbiguous(
        _ evidence: CloudKitAmbiguousRemoteRemovalEvidence,
        in store: CloudKitFamilyMetadataStore
    ) throws -> UUID {
        try store.stageAmbiguousRemoteRemoval(
            profileID: profileID,
            recordID: rootRecordID,
            scope: .privateDatabase,
            evidence: evidence,
            receivedAt: now
        )
    }

    func pendingCount(
        for evidence: StagedEvidence,
        in store: CloudKitFamilyMetadataStore
    ) throws -> Int {
        switch evidence {
        case .ownerLedger:
            try store.pendingOwnerDeletionLedgerRecoveries().count
        case .root:
            try store.pendingRemoteRootRemovalRecoveries().count
        case .zone:
            try store.pendingRemoteZoneRemovalRecoveries().count
        }
    }

    func commit(
        _ evidence: StagedEvidence,
        in store: CloudKitFamilyMetadataStore
    ) throws -> UUID? {
        switch evidence {
        case .ownerLedger:
            let recovery = try XCTUnwrap(
                store.pendingOwnerDeletionLedgerRecoveries().only
            )
            return try store.commitOwnerDeletionLedgerRecovery(
                record: recovery.record,
                recordID: recovery.recordID,
                previous: recovery.binding,
                receivedAt: recovery.receivedAt
            )
        case .root:
            let recovery = try XCTUnwrap(
                store.pendingRemoteRootRemovalRecoveries().only
            )
            return try store.commitRemoteProfileRemoval(
                record: recovery.record,
                recordID: recovery.recordID,
                scope: recovery.scope,
                receivedAt: recovery.receivedAt,
                terminalEvidence: .rootRecordDeletion
            )
        case .zone:
            let recovery = try XCTUnwrap(
                store.pendingRemoteZoneRemovalRecoveries().only
            )
            return try store.commitRemoteProfileRemoval(
                record: recovery.record,
                recordID: recovery.recordID,
                scope: recovery.scope,
                receivedAt: recovery.receivedAt,
                terminalEvidence: .zoneDeletion
            )
        }
    }

    func childRecord() -> FamilySyncRecord {
        FamilySyncRecord(
            recordName: childRecordID.recordName,
            profileID: profileID,
            kind: .wordPoolEntry,
            payload: Data("ACCOUNT_BOUNDARY_CHILD_PAYLOAD".utf8),
            updatedAt: now,
            deviceID: "account-boundary-child"
        )
    }

    func cloudRecord(
        for record: FamilySyncRecord,
        in store: CloudKitFamilyMetadataStore
    ) throws -> CKRecord {
        try CloudKitFamilyRecordCodec.cloudRecord(
            for: record,
            recordID: CKRecord.ID(
                recordName: record.recordName,
                zoneID: zoneID
            ),
            rootRecordID: rootRecordID,
            scope: .privateDatabase,
            metadataStore: store
        )
    }

    func remove() {
        try? FileManager.default.removeItem(at: directory)
    }
}

extension Collection {
    fileprivate var only: Element? {
        count == 1 ? first : nil
    }
}

private func accountBoundaryCloudError(_ code: CKError.Code) -> CKError {
    CKError(
        _nsError: NSError(
            domain: CKErrorDomain,
            code: code.rawValue
        )
    )
}
