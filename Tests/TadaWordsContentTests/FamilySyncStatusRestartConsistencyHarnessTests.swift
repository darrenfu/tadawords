import Foundation
import TadaWordsContent
import TadaWordsDomain
import XCTest

final class FamilySyncStatusRestartConsistencyHarnessTests: XCTestCase {
    func testParentVisibleTransportFailureStatusSurvivesCoordinatorRestart()
        async throws
    {
        let categories: [FamilySyncPrivacySafeErrorCategory] = [
            .connectivity,
            .rateLimited,
            .server,
            .account,
            .compatibility,
            .corruptState,
            .conflict,
            .unknown,
        ]

        for category in categories {
            let fixture = try FamilySyncStatusRestartFixture(category: category)
            defer { fixture.remove() }

            let live = await fixture.coordinator().synchronize()
            let afterRestart = await fixture.coordinator().status()

            XCTAssertEqual(
                afterRestart,
                live,
                "\(category) must have the same parent-visible status after restart"
            )
            assertExpectedCondition(live, for: category)
        }
    }

    private func assertExpectedCondition(
        _ status: FamilySyncStatus,
        for category: FamilySyncPrivacySafeErrorCategory,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        switch category {
        case .connectivity, .rateLimited, .server:
            guard case .pendingOffline = status else {
                return XCTFail(
                    "\(category) must remain retryable, got \(status)",
                    file: file,
                    line: line
                )
            }
        case .account:
            guard case .iCloudUnavailable = status else {
                return XCTFail(
                    "Account failure must ask for iCloud recovery, got \(status)",
                    file: file,
                    line: line
                )
            }
        case .compatibility, .corruptState, .conflict, .unknown:
            guard case .failed = status else {
                return XCTFail(
                    "\(category) must remain visible as needing attention, got \(status)",
                    file: file,
                    line: line
                )
            }
        }
    }
}

private struct FamilySyncStatusRestartFixture {
    let directory: URL
    let journalURL: URL
    let category: FamilySyncPrivacySafeErrorCategory

    init(category: FamilySyncPrivacySafeErrorCategory) throws {
        directory = FileManager.default.temporaryDirectory.appendingPathComponent(
            "TadaFamilySyncStatusRestart-\(UUID().uuidString)",
            isDirectory: true
        )
        try FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true
        )
        journalURL = directory.appendingPathComponent("journal.json")
        self.category = category
    }

    func coordinator() -> LocalFirstFamilySyncCoordinator {
        LocalFirstFamilySyncCoordinator(
            store: FamilySyncStatusRestartStore(),
            transport: FamilySyncStatusRestartTransport(category: category),
            preferenceRepository: InMemoryFamilySyncPreferenceRepository(
                isEnabled: true
            ),
            journalRepository: LocalJSONFamilySyncJournalRepository(
                snapshotURL: journalURL
            ),
            deviceID: "status-restart-device",
            clock: FamilySyncStatusRestartClock(
                now: Date(timeIntervalSince1970: 2_130_100_000)
            )
        )
    }

    func remove() {
        try? FileManager.default.removeItem(at: directory)
    }
}

private struct FamilySyncStatusRestartClock: AppClock {
    let now: Date
}

private struct FamilySyncStatusRestartStore: FamilySyncRecordStore {
    func profileIDsForSync() async throws -> [ProfileID] { [] }

    func records(for profileID: ProfileID) async throws -> [FamilySyncRecord] {
        _ = profileID
        return []
    }

    func apply(
        _ records: [FamilySyncRecord],
        for profileID: ProfileID
    ) async throws {
        _ = records
        _ = profileID
    }
}

private struct FamilySyncStatusRestartTransport: FamilySyncTransport {
    let category: FamilySyncPrivacySafeErrorCategory
    let capability: FamilySyncCapability = .iCloud

    func availability() async -> FamilySyncAvailability { .available }

    func prepareProfileZone(_ profileID: ProfileID) async throws {
        _ = profileID
    }

    func fetchRecords(for profileID: ProfileID) async throws -> [FamilySyncRecord] {
        _ = profileID
        return []
    }

    func fetchChanges(
        for profileIDs: [ProfileID]
    ) async throws -> FamilySyncTransportResult {
        _ = profileIDs
        return FamilySyncTransportResult(
            failures: [
                FamilySyncTransportFailure(key: nil, category: category)
            ]
        )
    }

    func push(
        _ records: [FamilySyncRecord],
        for profileID: ProfileID
    ) async throws {
        _ = records
        _ = profileID
    }

    func createShare(for profileID: ProfileID) async throws -> URL {
        _ = profileID
        return URL(string: "https://example.invalid/share")!
    }

    func acceptShare(at url: URL) async throws -> ProfileID {
        _ = url
        return ProfileID()
    }
}
