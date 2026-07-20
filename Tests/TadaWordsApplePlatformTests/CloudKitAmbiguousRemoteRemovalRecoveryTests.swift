@preconcurrency import CloudKit
import Foundation
import TadaWordsDomain
import XCTest

@testable import TadaWordsApplePlatform

final class CloudKitAmbiguousRemoteRemovalRecoveryTests: XCTestCase {
    func testRootFetchProofClassifiesOnlyExplicitAbsence() throws {
        let zoneID = CKRecordZone.ID(
            zoneName: "proof-zone",
            ownerName: CKCurrentUserDefaultName
        )
        let recordID = CKRecord.ID(recordName: "root", zoneID: zoneID)
        let root = CKRecord(recordType: "Root", recordID: recordID)

        XCTAssertEqual(
            try CloudKitRemoteRootFetchProof.proof(
                .success(root),
                scope: .privateDatabase,
                recordID: recordID
            ),
            .exists
        )
        XCTAssertEqual(
            try CloudKitRemoteRootFetchProof.proof(
                .failure(cloudError(.unknownItem)),
                scope: .privateDatabase,
                recordID: recordID
            ),
            .rootMissing
        )
        XCTAssertEqual(
            try CloudKitRemoteRootFetchProof.proof(
                .failure(cloudError(.zoneNotFound)),
                scope: .privateDatabase,
                recordID: recordID
            ),
            .zoneMissing
        )
        XCTAssertEqual(
            try CloudKitRemoteRootFetchProof.proof(
                .failure(cloudError(.permissionFailure)),
                scope: .sharedDatabase,
                recordID: recordID
            ),
            .zoneMissing
        )
        XCTAssertThrowsError(
            try CloudKitRemoteRootFetchProof.proof(
                nil,
                scope: .privateDatabase,
                recordID: recordID
            )
        )
        XCTAssertThrowsError(
            try CloudKitRemoteRootFetchProof.proof(
                .failure(cloudError(.permissionFailure)),
                scope: .privateDatabase,
                recordID: recordID
            )
        )
        XCTAssertThrowsError(
            try CloudKitRemoteRootFetchProof.proof(
                .failure(cloudError(.networkFailure)),
                scope: .sharedDatabase,
                recordID: recordID
            )
        )
    }

    @MainActor
    func testRootExistsDiscardsWithoutRecovery() async throws {
        var events: [String] = []

        let terminal = try await CloudKitAmbiguousRemoteRemovalRecoveryExecutor()
            .resolve(
                verifyOriginAccount: { events.append("verify") },
                fetchRootProof: {
                    events.append("fetch")
                    return .exists
                },
                discardMarker: { events.append("discard") },
                recoverRootMissing: { events.append("unexpected-root") },
                recoverZoneMissing: { events.append("unexpected-zone") }
            )

        XCTAssertFalse(terminal)
        XCTAssertEqual(events, ["verify", "fetch", "verify", "discard"])
    }

    @MainActor
    func testRootAndZoneAbsenceUseDifferentRecoveryRoutes() async throws {
        for proof in [
            CloudKitRemoteRootRevalidationProof.rootMissing,
            .zoneMissing,
        ] {
            var events: [String] = []
            let terminal = try await CloudKitAmbiguousRemoteRemovalRecoveryExecutor().resolve(
                verifyOriginAccount: { events.append("verify") },
                fetchRootProof: {
                    events.append("fetch")
                    return proof
                },
                discardMarker: { events.append("unexpected-discard") },
                recoverRootMissing: { events.append("recover-root") },
                recoverZoneMissing: { events.append("recover-zone") }
            )

            XCTAssertTrue(terminal)
            XCTAssertEqual(
                events,
                [
                    "verify",
                    "fetch",
                    "verify",
                    proof == .rootMissing ? "recover-root" : "recover-zone",
                ]
            )
        }
    }

    @MainActor
    func testAccountSwitchAfterFetchStopsBeforeDiscardOrRecovery() async {
        var events: [String] = []
        var verificationCount = 0

        do {
            _ = try await CloudKitAmbiguousRemoteRemovalRecoveryExecutor()
                .resolve(
                    verifyOriginAccount: {
                        verificationCount += 1
                        events.append("verify-\(verificationCount)")
                        if verificationCount == 2 {
                            throw RecoveryTestError.account
                        }
                    },
                    fetchRootProof: {
                        events.append("fetch")
                        return .rootMissing
                    },
                    discardMarker: { events.append("unexpected-discard") },
                    recoverRootMissing: { events.append("unexpected-recover") },
                    recoverZoneMissing: { events.append("unexpected-zone") }
                )
            XCTFail("The second live-account fence must stop recovery")
        } catch {
            XCTAssertEqual(error as? RecoveryTestError, .account)
        }

        XCTAssertEqual(events, ["verify-1", "fetch", "verify-2"])
    }

    @MainActor
    func testOwnerRecoveryFencesEveryDestructiveBoundary() async {
        let expected: [Int: [String]] = [
            1: ["verify-1"],
            2: ["verify-1", "persist", "verify-2"],
            3: ["verify-1", "persist", "verify-2", "verify-3"],
            4: [
                "verify-1", "persist", "verify-2", "verify-3", "erase",
                "verify-4",
            ],
            5: [
                "verify-1", "persist", "verify-2", "verify-3", "erase",
                "verify-4", "purge", "verify-5",
            ],
        ]
        for failingVerification in 1...5 {
            var events: [String] = []
            var verificationCount = 0
            do {
                _ = try await CloudKitOwnerDeletionRecoveryExecutor().recover(
                    verifyOriginAccount: {
                        verificationCount += 1
                        events.append("verify-\(verificationCount)")
                        if verificationCount == failingVerification {
                            throw RecoveryTestError.account
                        }
                    },
                    persistLedger: { events.append("persist") },
                    eraseZone: { events.append("erase") },
                    purgeLocalSources: { events.append("purge") },
                    commitRecovery: {
                        events.append("unexpected-commit")
                    }
                )
                XCTFail("Fence \(failingVerification) should fail")
            } catch {
                XCTAssertEqual(error as? RecoveryTestError, .account)
            }
            XCTAssertEqual(events, expected[failingVerification])
        }
    }

    @MainActor
    func testPurgeFailureRetainsRecoveryUntilRetry() async throws {
        var events: [String] = []
        var purgeAttempts = 0
        var commitCount = 0

        func recover() async throws {
            try await CloudKitProvenZoneDeletionRecoveryExecutor().recover(
                verifyOriginAccount: { events.append("verify") },
                purgeLocalSources: {
                    purgeAttempts += 1
                    events.append("purge-\(purgeAttempts)")
                    if purgeAttempts == 1 {
                        throw RecoveryTestError.purge
                    }
                },
                commit: {
                    commitCount += 1
                    events.append("commit")
                }
            )
        }

        do {
            try await recover()
            XCTFail("The first purge must fail before commit")
        } catch {
            XCTAssertEqual(error as? RecoveryTestError, .purge)
        }
        XCTAssertEqual(commitCount, 0)

        try await recover()
        XCTAssertEqual(commitCount, 1)
        XCTAssertEqual(
            events,
            ["verify", "purge-1", "verify", "purge-2", "verify", "commit"]
        )
    }

    func testEvidenceSpecificMarkersBlockOnlyOriginAndCommitOnce() throws {
        let fixture = try MarkerFixture()
        defer { fixture.remove() }
        let store = fixture.store()
        try fixture.configure(in: store)

        let rootMarkerID = try store.stageAmbiguousRemoteRemoval(
            profileID: fixture.profileID,
            recordID: fixture.rootRecordID,
            scope: .privateDatabase,
            evidence: .rootRecordDeletion,
            receivedAt: fixture.now
        )
        XCTAssertEqual(
            try store.stageAmbiguousRemoteRemoval(
                profileID: fixture.profileID,
                recordID: fixture.rootRecordID,
                scope: .privateDatabase,
                evidence: .rootRecordDeletion,
                receivedAt: fixture.now
            ),
            rootMarkerID
        )
        let zoneMarkerID = try store.stageAmbiguousRemoteRemoval(
            profileID: fixture.profileID,
            recordID: fixture.rootRecordID,
            scope: .privateDatabase,
            evidence: .zoneDeletion,
            receivedAt: fixture.now
        )
        XCTAssertNotEqual(rootMarkerID, zoneMarkerID)
        XCTAssertTrue(store.hasPendingInboxWorkForCurrentAccount())

        XCTAssertEqual(
            try store.confirm(accountRecordName: MarkerFixture.replacementAccount),
            .switchedAccounts
        )
        XCTAssertFalse(store.hasPendingInboxWorkForCurrentAccount())
        XCTAssertTrue(
            try store.pendingAmbiguousRemoteRemovalRevalidations().isEmpty
        )

        XCTAssertEqual(
            try store.confirm(accountRecordName: MarkerFixture.originAccount),
            .switchedAccounts
        )
        let markers = try store.pendingAmbiguousRemoteRemovalRevalidations()
        XCTAssertEqual(Set(markers.map(\.id)), [rootMarkerID, zoneMarkerID])
        let rootMarker = try XCTUnwrap(
            markers.first { $0.evidence == .rootRecordDeletion }
        )
        _ = try store.commitAmbiguousRemoteRemoval(
            rootMarker,
            record: CloudKitRemoteProfileRemovalRecordFactory.record(
                for: fixture.profileID
            )
        )

        XCTAssertTrue(
            try store.pendingAmbiguousRemoteRemovalRevalidations().isEmpty
        )
        XCTAssertEqual(store.inboxEntries().count, 1)
        XCTAssertEqual(store.binding(for: fixture.profileID).state, .ownerDeleted)
    }

    func testOwnerLedgerMarkerRejectsParticipantRoute() throws {
        let fixture = try MarkerFixture()
        defer { fixture.remove() }
        let store = fixture.store()
        try fixture.configureParticipant(in: store)

        XCTAssertThrowsError(
            try store.stageAmbiguousRemoteRemoval(
                profileID: fixture.profileID,
                recordID: fixture.rootRecordID,
                scope: .sharedDatabase,
                evidence: .ownerDeletionLedger,
                receivedAt: fixture.now
            )
        ) { error in
            XCTAssertEqual(
                error as? CloudKitFamilyPersistenceError,
                .bindingConflict
            )
        }
        XCTAssertTrue(
            try store.pendingAmbiguousRemoteRemovalRevalidations().isEmpty
        )
    }

    func testProvisionalOwnerMarkerWaitsForOtherMarkerBeforeBindingRollback()
        throws
    {
        let fixture = try MarkerFixture()
        defer { fixture.remove() }
        let store = fixture.store()
        _ = try store.confirm(accountRecordName: MarkerFixture.originAccount)
        let prepared =
            try store
            .prepareAndStageAmbiguousOwnerDeletionLedgerRecovery(
                profileID: fixture.profileID,
                zoneID: fixture.zoneID,
                rootRecordName: fixture.rootRecordID.recordName,
                receivedAt: fixture.now
            )
        XCTAssertTrue(prepared.provisionalBindingCreated)
        _ = try store.stageAmbiguousRemoteRemoval(
            profileID: fixture.profileID,
            recordID: fixture.rootRecordID,
            scope: .privateDatabase,
            evidence: .rootRecordDeletion,
            receivedAt: fixture.now
        )

        var markers = try store.pendingAmbiguousRemoteRemovalRevalidations()
        let ownerMarker = try XCTUnwrap(
            markers.first { $0.evidence == .ownerDeletionLedger }
        )
        XCTAssertFalse(
            try store.discardAmbiguousOwnerDeletionLedgerAbsence(ownerMarker),
            "Creation provenance must remain while another marker uses the binding"
        )
        XCTAssertTrue(store.hasPersistedBinding(for: fixture.profileID))
        XCTAssertEqual(
            try store.pendingAmbiguousRemoteRemovalRevalidations().count,
            2
        )

        markers = try store.pendingAmbiguousRemoteRemovalRevalidations()
        let rootMarker = try XCTUnwrap(
            markers.first { $0.evidence == .rootRecordDeletion }
        )
        try store.discardAmbiguousRemoteRemoval(rootMarker)

        let restarted = fixture.store()
        let retainedOwnerMarker = try XCTUnwrap(
            restarted.pendingAmbiguousRemoteRemovalRevalidations().only
        )
        XCTAssertTrue(retainedOwnerMarker.provisionalBindingCreated)
        XCTAssertTrue(
            try restarted.discardAmbiguousOwnerDeletionLedgerAbsence(
                retainedOwnerMarker
            )
        )
        XCTAssertFalse(restarted.hasPersistedBinding(for: fixture.profileID))
        XCTAssertTrue(
            try restarted.pendingAmbiguousRemoteRemovalRevalidations().isEmpty
        )
    }

    func testLegacyBindingWithoutCreationMarkerIsConservativelyRetained()
        throws
    {
        let fixture = try MarkerFixture()
        defer { fixture.remove() }
        let store = fixture.store()
        _ = try store.confirm(accountRecordName: MarkerFixture.originAccount)
        let legacyPreparation = try store.prepareOwnerDeletionLedgerRecovery(
            profileID: fixture.profileID,
            zoneID: fixture.zoneID,
            rootRecordName: fixture.rootRecordID.recordName
        )
        XCTAssertTrue(legacyPreparation.wasCreated)
        XCTAssertTrue(
            try store.pendingAmbiguousRemoteRemovalRevalidations().isEmpty
        )

        let restarted = fixture.store()
        let recovered =
            try restarted
            .prepareAndStageAmbiguousOwnerDeletionLedgerRecovery(
                profileID: fixture.profileID,
                zoneID: fixture.zoneID,
                rootRecordName: fixture.rootRecordID.recordName,
                receivedAt: fixture.now
            )
        XCTAssertFalse(recovered.provisionalBindingCreated)
        let marker = try XCTUnwrap(
            restarted.pendingAmbiguousRemoteRemovalRevalidations().only
        )
        XCTAssertFalse(marker.provisionalBindingCreated)

        XCTAssertTrue(
            try restarted.discardAmbiguousOwnerDeletionLedgerAbsence(marker)
        )
        XCTAssertTrue(
            restarted.hasPersistedBinding(for: fixture.profileID),
            "Old binding-only snapshots lack safe creation provenance and must not be guessed away"
        )
    }
}

private struct MarkerFixture {
    static let originAccount = "ambiguous-origin"
    static let replacementAccount = "ambiguous-replacement"

    let directory: URL
    let metadataURL: URL
    let profileID = ProfileID()
    let now = Date(timeIntervalSince1970: 789)

    init() throws {
        directory = FileManager.default.temporaryDirectory.appendingPathComponent(
            "TadaWords-Ambiguous-Recovery-\(UUID().uuidString)",
            isDirectory: true
        )
        try FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true
        )
        metadataURL = directory.appendingPathComponent("metadata.json")
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

    func store() -> CloudKitFamilyMetadataStore {
        CloudKitFamilyMetadataStore(snapshotURL: metadataURL)
    }

    func configure(in store: CloudKitFamilyMetadataStore) throws {
        _ = try store.confirm(accountRecordName: Self.originAccount)
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

    func configureParticipant(
        in store: CloudKitFamilyMetadataStore
    ) throws {
        _ = try store.confirm(accountRecordName: Self.originAccount)
        try store.save(
            binding: ProfileCloudBinding(
                profileID: profileID,
                state: .sharedParticipant,
                zoneName: zoneID.zoneName,
                ownerName: zoneID.ownerName,
                rootRecordName: rootRecordID.recordName
            )
        )
    }

    func remove() {
        try? FileManager.default.removeItem(at: directory)
    }
}

private enum RecoveryTestError: Error, Equatable {
    case account
    case purge
}

extension Collection {
    fileprivate var only: Element? {
        count == 1 ? first : nil
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
