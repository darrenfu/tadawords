import Foundation
import TadaWordsContent
import TadaWordsDomain
import XCTest

final class FamilySyncDurableReplayCoordinatorHarnessTests: XCTestCase {
    func testDurableInboxIsAppliedAndAcknowledgedBeforeFreshHeadFetchAndUpload()
        async throws
    {
        let fixture = try DurableReplayHarnessFixture()
        defer { fixture.remove() }
        let store = DurableReplayHarnessStore(
            profileID: fixture.profileID,
            records: [fixture.localRecord]
        )
        let transport = DurableReplayHarnessTransport(
            replayedRecord: fixture.remoteRecord
        )
        let coordinator = fixture.coordinator(
            store: store,
            transport: transport,
            now: fixture.now
        )

        let status = await coordinator.synchronize()
        let events = await transport.eventLog()

        XCTAssertEqual(status, .synced(at: fixture.now))
        XCTAssertEqual(
            events,
            [.fetchReplay, .acknowledgeReceipt, .fetchServerHead, .send]
        )
        let sent = await transport.sentOperations()
        XCTAssertEqual(sent.map(\.key.recordName), [fixture.localRecord.recordName])
        let stored = await store.snapshot()
        XCTAssertEqual(
            Set(stored.map(\.recordName)),
            [fixture.localRecord.recordName, fixture.remoteRecord.recordName]
        )
    }

    func testCrashAfterApplyBeforeReceiptAckReplaysThenFetchesHeadBeforeUpload()
        async throws
    {
        let fixture = try DurableReplayHarnessFixture()
        defer { fixture.remove() }
        let store = DurableReplayHarnessStore(
            profileID: fixture.profileID,
            records: [fixture.localRecord]
        )
        let transport = DurableReplayHarnessTransport(
            replayedRecord: fixture.remoteRecord,
            failNextReceiptAcknowledgement: true
        )
        let firstCoordinator = fixture.coordinator(
            store: store,
            transport: transport,
            now: fixture.now
        )

        let interrupted = await firstCoordinator.synchronize()
        let interruptedEvents = await transport.eventLog()
        let recordsAfterApply = await store.snapshot()
        guard case .failed = interrupted else {
            return XCTFail("Receipt-ack interruption must be surfaced and retried")
        }
        XCTAssertEqual(
            interruptedEvents,
            [.fetchReplay, .acknowledgeReceipt]
        )
        XCTAssertEqual(
            Set(recordsAfterApply.map(\.recordName)),
            [fixture.localRecord.recordName, fixture.remoteRecord.recordName]
        )

        let restartedCoordinator = fixture.coordinator(
            store: store,
            transport: transport,
            now: fixture.now.addingTimeInterval(20)
        )
        let recovered = await restartedCoordinator.synchronize()
        let recoveredEvents = await transport.eventLog()

        XCTAssertEqual(
            recovered,
            .synced(at: fixture.now.addingTimeInterval(20))
        )
        XCTAssertEqual(
            recoveredEvents,
            [
                .fetchReplay,
                .acknowledgeReceipt,
                .fetchReplay,
                .acknowledgeReceipt,
                .fetchServerHead,
                .send,
            ]
        )
    }

    func testApplyFailureDoesNotAcknowledgeReceiptAndReplaySurvivesRestart()
        async throws
    {
        let fixture = try DurableReplayHarnessFixture()
        defer { fixture.remove() }
        let store = DurableReplayHarnessStore(
            profileID: fixture.profileID,
            records: [fixture.localRecord],
            failNextApply: true
        )
        let transport = DurableReplayHarnessTransport(
            replayedRecord: fixture.remoteRecord
        )
        let firstCoordinator = fixture.coordinator(
            store: store,
            transport: transport,
            now: fixture.now
        )

        let interrupted = await firstCoordinator.synchronize()
        let interruptedEvents = await transport.eventLog()
        guard case .failed = interrupted else {
            return XCTFail("A failed local apply must leave the receipt durable")
        }
        XCTAssertEqual(interruptedEvents, [.fetchReplay])

        let restartedCoordinator = fixture.coordinator(
            store: store,
            transport: transport,
            now: fixture.now.addingTimeInterval(20)
        )
        let recovered = await restartedCoordinator.synchronize()
        let recoveredEvents = await transport.eventLog()

        XCTAssertEqual(
            recovered,
            .synced(at: fixture.now.addingTimeInterval(20))
        )
        XCTAssertEqual(
            recoveredEvents,
            [
                .fetchReplay,
                .fetchReplay,
                .acknowledgeReceipt,
                .fetchServerHead,
                .send,
            ]
        )
    }
}

private struct DurableReplayHarnessFixture {
    let directory: URL
    let profileID = ProfileID()
    let now = Date(timeIntervalSince1970: 2_130_000_000)

    init() throws {
        directory = FileManager.default.temporaryDirectory.appendingPathComponent(
            "TadaDurableReplayCoordinatorHarness-\(UUID().uuidString)",
            isDirectory: true
        )
        try FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true
        )
    }

    var localRecord: FamilySyncRecord {
        FamilySyncRecord(
            recordName: "profile-local",
            profileID: profileID,
            kind: .profile,
            payload: Data("local".utf8),
            updatedAt: now,
            deviceID: "raw-device"
        )
    }

    var remoteRecord: FamilySyncRecord {
        FamilySyncRecord(
            recordName: "word-remote",
            profileID: profileID,
            kind: .wordPoolEntry,
            payload: Data("remote".utf8),
            updatedAt: now,
            deviceID: "remote-device",
            logicalRevision: FamilySyncLogicalRevision(
                counter: 1,
                deviceID: "remote-device"
            )
        )
    }

    func coordinator(
        store: DurableReplayHarnessStore,
        transport: DurableReplayHarnessTransport,
        now: Date
    ) -> LocalFirstFamilySyncCoordinator {
        LocalFirstFamilySyncCoordinator(
            store: store,
            transport: transport,
            preferenceRepository: InMemoryFamilySyncPreferenceRepository(
                isEnabled: true
            ),
            journalRepository: LocalJSONFamilySyncJournalRepository(
                snapshotURL: directory.appendingPathComponent("journal.json")
            ),
            deviceID: "local-device",
            clock: DurableReplayHarnessClock(now: now)
        )
    }

    func remove() {
        try? FileManager.default.removeItem(at: directory)
    }
}

private struct DurableReplayHarnessClock: AppClock {
    let now: Date
}

private enum DurableReplayHarnessError: Error {
    case applyInterrupted
    case receiptAcknowledgementInterrupted
}

private actor DurableReplayHarnessStore: FamilySyncRecordStore {
    private let profileID: ProfileID
    private var recordsByName: [String: FamilySyncRecord]
    private var failNextApply: Bool

    init(
        profileID: ProfileID,
        records: [FamilySyncRecord],
        failNextApply: Bool = false
    ) {
        self.profileID = profileID
        recordsByName = Dictionary(uniqueKeysWithValues: records.map { ($0.recordName, $0) })
        self.failNextApply = failNextApply
    }

    func profileIDsForSync() async throws -> [ProfileID] {
        [profileID]
    }

    func records(for profileID: ProfileID) async throws -> [FamilySyncRecord] {
        guard profileID == self.profileID else { return [] }
        return sortedRecords()
    }

    func apply(
        _ records: [FamilySyncRecord],
        for profileID: ProfileID
    ) async throws {
        guard profileID == self.profileID else { return }
        if failNextApply {
            failNextApply = false
            throw DurableReplayHarnessError.applyInterrupted
        }
        for record in records {
            recordsByName[record.recordName] = record
        }
    }

    func snapshot() -> [FamilySyncRecord] {
        sortedRecords()
    }

    private func sortedRecords() -> [FamilySyncRecord] {
        recordsByName.values.sorted { $0.recordName < $1.recordName }
    }
}

private actor DurableReplayHarnessTransport: FamilySyncTransport {
    enum Event: Equatable {
        case fetchReplay
        case acknowledgeReceipt
        case fetchServerHead
        case send
    }

    nonisolated let capability: FamilySyncCapability = .iCloud
    private let replayedRecord: FamilySyncRecord
    private let receiptID = UUID()
    private var inboxPending = true
    private var failNextReceiptAcknowledgement: Bool
    private var events: [Event] = []
    private var sent: [FamilySyncPendingOperation] = []

    init(
        replayedRecord: FamilySyncRecord,
        failNextReceiptAcknowledgement: Bool = false
    ) {
        self.replayedRecord = replayedRecord
        self.failNextReceiptAcknowledgement = failNextReceiptAcknowledgement
    }

    func availability() async -> FamilySyncAvailability {
        .available
    }

    func prepareProfileZone(_ profileID: ProfileID) async throws {
        _ = profileID
    }

    func fetchRecords(for profileID: ProfileID) async throws -> [FamilySyncRecord] {
        guard profileID == replayedRecord.profileID else { return [] }
        return [replayedRecord]
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
        _ = profileIDs
        if inboxPending {
            events.append(.fetchReplay)
            return FamilySyncTransportResult(
                records: [replayedRecord],
                receipts: [
                    FamilySyncFetchedReceipt(
                        id: receiptID,
                        key: FamilySyncChangeKey(
                            profileID: replayedRecord.profileID,
                            recordName: replayedRecord.recordName
                        ),
                        operation: .save,
                        revision: replayedRecord.logicalRevision
                    )
                ],
                reachedServerHead: false,
                replayedDurableInbox: true
            )
        }
        events.append(.fetchServerHead)
        return FamilySyncTransportResult(records: [replayedRecord])
    }

    func acknowledgeFetchedChanges(receiptIDs: Set<UUID>) async throws {
        guard receiptIDs.contains(receiptID) else { return }
        events.append(.acknowledgeReceipt)
        if failNextReceiptAcknowledgement {
            failNextReceiptAcknowledgement = false
            throw DurableReplayHarnessError.receiptAcknowledgementInterrupted
        }
        inboxPending = false
    }

    func sendChanges(
        _ changes: [FamilySyncPendingOperation]
    ) async throws -> FamilySyncTransportResult {
        events.append(.send)
        sent += changes
        return FamilySyncTransportResult(
            acknowledged: Set(
                changes.map(FamilySyncChangeAcknowledgement.init(operation:))
            )
        )
    }

    func createShare(for profileID: ProfileID) async throws -> URL {
        _ = profileID
        return URL(string: "https://example.invalid/durable-replay")!
    }

    func acceptShare(at url: URL) async throws -> ProfileID {
        _ = url
        return replayedRecord.profileID
    }

    func eventLog() -> [Event] {
        events
    }

    func sentOperations() -> [FamilySyncPendingOperation] {
        sent
    }
}
