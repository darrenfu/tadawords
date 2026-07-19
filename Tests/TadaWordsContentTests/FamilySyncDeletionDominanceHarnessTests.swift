import Foundation
import TadaWordsContent
import TadaWordsDomain
import XCTest

final class FamilySyncDeletionDominanceHarnessTests: XCTestCase {
    func testTerminalDeletionDominatesLaterMutableAndImmutableRecordsAndOnlyLedgerSends()
        async throws
    {
        let fixture = try DeletionDominanceFixture()
        defer { fixture.remove() }
        let profileID = ProfileID()
        let now = Date(timeIntervalSince1970: 2_174_000_000)
        let tombstone = deletionDominanceRecord(
            profileID: profileID,
            name: "profile-\(profileID)",
            kind: .profileDeletion,
            payload: "minimal-deletion-ledger",
            isDeleted: true,
            revision: .init(counter: 1, deviceID: "owner-device"),
            at: now
        )
        let staleLaterRecords = [
            deletionDominanceRecord(
                profileID: profileID,
                name: "profile-\(profileID)",
                kind: .profile,
                payload: "late-profile-edit",
                revision: .init(counter: 999, deviceID: "stale-device"),
                at: now.addingTimeInterval(10_000)
            ),
            deletionDominanceRecord(
                profileID: profileID,
                name: "word-dog",
                kind: .wordPoolEntry,
                payload: "late-word-edit",
                revision: .init(counter: 999, deviceID: "stale-device"),
                at: now.addingTimeInterval(10_000)
            ),
            deletionDominanceRecord(
                profileID: profileID,
                name: "attempt-stale-uuid",
                kind: .attempt,
                payload: "late-immutable-attempt",
                revision: .init(counter: 999, deviceID: "stale-device"),
                at: now.addingTimeInterval(10_000)
            ),
            deletionDominanceRecord(
                profileID: profileID,
                name: "attempt-correction-stale-uuid",
                kind: .attemptCorrection,
                payload: "late-immutable-correction",
                revision: .init(counter: 999, deviceID: "stale-device"),
                at: now.addingTimeInterval(10_000)
            ),
        ]
        let store = DeletionDominanceStore(
            profileID: profileID,
            records: [tombstone]
        )
        let transport = DeletionDominanceTransport(
            fetchedRecords: staleLaterRecords
        )
        let coordinator = LocalFirstFamilySyncCoordinator(
            store: store,
            transport: transport,
            preferenceRepository: InMemoryFamilySyncPreferenceRepository(
                isEnabled: true
            ),
            journalRepository: LocalJSONFamilySyncJournalRepository(
                snapshotURL: fixture.journalURL
            ),
            deviceID: "owner-device",
            clock: DeletionDominanceClock(now: now)
        )

        let status = await coordinator.synchronize()

        XCTAssertEqual(status, .synced(at: now))
        let localRecords = await store.snapshot()
        XCTAssertEqual(localRecords.count, 1)
        XCTAssertEqual(localRecords.first?.kind, .profileDeletion)
        XCTAssertEqual(localRecords.first?.isDeleted, true)
        let terminalFetches = await transport.terminalFetches()
        XCTAssertTrue(
            terminalFetches.contains([profileID]),
            "A stale device must fetch the deletion ledger before route preparation or upload"
        )
        let sent = await transport.sentOperations()
        XCTAssertFalse(sent.isEmpty)
        XCTAssertTrue(
            sent.allSatisfy { operation in
                guard case .save(let record) = operation else { return false }
                return record.profileID == profileID
                    && record.kind == .profileDeletion
                    && record.isDeleted
            },
            "After terminal deletion, no nickname, word, attempt, reward, or other payload may leave the device"
        )
    }
}

private struct DeletionDominanceFixture {
    let directory: URL
    let journalURL: URL

    init() throws {
        directory = FileManager.default.temporaryDirectory.appendingPathComponent(
            "TadaDeletionDominance-\(UUID().uuidString)",
            isDirectory: true
        )
        try FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true
        )
        journalURL = directory.appendingPathComponent("journal.json")
    }

    func remove() {
        try? FileManager.default.removeItem(at: directory)
    }
}

private struct DeletionDominanceClock: AppClock {
    let now: Date
}

private actor DeletionDominanceStore: FamilySyncRecordStore {
    private let profileID: ProfileID
    private var recordsByName: [String: FamilySyncRecord]

    init(profileID: ProfileID, records: [FamilySyncRecord]) {
        self.profileID = profileID
        recordsByName = Dictionary(
            uniqueKeysWithValues: records.map { ($0.recordName, $0) }
        )
    }

    func profileIDsForSync() async throws -> [ProfileID] { [profileID] }

    func records(for profileID: ProfileID) async throws -> [FamilySyncRecord] {
        guard profileID == self.profileID else { return [] }
        return sortedRecords()
    }

    func apply(
        _ records: [FamilySyncRecord],
        for profileID: ProfileID
    ) async throws {
        guard profileID == self.profileID else { return }
        // Deliberately permissive: the coordinator owns the terminal-deletion
        // filter this harness is exercising.
        for record in records {
            recordsByName[record.recordName] = record
        }
    }

    func isProfileDeleted(_ profileID: ProfileID) async throws -> Bool {
        guard profileID == self.profileID else { return false }
        return recordsByName.values.contains {
            $0.kind == .profileDeletion && $0.isDeleted
        }
    }

    func snapshot() -> [FamilySyncRecord] { sortedRecords() }

    private func sortedRecords() -> [FamilySyncRecord] {
        recordsByName.values.sorted { $0.recordName < $1.recordName }
    }
}

private actor DeletionDominanceTransport: FamilySyncTransport {
    nonisolated let capability: FamilySyncCapability = .iCloud
    private var pendingFetchedRecords: [FamilySyncRecord]
    private var sent: [FamilySyncPendingOperation] = []
    private var terminalFetchSets: [Set<ProfileID>] = []

    init(fetchedRecords: [FamilySyncRecord]) {
        pendingFetchedRecords = fetchedRecords
    }

    func availability() async -> FamilySyncAvailability { .available }

    func prepareProfileZone(_ profileID: ProfileID) async throws {
        _ = profileID
    }

    func fetchRecords(for profileID: ProfileID) async throws -> [FamilySyncRecord] {
        let matches = pendingFetchedRecords.filter { $0.profileID == profileID }
        pendingFetchedRecords.removeAll { $0.profileID == profileID }
        return matches
    }

    func push(
        _ records: [FamilySyncRecord],
        for profileID: ProfileID
    ) async throws {
        _ = profileID
        sent += records.map(FamilySyncPendingOperation.save)
    }

    func fetchChanges(
        for profileIDs: [ProfileID],
        terminalProfileIDs: Set<ProfileID>
    ) async throws -> FamilySyncTransportResult {
        terminalFetchSets.append(terminalProfileIDs)
        let requested = Set(profileIDs)
        let matches = pendingFetchedRecords.filter {
            requested.contains($0.profileID)
        }
        pendingFetchedRecords.removeAll { requested.contains($0.profileID) }
        return FamilySyncTransportResult(records: matches)
    }

    func sendChanges(
        _ changes: [FamilySyncPendingOperation]
    ) async throws -> FamilySyncTransportResult {
        sent += changes
        return FamilySyncTransportResult(
            acknowledged: Set(
                changes.map(FamilySyncChangeAcknowledgement.init(operation:))
            )
        )
    }

    func createShare(for profileID: ProfileID) async throws -> URL {
        _ = profileID
        return URL(string: "https://example.invalid/deletion")!
    }

    func acceptShare(at url: URL) async throws -> ProfileID {
        _ = url
        return ProfileID()
    }

    func terminalFetches() -> [Set<ProfileID>] { terminalFetchSets }

    func sentOperations() -> [FamilySyncPendingOperation] { sent }
}

private func deletionDominanceRecord(
    profileID: ProfileID,
    name: String,
    kind: FamilySyncRecordKind,
    payload: String,
    isDeleted: Bool = false,
    revision: FamilySyncLogicalRevision,
    at date: Date
) -> FamilySyncRecord {
    FamilySyncRecord(
        recordName: name,
        profileID: profileID,
        kind: kind,
        payload: Data(payload.utf8),
        updatedAt: date,
        deviceID: revision.deviceID,
        isDeleted: isDeleted,
        logicalRevision: revision
    )
}
