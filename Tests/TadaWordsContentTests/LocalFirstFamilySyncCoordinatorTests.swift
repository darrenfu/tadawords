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
            transport: transport
        )

        let status = await coordinator.synchronize()
        let pushed = await transport.pushedRecords()
        XCTAssertEqual(status, .pendingOffline)
        XCTAssertTrue(pushed.isEmpty)
    }

    func testMissingICloudAccountKeepsAppInDeviceOnlyMode() async {
        let store = SyncStore(profileID: ProfileID(), records: [])
        let coordinator = LocalFirstFamilySyncCoordinator(
            store: store,
            transport: SyncTransport(records: [], availability: .noAccount)
        )

        let status = await coordinator.synchronize()
        guard case .thisDeviceOnly(let message) = status else {
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
            transport: transport
        )

        let url = try await coordinator.createShare(for: profileID)
        try await coordinator.acceptShare(at: url)

        XCTAssertEqual(url.absoluteString, "https://example.invalid/share")
        let acceptedURLs = await transport.acceptedURLs()
        let applied = await store.appliedRecords()
        XCTAssertEqual(acceptedURLs, [url])
        XCTAssertEqual(applied, [remote])
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
    let remoteRecords: [FamilySyncRecord]
    let state: FamilySyncAvailability
    let acceptedProfileID: ProfileID
    var pushed: [FamilySyncRecord] = []
    var accepted: [URL] = []

    init(
        records: [FamilySyncRecord],
        availability: FamilySyncAvailability = .available,
        acceptedProfileID: ProfileID = ProfileID()
    ) {
        remoteRecords = records
        state = availability
        self.acceptedProfileID = acceptedProfileID
    }

    func availability() async -> FamilySyncAvailability { state }
    func prepareProfileZone(_ profileID: ProfileID) async throws {}

    func fetchRecords(for profileID: ProfileID) async throws -> [FamilySyncRecord] {
        remoteRecords
    }

    func push(
        _ records: [FamilySyncRecord],
        for profileID: ProfileID
    ) async throws {
        pushed.append(contentsOf: records)
    }

    func createShare(for profileID: ProfileID) async throws -> URL {
        URL(string: "https://example.invalid/share")!
    }

    func acceptShare(at url: URL) async throws -> ProfileID {
        accepted.append(url)
        return acceptedProfileID
    }
    func pushedRecords() -> [FamilySyncRecord] { pushed }
    func acceptedURLs() -> [URL] { accepted }
}

private struct FixedClock: AppClock {
    let now: Date
}
