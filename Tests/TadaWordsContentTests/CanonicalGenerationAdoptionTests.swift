import Foundation
import TadaWordsContent
import TadaWordsDomain
import XCTest

final class CanonicalGenerationAdoptionTests: XCTestCase {
    func testFreshInstallAdoptsCanonicalGenerationBeforeAnyUpload()
        async throws
    {
        let profileID = ProfileID()
        let record = FamilySyncRecord(
            recordName: "profile-\(profileID)",
            profileID: profileID,
            kind: .profile,
            payload: Data("canonical".utf8),
            updatedAt: Date(timeIntervalSince1970: 10),
            deviceID: "canonical",
            logicalRevision: .init(counter: 4, deviceID: "canonical")
        )
        let snapshot = FamilySyncCanonicalGenerationSnapshot(
            generationID: "generation-1",
            previousGenerationID: nil,
            sourceInstallationID: "source-ipad",
            createdAt: Date(timeIntervalSince1970: 20),
            records: [record]
        )
        let store = CanonicalAdoptionStore()
        let transport = CanonicalAdoptionTransport(snapshot: snapshot)
        let coordinator = LocalFirstFamilySyncCoordinator(
            store: store,
            transport: transport,
            preferenceRepository: InMemoryFamilySyncPreferenceRepository(
                isEnabled: true
            ),
            journalRepository: VolatileFamilySyncJournalRepository(),
            deviceID: "fresh-install",
            clock: CanonicalAdoptionClock(
                now: Date(timeIntervalSince1970: 30)
            )
        )

        let status = await coordinator.synchronize()
        let currentRecords = await store.currentRecords()
        let replacementCount = await store.replacementCount()
        let sendCount = await transport.sendCount()
        let didMarkApplied = await transport.didMarkApplied()

        XCTAssertEqual(status, .synced(at: Date(timeIntervalSince1970: 30)))
        XCTAssertEqual(currentRecords, [record])
        XCTAssertEqual(replacementCount, 1)
        XCTAssertEqual(sendCount, 0)
        XCTAssertTrue(didMarkApplied)
    }

    func testFreshFindConfirmsAccountBeforeAdoptingCanonicalGeneration()
        async throws
    {
        let profileID = ProfileID()
        let record = FamilySyncRecord(
            recordName: "profile-\(profileID)",
            profileID: profileID,
            kind: .profile,
            payload: Data("canonical".utf8),
            updatedAt: Date(timeIntervalSince1970: 10),
            deviceID: "canonical"
        )
        let snapshot = FamilySyncCanonicalGenerationSnapshot(
            generationID: "generation-find",
            previousGenerationID: nil,
            sourceInstallationID: "source-ipad",
            createdAt: Date(timeIntervalSince1970: 20),
            records: [record]
        )
        let store = CanonicalAdoptionStore()
        let transport = CanonicalAdoptionTransport(
            snapshot: snapshot,
            confirmationRequired: true
        )
        let coordinator = LocalFirstFamilySyncCoordinator(
            store: store,
            transport: transport,
            preferenceRepository: InMemoryFamilySyncPreferenceRepository(
                isEnabled: false
            ),
            journalRepository: VolatileFamilySyncJournalRepository(),
            deviceID: "fresh-install",
            clock: CanonicalAdoptionClock(
                now: Date(timeIntervalSince1970: 30)
            )
        )

        let status = try await coordinator.setEnabled(true)
        let confirmationCount = await transport.confirmationCount()
        let currentRecords = await store.currentRecords()
        let replacementCount = await store.replacementCount()
        let sendCount = await transport.sendCount()

        XCTAssertEqual(status, .synced(at: Date(timeIntervalSince1970: 30)))
        XCTAssertEqual(confirmationCount, 1)
        XCTAssertEqual(currentRecords, [record])
        XCTAssertEqual(replacementCount, 1)
        XCTAssertEqual(sendCount, 0)
    }

    func testInterruptedSourcePublicationResumesBeforeOrdinarySync()
        async throws
    {
        let profileID = ProfileID()
        let record = FamilySyncRecord(
            recordName: "profile-\(profileID)",
            profileID: profileID,
            kind: .profile,
            payload: Data("canonical-source".utf8),
            updatedAt: Date(timeIntervalSince1970: 10),
            deviceID: "source-ipad",
            logicalRevision: .init(counter: 7, deviceID: "source-ipad")
        )
        let snapshot = FamilySyncCanonicalGenerationSnapshot(
            generationID: "generation-resumed",
            previousGenerationID: "generation-old",
            sourceInstallationID: "source-ipad",
            createdAt: Date(timeIntervalSince1970: 20),
            records: [record]
        )
        let store = CanonicalAdoptionStore(records: [record])
        let transport = CanonicalAdoptionTransport(
            snapshot: snapshot,
            pendingResumeRecords: [record]
        )
        let coordinator = LocalFirstFamilySyncCoordinator(
            store: store,
            transport: transport,
            preferenceRepository: InMemoryFamilySyncPreferenceRepository(
                isEnabled: true
            ),
            journalRepository: VolatileFamilySyncJournalRepository(),
            deviceID: "source-ipad",
            clock: CanonicalAdoptionClock(
                now: Date(timeIntervalSince1970: 30)
            )
        )

        let status = await coordinator.synchronize()
        let resumeCount = await transport.resumeCount()
        let fetchCount = await transport.fetchCount()
        let sendCount = await transport.sendCount()
        let currentRecords = await store.currentRecords()
        let replacementCount = await store.replacementCount()

        XCTAssertEqual(status, .synced(at: Date(timeIntervalSince1970: 30)))
        XCTAssertEqual(resumeCount, 1)
        XCTAssertEqual(fetchCount, 1)
        XCTAssertEqual(sendCount, 0)
        XCTAssertEqual(currentRecords, [record])
        XCTAssertEqual(replacementCount, 0)
    }

    func testChangedSourceSnapshotCannotClaimPendingPublication() async {
        let profileID = ProfileID()
        let authorized = FamilySyncRecord(
            recordName: "profile-\(profileID)",
            profileID: profileID,
            kind: .profile,
            payload: Data("authorized".utf8),
            updatedAt: Date(timeIntervalSince1970: 10),
            deviceID: "source-ipad"
        )
        let changed = FamilySyncRecord(
            recordName: authorized.recordName,
            profileID: profileID,
            kind: .profile,
            payload: Data("changed".utf8),
            updatedAt: Date(timeIntervalSince1970: 11),
            deviceID: "source-ipad"
        )
        let snapshot = FamilySyncCanonicalGenerationSnapshot(
            generationID: "generation-pending",
            previousGenerationID: nil,
            sourceInstallationID: "source-ipad",
            createdAt: Date(),
            records: [authorized]
        )
        let store = CanonicalAdoptionStore(records: [changed])
        let transport = CanonicalAdoptionTransport(
            snapshot: snapshot,
            pendingResumeRecords: [authorized]
        )
        let coordinator = LocalFirstFamilySyncCoordinator(
            store: store,
            transport: transport,
            preferenceRepository: InMemoryFamilySyncPreferenceRepository(
                isEnabled: true
            )
        )

        let status = await coordinator.synchronize()
        let resumeCount = await transport.resumeCount()
        let fetchCount = await transport.fetchCount()
        let sendCount = await transport.sendCount()
        let didMarkApplied = await transport.didMarkApplied()
        let currentRecords = await store.currentRecords()

        guard case .failed = status else {
            return XCTFail("Expected changed source snapshot to fail closed")
        }
        XCTAssertEqual(resumeCount, 0)
        XCTAssertEqual(fetchCount, 0)
        XCTAssertEqual(sendCount, 0)
        XCTAssertFalse(didMarkApplied)
        XCTAssertEqual(currentRecords, [changed])
    }

    func testFailedAuthoritativeApplyNeverAdvancesFenceOrUploads() async {
        let profileID = ProfileID()
        let snapshot = FamilySyncCanonicalGenerationSnapshot(
            generationID: "generation-2",
            previousGenerationID: "generation-1",
            sourceInstallationID: "source-ipad",
            createdAt: Date(),
            records: [
                FamilySyncRecord(
                    recordName: "profile-\(profileID)",
                    profileID: profileID,
                    kind: .profile,
                    payload: Data("canonical".utf8),
                    updatedAt: Date(),
                    deviceID: "canonical"
                )
            ]
        )
        let store = CanonicalAdoptionStore(failReplacement: true)
        let transport = CanonicalAdoptionTransport(snapshot: snapshot)
        let coordinator = LocalFirstFamilySyncCoordinator(
            store: store,
            transport: transport,
            preferenceRepository: InMemoryFamilySyncPreferenceRepository(
                isEnabled: true
            )
        )

        let status = await coordinator.synchronize()
        let didMarkApplied = await transport.didMarkApplied()
        let sendCount = await transport.sendCount()

        guard case .failed = status else {
            return XCTFail("Expected fail-closed adoption")
        }
        XCTAssertFalse(didMarkApplied)
        XCTAssertEqual(sendCount, 0)
    }
}

private enum CanonicalAdoptionFailure: Error {
    case injected
}

private actor CanonicalAdoptionStore: FamilySyncRecordStore {
    private var records: [FamilySyncRecord]
    private var replacements = 0
    private let failReplacement: Bool

    init(
        records: [FamilySyncRecord] = [],
        failReplacement: Bool = false
    ) {
        self.records = records
        self.failReplacement = failReplacement
    }

    func profileIDsForSync() -> [ProfileID] {
        Array(Set(records.map(\.profileID)))
    }

    func records(for profileID: ProfileID) -> [FamilySyncRecord] {
        records.filter { $0.profileID == profileID }
    }

    func apply(
        _ records: [FamilySyncRecord],
        for profileID: ProfileID
    ) {
        self.records.removeAll { $0.profileID == profileID }
        self.records.append(contentsOf: records)
    }

    func replaceWithCanonicalSnapshot(
        _ snapshot: FamilySyncCanonicalGenerationSnapshot
    ) throws {
        replacements += 1
        if failReplacement { throw CanonicalAdoptionFailure.injected }
        records = snapshot.records
    }

    func currentRecords() -> [FamilySyncRecord] { records }
    func replacementCount() -> Int { replacements }
}

private actor CanonicalAdoptionTransport:
    FamilySyncCanonicalRecoveryTransport
{
    nonisolated let capability: FamilySyncCapability = .iCloud
    private let snapshot: FamilySyncCanonicalGenerationSnapshot
    private var pendingResumeRecords: [FamilySyncRecord]?
    private var confirmationRequired: Bool
    private var confirmations = 0
    private var applied = false
    private var sends = 0
    private var fetches = 0
    private var resumes = 0

    init(
        snapshot: FamilySyncCanonicalGenerationSnapshot,
        pendingResumeRecords: [FamilySyncRecord]? = nil,
        confirmationRequired: Bool = false
    ) {
        self.snapshot = snapshot
        self.pendingResumeRecords = pendingResumeRecords
        self.confirmationRequired = confirmationRequired
    }

    nonisolated func availability() async -> FamilySyncAvailability {
        .available
    }

    func prepareProfileZone(_ profileID: ProfileID) {
        _ = profileID
    }

    func fetchRecords(for profileID: ProfileID) -> [FamilySyncRecord] {
        _ = profileID
        return []
    }

    func push(
        _ records: [FamilySyncRecord],
        for profileID: ProfileID
    ) {
        _ = profileID
        sends += records.count
    }

    func activeCanonicalGeneration()
        throws -> FamilySyncCanonicalGenerationSnapshot?
    {
        if confirmationRequired {
            throw CanonicalAdoptionFailure.injected
        }
        return snapshot
    }

    func confirmCurrentAccount() -> FamilySyncAccountChange? {
        confirmations += 1
        confirmationRequired = false
        return .signedIn
    }

    func resumePendingCanonicalGeneration(
        _ records: [FamilySyncRecord]
    ) throws -> FamilySyncCanonicalRecoveryReceipt? {
        guard let pendingResumeRecords else { return nil }
        guard records == pendingResumeRecords else {
            throw FamilySyncCanonicalRecoveryError.localSnapshotChanged
        }
        resumes += 1
        self.pendingResumeRecords = nil
        applied = true
        return FamilySyncCanonicalRecoveryReceipt(
            generationID: snapshot.generationID,
            previousGenerationID: snapshot.previousGenerationID,
            verifiedRemoteFingerprint: snapshot.recordSetFingerprint,
            recoveredRecordCount: snapshot.records.count
        )
    }

    func markCanonicalGenerationApplied(_ generationID: String) throws {
        guard generationID == snapshot.generationID else {
            throw CanonicalAdoptionFailure.injected
        }
        applied = true
    }

    func isCanonicalGenerationApplied(_ generationID: String) -> Bool {
        applied && generationID == snapshot.generationID
    }

    func fetchChanges(
        for profileIDs: [ProfileID],
        terminalProfileIDs: Set<ProfileID>
    ) -> FamilySyncTransportResult {
        _ = profileIDs
        _ = terminalProfileIDs
        fetches += 1
        return FamilySyncTransportResult(reachedServerHead: true)
    }

    func sendChanges(
        _ changes: [FamilySyncPendingOperation]
    ) -> FamilySyncTransportResult {
        sends += changes.count
        return FamilySyncTransportResult(
            acknowledged: Set(
                changes.map(FamilySyncChangeAcknowledgement.init)
            )
        )
    }

    func exchange(
        _ batch: FamilySyncTransportBatch
    ) -> FamilySyncTransportResult {
        _ = batch
        return FamilySyncTransportResult()
    }

    func createShare(for profileID: ProfileID) throws -> URL {
        _ = profileID
        throw CanonicalAdoptionFailure.injected
    }

    func acceptShare(at url: URL) throws -> ProfileID {
        _ = url
        throw CanonicalAdoptionFailure.injected
    }

    func didMarkApplied() -> Bool { applied }
    func sendCount() -> Int { sends }
    func fetchCount() -> Int { fetches }
    func resumeCount() -> Int { resumes }
    func confirmationCount() -> Int { confirmations }
}

private struct CanonicalAdoptionClock: AppClock {
    let now: Date
}
