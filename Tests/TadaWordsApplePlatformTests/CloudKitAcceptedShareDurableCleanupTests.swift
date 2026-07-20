@preconcurrency import CloudKit
import Foundation
import TadaWordsDomain
import XCTest

@testable import TadaWordsApplePlatform

final class CloudKitAcceptedShareDurableCleanupTests: XCTestCase {
    func testDeterministicRootIdentityIsProvedBeforeAcceptance() throws {
        let fixture = try AcceptedShareCleanupFixture(name: "root-proof")
        defer { fixture.remove() }

        XCTAssertEqual(
            try CloudKitAcceptedShareRootProof.profileID(
                from: fixture.rootRecordID
            ),
            fixture.profileID
        )

        let wrongZoneRoot = CKRecord.ID(
            recordName: fixture.rootRecordID.recordName,
            zoneID: CKRecordZone.ID(
                zoneName: "TadaProfile-\(ProfileID().rawValue.uuidString)",
                ownerName: fixture.rootRecordID.zoneID.ownerName
            )
        )
        XCTAssertThrowsError(
            try CloudKitAcceptedShareRootProof.profileID(from: wrongZoneRoot)
        )
    }

    func testAcceptedRootPayloadMustMatchPreAcceptedDeterministicIdentity()
        throws
    {
        let fixture = try AcceptedShareCleanupFixture(name: "root-payload")
        defer { fixture.remove() }
        let root = fixture.rootRecord(profileID: fixture.profileID)

        XCTAssertNoThrow(
            try CloudKitAcceptedShareRootProof.validate(
                root,
                expectedRootRecordID: fixture.rootRecordID,
                expectedShareRecordID: nil,
                profileID: fixture.profileID
            )
        )

        root[CloudKitFamilyRecordCodec.Schema.profileID] =
            ProfileID().rawValue.uuidString as NSString
        XCTAssertThrowsError(
            try CloudKitAcceptedShareRootProof.validate(
                root,
                expectedRootRecordID: fixture.rootRecordID,
                expectedShareRecordID: nil,
                profileID: fixture.profileID
            )
        )
    }

    func testCrashWindowRestoresMarkerThenAtomicCommitPublishesOnlyBinding()
        throws
    {
        let fixture = try AcceptedShareCleanupFixture(name: "atomic-commit")
        defer { fixture.remove() }
        let store = try fixture.originStore()
        let marker = try fixture.stage(in: store)

        let afterStage = fixture.store()
        XCTAssertEqual(
            try afterStage.pendingAcceptedShareCleanups(),
            [marker]
        )
        XCTAssertFalse(afterStage.hasPersistedBinding(for: fixture.profileID))

        let materialized = try fixture.materialize(marker, in: afterStage)
        try afterStage.commitAcceptedShareBinding(
            materialized.binding,
            clearing: materialized
        )

        let afterCommit = fixture.store()
        XCTAssertEqual(
            afterCommit.binding(for: fixture.profileID),
            materialized.binding
        )
        XCTAssertTrue(try afterCommit.pendingAcceptedShareCleanups().isEmpty)
    }

    func testPreparedCrashClearsWithoutAnyRemoteLeave()
        async throws
    {
        let fixture = try AcceptedShareCleanupFixture(name: "compensated")
        defer { fixture.remove() }
        let store = try fixture.originStore()
        let marker = try fixture.stage(in: store)
        var leaveCount = 0

        try await CloudKitAcceptedShareRecoveryExecutor().recover(
            marker: marker,
            verifyOriginAccount: {},
            completePrepared: { prepared in
                try store.completeAcceptedShareCleanup(
                    prepared,
                    proof: .preparedWithoutAcceptance
                )
            },
            materialize: { _ in
                XCTFail("Prepared marker must not query a remote root")
                throw AcceptedShareCleanupTestError.invalidRoot
            },
            deleteMaterializedShare: { _ in
                leaveCount += 1
            },
            completeMaterialized: { _ in
                XCTFail("Prepared marker has no materialized deletion")
            }
        )

        XCTAssertEqual(leaveCount, 0)
        XCTAssertFalse(store.isAcceptedShareCleanupPending(marker))
        XCTAssertFalse(store.hasPersistedBinding(for: fixture.profileID))
    }

    func testTransientLeaveFailureRetainsMarkerAcrossRestart() async throws {
        let fixture = try AcceptedShareCleanupFixture(name: "transient-leave")
        defer { fixture.remove() }
        let store = try fixture.originStore()
        let marker = try fixture.materialize(
            fixture.stage(in: store),
            in: store
        )

        do {
            try await CloudKitAcceptedShareRecoveryExecutor().recover(
                marker: marker,
                verifyOriginAccount: {},
                completePrepared: { _ in
                    XCTFail("Materialized marker is not prepared")
                },
                materialize: { _ in
                    XCTFail("Materialized marker must not refetch root")
                    throw AcceptedShareCleanupTestError.invalidRoot
                },
                deleteMaterializedShare: { _ in
                    throw AcceptedShareCleanupTestError.transientNetwork
                },
                completeMaterialized: { _ in
                    XCTFail("Transient leave is not absence proof")
                }
            )
            XCTFail("Expected transient leave failure")
        } catch AcceptedShareCleanupTestError.transientNetwork {
            // Expected.
        }

        let restarted = fixture.store()
        XCTAssertEqual(
            try restarted.pendingAcceptedShareCleanups(),
            [marker]
        )
        XCTAssertFalse(restarted.hasPersistedBinding(for: fixture.profileID))
    }

    func testAcceptedMarkerSurvivesDelayedZoneThenClearsAfterMaterialization()
        async throws
    {
        let fixture = try AcceptedShareCleanupFixture(name: "delayed-zone")
        defer { fixture.remove() }
        let store = try fixture.originStore()
        let prepared = try fixture.stage(in: store)
        let attempted = try store.advanceAcceptedShareCleanup(
            prepared,
            to: .acceptanceAttempted
        )
        let accepted = try store.advanceAcceptedShareCleanup(
            attempted,
            to: .accepted
        )
        var deleteCount = 0

        do {
            try await CloudKitAcceptedShareRecoveryExecutor().recover(
                marker: accepted,
                verifyOriginAccount: {},
                completePrepared: { _ in
                    XCTFail("Accepted marker is not prepared")
                },
                materialize: { _ in
                    throw AcceptedShareCleanupTestError.zoneNotFound
                },
                deleteMaterializedShare: { _ in
                    deleteCount += 1
                },
                completeMaterialized: { _ in
                    XCTFail("Unavailable zone is not deletion proof")
                }
            )
            XCTFail("Expected delayed zone materialization")
        } catch AcceptedShareCleanupTestError.zoneNotFound {
            // Expected.
        }

        let afterDelay = try XCTUnwrap(
            store.pendingAcceptedShareCleanups().first
        )
        XCTAssertEqual(afterDelay.effectivePhase, .accepted)
        XCTAssertEqual(deleteCount, 0)

        try await CloudKitAcceptedShareRecoveryExecutor().recover(
            marker: afterDelay,
            verifyOriginAccount: {},
            completePrepared: { _ in
                XCTFail("Accepted marker is not prepared")
            },
            materialize: { pending in
                try store.advanceAcceptedShareCleanup(
                    pending,
                    to: .materialized,
                    shareRecordID: fixture.shareRecordID
                )
            },
            deleteMaterializedShare: { materialized in
                XCTAssertEqual(materialized.effectivePhase, .materialized)
                deleteCount += 1
            },
            completeMaterialized: { materialized in
                try store.completeAcceptedShareCleanup(
                    materialized,
                    proof: .materializedShareDeletion
                )
            }
        )
        XCTAssertEqual(deleteCount, 1)
        XCTAssertTrue(try store.pendingAcceptedShareCleanups().isEmpty)
    }

    func testAmbiguousAcceptanceErrorRetainsAttemptedMarkerWhenZoneIsAbsent()
        async throws
    {
        let fixture = try AcceptedShareCleanupFixture(name: "ambiguous-accept")
        defer { fixture.remove() }
        let store = try fixture.originStore()
        let attempted = try store.advanceAcceptedShareCleanup(
            fixture.stage(in: store),
            to: .acceptanceAttempted
        )
        var deleteCount = 0

        do {
            _ = try await CloudKitAcceptedShareTransactionExecutor()
                .acceptAndCommit(
                    markerIsPending: {
                        store.isAcceptedShareCleanupPending(attempted)
                    },
                    acceptAndValidate: {
                        throw AcceptedShareCleanupTestError.ambiguousAcceptance
                    },
                    commit: { (_: Int) in
                        XCTFail("Ambiguous acceptance cannot commit")
                    },
                    compensate: {
                        try await CloudKitAcceptedShareRecoveryExecutor().recover(
                            marker: attempted,
                            verifyOriginAccount: {},
                            completePrepared: { _ in
                                XCTFail("Attempted marker is not prepared")
                            },
                            materialize: { _ in
                                throw AcceptedShareCleanupTestError.zoneNotFound
                            },
                            deleteMaterializedShare: { _ in
                                deleteCount += 1
                            },
                            completeMaterialized: { _ in
                                XCTFail("Absent residual zone is ambiguous")
                            }
                        )
                    }
                )
            XCTFail("Expected ambiguous outer acceptance error")
        } catch AcceptedShareCleanupTestError.ambiguousAcceptance {
            // The transaction preserves its original external error.
        }

        let restarted = fixture.store()
        let retained = try XCTUnwrap(
            restarted.pendingAcceptedShareCleanups().first
        )
        XCTAssertEqual(retained.effectivePhase, .acceptanceAttempted)
        XCTAssertEqual(deleteCount, 0)
    }

    func testExplicitPerShareFailureCanClearAttemptedMarker() throws {
        let fixture = try AcceptedShareCleanupFixture(name: "explicit-failure")
        defer { fixture.remove() }
        let store = try fixture.originStore()
        let prepared = try fixture.stage(in: store)
        let attempted = try store.advanceAcceptedShareCleanup(
            prepared,
            to: .acceptanceAttempted
        )

        XCTAssertTrue(
            CloudKitAcceptedShareFailureProofPolicy
                .canClearAfterExplicitPerShareFailure(
                    initialMarker: prepared,
                    attemptedMarker: attempted
                )
        )
        if CloudKitAcceptedShareFailureProofPolicy
            .canClearAfterExplicitPerShareFailure(
                initialMarker: prepared,
                attemptedMarker: attempted
            )
        {
            try store.completeAcceptedShareCleanup(
                attempted,
                proof: .explicitAcceptanceFailure
            )
        }

        XCTAssertTrue(try store.pendingAcceptedShareCleanups().isEmpty)
        XCTAssertFalse(store.hasPersistedBinding(for: fixture.profileID))
    }

    func testAmbiguousAttemptRetryFailureRetainsThenExactShareCleanupClears()
        async throws
    {
        let fixture = try AcceptedShareCleanupFixture(
            name: "ambiguous-retry-failure"
        )
        defer { fixture.remove() }
        let store = try fixture.originStore()
        let ambiguous = try store.advanceAcceptedShareCleanup(
            fixture.stage(in: store),
            to: .acceptanceAttempted
        )

        do {
            _ = try await CloudKitAcceptedShareTransactionExecutor()
                .acceptAndCommit(
                    markerIsPending: {
                        store.isAcceptedShareCleanupPending(ambiguous)
                    },
                    acceptAndValidate: {
                        throw AcceptedShareCleanupTestError.ambiguousAcceptance
                    },
                    commit: { (_: Int) in
                        XCTFail("Ambiguous acceptance cannot commit")
                    },
                    compensate: {
                        throw AcceptedShareCleanupTestError.zoneNotFound
                    }
                )
            XCTFail("Expected ambiguous outer acceptance error")
        } catch AcceptedShareCleanupTestError.ambiguousAcceptance {
            // The first request may have committed remotely.
        }

        let retainedAfterAmbiguity = try XCTUnwrap(
            fixture.store().pendingAcceptedShareCleanups().first
        )
        XCTAssertFalse(
            CloudKitAcceptedShareFailureProofPolicy
                .canClearAfterExplicitPerShareFailure(
                    initialMarker: retainedAfterAmbiguity,
                    attemptedMarker: retainedAfterAmbiguity
                )
        )
        // A per-item failure from the retry says nothing about whether the
        // earlier ambiguous request committed, so production leaves it alone.
        XCTAssertTrue(store.isAcceptedShareCleanupPending(retainedAfterAmbiguity))

        var deleteCount = 0
        try await CloudKitAcceptedShareRecoveryExecutor().recover(
            marker: retainedAfterAmbiguity,
            verifyOriginAccount: {},
            completePrepared: { _ in
                XCTFail("Ambiguous marker is not prepared")
            },
            materialize: { pending in
                let root = fixture.rootRecord(profileID: fixture.profileID)
                _ = CKShare(
                    rootRecord: root,
                    shareID: fixture.shareRecordID
                )
                try CloudKitAcceptedShareRootProof.validate(
                    root,
                    expectedRootRecordID: fixture.rootRecordID,
                    expectedShareRecordID: fixture.shareRecordID,
                    profileID: fixture.profileID
                )
                return try store.advanceAcceptedShareCleanup(
                    pending,
                    to: .materialized,
                    shareRecordID: fixture.shareRecordID
                )
            },
            deleteMaterializedShare: { materialized in
                XCTAssertEqual(
                    materialized.shareRecordID,
                    fixture.shareRecordID
                )
                deleteCount += 1
            },
            completeMaterialized: { materialized in
                try store.completeAcceptedShareCleanup(
                    materialized,
                    proof: .materializedShareDeletion
                )
            }
        )

        XCTAssertEqual(deleteCount, 1)
        XCTAssertTrue(try store.pendingAcceptedShareCleanups().isEmpty)
        XCTAssertFalse(store.hasPersistedBinding(for: fixture.profileID))
    }

    func testForeignAccountKeepsMarkerDormantAndOriginReturnCanCleanIt()
        async throws
    {
        let fixture = try AcceptedShareCleanupFixture(name: "account-roundtrip")
        defer { fixture.remove() }
        let store = try fixture.originStore()
        let marker = try fixture.stage(in: store)

        XCTAssertEqual(
            try store.confirm(accountRecordName: fixture.foreignAccount),
            .switchedAccounts
        )
        XCTAssertTrue(try store.pendingAcceptedShareCleanups().isEmpty)
        XCTAssertThrowsError(
            try store.completeAcceptedShareCleanup(
                marker,
                proof: .preparedWithoutAcceptance
            )
        ) { error in
            XCTAssertEqual(
                error as? CloudKitFamilyPersistenceError,
                .accountBindingMismatch
            )
        }
        XCTAssertTrue(store.isAcceptedShareCleanupPending(marker))

        XCTAssertEqual(
            try store.confirm(accountRecordName: fixture.originAccount),
            .switchedAccounts
        )
        XCTAssertEqual(try store.pendingAcceptedShareCleanups(), [marker])
        try await CloudKitAcceptedShareRecoveryExecutor().recover(
            marker: marker,
            verifyOriginAccount: {},
            completePrepared: { prepared in
                try store.completeAcceptedShareCleanup(
                    prepared,
                    proof: .preparedWithoutAcceptance
                )
            },
            materialize: { _ in
                throw AcceptedShareCleanupTestError.invalidRoot
            },
            deleteMaterializedShare: { _ in },
            completeMaterialized: { _ in }
        )
        XCTAssertTrue(try store.pendingAcceptedShareCleanups().isEmpty)
    }

    func testForeignMarkerBlocksPrivateRouteBeforeAnyRemoteSideEffect()
        async throws
    {
        let fixture = try AcceptedShareCleanupFixture(name: "foreign-preflight")
        defer { fixture.remove() }
        let store = try fixture.originStore()
        let marker = try fixture.materialize(
            fixture.stage(in: store),
            in: store
        )
        XCTAssertEqual(
            try store.confirm(accountRecordName: fixture.foreignAccount),
            .switchedAccounts
        )
        XCTAssertTrue(try store.pendingAcceptedShareCleanups().isEmpty)
        var remoteCreationCount = 0

        do {
            _ = try await CloudKitPrivateRoutePreparationExecutor().prepare(
                preflight: {
                    try store.ensurePrivateRoutePreparationAllowed(
                        for: fixture.profileID
                    )
                },
                createRemoteRoute: {
                    remoteCreationCount += 1
                },
                commitLocalRoute: {
                    XCTFail("Dormant reservation must block local commit")
                    return marker.binding
                }
            )
            XCTFail("Expected dormant accepted-share reservation conflict")
        } catch CloudKitFamilyPersistenceError.bindingConflict {
            // Expected.
        }

        XCTAssertEqual(remoteCreationCount, 0)
        XCTAssertTrue(store.isAcceptedShareCleanupPending(marker))
        XCTAssertFalse(store.hasPersistedBinding(for: fixture.profileID))
    }

    func testAcceptClaimedMarkerPreventsEitherEngineFetchFromAdvancing()
        throws
    {
        let fixture = try AcceptedShareCleanupFixture(name: "accept-first-fence")
        defer { fixture.remove() }
        let store = try fixture.originStore()
        let marker = try fixture.stage(in: store)
        var fence = CloudKitAcceptedShareOperationFence()
        XCTAssertTrue(fence.claimCleanup(marker))
        XCTAssertTrue(fence.claimEngineFetch())
        var privateFetchCount = 0
        var sharedFetchCount = 0

        let remainingMarkers = try store.pendingAcceptedShareCleanups()
        if CloudKitAcceptedShareFetchFence.allowsEngineProgress(
            pendingMarkerCount: remainingMarkers.count
        ) {
            privateFetchCount += 1
            sharedFetchCount += 1
        }

        XCTAssertEqual(privateFetchCount, 0)
        XCTAssertEqual(sharedFetchCount, 0)
        XCTAssertTrue(store.isAcceptedShareCleanupPending(marker))
    }

    func testFetchClaimedWindowPreventsAcceptanceStageAndExternalCall() throws {
        let fixture = try AcceptedShareCleanupFixture(name: "fetch-first-fence")
        defer { fixture.remove() }
        let store = try fixture.originStore()
        var fence = CloudKitAcceptedShareOperationFence()
        XCTAssertTrue(fence.claimEngineFetch())
        var stageCount = 0
        var externalAcceptCount = 0

        if fence.acceptanceCanStage {
            stageCount += 1
            _ = try fixture.stage(in: store)
            externalAcceptCount += 1
        }

        XCTAssertEqual(stageCount, 0)
        XCTAssertEqual(externalAcceptCount, 0)
        XCTAssertTrue(try store.pendingAcceptedShareCleanups().isEmpty)
        XCTAssertFalse(store.hasPersistedBinding(for: fixture.profileID))
    }

    func testDoubleCompletionIsIdempotentAndNeverCompensatesValidBinding()
        async throws
    {
        let fixture = try AcceptedShareCleanupFixture(name: "double-complete")
        defer { fixture.remove() }
        let store = try fixture.originStore()
        let marker = try fixture.materialize(
            fixture.stage(in: store),
            in: store
        )
        var compensationCount = 0

        try store.commitAcceptedShareBinding(marker.binding, clearing: marker)
        XCTAssertNoThrow(
            try store.commitAcceptedShareBinding(marker.binding, clearing: marker)
        )

        do {
            _ = try await CloudKitAcceptedShareTransactionExecutor()
                .acceptAndCommit(
                    markerIsPending: {
                        store.isAcceptedShareCleanupPending(marker)
                    },
                    acceptAndValidate: {
                        throw AcceptedShareCleanupTestError.invalidRoot
                    },
                    commit: { (_: Int) in
                        XCTFail("Second invalid completion must not commit")
                    },
                    compensate: {
                        compensationCount += 1
                    }
                )
            XCTFail("Expected second-path validation failure")
        } catch AcceptedShareCleanupTestError.invalidRoot {
            // Expected.
        }

        XCTAssertEqual(compensationCount, 0)
        XCTAssertEqual(store.binding(for: fixture.profileID), marker.binding)
        XCTAssertTrue(try store.pendingAcceptedShareCleanups().isEmpty)
    }

    func testRepeatedPreparationReusesMarkerThenRecognizesCommittedBinding()
        throws
    {
        let fixture = try AcceptedShareCleanupFixture(name: "repeat-prepare")
        defer { fixture.remove() }
        let store = try fixture.originStore()
        let first = try store.prepareAcceptedShareCleanup(
            profileID: fixture.profileID,
            rootRecordID: fixture.rootRecordID,
            shareRecordID: fixture.shareRecordID,
            originAccountRecordName: fixture.originAccount,
            stagedAt: fixture.now
        )
        let marker = try fixture.marker(from: first, expectedCreated: true)
        let second = try store.prepareAcceptedShareCleanup(
            profileID: fixture.profileID,
            rootRecordID: fixture.rootRecordID,
            shareRecordID: fixture.shareRecordID,
            originAccountRecordName: fixture.originAccount,
            stagedAt: fixture.now.addingTimeInterval(60)
        )
        XCTAssertEqual(
            try fixture.marker(from: second, expectedCreated: false),
            marker
        )

        let materialized = try fixture.materialize(marker, in: store)
        try store.commitAcceptedShareBinding(
            materialized.binding,
            clearing: materialized
        )
        let third = try store.prepareAcceptedShareCleanup(
            profileID: fixture.profileID,
            rootRecordID: fixture.rootRecordID,
            shareRecordID: fixture.shareRecordID,
            originAccountRecordName: fixture.originAccount
        )
        guard case .alreadyCommitted(let binding) = third.state else {
            return XCTFail("Expected exact committed route")
        }
        XCTAssertEqual(binding, marker.binding)
    }

    func testPendingMarkerBlocksPrivateBindingFallback() throws {
        let fixture = try AcceptedShareCleanupFixture(name: "fallback-block")
        defer { fixture.remove() }
        let store = try fixture.originStore()
        let marker = try fixture.stage(in: store)

        XCTAssertThrowsError(
            try store.save(
                binding: ProfileCloudBinding(
                    profileID: fixture.profileID,
                    state: .privateOwner,
                    zoneName: marker.zoneName,
                    ownerName: CKCurrentUserDefaultName,
                    rootRecordName: marker.rootRecordName
                )
            )
        ) { error in
            XCTAssertEqual(
                error as? CloudKitFamilyPersistenceError,
                .bindingConflict
            )
        }
        XCTAssertTrue(store.isAcceptedShareCleanupPending(marker))
    }

    func testMalformedMarkerRouteFailsClosedWithoutReplacingSnapshot() throws {
        let fixture = try AcceptedShareCleanupFixture(name: "invalid-marker")
        defer { fixture.remove() }
        let store = try fixture.originStore()
        _ = try fixture.stage(in: store)
        let corruptedBytes = try fixture.mutateSnapshot { snapshot in
            var markers = try XCTUnwrap(
                snapshot["pendingAcceptedShareCleanups"] as? [[String: Any]]
            )
            markers[0]["rootRecordName"] =
                CloudKitDeterministicProfileRoute.rootRecordName(
                    for: ProfileID()
                )
            snapshot["pendingAcceptedShareCleanups"] = markers
        }

        try fixture.assertCorruptSnapshotFailsClosed(
            originalBytes: corruptedBytes
        )
    }

    func testMarkerAndCommittedBindingCoexistenceFailsClosed() throws {
        let fixture = try AcceptedShareCleanupFixture(name: "marker-binding")
        defer { fixture.remove() }
        let store = try fixture.originStore()
        let marker = try fixture.stage(in: store)
        let encodedBinding = try JSONEncoder().encode(marker.binding)
        let bindingObject = try XCTUnwrap(
            JSONSerialization.jsonObject(with: encodedBinding)
                as? [String: Any]
        )
        let corruptedBytes = try fixture.mutateSnapshot { snapshot in
            snapshot["bindings"] = [bindingObject]
        }

        try fixture.assertCorruptSnapshotFailsClosed(
            originalBytes: corruptedBytes
        )
    }

    func testMaterializedMarkerWithoutExactShareRecordFailsClosed() throws {
        let fixture = try AcceptedShareCleanupFixture(name: "missing-share-id")
        defer { fixture.remove() }
        let store = try fixture.originStore()
        _ = try fixture.stage(in: store)
        let corruptedBytes = try fixture.mutateSnapshot { snapshot in
            var markers = try XCTUnwrap(
                snapshot["pendingAcceptedShareCleanups"] as? [[String: Any]]
            )
            markers[0]["phase"] =
                CloudKitAcceptedShareCleanupPhase.materialized.rawValue
            markers[0].removeValue(forKey: "shareRecordName")
            snapshot["pendingAcceptedShareCleanups"] = markers
        }

        try fixture.assertCorruptSnapshotFailsClosed(
            originalBytes: corruptedBytes
        )
    }

    func testLegacyPhaseLessMarkerLoadsAsAmbiguousAttemptedState() throws {
        let fixture = try AcceptedShareCleanupFixture(name: "legacy-marker")
        defer { fixture.remove() }
        let store = try fixture.originStore()
        _ = try fixture.stage(in: store)
        _ = try fixture.mutateSnapshot { snapshot in
            var markers = try XCTUnwrap(
                snapshot["pendingAcceptedShareCleanups"] as? [[String: Any]]
            )
            markers[0].removeValue(forKey: "phase")
            markers[0].removeValue(forKey: "shareRecordName")
            snapshot["pendingAcceptedShareCleanups"] = markers
        }

        let legacy = try XCTUnwrap(
            fixture.store().pendingAcceptedShareCleanups().first
        )
        XCTAssertEqual(legacy.effectivePhase, .acceptanceAttempted)
        XCTAssertNil(legacy.shareRecordID)
    }

    func testAcceptedSharePhaseCannotMoveBackward() throws {
        let fixture = try AcceptedShareCleanupFixture(name: "phase-regression")
        defer { fixture.remove() }
        let store = try fixture.originStore()
        let attempted = try store.advanceAcceptedShareCleanup(
            fixture.stage(in: store),
            to: .acceptanceAttempted
        )
        let accepted = try store.advanceAcceptedShareCleanup(
            attempted,
            to: .accepted
        )

        XCTAssertThrowsError(
            try store.advanceAcceptedShareCleanup(
                accepted,
                to: .acceptanceAttempted
            )
        ) { error in
            XCTAssertEqual(
                error as? CloudKitFamilyPersistenceError,
                .bindingConflict
            )
        }
        XCTAssertEqual(
            try store.pendingAcceptedShareCleanups().first?.effectivePhase,
            .accepted
        )
    }
}

private enum AcceptedShareCleanupTestError: Error {
    case invalidRoot
    case transientNetwork
    case zoneNotFound
    case ambiguousAcceptance
}

private struct AcceptedShareCleanupFixture {
    let directory: URL
    let metadataURL: URL
    let profileID = ProfileID()
    let originAccount = "accepted-share-origin"
    let foreignAccount = "accepted-share-foreign"
    let now = Date(timeIntervalSince1970: 2_222_222_222)

    init(name: String) throws {
        directory = FileManager.default.temporaryDirectory.appendingPathComponent(
            "TadaAcceptedShare-\(name)-\(UUID().uuidString)",
            isDirectory: true
        )
        try FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true
        )
        metadataURL = directory.appendingPathComponent("metadata.json")
    }

    var rootRecordID: CKRecord.ID {
        CKRecord.ID(
            recordName: CloudKitDeterministicProfileRoute.rootRecordName(
                for: profileID
            ),
            zoneID: CKRecordZone.ID(
                zoneName: CloudKitDeterministicProfileRoute.zoneName(
                    for: profileID
                ),
                ownerName: "remote-share-owner"
            )
        )
    }

    var shareRecordID: CKRecord.ID {
        CKRecord.ID(
            recordName: "accepted-share-\(profileID.rawValue.uuidString)",
            zoneID: rootRecordID.zoneID
        )
    }

    func store() -> CloudKitFamilyMetadataStore {
        CloudKitFamilyMetadataStore(snapshotURL: metadataURL)
    }

    func originStore() throws -> CloudKitFamilyMetadataStore {
        let store = store()
        XCTAssertEqual(
            try store.confirm(accountRecordName: originAccount),
            .signedIn
        )
        return store
    }

    func stage(
        in store: CloudKitFamilyMetadataStore
    ) throws -> CloudKitPendingAcceptedShareCleanup {
        try marker(
            from: store.prepareAcceptedShareCleanup(
                profileID: profileID,
                rootRecordID: rootRecordID,
                shareRecordID: shareRecordID,
                originAccountRecordName: originAccount,
                stagedAt: now
            ),
            expectedCreated: true
        )
    }

    func materialize(
        _ marker: CloudKitPendingAcceptedShareCleanup,
        in store: CloudKitFamilyMetadataStore
    ) throws -> CloudKitPendingAcceptedShareCleanup {
        let attempted = try store.advanceAcceptedShareCleanup(
            marker,
            to: .acceptanceAttempted
        )
        let accepted = try store.advanceAcceptedShareCleanup(
            attempted,
            to: .accepted
        )
        return try store.advanceAcceptedShareCleanup(
            accepted,
            to: .materialized,
            shareRecordID: shareRecordID
        )
    }

    func marker(
        from preparation: CloudKitPreparedAcceptedShareCleanup,
        expectedCreated: Bool
    ) throws -> CloudKitPendingAcceptedShareCleanup {
        guard
            case .staged(let marker, let wasCreated) = preparation.state
        else {
            throw AcceptedShareCleanupTestError.invalidRoot
        }
        XCTAssertEqual(wasCreated, expectedCreated)
        return marker
    }

    func rootRecord(profileID: ProfileID) -> CKRecord {
        let root = CKRecord(
            recordType: CloudKitFamilyRecordCodec.Schema.rootRecordType,
            recordID: rootRecordID
        )
        root[CloudKitFamilyRecordCodec.Schema.profileID] =
            profileID.rawValue.uuidString as NSString
        return root
    }

    func mutateSnapshot(
        _ mutation: (inout [String: Any]) throws -> Void
    ) throws -> Data {
        var snapshot = try XCTUnwrap(
            JSONSerialization.jsonObject(
                with: Data(contentsOf: metadataURL)
            ) as? [String: Any]
        )
        try mutation(&snapshot)
        let data = try JSONSerialization.data(
            withJSONObject: snapshot,
            options: [.prettyPrinted, .sortedKeys]
        )
        try data.write(to: metadataURL, options: .atomic)
        return data
    }

    func assertCorruptSnapshotFailsClosed(
        originalBytes: Data,
        file: StaticString = #filePath,
        line: UInt = #line
    ) throws {
        let corrupted = store()
        XCTAssertThrowsError(
            try corrupted.confirm(accountRecordName: originAccount),
            file: file,
            line: line
        ) { error in
            XCTAssertEqual(
                error as? CloudKitFamilyPersistenceError,
                .corruptMetadata,
                file: file,
                line: line
            )
        }
        XCTAssertEqual(
            try Data(contentsOf: metadataURL),
            originalBytes,
            file: file,
            line: line
        )
    }

    func remove() {
        try? FileManager.default.removeItem(at: directory)
    }
}
