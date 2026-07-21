import Foundation
import TadaWordsContent
import TadaWordsDomain
import XCTest

final class LocalFirstFamilySyncCoordinatorConcurrencyTests: XCTestCase {
    func testStatusWaitsForInFlightReconciliationAndReturnsSettledStatus()
        async
    {
        let profileID = ProfileID()
        let fetchBarrier = AsyncFetchBarrier()
        let coordinator = LocalFirstFamilySyncCoordinator(
            store: ConcurrencySyncStore(profileID: profileID, records: []),
            transport: SequencedSyncTransport(
                fetchResults: [FamilySyncTransportResult()],
                fetchBarrier: fetchBarrier
            ),
            preferenceRepository: InMemoryFamilySyncPreferenceRepository(
                isEnabled: true
            ),
            clock: ConcurrencyFixedClock(now: Date(timeIntervalSince1970: 100))
        )
        let syncTask = Task { await coordinator.synchronize() }
        await fetchBarrier.waitUntilEntered()
        let completion = AsyncCompletionProbe()
        let statusTask = Task {
            let status = await coordinator.status()
            await completion.markCompleted()
            return status
        }

        await Task.yield()
        let completedWhileFetchWasSuspended = await completion.isCompleted()
        XCTAssertFalse(completedWhileFetchWasSuspended)

        await fetchBarrier.resume()
        let status = await statusTask.value
        _ = await syncTask.value

        XCTAssertEqual(status, .synced(at: Date(timeIntervalSince1970: 100)))
    }

    func testConcurrentSynchronizeWaitsForSettledStatus() async {
        let profileID = ProfileID()
        let fetchBarrier = AsyncFetchBarrier()
        let coordinator = LocalFirstFamilySyncCoordinator(
            store: ConcurrencySyncStore(profileID: profileID, records: []),
            transport: SequencedSyncTransport(
                fetchResults: [
                    FamilySyncTransportResult(),
                    FamilySyncTransportResult(),
                ],
                fetchBarrier: fetchBarrier
            ),
            preferenceRepository: InMemoryFamilySyncPreferenceRepository(
                isEnabled: true
            ),
            clock: ConcurrencyFixedClock(now: Date(timeIntervalSince1970: 100))
        )
        let firstSync = Task { await coordinator.synchronize() }
        await fetchBarrier.waitUntilEntered()
        let secondSync = Task { await coordinator.synchronize() }

        await fetchBarrier.resume()
        let firstStatus = await firstSync.value
        let secondStatus = await secondSync.value

        XCTAssertEqual(firstStatus, .synced(at: Date(timeIntervalSince1970: 100)))
        XCTAssertEqual(secondStatus, firstStatus)
    }

    func testDurableInboxReplayFetchesServerHeadBeforeAnySend() async {
        let profileID = ProfileID()
        let local = makeRecord(
            profileID: profileID,
            payload: "local",
            revision: .init(counter: 0, deviceID: "raw")
        )
        let remote = makeRecord(
            profileID: profileID,
            payload: "remote",
            revision: .init(counter: 2, deviceID: "cloud")
        )
        let receiptID = UUID()
        let store = ConcurrencySyncStore(profileID: profileID, records: [local])
        let transport = SequencedSyncTransport(
            fetchResults: [
                FamilySyncTransportResult(
                    records: [remote],
                    receiptIDs: [receiptID],
                    reachedServerHead: false,
                    replayedDurableInbox: true
                ),
                FamilySyncTransportResult(reachedServerHead: true),
            ]
        )
        let coordinator = LocalFirstFamilySyncCoordinator(
            store: store,
            transport: transport,
            preferenceRepository: InMemoryFamilySyncPreferenceRepository(
                isEnabled: true
            ),
            deviceID: "local-device",
            clock: ConcurrencyFixedClock(now: Date(timeIntervalSince1970: 100))
        )

        _ = await coordinator.synchronize()

        let events = await transport.events()
        let stored = await store.currentRecords()
        XCTAssertEqual(
            events,
            ["fetch", "ack:\(receiptID)", "fetch"]
        )
        XCTAssertEqual(stored, [remote])
    }

    func testSameRevisionDifferentChecksumFailsWithoutAckOrSend() async {
        let profileID = ProfileID()
        let local = makeRecord(
            profileID: profileID,
            payload: "local",
            revision: .init(counter: 0, deviceID: "raw")
        )
        let remote = makeRecord(
            profileID: profileID,
            payload: "different-bytes",
            revision: .init(counter: 1, deviceID: "local-device")
        )
        let receiptID = UUID()
        let key = FamilySyncChangeKey(
            profileID: profileID,
            recordName: remote.recordName
        )
        let transport = SequencedSyncTransport(
            fetchResults: [
                FamilySyncTransportResult(
                    records: [remote],
                    receiptIDs: [receiptID],
                    receipts: [
                        FamilySyncFetchedReceipt(
                            id: receiptID,
                            key: key,
                            operation: .save,
                            revision: remote.logicalRevision
                        )
                    ]
                )
            ]
        )
        let coordinator = LocalFirstFamilySyncCoordinator(
            store: ConcurrencySyncStore(profileID: profileID, records: [local]),
            transport: transport,
            preferenceRepository: InMemoryFamilySyncPreferenceRepository(
                isEnabled: true
            ),
            deviceID: "local-device"
        )

        let status = await coordinator.synchronize()

        guard case .failed = status else {
            return XCTFail("Expected conflicting logical revision to fail closed")
        }
        let events = await transport.events()
        XCTAssertEqual(events, ["fetch", "quarantine:conflict:\(receiptID)"])
    }

    func testOptOutClosesGateBeforeSuspendedFetchCanResume() async throws {
        let profileID = ProfileID()
        let fetchBarrier = AsyncFetchBarrier()
        let transport = SequencedSyncTransport(
            fetchResults: [FamilySyncTransportResult()],
            fetchBarrier: fetchBarrier
        )
        let coordinator = LocalFirstFamilySyncCoordinator(
            store: ConcurrencySyncStore(profileID: profileID, records: []),
            transport: transport,
            preferenceRepository: InMemoryFamilySyncPreferenceRepository(
                isEnabled: true
            )
        )
        let syncTask = Task { await coordinator.synchronize() }
        await fetchBarrier.waitUntilEntered()

        let disabled = try await coordinator.setEnabled(false)
        await fetchBarrier.resume()
        _ = await syncTask.value

        guard case .optedOut = disabled else {
            return XCTFail("Expected opted-out status")
        }
        let isEnabled = await coordinator.isEnabled()
        let events = await transport.events()
        XCTAssertFalse(isEnabled)
        XCTAssertFalse(events.contains("send"))
    }

    func testFirstRunDisableWaitsForAcceptedApplyToReachQuiescence()
        async throws
    {
        let profileID = ProfileID()
        let applyBarrier = AsyncFetchBarrier()
        let remote = makeRecord(
            profileID: profileID,
            payload: "account-a",
            revision: .init(counter: 2, deviceID: "cloud-a")
        )
        let store = ConcurrencySyncStore(
            profileID: profileID,
            records: [],
            applyBarrier: applyBarrier
        )
        let transport = SequencedSyncTransport(
            fetchResults: [FamilySyncTransportResult(records: [remote])]
        )
        let coordinator = LocalFirstFamilySyncCoordinator(
            store: store,
            transport: transport,
            preferenceRepository: InMemoryFamilySyncPreferenceRepository(
                isEnabled: true
            )
        )
        let syncTask = Task { await coordinator.synchronize() }
        await applyBarrier.waitUntilEntered()
        let completion = AsyncCompletionProbe()
        let disableTask = Task {
            let status = try await coordinator.disableAndAwaitQuiescence()
            await completion.markCompleted()
            return status
        }
        for _ in 0..<100 {
            if await transport.events().contains("suspend") { break }
            await Task.yield()
        }

        let eventsBeforeResume = await transport.events()
        let completedBeforeResume = await completion.isCompleted()
        XCTAssertTrue(eventsBeforeResume.contains("suspend"))
        XCTAssertFalse(completedBeforeResume)
        await applyBarrier.resume()
        let disabled = try await disableTask.value
        _ = await syncTask.value

        guard case .optedOut = disabled else {
            return XCTFail("Expected the discovery fence to stay opted out")
        }
        let completedAfterResume = await completion.isCompleted()
        let stored = await store.currentRecords()
        XCTAssertTrue(completedAfterResume)
        XCTAssertEqual(stored, [remote])
    }

    func testPoisonRecordIsQuarantinedWithoutBlockingGoodRecord() async {
        let profileID = ProfileID()
        let good = makeRecord(
            profileID: profileID,
            recordName: "good",
            payload: "good",
            revision: .init(counter: 2, deviceID: "cloud")
        )
        let poison = makeRecord(
            profileID: profileID,
            recordName: "poison",
            payload: "valid-envelope-invalid-content",
            revision: .init(counter: 3, deviceID: "cloud")
        )
        let goodReceipt = UUID()
        let poisonReceipt = UUID()
        let transport = SequencedSyncTransport(
            fetchResults: [
                FamilySyncTransportResult(
                    records: [good, poison],
                    receipts: [
                        receipt(goodReceipt, record: good),
                        receipt(poisonReceipt, record: poison),
                    ]
                )
            ]
        )
        let store = ConcurrencySyncStore(
            profileID: profileID,
            records: [],
            rejectedRecordName: poison.recordName
        )
        let coordinator = LocalFirstFamilySyncCoordinator(
            store: store,
            transport: transport,
            preferenceRepository: InMemoryFamilySyncPreferenceRepository(
                isEnabled: true
            )
        )

        let status = await coordinator.synchronize()

        guard case .failed = status else {
            return XCTFail("Quarantine must remain visible in sync status")
        }
        let stored = await store.currentRecords()
        XCTAssertEqual(stored, [good])
        let events = await transport.events()
        XCTAssertTrue(
            events.contains("quarantine:compatibility:\(poisonReceipt)")
        )
        XCTAssertTrue(events.contains("ack:\(goodReceipt)"))
        XCTAssertFalse(events.contains("ack:\(poisonReceipt)"))
    }

    private func makeRecord(
        profileID: ProfileID,
        recordName: String? = nil,
        payload: String,
        revision: FamilySyncLogicalRevision
    ) -> FamilySyncRecord {
        FamilySyncRecord(
            recordName: recordName ?? "profile-\(profileID)",
            profileID: profileID,
            kind: .profile,
            payload: Data(payload.utf8),
            updatedAt: Date(timeIntervalSince1970: 10),
            deviceID: revision.deviceID,
            logicalRevision: revision
        )
    }

    private func receipt(
        _ id: UUID,
        record: FamilySyncRecord
    ) -> FamilySyncFetchedReceipt {
        FamilySyncFetchedReceipt(
            id: id,
            key: FamilySyncChangeKey(
                profileID: record.profileID,
                recordName: record.recordName
            ),
            operation: .save,
            revision: record.logicalRevision
        )
    }
}

private actor ConcurrencySyncStore: FamilySyncRecordStore {
    let profileID: ProfileID
    var values: [FamilySyncRecord]
    let rejectedRecordName: String?
    let applyBarrier: AsyncFetchBarrier?

    init(
        profileID: ProfileID,
        records: [FamilySyncRecord],
        rejectedRecordName: String? = nil,
        applyBarrier: AsyncFetchBarrier? = nil
    ) {
        self.profileID = profileID
        values = records
        self.rejectedRecordName = rejectedRecordName
        self.applyBarrier = applyBarrier
    }

    func profileIDsForSync() async throws -> [ProfileID] { [profileID] }

    func records(for profileID: ProfileID) async throws -> [FamilySyncRecord] {
        values
    }

    func apply(_ records: [FamilySyncRecord], for profileID: ProfileID) async throws {
        if let applyBarrier { await applyBarrier.enterAndWait() }
        var byName = Dictionary(uniqueKeysWithValues: values.map { ($0.recordName, $0) })
        for record in records { byName[record.recordName] = record }
        values = byName.values.sorted { $0.recordName < $1.recordName }
    }

    func validate(
        _ records: [FamilySyncRecord],
        for profileID: ProfileID
    ) async throws {
        if let rejectedRecordName,
            let rejected = records.first(where: {
                $0.recordName == rejectedRecordName
            })
        {
            throw RepositoryFamilySyncError.invalidRecordPayload(
                recordName: rejected.recordName,
                kind: rejected.kind
            )
        }
    }

    func currentRecords() -> [FamilySyncRecord] { values }
}

private actor SequencedSyncTransport: FamilySyncTransport {
    nonisolated let capability = FamilySyncCapability.iCloud
    private var results: [FamilySyncTransportResult]
    private let fetchBarrier: AsyncFetchBarrier?
    private var eventLog: [String] = []

    init(
        fetchResults: [FamilySyncTransportResult],
        fetchBarrier: AsyncFetchBarrier? = nil
    ) {
        results = fetchResults
        self.fetchBarrier = fetchBarrier
    }

    func availability() async -> FamilySyncAvailability { .available }
    func prepareProfileZone(_ profileID: ProfileID) async throws {}
    func fetchRecords(for profileID: ProfileID) async throws -> [FamilySyncRecord] { [] }
    func push(_ records: [FamilySyncRecord], for profileID: ProfileID) async throws {}

    func fetchChanges(for profileIDs: [ProfileID]) async throws
        -> FamilySyncTransportResult
    {
        eventLog.append("fetch")
        if let fetchBarrier { await fetchBarrier.enterAndWait() }
        return results.isEmpty ? FamilySyncTransportResult() : results.removeFirst()
    }

    func sendChanges(_ changes: [FamilySyncPendingOperation]) async throws
        -> FamilySyncTransportResult
    {
        eventLog.append("send")
        return FamilySyncTransportResult(
            acknowledged: Set(changes.map(FamilySyncChangeAcknowledgement.init))
        )
    }

    func acknowledgeFetchedChanges(receiptIDs: Set<UUID>) async throws {
        for id in receiptIDs.sorted(by: { $0.uuidString < $1.uuidString }) {
            eventLog.append("ack:\(id)")
        }
    }

    func quarantineFetchedChanges(
        receiptIDs: Set<UUID>,
        category: FamilySyncPrivacySafeErrorCategory
    ) async throws {
        for id in receiptIDs.sorted(by: { $0.uuidString < $1.uuidString }) {
            eventLog.append("quarantine:\(category.rawValue):\(id)")
        }
    }

    func suspend() async { eventLog.append("suspend") }
    func createShare(for profileID: ProfileID) async throws -> URL {
        URL(string: "https://example.invalid")!
    }
    func acceptShare(at url: URL) async throws -> ProfileID { ProfileID() }
    func events() -> [String] { eventLog }
}

private actor AsyncFetchBarrier {
    private var entered = false
    private var released = false
    private var entryWaiters: [CheckedContinuation<Void, Never>] = []
    private var resumeContinuation: CheckedContinuation<Void, Never>?

    func enterAndWait() async {
        if released { return }
        await withCheckedContinuation { continuation in
            resumeContinuation = continuation
            entered = true
            let waiters = entryWaiters
            entryWaiters.removeAll()
            for waiter in waiters { waiter.resume() }
        }
    }

    func waitUntilEntered() async {
        if entered { return }
        await withCheckedContinuation { continuation in
            entryWaiters.append(continuation)
        }
    }

    func resume() {
        released = true
        resumeContinuation?.resume()
        resumeContinuation = nil
    }
}

private actor AsyncCompletionProbe {
    private var completed = false

    func markCompleted() {
        completed = true
    }

    func isCompleted() -> Bool {
        completed
    }
}

private struct ConcurrencyFixedClock: AppClock {
    let now: Date
}
