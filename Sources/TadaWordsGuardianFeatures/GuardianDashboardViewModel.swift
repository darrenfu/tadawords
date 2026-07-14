import Foundation
import SwiftUI
import TadaWordsDomain

enum GuardianDestination {
    case parentGate
    case dashboard
    case profiles
    case profileEditor(KidProfile?)
    case quickAdd
    case pool(LearningMode)
    case reports
    case settings
    case familySync
    case voiceprint(KidProfile)
    case importReport(GuardianWordImportReport)
}

@MainActor
final class GuardianDashboardViewModel: ObservableObject {
    @Published private(set) var destination: GuardianDestination = .parentGate
    @Published private(set) var snapshot: GuardianDashboardSnapshot?
    @Published private(set) var familySnapshot: GuardianFamilySnapshot?
    @Published private(set) var isLoading = false
    @Published private(set) var report: GuardianLearningReport?
    @Published private(set) var reportPeriod: GuardianReportPeriod = .sevenDays
    @Published var errorMessage: String?
    @Published private(set) var syncStatus: FamilySyncStatus = .idle
    @Published private(set) var isFamilySyncEnabled = false
    @Published private(set) var shareURL: URL?
    @Published var shareURLText = ""
    @Published private(set) var voiceprintProgress: VoiceprintEnrollmentProgress?
    @Published private(set) var isCapturingVoiceprint = false

    private let store: any GuardianFamilyStore
    private let audioPromptService: any AudioPromptService
    private let audioExperienceService: any AudioExperienceService
    private let familySyncCoordinator: (any FamilySyncCoordinating)?
    private let notificationScheduler: (any LearningNotificationScheduling)?
    private let voiceprintEnrollmentService: (any DeviceVoiceprintEnrolling)?
    private let voiceprintRepository: (any DeviceVoiceprintRepository)?
    private let requestSpeechAuthorization: @Sendable () async -> Bool
    private let sensitiveActionAuthorizer: any SensitiveGuardianActionAuthorizing
    private var isUpdatingWordPool = false

    init(
        store: any GuardianFamilyStore,
        audioPromptService: any AudioPromptService,
        audioExperienceService: any AudioExperienceService =
            SilentAudioExperienceService(),
        familySyncCoordinator: (any FamilySyncCoordinating)? = nil,
        notificationScheduler: (any LearningNotificationScheduling)? = nil,
        voiceprintEnrollmentService: (any DeviceVoiceprintEnrolling)? = nil,
        voiceprintRepository: (any DeviceVoiceprintRepository)? = nil,
        requestSpeechAuthorization: @escaping @Sendable () async -> Bool = { false },
        sensitiveActionAuthorizer: any SensitiveGuardianActionAuthorizing =
            AllowSensitiveGuardianActions()
    ) {
        self.store = store
        self.audioPromptService = audioPromptService
        self.audioExperienceService = audioExperienceService
        self.familySyncCoordinator = familySyncCoordinator
        self.notificationScheduler = notificationScheduler
        self.voiceprintEnrollmentService = voiceprintEnrollmentService
        self.voiceprintRepository = voiceprintRepository
        self.requestSpeechAuthorization = requestSpeechAuthorization
        self.sensitiveActionAuthorizer = sensitiveActionAuthorizer
    }

    var transitionKey: String {
        switch destination {
        case .parentGate:
            "parent-gate"
        case .dashboard:
            "dashboard"
        case .profiles:
            "profiles"
        case .profileEditor(let profile):
            "profile-editor-\(profile?.id.description ?? "new")"
        case .quickAdd:
            "quick-add"
        case .pool(let mode):
            "pool-\(mode.rawValue)"
        case .reports:
            "reports-\(reportPeriod.rawValue)"
        case .settings:
            "settings"
        case .familySync:
            "family-sync"
        case .voiceprint(let profile):
            "voiceprint-\(profile.id)"
        case .importReport(let report):
            "report-\(report.learningMode.rawValue)-\(report.processedCount)"
        }
    }

    func unlockGuardianArea() {
        destination = .dashboard
        refresh()
    }

    func lockGuardianArea() {
        destination = .parentGate
    }

    func showDashboard() {
        destination = .dashboard
    }

    func showQuickAdd() {
        destination = .quickAdd
    }

    func showProfiles() {
        destination = .profiles
    }

    func showNewProfile() {
        destination = .profileEditor(nil)
    }

    func showEditProfile(_ profile: KidProfile) {
        destination = .profileEditor(profile)
    }

    func showPool(_ mode: LearningMode) {
        destination = .pool(mode)
    }

    func showSettings() {
        destination = .settings
    }

    func showReports() {
        destination = .reports
        loadReport(period: reportPeriod)
    }

    func authorizeReportExport() async -> Bool {
        await sensitiveActionAuthorizer.authorize(.exportLearningData)
    }

    func showFamilySync() {
        destination = .familySync
        refreshSyncStatus()
    }

    func showVoiceprint(_ profile: KidProfile) {
        voiceprintProgress = nil
        destination = .voiceprint(profile)
    }

    func loadReport(period: GuardianReportPeriod) {
        guard !isLoading else { return }
        reportPeriod = period
        isLoading = true
        Task {
            defer { isLoading = false }
            do {
                report = try await store.report(for: period)
            } catch {
                errorMessage = "The learning report could not be loaded. Please try again."
            }
        }
    }

    func refresh() {
        guard !isLoading else { return }
        isLoading = true

        Task {
            defer { isLoading = false }
            do {
                async let loadedFamily = store.familySnapshot()
                async let loadedDashboard = store.dashboardSnapshot()
                let (family, dashboard) = try await (
                    loadedFamily,
                    loadedDashboard
                )
                familySnapshot = family
                snapshot = dashboard
                await applyAudioSnapshot()
            } catch {
                errorMessage = "Family data could not be loaded. Please try again."
            }
        }
    }

    func selectProfile(_ profile: KidProfile) {
        guard !isLoading else { return }
        isLoading = true

        Task {
            defer { isLoading = false }
            do {
                snapshot = try await store.selectProfile(id: profile.id)
                await applyAudioSnapshot()
                familySnapshot = try await store.familySnapshot()
                destination = .dashboard
            } catch {
                errorMessage = "That child profile could not be opened. Please try again."
            }
        }
    }

    func saveProfile(
        existingProfile: KidProfile?,
        draft: GuardianProfileDraft
    ) {
        guard !isLoading else { return }
        isLoading = true

        Task {
            defer { isLoading = false }
            do {
                if let existingProfile {
                    snapshot = try await store.updateProfile(
                        id: existingProfile.id,
                        from: draft
                    )
                } else {
                    snapshot = try await store.createProfile(from: draft)
                }
                familySnapshot = try await store.familySnapshot()
                await applyAudioSnapshot()
                destination = .dashboard
            } catch let error as GuardianFamilyStoreError {
                errorMessage = Self.profileErrorMessage(error)
            } catch {
                errorMessage = "That child profile could not be saved. Please try again."
            }
        }
    }

    func deleteProfile(_ profile: KidProfile) {
        guard !isLoading else { return }
        isLoading = true
        Task {
            defer { isLoading = false }
            do {
                guard await sensitiveActionAuthorizer.authorize(.deleteProfile) else {
                    return
                }
                let deletion = try await store.deleteProfile(id: profile.id)
                try? await voiceprintRepository?.delete(for: profile.id)
                await notificationScheduler?.removeNotifications(for: profile.id)
                snapshot = deletion.dashboard
                familySnapshot = try await store.familySnapshot()
                destination = .dashboard
            } catch let error as GuardianFamilyStoreError {
                errorMessage = Self.profileErrorMessage(error)
            } catch {
                errorMessage =
                    "That child profile could not be deleted. No further changes were made."
            }
        }
    }

    func correctAttempt(id: AttemptID, to outcome: AttemptOutcome) {
        guard !isLoading else { return }
        isLoading = true
        Task {
            defer { isLoading = false }
            do {
                _ = try await store.correctAttempt(id: id, to: outcome)
                report = try await store.report(for: reportPeriod)
                snapshot = try await store.dashboardSnapshot()
            } catch {
                errorMessage = "That recognition result could not be corrected. Please try again."
            }
        }
    }

    func importWords(_ request: GuardianWordImportRequest) {
        guard !isLoading else { return }
        isLoading = true

        Task {
            defer { isLoading = false }
            let report: GuardianWordImportReport
            do {
                report = try await store.importWords(request)
            } catch {
                errorMessage = "Those words could not be added. Your existing pools are unchanged."
                return
            }

            do {
                snapshot = try await store.dashboardSnapshot()
                destination = .importReport(report)
            } catch {
                destination = .importReport(report)
                errorMessage =
                    "The words were added, but the dashboard could not refresh. Reopen it to try again."
            }
        }
    }

    func addWords(
        _ request: GuardianWordImportRequest
    ) async -> GuardianWordImportReport? {
        guard !isUpdatingWordPool else { return nil }
        isUpdatingWordPool = true
        defer { isUpdatingWordPool = false }

        let report: GuardianWordImportReport
        do {
            report = try await store.importWords(request)
        } catch {
            errorMessage = "Those words could not be added. Your existing pools are unchanged."
            return nil
        }

        do {
            snapshot = try await store.dashboardSnapshot()
        } catch {
            errorMessage =
                "The words were added, but the list could not refresh. Reopen Manage Words to try again."
        }
        return report
    }

    func play(_ prompt: WordPrompt) {
        guard let profileID = snapshot?.profile.id else { return }

        Task {
            do {
                try await audioPromptService.play(prompt, for: profileID)
            } catch {
                errorMessage = "The pronunciation could not be played. Please try again."
            }
        }
    }

    func deactivate(_ prompt: WordPrompt) {
        guard !isLoading else { return }
        isLoading = true

        Task {
            defer { isLoading = false }
            do {
                snapshot = try await store.deactivateWord(
                    id: prompt.id,
                    learningMode: prompt.learningMode
                )
            } catch {
                errorMessage =
                    "That word could not be removed from the active pool. Please try again."
            }
        }
    }

    func setWordsActive(
        _ prompts: [WordPrompt],
        isActive: Bool
    ) async -> Bool {
        guard !isUpdatingWordPool, let mode = prompts.first?.learningMode else {
            return false
        }
        guard prompts.allSatisfy({ $0.learningMode == mode }) else {
            errorMessage = "Read and Write words must be managed separately."
            return false
        }

        isUpdatingWordPool = true
        defer { isUpdatingWordPool = false }
        do {
            snapshot = try await store.setWordsActive(
                ids: prompts.map(\.id),
                learningMode: mode,
                isActive: isActive
            )
            return true
        } catch {
            errorMessage =
                isActive
                ? "Those words could not be restored. Please try again."
                : "Those words could not be removed. Please try again."
            return false
        }
    }

    func savePracticeSettings(_ settings: ProfilePracticeSettings) {
        guard !isLoading else { return }
        isLoading = true

        Task {
            defer { isLoading = false }
            do {
                let updated = try await store.updatePracticeSettings(settings)
                snapshot = updated
                await reconcileNotifications(for: updated)
                await applyAudioSnapshot()
                destination = .dashboard
            } catch {
                errorMessage = "Practice settings could not be saved. Please try again."
            }
        }
    }

    var guardianSyncState: GuardianSyncState {
        switch syncStatus {
        case .idle, .deviceOnly, .iCloudUnavailable:
            .thisDeviceOnly
        case .optedOut:
            .off
        case .syncing, .pendingOffline:
            .pending
        case .synced:
            .upToDate
        case .failed:
            .failed
        }
    }

    func syncNow() {
        guard let familySyncCoordinator, isFamilySyncEnabled else { return }
        Task {
            syncStatus = await familySyncCoordinator.synchronize()
        }
    }

    func setFamilySyncEnabled(_ isEnabled: Bool) {
        guard let familySyncCoordinator else { return }
        Task {
            if isEnabled,
                !(await sensitiveActionAuthorizer.authorize(.enableFamilySync))
            {
                return
            }
            do {
                syncStatus = try await familySyncCoordinator.setEnabled(isEnabled)
                isFamilySyncEnabled = await familySyncCoordinator.isEnabled()
                if !isFamilySyncEnabled {
                    shareURL = nil
                    shareURLText = ""
                }
            } catch {
                isFamilySyncEnabled = await familySyncCoordinator.isEnabled()
                errorMessage =
                    isEnabled
                    ? "Family sync could not be turned on. Learning data is still saved on this device."
                    : "Family sync could not be turned off. Please try again."
            }
        }
    }

    func createFamilyShare() {
        guard isFamilySyncEnabled,
            let familySyncCoordinator,
            let profileID = snapshot?.profile.id
        else {
            return
        }
        Task {
            guard await sensitiveActionAuthorizer.authorize(.manageGuardians) else {
                return
            }
            do {
                shareURL = try await familySyncCoordinator.createShare(for: profileID)
                syncStatus = await familySyncCoordinator.status()
            } catch {
                errorMessage = "A family invitation could not be created. Local data is safe."
            }
        }
    }

    func acceptFamilyShare() {
        guard isFamilySyncEnabled,
            let familySyncCoordinator,
            let url = URL(string: shareURLText.trimmingCharacters(in: .whitespacesAndNewlines))
        else {
            errorMessage = "Paste a valid family invitation link."
            return
        }
        Task {
            guard await sensitiveActionAuthorizer.authorize(.manageGuardians) else {
                return
            }
            do {
                try await familySyncCoordinator.acceptShare(at: url)
                syncStatus = await familySyncCoordinator.status()
                refresh()
            } catch {
                errorMessage = "That family invitation could not be accepted."
            }
        }
    }

    func beginVoiceprint(for profile: KidProfile) {
        guard let voiceprintEnrollmentService else {
            errorMessage = "Voice setup is unavailable on this device."
            return
        }
        Task {
            guard await requestSpeechAuthorization() else {
                errorMessage = "Microphone and speech access are needed for voice setup."
                return
            }
            do {
                voiceprintProgress = try await voiceprintEnrollmentService.begin(
                    profileID: profile.id
                )
            } catch {
                errorMessage = "Voice setup could not start. Please try again."
            }
        }
    }

    func captureVoiceprintSegment() {
        guard let voiceprintEnrollmentService, !isCapturingVoiceprint else { return }
        isCapturingVoiceprint = true
        Task {
            defer { isCapturingVoiceprint = false }
            do {
                let result = try await voiceprintEnrollmentService.captureSegment()
                voiceprintProgress = result.progress
                if result.rejectionReason != nil {
                    errorMessage = "That sample was not clear enough. Try again in a quiet spot."
                }
            } catch {
                errorMessage = "That voice sample could not be recorded. Please try again."
            }
        }
    }

    func finishVoiceprint(for profile: KidProfile) {
        guard let voiceprintEnrollmentService else { return }
        isLoading = true
        Task {
            defer { isLoading = false }
            do {
                let template = try await voiceprintEnrollmentService.finalize()
                snapshot = try await store.updateVoiceprintStatus(
                    profileID: profile.id,
                    status: .enrolled(
                        modelVersion: template.embedding.modelIdentifier,
                        enrolledAt: template.enrolledAt
                    )
                )
                familySnapshot = try await store.familySnapshot()
                destination = .profiles
            } catch {
                errorMessage = "Voice setup is not ready yet. Record a few more samples."
            }
        }
    }

    func cancelVoiceprint() {
        Task { await voiceprintEnrollmentService?.cancel() }
        voiceprintProgress = nil
        destination = .profiles
    }

    private func refreshSyncStatus() {
        guard let familySyncCoordinator else {
            isFamilySyncEnabled = false
            syncStatus = .deviceOnly(
                message: "Learning data is saved on this device."
            )
            return
        }
        Task {
            async let enabled = familySyncCoordinator.isEnabled()
            async let status = familySyncCoordinator.status()
            isFamilySyncEnabled = await enabled
            syncStatus = await status
        }
    }

    private func reconcileNotifications(
        for snapshot: GuardianDashboardSnapshot
    ) async {
        guard let notificationScheduler else { return }
        let preferences = snapshot.practiceSettings.notifications
        if preferences.hasEnabledNotifications {
            var authorization = await notificationScheduler.authorizationStatus()
            if authorization == .notDetermined {
                authorization = await notificationScheduler.requestAuthorization()
            }
            guard authorization == .authorized else {
                await notificationScheduler.removeNotifications(for: snapshot.profile.id)
                return
            }
        }
        do {
            try await notificationScheduler.reconcile(
                preferences: preferences,
                context: LearningNotificationContext(
                    profileID: snapshot.profile.id,
                    readPoolCount: snapshot.readPool.count,
                    writePoolCount: snapshot.writePool.count,
                    completedQuestCountToday: snapshot.todaySummary.completedQuestCount,
                    hasPendingSyncFailure: guardianSyncState == .failed,
                    weeklyAttentionCount: snapshot.needsAttention.count
                ),
                calendar: .current
            )
        } catch {
            errorMessage = "Settings were saved, but reminders could not be updated."
        }
    }

    private func applyAudioSnapshot() async {
        guard let snapshot else { return }
        await audioExperienceService.activate(
            world: snapshot.profile.selectedWorld,
            preferences: snapshot.practiceSettings.audio
        )
        await audioExperienceService.stopAmbientAudio()
    }

    private static func profileErrorMessage(
        _ error: GuardianFamilyStoreError
    ) -> String {
        switch error {
        case .profileNotFound:
            "That child profile is no longer available."
        case .emptyDisplayName:
            "Enter a nickname for this child."
        case .displayNameTooLong(let maximumCharacterCount):
            "Use no more than \(maximumCharacterCount) characters for the nickname."
        case .unsupportedAvatar:
            "Choose one of the available animal icons."
        case .invalidAge:
            "Choose an age from 2 through 18."
        case .cannotDeleteOnlyProfile:
            "Keep at least one child profile."
        case .learningHistoryUnavailable:
            "Learning history is not available right now."
        }
    }
}
