import Foundation
import SwiftUI
import TadaWordsContent
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

enum FirstRunOnboardingPresentationIdentity {
    static func value(
        purpose: FirstRunOnboardingPurpose,
        onboardingProfileID: ProfileID?
    ) -> String {
        // A Create -> Find containment can replace the staged Profile with a
        // remote receipt while the Find task is still returning. Profile IDs
        // therefore must not participate in SwiftUI identity: recreating the
        // view would discard its successful discovery state and require a
        // second tap.
        _ = onboardingProfileID
        return "first-run-\(purpose.rawValue)"
    }
}

enum FamilySyncBackgroundResultPolicy {
    static func result(
        status: FamilySyncStatus,
        receiptTokenBefore: String?,
        receiptTokenAfter: String?
    ) -> FamilySyncBackgroundFetchResult {
        if case .failed = status { return .failed }
        guard let receiptTokenBefore, let receiptTokenAfter,
            receiptTokenBefore != receiptTokenAfter
        else { return .noData }
        return .newData
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
    @State private var familySyncDataRevision: UUID?
    @State private var hasCompletedFirstRunOnboarding = false
    @StateObject private var launchPresentation = AppLaunchPresentationCoordinator()
    @StateObject private var bootstrapModel: ApplicationBootstrapModel

    private let launchMode: LaunchMode
    private let audioPromptService: any AudioPromptService
    private let audioExperienceService: any AudioExperienceService
    private let speechRecognitionService: any SpeechRecognitionService
    private let handwritingRecognitionService: any HandwritingRecognitionService
    private let imageTextRecognitionService: any ImageTextRecognizing
    private let pictureHintProvider: any WordPictureHintProviding
    private let speechPermissionActions: SpeechPermissionActions
    private let currentSpeechPermissionState: @Sendable () async -> SpeechPermissionState
    private let requestSpeechPermissions: @Sendable () async -> SpeechPermissionState
    private let notificationScheduler: (any LearningNotificationScheduling)?
    private let voiceprintEnrollmentService: (any DeviceVoiceprintEnrolling)?
    private let voiceprintRepository: (any DeviceVoiceprintRepository)?
    private let sensitiveActionAuthorizer: any SensitiveGuardianActionAuthorizing
    private let familySyncCapability: FamilySyncCapability
    private let familySyncAccessManagement: (@MainActor (ProfileID) async throws -> Void)?
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
        imageTextRecognitionService = Self.makeDemoImageTextRecognitionService()
        pictureHintProvider = NoWordPictureHintProvider()
        speechPermissionActions = .unavailable
        currentSpeechPermissionState = { .unavailable }
        requestSpeechPermissions = { .unavailable }
        notificationScheduler = nil
        voiceprintEnrollmentService = nil
        voiceprintRepository = nil
        sensitiveActionAuthorizer = AllowSensitiveGuardianActions()
        familySyncCapability = .deviceOnly
        familySyncAccessManagement = nil
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
        pictureHintProvider: any WordPictureHintProviding =
            NoWordPictureHintProvider(),
        currentSpeechPermissionState:
            @escaping @Sendable () async -> SpeechPermissionState,
        requestSpeechPermissions:
            @escaping @Sendable () async -> SpeechPermissionState,
        audioExperienceService: any AudioExperienceService =
            SilentAudioExperienceService(),
        familySyncTransport: (any FamilySyncTransport)? = nil,
        familySyncAccessManagement:
            (@MainActor (ProfileID) async throws -> Void)? = nil,
        notificationScheduler: (any LearningNotificationScheduling)? = nil,
        voiceprintEnrollmentService: (any DeviceVoiceprintEnrolling)? = nil,
        voiceprintRepository: (any DeviceVoiceprintRepository)? = nil,
        profileMutationGate: ProfileScopedMutationGate = ProfileScopedMutationGate(),
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
            notificationScheduler: notificationScheduler,
            voiceprintRepository: voiceprintRepository,
            profileMutationGate: profileMutationGate
        )
        launchMode = .production
        self.audioPromptService = audioPromptService
        self.audioExperienceService = audioExperienceService
        self.speechRecognitionService = speechRecognitionService
        self.handwritingRecognitionService = handwritingRecognitionService
        self.imageTextRecognitionService = imageTextRecognitionService
        self.pictureHintProvider = pictureHintProvider
        self.currentSpeechPermissionState = currentSpeechPermissionState
        self.requestSpeechPermissions = requestSpeechPermissions
        speechPermissionActions = SpeechPermissionActions {
            await currentSpeechPermissionState().isAuthorized
        }
        self.notificationScheduler = notificationScheduler
        self.voiceprintEnrollmentService = voiceprintEnrollmentService
        self.voiceprintRepository = voiceprintRepository
        self.sensitiveActionAuthorizer = sensitiveActionAuthorizer
        familySyncCapability = resolvedFamilySyncTransport.capability
        self.familySyncAccessManagement = familySyncAccessManagement
        self.interfaceOrientationController = interfaceOrientationController
        _bootstrapModel = StateObject(
            wrappedValue: ApplicationBootstrapModel(
                bootstrapper: bootstrapper
            )
        )
    }

    public var body: some View {
        ZStack {
            applicationContent
                .allowsHitTesting(!launchPresentation.isShowingLaunchPage)
                .accessibilityHidden(launchPresentation.isShowingLaunchPage)

            if launchPresentation.isShowingLaunchPage {
                AppLaunchPage()
                    .transition(.opacity)
            }
        }
        .preferredColorScheme(.light)
        .onAppear {
            startImmediateLaunchPresentationIfNeeded()
        }
        .onChange(of: scenePhase) { _, phase in
            guard phase == .active else { return }
            applyOrientation(for: currentOrientationRoute)
            rearmPendingDiscoveryAfterForegroundAccountChange()
            synchronizeIfReady()
        }
    }

    @ViewBuilder
    private var applicationContent: some View {
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
                    store: DemoGuardianFamilyStore(),
                    audioPromptService: audioPromptService,
                    audioExperienceService: audioExperienceService,
                    imageTextRecognitionService: imageTextRecognitionService,
                    onExit: showChildArea
                )
                .onAppear {
                    applyOrientation(for: .parents)
                }
            }
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
                launchPresentation.startIfNeeded()
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
        // A discovery-first empty install must keep its onboarding identity
        // stable while the receipt stream imports candidate Profiles. Those
        // candidates are presented by the onboarding view and do not become an
        // implicitly editable local seed before the parent adopts one.
        let requestedOnboardingPurpose =
            environment.firstRunOnboardingPurpose ?? .fullSetup
        let onboardingProfiles =
            FirstRunOnboardingProfileSelection
            .profilesForPresentation(
                liveProfiles: childProfiles,
                bootstrappedProfilesWereEmpty: environment.profiles.isEmpty,
                purpose: requestedOnboardingPurpose,
                familySyncCapability: familySyncCapability,
                profileIntent: environment.firstRunProfileIntent,
                pendingCreatedProfileID:
                    environment.firstRunPendingCreatedProfileID
            )
        let onboardingPurpose =
            FirstRunOnboardingProfileSelection.resolvedPurpose(
                requestedOnboardingPurpose,
                in: onboardingProfiles
            )
        let onboardingProfile = FirstRunOnboardingProfileSelection.profile(
            in: onboardingProfiles,
            purpose: onboardingPurpose,
            lastSelectedProfileID: initialProfileID
        )
        Group {
            if environment.requiresFirstRunOnboarding
                && !hasCompletedFirstRunOnboarding
            {
                FirstRunParentOnboardingView(
                    initialProfile: onboardingProfile,
                    purpose: onboardingPurpose,
                    familySyncCapability: familySyncCapability,
                    onDiscoverProfiles: {
                        try await discoverFirstRunProfiles(
                            environment: environment
                        )
                    },
                    onFinish: { submission in
                        try await completeFirstRunOnboarding(
                            submission: submission,
                            profileID: onboardingProfile?.id,
                            environment: environment
                        )
                    }
                )
                .id(
                    FirstRunOnboardingPresentationIdentity.value(
                        purpose: onboardingPurpose,
                        onboardingProfileID: onboardingProfile?.id
                    )
                )
                .onAppear {
                    applyOrientation(for: .firstRunParents)
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
                            profileMutationGate: environment.profileMutationGate,
                            initialProfileID: initialProfileID,
                            clock: environment.clock,
                            timeZone: environment.timeZone,
                            audioPromptService: audioPromptService,
                            audioExperienceService: audioExperienceService,
                            speechRecognitionService: speechRecognitionService,
                            handwritingRecognitionService: handwritingRecognitionService,
                            pictureHintProvider: pictureHintProvider,
                            speechPermissionActions: speechPermissionActions,
                            externalDataRevision: familySyncDataRevision,
                            onLearningDataChanged: {
                                Task {
                                    _ = await environment.familySyncCoordinator
                                        .synchronize(
                                            trigger: .localMutation
                                        )
                                }
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
                            familySyncAccessManagement: familySyncAccessManagement,
                            notificationScheduler: notificationScheduler,
                            voiceprintEnrollmentService: voiceprintEnrollmentService,
                            voiceprintRepository: voiceprintRepository,
                            currentSpeechPermissionState: currentSpeechPermissionState,
                            requestSpeechPermissions: requestSpeechPermissions,
                            imageTextRecognitionService: imageTextRecognitionService,
                            pictureHintProvider: pictureHintProvider,
                            sensitiveActionAuthorizer: sensitiveActionAuthorizer,
                            externalDataRevision: familySyncDataRevision,
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
            let foregroundGeneration =
                environment.firstRunDiscoveryAdmissionGate
                .closeForAccountRevalidation()
            _ = await FirstRunDiscoveryAdmissionRevalidator.revalidate(
                generation: foregroundGeneration,
                gate: environment.firstRunDiscoveryAdmissionGate,
                onboardingRepository:
                    environment.firstRunOnboardingRepository,
                familySyncCoordinator: environment.familySyncCoordinator
            )
            await FamilySyncRemoteNotificationBridge.shared.register {
                let onboardingIsPending =
                    await Self.isFirstRunOnboardingPending(in: environment)
                guard !onboardingIsPending else { return .noData }
                let receiptTokenBefore =
                    try? await environment
                    .familySyncApplyTransactionRepository
                    .committedReceiptToken()
                let status = await environment.familySyncCoordinator.synchronize(
                    trigger: .remoteNotification
                )
                let receiptTokenAfter =
                    try? await environment
                    .familySyncApplyTransactionRepository
                    .committedReceiptToken()
                return FamilySyncBackgroundResultPolicy.result(
                    status: status,
                    receiptTokenBefore: receiptTokenBefore,
                    receiptTokenAfter: receiptTokenAfter
                )
            }
            if await environment.familySyncCoordinator.isEnabled() {
                await FamilySyncRemoteNotificationBridge.shared
                    .requestRegistration()
            }
            await FamilySyncConnectivityRecoveryBridge.shared.register {
                let onboardingIsPending =
                    await Self.isFirstRunOnboardingPending(in: environment)
                guard !onboardingIsPending else { return }
                _ = await environment.familySyncCoordinator.synchronize(
                    trigger: .connectivityRecovery
                )
            }
            startProductionLaunchPresentationIfNeeded(
                environment: environment,
                profiles: childProfiles,
                initialProfileID: initialProfileID
            )
            if !environment.requiresFirstRunOnboarding
                || hasCompletedFirstRunOnboarding
            {
                Task {
                    _ = await environment.familySyncCoordinator.synchronize()
                    await environment.notificationReconciler?.reconcileAll()
                }
            }
        }
        .task {
            let receipts =
                await environment
                .familySyncApplyTransactionRepository.committedReceipts()
            for await receipt in receipts {
                guard !Task.isCancelled else { return }
                await applyCommittedFamilySyncReceipt(
                    receipt,
                    environment: environment
                )
            }
        }
    }

    private func applyCommittedFamilySyncReceipt(
        _ receipt: FamilySyncCommittedApplyReceipt,
        environment: ProductionApplicationEnvironment
    ) async {
        do {
            async let profiles = environment.profileRepository.profiles()
            async let lastSelectedProfileID =
                environment.childSessionRepository.lastSelectedProfileID()
            let refreshedProfiles = try await profiles
            let savedProfileID = try await lastSelectedProfileID
            if refreshedProfiles.isEmpty,
                environment.requiresFirstRunOnboarding,
                !hasCompletedFirstRunOnboarding
            {
                try? await environment.firstRunOnboardingRepository
                    .normalizePendingPurpose(.fullSetup)
            }
            refreshedChildState = RefreshedChildState(
                profiles: refreshedProfiles,
                lastSelectedProfileID: savedProfileID.flatMap { candidate in
                    refreshedProfiles.contains(where: { $0.id == candidate })
                        ? candidate
                        : nil
                }
            )
            familySyncDataRevision = receipt.transactionID
            await environment.notificationReconciler?.reconcileAll()
        } catch {
            // The repositories remain authoritative. The next receipt or
            // foreground activation retries this presentation-only read.
        }
    }

    private func completeFirstRunOnboarding(
        submission: FirstRunOnboardingSubmission,
        profileID: ProfileID?,
        environment: ProductionApplicationEnvironment
    ) async throws {
        let coordinator = FirstRunOnboardingCoordinator(
            profileRepository: environment.profileRepository,
            childSessionRepository: environment.childSessionRepository,
            onboardingRepository: environment.firstRunOnboardingRepository,
            guardianStore: environment.guardianStore,
            familySyncCoordinator: familySyncCapability == .iCloud
                ? environment.familySyncCoordinator
                : nil,
            discoveryAdmissionGate:
                environment.firstRunDiscoveryAdmissionGate,
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
            if submission.familySyncEnabled,
                familySyncCapability == .iCloud
            {
                await FamilySyncRemoteNotificationBridge.shared
                    .requestRegistration()
            }
            _ = await environment.familySyncCoordinator.synchronize(
                trigger: .localMutation
            )
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

    private func discoverFirstRunProfiles(
        environment: ProductionApplicationEnvironment
    ) async throws -> [KidProfile] {
        let admissionGeneration =
            environment.firstRunDiscoveryAdmissionGate.currentGeneration()
        let coordinator = FirstRunProfileDiscoveryCoordinator(
            familySyncCoordinator: environment.familySyncCoordinator,
            familySyncTransport: environment.familySyncTransport,
            profileRepository: environment.profileRepository,
            practiceSettingsRepository: environment.practiceSettingsRepository,
            childSessionRepository: environment.childSessionRepository,
            onboardingRepository: environment.firstRunOnboardingRepository,
            profileDataEraser: environment.profileDataEraser,
            familySyncJournalRepository:
                environment.familySyncJournalRepository,
            familySyncApplyTransactionRepository:
                environment.familySyncApplyTransactionRepository,
            discoveryAdmissionGate:
                environment.firstRunDiscoveryAdmissionGate,
            discoveryAdmissionGeneration: admissionGeneration
        )
        let profiles = try await coordinator.discoverProfiles()
        // The actor hop back to MainActor is another suspension boundary. A
        // foreground/account transition in that gap must invalidate the result
        // just like one that races the final repository write.
        try await coordinator.requireCurrentDiscoveryGeneration()
        // Only a successful, current-generation account confirmation/full
        // fetch may make its candidates interactive. A foreground transition
        // during Find advances the generation and keeps admission closed.
        guard
            environment.firstRunDiscoveryAdmissionGate.reopen(
                ifCurrent: admissionGeneration
            )
        else {
            // Close the check-to-reopen race at one lock-protected
            // linearization point. This call persists the reset and opts out
            // sync for the generation that invalidated this result.
            try await coordinator.requireCurrentDiscoveryGeneration()
            throw FirstRunProfileDiscoveryError.resetRequired
        }
        return profiles
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

    private func rearmPendingDiscoveryAfterForegroundAccountChange() {
        guard case .ready(let environment) = bootstrapModel.state else { return }
        // Close synchronously before creating the task. Even if the durable
        // write fails once, stale account-A candidates cannot be admitted.
        let foregroundGeneration =
            environment.firstRunDiscoveryAdmissionGate
            .closeForAccountRevalidation()
        Task {
            _ = await FirstRunDiscoveryAdmissionRevalidator.revalidate(
                generation: foregroundGeneration,
                gate: environment.firstRunDiscoveryAdmissionGate,
                onboardingRepository:
                    environment.firstRunOnboardingRepository,
                familySyncCoordinator: environment.familySyncCoordinator
            )
        }
    }

    private static func isFirstRunOnboardingPending(
        in environment: ProductionApplicationEnvironment
    ) async -> Bool {
        let state = try? await environment.firstRunOnboardingRepository.state()
        return state?.status == .pending
    }

    private func startImmediateLaunchPresentationIfNeeded() {
        switch launchMode {
        case .demo:
            launchPresentation.startIfNeeded(
                playSignature: playLaunchSignature
            )
        case .unconfigured:
            launchPresentation.startIfNeeded()
        case .production:
            break
        }
    }

    private func startProductionLaunchPresentationIfNeeded(
        environment: ProductionApplicationEnvironment,
        profiles: [KidProfile],
        initialProfileID: ProfileID?
    ) {
        launchPresentation.startIfNeeded(
            prepare: {
                await configureLaunchAudio(
                    environment: environment,
                    profiles: profiles,
                    initialProfileID: initialProfileID
                )
            },
            playSignature: playLaunchSignature
        )
    }

    private func playLaunchSignature() async {
        await audioExperienceService.playLaunchSignature()
    }

    private func configureLaunchAudio(
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

    private static func makeDemoImageTextRecognitionService()
        -> any ImageTextRecognizing
    {
        if DemoOCRFixtureLaunchPolicy.isEnabled {
            return DemoOCRFixtureRecognitionService()
        }
        return NoImageTextRecognitionService()
    }
}

private enum DemoOCRFixtureLaunchPolicy {
    static var isEnabled: Bool {
        let arguments = ProcessInfo.processInfo.arguments
        return arguments.contains("--demo-mode")
            && arguments.contains("--ui-testing")
            && arguments.contains("--ui-testing-ocr-fixture")
    }
}

/// A deterministic test seam for the Parent OCR review flow. The service only
/// activates when all three explicit demo UI-test flags are present.
private struct DemoOCRFixtureRecognitionService: ImageTextRecognizing {
    func recognizeText(in imageData: Data) async throws -> [String] {
        guard !imageData.isEmpty else {
            throw ImageTextRecognitionError.invalidImage
        }
        return ["cat read bow to"]
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
