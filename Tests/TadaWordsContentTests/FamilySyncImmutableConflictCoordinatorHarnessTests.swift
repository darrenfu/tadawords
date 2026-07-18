import Foundation
import TadaWordsContent
import TadaWordsDomain
import XCTest

final class FamilySyncImmutableConflictCoordinatorHarnessTests: XCTestCase {
    func testHigherRevisionImmutableAttemptConflictIsQuarantinedWithoutOverwriteOrUpload()
        async throws
    {
        let profileID = ProfileID()
        let key = FamilySyncChangeKey(
            profileID: profileID,
            recordName: "attempt-shared-uuid"
        )
        let local = FamilySyncRecord(
            recordName: key.recordName,
            profileID: profileID,
            kind: .attempt,
            payload: Data("device-a-attempt".utf8),
            updatedAt: Date(timeIntervalSince1970: 2_150_000_000),
            deviceID: "device-a"
        )
        let remote = FamilySyncRecord(
            recordName: key.recordName,
            profileID: profileID,
            kind: .attempt,
            payload: Data("different-bytes-for-same-immutable-uuid".utf8),
            updatedAt: Date(timeIntervalSince1970: 2_150_000_100),
            deviceID: "device-b",
            logicalRevision: FamilySyncLogicalRevision(
                counter: 99,
                deviceID: "device-b"
            )
        )
        let receiptID = UUID()
        let store = ImmutableConflictHarnessStore(
            profileID: profileID,
            local: local
        )
        let transport = ImmutableConflictHarnessTransport(
            remote: remote,
            receiptID: receiptID
        )
        let coordinator = LocalFirstFamilySyncCoordinator(
            store: store,
            transport: transport,
            preferenceRepository: InMemoryFamilySyncPreferenceRepository(
                isEnabled: true
            ),
            journalRepository: VolatileFamilySyncJournalRepository(),
            deviceID: "device-a",
            clock: ImmutableConflictHarnessClock(
                now: Date(timeIntervalSince1970: 2_150_000_200)
            )
        )

        let status = await coordinator.synchronize()

        guard case .failed = status else {
            return XCTFail("An immutable UUID payload conflict must surface as quarantined")
        }
        let stored = await store.currentRecord()
        let applyCount = await store.applyCount()
        let quarantines = await transport.quarantines()
        let sent = await transport.sentChanges()
        let acknowledged = await transport.acknowledgedReceiptSets()
        XCTAssertEqual(stored.payload, local.payload)
        XCTAssertEqual(applyCount, 0)
        XCTAssertEqual(
            quarantines,
            [
                ImmutableConflictHarnessTransport.Quarantine(
                    receiptIDs: [receiptID],
                    category: .conflict
                )
            ]
        )
        XCTAssertTrue(sent.isEmpty)
        XCTAssertTrue(acknowledged.allSatisfy(\.isEmpty))
    }
}

private struct ImmutableConflictHarnessClock: AppClock {
    let now: Date
}

private actor ImmutableConflictHarnessStore: FamilySyncRecordStore {
    private let profileID: ProfileID
    private var local: FamilySyncRecord
    private var applications = 0

    init(profileID: ProfileID, local: FamilySyncRecord) {
        self.profileID = profileID
        self.local = local
    }

    func profileIDsForSync() async throws -> [ProfileID] {
        [profileID]
    }

    func records(for profileID: ProfileID) async throws -> [FamilySyncRecord] {
        profileID == self.profileID ? [local] : []
    }

    func apply(
        _ records: [FamilySyncRecord],
        for profileID: ProfileID
    ) async throws {
        guard profileID == self.profileID else { return }
        applications += 1
        if let record = records.first { local = record }
    }

    func currentRecord() -> FamilySyncRecord {
        local
    }

    func applyCount() -> Int {
        applications
    }
}

private actor ImmutableConflictHarnessTransport: FamilySyncTransport {
    struct Quarantine: Equatable {
        let receiptIDs: Set<UUID>
        let category: FamilySyncPrivacySafeErrorCategory
    }

    nonisolated let capability = FamilySyncCapability.iCloud
    private let remote: FamilySyncRecord
    private let receiptID: UUID
    private var quarantined: [Quarantine] = []
    private var sent: [FamilySyncPendingOperation] = []
    private var acknowledged: [Set<UUID>] = []

    init(remote: FamilySyncRecord, receiptID: UUID) {
        self.remote = remote
        self.receiptID = receiptID
    }

    func availability() async -> FamilySyncAvailability {
        .available
    }

    func prepareProfileZone(_ profileID: ProfileID) async throws {
        _ = profileID
    }

    func fetchRecords(for profileID: ProfileID) async throws -> [FamilySyncRecord] {
        profileID == remote.profileID ? [remote] : []
    }

    func push(
        _ records: [FamilySyncRecord],
        for profileID: ProfileID
    ) async throws {
        _ = profileID
        sent += records.map(FamilySyncPendingOperation.save)
    }

    func fetchChanges(
        for profileIDs: [ProfileID]
    ) async throws -> FamilySyncTransportResult {
        guard profileIDs.contains(remote.profileID) else {
            return FamilySyncTransportResult()
        }
        return FamilySyncTransportResult(
            records: [remote],
            receipts: [
                FamilySyncFetchedReceipt(
                    id: receiptID,
                    key: FamilySyncChangeKey(
                        profileID: remote.profileID,
                        recordName: remote.recordName
                    ),
                    operation: .save,
                    revision: remote.logicalRevision
                )
            ]
        )
    }

    func quarantineFetchedChanges(
        receiptIDs: Set<UUID>,
        category: FamilySyncPrivacySafeErrorCategory
    ) async throws {
        quarantined.append(
            Quarantine(receiptIDs: receiptIDs, category: category)
        )
    }

    func acknowledgeFetchedChanges(receiptIDs: Set<UUID>) async throws {
        acknowledged.append(receiptIDs)
    }

    func sendChanges(
        _ changes: [FamilySyncPendingOperation]
    ) async throws -> FamilySyncTransportResult {
        sent += changes
        return FamilySyncTransportResult()
    }

    func createShare(for profileID: ProfileID) async throws -> URL {
        _ = profileID
        return URL(string: "https://example.invalid/immutable-conflict")!
    }

    func acceptShare(at url: URL) async throws -> ProfileID {
        _ = url
        return remote.profileID
    }

    func quarantines() -> [Quarantine] {
        quarantined
    }

    func sentChanges() -> [FamilySyncPendingOperation] {
        sent
    }

    func acknowledgedReceiptSets() -> [Set<UUID>] {
        acknowledged
    }
}
