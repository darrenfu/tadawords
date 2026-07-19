import Foundation
import TadaWordsDomain
import XCTest

@testable import TadaWordsGuardianFeatures

final class GuardianFamilySyncPresentationTests: XCTestCase {
    @MainActor
    func testManageAccessUsesParentAuthorizationAndSelectedProfile() async throws {
        let coordinator = GuardianFamilySyncCoordinatorStub()
        let recorder = GuardianFamilyAccessRecorder()
        let authorizer = GuardianFamilyAccessAuthorizer()
        let model = GuardianDashboardViewModel(
            store: DemoGuardianFamilyStore(),
            audioPromptService: GuardianFamilySyncSilentAudioService(),
            familySyncCoordinator: coordinator,
            familySyncAccessManagement: { profileID in
                await recorder.record(profileID)
            },
            sensitiveActionAuthorizer: authorizer
        )

        model.unlockGuardianArea()
        for _ in 0..<100 where model.snapshot == nil {
            try await Task.sleep(for: .milliseconds(10))
        }
        let profileID = try XCTUnwrap(model.snapshot?.profile.id)
        model.showFamilySync()
        for _ in 0..<100 where !model.isFamilySyncEnabled {
            try await Task.sleep(for: .milliseconds(10))
        }
        XCTAssertTrue(model.isFamilySyncEnabled)
        XCTAssertTrue(model.canManageFamilyAccess)

        model.manageFamilyAccess()
        for _ in 0..<100 where await recorder.profileIDs.isEmpty {
            try await Task.sleep(for: .milliseconds(10))
        }

        let recordedProfileIDs = await recorder.profileIDs
        let actions = await authorizer.actions
        XCTAssertEqual(recordedProfileIDs, [profileID])
        XCTAssertEqual(actions, [.manageGuardians])
    }

    func testDeviceOnlyModeHidesEveryCloudControl() {
        let presentation = GuardianFamilySyncPresentation(
            status: .deviceOnly(
                message: "This version keeps learning data on this device."
            ),
            isEnabled: false
        )

        XCTAssertEqual(presentation.navigationTitle, "Device storage")
        XCTAssertEqual(presentation.title, "This device only")
        XCTAssertFalse(presentation.message.localizedCaseInsensitiveContains("icloud"))
        XCTAssertFalse(presentation.showsPreferenceToggle)
        XCTAssertFalse(presentation.showsSyncAction)
        XCTAssertFalse(presentation.showsInvitationActions)
    }

    func testOptedOutICloudModeShowsOnlyExplicitPreferenceControl() {
        let presentation = GuardianFamilySyncPresentation(
            status: .optedOut(message: "Family sync is off."),
            isEnabled: false
        )

        XCTAssertEqual(presentation.navigationTitle, "Family sync")
        XCTAssertEqual(presentation.title, "Family sync is off")
        XCTAssertTrue(presentation.showsPreferenceToggle)
        XCTAssertFalse(presentation.showsSyncAction)
        XCTAssertFalse(presentation.showsInvitationActions)
    }

    func testInvitationsAppearOnlyAfterEnabledSyncSucceeds() {
        let unavailable = GuardianFamilySyncPresentation(
            status: .iCloudUnavailable(message: "Sign in to iCloud."),
            isEnabled: true
        )
        let synced = GuardianFamilySyncPresentation(
            status: .synced(at: Date(timeIntervalSince1970: 1_735_689_600)),
            isEnabled: true
        )

        XCTAssertTrue(unavailable.showsSyncAction)
        XCTAssertFalse(unavailable.showsInvitationActions)
        XCTAssertTrue(synced.showsSyncAction)
        XCTAssertTrue(synced.showsInvitationActions)
        XCTAssertTrue(synced.message.hasPrefix("Last synced "))
    }

    func testPendingPresentationShowsDurableRetrySummaryWithoutChildData() {
        let presentation = GuardianFamilySyncPresentation(
            status: .pendingOffline(
                pendingCount: 3,
                retryCount: 2,
                nextRetryAt: Date(timeIntervalSince1970: 1_735_689_900)
            ),
            isEnabled: true
        )

        XCTAssertEqual(presentation.title, "Waiting for a connection")
        XCTAssertTrue(presentation.message.contains("3 changes"))
        XCTAssertTrue(presentation.message.contains("Retry 2"))
        XCTAssertFalse(presentation.message.contains("Mia"))
        XCTAssertFalse(presentation.message.contains("dog"))
    }

    func testDiagnosticExportContainsOnlyPrivacySafeTransportState() {
        let report = GuardianFamilySyncDiagnosticReport(
            status: .pendingOffline(
                pendingCount: 3,
                retryCount: 2,
                nextRetryAt: Date(timeIntervalSince1970: 1_735_689_900)
            ),
            isEnabled: true,
            generatedAt: Date(timeIntervalSince1970: 1_735_689_600)
        ).text

        XCTAssertTrue(report.contains("State: waiting_for_connection"))
        XCTAssertTrue(report.contains("Pending changes: 3"))
        XCTAssertTrue(report.contains("Retry count: 2"))
        XCTAssertTrue(report.contains("Next retry:"))
        for childPayload in [
            "Mia",
            "dog",
            "profile-photo-",
            "voiceprint",
            "payloadChecksum",
        ] {
            XCTAssertFalse(report.contains(childPayload))
        }
    }
}

private actor GuardianFamilySyncCoordinatorStub: FamilySyncCoordinating {
    func isEnabled() async -> Bool { true }

    func setEnabled(_ isEnabled: Bool) async throws -> FamilySyncStatus {
        _ = isEnabled
        return .synced(at: Date(timeIntervalSince1970: 1_735_689_600))
    }

    func synchronize() async -> FamilySyncStatus {
        .synced(at: Date(timeIntervalSince1970: 1_735_689_600))
    }

    func status() async -> FamilySyncStatus {
        .synced(at: Date(timeIntervalSince1970: 1_735_689_600))
    }

    func createShare(for profileID: ProfileID) async throws -> URL {
        _ = profileID
        return URL(string: "https://www.icloud.com/share/example")!
    }

    func acceptShare(at url: URL) async throws {
        _ = url
    }
}

private actor GuardianFamilyAccessRecorder {
    private(set) var profileIDs: [ProfileID] = []

    func record(_ profileID: ProfileID) {
        profileIDs.append(profileID)
    }
}

private actor GuardianFamilyAccessAuthorizer:
    SensitiveGuardianActionAuthorizing
{
    private(set) var actions: [SensitiveGuardianAction] = []

    func authorize(_ action: SensitiveGuardianAction) async -> Bool {
        actions.append(action)
        return true
    }
}

private struct GuardianFamilySyncSilentAudioService: AudioPromptService {
    func play(_ prompt: WordPrompt, for profileID: ProfileID) async throws {
        _ = prompt
        _ = profileID
    }
}
