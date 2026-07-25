import Foundation
import SwiftUI
import TadaWordsContent
import TadaWordsDesignSystem
import TadaWordsDomain
import TadaWordsLearning

@MainActor
final class TadaWordsAppModel: ObservableObject {
    @Published private(set) var destination: AppDestination = .profileChooser
    @Published private(set) var selectedProfile: KidProfile?
    @Published private(set) var lastPlayedProfileID: ProfileID?
    @Published private(set) var todayRouteStatuses: [LearningMode: TodayQuestRouteStatus] = [:]
    @Published private(set) var calendarMonthSummary: DailyQuestMonthSummary?
    @Published private(set) var isCalendarLoading = false
    @Published private(set) var calendarLoadFailed = false
    @Published private(set) var profiles: [KidProfile]
    @Published private(set) var isCreatingChildProfile = false
    @Published private(set) var childProfileCreationError: String?
    @Published private(set) var worldProgression: WorldProgression?
    @Published private(set) var rewardCollections: [WorldTheme: RewardCollection] = [:]
    @Published private(set) var worldSelectionError: String?
    @Published private(set) var rechargingModes: Set<LearningMode> = []

    private let contentProvider: any QuestContentProviding
    private let audioPromptService: any AudioPromptService
    private let audioExperienceService: any AudioExperienceService
    private let practiceSettingsRepository: (any PracticeSettingsRepository)?
    private let attemptEventRepository: any AttemptEventRepository
    private let wordProgressRepository: any WordProgressRepository
    private let dailyQuestCoordinator: DailyQuestCoordinator
    private let clock: any AppClock
    private let timeZone: TimeZone
    private let progressReducer: WordProgressReducer
    private let questTimerFactory: (TimeInterval) -> QuestTimerModel
    private let childSessionRepository: (any ChildSessionRepository)?
    private let childProfileCreator: (any ChildProfileCreating)?
    private let profileRepository: (any KidProfileRepository)?
    private let profileMutationGate: ProfileScopedMutationGate?
    private let onLearningDataChanged: @Sendable () async -> Void

    private var activeQuest: ActiveQuest?
    private var pendingCompletion: PendingItemCompletion?
    private var preparationTask: Task<Void, Never>?
    private var persistenceTask: Task<Void, Never>?
    private var activePreparationID: UUID?
    private var routeStatusTask: Task<Void, Never>?
    private var calendarTask: Task<Void, Never>?
    private var profileSelectionTask: Task<Void, Never>?
    private var handwritingToolTask: Task<Void, Never>?
    private var worldProgressTask: Task<Void, Never>?
    private var focusedReplaySeed: FocusedReplaySeed?
    private var pendingWritePreparationIntent: QuestPreparationIntent = .standard
    private var lastPracticeWordOrderByMode: [LearningMode: [WordPromptID]] = [:]
    private var isApplicationActive = true
    private var externalSyncRefreshGeneration: UInt64 = 0

    init(
        profiles: [KidProfile] = .previewProfiles,
        contentProvider: any QuestContentProviding = UnavailableQuestContentProvider(),
        audioPromptService: any AudioPromptService = SilentAudioPromptService(),
        audioExperienceService: any AudioExperienceService =
            SilentAudioExperienceService(),
        practiceSettingsRepository: (any PracticeSettingsRepository)? = nil,
        attemptEventRepository: any AttemptEventRepository =
            UnavailableAttemptEventRepository(),
        wordProgressRepository: any WordProgressRepository =
            UnavailableWordProgressRepository(),
        dailyQuestCoordinator: DailyQuestCoordinator = DailyQuestCoordinator(
            repository: InMemoryDailyQuestRepository(),
            timeZone: .current
        ),
        clock: any AppClock = SystemAppClock(),
        timeZone: TimeZone = .current,
        initialProfileID: ProfileID? = nil,
        childSessionRepository: (any ChildSessionRepository)? = nil,
        childProfileCreator: (any ChildProfileCreating)? = nil,
        profileRepository: (any KidProfileRepository)? = nil,
        profileMutationGate: ProfileScopedMutationGate? = nil,
        progressReducer: WordProgressReducer = WordProgressReducer(),
        onLearningDataChanged: @escaping @Sendable () async -> Void = {},
        questTimerFactory: @escaping (TimeInterval) -> QuestTimerModel = {
            QuestTimerModel(emergencyAfter: $0)
        }
    ) {
        self.profiles = profiles
        self.contentProvider = contentProvider
        self.audioPromptService = audioPromptService
        self.audioExperienceService = audioExperienceService
        self.practiceSettingsRepository = practiceSettingsRepository
        self.attemptEventRepository = attemptEventRepository
        self.wordProgressRepository = wordProgressRepository
        self.dailyQuestCoordinator = dailyQuestCoordinator
        self.clock = clock
        self.timeZone = timeZone
        self.childSessionRepository = childSessionRepository
        self.childProfileCreator = childProfileCreator
        self.profileRepository = profileRepository
        self.profileMutationGate = profileMutationGate
        self.progressReducer = progressReducer
        self.onLearningDataChanged = onLearningDataChanged
        self.questTimerFactory = questTimerFactory
        lastPlayedProfileID = initialProfileID.flatMap { rememberedID in
            profiles.contains(where: { $0.id == rememberedID }) ? rememberedID : nil
        }
    }

    var selectedTheme: TadaWorldTheme {
        guard let selectedProfile else { return .moonpetal }
        return TadaWorldTheme.from(selectedProfile.selectedWorld)
    }

    func selectProfile(_ profile: KidProfile) {
        guard let currentProfile = profiles.first(where: { $0.id == profile.id }) else {
            return
        }
        applyProfileSelection(currentProfile)
        profileSelectionTask?.cancel()
        profileSelectionTask = Task { [weak self] in
            await self?.persistLastSelectedProfile(currentProfile.id)
        }
    }

    func selectProfileAndWait(_ profile: KidProfile) async {
        guard let currentProfile = profiles.first(where: { $0.id == profile.id }) else {
            return
        }
        applyProfileSelection(currentProfile)
        await persistLastSelectedProfile(currentProfile.id)
    }

    @discardableResult
    func createChildProfileAndWait(
        nickname: String,
        ageYears: Int?
    ) async -> Bool {
        guard !isCreatingChildProfile else { return false }
        guard let ageYears, ProfileAgePolicy.isSupported(ageYears) else {
            childProfileCreationError = Self.message(for: .invalidAge)
            return false
        }
        guard let childProfileCreator else {
            childProfileCreationError = Self.creationFailureMessage
            return false
        }
        isCreatingChildProfile = true
        childProfileCreationError = nil
        do {
            let profile = try await childProfileCreator.createProfile(
                displayName: nickname,
                ageYears: ageYears,
                existingProfiles: profiles
            )
            profiles.append(profile)
            profiles.sort(by: Self.isProfileOrderedBefore)
            isCreatingChildProfile = false
            await selectProfileAndWait(profile)
            Task { await onLearningDataChanged() }
            return true
        } catch let error as ChildProfileCreationError {
            isCreatingChildProfile = false
            childProfileCreationError = Self.message(for: error)
            return false
        } catch {
            isCreatingChildProfile = false
            childProfileCreationError = Self.creationFailureMessage
            return false
        }
    }

    func clearChildProfileCreationError() {
        childProfileCreationError = nil
    }

    private func applyProfileSelection(_ profile: KidProfile) {
        abandonActiveQuest()
        focusedReplaySeed = nil
        rechargingModes.removeAll()
        lastPracticeWordOrderByMode = [:]
        routeStatusTask?.cancel()
        calendarTask?.cancel()
        todayRouteStatuses = [:]
        calendarMonthSummary = nil
        worldProgression = nil
        rewardCollections = [:]
        calendarLoadFailed = false
        selectedProfile = profile
        lastPlayedProfileID = profile.id
        destination = .lobby
        beginProfileServices(for: profile)
    }

    private func beginProfileServices(for profile: KidProfile) {
        Task { [weak self] in
            await self?.activateAudio(for: profile)
        }
        routeStatusTask = Task { [weak self] in
            await self?.refreshTodayRouteStatuses(for: profile)
        }
        refreshCalendar()
        refreshWorldProgress()
    }

    func showProfiles() {
        abandonActiveQuest()
        focusedReplaySeed = nil
        rechargingModes.removeAll()
        lastPracticeWordOrderByMode = [:]
        routeStatusTask?.cancel()
        routeStatusTask = nil
        calendarTask?.cancel()
        calendarTask = nil
        todayRouteStatuses = [:]
        calendarMonthSummary = nil
        worldProgressTask?.cancel()
        worldProgression = nil
        rewardCollections = [:]
        selectedProfile = nil
        Task {
            await audioExperienceService.stopAmbientAudio()
        }
        destination = .profileChooser
    }

    func showLobby() {
        abandonActiveQuest()
        focusedReplaySeed = nil
        pendingWritePreparationIntent = .standard
        rechargingModes.removeAll()
        destination = .lobby
        refreshCalendar()
        refreshWorldProgress()
    }

    func refreshWorldProgress() {
        guard let selectedProfile else { return }
        worldProgressTask?.cancel()
        worldProgressTask = Task { [weak self] in
            await self?.loadWorldProgress(for: selectedProfile)
        }
    }

    func refreshWorldProgressAndWait() async {
        guard let selectedProfile else { return }
        worldProgressTask?.cancel()
        await loadWorldProgress(for: selectedProfile)
    }

    func selectWorld(_ world: WorldTheme) {
        worldProgressTask?.cancel()
        worldProgressTask = Task { [weak self] in
            await self?.selectWorldAndWait(world)
        }
    }

    func selectWorldAndWait(_ world: WorldTheme) async {
        guard let profile = selectedProfile,
            worldProgression?.state(for: world)?.isUnlocked == true,
            world != profile.selectedWorld,
            let profileRepository
        else { return }
        let updated = profileSelection(
            from: profile,
            world: world,
            cartoonIconAssetID: profile.selectedCartoonIconAssetID,
            treasureAvatar: profile.selectedTreasureAvatar
        )
        do {
            try await saveProfileSelection(
                updated,
                in: profileRepository,
                shouldRefreshAudio: true
            )
        } catch {
            worldSelectionError = "Ask a parent to try changing worlds again."
        }
    }

    func clearWorldSelectionError() {
        worldSelectionError = nil
    }

    func selectHandwritingTool(_ tool: HandwritingTool) {
        guard let profileID = selectedProfile?.id,
            let practiceSettingsRepository
        else { return }
        handwritingToolTask?.cancel()
        handwritingToolTask = Task { [weak self] in
            guard let self, !Task.isCancelled else { return }
            do {
                let current =
                    try await practiceSettingsRepository.settings(
                        for: profileID
                    ) ?? .defaults(for: profileID)
                guard !Task.isCancelled,
                    current.interface.selectedHandwritingTool != tool
                else { return }
                let updated = ProfilePracticeSettings(
                    profileID: current.profileID,
                    read: current.read,
                    write: current.write,
                    audio: current.audio,
                    notifications: current.notifications,
                    interface: PracticeInterfacePreferences(
                        leftHandedLayoutEnabled:
                            current.interface.leftHandedLayoutEnabled,
                        selectedHandwritingTool: tool
                    ),
                    wordRecommendationMode: current.wordRecommendationMode
                )
                try await practiceSettingsRepository.save(updated)
                guard !Task.isCancelled else { return }
                await onLearningDataChanged()
            } catch {
                // Tool choice is non-blocking child UI. The in-quest selection
                // remains usable and a later choice retries persistence.
            }
        }
    }

    func selectCartoonIcon(_ assetID: String) {
        worldProgressTask?.cancel()
        worldProgressTask = Task { [weak self] in
            await self?.selectCartoonIconAndWait(assetID)
        }
    }

    func selectCartoonIconAndWait(_ assetID: String) async {
        guard let profile = selectedProfile,
            worldProgression?.unlockedCartoonIconAssetIDs.contains(assetID) == true,
            profile.selectedCartoonIconAssetID != assetID,
            let profileRepository
        else { return }
        let updated = profileSelection(
            from: profile,
            world: profile.selectedWorld,
            cartoonIconAssetID: assetID,
            treasureAvatar: nil
        )
        do {
            try await saveProfileSelection(updated, in: profileRepository)
        } catch {
            worldSelectionError = "Ask a parent to try changing your icon again."
        }
    }

    func selectTreasureAvatar(_ item: RewardCatalogItem) {
        worldProgressTask?.cancel()
        worldProgressTask = Task { [weak self] in
            await self?.selectTreasureAvatarAndWait(item)
        }
    }

    func selectTreasureAvatarAndWait(_ item: RewardCatalogItem) async {
        let selection = TreasureAvatarSelection(
            rewardItemID: item.id,
            iconAssetID: item.iconAssetID
        )
        guard let profile = selectedProfile,
            profile.selectedTreasureAvatar != selection,
            rewardCollections[item.world]?.items.contains(where: {
                $0.item.id == item.id && $0.isCollected
            }) == true,
            let profileRepository
        else { return }
        let updated = profileSelection(
            from: profile,
            world: profile.selectedWorld,
            cartoonIconAssetID: nil,
            treasureAvatar: selection
        )
        do {
            try await saveProfileSelection(updated, in: profileRepository)
        } catch {
            worldSelectionError = "Ask a parent to try changing your icon again."
        }
    }

    func selectOriginalAvatar() {
        worldProgressTask?.cancel()
        worldProgressTask = Task { [weak self] in
            await self?.selectOriginalAvatarAndWait()
        }
    }

    func selectOriginalAvatarAndWait() async {
        guard let profile = selectedProfile,
            profile.selectedCartoonIconAssetID != nil
                || profile.selectedTreasureAvatar != nil,
            let profileRepository
        else { return }
        let updated = profileSelection(
            from: profile,
            world: profile.selectedWorld,
            cartoonIconAssetID: nil,
            treasureAvatar: nil
        )
        do {
            try await saveProfileSelection(updated, in: profileRepository)
        } catch {
            worldSelectionError = "Ask a parent to try changing your icon again."
        }
    }

    func availability(for mode: LearningMode) -> QuestAvailability {
        guard let selectedProfile else { return .blocked(.emptyPool) }
        return contentProvider.availability(for: mode, profile: selectedProfile)
    }

    func todayRouteStatus(for mode: LearningMode) -> TodayQuestRouteStatus {
        todayRouteStatuses[mode] ?? .ready
    }

    func refreshTodayRouteStatusesAndWait() async {
        guard let selectedProfile else { return }
        await refreshTodayRouteStatuses(for: selectedProfile)
    }

    var currentLocalDay: LocalDay {
        LocalDay(date: clock.now, timeZone: timeZone)
    }

    func refreshCalendar() {
        guard let selectedProfile else { return }
        calendarTask?.cancel()
        isCalendarLoading = true
        calendarLoadFailed = false
        calendarTask = Task { [weak self] in
            await self?.loadCalendar(for: selectedProfile)
        }
    }

    func refreshCalendarAndWait() async {
        guard let selectedProfile else { return }
        calendarTask?.cancel()
        isCalendarLoading = true
        calendarLoadFailed = false
        await loadCalendar(for: selectedProfile)
    }

    /// Routes Write through the child-facing response chooser while Read keeps
    /// its direct one-tap launch.
    func chooseQuest(_ mode: LearningMode) {
        guard mode == .write else {
            startQuest(mode)
            return
        }
        guard let profile = selectedProfile else {
            destination = .profileChooser
            return
        }
        switch contentProvider.availability(for: .write, profile: profile) {
        case .available:
            abandonActiveQuest()
            focusedReplaySeed = nil
            pendingWritePreparationIntent = .standard
            destination = .writeInputChooser
            Task { await audioExperienceService.play(.click) }
        case .blocked:
            startQuest(.write)
        }
    }

    func startWriteQuest(using inputMethod: WriteQuestInputMethod) {
        let intent = pendingWritePreparationIntent
        pendingWritePreparationIntent = .standard
        startQuest(
            .write,
            writeInputMethod: inputMethod,
            writeInputMethodSource: .explicitChooserSelection,
            intent: intent
        )
    }

    /// Loads another reward-free batch after Today is complete. Write keeps
    /// the same explicit Handwriting/Typing choice as the ordinary route.
    func rechargeQuest(_ mode: LearningMode) {
        guard todayRouteStatus(for: mode).action == .practiceAgain,
            !rechargingModes.contains(mode)
        else { return }
        if mode == .write {
            guard let profile = selectedProfile else { return }
            guard
                case .available = contentProvider.availability(
                    for: mode,
                    profile: profile
                )
            else { return }
            pendingWritePreparationIntent = .freestyleRecharge
            destination = .writeInputChooser
            return
        }
        startQuest(mode, intent: .freestyleRecharge)
    }

    /// Async test seam for both recharge routes.
    func rechargeQuestAndWait(
        _ mode: LearningMode,
        writeInputMethod: WriteQuestInputMethod = .handwriting
    ) async {
        guard todayRouteStatus(for: mode).action == .practiceAgain,
            !rechargingModes.contains(mode),
            let request = beginPreparation(
                for: mode,
                writeInputMethod: writeInputMethod,
                writeInputMethodSource: .explicitChooserSelection,
                intent: .freestyleRecharge
            )
        else { return }
        await loadPreparedQuest(request)
    }

    /// Async test/integration seam for the same explicit chooser path.
    func startWriteQuestAndWait(using inputMethod: WriteQuestInputMethod) async {
        let intent = pendingWritePreparationIntent
        pendingWritePreparationIntent = .standard
        guard
            let request = beginPreparation(
                for: .write,
                writeInputMethod: inputMethod,
                writeInputMethodSource: .explicitChooserSelection,
                intent: intent
            )
        else { return }
        await loadPreparedQuest(request)
    }

    func startQuest(
        _ mode: LearningMode,
        writeInputMethod: WriteQuestInputMethod = .handwriting,
        writeInputMethodSource: WriteInputMethodSource = .recoveryFallback,
        intent: QuestPreparationIntent = .standard
    ) {
        guard
            let request = beginPreparation(
                for: mode,
                writeInputMethod: writeInputMethod,
                writeInputMethodSource: writeInputMethodSource,
                intent: intent
            )
        else { return }
        Task {
            await audioExperienceService.play(.click)
        }
        preparationTask = Task { [weak self] in
            await self?.loadPreparedQuest(request)
        }
    }

    func replayMissedWords() {
        guard let request = beginFocusedReplayPreparation() else { return }
        Task {
            await audioExperienceService.play(.click)
        }
        preparationTask = Task { [weak self] in
            await self?.loadFocusedReplay(request)
        }
    }

    /// Async test/integration seam for the focused replay path.
    func replayMissedWordsAndWait() async {
        guard let request = beginFocusedReplayPreparation() else { return }
        await loadFocusedReplay(request)
    }

    func setApplicationActive(_ isActive: Bool) {
        guard isApplicationActive != isActive else { return }
        isApplicationActive = isActive
        if isActive {
            activeQuest?.timer.resume(from: .appInactive)
            refreshWorldProgress()
        } else {
            activeQuest?.timer.suspend(for: .appInactive)
        }
        Task {
            await audioExperienceService.setApplicationActive(isActive)
        }
    }

    /// Reloads repository-backed state after a committed Family Sync apply.
    /// An in-flight quest keeps its session, timer, and current response. The
    /// only forced navigation is a remote deletion of the active Profile.
    func refreshAfterExternalSyncAndWait() async {
        do {
            try await withAllProfilesCommittedRead(profileMutationGate) {
                await self.refreshAfterExternalSyncHoldingCommittedLease()
            }
        } catch {
            // Keep the last fully committed child presentation visible while
            // exact accepted bytes are waiting for deterministic replay.
        }
    }

    private func refreshAfterExternalSyncHoldingCommittedLease() async {
        guard let profileRepository else { return }
        externalSyncRefreshGeneration &+= 1
        let refreshGeneration = externalSyncRefreshGeneration
        do {
            let refreshedProfiles = try await profileRepository.profiles()
                .sorted(by: Self.isProfileOrderedBefore)
            try Task.checkCancellation()
            guard refreshGeneration == externalSyncRefreshGeneration else {
                return
            }
            profiles = refreshedProfiles

            guard let selectedProfileID = selectedProfile?.id else {
                if let lastPlayedProfileID,
                    !refreshedProfiles.contains(where: {
                        $0.id == lastPlayedProfileID
                    })
                {
                    self.lastPlayedProfileID = nil
                    guard refreshGeneration == externalSyncRefreshGeneration else {
                        return
                    }
                    try? await childSessionRepository?
                        .clearLastSelectedProfileID()
                }
                return
            }
            guard
                let refreshedProfile = refreshedProfiles.first(where: {
                    $0.id == selectedProfileID
                })
            else {
                abandonActiveQuest()
                focusedReplaySeed = nil
                routeStatusTask?.cancel()
                calendarTask?.cancel()
                worldProgressTask?.cancel()
                selectedProfile = nil
                lastPlayedProfileID = nil
                todayRouteStatuses = [:]
                calendarMonthSummary = nil
                worldProgression = nil
                rewardCollections = [:]
                destination = .profileChooser
                try? await childSessionRepository?
                    .clearLastSelectedProfileID()
                guard refreshGeneration == externalSyncRefreshGeneration else {
                    return
                }
                await audioExperienceService.stopAmbientAudio()
                return
            }

            guard refreshGeneration == externalSyncRefreshGeneration else {
                return
            }
            selectedProfile = refreshedProfile
            await activateAudio(for: refreshedProfile)
            guard refreshGeneration == externalSyncRefreshGeneration else {
                return
            }
            await refreshTodayRouteStatuses(for: refreshedProfile)
            guard refreshGeneration == externalSyncRefreshGeneration else {
                return
            }
            await loadCalendar(for: refreshedProfile)
            guard refreshGeneration == externalSyncRefreshGeneration else {
                return
            }
            await loadWorldProgress(for: refreshedProfile)
        } catch is CancellationError {
            return
        } catch {
            // Existing local state remains usable. The next foreground or
            // committed receipt retries from the repository source of truth.
        }
    }

    /// Async test/integration seam that exercises the same preparation path as
    /// the UI without polling published state.
    func prepareQuestAndWait(
        _ mode: LearningMode,
        writeInputMethod: WriteQuestInputMethod = .handwriting
    ) async {
        guard
            let request = beginPreparation(
                for: mode,
                writeInputMethod: writeInputMethod
            )
        else { return }
        await loadPreparedQuest(request)
    }

    func speak(_ prompt: WordPrompt) {
        Task { [weak self] in
            await self?.speakAndWait(prompt)
        }
    }

    func speakAndWait(_ prompt: WordPrompt) async {
        guard let profileID = selectedProfile?.id else { return }
        do {
            try await audioPromptService.play(prompt, for: profileID)
        } catch is CancellationError {
            return
        } catch {
            destination = .blocked(
                mode: prompt.learningMode,
                reason: .audioUnavailable
            )
        }
    }

    func finishItem(
        _ session: QuestSession,
        summary: QuestAttemptSummary
    ) {
        guard let pendingID = beginItemCompletion(session, summary: summary) else {
            return
        }
        persistenceTask = Task { [weak self] in
            await self?.persistPendingCompletion(pendingID)
        }
    }

    /// Async test/integration seam for durable item completion.
    func finishItemAndWait(
        _ session: QuestSession,
        summary: QuestAttemptSummary
    ) async {
        guard let pendingID = beginItemCompletion(session, summary: summary) else {
            return
        }
        await persistPendingCompletion(pendingID)
    }

    func recoverQuest(_ mode: LearningMode) {
        guard let pendingCompletion, pendingCompletion.mode == mode else {
            if focusedReplaySeed?.mode == mode {
                replayMissedWords()
                return
            }
            startQuest(mode)
            return
        }
        activeQuest?.timer.suspend(for: .saving)
        destination = .loading(
            mode: mode,
            phase: .saving(
                currentItem: pendingCompletion.itemIndex + 1,
                totalItems: pendingCompletion.totalItems
            )
        )
        persistenceTask?.cancel()
        persistenceTask = Task { [weak self] in
            await self?.persistPendingCompletion(pendingCompletion.id)
        }
    }

    func recoverQuestAndWait(_ mode: LearningMode) async {
        guard let pendingCompletion, pendingCompletion.mode == mode else {
            if focusedReplaySeed?.mode == mode {
                await replayMissedWordsAndWait()
                return
            }
            await prepareQuestAndWait(mode)
            return
        }
        activeQuest?.timer.suspend(for: .saving)
        destination = .loading(
            mode: mode,
            phase: .saving(
                currentItem: pendingCompletion.itemIndex + 1,
                totalItems: pendingCompletion.totalItems
            )
        )
        await persistPendingCompletion(pendingCompletion.id)
    }

    private func beginPreparation(
        for mode: LearningMode,
        writeInputMethod: WriteQuestInputMethod = .handwriting,
        writeInputMethodSource: WriteInputMethodSource = .recoveryFallback,
        intent: QuestPreparationIntent = .standard
    ) -> QuestPreparationRequest? {
        guard activePreparationID == nil, activeQuest == nil,
            pendingCompletion == nil
        else {
            return nil
        }
        guard let profile = selectedProfile else {
            destination = .profileChooser
            return nil
        }

        routeStatusTask?.cancel()
        routeStatusTask = nil

        switch contentProvider.availability(for: mode, profile: profile) {
        case .available:
            break
        case .blocked(let reason):
            destination = .blocked(mode: mode, reason: reason)
            return nil
        }

        abandonActiveQuest()
        focusedReplaySeed = nil
        if intent == .freestyleRecharge {
            guard todayRouteStatus(for: mode).action == .practiceAgain,
                !rechargingModes.contains(mode)
            else { return nil }
            rechargingModes.insert(mode)
        }
        let request = QuestPreparationRequest(
            id: UUID(),
            mode: mode,
            writeInputMethod: mode == .write ? writeInputMethod : .handwriting,
            writeInputMethodSource: writeInputMethodSource,
            intent: intent,
            profile: profile
        )
        activePreparationID = request.id
        destination = .loading(mode: mode, phase: .preparing)
        return request
    }

    private func beginFocusedReplayPreparation() -> FocusedReplayRequest? {
        guard let profile = selectedProfile,
            let seed = focusedReplaySeed,
            seed.profileID == profile.id,
            !seed.prompts.isEmpty
        else {
            return nil
        }

        routeStatusTask?.cancel()
        routeStatusTask = nil
        abandonActiveQuest()
        let request = FocusedReplayRequest(
            id: UUID(),
            profile: profile,
            seed: seed
        )
        activePreparationID = request.id
        destination = .loading(mode: seed.mode, phase: .preparing)
        return request
    }

    private func loadFocusedReplay(_ request: FocusedReplayRequest) async {
        do {
            let state = try await dailyQuestCoordinator.state(
                profileID: request.profile.id,
                learningMode: request.seed.mode,
                on: clock.now
            )
            guard
                let launch = dailyQuestCoordinator.practiceAgainLaunch(
                    from: state,
                    replaying: request.seed.prompts.map(\.id),
                    startedAt: clock.now
                )
            else {
                throw QuestContentError.inconsistentContent
            }
            try Task.checkCancellation()
            guard activePreparationID == request.id else { return }
            guard selectedProfile?.id == request.profile.id else { return }
            guard
                launch.questPlan.orderedItems.map(\.wordPromptID)
                    == request.seed.prompts.map(\.id)
            else {
                throw QuestContentError.inconsistentContent
            }

            let timer = questTimerFactory(request.seed.emergencyAfter)
            activeQuest = ActiveQuest(
                launch: launch,
                plan: launch.questPlan,
                profileID: request.profile.id,
                world: request.seed.world,
                mode: request.seed.mode,
                writeInputMethod: request.seed.writeInputMethod,
                prompts: request.seed.prompts,
                deviceClass: request.seed.deviceClass,
                personalPaceBands: request.seed.personalPaceBands,
                interfacePreferences: request.seed.interfacePreferences,
                incorrectAttemptLimit: request.seed.incorrectAttemptLimit,
                emergencyAfter: request.seed.emergencyAfter,
                timer: timer
            )
            focusedReplaySeed = nil
            activePreparationID = nil
            preparationTask = nil
            timer.start()
            if !isApplicationActive {
                timer.suspend(for: .appInactive)
            }
            showCurrentItem()
        } catch is CancellationError {
            return
        } catch {
            guard activePreparationID == request.id else { return }
            activePreparationID = nil
            preparationTask = nil
            destination = .blocked(
                mode: request.seed.mode,
                reason: .storageUnavailable
            )
        }
    }

    private func loadPreparedQuest(_ request: QuestPreparationRequest) async {
        do {
            let existingState = try await dailyQuestCoordinator.state(
                profileID: request.profile.id,
                learningMode: request.mode,
                on: clock.now
            )
            let excludedWordIDs = Set(
                existingState.plan?.questPlan.orderedItems.map(\.wordPromptID) ?? []
            )
            let candidate =
                switch request.intent {
                case .standard:
                    try await contentProvider.prepareQuest(
                        for: request.mode,
                        profile: request.profile
                    )
                case .freestyleRecharge:
                    try await contentProvider.prepareFreestyleQuest(
                        for: request.mode,
                        profile: request.profile,
                        excluding: excludedWordIDs
                    )
                }
            try Task.checkCancellation()
            guard activePreparationID == request.id else { return }
            guard selectedProfile?.id == request.profile.id else { return }
            guard candidate.plan.profileID == request.profile.id else {
                showPreparationFailure(.storageUnavailable, request: request)
                return
            }
            guard candidate.plan.configuration.learningMode == request.mode else {
                showPreparationFailure(.storageUnavailable, request: request)
                return
            }
            let dailyState =
                switch request.intent {
                case .standard:
                    try await dailyQuestCoordinator.loadOrCreateToday(
                        candidate: candidate.plan,
                        on: clock.now
                    )
                case .freestyleRecharge:
                    existingState
                }
            try Task.checkCancellation()
            guard activePreparationID == request.id else { return }
            guard selectedProfile?.id == request.profile.id else { return }
            let launch =
                switch request.intent {
                case .standard:
                    dailyQuestCoordinator.todayLaunch(from: dailyState)
                        ?? dailyQuestCoordinator.practiceAgainLaunch(
                            from: dailyState,
                            avoiding: lastPracticeWordOrderByMode[request.mode],
                            startedAt: clock.now
                        )
                case .freestyleRecharge:
                    dailyQuestCoordinator.practiceAgainLaunch(
                        from: dailyState,
                        freshCandidate: candidate.plan,
                        avoiding: lastPracticeWordOrderByMode[request.mode],
                        startedAt: clock.now
                    )
                }
            guard let launch else {
                showPreparationFailure(.storageUnavailable, request: request)
                return
            }
            guard launch.questPlan.profileID == request.profile.id else {
                showPreparationFailure(.storageUnavailable, request: request)
                return
            }
            guard launch.questPlan.configuration.learningMode == request.mode else {
                showPreparationFailure(.storageUnavailable, request: request)
                return
            }
            var prompts: [WordPrompt]
            if launch.questPlan == candidate.plan {
                prompts = candidate.orderedPrompts
            } else {
                prompts = try await contentProvider.prompts(
                    for: launch.questPlan,
                    profile: request.profile
                )
            }
            try Task.checkCancellation()
            guard activePreparationID == request.id else { return }
            guard selectedProfile?.id == request.profile.id else { return }
            guard !prompts.isEmpty else {
                showPreparationFailure(.emptyPool, request: request)
                return
            }
            guard prompts.allSatisfy({ $0.learningMode == request.mode }) else {
                showPreparationFailure(.storageUnavailable, request: request)
                return
            }
            guard Set(prompts.map(\.id)).count == prompts.count else {
                showPreparationFailure(.storageUnavailable, request: request)
                return
            }
            guard
                launch.questPlan.orderedItems.map(\.wordPromptID)
                    == prompts.map(\.id)
            else {
                showPreparationFailure(.storageUnavailable, request: request)
                return
            }
            if launch.runKind == .practiceAgain {
                lastPracticeWordOrderByMode[request.mode] =
                    launch.questPlan.orderedItems.map(\.wordPromptID)
            }

            let storedAttempts = try await attemptEventRepository.attempts(
                for: request.profile.id,
                wordPromptID: nil
            )
            let runAttempts = storedAttempts.filter {
                $0.questID == launch.questPlan.id
            }
            let recoveredWriteInputMethod = Self.recoveredWriteInputMethod(
                requested: request.writeInputMethod,
                source: request.writeInputMethodSource,
                mode: request.mode,
                attempts: runAttempts
            )
            let effectivePlan = ProblemNewReviewReplacement().adjustedPlan(
                launch.questPlan,
                attempts: runAttempts,
                personalPaceBands: candidate.personalPaceBands
            )
            if effectivePlan != launch.questPlan {
                let retainedWordIDs = Set(
                    effectivePlan.orderedItems.map(\.wordPromptID)
                )
                prompts = prompts.filter { retainedWordIDs.contains($0.id) }
            }
            let recovery = try PersistedQuestRecoveryResolver().resolve(
                plan: effectivePlan,
                attempts: storedAttempts,
                incorrectAttemptLimit: candidate.incorrectAttemptLimit
            )
            for completedPrompt in prompts.prefix(recovery.nextItemIndex) {
                try await rebuildAndSaveProgress(
                    profileID: request.profile.id,
                    prompt: completedPrompt,
                    mode: request.mode,
                    expectedEvents: recovery.eventsByWordID[completedPrompt.id] ?? []
                )
            }
            try Task.checkCancellation()
            guard activePreparationID == request.id else { return }
            guard selectedProfile?.id == request.profile.id else { return }

            let timer = questTimerFactory(candidate.emergencyAfter)
            let recoveredQuest = ActiveQuest(
                launch: launch,
                plan: effectivePlan,
                profileID: request.profile.id,
                world: request.profile.selectedWorld,
                mode: request.mode,
                writeInputMethod: recoveredWriteInputMethod,
                prompts: prompts,
                deviceClass: candidate.deviceClass,
                personalPaceBands: candidate.personalPaceBands,
                interfacePreferences: candidate.interfacePreferences,
                incorrectAttemptLimit: candidate.incorrectAttemptLimit,
                emergencyAfter: candidate.emergencyAfter,
                timer: timer,
                currentIndex: recovery.nextItemIndex,
                attempts: recovery.attempts,
                completedWordIDs: recovery.completedWordIDs
            )
            activeQuest = recoveredQuest
            todayRouteStatuses[request.mode] = TodayQuestRouteStatus(
                state: dailyState
            )
            activePreparationID = nil
            preparationTask = nil
            if recovery.nextItemIndex == prompts.count {
                let pending = recoveredQuestCompletion(
                    quest: recoveredQuest,
                    recovery: recovery
                )
                pendingCompletion = pending
                timer.suspend(for: .saving)
                destination = .loading(
                    mode: request.mode,
                    phase: .saving(
                        currentItem: prompts.count,
                        totalItems: prompts.count
                    )
                )
                await persistPendingCompletion(pending.id)
                return
            }
            timer.start()
            if !isApplicationActive {
                timer.suspend(for: .appInactive)
            }
            showCurrentItem()
        } catch is CancellationError {
            return
        } catch QuestContentError.emptyPool {
            showPreparationFailure(.emptyPool, request: request)
        } catch QuestContentError.noReviewDue {
            showPreparationFailure(.noReviewDue, request: request)
        } catch {
            showPreparationFailure(.storageUnavailable, request: request)
        }
    }

    private func showPreparationFailure(
        _ reason: QuestBlockReason,
        request: QuestPreparationRequest
    ) {
        guard activePreparationID == request.id else { return }
        activePreparationID = nil
        preparationTask = nil
        activeQuest = nil
        rechargingModes.remove(request.mode)
        destination = .blocked(mode: request.mode, reason: reason)
    }

    private func beginItemCompletion(
        _ session: QuestSession,
        summary: QuestAttemptSummary
    ) -> UUID? {
        guard pendingCompletion == nil else { return nil }
        guard let quest = activeQuest else { return nil }
        guard quest.id == session.id else { return nil }
        guard quest.profileID == session.profileID else { return nil }
        guard quest.mode == session.mode else { return nil }
        guard quest.currentIndex + 1 == session.currentItem else { return nil }
        guard quest.currentPrompt.id == session.prompt.id else { return nil }
        guard quest.timer === session.timer else { return nil }
        guard !summary.records.isEmpty else { return nil }
        quest.timer.suspend(for: .saving)

        let earliestDate =
            quest.attempts.last?.occurredAt.addingTimeInterval(0.001)
            ?? clock.now
        let baseDate = max(clock.now, earliestDate)
        let records = persistenceRecords(
            from: summary,
            existingAttempts: quest.attempts.filter {
                $0.wordPromptID == quest.currentPrompt.id
            }
        )
        let events = records.enumerated().map { index, record in
            AttemptEvent(
                questID: quest.id,
                profileID: quest.profileID,
                wordPromptID: quest.currentPrompt.id,
                learningMode: quest.mode,
                evidence: record.evidence,
                outcome: record.outcome,
                timing: record.timing,
                occurredAt: baseDate.addingTimeInterval(Double(index) / 1_000),
                replayCount: record.replayCount,
                recognitionConfidence: record.confidence,
                paceContext: quest.currentPrompt.paceContext(
                    deviceClass: quest.deviceClass,
                    writeInputMethod: quest.writeInputMethod
                )
            )
        }
        let pending = PendingItemCompletion(
            id: UUID(),
            questID: quest.id,
            profileID: quest.profileID,
            mode: quest.mode,
            prompt: quest.currentPrompt,
            itemIndex: quest.currentIndex,
            totalItems: quest.prompts.count,
            events: events,
            dailyCompletionID: DailyQuestCompletionID(),
            rewardGrantID: RewardGrantID(),
            completionRecordedAt: baseDate.addingTimeInterval(
                Double(summary.records.count) / 1_000
            )
        )
        pendingCompletion = pending
        destination = .loading(
            mode: quest.mode,
            phase: .saving(
                currentItem: quest.currentIndex + 1,
                totalItems: quest.prompts.count
            )
        )
        return pending.id
    }

    private func persistPendingCompletion(_ pendingID: UUID) async {
        guard let pending = pendingCompletion, pending.id == pendingID else {
            return
        }

        do {
            for event in pending.events {
                try Task.checkCancellation()
                try await attemptEventRepository.append(event)
            }
            try Task.checkCancellation()
            try await rebuildAndSaveProgress(for: pending)
            try Task.checkCancellation()
            try await commitPersistedCompletion(pendingID)
        } catch is CancellationError {
            return
        } catch {
            guard pendingCompletion?.id == pendingID else { return }
            activeQuest?.timer.suspend(for: .saving)
            persistenceTask = nil
            destination = .blocked(mode: pending.mode, reason: .storageUnavailable)
        }
    }

    private func rebuildAndSaveProgress(
        for pending: PendingItemCompletion
    ) async throws {
        try await rebuildAndSaveProgress(
            profileID: pending.profileID,
            prompt: pending.prompt,
            mode: pending.mode,
            expectedEvents: pending.events
        )
    }

    private func rebuildAndSaveProgress(
        profileID: ProfileID,
        prompt: WordPrompt,
        mode: LearningMode,
        expectedEvents: [AttemptEvent]
    ) async throws {
        let storedAttempts = try await attemptEventRepository.attempts(
            for: profileID,
            wordPromptID: prompt.id
        )
        let storedAttemptIDs = Set(storedAttempts.map(\.id))
        guard expectedEvents.allSatisfy({ storedAttemptIDs.contains($0.id) }) else {
            throw QuestStorageError.unavailable
        }

        var corrections: [AttemptCorrectionEvent] = []
        for attempt in storedAttempts {
            corrections.append(
                contentsOf: try await attemptEventRepository.corrections(for: attempt.id)
            )
        }
        let progress = try progressReducer.rebuild(
            profileID: profileID,
            wordPromptID: prompt.id,
            learningMode: mode,
            from: storedAttempts,
            corrections: corrections
        )
        try await wordProgressRepository.save(progress)
    }

    private func recoveredQuestCompletion(
        quest: ActiveQuest,
        recovery: PersistedQuestRecovery
    ) -> PendingItemCompletion {
        let finalItemIndex = quest.prompts.count - 1
        let finalPrompt = quest.prompts[finalItemIndex]
        let latestAttemptDate = recovery.attempts.last?.occurredAt ?? clock.now
        return PendingItemCompletion(
            id: UUID(),
            questID: quest.id,
            profileID: quest.profileID,
            mode: quest.mode,
            prompt: finalPrompt,
            itemIndex: finalItemIndex,
            totalItems: quest.prompts.count,
            events: recovery.eventsByWordID[finalPrompt.id] ?? [],
            dailyCompletionID: DailyQuestCompletionID(),
            rewardGrantID: RewardGrantID(),
            completionRecordedAt: max(clock.now, latestAttemptDate)
        )
    }

    private func persistenceRecords(
        from summary: QuestAttemptSummary,
        existingAttempts: [AttemptEvent]
    ) -> [QuestAttemptRecord] {
        var hasFirstIndependentAttempt = existingAttempts.contains {
            $0.evidence == .firstIndependentAttempt
        }
        var hasAnswerExposure = existingAttempts.contains {
            $0.evidence.hasAnswerExposure
        }

        return summary.records.map { record in
            var evidence = record.evidence
            if evidence == .firstIndependentAttempt {
                if hasAnswerExposure {
                    evidence = .guidedRetry
                } else if hasFirstIndependentAttempt {
                    evidence = .unaidedRetry
                }
            }

            if evidence == .firstIndependentAttempt {
                hasFirstIndependentAttempt = true
            }
            if evidence.hasAnswerExposure {
                hasAnswerExposure = true
            }
            return QuestAttemptRecord(
                evidence: evidence,
                outcome: record.outcome,
                confidence: record.confidence,
                timing: record.timing,
                replayCount: record.replayCount
            )
        }
    }

    private func commitPersistedCompletion(_ pendingID: UUID) async throws {
        guard let pending = pendingCompletion, pending.id == pendingID else {
            return
        }
        guard var quest = activeQuest, quest.id == pending.questID else {
            return
        }
        if quest.currentIndex == pending.itemIndex {
            quest.attempts.append(contentsOf: pending.events)
            quest.completedWordIDs.insert(pending.prompt.id)
            quest.applyProblemNewReplacement()
            quest.currentIndex += 1
            activeQuest = quest
        } else {
            guard quest.currentIndex == pending.itemIndex + 1 else { return }
            guard quest.completedWordIDs.contains(pending.prompt.id) else {
                return
            }
        }

        if quest.currentIndex < quest.prompts.count {
            pendingCompletion = nil
            persistenceTask = nil
            quest.timer.resume(from: .saving)
            showCurrentItem()
        } else {
            let resultState = try await finishPersistedQuest(
                quest,
                pending: pending
            )
            guard pendingCompletion?.id == pendingID else { return }
            guard activeQuest?.id == quest.id else { return }
            quest.timer.stop()
            activeQuest = nil
            pendingCompletion = nil
            persistenceTask = nil
            if resultState.persistedCompletion.runKind == .today {
                todayRouteStatuses[quest.mode] = TodayQuestRouteStatus(
                    completion: resultState.persistedCompletion
                )
            }
            rechargingModes.remove(quest.mode)
            destination = .result(resultState.viewState)
            refreshCalendar()
            refreshWorldProgress()
            Task { await onLearningDataChanged() }
        }
    }

    private func showCurrentItem() {
        guard let quest = activeQuest else { return }
        guard quest.currentIndex < quest.prompts.count else { return }
        let earnedWordIDs = Set(
            quest.attempts.compactMap { attempt in
                attempt.outcome.isCorrect ? attempt.wordPromptID : nil
            }
        )

        destination = .quest(
            QuestSession(
                id: quest.id,
                profileID: quest.profileID,
                mode: quest.mode,
                writeInputMethod: quest.writeInputMethod,
                prompt: quest.currentPrompt,
                source: quest.currentItem.source,
                currentItem: quest.currentIndex + 1,
                totalItems: quest.prompts.count,
                earnedItemCount: earnedWordIDs.count,
                timer: quest.timer,
                interfacePreferences: quest.interfacePreferences,
                incorrectAttemptLimit: quest.incorrectAttemptLimit
            )
        )
    }

    private func finishPersistedQuest(
        _ quest: ActiveQuest,
        pending: PendingItemCompletion
    ) async throws -> PersistedQuestResult {
        let score = QuestScorer().score(
            QuestScoringInput(
                plan: quest.plan,
                completedWordIDs: quest.completedWordIDs,
                attempts: quest.attempts,
                paceContextByWordID: Dictionary(
                    uniqueKeysWithValues: quest.prompts.map { prompt in
                        (
                            prompt.id,
                            prompt.paceContext(
                                deviceClass: quest.deviceClass,
                                writeInputMethod: quest.writeInputMethod
                            )
                        )
                    }
                ),
                personalPaceBands: quest.personalPaceBands
            )
        )
        let writeResult = try await dailyQuestCoordinator.complete(
            quest.launch,
            score: score,
            world: quest.world,
            completionID: pending.dailyCompletionID,
            rewardGrantID: pending.rewardGrantID,
            completedAt: pending.completionRecordedAt
        )
        let replayPrompts = focusedReplayPrompts(for: quest)
        focusedReplaySeed =
            replayPrompts.isEmpty
            ? nil
            : FocusedReplaySeed(
                profileID: quest.profileID,
                mode: quest.mode,
                world: quest.world,
                prompts: replayPrompts,
                deviceClass: quest.deviceClass,
                personalPaceBands: quest.personalPaceBands,
                interfacePreferences: quest.interfacePreferences,
                incorrectAttemptLimit: quest.incorrectAttemptLimit,
                emergencyAfter: quest.emergencyAfter,
                writeInputMethod: quest.writeInputMethod
            )
        return PersistedQuestResult(
            persistedCompletion: writeResult.completion,
            viewState: QuestResultViewState(
                mode: quest.mode,
                score: score,
                runKind: quest.launch.runKind,
                rewardGrant: writeResult.rewardGrant,
                replayWordCount: replayPrompts.count
            )
        )
    }

    /// A focused replay contains every word that did not have a correct first
    /// independent response in this run. Technical-only skips are included,
    /// while a technical retry followed by a correct independent response is
    /// not treated as a miss.
    private func focusedReplayPrompts(for quest: ActiveQuest) -> [WordPrompt] {
        let runAttempts = quest.attempts.filter { $0.questID == quest.id }
        let independentAttemptsByWordID = Dictionary(
            grouping: runAttempts.filter {
                $0.evidence.countsTowardAccuracy
                    && $0.outcome.isScorableResponse
            },
            by: \.wordPromptID
        )

        return quest.prompts.filter { prompt in
            guard
                let attempts = independentAttemptsByWordID[prompt.id],
                let firstAttempt = attempts.sorted(by: attemptEventSort).first
            else {
                return true
            }
            return !firstAttempt.outcome.isCorrect
        }
    }

    private func attemptEventSort(
        _ left: AttemptEvent,
        _ right: AttemptEvent
    ) -> Bool {
        if left.occurredAt != right.occurredAt {
            return left.occurredAt < right.occurredAt
        }
        return left.id.rawValue.uuidString < right.id.rawValue.uuidString
    }

    private func cancelQuestWork() {
        activePreparationID = nil
        preparationTask?.cancel()
        preparationTask = nil
        persistenceTask?.cancel()
        persistenceTask = nil
    }

    private func abandonActiveQuest() {
        if let activeQuest, activeQuest.launch.runKind == .practiceAgain {
            rechargingModes.remove(activeQuest.mode)
        }
        cancelQuestWork()
        activeQuest?.timer.stop()
        activeQuest = nil
        pendingCompletion = nil
    }

    private func refreshTodayRouteStatuses(for profile: KidProfile) async {
        var refreshed: [LearningMode: TodayQuestRouteStatus] = [:]
        do {
            for mode in LearningMode.allCases {
                try Task.checkCancellation()
                let state = try await dailyQuestCoordinator.state(
                    profileID: profile.id,
                    learningMode: mode,
                    on: clock.now
                )
                refreshed[mode] = TodayQuestRouteStatus(state: state)
            }
            try Task.checkCancellation()
            guard selectedProfile?.id == profile.id else { return }
            todayRouteStatuses = refreshed
            routeStatusTask = nil
        } catch is CancellationError {
            return
        } catch {
            guard selectedProfile?.id == profile.id else { return }
            routeStatusTask = nil
        }
    }

    private func loadCalendar(for profile: KidProfile) async {
        do {
            let summary = try await dailyQuestCoordinator.monthSummary(
                profileID: profile.id,
                containing: clock.now
            )
            try Task.checkCancellation()
            guard selectedProfile?.id == profile.id else { return }
            calendarMonthSummary = summary
            isCalendarLoading = false
            calendarLoadFailed = false
            calendarTask = nil
        } catch is CancellationError {
            return
        } catch {
            guard selectedProfile?.id == profile.id else { return }
            calendarMonthSummary = nil
            isCalendarLoading = false
            calendarLoadFailed = true
            calendarTask = nil
        }
    }

    private func loadWorldProgress(for profile: KidProfile) async {
        do {
            async let progression = dailyQuestCoordinator.worldProgression(
                for: profile,
                on: clock.now
            )
            async let collections = dailyQuestCoordinator.rewardCollections(
                for: profile
            )
            let (loadedProgression, loadedCollections) = try await (
                progression,
                collections
            )
            try Task.checkCancellation()
            guard selectedProfile?.id == profile.id else { return }
            worldProgression = loadedProgression
            rewardCollections = loadedCollections
            worldProgressTask = nil
        } catch is CancellationError {
            return
        } catch {
            guard selectedProfile?.id == profile.id else { return }
            worldProgression = WorldProgression(
                profile: profile,
                completions: [],
                currentLocalDay: currentLocalDay
            )
            rewardCollections = [:]
            worldProgressTask = nil
        }
    }

    private func persistLastSelectedProfile(_ profileID: ProfileID) async {
        guard selectedProfile?.id == profileID else { return }
        do {
            try await childSessionRepository?.saveLastSelectedProfileID(profileID)
        } catch {
            // Remembering a launch preference must never block play. The
            // durable profile remains available from the chooser.
        }
        guard selectedProfile?.id == profileID else { return }
        profileSelectionTask = nil
    }

    private func profileSelection(
        from profile: KidProfile,
        world: WorldTheme,
        cartoonIconAssetID: String?,
        treasureAvatar: TreasureAvatarSelection?
    ) -> KidProfile {
        KidProfile(
            id: profile.id,
            displayName: profile.displayName,
            avatar: profile.avatar,
            selectedWorld: world,
            starterWorld: profile.starterWorld,
            guardianUnlockedWorlds: profile.guardianUnlockedWorlds,
            selectedCartoonIconAssetID: cartoonIconAssetID,
            selectedTreasureAvatar: treasureAvatar,
            schoolGrade: profile.schoolGrade,
            ageYears: profile.ageYears,
            voiceprintStatus: profile.voiceprintStatus,
            createdAt: profile.createdAt,
            updatedAt: clock.now
        )
    }

    private func saveProfileSelection(
        _ updated: KidProfile,
        in repository: any KidProfileRepository,
        shouldRefreshAudio: Bool = false
    ) async throws {
        try await repository.save(updated)
        Task { await onLearningDataChanged() }
        guard selectedProfile?.id == updated.id else { return }
        selectedProfile = updated
        if let index = profiles.firstIndex(where: { $0.id == updated.id }) {
            profiles[index] = updated
        }
        if shouldRefreshAudio {
            await activateAudio(for: updated)
        }
        await loadWorldProgress(for: updated)
    }

    private static func isProfileOrderedBefore(
        _ lhs: KidProfile,
        _ rhs: KidProfile
    ) -> Bool {
        if lhs.createdAt != rhs.createdAt {
            return lhs.createdAt < rhs.createdAt
        }
        return lhs.id.rawValue.uuidString < rhs.id.rawValue.uuidString
    }

    /// A resumed Write quest keeps one response surface for its full run.
    /// Persisted attempts are authoritative only when every record carries a
    /// valid, matching pace context and they all agree. Before the first
    /// durable attempt (or for legacy/mixed evidence), the current chooser or
    /// generic handwriting fallback remains in control.
    private static func recoveredWriteInputMethod(
        requested: WriteQuestInputMethod,
        source: WriteInputMethodSource,
        mode: LearningMode,
        attempts: [AttemptEvent]
    ) -> WriteQuestInputMethod {
        guard source == .recoveryFallback else { return requested }
        guard mode == .write, !attempts.isEmpty else { return requested }

        let inferredMethods = attempts.map { attempt -> WriteQuestInputMethod? in
            guard
                attempt.learningMode == .write,
                let context = attempt.paceContext,
                context.learningMode == .write
            else { return nil }

            return switch context.inputMethod {
            case .letterKeyboard:
                .letterKeyboard
            case .fingerWriting, .pencilWriting:
                .handwriting
            case .speech:
                nil
            }
        }
        guard inferredMethods.allSatisfy({ $0 != nil }) else { return requested }

        let uniqueMethods = Set(inferredMethods.compactMap { $0 })
        guard uniqueMethods.count == 1, let recovered = uniqueMethods.first else {
            return requested
        }
        return recovered
    }

    private static let creationFailureMessage =
        "We couldn't save your kid profile. Ask a parent to try again."

    private static func message(
        for error: ChildProfileCreationError
    ) -> String {
        switch error {
        case .emptyDisplayName:
            "Type your nickname first."
        case .displayNameTooLong(let maximumCharacterCount):
            "Keep your nickname to \(maximumCharacterCount) letters or fewer."
        case .invalidAge:
            "Choose your age, then try again."
        case .settingsPersistenceFailed, .profilePersistenceFailed,
            .rollbackFailed:
            creationFailureMessage
        }
    }

    private func activateAudio(for profile: KidProfile) async {
        let settings = try? await practiceSettingsRepository?.settings(
            for: profile.id
        )
        guard selectedProfile?.id == profile.id else { return }
        await audioExperienceService.activate(
            world: profile.selectedWorld,
            preferences: settings?.audio ?? .default
        )
    }
}

private struct QuestPreparationRequest: Sendable {
    let id: UUID
    let mode: LearningMode
    let writeInputMethod: WriteQuestInputMethod
    let writeInputMethodSource: WriteInputMethodSource
    let intent: QuestPreparationIntent
    let profile: KidProfile
}

enum QuestPreparationIntent: Sendable {
    case standard
    case freestyleRecharge
}

enum WriteInputMethodSource: Sendable {
    case explicitChooserSelection
    case recoveryFallback
}

private struct FocusedReplayRequest: Sendable {
    let id: UUID
    let profile: KidProfile
    let seed: FocusedReplaySeed
}

private struct FocusedReplaySeed: Sendable {
    let profileID: ProfileID
    let mode: LearningMode
    let world: WorldTheme
    let prompts: [WordPrompt]
    let deviceClass: DeviceClass
    let personalPaceBands: [PersonalPaceBand]
    let interfacePreferences: PracticeInterfacePreferences
    let incorrectAttemptLimit: Int
    let emergencyAfter: TimeInterval
    let writeInputMethod: WriteQuestInputMethod
}

private struct ActiveQuest {
    let launch: DailyQuestLaunch
    var plan: QuestPlan
    let profileID: ProfileID
    let world: WorldTheme
    let mode: LearningMode
    let writeInputMethod: WriteQuestInputMethod
    var prompts: [WordPrompt]
    let deviceClass: DeviceClass
    let personalPaceBands: [PersonalPaceBand]
    let interfacePreferences: PracticeInterfacePreferences
    let incorrectAttemptLimit: Int
    let emergencyAfter: TimeInterval
    let timer: QuestTimerModel
    var currentIndex = 0
    var attempts: [AttemptEvent] = []
    var completedWordIDs: Set<WordPromptID> = []

    var currentPrompt: WordPrompt {
        prompts[currentIndex]
    }

    var currentItem: QuestPlanItem {
        plan.orderedItems[currentIndex]
    }

    var id: QuestID {
        plan.id
    }

    mutating func applyProblemNewReplacement() {
        let adjustedPlan = ProblemNewReviewReplacement().adjustedPlan(
            launch.questPlan,
            attempts: attempts,
            personalPaceBands: personalPaceBands
        )
        guard adjustedPlan != plan else { return }
        let retainedWordIDs = Set(adjustedPlan.orderedItems.map(\.wordPromptID))
        prompts = prompts.filter { retainedWordIDs.contains($0.id) }
        plan = adjustedPlan
    }
}

private struct PendingItemCompletion {
    let id: UUID
    let questID: QuestID
    let profileID: ProfileID
    let mode: LearningMode
    let prompt: WordPrompt
    let itemIndex: Int
    let totalItems: Int
    let events: [AttemptEvent]
    let dailyCompletionID: DailyQuestCompletionID
    let rewardGrantID: RewardGrantID
    let completionRecordedAt: Date
}

private struct PersistedQuestResult {
    let persistedCompletion: DailyQuestCompletion
    let viewState: QuestResultViewState
}
