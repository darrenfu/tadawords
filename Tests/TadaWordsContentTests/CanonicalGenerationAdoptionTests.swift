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
    private var records: [FamilySyncRecord] = []
    private var replacements = 0
    private let failReplacement: Bool

    init(failReplacement: Bool = false) {
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
    private var applied = false
    private var sends = 0

    init(snapshot: FamilySyncCanonicalGenerationSnapshot) {
        self.snapshot = snapshot
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
        -> FamilySyncCanonicalGenerationSnapshot?
    {
        snapshot
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
        return FamilySyncTransportResult(reachedServerHead: true)
    }

    func sendChanges(
        _ changes: [FamilySyncPendingOperation]
    ) -> FamilySyncTransportResult {
        sends += 1
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
}

private struct CanonicalAdoptionClock: AppClock {
    let now: Date
}
