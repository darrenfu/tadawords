import Foundation
import TadaWordsContent
import TadaWordsDomain
import XCTest

final class ProfileErasureLifecycleCoordinatorTests: XCTestCase {
    func testOwnerDispositionCompletesDurableErasureLifecycle() async throws {
        let harness = try await ProfileErasureCoordinatorHarness.make(
            sendBehavior: .completed(route: .owner)
        )
        defer { harness.remove() }

        let status = await harness.coordinator.synchronize()
        let lifecycle = try await requiredLifecycle(in: harness)

        XCTAssertEqual(status, .synced(at: harness.now))
        XCTAssertEqual(lifecycle.route, .owner)
        XCTAssertEqual(lifecycle.state, .complete)
        XCTAssertEqual(lifecycle.attemptCount, 1)
        XCTAssertEqual(lifecycle.retryCount, 0)
        XCTAssertEqual(lifecycle.lastAttemptAt, harness.now)
        XCTAssertEqual(lifecycle.lastSuccessAt, harness.now)
        XCTAssertNil(lifecycle.errorCategory)
    }

    func testParticipantDispositionCompletesDurableErasureLifecycle() async throws {
        let harness = try await ProfileErasureCoordinatorHarness.make(
            sendBehavior: .completed(route: .participant)
        )
        defer { harness.remove() }

        _ = await harness.coordinator.synchronize()
        let lifecycle = try await requiredLifecycle(in: harness)

        XCTAssertEqual(lifecycle.route, .participant)
        XCTAssertEqual(lifecycle.state, .complete)
        XCTAssertEqual(lifecycle.lastSuccessAt, harness.now)
        XCTAssertNil(lifecycle.errorCategory)
    }

    func testTemporaryUnavailabilityPersistsWaitingForConnection() async throws {
        let harness = try await ProfileErasureCoordinatorHarness.make(
            availability: .temporarilyUnavailable,
            sendBehavior: .genericAcknowledgement
        )
        defer { harness.remove() }

        let status = await harness.coordinator.synchronize()
        let lifecycle = try await requiredLifecycle(in: harness)

        guard case .pendingOffline(let pendingCount, _, _) = status else {
            return XCTFail("Expected a nonblocking offline state, got \(status)")
        }
        XCTAssertEqual(pendingCount, 1)
        XCTAssertEqual(lifecycle.route, .unresolved)
        XCTAssertEqual(lifecycle.state, .waitingForConnection)
        XCTAssertEqual(lifecycle.attemptCount, 0)
        XCTAssertEqual(lifecycle.retryCount, 0)
        XCTAssertEqual(lifecycle.errorCategory, .connectivity)
        let sendCount = await harness.transport.sendCount()
        XCTAssertEqual(sendCount, 0)
    }

    func testRetryableFailureAndBackoffSurviveCoordinatorRestart() async throws {
        let harness = try await ProfileErasureCoordinatorHarness.make(
            sendBehavior: .failed(
                route: .owner,
                category: .connectivity,
                retryAfter: 300
            )
        )
        defer { harness.remove() }

        let status = await harness.coordinator.synchronize()
        let beforeRestart = try await requiredLifecycle(in: harness)

        guard
            case .pendingOffline(let pendingCount, let retryCount, let nextRetryAt) =
                status
        else {
            return XCTFail("Expected durable retry state, got \(status)")
        }
        XCTAssertEqual(pendingCount, 1)
        XCTAssertEqual(retryCount, 1)
        XCTAssertEqual(nextRetryAt, harness.now.addingTimeInterval(300))
        XCTAssertEqual(beforeRestart.route, .owner)
        XCTAssertEqual(beforeRestart.state, .waitingForConnection)
        XCTAssertEqual(beforeRestart.retryCount, 1)
        XCTAssertEqual(beforeRestart.nextRetryAt, nextRetryAt)
        XCTAssertEqual(beforeRestart.errorCategory, .connectivity)

        let restartedTombstones = LocalJSONProfileDeletionTombstoneRepository(
            snapshotURL: harness.tombstoneURL
        )
        let restartedJournal = LocalJSONFamilySyncJournalRepository(
            snapshotURL: harness.journalURL
        )
        let restarted = LocalFirstFamilySyncCoordinator(
            store: harness.store,
            transport: ProfileErasureTestTransport(
                availability: .available,
                sendBehavior: .completed(route: .owner)
            ),
            preferenceRepository: InMemoryFamilySyncPreferenceRepository(
                isEnabled: true
            ),
            journalRepository: restartedJournal,
            profileDeletionRepository: restartedTombstones,
            deviceID: "restart-device",
            clock: ProfileErasureFixedClock(
                now: harness.now.addingTimeInterval(10)
            )
        )

        let restartedLifecycles = try await restarted.profileErasureLifecycles()
        let afterRestart = try XCTUnwrap(restartedLifecycles.first)
        XCTAssertEqual(afterRestart, beforeRestart)
        let evidence = try await restartedJournal.profileDeletionDeliveryEvidence(
            for: harness.profileID
        )
        guard case .pending(let pending) = evidence else {
            return XCTFail("Expected pending deletion evidence after restart")
        }
        XCTAssertEqual(pending.retryCount, 1)
        XCTAssertEqual(pending.nextRetryAt, nextRetryAt)
        XCTAssertEqual(pending.errorCategory, .connectivity)
    }

    func testAccountChangeNeedsAttentionAndCannotCompleteDeletion() async throws {
        let harness = try await ProfileErasureCoordinatorHarness.make(
            fetchAccountChange: .switchedAccounts,
            sendBehavior: .completed(route: .owner)
        )
        defer { harness.remove() }

        let status = await harness.coordinator.synchronize()
        let lifecycle = try await requiredLifecycle(in: harness)

        guard case .iCloudUnavailable = status else {
            return XCTFail("Expected account attention, got \(status)")
        }
        XCTAssertEqual(lifecycle.route, .unresolved)
        XCTAssertEqual(lifecycle.state, .needsAttention)
        XCTAssertEqual(lifecycle.attemptCount, 0)
        XCTAssertNil(lifecycle.lastSuccessAt)
        XCTAssertEqual(lifecycle.errorCategory, .account)
        let sendCount = await harness.transport.sendCount()
        XCTAssertEqual(sendCount, 0)
    }

    func testManualRetryBypassesBackoffForNeedsAttentionDeletion() async throws {
        let harness = try await ProfileErasureCoordinatorHarness.make(
            sendBehavior: .failed(
                route: .owner,
                category: .unknown,
                retryAfter: 300
            )
        )
        defer { harness.remove() }

        let failedStatus = await harness.coordinator.synchronize()
        guard case .failed = failedStatus else {
            return XCTFail("Expected needs-attention failure, got \(failedStatus)")
        }
        let failedLifecycle = try await requiredLifecycle(in: harness)
        XCTAssertEqual(failedLifecycle.state, .needsAttention)

        let recoveryTransport = ProfileErasureTestTransport(
            availability: .available,
            sendBehavior: .completed(route: .owner)
        )
        let retryTime = harness.now.addingTimeInterval(10)
        let restarted = LocalFirstFamilySyncCoordinator(
            store: harness.store,
            transport: recoveryTransport,
            preferenceRepository: InMemoryFamilySyncPreferenceRepository(
                isEnabled: true
            ),
            journalRepository: LocalJSONFamilySyncJournalRepository(
                snapshotURL: harness.journalURL
            ),
            profileDeletionRepository:
                LocalJSONProfileDeletionTombstoneRepository(
                    snapshotURL: harness.tombstoneURL
                ),
            deviceID: "manual-retry-device",
            clock: ProfileErasureFixedClock(now: retryTime)
        )

        let ordinaryStatus = await restarted.synchronize()
        guard case .pendingOffline = ordinaryStatus else {
            return XCTFail(
                "Ordinary sync should respect durable backoff, got \(ordinaryStatus)"
            )
        }
        let sendCountBeforeRetry = await recoveryTransport.sendCount()
        XCTAssertEqual(sendCountBeforeRetry, 0)

        let retryStatus = await restarted.retryProfileErasures()
        XCTAssertEqual(retryStatus, .synced(at: retryTime))
        let sendCountAfterRetry = await recoveryTransport.sendCount()
        XCTAssertEqual(sendCountAfterRetry, 1)
        let recovered = try await restarted.profileErasureLifecycles()
        XCTAssertEqual(recovered.first?.state, .complete)
        XCTAssertEqual(recovered.first?.route, .owner)
    }

    func testRestartRepairsRouteResolvedAcknowledgementAfterCrashWindow()
        async throws
    {
        let harness = try await ProfileErasureCoordinatorHarness.make(
            sendBehavior: .completed(route: .owner)
        )
        defer { harness.remove() }
        let versioned = try await harness.journal.reconcileLocalRecords(
            [harness.deletionRecord],
            deviceID: "pre-crash-device",
            now: harness.now
        )
        let operation = try XCTUnwrap(versioned.first).asPendingSave
        let acknowledgement = FamilySyncChangeAcknowledgement(operation: operation)
        try await harness.journal.recordAttempt(
            keys: [acknowledgement.key],
            at: harness.now
        )
        try await harness.tombstones.recordErasureEvent(
            .attemptStarted(route: .unresolved, at: harness.now),
            for: harness.profileID
        )
        try await harness.tombstones.recordErasureEvent(
            .routeResolved(route: .owner, at: harness.now),
            for: harness.profileID
        )
        try await harness.journal.recordTransportResult(
            acknowledged: [acknowledgement],
            failures: [],
            at: harness.now
        )

        let crashWindow = try await requiredLifecycle(in: harness)
        XCTAssertEqual(crashWindow.route, .owner)
        XCTAssertEqual(crashWindow.state, .deleting)
        XCTAssertNil(crashWindow.lastSuccessAt)

        let restartedTombstones = LocalJSONProfileDeletionTombstoneRepository(
            snapshotURL: harness.tombstoneURL
        )
        let restartedJournal = LocalJSONFamilySyncJournalRepository(
            snapshotURL: harness.journalURL
        )
        let repairTime = harness.now.addingTimeInterval(5)
        let restarted = LocalFirstFamilySyncCoordinator(
            store: harness.store,
            transport: ProfileErasureTestTransport(
                availability: .available,
                sendBehavior: .genericAcknowledgement
            ),
            preferenceRepository: InMemoryFamilySyncPreferenceRepository(
                isEnabled: true
            ),
            journalRepository: restartedJournal,
            profileDeletionRepository: restartedTombstones,
            deviceID: "post-crash-device",
            clock: ProfileErasureFixedClock(now: repairTime)
        )

        let repairedLifecycles = try await restarted.profileErasureLifecycles()
        let repaired = try XCTUnwrap(repairedLifecycles.first)
        XCTAssertEqual(repaired.route, .owner)
        XCTAssertEqual(repaired.state, .complete)
        XCTAssertEqual(repaired.lastSuccessAt, repairTime)
        XCTAssertNil(repaired.errorCategory)
    }

    func testDuplicateSynchronizationCannotRegressCompletedLifecycle() async throws {
        let harness = try await ProfileErasureCoordinatorHarness.make(
            sendBehavior: .completed(route: .owner)
        )
        defer { harness.remove() }

        _ = await harness.coordinator.synchronize()
        let first = try await requiredLifecycle(in: harness)
        _ = await harness.coordinator.synchronize()
        let duplicate = try await requiredLifecycle(in: harness)

        XCTAssertEqual(first.state, .complete)
        XCTAssertEqual(duplicate, first)
        let sendCount = await harness.transport.sendCount()
        XCTAssertEqual(sendCount, 1)

        try await harness.tombstones.recordErasureEvent(
            .needsAttention(
                route: .owner,
                category: .server,
                at: harness.now.addingTimeInterval(30)
            ),
            for: harness.profileID
        )
        let afterLateEvent = try await requiredLifecycle(in: harness)
        XCTAssertEqual(afterLateEvent, first)
    }

    func testGenericAcknowledgementWithoutExactDispositionFailsClosed()
        async throws
    {
        let harness = try await ProfileErasureCoordinatorHarness.make(
            sendBehavior: .genericAcknowledgement
        )
        defer { harness.remove() }

        let status = await harness.coordinator.synchronize()
        let lifecycle = try await requiredLifecycle(in: harness)
        let evidence = try await harness.journal.profileDeletionDeliveryEvidence(
            for: harness.profileID
        )

        guard case .failed = status else {
            return XCTFail("Expected missing route evidence to fail closed, got \(status)")
        }
        XCTAssertEqual(lifecycle.route, .unresolved)
        XCTAssertEqual(lifecycle.state, .needsAttention)
        XCTAssertEqual(lifecycle.errorCategory, .unknown)
        XCTAssertNil(lifecycle.lastSuccessAt)
        guard case .pending(let pending) = evidence else {
            return XCTFail("A route-less ACK must leave the tombstone pending")
        }
        XCTAssertEqual(pending.errorCategory, .unknown)

        let reread = try await harness.coordinator.profileErasureLifecycles()
        XCTAssertEqual(reread.first, lifecycle)
    }

    func testLegacyAcknowledgementWithoutRouteIsRequeuedAndCanRecover()
        async throws
    {
        let harness = try await ProfileErasureCoordinatorHarness.make(
            sendBehavior: .completed(route: .owner)
        )
        defer { harness.remove() }
        let versioned = try await harness.journal.reconcileLocalRecords(
            [harness.deletionRecord],
            deviceID: "legacy-device",
            now: harness.now
        )
        let acknowledgement = FamilySyncChangeAcknowledgement(
            operation: .save(try XCTUnwrap(versioned.first))
        )
        try await harness.journal.recordTransportResult(
            acknowledged: [acknowledgement],
            failures: [],
            at: harness.now
        )

        let repaired = try await harness.coordinator.profileErasureLifecycles()
        let pending = try await harness.journal.profileDeletionDeliveryEvidence(
            for: harness.profileID
        )

        XCTAssertEqual(repaired.first?.route, .unresolved)
        XCTAssertEqual(repaired.first?.state, .needsAttention)
        XCTAssertEqual(repaired.first?.errorCategory, .compatibility)
        guard case .pending(let evidence) = pending else {
            return XCTFail("Legacy route-less ACK must be requeued")
        }
        XCTAssertEqual(evidence.errorCategory, .compatibility)

        let status = await harness.coordinator.synchronize()
        let completed = try await requiredLifecycle(in: harness)
        let sendCount = await harness.transport.sendCount()
        XCTAssertEqual(status, .synced(at: harness.now))
        XCTAssertEqual(completed.route, .owner)
        XCTAssertEqual(completed.state, .complete)
        XCTAssertEqual(sendCount, 1)
    }

    private func requiredLifecycle(
        in harness: ProfileErasureCoordinatorHarness
    ) async throws -> ProfileErasureLifecycle {
        let lifecycle = try await harness.tombstones.erasureLifecycle(
            for: harness.profileID
        )
        return try XCTUnwrap(lifecycle)
    }
}

private struct ProfileErasureCoordinatorHarness {
    let directory: URL
    let tombstoneURL: URL
    let journalURL: URL
    let profileID: ProfileID
    let now: Date
    let deletionRecord: FamilySyncRecord
    let store: ProfileErasureTestStore
    let transport: ProfileErasureTestTransport
    let tombstones: LocalJSONProfileDeletionTombstoneRepository
    let journal: LocalJSONFamilySyncJournalRepository
    let coordinator: LocalFirstFamilySyncCoordinator

    static func make(
        availability: FamilySyncAvailability = .available,
        fetchAccountChange: FamilySyncAccountChange? = nil,
        sendBehavior: ProfileErasureTestTransport.SendBehavior
    ) async throws -> Self {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(
            "TadaWordsProfileErasureCoordinator-\(UUID().uuidString)",
            isDirectory: true
        )
        try FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true
        )
        let profileID = ProfileID()
        let now = Date(timeIntervalSince1970: 1_900_000_000)
        let tombstone = ProfileDeletionTombstone(
            profileID: profileID,
            deletedAt: now.addingTimeInterval(-10)
        )
        let deletionRecord = FamilySyncRecord(
            recordName: "profile-\(profileID)",
            profileID: profileID,
            kind: .profileDeletion,
            payload: try JSONEncoder().encode(tombstone),
            updatedAt: tombstone.deletedAt,
            deviceID: "privacy-minimal-device",
            isDeleted: true
        )
        let tombstoneURL = directory.appendingPathComponent("deletions.json")
        let journalURL = directory.appendingPathComponent("journal.json")
        let tombstones = LocalJSONProfileDeletionTombstoneRepository(
            snapshotURL: tombstoneURL
        )
        try await tombstones.save(tombstone)
        try await tombstones.markCommitted(for: profileID)
        let journal = LocalJSONFamilySyncJournalRepository(snapshotURL: journalURL)
        let store = ProfileErasureTestStore(
            profileID: profileID,
            record: deletionRecord
        )
        let transport = ProfileErasureTestTransport(
            availability: availability,
            fetchAccountChange: fetchAccountChange,
            sendBehavior: sendBehavior
        )
        let coordinator = LocalFirstFamilySyncCoordinator(
            store: store,
            transport: transport,
            preferenceRepository: InMemoryFamilySyncPreferenceRepository(
                isEnabled: true
            ),
            journalRepository: journal,
            profileDeletionRepository: tombstones,
            deviceID: "coordinator-test-device",
            clock: ProfileErasureFixedClock(now: now)
        )
        return Self(
            directory: directory,
            tombstoneURL: tombstoneURL,
            journalURL: journalURL,
            profileID: profileID,
            now: now,
            deletionRecord: deletionRecord,
            store: store,
            transport: transport,
            tombstones: tombstones,
            journal: journal,
            coordinator: coordinator
        )
    }

    func remove() {
        try? FileManager.default.removeItem(at: directory)
    }
}

private struct ProfileErasureFixedClock: AppClock {
    let now: Date
}

private actor ProfileErasureTestStore: FamilySyncRecordStore {
    private let profileID: ProfileID
    private var record: FamilySyncRecord

    init(profileID: ProfileID, record: FamilySyncRecord) {
        self.profileID = profileID
        self.record = record
    }

    func profileIDsForSync() async throws -> [ProfileID] { [profileID] }

    func records(for profileID: ProfileID) async throws -> [FamilySyncRecord] {
        profileID == self.profileID ? [record] : []
    }

    func apply(
        _ records: [FamilySyncRecord],
        for profileID: ProfileID
    ) async throws {
        guard profileID == self.profileID,
            let replacement = records.first(where: {
                $0.kind == .profileDeletion && $0.isDeleted
            })
        else { return }
        record = replacement
    }

    func isProfileDeleted(_ profileID: ProfileID) async throws -> Bool {
        profileID == self.profileID
    }
}

private actor ProfileErasureTestTransport: FamilySyncTransport {
    enum SendBehavior: Sendable {
        case completed(route: ProfileErasureRoute)
        case failed(
            route: ProfileErasureRoute,
            category: FamilySyncPrivacySafeErrorCategory,
            retryAfter: TimeInterval
        )
        case genericAcknowledgement
    }

    nonisolated let capability: FamilySyncCapability = .iCloud
    private let availabilityValue: FamilySyncAvailability
    private let sendBehavior: SendBehavior
    private var pendingFetchAccountChange: FamilySyncAccountChange?
    private var sends = 0

    init(
        availability: FamilySyncAvailability,
        fetchAccountChange: FamilySyncAccountChange? = nil,
        sendBehavior: SendBehavior
    ) {
        availabilityValue = availability
        pendingFetchAccountChange = fetchAccountChange
        self.sendBehavior = sendBehavior
    }

    func availability() async -> FamilySyncAvailability { availabilityValue }

    func prepareProfileZone(_ profileID: ProfileID) async throws {
        _ = profileID
    }

    func fetchRecords(for profileID: ProfileID) async throws -> [FamilySyncRecord] {
        _ = profileID
        return []
    }

    func fetchChanges(
        for profileIDs: [ProfileID],
        terminalProfileIDs: Set<ProfileID>
    ) async throws -> FamilySyncTransportResult {
        _ = profileIDs
        _ = terminalProfileIDs
        let accountChange = pendingFetchAccountChange
        pendingFetchAccountChange = nil
        return FamilySyncTransportResult(accountChange: accountChange)
    }

    func push(
        _ records: [FamilySyncRecord],
        for profileID: ProfileID
    ) async throws {
        _ = records
        _ = profileID
    }

    func sendChanges(
        _ changes: [FamilySyncPendingOperation]
    ) async throws -> FamilySyncTransportResult {
        sends += 1
        let deletionOperations = changes.filter { operation in
            guard case .save(let record) = operation else { return false }
            return record.kind == .profileDeletion && record.isDeleted
        }
        let acknowledgements = Set(
            deletionOperations.map(FamilySyncChangeAcknowledgement.init(operation:))
        )
        switch sendBehavior {
        case .completed(let route):
            return FamilySyncTransportResult(
                acknowledged: acknowledgements,
                profileErasureDispositions: acknowledgements.map {
                    ProfileErasureTransportDisposition(
                        change: $0,
                        route: route,
                        outcome: .completed
                    )
                }
            )
        case .failed(let route, let category, let retryAfter):
            let failures = acknowledgements.map {
                FamilySyncTransportFailure(
                    key: $0.key,
                    category: category,
                    retryAfter: retryAfter
                )
            }
            return FamilySyncTransportResult(
                failures: failures,
                profileErasureDispositions: acknowledgements.map {
                    ProfileErasureTransportDisposition(
                        change: $0,
                        route: route,
                        outcome: .failed(
                            category: category,
                            retryAfter: retryAfter
                        )
                    )
                }
            )
        case .genericAcknowledgement:
            return FamilySyncTransportResult(acknowledged: acknowledgements)
        }
    }

    func createShare(for profileID: ProfileID) async throws -> URL {
        _ = profileID
        return URL(string: "https://example.invalid/profile-erasure")!
    }

    func acceptShare(at url: URL) async throws -> ProfileID {
        _ = url
        return ProfileID()
    }

    func sendCount() -> Int { sends }
}

extension FamilySyncRecord {
    fileprivate var asPendingSave: FamilySyncPendingOperation { .save(self) }
}
