import SwiftUI
import TadaWordsDesignSystem
import TadaWordsDomain
import TadaWordsFeatures
import TadaWordsGuardianFeatures

enum ApplicationOrientationRoute: Equatable {
    case child
    case parents
    case firstRunParents
}

enum ApplicationOrientationPolicy {
    static func mode(
        for route: ApplicationOrientationRoute
    ) -> InterfaceOrientationMode {
        switch route {
        case .child:
            .childLandscape
        case .parents, .firstRunParents:
            .parentFlexible
        }
    }
}

@MainActor
public struct TadaWordsApplicationView: View {
    @Environment(\.scenePhase) private var scenePhase
    private struct RefreshedChildState {
        let profiles: [KidProfile]
        let lastSelectedProfileID: ProfileID?
    }

    private enum Area {
        case child
        case guardian
    }

    private enum LaunchMode {
        case demo
        case production
        case unconfigured
    }

    @State private var area: Area = .child
    @State private var refreshedChildState: RefreshedChildState?
    @State private var childProfileRevision = UUID()
    @State private var hasCompletedFirstRunOnboarding = false
    @StateObject private var bootstrapModel: ApplicationBootstrapModel

    private let launchMode: LaunchMode
    private let audioPromptService: any AudioPromptService
    private let audioExperienceService: any AudioExperienceService
    private let speechRecognitionService: any SpeechRecognitionService
    private let handwritingRecognitionService: any HandwritingRecognitionService
    private let imageTextRecognitionService: any ImageTextRecognizing
    private let speechPermissionActions: SpeechPermissionActions
    private let notificationScheduler: (any LearningNotificationScheduling)?
    private let voiceprintEnrollmentService: (any DeviceVoiceprintEnrolling)?
    private let voiceprintRepository: (any DeviceVoiceprintRepository)?
    private let sensitiveActionAuthorizer: any SensitiveGuardianActionAuthorizing
    private let familySyncCapability: FamilySyncCapability
    private let interfaceOrientationController: any InterfaceOrientationControlling

    /// Preview-only convenience. Production callers must use the initializer
    /// that accepts an Application Support directory and a default profile.
    public init(demoMode: Bool) {
        self.init(
            audioPromptService: NoAudioPromptService(),
            demoMode: demoMode
        )
    }

    /// Preview-only convenience with real audio playback.
    public init(
        audioPromptService: any AudioPromptService,
        audioExperienceService: any AudioExperienceService =
            SilentAudioExperienceService(),
        interfaceOrientationController: any InterfaceOrientationControlling =
            InertInterfaceOrientationController(),
        demoMode: Bool
    ) {
        launchMode = demoMode ? .demo : .unconfigured
        self.audioPromptService = audioPromptService
        self.audioExperienceService = audioExperienceService
        speechRecognitionService = NoSpeechRecognitionService()
        handwritingRecognitionService = NoHandwritingRecognitionService()
        imageTextRecognitionService = NoImageTextRecognitionService()
        speechPermissionActions = .unavailable
        notificationScheduler = nil
        voiceprintEnrollmentService = nil
        voiceprintRepository = nil
        sensitiveActionAuthorizer = AllowSensitiveGuardianActions()
        familySyncCapability = .deviceOnly
        self.interfaceOrientationController = interfaceOrientationController
        _bootstrapModel = StateObject(
            wrappedValue: ApplicationBootstrapModel(
                bootstrapper: UnavailableApplicationBootstrapper()
            )
        )
    }

    public init(
        applicationSupportDirectory: @escaping @Sendable () throws -> URL,
        defaultProfile: KidProfile,
        clock: any AppClock = SystemAppClock(),
        timeZone: TimeZone = .current,
        audioPromptService: any AudioPromptService,
        speechRecognitionService: any SpeechRecognitionService,
        handwritingRecognitionService: any HandwritingRecognitionService,
        imageTextRecognitionService: any ImageTextRecognizing =
            NoImageTextRecognitionService(),
        requestSpeechAuthorization: @escaping @Sendable () async -> Bool,
        audioExperienceService: any AudioExperienceService =
            SilentAudioExperienceService(),
        familySyncTransport: (any FamilySyncTransport)? = nil,
        notificationScheduler: (any LearningNotificationScheduling)? = nil,
        voiceprintEnrollmentService: (any DeviceVoiceprintEnrolling)? = nil,
        voiceprintRepository: (any DeviceVoiceprintRepository)? = nil,
        sensitiveActionAuthorizer: any SensitiveGuardianActionAuthorizing =
            AllowSensitiveGuardianActions(),
        interfaceOrientationController: any InterfaceOrientationControlling =
            InertInterfaceOrientationController()
    ) {
        let resolvedFamilySyncTransport =
            familySyncTransport ?? LocalOnlyFamilySyncTransport()
        let bootstrapper = ProductionApplicationBootstrapper(
            applicationSupportDirectory: applicationSupportDirectory,
            defaultProfile: defaultProfile,
            clock: clock,
            timeZone: timeZone,
            familySyncTransport: resolvedFamilySyncTransport,
            notificationScheduler: notificationScheduler
        )
        launchMode = .production
        self.audioPromptService = audioPromptService
        self.audioExperienceService = audioExperienceService
        self.speechRecognitionService = speechRecognitionService
        self.handwritingRecognitionService = handwritingRecognitionService
        self.imageTextRecognitionService = imageTextRecognitionService
        speechPermissionActions = SpeechPermissionActions(
            requestAuthorization: requestSpeechAuthorization
        )
        self.notificationScheduler = notificationScheduler
        self.voiceprintEnrollmentService = voiceprintEnrollmentService
        self.voiceprintRepository = voiceprintRepository
        self.sensitiveActionAuthorizer = sensitiveActionAuthorizer
        familySyncCapability = resolvedFamilySyncTransport.capability
        self.interfaceOrientationController = interfaceOrientationController
        _bootstrapModel = StateObject(
            wrappedValue: ApplicationBootstrapModel(
                bootstrapper: bootstrapper
            )
        )
    }

    public var body: some View {
        Group {
            switch launchMode {
            case .demo:
                demoView
            case .production:
                productionView
                    .task {
                        bootstrapModel.startIfNeeded()
                    }
            case .unconfigured:
                UnconfiguredApplicationView()
                    .onAppear {
                        applyOrientation(for: .child)
                    }
            }
        }
        .preferredColorScheme(.light)
        .onChange(of: scenePhase) { _, phase in
            guard phase == .active else { return }
            applyOrientation(for: currentOrientationRoute)
            synchronizeIfReady()
        }
    }

    @ViewBuilder
    private var demoView: some View {
        Group {
            switch area {
            case .child:
                TadaWordsRootView.demo(
                    audioPromptService: audioPromptService,
                    audioExperienceService: audioExperienceService,
                    onOpenGuardian: showGuardianArea
                )
                .onAppear {
                    applyOrientation(for: .child)
                }
            case .guardian:
                GuardianRootView(
                    audioPromptService: audioPromptService,
                    audioExperienceService: audioExperienceService,
                    onExit: showChildArea
                )
                .onAppear {
                    applyOrientation(for: .parents)
                }
            }
        }
        .task {
            await audioExperienceService.playLaunchSignature()
        }
    }

    @ViewBuilder
    private var productionView: some View {
        switch bootstrapModel.state {
        case .idle, .loading:
            ApplicationLoadingView()
                .onAppear {
                    applyOrientation(for: .child)
                }
        case .ready(let environment):
            productionContent(environment: environment)
        case .failed(let failure):
            ApplicationFailureView(
                failure: failure,
                onRetry: bootstrapModel.retry
            )
            .onAppear {
                applyOrientation(for: .child)
            }
        }
    }

    @ViewBuilder
    private func productionContent(
        environment: ProductionApplicationEnvironment
    ) -> some View {
        let childProfiles = refreshedChildState?.profiles ?? environment.profiles
        let initialProfileID =
            refreshedChildState == nil
            ? environment.lastSelectedProfileID
            : refreshedChildState?.lastSelectedProfileID
        let onboardingPurpose = environment.firstRunOnboardingPurpose ?? .fullSetup
        let onboardingProfile = FirstRunOnboardingProfileSelection.profile(
            in: childProfiles,
            purpose: onboardingPurpose,
            lastSelectedProfileID: initialProfileID
        )
        Group {
            if environment.requiresFirstRunOnboarding
                && !hasCompletedFirstRunOnboarding
            {
                if let profile = onboardingProfile {
                    FirstRunParentOnboardingView(
                        initialProfile: profile,
                        purpose: onboardingPurpose,
                        familySyncCapability: familySyncCapability,
                        onFinish: { submission in
                            try await completeFirstRunOnboarding(
                                submission: submission,
                                profileID: profile.id,
                                environment: environment
                            )
                        }
                    )
                    .onAppear {
                        applyOrientation(for: .firstRunParents)
                    }
                } else {
                    ApplicationFailureView(
                        failure: ApplicationBootstrapFailure(
                            error: FirstRunOnboardingError.profileNotFound
                        ),
                        onRetry: bootstrapModel.retry
                    )
                    .onAppear {
                        applyOrientation(for: .firstRunParents)
                    }
                }
            } else {
                Group {
                    switch area {
                    case .child:
                        TadaWordsRootView(
                            profiles: childProfiles,
                            profileRepository: environment.profileRepository,
                            wordPoolRepository: environment.wordPoolRepository,
                            attemptEventRepository: environment.learningRecordRepository,
                            wordProgressRepository: environment.learningRecordRepository,
                            practiceSettingsRepository:
                                environment.practiceSettingsRepository,
                            dailyQuestRepository: environment.dailyQuestRepository,
                            childSessionRepository: environment.childSessionRepository,
                            initialProfileID: initialProfileID,
                            clock: environment.clock,
                            timeZone: environment.timeZone,
                            audioPromptService: audioPromptService,
                            audioExperienceService: audioExperienceService,
                            speechRecognitionService: speechRecognitionService,
                            handwritingRecognitionService: handwritingRecognitionService,
                            speechPermissionActions: speechPermissionActions,
                            onLearningDataChanged: {
                                await environment.notificationReconciler?.reconcileAll()
                            },
                            onOpenGuardian: showGuardianArea
                        )
                        .id(childProfileRevision)
                        .onAppear {
                            applyOrientation(for: .child)
                        }
                    case .guardian:
                        GuardianRootView(
                            store: environment.guardianStore,
                            audioPromptService: audioPromptService,
                            audioExperienceService: audioExperienceService,
                            familySyncCoordinator: environment.familySyncCoordinator,
                            notificationScheduler: notificationScheduler,
                            voiceprintEnrollmentService: voiceprintEnrollmentService,
                            voiceprintRepository: voiceprintRepository,
                            requestSpeechAuthorization:
                                speechPermissionActions.requestAuthorization,
                            imageTextRecognitionService: imageTextRecognitionService,
                            sensitiveActionAuthorizer: sensitiveActionAuthorizer,
                            onExit: {
                                refreshProfilesAndShowChild(environment: environment)
                            }
                        )
                        .onAppear {
                            applyOrientation(for: .parents)
                        }
                    }
                }
            }
        }
        .task {
            if !environment.requiresFirstRunOnboarding
                || hasCompletedFirstRunOnboarding
            {
                Task {
                    _ = await environment.familySyncCoordinator.synchronize()
                    await environment.notificationReconciler?.reconcileAll()
                }
            }
            if let voiceprintRepository {
                for tombstone in (try? await environment.tombstoneRepository.tombstones()) ?? [] {
                    try? await voiceprintRepository.delete(for: tombstone.profileID)
                }
            }
            await prepareLaunchAudio(
                environment: environment,
                profiles: childProfiles,
                initialProfileID: initialProfileID
            )
        }
    }

    private func completeFirstRunOnboarding(
        submission: FirstRunOnboardingSubmission,
        profileID: ProfileID,
        environment: ProductionApplicationEnvironment
    ) async throws {
        let coordinator = FirstRunOnboardingCoordinator(
            profileRepository: environment.profileRepository,
            childSessionRepository: environment.childSessionRepository,
            onboardingRepository: environment.firstRunOnboardingRepository,
            guardianStore: environment.guardianStore,
            clock: environment.clock
        )
        let completion = try await coordinator.complete(
            profileID: profileID,
            submission: submission
        )
        refreshedChildState = RefreshedChildState(
            profiles: completion.profiles,
            lastSelectedProfileID: completion.selectedProfileID
        )
        childProfileRevision = UUID()
        applyOrientation(for: .child)
        hasCompletedFirstRunOnboarding = true

        Task {
            _ = await environment.familySyncCoordinator.synchronize()
            await environment.notificationReconciler?.reconcileAll()
        }

        if let selectedProfileID = completion.selectedProfileID,
            let profile = completion.profiles.first(where: {
                $0.id == selectedProfileID
            })
        {
            let settings = try? await environment.practiceSettingsRepository.settings(
                for: profile.id
            )
            await audioExperienceService.configure(
                world: profile.selectedWorld,
                preferences: settings?.audio ?? .default
            )
        }
    }

    private func synchronizeIfReady() {
        guard case .ready(let environment) = bootstrapModel.state else { return }
        guard
            !environment.requiresFirstRunOnboarding
                || hasCompletedFirstRunOnboarding
        else { return }
        Task {
            _ = await environment.familySyncCoordinator.synchronize()
            await environment.notificationReconciler?.reconcileAll()
        }
    }

    private func prepareLaunchAudio(
        environment: ProductionApplicationEnvironment,
        profiles: [KidProfile],
        initialProfileID: ProfileID?
    ) async {
        let profile =
            initialProfileID.flatMap { profileID in
                profiles.first(where: { $0.id == profileID })
            } ?? profiles.first
        if let profile {
            let settings = try? await environment.practiceSettingsRepository.settings(
                for: profile.id
            )
            await audioExperienceService.configure(
                world: profile.selectedWorld,
                preferences: settings?.audio ?? .default
            )
        }
        await audioExperienceService.playLaunchSignature()
    }

    private func refreshProfilesAndShowChild(
        environment: ProductionApplicationEnvironment
    ) {
        Task {
            do {
                async let profiles = environment.profileRepository.profiles()
                async let lastSelectedProfileID =
                    environment.childSessionRepository.lastSelectedProfileID()
                let refreshedProfiles = try await profiles
                let savedProfileID = try await lastSelectedProfileID
                refreshedChildState = RefreshedChildState(
                    profiles: refreshedProfiles,
                    lastSelectedProfileID: savedProfileID.flatMap { candidate in
                        refreshedProfiles.contains(where: { $0.id == candidate })
                            ? candidate
                            : nil
                    }
                )
                childProfileRevision = UUID()
            } catch {
                // The existing child UI remains usable if a refresh fails. No
                // profile data is rewritten or discarded here.
            }
            applyOrientation(for: .child)
            area = .child
        }
    }

    private func showChildArea() {
        applyOrientation(for: .child)
        area = .child
    }

    private func showGuardianArea() {
        Task {
            await audioExperienceService.stopAmbientAudio()
        }
        applyOrientation(for: .parents)
        area = .guardian
    }

    private func applyOrientation(for route: ApplicationOrientationRoute) {
        interfaceOrientationController.apply(
            ApplicationOrientationPolicy.mode(for: route)
        )
    }

    private var currentOrientationRoute: ApplicationOrientationRoute {
        if case .production = launchMode,
            case .ready(let environment) = bootstrapModel.state,
            environment.requiresFirstRunOnboarding,
            !hasCompletedFirstRunOnboarding
        {
            return .firstRunParents
        }
        if case .guardian = area {
            return .parents
        }
        return .child
    }
}

private struct ApplicationLoadingView: View {
    var body: some View {
        TadaWorldBackground(theme: .moonpetal, sceneStyle: .lobby) {
            TadaChildStatePanel(
                theme: .moonpetal,
                symbol: "sparkles",
                title: "Opening Tada Words…",
                message: "Getting your quests ready.",
                showsProgress: true
            )
            .padding(TadaPrimitiveTokens.Spacing.large)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }
}

private struct ApplicationFailureView: View {
    let failure: ApplicationBootstrapFailure
    let onRetry: () -> Void

    var body: some View {
        TadaWorldBackground(theme: .moonpetal, sceneStyle: .lobby) {
            TadaChildStatePanel(
                theme: .moonpetal,
                symbol: "externaldrive.badge.exclamationmark",
                title: failure.title,
                message: failure.message
            ) {
                Button("Try Again", action: onRetry)
                    .buttonStyle(TadaPrimaryButtonStyle(fill: TadaWorldTheme.moonpetal.primary))
            }
            .padding(TadaPrimitiveTokens.Spacing.large)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }
}

private struct UnconfiguredApplicationView: View {
    var body: some View {
        TadaWorldBackground(theme: .moonpetal, sceneStyle: .lobby) {
            TadaChildStatePanel(
                theme: .moonpetal,
                symbol: "wrench.and.screwdriver",
                title: "Tada Words isn’t configured",
                message: "Launch the production app or explicitly enable demo mode."
            )
            .padding(TadaPrimitiveTokens.Spacing.large)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }
}

private struct NoAudioPromptService: AudioPromptService {
    func play(_ prompt: WordPrompt, for profileID: ProfileID) async throws {}
}

private struct NoSpeechRecognitionService: SpeechRecognitionService {
    func recognize(
        _ request: SpeechRecognitionRequest
    ) async throws -> RecognitionResult {
        _ = request
        return RecognitionResult(
            decision: .technicalFailure(.serviceUnavailable)
        )
    }
}

private struct NoHandwritingRecognitionService: HandwritingRecognitionService {
    func recognize(
        sample: HandwritingSample,
        prompt: WordPrompt,
        for profileID: ProfileID
    ) async throws -> RecognitionResult {
        _ = sample
        _ = prompt
        _ = profileID
        return RecognitionResult(
            decision: .technicalFailure(.serviceUnavailable)
        )
    }
}
