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
                replaceProfiles: { probe.note("replace") },
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
            ["prepare", "account", "replace", "account", "verify"]
        )
    }

    func testExecutorCompletesOnlyAfterVerifiedManifestAndFinalAccountFence()
        async throws
    {
        let probe = CloudKitCanonicalRecoveryProbe()
        let value: Int = try await CloudKitCanonicalRecoveryExecutor().recover(
            prepareDurableMarker: { probe.note("prepare") },
            verifyOriginAccount: { probe.note("account") },
            replaceProfiles: { probe.note("replace") },
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
                "prepare", "account", "replace", "account", "verify",
                "account", "complete",
            ]
        )
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

private func assertThrowsErrorAsync(
    _ expression: () async throws -> Void
) async {
    do {
        try await expression()
        XCTFail("Expected error")
    } catch {}
}
