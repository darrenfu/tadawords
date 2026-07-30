import SwiftUI
import TadaWordsContent
import TadaWordsDesignSystem
import TadaWordsDomain

@MainActor
public struct GuardianRootView: View {
    @Environment(\.scenePhase) private var scenePhase
    @StateObject private var model: GuardianDashboardViewModel
    @AccessibilityFocusState private var loadingOverlayIsFocused: Bool
    private let onExit: () -> Void
    private let imageTextRecognitionService: any ImageTextRecognizing
    private let presetWordCatalog: PresetWordCatalog
    private var externalDataRevision: UUID?
    @State private var externalSyncRefreshTask: Task<Void, Never>?

    /// Preview convenience. Production composition must use `init(store:onExit:)`.
    public init(onExit: @escaping () -> Void = {}) {
        self.onExit = onExit
        imageTextRecognitionService = NoImageTextRecognitionService()
        presetWordCatalog = BundledPresetWordCatalog.catalog
        _model = StateObject(
            wrappedValue: GuardianDashboardViewModel(
                store: DemoGuardianFamilyStore(),
                audioPromptService: SilentGuardianAudioPromptService(),
                audioExperienceService: SilentAudioExperienceService()
            )
        )
    }

    public init(
        audioPromptService: any AudioPromptService,
        audioExperienceService: any AudioExperienceService =
            SilentAudioExperienceService(),
        onExit: @escaping () -> Void = {}
    ) {
        self.onExit = onExit
        imageTextRecognitionService = NoImageTextRecognitionService()
        presetWordCatalog = BundledPresetWordCatalog.catalog
        _model = StateObject(
            wrappedValue: GuardianDashboardViewModel(
                store: DemoGuardianFamilyStore(),
                audioPromptService: audioPromptService,
                audioExperienceService: audioExperienceService
            )
        )
    }

    public init(
        store: any GuardianFamilyStore,
        presetWordCatalog: PresetWordCatalog = BundledPresetWordCatalog.catalog,
        onExit: @escaping () -> Void = {}
    ) {
        self.onExit = onExit
        imageTextRecognitionService = NoImageTextRecognitionService()
        self.presetWordCatalog = presetWordCatalog
        _model = StateObject(
            wrappedValue: GuardianDashboardViewModel(
                store: store,
                audioPromptService: SilentGuardianAudioPromptService(),
                audioExperienceService: SilentAudioExperienceService()
            )
        )
    }

    public init(
        store: any GuardianFamilyStore,
        audioPromptService: any AudioPromptService,
        audioExperienceService: any AudioExperienceService =
            SilentAudioExperienceService(),
        familySyncCoordinator: (any FamilySyncCoordinating)? = nil,
        familySyncCanonicalRecovery:
            (any FamilySyncCanonicalRecoveryProviding)? = nil,
        familySyncAccessManagement:
            (@MainActor (ProfileID) async throws -> Void)? = nil,
        notificationScheduler: (any LearningNotificationScheduling)? = nil,
        voiceprintEnrollmentService: (any DeviceVoiceprintEnrolling)? = nil,
        voiceprintRepository: (any DeviceVoiceprintRepository)? = nil,
        currentSpeechPermissionState:
            @escaping @Sendable () async -> SpeechPermissionState = { .unavailable },
        requestSpeechPermissions:
            @escaping @Sendable () async -> SpeechPermissionState = { .unavailable },
        imageTextRecognitionService: any ImageTextRecognizing =
            NoImageTextRecognitionService(),
        pictureHintProvider: any WordPictureHintProviding =
            NoWordPictureHintProvider(),
        presetWordCatalog: PresetWordCatalog = BundledPresetWordCatalog.catalog,
        sensitiveActionAuthorizer: any SensitiveGuardianActionAuthorizing =
            AllowSensitiveGuardianActions(),
        externalDataRevision: UUID? = nil,
        onExit: @escaping () -> Void = {}
    ) {
        self.onExit = onExit
        self.imageTextRecognitionService = imageTextRecognitionService
        self.presetWordCatalog = presetWordCatalog
        self.externalDataRevision = externalDataRevision
        _model = StateObject(
            wrappedValue: GuardianDashboardViewModel(
                store: store,
                audioPromptService: audioPromptService,
                audioExperienceService: audioExperienceService,
                familySyncCoordinator: familySyncCoordinator,
                familySyncCanonicalRecovery: familySyncCanonicalRecovery,
                familySyncAccessManagement: familySyncAccessManagement,
                notificationScheduler: notificationScheduler,
                voiceprintEnrollmentService: voiceprintEnrollmentService,
                voiceprintRepository: voiceprintRepository,
                currentSpeechPermissionState: currentSpeechPermissionState,
                requestSpeechPermissions: requestSpeechPermissions,
                pictureHintProvider: pictureHintProvider,
                sensitiveActionAuthorizer: sensitiveActionAuthorizer
            )
        )
    }

    public var body: some View {
        ZStack {
            GuardianSemanticTokens.background
                .ignoresSafeArea()

            destinationView
                .id(model.transitionKey)
                .tadaNavigationMotion(
                    value: model.transitionKey,
                    standardTransition: .opacity.combined(with: .move(edge: .trailing))
                )
                .accessibilityHidden(model.isLoading)

            if model.isLoading {
                loadingOverlay
            }
        }
        .guardianDismissesKeyboardOnOutsideTap()
        .foregroundStyle(GuardianSemanticTokens.foreground)
        .environment(\.font, .system(.body, design: .rounded))
        .onChange(of: model.isLoading, initial: true) { _, isLoading in
            loadingOverlayIsFocused = isLoading
        }
        .onChange(of: externalDataRevision) { _, revision in
            guard revision != nil else { return }
            externalSyncRefreshTask?.cancel()
            externalSyncRefreshTask = Task {
                await model.refreshAfterExternalSyncAndWait()
            }
        }
        .onChange(of: scenePhase) { _, phase in
            guard phase == .active else { return }
            model.refreshSpeechPermissionState()
        }
        .onDisappear {
            externalSyncRefreshTask?.cancel()
            externalSyncRefreshTask = nil
        }
        .alert(
            "Something went wrong",
            isPresented: Binding(
                get: { model.errorMessage != nil },
                set: { if !$0 { model.errorMessage = nil } }
            )
        ) {
            Button("OK", role: .cancel) {
                model.errorMessage = nil
            }
        } message: {
            Text(model.errorMessage ?? "Please try again.")
        }
    }

    @ViewBuilder
    private var destinationView: some View {
        switch model.destination {
        case .parentGate:
            GuardianParentGateView(
                onExit: onExit,
                onContinue: model.unlockGuardianArea
            )

        case .dashboard:
            if let snapshot = model.snapshot,
                let family = model.familySnapshot
            {
                GuardianTodayView(
                    snapshot: snapshot,
                    family: family,
                    onBack: returnToPreviousPage,
                    onSelectProfile: model.selectProfile,
                    onEditProfile: model.showEditProfileFromDashboard,
                    onOpenWordsAndPractice: model.showWordsAndPractice,
                    onOpenProgressAndPerformance: model.showProgressAndPerformance,
                    onOpenAppAndFamily: model.showAppAndFamily,
                    syncState: model.guardianSyncState
                )
            } else {
                GuardianLoadingView(onRetry: model.refresh)
            }

        case .parentSection(let section):
            if let snapshot = model.snapshot {
                switch section {
                case .wordsAndPractice:
                    GuardianWordsAndPracticeView(
                        snapshot: snapshot,
                        onBack: model.showDashboard,
                        onManageWords: model.showQuickAdd,
                        onOpenPresets: model.showPresetWords,
                        onOpenPracticePlan: {
                            model.showSettings(.practicePlan)
                        }
                    )

                case .progressAndPerformance:
                    GuardianProgressAndPerformanceView(
                        snapshot: snapshot,
                        syncState: model.guardianSyncState,
                        onBack: model.showDashboard,
                        onOpenReports: model.showReports
                    )

                case .appAndFamily:
                    GuardianAppAndFamilyView(
                        snapshot: snapshot,
                        syncState: model.guardianSyncState,
                        onBack: model.showDashboard,
                        onOpenSoundAndAccessibility: {
                            model.showSettings(.soundAndAccessibility)
                        },
                        onOpenNotifications: {
                            model.showSettings(.notifications)
                        },
                        speechPermissionState: model.speechPermissionState,
                        onOpenSpeechPermissions: model.showSpeechPermissions,
                        onOpenFamilySync: model.showFamilySync,
                        onOpenThirdPartyNotices: model.showThirdPartyNotices
                    )
                }
            } else {
                GuardianLoadingView(onRetry: model.refresh)
            }

        case .profiles:
            if let family = model.familySnapshot {
                GuardianProfilesView(
                    family: family,
                    onBack: {
                        if model.returnFromProfiles() {
                            onExit()
                        }
                    },
                    onSelect: model.selectProfile,
                    onEdit: model.showEditProfile,
                    onVoiceprint: model.showVoiceprint,
                    onAdd: model.showNewProfile
                )
            } else {
                GuardianLoadingView(onRetry: model.refresh)
            }

        case .profileEditor(let profile):
            GuardianProfileEditorView(
                existingProfile: profile,
                onBack: {
                    if model.returnFromProfileEditor() {
                        onExit()
                    }
                },
                onSave: { draft in
                    model.saveProfile(
                        existingProfile: profile,
                        draft: draft
                    )
                },
                onDelete: profile.map { existing in
                    { model.deleteProfile(existing) }
                }
            )

        case .quickAdd:
            GuardianWordManagerView(
                initialMode: .read,
                readWords: model.snapshot?.readPool ?? [],
                writeWords: model.snapshot?.writePool ?? [],
                practiceFrequencyByWordID: model.snapshot?.practiceFrequencyByWordID ?? [:],
                undoWordsByMode: model.undoWordsByMode,
                isUpdatingWordPool: model.isUpdatingWordPool,
                imageTextRecognitionService: imageTextRecognitionService,
                hasConfirmedRemovalThisSession: Binding(
                    get: { model.hasConfirmedWordRemovalThisSession },
                    set: { model.setWordRemovalConfirmation($0) }
                ),
                onBack: model.returnToParentSection,
                onSubmit: model.addWords,
                onPlay: model.play,
                onSetWordsActive: { prompts, isActive in
                    await model.setWordsActive(prompts, isActive: isActive)
                }
            )

        case .presetWords:
            if let snapshot = model.snapshot {
                GuardianPresetWordsView(
                    profile: snapshot.profile,
                    catalog: presetWordCatalog,
                    readWords: snapshot.readPool,
                    writeWords: snapshot.writePool,
                    onBack: model.returnToParentSection,
                    onSubmit: { profileID, request in
                        await model.addPresetWords(request, for: profileID)
                    },
                    onRollback: model.rollbackPresetAdditions
                )
            } else {
                GuardianLoadingView(onRetry: model.refresh)
            }

        case .pool(let mode):
            GuardianWordManagerView(
                initialMode: mode,
                readWords: model.snapshot?.readPool ?? [],
                writeWords: model.snapshot?.writePool ?? [],
                practiceFrequencyByWordID: model.snapshot?.practiceFrequencyByWordID ?? [:],
                undoWordsByMode: model.undoWordsByMode,
                isUpdatingWordPool: model.isUpdatingWordPool,
                imageTextRecognitionService: imageTextRecognitionService,
                hasConfirmedRemovalThisSession: Binding(
                    get: { model.hasConfirmedWordRemovalThisSession },
                    set: { model.setWordRemovalConfirmation($0) }
                ),
                onBack: model.returnToParentSection,
                onSubmit: model.addWords,
                onPlay: model.play,
                onSetWordsActive: { prompts, isActive in
                    await model.setWordsActive(prompts, isActive: isActive)
                }
            )

        case .settings(let section):
            if let settings = model.snapshot?.practiceSettings {
                GuardianPracticeSettingsView(
                    settings: settings,
                    section: section,
                    onBack: model.returnToParentSection,
                    onSave: { settings in
                        if section.usesAutoSave {
                            model.autoSavePracticeSettings(
                                settings,
                                section: section
                            )
                        } else {
                            model.savePracticeSettings(
                                settings,
                                section: section
                            )
                        }
                    }
                )
            } else {
                GuardianLoadingView(onRetry: model.refresh)
            }

        case .familySync:
            GuardianFamilySyncView(
                status: model.syncStatus,
                isEnabled: model.isFamilySyncEnabled,
                profileErasure: model.profileErasurePresentation,
                shareURL: model.shareURL,
                canManageAccess: model.canManageFamilyAccess,
                shareURLText: $model.shareURLText,
                onBack: model.returnFromFamilySync,
                onSetEnabled: model.setFamilySyncEnabled,
                onSyncNow: model.syncNow,
                onCreateShare: model.createFamilyShare,
                onManageAccess: model.manageFamilyAccess,
                onAcceptShare: model.acceptFamilyShare,
                onRetryProfileErasure: model.retryProfileErasure,
                canonicalRecoveryPlan: model.canonicalRecoveryPlan,
                isCanonicalRecoveryRunning:
                    model.isCanonicalRecoveryRunning,
                canonicalRecoveryMessage: model.canonicalRecoveryMessage,
                onRecoverCanonicalData: model.recoverCanonicalLocalData
            )

        case .speechPermissions:
            GuardianSpeechPermissionSetupView(
                state: model.speechPermissionState,
                isRequesting: model.isRequestingSpeechPermissions,
                onBack: model.returnToParentSection,
                onRequest: model.setUpSpeechPermissions
            )

        case .thirdPartyNotices:
            GuardianThirdPartyNoticesView(
                onBack: model.returnToParentSection
            )

        case .voiceprint(let profile):
            GuardianVoiceprintEnrollmentView(
                profile: profile,
                progress: model.voiceprintProgress,
                isCapturing: model.isCapturingVoiceprint,
                currentSentence: model.currentVoiceprintSentence,
                currentSampleNumber: model.currentVoiceprintSampleNumber,
                sampleCount: model.voiceprintSampleCount,
                isPlayingPrompt: model.isPlayingVoiceprintPrompt,
                guidanceMessage: model.voiceprintGuidanceMessage,
                onBack: model.cancelVoiceprint,
                onBegin: { model.beginVoiceprint(for: profile) },
                onReplaySentence: {
                    model.replayVoiceprintSentence(for: profile)
                },
                onCapture: model.captureVoiceprintSegment,
                onFinish: { model.finishVoiceprint(for: profile) }
            )

        case .reports:
            GuardianReportsView(
                report: model.report,
                selectedPeriod: model.reportPeriod,
                onBack: model.returnToParentSection,
                onSelectPeriod: model.loadReport,
                onCorrect: model.correctAttempt,
                onAuthorizeExport: model.authorizeReportExport
            )

        case .importReport(let report):
            GuardianImportReportView(
                report: report,
                onAddMore: model.showQuickAdd,
                onDone: model.returnToParentSection
            )
        }
    }

    private func routeSettings(for mode: LearningMode) -> LearningRouteSettings {
        guard let settings = model.snapshot?.practiceSettings else {
            switch mode {
            case .read:
                return .defaultRead
            case .write:
                return .defaultWrite
            }
        }
        return settings.route(for: mode)
    }

    private func returnToPreviousPage() {
        // Leaving parent tools still restores the gate for the next visit.
        model.lockGuardianArea()
        onExit()
    }

    private var loadingOverlay: some View {
        ZStack {
            Color.black.opacity(0.12)
                .ignoresSafeArea()
            ProgressView("Saving…")
                .font(.system(.body, design: .rounded, weight: .semibold))
                .padding(24)
                .background(
                    .regularMaterial,
                    in: RoundedRectangle(
                        cornerRadius: GuardianPrimitiveTokens.Radius.medium,
                        style: .continuous
                    ))
        }
        .accessibilityAddTraits(.isModal)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Saving")
        .accessibilityHint("Please wait while your changes are saved")
        .accessibilityFocused($loadingOverlayIsFocused)
    }
}

private struct SilentGuardianAudioPromptService: AudioPromptService {
    func play(_ prompt: WordPrompt, for profileID: ProfileID) async throws {
        _ = prompt
        _ = profileID
    }
}

private struct GuardianLoadingView: View {
    let onRetry: () -> Void

    var body: some View {
        VStack(spacing: GuardianPrimitiveTokens.Spacing.medium) {
            ProgressView()
                .controlSize(.large)
            Text("Loading guardian tools…")
                .font(.system(.headline, design: .rounded, weight: .semibold))
            Button("Try again", action: onRetry)
                .buttonStyle(.bordered)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
