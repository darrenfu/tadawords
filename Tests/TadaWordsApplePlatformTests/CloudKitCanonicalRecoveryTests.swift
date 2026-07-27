@preconcurrency import CloudKit
import Foundation
import TadaWordsDomain
import XCTest

@testable import TadaWordsApplePlatform

final class CloudKitCanonicalRecoveryTests: XCTestCase {
    func testDurableMarkerSurvivesRestartAndIdenticalRetry() throws {
        let fixture = try CloudKitCanonicalRecoveryFixture()
        defer { fixture.remove() }
        let store = CloudKitFamilyMetadataStore(snapshotURL: fixture.url)
        try store.confirm(accountRecordName: fixture.account)

        let first = try store.prepareCanonicalRecovery(
            authorization: fixture.authorization,
            originAccountRecordName: fixture.account,
            stagedAt: fixture.now
        )
        let restarted = CloudKitFamilyMetadataStore(snapshotURL: fixture.url)
        let restored = try restarted.pendingCanonicalRecovery()
        let retried = try restarted.prepareCanonicalRecovery(
            authorization: fixture.authorization,
            originAccountRecordName: fixture.account,
            stagedAt: fixture.now.addingTimeInterval(30)
        )

        XCTAssertEqual(restored, first)
        XCTAssertEqual(retried, first)
        try restarted.completeCanonicalRecovery(first)
        XCTAssertNil(try restarted.pendingCanonicalRecovery())
    }

    func testDifferentBackupCannotClaimPendingRecovery() throws {
        let fixture = try CloudKitCanonicalRecoveryFixture()
        defer { fixture.remove() }
        let store = CloudKitFamilyMetadataStore(snapshotURL: fixture.url)
        try store.confirm(accountRecordName: fixture.account)
        _ = try store.prepareCanonicalRecovery(
            authorization: fixture.authorization,
            originAccountRecordName: fixture.account
        )
        let mismatched = FamilySyncCanonicalRecoveryAuthorization(
            expectedPlan: fixture.authorization.expectedPlan,
            verifiedBackupSHA256: String(repeating: "b", count: 64)
        )

        XCTAssertThrowsError(
            try store.prepareCanonicalRecovery(
                authorization: mismatched,
                originAccountRecordName: fixture.account
            )
        )
        XCTAssertNotNil(try store.pendingCanonicalRecovery())
    }

    func testCorruptPendingRecoveryMarkerFailsClosedAfterRestart() throws {
        let fixture = try CloudKitCanonicalRecoveryFixture()
        defer { fixture.remove() }
        let store = CloudKitFamilyMetadataStore(snapshotURL: fixture.url)
        try store.confirm(accountRecordName: fixture.account)
        _ = try store.prepareCanonicalRecovery(
            authorization: fixture.authorization,
            originAccountRecordName: fixture.account
        )
        let data = try Data(contentsOf: fixture.url)
        var object = try XCTUnwrap(
            JSONSerialization.jsonObject(with: data) as? [String: Any]
        )
        var marker = try XCTUnwrap(
            object["pendingCanonicalRecovery"] as? [String: Any]
        )
        marker["recordCount"] = 0
        object["pendingCanonicalRecovery"] = marker
        try JSONSerialization.data(withJSONObject: object).write(
            to: fixture.url,
            options: .atomic
        )

        let restarted = CloudKitFamilyMetadataStore(snapshotURL: fixture.url)
        XCTAssertThrowsError(try restarted.pendingCanonicalRecovery())
    }

    func testExecutorNeverCompletesMarkerBeforeRemoteVerification() async throws {
        let probe = CloudKitCanonicalRecoveryProbe()

        await assertThrowsErrorAsync {
            try await CloudKitCanonicalRecoveryExecutor().recover(
                prepareDurableMarker: { probe.note("prepare") },
                verifyOriginAccount: { probe.note("account") },
                publishProfiles: { probe.note("publish") },
                verifyRemoteManifest: {
                    probe.note("verify")
                    throw FamilySyncCanonicalRecoveryError
                        .remoteVerificationFailed
                },
                completeDurableMarker: { probe.note("complete") }
            ) as Void
        }

        let events = probe.events()
        XCTAssertEqual(
            events,
            ["prepare", "account", "publish", "account", "verify"]
        )
    }

    func testExecutorCompletesOnlyAfterVerifiedManifestAndFinalAccountFence()
        async throws
    {
        let probe = CloudKitCanonicalRecoveryProbe()
        let value: Int = try await CloudKitCanonicalRecoveryExecutor().recover(
            prepareDurableMarker: { probe.note("prepare") },
            verifyOriginAccount: { probe.note("account") },
            publishProfiles: { probe.note("publish") },
            verifyRemoteManifest: {
                probe.note("verify")
                return 220
            },
            completeDurableMarker: { probe.note("complete") }
        )

        let events = probe.events()
        XCTAssertEqual(value, 220)
        XCTAssertEqual(
            events,
            [
                "prepare", "account", "publish", "account", "verify",
                "account", "complete",
            ]
        )
    }

    func testAccountSwitchAtFinalFenceNeverCompletesMarker() async throws {
        let probe = CloudKitCanonicalRecoveryProbe()
        let accountChecks = CloudKitCanonicalRecoveryCounter()

        await assertThrowsErrorAsync {
            try await CloudKitCanonicalRecoveryExecutor().recover(
                prepareDurableMarker: { probe.note("prepare") },
                verifyOriginAccount: {
                    probe.note("account")
                    if accountChecks.increment() == 3 {
                        throw CloudKitFamilySyncError.accountBindingMismatch
                    }
                },
                publishProfiles: { probe.note("publish") },
                verifyRemoteManifest: {
                    probe.note("verify")
                },
                completeDurableMarker: { probe.note("complete") }
            ) as Void
        }

        XCTAssertEqual(
            probe.events(),
            ["prepare", "account", "publish", "account", "verify", "account"]
        )
    }

    func testGenerationPointerIsVerifiedBeforeLegacyZoneProjection()
        async throws
    {
        let probe = CloudKitCanonicalRecoveryProbe()
        let value: Int =
            try await CloudKitCanonicalGenerationActivationExecutor()
            .activate(
                stageSnapshot: { probe.note("stage") },
                activatePointer: { probe.note("activate") },
                verifyActiveSnapshot: {
                    probe.note("verify")
                    return 220
                },
                projectLegacyZones: { recordCount in
                    XCTAssertEqual(recordCount, 220)
                    probe.note("project")
                }
            )

        XCTAssertEqual(value, 220)
        XCTAssertEqual(
            probe.events(),
            ["stage", "activate", "verify", "project"]
        )
    }

    func testProjectionFailureLeavesPointerActivationAsRetryBoundary()
        async
    {
        let probe = CloudKitCanonicalRecoveryProbe()

        await assertThrowsErrorAsync {
            _ =
                try await CloudKitCanonicalGenerationActivationExecutor()
                .activate(
                    stageSnapshot: { probe.note("stage") },
                    activatePointer: { probe.note("activate") },
                    verifyActiveSnapshot: {
                        probe.note("verify")
                        return 220
                    },
                    projectLegacyZones: { _ in
                        probe.note("project")
                        throw FamilySyncCanonicalRecoveryError
                            .remoteVerificationFailed
                    }
                ) as Int
        }

        XCTAssertEqual(
            probe.events(),
            ["stage", "activate", "verify", "project"]
        )
    }

    func testSharedAndTerminalBindingsCannotEnterPrivateOwnerPublication() {
        let fixture = CloudKitCanonicalRecoveryBindingFixture()
        for state in [
            ProfileCloudBindingState.sharedParticipant,
            .revoked,
            .ownerDeleted,
            .participantLeft,
        ] {
            XCTAssertThrowsError(
                try CloudKitCanonicalRecoveryBindingProof()
                    .requirePrivateOwnerPublication(
                        binding: fixture.binding(state: state),
                        expectedZoneID: fixture.zoneID,
                        expectedRootRecordID: fixture.rootID,
                        isAuthorizedForConfirmedAccount: true
                    )
            )
        }
    }

    func testAppliedGenerationClearsSupersededConflictStateDurably()
        throws
    {
        let fixture = try CloudKitCanonicalRecoveryFixture()
        defer { fixture.remove() }
        let store = CloudKitFamilyMetadataStore(snapshotURL: fixture.url)
        try store.confirm(accountRecordName: fixture.account)
        try store.quarantine(
            CloudKitFamilyQuarantineEntry(
                id: UUID(),
                scope: .privateDatabase,
                recordName: "attempt-conflict",
                zoneName: "TadaProfile-conflict",
                ownerName: CKCurrentUserDefaultName,
                reason: .conflict,
                envelopeData: Data("stale".utf8),
                quarantinedAt: fixture.now
            )
        )
        XCTAssertEqual(store.quarantinedCount(), 1)

        try store.markCanonicalGenerationApplied("generation-1")

        let restarted = CloudKitFamilyMetadataStore(
            snapshotURL: fixture.url
        )
        XCTAssertEqual(
            try restarted.appliedCanonicalGenerationID(),
            "generation-1"
        )
        XCTAssertEqual(restarted.quarantinedCount(), 0)
    }
}

private struct CloudKitCanonicalRecoveryFixture {
    let directory: URL
    let url: URL
    let account = "owner-account"
    let now = Date(timeIntervalSince1970: 1_785_121_955)
    let authorization: FamilySyncCanonicalRecoveryAuthorization

    init() throws {
        directory = FileManager.default.temporaryDirectory.appendingPathComponent(
            "cloudkit-canonical-recovery-\(UUID().uuidString)",
            isDirectory: true
        )
        try FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true
        )
        url = directory.appendingPathComponent("metadata.json")
        let fixtureNow = Date(timeIntervalSince1970: 1_785_121_955)
        let profileIDs = [
            ProfileID(
                rawValue: UUID(
                    uuidString: "2821E4F6-B2AC-45D0-9A77-59A2322B4E7E"
                )!
            ),
            ProfileID(
                rawValue: UUID(
                    uuidString: "8EFBB428-64EC-40EE-BF52-362160E744A7"
                )!
            ),
        ]
        let records = profileIDs.enumerated().map { index, profileID in
            FamilySyncRecord(
                recordName: "profile-\(profileID)",
                profileID: profileID,
                kind: .profile,
                payload: Data("profile-\(index)".utf8),
                updatedAt: fixtureNow,
                deviceID: "F399F4B9-EB03-4BA5-8290-2D6653A465BE"
            )
        }
        authorization = .init(
            expectedPlan: .init(
                profileIDs: profileIDs,
                recordCount: records.count,
                recordSetFingerprint: .init(records: records),
                installationID: "F399F4B9-EB03-4BA5-8290-2D6653A465BE"
            ),
            verifiedBackupSHA256:
                "e616ce98d1e37b6949a203563399a2da204d72efec077619594b4c109ae78db2"
        )
    }

    func remove() {
        try? FileManager.default.removeItem(at: directory)
    }
}

private final class CloudKitCanonicalRecoveryProbe: @unchecked Sendable {
    private let lock = NSLock()
    private var recorded: [String] = []
    func note(_ event: String) {
        lock.withLock { recorded.append(event) }
    }
    func events() -> [String] {
        lock.withLock { recorded }
    }
}

private final class CloudKitCanonicalRecoveryCounter: @unchecked Sendable {
    private let lock = NSLock()
    private var value = 0
    func increment() -> Int {
        lock.withLock {
            value += 1
            return value
        }
    }
}

private struct CloudKitCanonicalRecoveryBindingFixture {
    let profileID = ProfileID(
        rawValue: UUID(
            uuidString: "2821E4F6-B2AC-45D0-9A77-59A2322B4E7E"
        )!
    )
    let zoneID = CKRecordZone.ID(
        zoneName: "TadaProfile-2821E4F6-B2AC-45D0-9A77-59A2322B4E7E",
        ownerName: CKCurrentUserDefaultName
    )
    var rootID: CKRecord.ID {
        CKRecord.ID(recordName: "ProfileRoot", zoneID: zoneID)
    }

    func binding(state: ProfileCloudBindingState) -> ProfileCloudBinding {
        ProfileCloudBinding(
            profileID: profileID,
            state: state,
            zoneName: zoneID.zoneName,
            ownerName: zoneID.ownerName,
            rootRecordName: rootID.recordName,
            originAccountRecordName: "owner-account"
        )
    }
}

private func assertThrowsErrorAsync(
    _ expression: () async throws -> Void
) async {
    do {
        try await expression()
        XCTFail("Expected error")
    } catch {}
}
