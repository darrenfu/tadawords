import Foundation
import TadaWordsContent
import TadaWordsDomain
import XCTest

final class FamilySyncTwoDeviceFaultHarnessTests: XCTestCase {
    func testTwoDevicesFetchBeforeSendAndConvergeWithDuplicateReorderedFetches()
        async throws
    {
        let fixture = try TwoDeviceHarnessFixture()
        defer { fixture.remove() }
        let now = Date(timeIntervalSince1970: 2_110_000_000)
        let profileID = ProfileID()
        let cloud = FamilySyncHarnessCloud()
        let storeA = FamilySyncHarnessStore(
            profileID: profileID,
            records: [
                harnessRecord(
                    profileID: profileID,
                    name: "profile",
                    kind: .profile,
                    payload: "A-profile",
                    at: now
                ),
                harnessRecord(
                    profileID: profileID,
                    name: "word-dog",
                    kind: .wordPoolEntry,
                    payload: "A-dog",
                    at: now
                ),
            ]
        )
        let storeB = FamilySyncHarnessStore(
            profileID: profileID,
            records: [
                harnessRecord(
                    profileID: profileID,
                    name: "profile",
                    kind: .profile,
                    payload: "B-profile",
                    at: now
                ),
                harnessRecord(
                    profileID: profileID,
                    name: "word-dog",
                    kind: .wordPoolEntry,
                    payload: "B-dog",
                    at: now
                ),
            ]
        )
        let transportA = FamilySyncHarnessTransport(cloud: cloud)
        let transportB = FamilySyncHarnessTransport(
            cloud: cloud,
            duplicateAndReverseFetches: true
        )
        let coordinatorA = fixture.coordinator(
            store: storeA,
            transport: transportA,
            deviceID: "device-a",
            journalName: "a.json",
            now: now
        )
        let coordinatorB = fixture.coordinator(
            store: storeB,
            transport: transportB,
            deviceID: "device-b",
            journalName: "b.json",
            now: now
        )

        _ = await coordinatorA.synchronize()
        _ = await coordinatorB.synchronize()
        let finalStatus = await coordinatorA.synchronize()

        XCTAssertEqual(finalStatus, .synced(at: now))
        let recordsA = await storeA.snapshot()
        let recordsB = await storeB.snapshot()
        let cloudRecords = await cloud.snapshot(account: "family")
        XCTAssertEqual(
            FamilySyncRecordSetFingerprint(records: recordsA),
            FamilySyncRecordSetFingerprint(records: recordsB)
        )
        XCTAssertEqual(
            FamilySyncRecordSetFingerprint(records: recordsA),
            FamilySyncRecordSetFingerprint(records: cloudRecords)
        )
        XCTAssertEqual(
            recordsA.map(harnessPayload).sorted(),
            ["B-dog", "B-profile"]
        )
        assertEverySendHasEarlierFetch(await transportA.eventLog())
        assertEverySendHasEarlierFetch(await transportB.eventLog())
        let returnedDuplicateBatch = await transportB.didReturnDuplicateReorderedBatch()
        XCTAssertTrue(returnedDuplicateBatch)
    }

    func testLocalMutationBetweenFetchAndCompareApplyWinsTheRestartedPass()
        async throws
    {
        let fixture = try TwoDeviceHarnessFixture()
        defer { fixture.remove() }
        let now = Date(timeIntervalSince1970: 2_110_000_100)
        let profileID = ProfileID()
        let remote = harnessRecord(
            profileID: profileID,
            name: "profile",
            kind: .profile,
            payload: "remote",
            at: now,
            revision: FamilySyncLogicalRevision(counter: 1, deviceID: "device-z")
        )
        let cloud = FamilySyncHarnessCloud()
        await cloud.seed([remote], account: "family")
        let store = FamilySyncHarnessStore(
            profileID: profileID,
            records: [
                harnessRecord(
                    profileID: profileID,
                    name: "profile",
                    kind: .profile,
                    payload: "initial-local",
                    at: now
                )
            ]
        )
        await store.injectMutationBeforeNextConditionalApply(
            harnessRecord(
                profileID: profileID,
                name: "profile",
                kind: .profile,
                payload: "local-during-fetch",
                at: now.addingTimeInterval(1)
            )
        )
        let transport = FamilySyncHarnessTransport(cloud: cloud)
        let coordinator = fixture.coordinator(
            store: store,
            transport: transport,
            deviceID: "device-a",
            journalName: "cas.json",
            now: now.addingTimeInterval(2)
        )

        let status = await coordinator.synchronize()

        XCTAssertEqual(status, .synced(at: now.addingTimeInterval(2)))
        let rejectionCount = await store.conditionalApplyRejectionCount()
        XCTAssertEqual(rejectionCount, 1)
        let local = await store.snapshot()
        let server = await cloud.snapshot(account: "family")
        XCTAssertEqual(
            FamilySyncRecordSetFingerprint(records: local),
            FamilySyncRecordSetFingerprint(records: server)
        )
        XCTAssertEqual(local.map(harnessPayload), ["local-during-fetch"])
        let events = await transport.eventLog()
        XCTAssertEqual(events.prefix(3), [.fetch, .fetch, .send])
    }

    func testAccountSwitchBlocksUploadUntilParentConfirmsNewAccount() async throws {
        let fixture = try TwoDeviceHarnessFixture()
        defer { fixture.remove() }
        let now = Date(timeIntervalSince1970: 2_110_000_200)
        let profileID = ProfileID()
        let cloud = FamilySyncHarnessCloud()
        let store = FamilySyncHarnessStore(
            profileID: profileID,
            records: [
                harnessRecord(
                    profileID: profileID,
                    name: "profile",
                    kind: .profile,
                    payload: "Mia",
                    at: now
                )
            ]
        )
        let transport = FamilySyncHarnessTransport(cloud: cloud)
        let coordinator = fixture.coordinator(
            store: store,
            transport: transport,
            deviceID: "device-a",
            journalName: "account.json",
            now: now
        )
        _ = await coordinator.synchronize()
        await transport.simulateAccountSwitch(to: "new-family")
        let eventCountBeforeSwitch = await transport.eventLog().count

        let firstBlocked = await coordinator.synchronize()
        let secondBlocked = await coordinator.synchronize()
        let blockedEvents = Array(
            await transport.eventLog().dropFirst(eventCountBeforeSwitch)
        )

        guard case .iCloudUnavailable = firstBlocked,
            case .iCloudUnavailable = secondBlocked
        else {
            return XCTFail("An unconfirmed account switch must stay blocked")
        }
        XCTAssertEqual(blockedEvents, [.fetch, .fetch])
        let unconfirmedAccountRecords = await cloud.snapshot(account: "new-family")
        XCTAssertTrue(unconfirmedAccountRecords.isEmpty)

        let confirmedStatus = try await coordinator.setEnabled(true)
        XCTAssertEqual(confirmedStatus, .synced(at: now))
        let newAccountRecords = await cloud.snapshot(account: "new-family")
        XCTAssertEqual(newAccountRecords.map(harnessPayload), ["Mia"])
        let finalEvents = await transport.eventLog()
        let confirmationIndex = try XCTUnwrap(finalEvents.lastIndex(of: .confirmAccount))
        let sendIndex = try XCTUnwrap(finalEvents.lastIndex(of: .send))
        XCTAssertLessThan(confirmationIndex, sendIndex)
    }

    func testAccountSwitchWhileOptedOutRequeuesAcknowledgedLocalRecordsAfterReenable()
        async throws
    {
        let fixture = try TwoDeviceHarnessFixture()
        defer { fixture.remove() }
        let now = Date(timeIntervalSince1970: 2_110_000_250)
        let profileID = ProfileID()
        let cloud = FamilySyncHarnessCloud()
        let store = FamilySyncHarnessStore(
            profileID: profileID,
            records: [
                harnessRecord(
                    profileID: profileID,
                    name: "profile",
                    kind: .profile,
                    payload: "Mia",
                    at: now
                )
            ]
        )
        let transport = FamilySyncHarnessTransport(cloud: cloud)
        let coordinator = fixture.coordinator(
            store: store,
            transport: transport,
            deviceID: "device-a",
            journalName: "opted-out-account-switch.json",
            now: now
        )

        let initialStatus = await coordinator.synchronize()
        let originalAccountPayloads = await cloud.snapshot(account: "family")
            .map(harnessPayload)
        XCTAssertEqual(initialStatus, .synced(at: now))
        XCTAssertEqual(originalAccountPayloads, ["Mia"])
        _ = try await coordinator.setEnabled(false)
        await transport.simulateAccountSwitch(to: "new-family")
        let eventCountBeforeReenable = await transport.eventLog().count

        let reenabled = try await coordinator.setEnabled(true)
        let newAccountPayloads = await cloud.snapshot(account: "new-family")
            .map(harnessPayload)
        let reenableEvents = Array(
            await transport.eventLog().dropFirst(eventCountBeforeReenable)
        )

        XCTAssertEqual(reenabled, .synced(at: now))
        XCTAssertEqual(
            newAccountPayloads,
            ["Mia"],
            "Acknowledgements from the previous iCloud account must never suppress the first upload to the newly confirmed account"
        )
        XCTAssertEqual(
            reenableEvents,
            [.confirmAccount, .fetch, .send]
        )
    }

    func testProfileTombstoneConvergesAndStaleChildDeltaCannotResurrectProfile()
        async throws
    {
        let fixture = try TwoDeviceHarnessFixture()
        defer { fixture.remove() }
        let now = Date(timeIntervalSince1970: 2_110_000_300)
        let profileID = ProfileID()
        let cloud = FamilySyncHarnessCloud()
        let initial = harnessRecord(
            profileID: profileID,
            name: "profile",
            kind: .profile,
            payload: "Mia",
            at: now
        )
        let storeA = FamilySyncHarnessStore(profileID: profileID, records: [initial])
        let storeB = FamilySyncHarnessStore(profileID: profileID, records: [initial])
        let transportA = FamilySyncHarnessTransport(cloud: cloud)
        let transportB = FamilySyncHarnessTransport(cloud: cloud)
        let coordinatorA = fixture.coordinator(
            store: storeA,
            transport: transportA,
            deviceID: "device-a",
            journalName: "delete-a.json",
            now: now
        )
        let coordinatorB = fixture.coordinator(
            store: storeB,
            transport: transportB,
            deviceID: "device-b",
            journalName: "delete-b.json",
            now: now
        )
        _ = await coordinatorA.synchronize()
        _ = await coordinatorB.synchronize()
        _ = await coordinatorA.synchronize()

        let tombstone = harnessRecord(
            profileID: profileID,
            name: "profile",
            kind: .profileDeletion,
            payload: "deleted",
            at: now.addingTimeInterval(1),
            isDeleted: true
        )
        await storeA.replaceAll(with: [tombstone])
        _ = await coordinatorA.synchronize()
        _ = await coordinatorB.synchronize()

        let deletedOnA = try await storeA.isProfileDeleted(profileID)
        let deletedOnB = try await storeB.isProfileDeleted(profileID)
        let deletedRecordsOnB = await storeB.snapshot()
        XCTAssertTrue(deletedOnA)
        XCTAssertTrue(deletedOnB)
        XCTAssertEqual(deletedRecordsOnB.map(\.kind), [.profileDeletion])

        let staleChild = harnessRecord(
            profileID: profileID,
            name: "word-stale",
            kind: .wordPoolEntry,
            payload: "stale-child",
            at: now.addingTimeInterval(-100),
            revision: FamilySyncLogicalRevision(counter: 1, deviceID: "old-device")
        )
        await cloud.seed([staleChild], account: "family")
        _ = await coordinatorB.synchronize()

        let afterStaleDelta = await storeB.snapshot()
        XCTAssertEqual(afterStaleDelta.count, 1)
        XCTAssertEqual(afterStaleDelta.first?.kind, .profileDeletion)
        XCTAssertEqual(afterStaleDelta.first?.isDeleted, true)
    }

    func testServerCommitBeforeLocalAckRecoversAfterCoordinatorRestart() async throws {
        let fixture = try TwoDeviceHarnessFixture()
        defer { fixture.remove() }
        let now = Date(timeIntervalSince1970: 2_110_000_400)
        let profileID = ProfileID()
        let cloud = FamilySyncHarnessCloud()
        let store = FamilySyncHarnessStore(
            profileID: profileID,
            records: [
                harnessRecord(
                    profileID: profileID,
                    name: "profile",
                    kind: .profile,
                    payload: "Mia",
                    at: now
                )
            ]
        )
        let firstTransport = FamilySyncHarnessTransport(
            cloud: cloud,
            dropNextAcknowledgementsAfterCommit: true
        )
        let journalURL = fixture.directory.appendingPathComponent("commit-crash.json")
        let firstCoordinator = fixture.coordinator(
            store: store,
            transport: firstTransport,
            deviceID: "device-a",
            journalURL: journalURL,
            now: now
        )

        let interruptedStatus = await firstCoordinator.synchronize()
        let recordsAfterInterruptedAck = await cloud.snapshot(account: "family")
        XCTAssertEqual(interruptedStatus, .pendingOffline(pendingCount: 1))
        XCTAssertEqual(recordsAfterInterruptedAck.count, 1)

        let restartedTransport = FamilySyncHarnessTransport(cloud: cloud)
        let restartedCoordinator = fixture.coordinator(
            store: store,
            transport: restartedTransport,
            deviceID: "device-a",
            journalURL: journalURL,
            now: now.addingTimeInterval(1)
        )
        let recoveredStatus = await restartedCoordinator.synchronize()
        let recordsAfterRecovery = await cloud.snapshot(account: "family")

        XCTAssertEqual(recoveredStatus, .synced(at: now.addingTimeInterval(1)))
        XCTAssertEqual(recordsAfterRecovery.count, 1)
        let restartedEvents = await restartedTransport.eventLog()
        XCTAssertEqual(
            restartedEvents,
            [.fetch],
            "Observing the exact committed revision at server head must durably clear the outbox without a redundant resend"
        )
        let restartedJournal = LocalJSONFamilySyncJournalRepository(
            snapshotURL: journalURL
        )
        let durableStatus = try await restartedJournal.durableStatus()
        XCTAssertEqual(durableStatus.pendingCount, 0)
    }

    private func assertEverySendHasEarlierFetch(
        _ events: [FamilySyncHarnessTransport.Event],
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        var fetchedSinceLastSend = false
        for event in events {
            switch event {
            case .fetch:
                fetchedSinceLastSend = true
            case .send:
                XCTAssertTrue(
                    fetchedSinceLastSend,
                    "Every upload must follow a fetch in the same pass: \(events)",
                    file: file,
                    line: line
                )
                fetchedSinceLastSend = false
            case .acknowledgeReceipt, .confirmAccount, .suspend:
                break
            }
        }
    }
}

private struct TwoDeviceHarnessFixture {
    let directory: URL

    init() throws {
        directory = FileManager.default.temporaryDirectory.appendingPathComponent(
            "TadaFamilySyncTwoDeviceHarness-\(UUID().uuidString)",
            isDirectory: true
        )
        try FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true
        )
    }

    func coordinator(
        store: FamilySyncHarnessStore,
        transport: FamilySyncHarnessTransport,
        deviceID: String,
        journalName: String,
        now: Date
    ) -> LocalFirstFamilySyncCoordinator {
        coordinator(
            store: store,
            transport: transport,
            deviceID: deviceID,
            journalURL: directory.appendingPathComponent(journalName),
            now: now
        )
    }

    func coordinator(
        store: FamilySyncHarnessStore,
        transport: FamilySyncHarnessTransport,
        deviceID: String,
        journalURL: URL,
        now: Date
    ) -> LocalFirstFamilySyncCoordinator {
        LocalFirstFamilySyncCoordinator(
            store: store,
            transport: transport,
            preferenceRepository: InMemoryFamilySyncPreferenceRepository(
                isEnabled: true
            ),
            journalRepository: LocalJSONFamilySyncJournalRepository(
                snapshotURL: journalURL
            ),
            deviceID: deviceID,
            clock: FamilySyncHarnessClock(now: now)
        )
    }

    func remove() {
        try? FileManager.default.removeItem(at: directory)
    }
}

private struct FamilySyncHarnessClock: AppClock {
    let now: Date
}

private actor FamilySyncHarnessStore: FamilySyncRecordStore {
    private let profileID: ProfileID
    private var recordsByName: [String: FamilySyncRecord]
    private var mutationBeforeNextConditionalApply: FamilySyncRecord?
    private var conditionalApplyRejections = 0

    init(profileID: ProfileID, records: [FamilySyncRecord]) {
        self.profileID = profileID
        recordsByName = Dictionary(uniqueKeysWithValues: records.map { ($0.recordName, $0) })
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
        applyRecords(records)
    }

    func applyIfUnchanged(
        _ records: [FamilySyncRecord],
        for profileID: ProfileID,
        expected: FamilySyncRecordSetFingerprint
    ) async throws -> Bool {
        guard profileID == self.profileID else { return false }
        if let mutationBeforeNextConditionalApply {
            recordsByName[mutationBeforeNextConditionalApply.recordName] =
                mutationBeforeNextConditionalApply
            self.mutationBeforeNextConditionalApply = nil
        }
        guard FamilySyncRecordSetFingerprint(records: sortedRecords()) == expected else {
            conditionalApplyRejections += 1
            return false
        }
        applyRecords(records)
        return true
    }

    func isProfileDeleted(_ profileID: ProfileID) async throws -> Bool {
        guard profileID == self.profileID else { return false }
        return recordsByName.values.contains {
            $0.kind == .profileDeletion && $0.isDeleted
        }
    }

    func injectMutationBeforeNextConditionalApply(_ record: FamilySyncRecord) {
        mutationBeforeNextConditionalApply = record
    }

    func replaceAll(with records: [FamilySyncRecord]) {
        recordsByName = Dictionary(uniqueKeysWithValues: records.map { ($0.recordName, $0) })
    }

    func snapshot() -> [FamilySyncRecord] {
        sortedRecords()
    }

    func conditionalApplyRejectionCount() -> Int {
        conditionalApplyRejections
    }

    private func applyRecords(_ records: [FamilySyncRecord]) {
        if let tombstone = records.first(where: {
            $0.kind == .profileDeletion && $0.isDeleted
        }) {
            recordsByName = [tombstone.recordName: tombstone]
            return
        }
        guard
            !recordsByName.values.contains(where: {
                $0.kind == .profileDeletion && $0.isDeleted
            })
        else { return }
        for record in records {
            recordsByName[record.recordName] = record
        }
    }

    private func sortedRecords() -> [FamilySyncRecord] {
        recordsByName.values.sorted { $0.recordName < $1.recordName }
    }
}

private actor FamilySyncHarnessCloud {
    private var recordsByAccount: [String: [FamilySyncChangeKey: FamilySyncRecord]] = [:]

    func seed(_ records: [FamilySyncRecord], account: String) {
        var current = recordsByAccount[account, default: [:]]
        for record in records {
            current[
                FamilySyncChangeKey(
                    profileID: record.profileID,
                    recordName: record.recordName
                )
            ] = record
        }
        recordsByAccount[account] = current
    }

    func snapshot(
        account: String,
        profileIDs: Set<ProfileID>? = nil
    ) -> [FamilySyncRecord] {
        recordsByAccount[account, default: [:]].values
            .filter { profileIDs?.contains($0.profileID) ?? true }
            .sorted {
                if $0.profileID != $1.profileID {
                    return $0.profileID.description < $1.profileID.description
                }
                return $0.recordName < $1.recordName
            }
    }

    func apply(
        _ changes: [FamilySyncPendingOperation],
        account: String
    ) -> FamilySyncTransportResult {
        var current = recordsByAccount[account, default: [:]]
        var acknowledgements: Set<FamilySyncChangeAcknowledgement> = []
        var failures: [FamilySyncTransportFailure] = []
        for operation in changes {
            switch operation {
            case .save(let incoming):
                let existing = current[operation.key]
                if let existing,
                    existing.logicalRevision == incoming.logicalRevision,
                    existing.payloadChecksum != incoming.payloadChecksum
                {
                    failures.append(
                        FamilySyncTransportFailure(
                            key: operation.key,
                            category: .conflict
                        )
                    )
                    continue
                }
                let winner = FamilySyncConflictResolver.resolved(
                    local: existing,
                    remote: incoming
                )
                if winner == incoming {
                    current[operation.key] = incoming
                    acknowledgements.insert(
                        FamilySyncChangeAcknowledgement(operation: operation)
                    )
                } else {
                    failures.append(
                        FamilySyncTransportFailure(
                            key: operation.key,
                            category: .conflict
                        )
                    )
                }
            case .delete:
                current.removeValue(forKey: operation.key)
                acknowledgements.insert(
                    FamilySyncChangeAcknowledgement(operation: operation)
                )
            }
        }
        recordsByAccount[account] = current
        return FamilySyncTransportResult(
            acknowledged: acknowledgements,
            failures: failures
        )
    }
}

private actor FamilySyncHarnessTransport: FamilySyncTransport {
    enum Event: Equatable {
        case fetch
        case acknowledgeReceipt
        case send
        case confirmAccount
        case suspend
    }

    nonisolated let capability: FamilySyncCapability = .iCloud
    private let cloud: FamilySyncHarnessCloud
    private let duplicateAndReverseFetches: Bool
    private var dropNextAcknowledgementsAfterCommit: Bool
    private var currentAccount = "family"
    private var accountConfirmationRequired = false
    private var accountChange: FamilySyncAccountChange = .switchedAccounts
    private var events: [Event] = []
    private var returnedDuplicateReorderedBatch = false

    init(
        cloud: FamilySyncHarnessCloud,
        duplicateAndReverseFetches: Bool = false,
        dropNextAcknowledgementsAfterCommit: Bool = false
    ) {
        self.cloud = cloud
        self.duplicateAndReverseFetches = duplicateAndReverseFetches
        self.dropNextAcknowledgementsAfterCommit = dropNextAcknowledgementsAfterCommit
    }

    func availability() async -> FamilySyncAvailability {
        .available
    }

    func prepareProfileZone(_ profileID: ProfileID) async throws {
        _ = profileID
    }

    func fetchRecords(for profileID: ProfileID) async throws -> [FamilySyncRecord] {
        await cloud.snapshot(account: currentAccount, profileIDs: [profileID])
    }

    func push(
        _ records: [FamilySyncRecord],
        for profileID: ProfileID
    ) async throws {
        _ = profileID
        _ = await cloud.apply(records.map(FamilySyncPendingOperation.save), account: currentAccount)
    }

    func fetchChanges(
        for profileIDs: [ProfileID]
    ) async throws -> FamilySyncTransportResult {
        events.append(.fetch)
        guard !accountConfirmationRequired else {
            return FamilySyncTransportResult(accountChange: accountChange)
        }
        let records = await cloud.snapshot(
            account: currentAccount,
            profileIDs: Set(profileIDs)
        )
        guard duplicateAndReverseFetches, records.count > 1 else {
            return FamilySyncTransportResult(records: records)
        }
        returnedDuplicateReorderedBatch = true
        return FamilySyncTransportResult(records: Array(records.reversed()) + records)
    }

    func sendChanges(
        _ changes: [FamilySyncPendingOperation]
    ) async throws -> FamilySyncTransportResult {
        events.append(.send)
        guard !accountConfirmationRequired else {
            return FamilySyncTransportResult(accountChange: accountChange)
        }
        let result = await cloud.apply(changes, account: currentAccount)
        guard dropNextAcknowledgementsAfterCommit else { return result }
        dropNextAcknowledgementsAfterCommit = false
        return FamilySyncTransportResult(
            failures: result.failures
        )
    }

    func acknowledgeFetchedChanges(receiptIDs: Set<UUID>) async throws {
        guard !receiptIDs.isEmpty else { return }
        events.append(.acknowledgeReceipt)
    }

    func confirmCurrentAccount() async throws -> FamilySyncAccountChange? {
        events.append(.confirmAccount)
        let confirmedChange = accountConfirmationRequired ? accountChange : nil
        accountConfirmationRequired = false
        return confirmedChange
    }

    func suspend() async {
        events.append(.suspend)
    }

    func createShare(for profileID: ProfileID) async throws -> URL {
        _ = profileID
        return URL(string: "https://example.invalid/family-sync-harness")!
    }

    func acceptShare(at url: URL) async throws -> ProfileID {
        _ = url
        return ProfileID()
    }

    func simulateAccountSwitch(to account: String) {
        currentAccount = account
        accountConfirmationRequired = true
        accountChange = .switchedAccounts
    }

    func eventLog() -> [Event] {
        events
    }

    func didReturnDuplicateReorderedBatch() -> Bool {
        returnedDuplicateReorderedBatch
    }
}

private func harnessRecord(
    profileID: ProfileID,
    name: String,
    kind: FamilySyncRecordKind,
    payload: String,
    at date: Date,
    isDeleted: Bool = false,
    revision: FamilySyncLogicalRevision? = nil
) -> FamilySyncRecord {
    FamilySyncRecord(
        recordName: name,
        profileID: profileID,
        kind: kind,
        payload: Data(payload.utf8),
        updatedAt: date,
        deviceID: revision?.deviceID ?? "raw-device",
        isDeleted: isDeleted,
        logicalRevision: revision
    )
}

private func harnessPayload(_ record: FamilySyncRecord) -> String {
    String(decoding: record.payload, as: UTF8.self)
}
