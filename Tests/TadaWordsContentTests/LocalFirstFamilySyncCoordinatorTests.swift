import Foundation
import TadaWordsContent
import TadaWordsDomain
import XCTest

final class LocalFirstFamilySyncCoordinatorTests: XCTestCase {
    func testCoordinatorResolvesRemoteAndLocalBeforePushing() async throws {
        let profileID = ProfileID()
        let local = record(
            profileID: profileID,
            payload: "local",
            updatedAt: Date(timeIntervalSince1970: 10),
            deviceID: "a"
        )
        let remote = record(
            profileID: profileID,
            payload: "remote",
            updatedAt: Date(timeIntervalSince1970: 20),
            deviceID: "b"
        )
        let store = SyncStore(profileID: profileID, records: [local])
        let transport = SyncTransport(records: [remote])
        let coordinator = LocalFirstFamilySyncCoordinator(
            store: store,
            transport: transport,
            preferenceRepository: InMemoryFamilySyncPreferenceRepository(
                isEnabled: true
            ),
            clock: FixedClock(now: Date(timeIntervalSince1970: 30))
        )

        let status = await coordinator.synchronize()
        let applied = await store.appliedRecords()
        let pushed = await transport.pushedRecords()

        XCTAssertEqual(status, .synced(at: Date(timeIntervalSince1970: 30)))
        XCTAssertEqual(applied, [remote])
        XCTAssertEqual(pushed, [remote])
    }

    func testTemporaryCloudFailureLeavesLocalDataPendingNotFailed() async {
        let store = SyncStore(profileID: ProfileID(), records: [])
        let transport = SyncTransport(
            records: [],
            availability: .temporarilyUnavailable
        )
        let coordinator = LocalFirstFamilySyncCoordinator(
            store: store,
            transport: transport,
            preferenceRepository: InMemoryFamilySyncPreferenceRepository(
                isEnabled: true
            )
        )

        let status = await coordinator.synchronize()
        let pushed = await transport.pushedRecords()
        XCTAssertEqual(status, .pendingOffline)
        XCTAssertTrue(pushed.isEmpty)
    }

    func testMissingICloudAccountReportsRecoverableICloudUnavailableState() async {
        let store = SyncStore(profileID: ProfileID(), records: [])
        let coordinator = LocalFirstFamilySyncCoordinator(
            store: store,
            transport: SyncTransport(records: [], availability: .noAccount),
            preferenceRepository: InMemoryFamilySyncPreferenceRepository(
                isEnabled: true
            )
        )

        let status = await coordinator.synchronize()
        guard case .iCloudUnavailable(let message) = status else {
            return XCTFail("Expected a nonblocking device-only state")
        }
        XCTAssertTrue(message.contains("iCloud"))
    }

    func testShareOperationsAreForwardedAndAcceptanceResyncs() async throws {
        let profileID = ProfileID()
        let remote = record(
            profileID: profileID,
            payload: "accepted-family",
            updatedAt: Date(timeIntervalSince1970: 50),
            deviceID: "owner"
        )
        let transport = SyncTransport(records: [remote], acceptedProfileID: profileID)
        let store = SyncStore(
            profileID: profileID,
            records: [],
            profileIDsForSync: []
        )
        let coordinator = LocalFirstFamilySyncCoordinator(
            store: store,
            transport: transport,
            preferenceRepository: InMemoryFamilySyncPreferenceRepository(
                isEnabled: true
            )
        )

        let url = try await coordinator.createShare(for: profileID)
        try await coordinator.acceptShare(at: url)

        XCTAssertEqual(url.absoluteString, "https://example.invalid/share")
        let acceptedURLs = await transport.acceptedURLs()
        let applied = await store.appliedRecords()
        XCTAssertEqual(acceptedURLs, [url])
        XCTAssertEqual(applied, [remote])
    }

    func testDefaultOptOutNeverContactsTransport() async {
        let profileID = ProfileID()
        let transport = SyncTransport(records: [])
        let coordinator = LocalFirstFamilySyncCoordinator(
            store: SyncStore(profileID: profileID, records: []),
            transport: transport
        )

        let status = await coordinator.synchronize()

        guard case .optedOut(let message) = status else {
            return XCTFail("Expected explicit opt-out status")
        }
        XCTAssertFalse(message.localizedCaseInsensitiveContains("sign in"))
        await assertThrowsErrorAsync(
            try await coordinator.createShare(for: profileID)
        ) { error in
            XCTAssertEqual(error as? FamilySyncConsentError, .optInRequired)
        }
        await assertThrowsErrorAsync(
            try await coordinator.acceptShare(
                at: URL(string: "https://example.invalid/share")!
            )
        ) { error in
            XCTAssertEqual(error as? FamilySyncConsentError, .optInRequired)
        }
        let calls = await transport.callCounts()
        XCTAssertEqual(calls, .zero)
    }

    func testCorruptPreferenceFailsClosedWithoutContactingTransport() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(
            "TadaWordsCorruptSyncPreference-\(UUID().uuidString)",
            isDirectory: true
        )
        defer { try? FileManager.default.removeItem(at: directory) }
        try FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true
        )
        let preferenceURL = directory.appendingPathComponent("family-sync.json")
        try Data("not-json".utf8).write(to: preferenceURL, options: .atomic)
        let transport = SyncTransport(records: [])
        let coordinator = LocalFirstFamilySyncCoordinator(
            store: SyncStore(profileID: ProfileID(), records: []),
            transport: transport,
            preferenceRepository: LocalJSONFamilySyncPreferenceRepository(
                snapshotURL: preferenceURL
            )
        )

        let status = await coordinator.synchronize()
        let isEnabled = await coordinator.isEnabled()
        let calls = await transport.callCounts()

        guard case .optedOut = status else {
            return XCTFail("Expected a corrupt preference to fail closed")
        }
        XCTAssertFalse(isEnabled)
        XCTAssertEqual(calls, .zero)
    }

    func testDeviceOnlyModeNeverContactsTransportOrOffersShares() async {
        let profileID = ProfileID()
        let transport = SyncTransport(records: [], capability: .deviceOnly)
        let coordinator = LocalFirstFamilySyncCoordinator(
            store: SyncStore(profileID: profileID, records: []),
            transport: transport,
            preferenceRepository: InMemoryFamilySyncPreferenceRepository(
                isEnabled: true
            )
        )

        let status = await coordinator.status()
        let synchronized = await coordinator.synchronize()

        guard case .deviceOnly(let message) = status else {
            return XCTFail("Expected explicit device-only status")
        }
        XCTAssertEqual(synchronized, status)
        XCTAssertFalse(message.localizedCaseInsensitiveContains("icloud"))
        await assertThrowsErrorAsync(
            try await coordinator.createShare(for: profileID)
        ) { error in
            XCTAssertEqual(error as? FamilySyncConsentError, .deviceOnly)
        }
        let calls = await transport.callCounts()
        XCTAssertEqual(calls, .zero)
    }

    func testTurningOffStopsLaterSynchronization() async throws {
        let profileID = ProfileID()
        let preference = InMemoryFamilySyncPreferenceRepository()
        let transport = SyncTransport(records: [])
        let coordinator = LocalFirstFamilySyncCoordinator(
            store: SyncStore(profileID: profileID, records: []),
            transport: transport,
            preferenceRepository: preference
        )

        _ = try await coordinator.setEnabled(true)
        let enabledCalls = await transport.callCounts()
        XCTAssertGreaterThan(enabledCalls.availability, 0)

        let disabledStatus = try await coordinator.setEnabled(false)
        let statusAfterLifecycleSync = await coordinator.synchronize()

        guard case .optedOut = disabledStatus else {
            return XCTFail("Expected opt-out after disabling")
        }
        XCTAssertEqual(statusAfterLifecycleSync, disabledStatus)
        let callsAfterLifecycleSync = await transport.callCounts()
        XCTAssertEqual(callsAfterLifecycleSync, enabledCalls)
    }

    private func record(
        profileID: ProfileID,
        payload: String,
        updatedAt: Date,
        deviceID: String
    ) -> FamilySyncRecord {
        FamilySyncRecord(
            recordName: "profile-\(profileID)",
            profileID: profileID,
            kind: .profile,
            payload: Data(payload.utf8),
            updatedAt: updatedAt,
            deviceID: deviceID
        )
    }
}

private actor SyncStore: FamilySyncRecordStore {
    let profileID: ProfileID
    let localRecords: [FamilySyncRecord]
    let idsForSync: [ProfileID]
    var applied: [FamilySyncRecord] = []

    init(
        profileID: ProfileID,
        records: [FamilySyncRecord],
        profileIDsForSync: [ProfileID]? = nil
    ) {
        self.profileID = profileID
        localRecords = records
        idsForSync = profileIDsForSync ?? [profileID]
    }

    func profileIDsForSync() async throws -> [ProfileID] { idsForSync }

    func records(for profileID: ProfileID) async throws -> [FamilySyncRecord] {
        localRecords
    }

    func apply(
        _ records: [FamilySyncRecord],
        for profileID: ProfileID
    ) async throws {
        applied.append(contentsOf: records)
    }

    func appliedRecords() -> [FamilySyncRecord] { applied }
}

private actor SyncTransport: FamilySyncTransport {
    nonisolated let capability: FamilySyncCapability
    let remoteRecords: [FamilySyncRecord]
    let state: FamilySyncAvailability
    let acceptedProfileID: ProfileID
    var pushed: [FamilySyncRecord] = []
    var accepted: [URL] = []
    var availabilityCallCount = 0
    var fetchCallCount = 0
    var pushCallCount = 0
    var createShareCallCount = 0

    init(
        records: [FamilySyncRecord],
        capability: FamilySyncCapability = .iCloud,
        availability: FamilySyncAvailability = .available,
        acceptedProfileID: ProfileID = ProfileID()
    ) {
        self.capability = capability
        remoteRecords = records
        state = availability
        self.acceptedProfileID = acceptedProfileID
    }

    func availability() async -> FamilySyncAvailability {
        availabilityCallCount += 1
        return state
    }
    func prepareProfileZone(_ profileID: ProfileID) async throws {}

    func fetchRecords(for profileID: ProfileID) async throws -> [FamilySyncRecord] {
        fetchCallCount += 1
        return remoteRecords
    }

    func push(
        _ records: [FamilySyncRecord],
        for profileID: ProfileID
    ) async throws {
        pushCallCount += 1
        pushed.append(contentsOf: records)
    }

    func createShare(for profileID: ProfileID) async throws -> URL {
        createShareCallCount += 1
        return URL(string: "https://example.invalid/share")!
    }

    func acceptShare(at url: URL) async throws -> ProfileID {
        accepted.append(url)
        return acceptedProfileID
    }
    func pushedRecords() -> [FamilySyncRecord] { pushed }
    func acceptedURLs() -> [URL] { accepted }

    func callCounts() -> SyncTransportCallCounts {
        SyncTransportCallCounts(
            availability: availabilityCallCount,
            fetch: fetchCallCount,
            push: pushCallCount,
            createShare: createShareCallCount,
            acceptShare: accepted.count
        )
    }
}

private struct SyncTransportCallCounts: Equatable, Sendable {
    let availability: Int
    let fetch: Int
    let push: Int
    let createShare: Int
    let acceptShare: Int

    static let zero = SyncTransportCallCounts(
        availability: 0,
        fetch: 0,
        push: 0,
        createShare: 0,
        acceptShare: 0
    )
}

private func assertThrowsErrorAsync<T>(
    _ expression: @autoclosure () async throws -> T,
    _ errorHandler: (Error) -> Void
) async {
    do {
        _ = try await expression()
        XCTFail("Expected expression to throw")
    } catch {
        errorHandler(error)
    }
}

private struct FixedClock: AppClock {
    let now: Date
}
