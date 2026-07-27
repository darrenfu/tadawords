import Foundation
import TadaWordsContent
import TadaWordsDomain
import XCTest

final class CanonicalFamilySyncRecoveryCoordinatorTests: XCTestCase {
    func testExactTwoProfile220RecordSnapshotIsAcknowledgedOnlyAfterRemoteProof()
        async throws
    {
        let fixture = CanonicalRecoveryFixture()
        let records = fixture.records(count: 220)
        let store = CanonicalRecoveryStore(records: records)
        let journal = VolatileFamilySyncJournalRepository()
        let versioned = await journal.reconcileLocalRecords(
            records,
            deviceID: fixture.installationID,
            now: fixture.now
        )
        await store.replace(versioned)
        let transport = CanonicalRecoveryTransport()
        let coordinator = CanonicalFamilySyncRecoveryCoordinator(
            store: store,
            transport: transport,
            journal: journal,
            installationID: fixture.installationID,
            clock: CanonicalRecoveryClock(now: fixture.now)
        )
        let plan = try await coordinator.canonicalRecoveryPlan()

        XCTAssertEqual(plan.profileIDs, fixture.profileIDs)
        XCTAssertEqual(plan.recordCount, 220)
        XCTAssertEqual(plan.recordCountsByKind[.profile], 2)
        XCTAssertEqual(plan.recordCountsByKind[.wordPoolEntry], 171)
        XCTAssertEqual(plan.recordCountsByKind[.attempt], 28)
        XCTAssertEqual(plan.recordCountsByKind[.dailyPlan], 3)
        XCTAssertEqual(plan.recordCountsByKind[.dailyCompletion], 3)
        XCTAssertEqual(plan.recordCountsByKind[.practiceSettings], 12)
        XCTAssertEqual(plan.recordCountsByKind[.rewardGrant], 1)
        let receipt = try await coordinator.recoverCanonicalLocalData(
            authorization: .init(expectedPlan: plan)
        )

        XCTAssertEqual(receipt.recoveredRecordCount, 220)
        let received = await transport.receivedRecords()
        let pending = await journal.pendingChanges(
            using: versioned,
            now: fixture.now
        )
        XCTAssertEqual(received.count, versioned.count)
        XCTAssertEqual(
            FamilySyncRecordSetFingerprint(records: received),
            FamilySyncRecordSetFingerprint(records: versioned)
        )
        XCTAssertTrue(pending.isEmpty)
    }

    func testChangedProfileSetNeverCallsDestructiveTransport() async throws {
        let fixture = CanonicalRecoveryFixture()
        let store = CanonicalRecoveryStore(records: fixture.records(count: 4))
        let transport = CanonicalRecoveryTransport()
        let coordinator = CanonicalFamilySyncRecoveryCoordinator(
            store: store,
            transport: transport,
            journal: VolatileFamilySyncJournalRepository(),
            installationID: fixture.installationID
        )
        let plan = try await coordinator.canonicalRecoveryPlan()
        await store.replace(
            fixture.records(count: 4).filter {
                $0.profileID == fixture.profileIDs[0]
            }
        )

        await assertThrowsErrorAsync(
            try await coordinator.recoverCanonicalLocalData(
                authorization: .init(expectedPlan: plan)
            )
        ) {
            XCTAssertEqual(
                $0 as? FamilySyncCanonicalRecoveryError,
                .profileSetChanged
            )
        }
        let callCount = await transport.callCount()
        XCTAssertEqual(callCount, 0)
    }

    func testDifferentInstallationNeverCallsDestructiveTransport() async throws {
        let fixture = CanonicalRecoveryFixture()
        let store = CanonicalRecoveryStore(records: fixture.records(count: 4))
        let transport = CanonicalRecoveryTransport()
        let coordinator = CanonicalFamilySyncRecoveryCoordinator(
            store: store,
            transport: transport,
            journal: VolatileFamilySyncJournalRepository(),
            installationID: fixture.installationID
        )
        let plan = try await coordinator.canonicalRecoveryPlan()
        let wrongPlan = FamilySyncCanonicalRecoveryPlan(
            profileIDs: plan.profileIDs,
            recordCount: plan.recordCount,
            recordCountsByKind: plan.recordCountsByKind,
            recordSetFingerprint: plan.recordSetFingerprint,
            installationID: "different-installation"
        )

        await assertThrowsErrorAsync(
            try await coordinator.recoverCanonicalLocalData(
                authorization: .init(expectedPlan: wrongPlan)
            )
        ) {
            XCTAssertEqual(
                $0 as? FamilySyncCanonicalRecoveryError,
                .installationMismatch
            )
        }
        let callCount = await transport.callCount()
        XCTAssertEqual(callCount, 0)
    }

    func testTransportInterruptionKeepsEveryOutboxEntryPending() async throws {
        let fixture = CanonicalRecoveryFixture()
        let records = fixture.records(count: 8)
        let store = CanonicalRecoveryStore(records: records)
        let journal = VolatileFamilySyncJournalRepository()
        let versioned = await journal.reconcileLocalRecords(
            records,
            deviceID: fixture.installationID,
            now: fixture.now
        )
        await store.replace(versioned)
        let transport = CanonicalRecoveryTransport(
            replacementError: CanonicalRecoveryTestError.interrupted
        )
        let coordinator = CanonicalFamilySyncRecoveryCoordinator(
            store: store,
            transport: transport,
            journal: journal,
            installationID: fixture.installationID
        )
        let plan = try await coordinator.canonicalRecoveryPlan()

        await assertThrowsErrorAsync(
            try await coordinator.recoverCanonicalLocalData(
                authorization: .init(expectedPlan: plan)
            )
        )
        let pending = await journal.pendingChanges(
            using: versioned,
            now: fixture.now
        )
        XCTAssertEqual(pending.count, versioned.count)
    }

    func testRemoteMismatchDoesNotAcknowledgeLocalOutbox() async throws {
        let fixture = CanonicalRecoveryFixture()
        let records = fixture.records(count: 8)
        let store = CanonicalRecoveryStore(records: records)
        let journal = VolatileFamilySyncJournalRepository()
        let versioned = await journal.reconcileLocalRecords(
            records,
            deviceID: fixture.installationID,
            now: fixture.now
        )
        await store.replace(versioned)
        let transport = CanonicalRecoveryTransport(
            receiptOverride: .init(
                verifiedRemoteFingerprint: .init(records: []),
                recoveredRecordCount: 0
            )
        )
        let coordinator = CanonicalFamilySyncRecoveryCoordinator(
            store: store,
            transport: transport,
            journal: journal,
            installationID: fixture.installationID
        )
        let plan = try await coordinator.canonicalRecoveryPlan()

        await assertThrowsErrorAsync(
            try await coordinator.recoverCanonicalLocalData(
                authorization: .init(expectedPlan: plan)
            )
        ) {
            XCTAssertEqual(
                $0 as? FamilySyncCanonicalRecoveryError,
                .remoteVerificationFailed
            )
        }
        let pending = await journal.pendingChanges(
            using: versioned,
            now: fixture.now
        )
        XCTAssertEqual(pending.count, versioned.count)
    }

    func testLocalMutationDuringReplacementDoesNotAcknowledgeSnapshot() async throws {
        let fixture = CanonicalRecoveryFixture()
        let records = fixture.records(count: 8)
        let store = CanonicalRecoveryStore(records: records)
        let journal = VolatileFamilySyncJournalRepository()
        let versioned = await journal.reconcileLocalRecords(
            records,
            deviceID: fixture.installationID,
            now: fixture.now
        )
        await store.replace(versioned)
        let transport = CanonicalRecoveryTransport {
            var changed = versioned
            changed[0] = fixture.record(
                profileID: changed[0].profileID,
                index: 999
            )
            await store.replace(changed)
        }
        let coordinator = CanonicalFamilySyncRecoveryCoordinator(
            store: store,
            transport: transport,
            journal: journal,
            installationID: fixture.installationID
        )
        let plan = try await coordinator.canonicalRecoveryPlan()

        await assertThrowsErrorAsync(
            try await coordinator.recoverCanonicalLocalData(
                authorization: .init(expectedPlan: plan)
            )
        ) {
            XCTAssertEqual(
                $0 as? FamilySyncCanonicalRecoveryError,
                .localSnapshotChanged
            )
        }
        let pending = await journal.pendingChanges(
            using: versioned,
            now: fixture.now
        )
        XCTAssertEqual(pending.count, versioned.count)
    }
}

private actor CanonicalRecoveryStore: FamilySyncRecordStore {
    private var records: [FamilySyncRecord]

    init(records: [FamilySyncRecord]) {
        self.records = records
    }

    func replace(_ records: [FamilySyncRecord]) {
        self.records = records
    }

    func profileIDsForSync() -> [ProfileID] {
        Array(Set(records.map(\.profileID)))
    }

    func records(for profileID: ProfileID) -> [FamilySyncRecord] {
        records.filter { $0.profileID == profileID }
    }

    func apply(_ records: [FamilySyncRecord], for profileID: ProfileID) {
        self.records.removeAll { $0.profileID == profileID }
        self.records.append(contentsOf: records)
    }
}

private actor CanonicalRecoveryTransport:
    FamilySyncCanonicalRecoveryTransport
{
    nonisolated let capability = FamilySyncCapability.iCloud
    private var calls = 0
    private var received: [FamilySyncRecord] = []
    private let receiptOverride: FamilySyncCanonicalRecoveryReceipt?
    private let replacementError: (any Error & Sendable)?
    private let onReplace: @Sendable () async -> Void

    init(
        receiptOverride: FamilySyncCanonicalRecoveryReceipt? = nil,
        replacementError: (any Error & Sendable)? = nil,
        onReplace: @escaping @Sendable () async -> Void = {}
    ) {
        self.receiptOverride = receiptOverride
        self.replacementError = replacementError
        self.onReplace = onReplace
    }

    func availability() -> FamilySyncAvailability { .available }
    func prepareProfileZone(_ profileID: ProfileID) async throws {}
    func fetchRecords(for profileID: ProfileID) async throws -> [FamilySyncRecord] {
        []
    }
    func push(
        _ records: [FamilySyncRecord],
        for profileID: ProfileID
    ) async throws {}
    func createShare(for profileID: ProfileID) async throws -> URL {
        URL(string: "https://example.invalid")!
    }
    func acceptShare(at url: URL) async throws -> ProfileID {
        ProfileID()
    }

    func replaceRemoteWithCanonicalRecords(
        _ records: [FamilySyncRecord],
        authorization: FamilySyncCanonicalRecoveryAuthorization
    ) async throws -> FamilySyncCanonicalRecoveryReceipt {
        calls += 1
        received = records
        await onReplace()
        if let replacementError { throw replacementError }
        return receiptOverride
            ?? .init(
                verifiedRemoteFingerprint: authorization.expectedPlan
                    .recordSetFingerprint,
                recoveredRecordCount: records.count
            )
    }

    func callCount() -> Int { calls }
    func receivedRecords() -> [FamilySyncRecord] { received }
}

private enum CanonicalRecoveryTestError: Error, Sendable {
    case interrupted
}

private struct CanonicalRecoveryFixture {
    let profileIDs = [
        ProfileID(rawValue: UUID(uuidString: "2821E4F6-B2AC-45D0-9A77-59A2322B4E7E")!),
        ProfileID(rawValue: UUID(uuidString: "8EFBB428-64EC-40EE-BF52-362160E744A7")!),
    ]
    let installationID = "F399F4B9-EB03-4BA5-8290-2D6653A465BE"
    let now = Date(timeIntervalSince1970: 1_785_121_955)

    func records(count: Int) -> [FamilySyncRecord] {
        (0..<count).map {
            record(profileID: profileIDs[$0 % profileIDs.count], index: $0)
        }
    }

    func record(profileID: ProfileID, index: Int) -> FamilySyncRecord {
        let kind: FamilySyncRecordKind =
            switch index {
            case 0..<2: .profile
            case 2..<173: .wordPoolEntry
            case 173..<201: .attempt
            case 201..<204: .dailyPlan
            case 204..<207: .dailyCompletion
            case 207..<219: .practiceSettings
            default: .rewardGrant
            }
        return FamilySyncRecord(
            recordName: index < 2 ? "profile-\(profileID)" : "word-\(index)",
            profileID: profileID,
            kind: kind,
            payload: Data("payload-\(index)".utf8),
            updatedAt: now,
            deviceID: installationID,
            logicalRevision: .init(
                counter: 1,
                deviceID: installationID
            )
        )
    }
}

private struct CanonicalRecoveryClock: AppClock {
    let now: Date
}

private func assertThrowsErrorAsync<T>(
    _ expression: @autoclosure () async throws -> T,
    _ errorHandler: (Error) -> Void = { _ in }
) async {
    do {
        _ = try await expression()
        XCTFail("Expected error")
    } catch {
        errorHandler(error)
    }
}
