import Foundation
import TadaWordsDomain
import XCTest

@testable import TadaWordsGuardianFeatures

final class GuardianFamilySyncPresentationTests: XCTestCase {
    @MainActor
    func testUnlockLoadsPersistedProfileErasureState() async throws {
        let coordinator = GuardianFamilySyncCoordinatorStub(
            lifecycles: [
                profileErasure(.waitingForConnection, retryCount: 2)
            ]
        )
        let model = GuardianDashboardViewModel(
            store: DemoGuardianFamilyStore(),
            audioPromptService: GuardianFamilySyncSilentAudioService(),
            familySyncCoordinator: coordinator
        )

        model.unlockGuardianArea()
        for _ in 0..<100
        where model.profileErasurePresentation?.state != .waitingForConnection {
            try await Task.sleep(for: .milliseconds(10))
        }

        XCTAssertEqual(
            model.profileErasurePresentation?.state,
            .waitingForConnection
        )
        XCTAssertEqual(model.profileErasurePresentation?.retryCount, 2)
        let lifecycleReadCount = await coordinator.lifecycleReadCount
        XCTAssertGreaterThanOrEqual(lifecycleReadCount, 1)
    }

    @MainActor
    func testUnreadableProfileErasureStateStaysVisibleAsUnavailable() async throws {
        let coordinator = GuardianFamilySyncCoordinatorStub(
            lifecycleReadShouldFail: true
        )
        let model = GuardianDashboardViewModel(
            store: DemoGuardianFamilyStore(),
            audioPromptService: GuardianFamilySyncSilentAudioService(),
            familySyncCoordinator: coordinator
        )

        model.showFamilySync()
        for _ in 0..<100
        where model.profileErasurePresentation?.state != .unavailable {
            try await Task.sleep(for: .milliseconds(10))
        }

        XCTAssertEqual(model.profileErasurePresentation, .unavailable)
    }

    @MainActor
    func testProfileErasureRetrySynchronizesThenRereadsLifecycle() async throws {
        let coordinator = GuardianFamilySyncCoordinatorStub(
            lifecycles: [profileErasure(.waitingForConnection, retryCount: 1)]
        )
        let model = GuardianDashboardViewModel(
            store: DemoGuardianFamilyStore(),
            audioPromptService: GuardianFamilySyncSilentAudioService(),
            familySyncCoordinator: coordinator
        )
        model.showFamilySync()
        for _ in 0..<100
        where model.profileErasurePresentation?.state != .waitingForConnection {
            try await Task.sleep(for: .milliseconds(10))
        }
        await coordinator.setLifecycles([profileErasure(.complete)])

        model.retryProfileErasure()
        for _ in 0..<100
        where model.profileErasurePresentation?.state != .complete {
            try await Task.sleep(for: .milliseconds(10))
        }

        XCTAssertEqual(model.profileErasurePresentation?.state, .complete)
        let synchronizeCallCount = await coordinator.synchronizeCallCount
        let lifecycleReadCount = await coordinator.lifecycleReadCount
        XCTAssertEqual(synchronizeCallCount, 1)
        XCTAssertGreaterThanOrEqual(lifecycleReadCount, 2)
    }

    @MainActor
    func testUnavailableRetryWhileSyncOffRereadsWithoutNoOpSynchronization()
        async throws
    {
        let coordinator = GuardianFamilySyncCoordinatorStub(
            enabled: false,
            lifecycleReadShouldFail: true
        )
        let model = GuardianDashboardViewModel(
            store: DemoGuardianFamilyStore(),
            audioPromptService: GuardianFamilySyncSilentAudioService(),
            familySyncCoordinator: coordinator
        )
        model.showFamilySync()
        for _ in 0..<100
        where model.profileErasurePresentation?.state != .unavailable {
            try await Task.sleep(for: .milliseconds(10))
        }
        await coordinator.setLifecycleReadShouldFail(false)
        await coordinator.setLifecycles([profileErasure(.requested)])

        model.retryProfileErasure()
        for _ in 0..<100
        where model.profileErasurePresentation?.state != .waitingForFamilySync {
            try await Task.sleep(for: .milliseconds(10))
        }

        XCTAssertEqual(
            model.profileErasurePresentation?.state,
            .waitingForFamilySync
        )
        let synchronizeCallCount = await coordinator.synchronizeCallCount
        let lifecycleReadCount = await coordinator.lifecycleReadCount
        XCTAssertEqual(synchronizeCallCount, 0)
        XCTAssertGreaterThanOrEqual(lifecycleReadCount, 2)
    }

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
            remoteNotificationRegistration: .failed(
                category: .connectivity,
                at: Date(timeIntervalSince1970: 1_735_689_700)
            ),
            generatedAt: Date(timeIntervalSince1970: 1_735_689_600)
        ).text

        XCTAssertTrue(report.contains("State: waiting_for_connection"))
        XCTAssertTrue(report.contains("Pending changes: 3"))
        XCTAssertTrue(report.contains("Retry count: 2"))
        XCTAssertTrue(report.contains("Next retry:"))
        XCTAssertTrue(report.contains("Push registration: failed"))
        XCTAssertTrue(report.contains("Push registration failure: connectivity"))
        XCTAssertTrue(report.contains("Push registration updated:"))
        for childPayload in [
            "Mia",
            "dog",
            "profile-photo-",
            "voiceprint",
            "payloadChecksum",
            "device token",
            "private details",
        ] {
            XCTAssertFalse(report.contains(childPayload))
        }
    }

    func testDiagnosticExportDescribesEveryRegistrationStateWithoutInventingTime() {
        let generatedAt = Date(timeIntervalSince1970: 1_735_689_600)

        let notRequested = GuardianFamilySyncDiagnosticReport(
            status: .idle,
            isEnabled: false,
            remoteNotificationRegistration: .notRequested,
            generatedAt: generatedAt
        ).text
        XCTAssertTrue(notRequested.contains("Push registration: not_requested"))
        XCTAssertFalse(notRequested.contains("Push registration updated:"))

        let pending = GuardianFamilySyncDiagnosticReport(
            status: .syncing(pendingCount: 0),
            isEnabled: true,
            remoteNotificationRegistration: .pending(since: generatedAt),
            generatedAt: generatedAt
        ).text
        XCTAssertTrue(pending.contains("Push registration: pending"))

        let registered = GuardianFamilySyncDiagnosticReport(
            status: .synced(at: generatedAt),
            isEnabled: true,
            remoteNotificationRegistration: .registered(at: generatedAt),
            generatedAt: generatedAt
        ).text
        XCTAssertTrue(registered.contains("Push registration: registered"))
        XCTAssertFalse(registered.contains("Push registration failure:"))
    }

    func testRegisteredPushPresentationDoesNotClaimCloudKitDelivery() {
        let presentation = GuardianRemoteNotificationRegistrationPresentation(
            state: .registered(at: Date(timeIntervalSince1970: 1_735_689_600))
        )

        XCTAssertEqual(
            presentation.title,
            "Background notifications registered"
        )
        XCTAssertEqual(
            presentation.message,
            "Apple registered background notifications for this app. "
                + "CloudKit delivery is checked separately."
        )
        XCTAssertFalse(
            presentation.message.localizedCaseInsensitiveContains("can receive")
        )
        XCTAssertFalse(
            presentation.message.localizedCaseInsensitiveContains(
                "iCloud change notices"
            )
        )
    }

    func testProfileErasureAggregateUsesMostSevereStateAndCountsOnlyThatState() throws {
        let presentation = try XCTUnwrap(
            GuardianProfileErasurePresentation.make(
                lifecycles: [
                    profileErasure(.complete),
                    profileErasure(.requested),
                    profileErasure(.deleting),
                    profileErasure(.waitingForConnection, retryCount: 2),
                    profileErasure(.needsAttention, retryCount: 1),
                    profileErasure(.needsAttention, retryCount: 4),
                ],
                isFamilySyncEnabled: true
            )
        )

        XCTAssertEqual(presentation.state, .needsAttention)
        XCTAssertEqual(presentation.count, 2)
        XCTAssertEqual(presentation.retryCount, 4)
        XCTAssertEqual(presentation.title, "Deletion needs attention")
        XCTAssertEqual(
            presentation.message,
            "2 deleted profiles are gone from this device, but iCloud cleanup needs you to try again."
        )
        XCTAssertTrue(presentation.showsRetryAction)
        XCTAssertEqual(
            presentation.accessibilityIdentifier,
            "guardian.sync.erasure.needs-attention"
        )
    }

    func testProfileErasureSeverityOrderIsStable() throws {
        let states: [ProfileErasureState] = [
            .complete,
            .requested,
            .deleting,
            .waitingForConnection,
            .needsAttention,
        ]
        let expected: [GuardianProfileErasureAggregateState] = [
            .complete,
            .requested,
            .deleting,
            .waitingForConnection,
            .needsAttention,
        ]

        for upperBound in states.indices {
            let presentation = try XCTUnwrap(
                GuardianProfileErasurePresentation.make(
                    lifecycles: states[...upperBound].map { profileErasure($0) },
                    isFamilySyncEnabled: true
                )
            )
            XCTAssertEqual(presentation.state, expected[upperBound])
        }
    }

    func testProfileErasureSyncOffCopyIsTruthfulAndDoesNotOfferNoOpRetry() throws {
        let presentation = try XCTUnwrap(
            GuardianProfileErasurePresentation.make(
                lifecycles: [
                    profileErasure(.requested),
                    profileErasure(.deleting),
                    profileErasure(.waitingForConnection),
                    profileErasure(.complete),
                ],
                isFamilySyncEnabled: false
            )
        )

        XCTAssertEqual(presentation.state, .waitingForFamilySync)
        XCTAssertEqual(presentation.count, 3)
        XCTAssertEqual(presentation.title, "Deletion waiting for Family Sync")
        XCTAssertEqual(
            presentation.message,
            "3 deleted profiles are already gone from this device. Turn on Family Sync to finish iCloud cleanup."
        )
        XCTAssertFalse(presentation.showsRetryAction)
    }

    func testProfileErasureNeedsAttentionRemainsVisibleWhenSyncIsOff() throws {
        let presentation = try XCTUnwrap(
            GuardianProfileErasurePresentation.make(
                lifecycles: [
                    profileErasure(.waitingForConnection),
                    profileErasure(.needsAttention, retryCount: 3),
                ],
                isFamilySyncEnabled: false
            )
        )

        XCTAssertEqual(presentation.state, .needsAttention)
        XCTAssertEqual(presentation.count, 1)
        XCTAssertEqual(
            presentation.message,
            "1 deleted profile is gone from this device. Turn on Family Sync, then try iCloud cleanup again."
        )
        XCTAssertFalse(presentation.showsRetryAction)
    }

    func testProfileErasureCompleteCopyDoesNotOverclaimParticipantDeletion() throws {
        let presentation = try XCTUnwrap(
            GuardianProfileErasurePresentation.make(
                lifecycles: [
                    profileErasure(.complete, route: .owner),
                    profileErasure(.complete, route: .participant),
                ],
                isFamilySyncEnabled: true
            )
        )

        XCTAssertEqual(presentation.state, .complete)
        XCTAssertEqual(presentation.count, 2)
        XCTAssertEqual(presentation.title, "Profile removal complete")
        XCTAssertEqual(
            presentation.message,
            "Remote cleanup for 2 deleted profiles has finished."
        )
        XCTAssertFalse(presentation.message.localizedCaseInsensitiveContains("everywhere"))
        XCTAssertFalse(presentation.message.localizedCaseInsensitiveContains("owner"))
        XCTAssertFalse(presentation.message.localizedCaseInsensitiveContains("participant"))
        XCTAssertFalse(presentation.showsRetryAction)
    }

    func testProfileErasureAggregateIsAbsentWithoutLifecycleHistory() {
        XCTAssertNil(
            GuardianProfileErasurePresentation.make(
                lifecycles: [],
                isFamilySyncEnabled: true
            )
        )
    }

    func testProfileErasureUnavailableIsPersistentNeedsAttentionWithoutFalseCount() {
        let presentation = GuardianProfileErasurePresentation.unavailable

        XCTAssertEqual(presentation.state, .unavailable)
        XCTAssertNil(presentation.count)
        XCTAssertNil(presentation.retryCount)
        XCTAssertEqual(presentation.title, "Deletion status needs attention")
        XCTAssertEqual(
            presentation.message,
            "Tada Words couldn’t read the saved deletion status. No child data was restored or replaced. Try again."
        )
        XCTAssertTrue(presentation.showsRetryAction)
        XCTAssertEqual(
            presentation.accessibilityIdentifier,
            "guardian.sync.erasure.unavailable"
        )
    }

    func testUnavailableDiagnosticDoesNotInventErasureCounts() {
        let report = GuardianFamilySyncDiagnosticReport(
            status: .failed(message: "Local data is safe.", pendingCount: 1),
            isEnabled: true,
            profileErasure: .unavailable,
            generatedAt: Date(timeIntervalSince1970: 1_735_689_600)
        ).text

        XCTAssertTrue(report.contains("Profile erasure state: unavailable"))
        XCTAssertTrue(report.contains("Profile erasure count: unavailable"))
        XCTAssertTrue(report.contains("Profile erasure retry count: unavailable"))
        XCTAssertFalse(report.contains("Profile erasure count: 0"))
    }

    func testDiagnosticExportIncludesOnlyAggregateProfileErasureState() throws {
        let first = profileErasure(.waitingForConnection, retryCount: 2)
        let second = profileErasure(.waitingForConnection, retryCount: 5)
        let presentation = try XCTUnwrap(
            GuardianProfileErasurePresentation.make(
                lifecycles: [first, second],
                isFamilySyncEnabled: true
            )
        )

        let report = GuardianFamilySyncDiagnosticReport(
            status: .pendingOffline(pendingCount: 2),
            isEnabled: true,
            profileErasure: presentation,
            generatedAt: Date(timeIntervalSince1970: 1_735_689_600)
        ).text

        XCTAssertTrue(report.contains("Profile erasure state: waiting_for_connection"))
        XCTAssertTrue(report.contains("Profile erasure count: 2"))
        XCTAssertTrue(report.contains("Profile erasure retry count: 5"))
        XCTAssertFalse(report.contains(first.profileID.description))
        XCTAssertFalse(report.contains(second.profileID.description))
        XCTAssertFalse(report.localizedCaseInsensitiveContains("owner"))
        XCTAssertFalse(report.localizedCaseInsensitiveContains("participant"))
    }
}

private func profileErasure(
    _ state: ProfileErasureState,
    route: ProfileErasureRoute = .unresolved,
    retryCount: Int = 0
) -> ProfileErasureLifecycle {
    ProfileErasureLifecycle(
        profileID: ProfileID(),
        route: route,
        state: state,
        requestedAt: Date(timeIntervalSince1970: 1_735_689_600),
        attemptCount: retryCount,
        retryCount: retryCount,
        lastAttemptAt: retryCount > 0
            ? Date(timeIntervalSince1970: 1_735_689_700)
            : nil,
        nextRetryAt: state == .waitingForConnection
            ? Date(timeIntervalSince1970: 1_735_690_000)
            : nil,
        lastSuccessAt: state == .complete
            ? Date(timeIntervalSince1970: 1_735_690_100)
            : nil,
        errorCategory: state == .needsAttention ? .unknown : nil
    )
}

private enum GuardianFamilySyncCoordinatorStubError: Error {
    case lifecycleUnavailable
}

private actor GuardianFamilySyncCoordinatorStub: FamilySyncCoordinating {
    private var enabled: Bool
    private var lifecycles: [ProfileErasureLifecycle]
    private var lifecycleReadShouldFail: Bool
    private(set) var synchronizeCallCount = 0
    private(set) var lifecycleReadCount = 0

    init(
        enabled: Bool = true,
        lifecycles: [ProfileErasureLifecycle] = [],
        lifecycleReadShouldFail: Bool = false
    ) {
        self.enabled = enabled
        self.lifecycles = lifecycles
        self.lifecycleReadShouldFail = lifecycleReadShouldFail
    }

    func isEnabled() async -> Bool { enabled }

    func setEnabled(_ isEnabled: Bool) async throws -> FamilySyncStatus {
        enabled = isEnabled
        return isEnabled
            ? .synced(at: Date(timeIntervalSince1970: 1_735_689_600))
            : .optedOut(message: "Family sync is off.")
    }

    func synchronize() async -> FamilySyncStatus {
        synchronizeCallCount += 1
        return .synced(at: Date(timeIntervalSince1970: 1_735_689_600))
    }

    func status() async -> FamilySyncStatus {
        enabled
            ? .synced(at: Date(timeIntervalSince1970: 1_735_689_600))
            : .optedOut(message: "Family sync is off.")
    }

    func profileErasureLifecycles() async throws -> [ProfileErasureLifecycle] {
        lifecycleReadCount += 1
        if lifecycleReadShouldFail {
            throw GuardianFamilySyncCoordinatorStubError.lifecycleUnavailable
        }
        return lifecycles
    }

    func setLifecycles(_ lifecycles: [ProfileErasureLifecycle]) {
        self.lifecycles = lifecycles
    }

    func setLifecycleReadShouldFail(_ shouldFail: Bool) {
        lifecycleReadShouldFail = shouldFail
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
