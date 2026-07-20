import Foundation
import SwiftUI
import TadaWordsContent
import TadaWordsDesignSystem
import TadaWordsDomain

#if os(iOS)
    import UIKit
#endif

@MainActor
public struct TadaWordsRootView: View {
    @StateObject private var model: TadaWordsAppModel
    @Environment(\.scenePhase) private var scenePhase
    private let speechRecognitionService: any SpeechRecognitionService
    private let handwritingRecognitionService: any HandwritingRecognitionService
    private let audioExperienceService: any AudioExperienceService
    private var pictureHintProvider: any WordPictureHintProviding =
        NoWordPictureHintProvider()
    private let speechPermissionActions: SpeechPermissionActions
    private let onOpenGuardian: () -> Void
    private let demoLaunchRoute: DemoLaunchRoute?
    private let usesSimulatedVoiceCheck: Bool
    private var externalDataRevision: UUID?

    @State private var didApplyDemoLaunchRoute = false
    @State private var isCalendarPresented = false
    @State private var isWorldPickerPresented = false
    @State private var isCollectionPresented = false
    @State private var externalSyncRefreshTask: Task<Void, Never>?

    public init(onOpenGuardian: @escaping () -> Void = {}) {
        self.speechRecognitionService = UnavailableSpeechRecognitionService()
        self.handwritingRecognitionService = UnavailableHandwritingRecognitionService()
        self.audioExperienceService = SilentAudioExperienceService()
        self.speechPermissionActions = .unavailable
        self.onOpenGuardian = onOpenGuardian
        demoLaunchRoute = nil
        usesSimulatedVoiceCheck = false
        let profileRepository = InMemoryKidProfileRepository()
        let settingsRepository = InMemoryPracticeSettingsRepository()
        let clock = SystemAppClock()
        _model = StateObject(
            wrappedValue: TadaWordsAppModel(
                practiceSettingsRepository: settingsRepository,
                clock: clock,
                childSessionRepository: InMemoryChildSessionRepository(),
                childProfileCreator: RepositoryChildProfileCreator(
                    profileRepository: profileRepository,
                    practiceSettingsRepository: settingsRepository,
                    clock: clock
                ),
                profileRepository: profileRepository
            )
        )
    }

    public init(
        audioPromptService: any AudioPromptService,
        audioExperienceService: any AudioExperienceService =
            SilentAudioExperienceService(),
        onOpenGuardian: @escaping () -> Void = {}
    ) {
        self.speechRecognitionService = UnavailableSpeechRecognitionService()
        self.handwritingRecognitionService = UnavailableHandwritingRecognitionService()
        self.audioExperienceService = audioExperienceService
        self.speechPermissionActions = .unavailable
        self.onOpenGuardian = onOpenGuardian
        demoLaunchRoute = nil
        usesSimulatedVoiceCheck = false
        let profileRepository = InMemoryKidProfileRepository()
        let settingsRepository = InMemoryPracticeSettingsRepository()
        let clock = SystemAppClock()
        _model = StateObject(
            wrappedValue: TadaWordsAppModel(
                audioPromptService: audioPromptService,
                audioExperienceService: audioExperienceService,
                practiceSettingsRepository: settingsRepository,
                clock: clock,
                childSessionRepository: InMemoryChildSessionRepository(),
                childProfileCreator: RepositoryChildProfileCreator(
                    profileRepository: profileRepository,
                    practiceSettingsRepository: settingsRepository,
                    clock: clock
                ),
                profileRepository: profileRepository
            )
        )
    }

    public init(
        audioPromptService: any AudioPromptService,
        audioExperienceService: any AudioExperienceService =
            SilentAudioExperienceService(),
        speechRecognitionService: any SpeechRecognitionService,
        handwritingRecognitionService: any HandwritingRecognitionService,
        pictureHintProvider: any WordPictureHintProviding =
            NoWordPictureHintProvider(),
        speechPermissionActions: SpeechPermissionActions,
        externalDataRevision: UUID? = nil,
        onLearningDataChanged: @escaping @Sendable () async -> Void = {},
        onOpenGuardian: @escaping () -> Void = {}
    ) {
        self.speechRecognitionService = speechRecognitionService
        self.handwritingRecognitionService = handwritingRecognitionService
        self.audioExperienceService = audioExperienceService
        self.pictureHintProvider = pictureHintProvider
        self.speechPermissionActions = speechPermissionActions
        self.externalDataRevision = externalDataRevision
        self.onOpenGuardian = onOpenGuardian
        demoLaunchRoute = nil
        usesSimulatedVoiceCheck = false
        let profileRepository = InMemoryKidProfileRepository()
        let settingsRepository = InMemoryPracticeSettingsRepository()
        let clock = SystemAppClock()
        _model = StateObject(
            wrappedValue: TadaWordsAppModel(
                audioPromptService: audioPromptService,
                audioExperienceService: audioExperienceService,
                practiceSettingsRepository: settingsRepository,
                clock: clock,
                childSessionRepository: InMemoryChildSessionRepository(),
                childProfileCreator: RepositoryChildProfileCreator(
                    profileRepository: profileRepository,
                    practiceSettingsRepository: settingsRepository,
                    clock: clock
                ),
                profileRepository: profileRepository,
                onLearningDataChanged: onLearningDataChanged
            )
        )
    }

    public init(
        profiles: [KidProfile],
        profileRepository: any KidProfileRepository,
        wordPoolRepository: any WordPoolRepository,
        attemptEventRepository: any AttemptEventRepository,
        wordProgressRepository: any WordProgressRepository,
        practiceSettingsRepository: any PracticeSettingsRepository,
        dailyQuestRepository: any DailyQuestRepository,
        childSessionRepository: any ChildSessionRepository,
        initialProfileID: ProfileID? = nil,
        clock: any AppClock = SystemAppClock(),
        timeZone: TimeZone = .current,
        deviceClass: DeviceClass? = nil,
        audioPromptService: any AudioPromptService,
        audioExperienceService: any AudioExperienceService =
            SilentAudioExperienceService(),
        speechRecognitionService: any SpeechRecognitionService,
        handwritingRecognitionService: any HandwritingRecognitionService,
        pictureHintProvider: any WordPictureHintProviding =
            NoWordPictureHintProvider(),
        speechPermissionActions: SpeechPermissionActions,
        externalDataRevision: UUID? = nil,
        onLearningDataChanged: @escaping @Sendable () async -> Void = {},
        onOpenGuardian: @escaping () -> Void = {}
    ) {
        self.speechRecognitionService = speechRecognitionService
        self.handwritingRecognitionService = handwritingRecognitionService
        self.audioExperienceService = audioExperienceService
        self.pictureHintProvider = pictureHintProvider
        self.speechPermissionActions = speechPermissionActions
        self.externalDataRevision = externalDataRevision
        self.onOpenGuardian = onOpenGuardian
        demoLaunchRoute = nil
        usesSimulatedVoiceCheck = false
        let resolvedDeviceClass = deviceClass ?? CurrentDeviceClass.value
        let contentProvider = RepositoryBackedQuestContentProvider(
            wordPoolRepository: wordPoolRepository,
            wordProgressRepository: wordProgressRepository,
            practiceSettingsRepository: practiceSettingsRepository,
            attemptEventRepository: attemptEventRepository,
            gradeWordRecommender: RepositoryGradeWordRecommender(
                repository: wordPoolRepository,
                clock: clock
            ),
            deviceClass: resolvedDeviceClass,
            clock: clock,
            timeZone: timeZone
        )
        _model = StateObject(
            wrappedValue: TadaWordsAppModel(
                profiles: profiles,
                contentProvider: contentProvider,
                audioPromptService: audioPromptService,
                audioExperienceService: audioExperienceService,
                practiceSettingsRepository: practiceSettingsRepository,
                attemptEventRepository: attemptEventRepository,
                wordProgressRepository: wordProgressRepository,
                dailyQuestCoordinator: DailyQuestCoordinator(
                    repository: dailyQuestRepository,
                    timeZone: timeZone
                ),
                clock: clock,
                timeZone: timeZone,
                initialProfileID: initialProfileID,
                childSessionRepository: childSessionRepository,
                childProfileCreator: RepositoryChildProfileCreator(
                    profileRepository: profileRepository,
                    practiceSettingsRepository: practiceSettingsRepository,
                    clock: clock
                ),
                profileRepository: profileRepository,
                onLearningDataChanged: onLearningDataChanged
            )
        )
    }

    public static func demo(
        deviceClass: DeviceClass? = nil,
        onOpenGuardian: @escaping () -> Void = {}
    ) -> TadaWordsRootView {
        makeDemo(
            audioPromptService: SilentAudioPromptService(),
            deviceClass: deviceClass ?? CurrentDeviceClass.value,
            onOpenGuardian: onOpenGuardian
        )
    }

    public static func demo(
        audioPromptService: any AudioPromptService,
        audioExperienceService: any AudioExperienceService =
            SilentAudioExperienceService(),
        deviceClass: DeviceClass? = nil,
        onOpenGuardian: @escaping () -> Void = {}
    ) -> TadaWordsRootView {
        makeDemo(
            audioPromptService: audioPromptService,
            audioExperienceService: audioExperienceService,
            deviceClass: deviceClass ?? CurrentDeviceClass.value,
            onOpenGuardian: onOpenGuardian
        )
    }

    private static func makeDemo(
        audioPromptService: any AudioPromptService,
        audioExperienceService: any AudioExperienceService =
            SilentAudioExperienceService(),
        deviceClass: DeviceClass,
        onOpenGuardian: @escaping () -> Void
    ) -> TadaWordsRootView {
        let clock = DemoAppClock()
        let wordPoolRepository = InMemoryWordPoolRepository()
        let learningRepository = InMemoryLearningRecordRepository()
        let practiceSettingsRepository = InMemoryPracticeSettingsRepository()
        let dailyQuestRepository = InMemoryDailyQuestRepository()
        let profileRepository = InMemoryKidProfileRepository()
        let childSessionRepository = InMemoryChildSessionRepository()
        let contentProvider = DemoQuestContentProvider(
            wordPoolRepository: wordPoolRepository,
            wordProgressRepository: learningRepository,
            practiceSettingsRepository: practiceSettingsRepository,
            attemptEventRepository: learningRepository,
            deviceClass: deviceClass,
            clock: clock,
            timeZone: TimeZone(secondsFromGMT: 0) ?? .current
        )
        let speechRecognitionService: any SpeechRecognitionService =
            DemoSpeechRecognitionService()
        return TadaWordsRootView(
            contentProvider: contentProvider,
            audioPromptService: audioPromptService,
            audioExperienceService: audioExperienceService,
            practiceSettingsRepository: practiceSettingsRepository,
            attemptEventRepository: learningRepository,
            wordProgressRepository: learningRepository,
            dailyQuestCoordinator: DailyQuestCoordinator(
                repository: dailyQuestRepository,
                timeZone: TimeZone(secondsFromGMT: 0) ?? .current
            ),
            clock: clock,
            profileRepository: profileRepository,
            childSessionRepository: childSessionRepository,
            speechRecognitionService: speechRecognitionService,
            handwritingRecognitionService: DemoHandwritingRecognitionService(),
            speechPermissionActions: .demoAuthorized,
            demoLaunchRoute: DemoLaunchRoute.current,
            onOpenGuardian: onOpenGuardian
        )
    }

    private init(
        contentProvider: any QuestContentProviding,
        audioPromptService: any AudioPromptService,
        audioExperienceService: any AudioExperienceService,
        practiceSettingsRepository: (any PracticeSettingsRepository)?,
        attemptEventRepository: any AttemptEventRepository,
        wordProgressRepository: any WordProgressRepository,
        dailyQuestCoordinator: DailyQuestCoordinator,
        clock: any AppClock,
        profileRepository: any KidProfileRepository,
        childSessionRepository: any ChildSessionRepository,
        speechRecognitionService: any SpeechRecognitionService,
        handwritingRecognitionService: any HandwritingRecognitionService,
        speechPermissionActions: SpeechPermissionActions,
        demoLaunchRoute: DemoLaunchRoute?,
        onOpenGuardian: @escaping () -> Void
    ) {
        self.speechRecognitionService = speechRecognitionService
        self.handwritingRecognitionService = handwritingRecognitionService
        self.audioExperienceService = audioExperienceService
        self.speechPermissionActions = speechPermissionActions
        self.demoLaunchRoute = demoLaunchRoute
        usesSimulatedVoiceCheck = true
        self.onOpenGuardian = onOpenGuardian
        _model = StateObject(
            wrappedValue: TadaWordsAppModel(
                contentProvider: contentProvider,
                audioPromptService: audioPromptService,
                audioExperienceService: audioExperienceService,
                practiceSettingsRepository: practiceSettingsRepository,
                attemptEventRepository: attemptEventRepository,
                wordProgressRepository: wordProgressRepository,
                dailyQuestCoordinator: dailyQuestCoordinator,
                clock: clock,
                timeZone: TimeZone(secondsFromGMT: 0) ?? .current,
                childSessionRepository: childSessionRepository,
                childProfileCreator: RepositoryChildProfileCreator(
                    profileRepository: profileRepository,
                    practiceSettingsRepository: practiceSettingsRepository
                        ?? InMemoryPracticeSettingsRepository(),
                    clock: clock
                ),
                profileRepository: profileRepository
            )
        )
    }

    public var body: some View {
        ZStack {
            destinationView
                .id(model.transitionKey)
                .tadaNavigationMotion(
                    value: model.transitionKey,
                    standardTransition: .opacity.combined(with: .scale(scale: 0.985))
                )
        }
        .environment(\.font, .system(.body, design: .rounded))
        .preferredColorScheme(.light)
        .task {
            await applyDemoLaunchRouteIfNeeded()
        }
        .onChange(of: scenePhase, initial: true) { _, phase in
            model.setApplicationActive(phase == .active)
        }
        .onChange(of: externalDataRevision) { _, revision in
            guard revision != nil else { return }
            externalSyncRefreshTask?.cancel()
            externalSyncRefreshTask = Task {
                await model.refreshAfterExternalSyncAndWait()
            }
        }
        .onDisappear {
            externalSyncRefreshTask?.cancel()
            externalSyncRefreshTask = nil
        }
        .sheet(isPresented: $isCalendarPresented) {
            ChildQuestCalendarView(
                profile: model.selectedProfile,
                summary: model.calendarMonthSummary,
                today: model.currentLocalDay,
                isLoading: model.isCalendarLoading,
                loadFailed: model.calendarLoadFailed,
                theme: model.selectedTheme,
                onRetry: model.refreshCalendar,
                onClose: { isCalendarPresented = false }
            )
        }
        .sheet(isPresented: $isWorldPickerPresented) {
            if let profile = model.selectedProfile {
                ChildWorldPickerView(
                    profile: profile,
                    progression: model.worldProgression,
                    currentLocalDay: model.currentLocalDay,
                    onSelect: model.selectWorld,
                    onClose: { isWorldPickerPresented = false }
                )
            }
        }
        .sheet(isPresented: $isCollectionPresented) {
            if let profile = model.selectedProfile {
                ChildCollectionView(
                    profile: profile,
                    progression: model.worldProgression,
                    collections: model.rewardCollections,
                    onSelectWorld: model.selectWorld,
                    onSelectCartoonIcon: model.selectCartoonIcon,
                    onSelectTreasureAvatar: model.selectTreasureAvatar,
                    onSelectOriginalAvatar: model.selectOriginalAvatar,
                    onClose: { isCollectionPresented = false }
                )
            }
        }
        .alert(
            "Collection choice could not change",
            isPresented: Binding(
                get: { model.worldSelectionError != nil },
                set: { if !$0 { model.clearWorldSelectionError() } }
            )
        ) {
            Button("OK", role: .cancel) { model.clearWorldSelectionError() }
        } message: {
            Text(model.worldSelectionError ?? "Ask a parent to try again.")
        }
    }

    @ViewBuilder
    private var destinationView: some View {
        switch model.destination {
        case .profileChooser:
            ProfileChooserView(
                profiles: model.profiles,
                lastPlayedProfileID: model.lastPlayedProfileID,
                onSelect: model.selectProfile,
                onCreateProfile: model.createChildProfileAndWait,
                isCreatingProfile: model.isCreatingChildProfile,
                creationError: model.childProfileCreationError,
                onDismissCreationError: model.clearChildProfileCreationError,
                onOpenGuardian: onOpenGuardian
            )

        case .lobby:
            if let profile = model.selectedProfile {
                ChildLobbyView(
                    profile: profile,
                    theme: model.selectedTheme,
                    readAvailability: model.availability(for: .read),
                    writeAvailability: model.availability(for: .write),
                    readStatus: model.todayRouteStatus(for: .read),
                    writeStatus: model.todayRouteStatus(for: .write),
                    onChooseProfile: model.showProfiles,
                    onOpenCalendar: {
                        model.refreshCalendar()
                        isCalendarPresented = true
                    },
                    onOpenWorlds: {
                        model.refreshWorldProgress()
                        isWorldPickerPresented = true
                    },
                    onOpenCollection: {
                        model.refreshWorldProgress()
                        isCollectionPresented = true
                    },
                    onStart: model.chooseQuest
                )
            } else {
                ProfileChooserView(
                    profiles: model.profiles,
                    lastPlayedProfileID: model.lastPlayedProfileID,
                    onSelect: model.selectProfile,
                    onCreateProfile: model.createChildProfileAndWait,
                    isCreatingProfile: model.isCreatingChildProfile,
                    creationError: model.childProfileCreationError,
                    onDismissCreationError: model.clearChildProfileCreationError,
                    onOpenGuardian: onOpenGuardian
                )
            }

        case .writeInputChooser:
            WriteInputChooserView(
                theme: model.selectedTheme,
                onSelect: model.startWriteQuest,
                onBack: model.showLobby
            )

        case .loading(let mode, let phase):
            QuestLoadingView(
                mode: mode,
                phase: phase,
                theme: model.selectedTheme,
                onBack: model.showLobby
            )

        case .quest(let session):
            switch session.mode {
            case .read:
                ReadQuestView(
                    session: session,
                    questTimer: session.timer,
                    theme: model.selectedTheme,
                    recognitionService: speechRecognitionService,
                    audioExperienceService: audioExperienceService,
                    permissionActions: speechPermissionActions,
                    showsSimulatedVoiceCheck: usesSimulatedVoiceCheck,
                    onSpeak: { await model.speakAndWait(session.prompt) },
                    onBack: model.showLobby,
                    onComplete: { summary in
                        model.finishItem(session, summary: summary)
                    }
                )
            case .write:
                switch session.writeInputMethod {
                case .handwriting:
                    WriteQuestView(
                        session: session,
                        questTimer: session.timer,
                        theme: model.selectedTheme,
                        recognitionService: handwritingRecognitionService,
                        audioExperienceService: audioExperienceService,
                        pictureHintProvider: pictureHintProvider,
                        onHandwritingToolChanged: model.selectHandwritingTool,
                        onSpeak: { await model.speakAndWait(session.prompt) },
                        onBack: model.showLobby,
                        onComplete: { summary in
                            model.finishItem(session, summary: summary)
                        }
                    )
                case .letterKeyboard:
                    SpellQuestView(
                        session: session,
                        questTimer: session.timer,
                        theme: model.selectedTheme,
                        audioExperienceService: audioExperienceService,
                        onSpeak: { await model.speakAndWait(session.prompt) },
                        onBack: model.showLobby,
                        onComplete: { summary in
                            model.finishItem(session, summary: summary)
                        }
                    )
                }
            }

        case .blocked(let mode, let reason):
            QuestBlockedView(
                mode: mode,
                reason: reason,
                theme: model.selectedTheme,
                onRecover: {
                    if reason == .storageUnavailable {
                        model.recoverQuest(mode)
                    } else if reason == .recognitionUnavailable {
                        model.startQuest(mode)
                    } else {
                        model.showLobby()
                    }
                },
                onBack: model.showLobby
            )

        case .result(let result):
            QuestResultView(
                result: result,
                theme: model.selectedTheme,
                audioExperienceService: audioExperienceService,
                onReplay: model.replayMissedWords,
                onContinue: model.showLobby
            )
        }
    }

    private func applyDemoLaunchRouteIfNeeded() async {
        guard !didApplyDemoLaunchRoute, let demoLaunchRoute else { return }
        didApplyDemoLaunchRoute = true

        let targetWorld = demoLaunchRoute.world
        guard let profile = model.profiles.first(where: { $0.selectedWorld == targetWorld }) else {
            return
        }
        model.selectProfile(profile)

        guard let mode = demoLaunchRoute.mode else { return }
        await Task.yield()
        model.startQuest(mode)
    }
}

private enum CurrentDeviceClass {
    @MainActor
    static var value: DeviceClass {
        #if os(iOS)
            UIDevice.current.userInterfaceIdiom == .phone ? .phone : .tablet
        #else
            .tablet
        #endif
    }
}

private struct DemoLaunchRoute {
    let world: WorldTheme
    let mode: LearningMode?

    static var current: DemoLaunchRoute? {
        guard
            let argument = ProcessInfo.processInfo.arguments.first(where: {
                $0.hasPrefix("--demo-start=")
            })
        else {
            return nil
        }

        let value = argument.replacingOccurrences(of: "--demo-start=", with: "")
        let parts = value.split(separator: "-").map(String.init)
        guard let worldPart = parts.first else { return nil }

        let world: WorldTheme
        switch worldPart {
        case "moonpetal":
            world = .moonpetalKingdom
        case "buildit":
            world = .buildItBay
        case "paws":
            world = .pawsAndPines
        default:
            return nil
        }

        let mode: LearningMode?
        switch parts.dropFirst().first {
        case "read":
            mode = .read
        case "write":
            mode = .write
        default:
            mode = nil
        }
        return DemoLaunchRoute(world: world, mode: mode)
    }
}

extension TadaWordsAppModel {
    var transitionKey: String {
        switch destination {
        case .profileChooser:
            "profiles"
        case .lobby:
            "lobby-\(selectedProfile?.id.description ?? "none")"
        case .writeInputChooser:
            "write-input-chooser-\(selectedProfile?.id.description ?? "none")"
        case .loading(let mode, let phase):
            "loading-\(mode.rawValue)-\(String(describing: phase))"
        case .quest(let session):
            // Keep the quest shell's identity stable while advancing between
            // words. WriteQuestView owns the in-quest feedback animation, so
            // rebuilding and scaling this root would move the handwriting
            // coordinate space underneath a child's finger.
            "quest-\(session.id.description)"
        case .blocked(let mode, let reason):
            "blocked-\(mode.rawValue)-\(String(describing: reason))"
        case .result(let result):
            "result-\(result.mode.rawValue)"
        }
    }
}
