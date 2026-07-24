import Foundation
import SwiftUI
import TadaWordsDomain

enum GuardianParentSection: String, CaseIterable, Equatable {
    case wordsAndPractice
    case progressAndPerformance
    case appAndFamily
}

enum GuardianSettingsSection: String, CaseIterable, Equatable {
    case practicePlan
    case soundAndAccessibility
    case notifications

    var parentSection: GuardianParentSection {
        switch self {
        case .practicePlan:
            .wordsAndPractice
        case .soundAndAccessibility, .notifications:
            .appAndFamily
        }
    }
}

enum GuardianSettingsMergePolicy {
    static func merging(
        edited: ProfilePracticeSettings,
        section: GuardianSettingsSection,
        into current: ProfilePracticeSettings
    ) -> ProfilePracticeSettings? {
        guard edited.profileID == current.profileID else { return nil }

        switch section {
        case .practicePlan:
            return ProfilePracticeSettings(
                profileID: current.profileID,
                read: edited.read,
                write: edited.write,
                audio: current.audio,
                notifications: current.notifications,
                interface: current.interface,
                wordRecommendationMode: current.wordRecommendationMode
            )
        case .soundAndAccessibility:
            return ProfilePracticeSettings(
                profileID: current.profileID,
                read: current.read,
                write: current.write,
                audio: edited.audio,
                notifications: current.notifications,
                interface: edited.interface,
                wordRecommendationMode: current.wordRecommendationMode
            )
        case .notifications:
            return ProfilePracticeSettings(
                profileID: current.profileID,
                read: current.read,
                write: current.write,
                audio: current.audio,
                notifications: edited.notifications,
                interface: current.interface,
                wordRecommendationMode: current.wordRecommendationMode
            )
        }
    }
}

enum GuardianDestination {
    case parentGate
    case dashboard
    case parentSection(GuardianParentSection)
    case profiles
    case profileEditor(KidProfile?)
    case quickAdd
    case presetWords
    case pool(LearningMode)
    case reports
    case settings(GuardianSettingsSection)
    case speechPermissions
    case familySync
    case thirdPartyNotices
    case voiceprint(KidProfile)
    case importReport(GuardianWordImportReport)

    var parentSectionForBack: GuardianParentSection? {
        switch self {
        case .quickAdd, .presetWords, .pool, .importReport:
            .wordsAndPractice
        case .reports:
            .progressAndPerformance
        case .settings(let section):
            section.parentSection
        case .speechPermissions, .familySync, .thirdPartyNotices:
            .appAndFamily
        case .parentGate, .dashboard, .parentSection, .profiles, .profileEditor,
            .voiceprint:
            nil
        }
    }
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
    @Published private(set) var profileErasurePresentation: GuardianProfileErasurePresentation?
    @Published private(set) var shareURL: URL?
    @Published var shareURLText = ""
    @Published private(set) var voiceprintProgress: VoiceprintEnrollmentProgress?
    @Published private(set) var isCapturingVoiceprint = false
    @Published private(set) var currentVoiceprintSentence: String?
    @Published private(set) var currentVoiceprintSampleNumber = 0
    @Published private(set) var voiceprintSampleCount =
        VoiceprintEnrollmentScript.sentences.count
    @Published private(set) var isPlayingVoiceprintPrompt = false
    @Published private(set) var voiceprintGuidanceMessage: String?
    @Published private(set) var hasConfirmedWordRemovalThisSession = false
    @Published private(set) var undoWordsByMode: [LearningMode: [WordPrompt]] = [:]
    @Published private(set) var isUpdatingWordPool = false
    @Published private(set) var speechPermissionState: SpeechPermissionState = .unavailable
    @Published private(set) var isRequestingSpeechPermissions = false

    private let store: any GuardianFamilyStore
    private let audioPromptService: any AudioPromptService
    private let audioExperienceService: any AudioExperienceService
    private let familySyncCoordinator: (any FamilySyncCoordinating)?
    private let familySyncAccessManagement: (@MainActor (ProfileID) async throws -> Void)?
    private let notificationScheduler: (any LearningNotificationScheduling)?
    private let voiceprintEnrollmentService: (any DeviceVoiceprintEnrolling)?
    private let voiceprintRepository: (any DeviceVoiceprintRepository)?
    private let currentSpeechPermissionState: @Sendable () async -> SpeechPermissionState
    private let requestSpeechPermissions: @Sendable () async -> SpeechPermissionState
    private let sensitiveActionAuthorizer: any SensitiveGuardianActionAuthorizing
    private let pictureHintProvider: any WordPictureHintProviding
    private var confirmedWordRemovalProfileIDs = Set<ProfileID>()
    private var undoWordsByProfile: [ProfileID: [LearningMode: [WordPrompt]]] = [:]
    private var voiceprintSentences: [String] = []
    private var voiceprintPromptTask: Task<Void, Never>?
    private var pendingProfileAutoSave: (profileID: ProfileID, draft: GuardianProfileDraft)?
    private var profileAutoSaveTask: Task<Void, Never>?
    private var externalSyncRefreshGeneration: UInt64 = 0
    private var syncPresentationRefreshGeneration: UInt64 = 0

    init(
        store: any GuardianFamilyStore,
        audioPromptService: any AudioPromptService,
        audioExperienceService: any AudioExperienceService =
            SilentAudioExperienceService(),
        familySyncCoordinator: (any FamilySyncCoordinating)? = nil,
        familySyncAccessManagement:
            (@MainActor (ProfileID) async throws -> Void)? = nil,
        notificationScheduler: (any LearningNotificationScheduling)? = nil,
        voiceprintEnrollmentService: (any DeviceVoiceprintEnrolling)? = nil,
        voiceprintRepository: (any DeviceVoiceprintRepository)? = nil,
        currentSpeechPermissionState:
            @escaping @Sendable () async -> SpeechPermissionState = { .unavailable },
        requestSpeechPermissions:
            @escaping @Sendable () async -> SpeechPermissionState = { .unavailable },
        pictureHintProvider: any WordPictureHintProviding =
            NoWordPictureHintProvider(),
        sensitiveActionAuthorizer: any SensitiveGuardianActionAuthorizing =
            AllowSensitiveGuardianActions()
    ) {
        self.store = store
        self.audioPromptService = audioPromptService
        self.audioExperienceService = audioExperienceService
        self.familySyncCoordinator = familySyncCoordinator
        self.familySyncAccessManagement = familySyncAccessManagement
        self.notificationScheduler = notificationScheduler
        self.voiceprintEnrollmentService = voiceprintEnrollmentService
        self.voiceprintRepository = voiceprintRepository
        self.currentSpeechPermissionState = currentSpeechPermissionState
        self.requestSpeechPermissions = requestSpeechPermissions
        self.pictureHintProvider = pictureHintProvider
        self.sensitiveActionAuthorizer = sensitiveActionAuthorizer
    }

    var transitionKey: String {
        switch destination {
        case .parentGate:
            "parent-gate"
        case .dashboard:
            "dashboard"
        case .parentSection(let section):
            "parent-section-\(section.rawValue)"
        case .profiles:
            "profiles"
        case .profileEditor(let profile):
            "profile-editor-\(profile?.id.description ?? "new")"
        case .quickAdd:
            "quick-add"
        case .presetWords:
            "preset-words"
        case .pool(let mode):
            "pool-\(mode.rawValue)"
        case .reports:
            "reports-\(reportPeriod.rawValue)"
        case .settings(let section):
            "settings-\(section.rawValue)"
        case .speechPermissions:
            "speech-permissions"
        case .familySync:
            "family-sync"
        case .thirdPartyNotices:
            "third-party-notices"
        case .voiceprint(let profile):
            "voiceprint-\(profile.id)"
        case .importReport(let report):
            "report-\(report.learningMode.rawValue)-\(report.processedCount)"
        }
    }

    func unlockGuardianArea() {
        resetWordRemovalSession()
        destination = .dashboard
        refresh()
        refreshSyncStatus()
    }

    func lockGuardianArea() {
        resetWordRemovalSession()
        destination = .parentGate
    }

    func showDashboard() {
        destination = .dashboard
    }

    func showWordsAndPractice() {
        destination = .parentSection(.wordsAndPractice)
    }

    func showProgressAndPerformance() {
        destination = .parentSection(.progressAndPerformance)
    }

    func showAppAndFamily() {
        destination = .parentSection(.appAndFamily)
        refreshSpeechPermissionState()
    }

    func returnToParentSection() {
        guard let parentSection = destination.parentSectionForBack else {
            destination = .dashboard
            return
        }
        destination = .parentSection(parentSection)
    }

    func showQuickAdd() {
        destination = .quickAdd
    }

    func showPresetWords() {
        destination = .presetWords
    }

    func showProfiles() {
        destination = .profiles
    }

    /// An empty family has no dashboard to return to. Closing Parents returns
    /// the app to the first-run Profile creation flow instead of trapping the
    /// parent between an empty chooser and editor.
    @discardableResult
    func returnFromProfiles() -> Bool {
        guard familySnapshot?.profiles.isEmpty == true else {
            showDashboard()
            return false
        }
        lockGuardianArea()
        return true
    }

    func showNewProfile() {
        destination = .profileEditor(nil)
    }

    @discardableResult
    func returnFromProfileEditor() -> Bool {
        guard familySnapshot?.profiles.isEmpty == true else {
            showProfiles()
            return false
        }
        lockGuardianArea()
        return true
    }

    func showEditProfile(_ profile: KidProfile) {
        destination = .profileEditor(profile)
    }

    func showPool(_ mode: LearningMode) {
        destination = .pool(mode)
    }

    func showSettings(_ section: GuardianSettingsSection) {
        destination = .settings(section)
    }

    func showSpeechPermissions() {
        destination = .speechPermissions
        refreshSpeechPermissionState()
    }

    func refreshSpeechPermissionState() {
        Task {
            await refreshSpeechPermissionStateAndWait()
        }
    }

    func refreshSpeechPermissionStateAndWait() async {
        speechPermissionState = await currentSpeechPermissionState()
    }

    func setUpSpeechPermissions() {
        guard !isRequestingSpeechPermissions else { return }
        Task {
            await setUpSpeechPermissionsAndWait()
        }
    }

    func setUpSpeechPermissionsAndWait() async {
        guard !isRequestingSpeechPermissions else { return }
        isRequestingSpeechPermissions = true
        defer { isRequestingSpeechPermissions = false }
        speechPermissionState = await requestSpeechPermissions()
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

    func returnFromFamilySync() {
        guard snapshot == nil else {
            returnToParentSection()
            return
        }
        destination =
            familySnapshot?.profiles.isEmpty == false
            ? .profiles
            : .profileEditor(nil)
    }

    func showThirdPartyNotices() {
        destination = .thirdPartyNotices
    }

    func showVoiceprint(_ profile: KidProfile) {
        guard VoiceprintReleasePolicy.shipsEnrollmentAndSpeakerMatching else {
            return
        }
        voiceprintPromptTask?.cancel()
        voiceprintProgress = nil
        currentVoiceprintSentence = nil
        currentVoiceprintSampleNumber = 0
        voiceprintGuidanceMessage = nil
        voiceprintSentences = []
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
                let family = try await store.familySnapshot()
                familySnapshot = family
                guard let selectedProfileID = family.selectedProfileID else {
                    snapshot = nil
                    report = nil
                    destination = .profileEditor(nil)
                    await audioExperienceService.stopAmbientAudio()
                    return
                }
                let dashboard = try await store.dashboardSnapshot(
                    for: selectedProfileID
                )
                showWordRemovalState(for: dashboard.profile.id)
                snapshot = dashboard
                await applyAudioSnapshot()
            } catch GuardianFamilyStoreError.profileNotFound,
                GuardianFamilyStoreError.noProfiles
            {
                familySnapshot = try? await store.familySnapshot()
                snapshot = nil
                report = nil
                destination = .profileEditor(nil)
            } catch {
                errorMessage = "Family data could not be loaded. Please try again."
            }
        }
    }

    /// Applies a committed Family Sync refresh without resetting the parent's
    /// navigation. If the Profile currently being viewed was deleted on
    /// another device, move to the Profile chooser immediately.
    func refreshAfterExternalSyncAndWait() async {
        externalSyncRefreshGeneration &+= 1
        let refreshGeneration = externalSyncRefreshGeneration
        let previouslyVisibleProfileID = snapshot?.profile.id
        do {
            var family = try await store.familySnapshot()
            try Task.checkCancellation()
            guard refreshGeneration == externalSyncRefreshGeneration else {
                return
            }
            let visibleProfileStillExists =
                previouslyVisibleProfileID.map {
                    profileID in
                    family.profiles.contains(where: { $0.id == profileID })
                } ?? false
            guard
                let targetProfileID =
                    visibleProfileStillExists
                    ? previouslyVisibleProfileID
                    : family.selectedProfileID
            else {
                throw GuardianFamilyStoreError.noProfiles
            }
            let dashboard: GuardianDashboardSnapshot
            if visibleProfileStillExists {
                dashboard = try await store.dashboardSnapshot(
                    for: targetProfileID
                )
            } else {
                guard refreshGeneration == externalSyncRefreshGeneration else {
                    return
                }
                dashboard = try await store.selectProfile(id: targetProfileID)
                family = try await store.familySnapshot()
            }
            let refreshedReport: GuardianLearningReport?
            if case .reports = destination {
                refreshedReport = try await store.report(for: reportPeriod)
            } else {
                refreshedReport = nil
            }
            try Task.checkCancellation()
            guard refreshGeneration == externalSyncRefreshGeneration else {
                return
            }
            familySnapshot = family
            snapshot = dashboard
            showWordRemovalState(for: dashboard.profile.id)
            if previouslyVisibleProfileID != nil, !visibleProfileStillExists {
                destination = .profiles
            }
            if let refreshedReport {
                report = refreshedReport
            }
            await applyAudioSnapshot()
        } catch GuardianFamilyStoreError.profileNotFound,
            GuardianFamilyStoreError.noProfiles
        {
            // A remote owner can remove the final shared Profile. Keep the
            // parent in a recoverable creation flow instead of a stale editor.
            let emptyFamily = try? await store.familySnapshot()
            guard refreshGeneration == externalSyncRefreshGeneration else {
                return
            }
            familySnapshot = emptyFamily
            snapshot = nil
            report = nil
            destination = .profileEditor(nil)
            await audioExperienceService.stopAmbientAudio()
        } catch is CancellationError {
            return
        } catch {
            guard refreshGeneration == externalSyncRefreshGeneration else {
                return
            }
            errorMessage =
                "Family Sync finished, but this page could not refresh. Please try again."
        }
        guard refreshGeneration == externalSyncRefreshGeneration else {
            return
        }
        await refreshSyncStatusAndWait()
    }

    func selectProfile(_ profile: KidProfile) {
        guard !isLoading else { return }
        isLoading = true

        Task {
            defer { isLoading = false }
            do {
                let selectedDashboard = try await store.selectProfile(id: profile.id)
                showWordRemovalState(for: selectedDashboard.profile.id)
                snapshot = selectedDashboard
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
        if let existingProfile {
            pendingProfileAutoSave = (existingProfile.id, draft)
            guard profileAutoSaveTask == nil else { return }
            profileAutoSaveTask = Task { [weak self] in
                try? await Task.sleep(for: .milliseconds(250))
                await self?.drainProfileAutoSaves()
            }
            return
        }

        guard !isLoading else { return }
        isLoading = true

        Task {
            defer { isLoading = false }
            do {
                let savedDashboard: GuardianDashboardSnapshot
                savedDashboard = try await store.createProfile(from: draft)
                showWordRemovalState(for: savedDashboard.profile.id)
                snapshot = savedDashboard
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

    private func drainProfileAutoSaves() async {
        defer { profileAutoSaveTask = nil }

        while let pendingProfileAutoSave {
            self.pendingProfileAutoSave = nil
            do {
                let savedDashboard = try await store.updateProfile(
                    id: pendingProfileAutoSave.profileID,
                    from: pendingProfileAutoSave.draft
                )
                showWordRemovalState(for: savedDashboard.profile.id)
                snapshot = savedDashboard
                familySnapshot = try await store.familySnapshot()
                await applyAudioSnapshot()
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
                await notificationScheduler?.removeNotifications(for: profile.id)
                undoWordsByProfile[profile.id] = nil
                confirmedWordRemovalProfileIDs.remove(profile.id)
                if let dashboard = deletion.dashboard {
                    showWordRemovalState(for: dashboard.profile.id)
                    snapshot = dashboard
                } else {
                    snapshot = nil
                    report = nil
                }
                familySnapshot = deletion.family
                destination = .familySync
                refreshSyncStatus()
            } catch let error as GuardianFamilyStoreError {
                errorMessage = Self.profileErrorMessage(error)
            } catch {
                errorMessage =
                    "Deletion paused safely. Try again; deleted data will not be restored."
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
                errorMessage = Self.wordImportErrorMessage(error)
                return
            }

            prefetchPictures(for: report)

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
        guard let profileID = await currentProfileID() else { return nil }
        return await performWordImport(request, for: profileID)
    }

    func addPresetWords(
        _ request: GuardianWordImportRequest,
        for profileID: ProfileID
    ) async -> GuardianWordImportReport? {
        await performWordImport(request, for: profileID)
    }

    private func performWordImport(
        _ request: GuardianWordImportRequest,
        for profileID: ProfileID
    ) async -> GuardianWordImportReport? {
        guard !isUpdatingWordPool else { return nil }
        isUpdatingWordPool = true
        defer { isUpdatingWordPool = false }

        let report: GuardianWordImportReport
        do {
            report = try await store.importWords(request, for: profileID)
        } catch {
            errorMessage = Self.wordImportErrorMessage(error)
            return nil
        }
        guard report.profileID == profileID else {
            errorMessage = "Those words could not be added to the selected kid. Please try again."
            return nil
        }

        prefetchPictures(for: report)

        do {
            let refreshed = try await store.dashboardSnapshot(for: profileID)
            if snapshot == nil || snapshot?.profile.id == profileID {
                snapshot = refreshed
            }
        } catch {
            errorMessage =
                "The words were added, but the list could not refresh. Reopen Manage Words to try again."
        }
        return report
    }

    static func wordImportErrorMessage(_ error: Error) -> String {
        if let audioError = error as? TeacherWordAudioError {
            switch audioError {
            case .unconfiguredEndpoint, .invalidEndpoint:
                return """
                    Teacher audio is not available in this build yet. \
                    No words were added; your existing pools are unchanged.
                    """
            case .serverRejected(statusCode: 429):
                return """
                    Teacher audio is temporarily busy. Wait a moment and try \
                    again; your existing pools are unchanged.
                    """
            case .serverRejected(statusCode: 401), .appAttestUnavailable:
                return """
                    This device could not verify the teacher-audio request. \
                    Try again from this Parent screen; no words were added.
                    """
            case .invalidResponse, .emptyAudio, .responseTooLarge,
                .unsupportedContentType, .invalidAudioChecksum,
                .mismatchedAudioContract, .persistentCacheUnavailable:
                return """
                    Teacher audio could not be verified, so no words were added. \
                    Please try again later.
                    """
            case .serverRejected, .unavailableOfflineClip,
                .emptySpokenText, .invalidIsolatedWord:
                break
            }
        }
        if error is URLError {
            return """
                Connect to the internet and try adding those words again. \
                Your existing pools are unchanged.
                """
        }
        return "Those words could not be added. Your existing pools are unchanged."
    }

    /// Reverses only memberships changed by an incomplete preset import. This
    /// deliberately does not publish a user-facing Undo action: the parent
    /// already receives a retryable preset selection after the rollback.
    func rollbackPresetAdditions(
        _ request: GuardianPresetRollbackRequest
    ) async -> Bool {
        guard !isUpdatingWordPool else { return false }
        guard !request.membershipIDs.isEmpty else { return true }

        isUpdatingWordPool = true
        defer { isUpdatingWordPool = false }
        do {
            try await store.setMembershipsActive(
                ids: request.membershipIDs,
                learningMode: request.learningMode,
                isActive: false,
                for: request.profileID
            )
            do {
                let refreshed = try await store.dashboardSnapshot(
                    for: request.profileID
                )
                if snapshot == nil || snapshot?.profile.id == request.profileID {
                    snapshot = refreshed
                }
            } catch {
                // The exact-ID rollback already committed. A dashboard refresh
                // is best-effort and must never turn a successful rollback into
                // a false partial-import warning.
                errorMessage =
                    "The preset Add was rolled back, but the list could not refresh. Reopen Manage Words to try again."
            }
            return true
        } catch {
            errorMessage =
                "An incomplete preset import could not be rolled back. Review both pools before trying again."
            return false
        }
    }

    private func prefetchPictures(for report: GuardianWordImportReport) {
        let words = report.accepted + report.duplicates
        guard !words.isEmpty else { return }
        let provider = pictureHintProvider
        Task {
            await provider.prefetch(words)
        }
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
        guard let profileID = await currentProfileID() else { return false }
        guard
            !isUpdatingWordPool,
            let mode = prompts.first?.learningMode
        else {
            return false
        }
        guard prompts.allSatisfy({ $0.learningMode == mode }) else {
            errorMessage = "Read and Write words must be managed separately."
            return false
        }

        isUpdatingWordPool = true
        defer { isUpdatingWordPool = false }
        do {
            let updatedSnapshot = try await store.setWordsActive(
                ids: prompts.map(\.id),
                learningMode: mode,
                isActive: isActive,
                for: profileID
            )
            if snapshot == nil || snapshot?.profile.id == profileID {
                snapshot = updatedSnapshot
            }
            saveUndoWords(
                isActive ? nil : prompts,
                mode: mode,
                profileID: profileID
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

    func setWordRemovalConfirmation(_ isConfirmed: Bool) {
        guard let profileID = snapshot?.profile.id else { return }
        if isConfirmed {
            confirmedWordRemovalProfileIDs.insert(profileID)
        } else {
            confirmedWordRemovalProfileIDs.remove(profileID)
        }
        hasConfirmedWordRemovalThisSession = isConfirmed
    }

    func savePracticeSettings(
        _ settings: ProfilePracticeSettings,
        section: GuardianSettingsSection
    ) {
        guard !isLoading else { return }
        guard let currentSettings = snapshot?.practiceSettings else {
            errorMessage = "Practice settings could not be loaded. Please try again."
            return
        }
        guard
            let scopedSettings = GuardianSettingsMergePolicy.merging(
                edited: settings,
                section: section,
                into: currentSettings
            )
        else {
            errorMessage = "Practice settings belong to a different Kid profile."
            return
        }
        isLoading = true

        Task {
            defer { isLoading = false }
            do {
                let updated = try await store.updatePracticeSettings(scopedSettings)
                snapshot = updated
                await reconcileNotifications(for: updated)
                await applyAudioSnapshot()
                destination = .parentSection(section.parentSection)
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

    var canManageFamilyAccess: Bool {
        familySyncAccessManagement != nil
    }

    func syncNow() {
        guard let familySyncCoordinator, isFamilySyncEnabled else { return }
        Task {
            syncStatus = await familySyncCoordinator.synchronize()
            await refreshProfileErasurePresentation(
                using: familySyncCoordinator,
                isEnabled: isFamilySyncEnabled
            )
        }
    }

    func retryProfileErasure() {
        guard let familySyncCoordinator else { return }
        Task {
            let isEnabled = await familySyncCoordinator.isEnabled()
            isFamilySyncEnabled = isEnabled
            if isEnabled {
                syncStatus = await familySyncCoordinator.retryProfileErasures()
            } else {
                syncStatus = await familySyncCoordinator.status()
            }
            await refreshProfileErasurePresentation(
                using: familySyncCoordinator,
                isEnabled: isEnabled
            )
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
                // Family Sync can be enabled after the app has finished its
                // bootstrap task. Register here as well, otherwise APNs stays
                // unrequested until a later relaunch and a background device
                // cannot be woken for a remote family change.
                if isFamilySyncEnabled {
                    await FamilySyncRemoteNotificationBridge.shared
                        .requestRegistration()
                } else {
                    await FamilySyncRemoteNotificationBridge.shared
                        .requestUnregistration()
                }
                if !isFamilySyncEnabled {
                    shareURL = nil
                    shareURLText = ""
                }
                await refreshProfileErasurePresentation(
                    using: familySyncCoordinator,
                    isEnabled: isFamilySyncEnabled
                )
            } catch {
                isFamilySyncEnabled = await familySyncCoordinator.isEnabled()
                await refreshProfileErasurePresentation(
                    using: familySyncCoordinator,
                    isEnabled: isFamilySyncEnabled
                )
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

    func manageFamilyAccess() {
        guard isFamilySyncEnabled,
            let familySyncAccessManagement,
            let profileID = snapshot?.profile.id
        else { return }
        Task {
            guard await sensitiveActionAuthorizer.authorize(.manageGuardians) else {
                return
            }
            do {
                try await familySyncAccessManagement(profileID)
            } catch {
                errorMessage =
                    "Family access could not be opened. Local data is safe."
            }
        }
    }

    func beginVoiceprint(for profile: KidProfile) {
        guard VoiceprintReleasePolicy.shipsEnrollmentAndSpeakerMatching else {
            errorMessage = "Voice setup is not included in this release."
            return
        }
        guard let voiceprintEnrollmentService else {
            errorMessage = "Voice setup is unavailable on this device."
            return
        }
        Task {
            voiceprintGuidanceMessage = nil
            guard (await requestSpeechPermissions()).isAuthorized else {
                errorMessage = "Microphone and speech access are needed for voice setup."
                return
            }
            do {
                voiceprintSentences = VoiceprintEnrollmentScript.randomizedSentences()
                voiceprintSampleCount = voiceprintSentences.count
                voiceprintProgress = try await voiceprintEnrollmentService.begin(
                    profileID: profile.id
                )
                selectVoiceprintSentence(forAcceptedSampleCount: 0)
                await playCurrentVoiceprintSentence(for: profile.id)
            } catch {
                errorMessage = "Voice setup could not start. Please try again."
            }
        }
    }

    func captureVoiceprintSegment() {
        guard let voiceprintEnrollmentService,
            !isCapturingVoiceprint,
            !isPlayingVoiceprintPrompt
        else { return }
        isCapturingVoiceprint = true
        voiceprintGuidanceMessage = "Listening… repeat the sentence now."
        Task {
            defer { isCapturingVoiceprint = false }
            do {
                let result = try await voiceprintEnrollmentService.captureSegment()
                voiceprintProgress = result.progress
                if let reason = result.rejectionReason {
                    voiceprintGuidanceMessage = voiceprintGuidance(for: reason)
                } else if result.progress.isReadyToFinalize {
                    currentVoiceprintSentence = nil
                    currentVoiceprintSampleNumber = voiceprintSampleCount
                    voiceprintGuidanceMessage = "Voice setup is ready to finish."
                } else {
                    voiceprintGuidanceMessage = "Great sample! Here is the next sentence."
                    selectVoiceprintSentence(
                        forAcceptedSampleCount: result.progress.acceptedSegmentCount
                    )
                    if case .voiceprint(let profile) = destination {
                        await playCurrentVoiceprintSentence(for: profile.id)
                    }
                }
            } catch {
                voiceprintGuidanceMessage =
                    "The microphone did not start. Keep the device unlocked, check microphone access, and try this sentence again."
            }
        }
    }

    func replayVoiceprintSentence(for profile: KidProfile) {
        guard !isCapturingVoiceprint, !isPlayingVoiceprintPrompt else { return }
        voiceprintPromptTask?.cancel()
        voiceprintPromptTask = Task {
            await playCurrentVoiceprintSentence(for: profile.id)
        }
    }

    func finishVoiceprint(for profile: KidProfile) {
        guard let voiceprintEnrollmentService else { return }
        isLoading = true
        Task {
            defer { isLoading = false }
            do {
                let template = try await voiceprintEnrollmentService.finalize()
                let updatedDashboard = try await store.updateVoiceprintStatus(
                    profileID: profile.id,
                    status: .enrolled(
                        modelVersion: template.embedding.modelIdentifier,
                        enrolledAt: template.enrolledAt
                    )
                )
                showWordRemovalState(for: updatedDashboard.profile.id)
                snapshot = updatedDashboard
                familySnapshot = try await store.familySnapshot()
                destination = .profiles
            } catch {
                errorMessage = "Voice setup is not ready yet. Record a few more samples."
            }
        }
    }

    func cancelVoiceprint() {
        voiceprintPromptTask?.cancel()
        voiceprintPromptTask = nil
        Task { await voiceprintEnrollmentService?.cancel() }
        voiceprintProgress = nil
        currentVoiceprintSentence = nil
        currentVoiceprintSampleNumber = 0
        voiceprintGuidanceMessage = nil
        destination = .profiles
    }

    private func selectVoiceprintSentence(forAcceptedSampleCount count: Int) {
        guard !voiceprintSentences.isEmpty else {
            currentVoiceprintSentence = nil
            currentVoiceprintSampleNumber = 0
            return
        }
        let index = min(max(0, count), voiceprintSentences.count - 1)
        currentVoiceprintSentence = voiceprintSentences[index]
        currentVoiceprintSampleNumber = index + 1
    }

    private func playCurrentVoiceprintSentence(for profileID: ProfileID) async {
        guard let sentence = currentVoiceprintSentence else { return }
        isPlayingVoiceprintPrompt = true
        voiceprintGuidanceMessage = "Listen, then tap Record and repeat it."
        defer { isPlayingVoiceprintPrompt = false }
        do {
            try await audioPromptService.playVoiceSetupSentence(
                sentence,
                for: profileID
            )
        } catch is CancellationError {
            return
        } catch {
            voiceprintGuidanceMessage =
                "Read the sentence aloud, or tap Hear sentence to try the audio again."
        }
    }

    private func voiceprintGuidance(
        for reason: VoiceprintSegmentRejectionReason
    ) -> String {
        switch reason {
        case .noSpeech:
            "We did not hear a voice. Move closer and repeat the sentence."
        case .tooShort:
            "Say the whole sentence, a little more slowly."
        case .tooLong:
            "Try the sentence once, without extra words."
        case .tooNoisy, .multipleSpeakers:
            "Let one child speak in a quieter spot, then try again."
        case .modelMismatch, .dimensionMismatch, .technicalFailure:
            "That sample could not be used. Keep the device unlocked and try again."
        }
    }

    private func refreshSyncStatus() {
        Task {
            await refreshSyncStatusAndWait()
        }
    }

    private func refreshSyncStatusAndWait() async {
        syncPresentationRefreshGeneration &+= 1
        let refreshGeneration = syncPresentationRefreshGeneration
        guard let familySyncCoordinator else {
            guard refreshGeneration == syncPresentationRefreshGeneration else {
                return
            }
            isFamilySyncEnabled = false
            profileErasurePresentation = nil
            syncStatus = .deviceOnly(
                message: "Learning data is saved on this device."
            )
            return
        }
        async let enabled = familySyncCoordinator.isEnabled()
        async let status = familySyncCoordinator.status()
        let resolvedEnabled = await enabled
        let resolvedStatus = await status
        let erasurePresentation = await profileErasurePresentation(
            using: familySyncCoordinator,
            isEnabled: resolvedEnabled
        )
        guard refreshGeneration == syncPresentationRefreshGeneration else {
            return
        }
        isFamilySyncEnabled = resolvedEnabled
        syncStatus = resolvedStatus
        profileErasurePresentation = erasurePresentation
    }

    private func refreshProfileErasurePresentation(
        using familySyncCoordinator: any FamilySyncCoordinating,
        isEnabled: Bool
    ) async {
        syncPresentationRefreshGeneration &+= 1
        let refreshGeneration = syncPresentationRefreshGeneration
        let presentation = await profileErasurePresentation(
            using: familySyncCoordinator,
            isEnabled: isEnabled
        )
        guard refreshGeneration == syncPresentationRefreshGeneration else {
            return
        }
        profileErasurePresentation = presentation
    }

    private func profileErasurePresentation(
        using familySyncCoordinator: any FamilySyncCoordinating,
        isEnabled: Bool
    ) async -> GuardianProfileErasurePresentation? {
        do {
            return GuardianProfileErasurePresentation.make(
                lifecycles: try await familySyncCoordinator.profileErasureLifecycles(),
                isFamilySyncEnabled: isEnabled
            )
        } catch {
            return .unavailable
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

    private func currentProfileID() async -> ProfileID? {
        if let profileID = snapshot?.profile.id { return profileID }
        return try? await store.familySnapshot().selectedProfileID
    }

    private func resetWordRemovalSession() {
        confirmedWordRemovalProfileIDs = []
        undoWordsByProfile = [:]
        hasConfirmedWordRemovalThisSession = false
        undoWordsByMode = [:]
    }

    private func showWordRemovalState(for profileID: ProfileID) {
        hasConfirmedWordRemovalThisSession =
            confirmedWordRemovalProfileIDs.contains(profileID)
        undoWordsByMode = undoWordsByProfile[profileID, default: [:]]
    }

    private func saveUndoWords(
        _ prompts: [WordPrompt]?,
        mode: LearningMode,
        profileID: ProfileID
    ) {
        var profileUndoWords = undoWordsByProfile[profileID, default: [:]]
        profileUndoWords[mode] = prompts
        if profileUndoWords.isEmpty {
            undoWordsByProfile[profileID] = nil
        } else {
            undoWordsByProfile[profileID] = profileUndoWords
        }
        if snapshot?.profile.id == profileID {
            undoWordsByMode = profileUndoWords
        }
    }

    private static func profileErrorMessage(
        _ error: GuardianFamilyStoreError
    ) -> String {
        switch error {
        case .profileNotFound:
            "That child profile is no longer available."
        case .noProfiles:
            "Add a child profile to continue."
        case .emptyDisplayName:
            "Enter a nickname for this child."
        case .displayNameTooLong(let maximumCharacterCount):
            "Use no more than \(maximumCharacterCount) characters for the nickname."
        case .unsupportedAvatar:
            "Choose one of the available animal icons."
        case .invalidAge:
            "Choose an age from 2 through 18."
        case .learningHistoryUnavailable:
            "Learning history is not available right now."
        }
    }
}
