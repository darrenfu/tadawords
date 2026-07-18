import Foundation
import TadaWordsContent
import TadaWordsDomain
import XCTest

final class FamilySyncServerRecordChangedCoordinatorHarnessTests: XCTestCase {
    func testMutableServerWinnerConvergesInOneReconcileWithoutResend()
        async throws
    {
        let fixture = ServerRecordChangedHarnessFixture(serverWins: true)

        let status = await fixture.coordinator.synchronize()

        XCTAssertEqual(status, .synced(at: fixture.now))
        let stored = await fixture.store.record()
        let sends = await fixture.transport.sendCount()
        let events = await fixture.transport.events()
        XCTAssertEqual(stored.payload, fixture.server.payload)
        XCTAssertEqual(stored.logicalRevision, fixture.server.logicalRevision)
        XCTAssertEqual(sends, 1, "The logical server winner must not be resent")
        XCTAssertEqual(
            events,
            [
                .fetchInitialHead,
                .sendStaleClient,
                .fetchDurableServerRecord,
                .acknowledgeServerReceipt,
                .fetchFreshHead,
            ]
        )
    }

    func testMutableClientWinnerRefreshesServerStateAndRetriesInOneReconcile()
        async throws
    {
        let fixture = ServerRecordChangedHarnessFixture(serverWins: false)

        let status = await fixture.coordinator.synchronize()

        XCTAssertEqual(status, .synced(at: fixture.now))
        let stored = await fixture.store.record()
        let sends = await fixture.transport.sendCount()
        let events = await fixture.transport.events()
        XCTAssertEqual(stored.payload, fixture.local.payload)
        XCTAssertEqual(
            sends,
            2,
            "The client winner must retry once using the freshly persisted server system fields"
        )
        XCTAssertEqual(
            events,
            [
                .fetchInitialHead,
                .sendStaleClient,
                .fetchDurableServerRecord,
                .acknowledgeServerReceipt,
                .fetchFreshHead,
                .retryClientWithFreshServerFields,
            ]
        )
    }
}

private final class ServerRecordChangedHarnessFixture: @unchecked Sendable {
    let now = Date(timeIntervalSince1970: 2_160_000_000)
    let profileID = ProfileID()
    let local: FamilySyncRecord
    let server: FamilySyncRecord
    let store: ServerRecordChangedHarnessStore
    let transport: ServerRecordChangedHarnessTransport
    let coordinator: LocalFirstFamilySyncCoordinator

    init(serverWins: Bool) {
        local = FamilySyncRecord(
            recordName: "profile-stable-key",
            profileID: profileID,
            kind: .profile,
            payload: Data("client-value".utf8),
            updatedAt: now,
            deviceID: "device-a"
        )
        server = FamilySyncRecord(
            recordName: local.recordName,
            profileID: profileID,
            kind: .profile,
            payload: Data("concurrent-server-value".utf8),
            updatedAt: now.addingTimeInterval(1),
            deviceID: "device-b",
            logicalRevision: FamilySyncLogicalRevision(
                counter: serverWins ? 99 : 0,
                deviceID: "device-b"
            )
        )
        store = ServerRecordChangedHarnessStore(
            profileID: profileID,
            record: local
        )
        transport = ServerRecordChangedHarnessTransport(
            server: server,
            serverWins: serverWins
        )
        coordinator = LocalFirstFamilySyncCoordinator(
            store: store,
            transport: transport,
            preferenceRepository: InMemoryFamilySyncPreferenceRepository(
                isEnabled: true
            ),
            journalRepository: VolatileFamilySyncJournalRepository(),
            deviceID: "device-a",
            clock: ServerRecordChangedHarnessClock(now: now)
        )
    }
}

private struct ServerRecordChangedHarnessClock: AppClock {
    let now: Date
}

private actor ServerRecordChangedHarnessStore: FamilySyncRecordStore {
    private let profileID: ProfileID
    private var stored: FamilySyncRecord

    init(profileID: ProfileID, record: FamilySyncRecord) {
        self.profileID = profileID
        stored = record
    }

    func profileIDsForSync() async throws -> [ProfileID] {
        [profileID]
    }

    func records(for profileID: ProfileID) async throws -> [FamilySyncRecord] {
        profileID == self.profileID ? [stored] : []
    }

    func apply(
        _ records: [FamilySyncRecord],
        for profileID: ProfileID
    ) async throws {
        guard profileID == self.profileID, let record = records.first else { return }
        stored = record
    }

    func record() -> FamilySyncRecord {
        stored
    }
}

private actor ServerRecordChangedHarnessTransport: FamilySyncTransport {
    enum Event: Equatable {
        case fetchInitialHead
        case sendStaleClient
        case fetchDurableServerRecord
        case acknowledgeServerReceipt
        case fetchFreshHead
        case retryClientWithFreshServerFields
    }

    nonisolated let capability = FamilySyncCapability.iCloud
    private let server: FamilySyncRecord
    private let serverWins: Bool
    private let receiptID = UUID()
    private var firstHeadFetched = false
    private var conflictCommitted = false
    private var durableInboxPending = false
    private var freshHeadFetched = false
    private var sendAttempts = 0
    private var log: [Event] = []

    init(server: FamilySyncRecord, serverWins: Bool) {
        self.server = server
        self.serverWins = serverWins
    }

    func availability() async -> FamilySyncAvailability {
        .available
    }

    func prepareProfileZone(_ profileID: ProfileID) async throws {
        _ = profileID
    }

    func fetchRecords(for profileID: ProfileID) async throws -> [FamilySyncRecord] {
        profileID == server.profileID && conflictCommitted ? [server] : []
    }

    func push(
        _ records: [FamilySyncRecord],
        for profileID: ProfileID
    ) async throws {
        _ = records
        _ = profileID
    }

    func fetchChanges(
        for profileIDs: [ProfileID]
    ) async throws -> FamilySyncTransportResult {
        guard profileIDs.contains(server.profileID) else {
            return FamilySyncTransportResult()
        }
        if !firstHeadFetched {
            firstHeadFetched = true
            log.append(.fetchInitialHead)
            return FamilySyncTransportResult()
        }
        if durableInboxPending {
            log.append(.fetchDurableServerRecord)
            return FamilySyncTransportResult(
                records: [server],
                receipts: [
                    FamilySyncFetchedReceipt(
                        id: receiptID,
                        key: FamilySyncChangeKey(
                            profileID: server.profileID,
                            recordName: server.recordName
                        ),
                        operation: .save,
                        revision: server.logicalRevision
                    )
                ],
                reachedServerHead: false,
                replayedDurableInbox: true
            )
        }
        freshHeadFetched = true
        log.append(.fetchFreshHead)
        return FamilySyncTransportResult(records: [server])
    }

    func acknowledgeFetchedChanges(receiptIDs: Set<UUID>) async throws {
        guard receiptIDs.contains(receiptID) else { return }
        durableInboxPending = false
        log.append(.acknowledgeServerReceipt)
    }

    func sendChanges(
        _ changes: [FamilySyncPendingOperation]
    ) async throws -> FamilySyncTransportResult {
        XCTAssertFalse(changes.isEmpty)
        sendAttempts += 1
        if sendAttempts == 1 {
            log.append(.sendStaleClient)
            conflictCommitted = true
            durableInboxPending = true
            return FamilySyncTransportResult(
                failures: [
                    FamilySyncTransportFailure(
                        key: changes[0].key,
                        category: .conflict
                    )
                ]
            )
        }
        XCTAssertFalse(serverWins)
        XCTAssertTrue(freshHeadFetched)
        log.append(.retryClientWithFreshServerFields)
        return FamilySyncTransportResult(
            acknowledged: Set(
                changes.map(FamilySyncChangeAcknowledgement.init(operation:))
            )
        )
    }

    func createShare(for profileID: ProfileID) async throws -> URL {
        _ = profileID
        return URL(string: "https://example.invalid/server-record-changed")!
    }

    func acceptShare(at url: URL) async throws -> ProfileID {
        _ = url
        return server.profileID
    }

    func sendCount() -> Int {
        sendAttempts
    }

    func events() -> [Event] {
        log
    }
}
