import SwiftUI
import TadaWordsDesignSystem
import TadaWordsDomain

struct ReadQuestView: View {
    let session: QuestSession
    let theme: TadaWorldTheme
    let recognitionService: any SpeechRecognitionService
    let audioExperienceService: any AudioExperienceService
    let permissionActions: SpeechPermissionActions
    let showsSimulatedVoiceCheck: Bool
    let onSpeak: () async -> Void
    let onBack: () -> Void
    let onComplete: (QuestAttemptSummary) -> Void

    @ObservedObject private var questTimer: QuestTimerModel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.verticalSizeClass) private var verticalSizeClass
    @State private var attemptState = QuestAttemptStateMachine()
    @State private var isListening = false
    @State private var isPaused = false
    @State private var isCheckingPermission = false
    @State private var didCheckPermission = false
    @State private var permissionWasDenied = false
    @State private var listeningTask: Task<Void, Never>?
    @State private var completionTask: Task<Void, Never>?
    @State private var feedbackPlaybackTask: Task<Void, Never>?
    @State private var answerPlaybackTask: Task<Void, Never>?
    @State private var hintPlaybackTask: Task<Void, Never>?
    @State private var completionFeedbackLifecycle:
        QuestItemFeedbackLifecycle<
            WordPromptID,
            QuestAttemptSummary
        >
    @State private var responseClock: AttemptResponseClock
    @State private var pendingAttemptTiming = AttemptTiming.unmeasured
    @State private var replayCountSinceLastAttempt = 0
    @State private var isPlayingPronunciationHint = false
    @State private var starFeedbackEvent: QuestStarFeedbackEvent?
    @State private var starSlotFrames: [Int: CGRect] = [:]

    init(
        session: QuestSession,
        questTimer: QuestTimerModel,
        theme: TadaWorldTheme,
        recognitionService: any SpeechRecognitionService,
        audioExperienceService: any AudioExperienceService =
            SilentAudioExperienceService(),
        permissionActions: SpeechPermissionActions,
        showsSimulatedVoiceCheck: Bool = false,
        onSpeak: @escaping () async -> Void,
        onBack: @escaping () -> Void,
        onComplete: @escaping (QuestAttemptSummary) -> Void
    ) {
        self.session = session
        self.theme = theme
        self.recognitionService = recognitionService
        self.audioExperienceService = audioExperienceService
        self.permissionActions = permissionActions
        self.showsSimulatedVoiceCheck = showsSimulatedVoiceCheck
        self.onSpeak = onSpeak
        self.onBack = onBack
        self.onComplete = onComplete
        _questTimer = ObservedObject(
            wrappedValue: questTimer
        )
        _attemptState = State(
            initialValue: QuestAttemptStateMachine(
                policy: .read,
                incorrectAttemptLimit: session.incorrectAttemptLimit
            )
        )
        _responseClock = State(
            initialValue: AttemptResponseClock(
                startingAt: questTimer.elapsedSeconds
            )
        )
        _completionFeedbackLifecycle = State(
            initialValue: QuestItemFeedbackLifecycle(
                itemID: session.prompt.id
            )
        )
    }

    var body: some View {
        TadaWorldBackground(theme: theme, sceneStyle: .quest) {
            GeometryReader { proxy in
                ZStack {
                    VStack(spacing: TadaPrimitiveTokens.Spacing.small) {
                        QuestChrome(
                            mode: .read,
                            currentItem: session.currentItem,
                            totalItems: session.totalItems,
                            earnedStars: session.earnedItemCount,
                            starFeedback: starFeedbackEvent,
                            elapsedText: questTimer.elapsedText,
                            isEmergency: questTimer.isEmergency,
                            theme: theme,
                            onBack: onBack,
                            onPause: pause
                        )
                        .zIndex(3)

                        readingStage
                    }
                    .padding(.vertical, TadaPrimitiveTokens.Spacing.small)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .hiddenFromAccessibility(when: isPaused)

                    TadaEmergencyAtmosphere(
                        theme: theme,
                        isActive: questTimer.isEmergency
                    )

                    if let pendingCompletion =
                        completionFeedbackLifecycle
                        .visibleFeedback(for: session.prompt.id)
                    {
                        completionFeedback(for: pendingCompletion)
                            .transition(.scale(scale: 0.88).combined(with: .opacity))
                            .zIndex(2)
                    }

                    if isPaused {
                        QuestPauseOverlay(
                            theme: theme,
                            onResume: resume,
                            onExit: onBack
                        )
                    }

                    QuestStarFeedbackOverlay(
                        event: starFeedbackEvent,
                        targetSlotFrame: starFeedbackEvent.flatMap {
                            starSlotFrames[$0.targetSlot]
                        },
                        viewportFrame: proxy.frame(in: .global),
                        accent: theme.primary
                    )
                    .zIndex(5)
                }
                .onPreferenceChange(QuestStarSlotFramesPreferenceKey.self) {
                    starSlotFrames = $0
                }
            }
        }
        .onDisappear {
            listeningTask?.cancel()
            completionTask?.cancel()
            feedbackPlaybackTask?.cancel()
            answerPlaybackTask?.cancel()
            hintPlaybackTask?.cancel()
            attemptState.cancelAttempt()
            Task {
                await audioExperienceService.setEmergencyMode(false)
            }
        }
        .task(id: session.prompt.id) {
            resetForCurrentWordIfNeeded()
        }
        .task(id: questTimer.isEmergency) {
            await audioExperienceService.setEmergencyMode(questTimer.isEmergency)
        }
        .onChange(of: scenePhase) { _, phase in
            guard phase == .background else { return }
            cancelListeningForBackground()
        }
        .sensoryFeedback(.success, trigger: successFeedbackTrigger)
    }

    @ViewBuilder
    private var readingStage: some View {
        if verticalSizeClass == .compact {
            HStack(spacing: TadaPrimitiveTokens.Spacing.large) {
                TadaWorldMascot(
                    theme: theme,
                    pose: .encouraging,
                    size: TadaChildScaleTokens.Read.mascotCompact
                )
                wordCard
                    .frame(maxWidth: 510)
                microphoneButton
            }
            .padding(.horizontal, TadaPrimitiveTokens.Spacing.large)
            .frame(maxWidth: 900, maxHeight: .infinity)
            .overlay(alignment: .bottom) {
                feedbackView
                    .offset(y: -2)
            }
        } else {
            VStack(spacing: TadaPrimitiveTokens.Spacing.large) {
                TadaWorldMascot(
                    theme: theme,
                    pose: .encouraging,
                    size: TadaChildScaleTokens.Read.mascotRegular
                )
                wordCard
                    .frame(
                        minWidth: TadaChildScaleTokens.Read.cardRegularMinimumWidth,
                        maxWidth: TadaChildScaleTokens.Read.cardRegularMaximumWidth
                    )
                microphoneButton
                feedbackView
            }
            .frame(
                maxWidth: TadaChildScaleTokens.Read.cardRegularMaximumWidth
                    + (TadaPrimitiveTokens.Spacing.xLarge * 2),
                maxHeight: .infinity
            )
        }
    }

    private var wordCard: some View {
        VStack(spacing: TadaPrimitiveTokens.Spacing.small) {
            HStack(spacing: 16) {
                Text(session.prompt.displayText)
                    .font(
                        .system(
                            size: verticalSizeClass == .compact
                                ? 78
                                : TadaChildScaleTokens.Read.wordRegularSize,
                            weight: .bold,
                            design: .rounded
                        )
                    )
                    .minimumScaleFactor(0.52)
                    .lineLimit(1)
                    .foregroundStyle(readWordColor.color)
                    .accessibilityHidden(true)

            }
            .padding(.horizontal, 20)

            if showsAssistance {
                assistanceControls
                    .transition(.scale(scale: 0.92).combined(with: .opacity))
            }

        }
        .padding(.horizontal, TadaPrimitiveTokens.Spacing.large)
        .padding(.vertical, verticalSizeClass == .compact ? 14 : 20)
        .background(
            TadaReadWordColorPalette.cardSurface.color,
            in: RoundedRectangle(
                cornerRadius: TadaPrimitiveTokens.Radius.large,
                style: .continuous
            )
        )
        .overlay {
            RoundedRectangle(
                cornerRadius: TadaPrimitiveTokens.Radius.large,
                style: .continuous
            )
            .strokeBorder(Color.white.opacity(0.78), lineWidth: 2)
        }
        .overlay(alignment: .bottom) {
            HStack(spacing: 5) {
                ForEach(0..<7, id: \.self) { index in
                    Capsule()
                        .fill(theme.primary.opacity(0.62))
                        .frame(width: 14, height: CGFloat(4 + (index % 3) * 3))
                }
            }
            .offset(y: 4)
        }
        .shadow(color: theme.primary.opacity(0.18), radius: 18, y: 9)
        .animation(
            reduceMotion ? nil : .spring(response: 0.28, dampingFraction: 0.78),
            value: showsAssistance
        )
    }

    private var readWordColor: TadaReadWordColorToken {
        ReadWordColorPolicy.token(worldID: theme.id)
    }

    private var showsAssistance: Bool {
        ReadAssistancePolicy.shouldReveal(
            validIncorrectAttemptCount: validIncorrectAttemptCount,
            isComplete: attemptState.completedSummary != nil
        )
    }

    private var validIncorrectAttemptCount: Int {
        attemptState.records.filter { record in
            record.outcome == .incorrect
                && record.evidence != .recognitionUncertain
                && record.evidence != .helped
                && record.evidence != .studyExposed
        }.count
    }

    private var assistanceControls: some View {
        assistanceButton(
            title: isPlayingPronunciationHint ? "Playing…" : "Hear it",
            symbol: isPlayingPronunciationHint
                ? "speaker.wave.3.fill"
                : "speaker.wave.2.fill",
            isDisabled: isPlayingPronunciationHint,
            action: playPronunciationHint
        )
        .accessibilityLabel("Hear the word after two tries")
    }

    private func assistanceButton(
        title: String,
        symbol: String,
        isDisabled: Bool,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Label(title, systemImage: symbol)
                .font(.system(.subheadline, design: .rounded, weight: .bold))
                .foregroundStyle(theme.primary)
                .frame(minWidth: 112, minHeight: 44)
                .padding(.horizontal, 10)
                .background(theme.primary.opacity(0.11), in: Capsule())
                .overlay {
                    Capsule()
                        .strokeBorder(theme.primary.opacity(0.22), lineWidth: 1.5)
                }
        }
        .buttonStyle(.plain)
        .disabled(isDisabled || isPaused || isListening)
    }

    private var microphoneButton: some View {
        Button(action: startListening) {
            VStack(spacing: TadaPrimitiveTokens.Spacing.small) {
                ZStack {
                    Circle()
                        .fill(theme.surface.opacity(0.74))
                        .scaleEffect(1.18)
                    Circle()
                        .fill(isListening ? TadaPrimitiveTokens.ColorValue.success : theme.primary)
                    Circle()
                        .strokeBorder(Color.white.opacity(0.74), lineWidth: 5)
                        .padding(7)
                    Image(systemName: isListening ? "waveform" : "mic.fill")
                        .font(.system(size: 46, weight: .bold))
                        .foregroundStyle(Color.white)
                        .symbolEffect(.variableColor.iterative, isActive: isListening)
                }
                .frame(
                    width: verticalSizeClass == .compact ? 96 : 112,
                    height: verticalSizeClass == .compact ? 96 : 112
                )
                .shadow(color: theme.primary.opacity(0.24), radius: 16, y: 8)

                if let microphoneStatusTitle {
                    Text(microphoneStatusTitle)
                        .font(.system(.headline, design: .rounded, weight: .bold))
                        .foregroundStyle(theme.ink)
                }

                #if DEBUG
                    if showsSimulatedVoiceCheck {
                        Label("Simulated voice check", systemImage: "wrench.and.screwdriver.fill")
                            .font(.system(.caption2, design: .rounded, weight: .bold))
                            .foregroundStyle(theme.ink.opacity(0.62))
                            .accessibilityLabel("Demo mode. Simulated voice check.")
                    }
                #endif
            }
        }
        .buttonStyle(.plain)
        .disabled(
            isListening || isCheckingPermission || isPaused
                || attemptState.completedSummary != nil
        )
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(microphoneAccessibilityLabel)
        .accessibilityHint("Read the word shown on screen")
    }

    private var microphoneAccessibilityLabel: String {
        if isCheckingPermission {
            return "Checking microphone permission"
        }
        let action = isListening ? "Listening" : "Start listening"
        #if DEBUG
            if showsSimulatedVoiceCheck {
                return "\(action). Demo mode. Simulated voice check."
            }
        #endif
        return action
    }

    private var microphoneStatusTitle: String? {
        KidReadMicrophonePresentation.visibleStatus(
            isCheckingPermission: isCheckingPermission,
            isListening: isListening
        )
    }

    @ViewBuilder
    private var feedbackView: some View {
        if let feedback = currentFeedback {
            HStack(spacing: TadaPrimitiveTokens.Spacing.small) {
                TadaWorldMascot(
                    theme: theme,
                    pose: feedback.kind == .technical ? .encouraging : .cheering,
                    size: verticalSizeClass == .compact ? 42 : 50
                )

                VStack(spacing: TadaPrimitiveTokens.Spacing.small) {
                    Label(feedback.message, systemImage: feedback.symbol)
                        .font(.system(.subheadline, design: .rounded, weight: .semibold))
                        .multilineTextAlignment(.center)
                        .foregroundStyle(theme.ink.opacity(0.76))

                    if feedback.showsParentGuidance && didCheckPermission {
                        Text(ChildSpeechPermissionCopy.parentSetupHint)
                            .font(.system(.caption, design: .rounded, weight: .medium))
                            .multilineTextAlignment(.center)
                            .foregroundStyle(theme.ink.opacity(0.66))
                    }

                    if attemptState.canSkipAfterTechnicalIssues {
                        Button("Move On", action: moveOnAfterTechnicalIssues)
                            .buttonStyle(
                                TadaPrimaryButtonStyle(
                                    fill: theme.primary,
                                    isCompact: true
                                )
                            )
                            .accessibilityHint(
                                "Moves to the next word without counting this as wrong"
                            )
                    }
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 7)
            .background(theme.surface.opacity(0.90), in: Capsule())
            .frame(maxWidth: 430)
            .transition(.scale(scale: 0.92).combined(with: .opacity))
        }
    }

    private var currentFeedback: ReadFeedback? {
        if permissionWasDenied {
            return technicalFeedback(for: .permissionDenied)
        }

        guard case .feedback(let feedback) = attemptState.phase else { return nil }
        switch feedback {
        case .tryAgain(let remainingAttempts):
            return ReadFeedback(
                message: retryMessage(remainingAttempts: remainingAttempts),
                symbol: "arrow.clockwise.circle.fill",
                kind: .tryAgain
            )
        case .recognitionUncertain:
            return ReadFeedback(
                message: "I’m not sure I heard that. Please try again.",
                symbol: "ear.badge.questionmark",
                kind: .technical
            )
        case .technicalRetry(let reason):
            return technicalFeedback(for: reason)
        }
    }

    private func startListening() {
        guard
            !isListening,
            !isCheckingPermission,
            !isPaused,
            attemptState.completedSummary == nil
        else {
            return
        }

        let shouldResetResponseClock =
            ReadPermissionCheckTimingPolicy.shouldResetResponseClock(
                hasCheckedPermission: didCheckPermission,
                wasPreviouslyDenied: permissionWasDenied
            )
        permissionWasDenied = false
        isCheckingPermission = true
        questTimer.suspend(for: .speechRecognition)
        listeningTask?.cancel()
        listeningTask = Task { @MainActor in
            let isAuthorized = await permissionActions.authorizeMicrophoneTap()
            didCheckPermission = true
            isCheckingPermission = false
            guard !Task.isCancelled, !isPaused else {
                if !isPaused {
                    questTimer.resume(from: .speechRecognition)
                }
                return
            }
            guard isAuthorized else {
                permissionWasDenied = true
                questTimer.resume(from: .speechRecognition)
                responseClock.reset(at: questTimer.elapsedSeconds)
                announceForAccessibility(ChildSpeechPermissionCopy.blockedMessage)
                return
            }

            if shouldResetResponseClock {
                responseClock.reset(at: questTimer.elapsedSeconds)
            }
            await listenForWord()
        }
    }

    @MainActor
    private func listenForWord() async {
        guard attemptState.beginAttempt() else { return }
        let responseLatency = ElapsedTime(
            seconds: responseClock.elapsed(at: questTimer.elapsedSeconds)
        )
        pendingAttemptTiming = AttemptTiming(
            totalResponseTime: responseLatency,
            speechOnsetLatency: responseLatency
        )
        questTimer.suspend(for: .speechRecognition)
        withAnimation(.easeOut(duration: TadaPrimitiveTokens.Motion.quick)) {
            isListening = true
        }

        await audioExperienceService.prepareForRecording()
        let request = SpeechRecognitionRequest(
            profileID: session.profileID,
            prompt: session.prompt,
            maximumRecordingDuration: ElapsedTime(seconds: 5),
            speakerFilterPolicy: .useWhenAvailable,
            noiseSuppressionEnabled: true
        )

        do {
            let result = try await recognitionService.recognize(request)
            await audioExperienceService.finishRecording()
            guard !Task.isCancelled, !isPaused else {
                attemptState.cancelAttempt()
                isListening = false
                questTimer.resume(from: .speechRecognition)
                return
            }
            receive(result)
        } catch is CancellationError {
            await audioExperienceService.finishRecording()
            attemptState.cancelAttempt()
            isListening = false
            if !isPaused {
                questTimer.resume(from: .speechRecognition)
            }
        } catch {
            await audioExperienceService.finishRecording()
            receive(
                RecognitionResult(
                    decision: .technicalFailure(.serviceUnavailable)
                )
            )
        }
    }

    private func receive(_ result: RecognitionResult) {
        guard case .evaluating = attemptState.phase else { return }
        isListening = false
        attemptState.receive(
            result,
            timing: pendingAttemptTiming,
            replayCount: replayCountSinceLastAttempt
        )
        presentStarFeedback(for: result.decision)
        let feedbackPlayback = playFeedback(for: result.decision)
        replayCountSinceLastAttempt = 0
        if let message = currentFeedback?.message {
            announceForAccessibility(message)
        }
        if let summary = attemptState.completedSummary {
            playPronunciationThenComplete(
                summary,
                after: feedbackPlayback
            )
        } else {
            // Every retry starts a fresh response-time window. Recognition,
            // permission, and prior speaking time must not leak into the next
            // valid attempt.
            responseClock.reset(at: questTimer.elapsedSeconds)
            pendingAttemptTiming = .unmeasured
        }
        if !isPaused {
            questTimer.resume(from: .speechRecognition)
        }
    }

    private func presentStarFeedback(for decision: RecognitionDecision) {
        guard
            let kind = QuestAttemptFeedbackPolicy.presentation(
                for: decision
            ).kind
        else { return }
        starFeedbackEvent = QuestStarFeedbackEvent(
            kind: kind,
            targetSlot: min(session.earnedItemCount, session.totalItems - 1)
        )
    }

    private func playFeedback(
        for decision: RecognitionDecision
    ) -> Task<Void, Never> {
        let cue = QuestAttemptFeedbackPolicy.presentation(for: decision).cue
        feedbackPlaybackTask?.cancel()
        let task = Task {
            await audioExperienceService.play(cue)
        }
        feedbackPlaybackTask = task
        return task
    }

    private func playPronunciationThenComplete(
        _ summary: QuestAttemptSummary,
        after feedbackPlayback: Task<Void, Never>
    ) {
        questTimer.suspend(for: .promptPlayback)
        answerPlaybackTask?.cancel()
        answerPlaybackTask = Task { @MainActor in
            await feedbackPlayback.value
            guard !Task.isCancelled else { return }
            await onSpeak()
            guard !Task.isCancelled else { return }
            questTimer.resume(from: .promptPlayback)
            showCompletion(summary, after: feedbackPlayback)
        }
    }

    private func playPronunciationHint() {
        guard showsAssistance, !isPlayingPronunciationHint else { return }
        attemptState.useGuidance()
        replayCountSinceLastAttempt += 1
        isPlayingPronunciationHint = true
        questTimer.suspend(for: .promptPlayback)
        hintPlaybackTask?.cancel()
        hintPlaybackTask = Task { @MainActor in
            await onSpeak()
            guard !Task.isCancelled else { return }
            isPlayingPronunciationHint = false
            if !isPaused {
                questTimer.resume(from: .promptPlayback)
            }
        }
    }

    private func moveOnAfterTechnicalIssues() {
        guard attemptState.skipAfterTechnicalIssues() else { return }
        guard let summary = attemptState.completedSummary else { return }
        showCompletion(summary)
    }

    private func retryMessage(remainingAttempts: Int) -> String {
        if remainingAttempts == 1 {
            return "Nice try. One more try."
        }
        return "Nice try. You have \(remainingAttempts) more tries."
    }

    private func technicalFeedback(for reason: TechnicalFailureReason) -> ReadFeedback {
        switch reason {
        case .permissionDenied:
            return ReadFeedback(
                message: ChildSpeechPermissionCopy.blockedMessage,
                symbol: "mic.slash.fill",
                kind: .technical,
                showsParentGuidance: true
            )
        case .noUsableAudio:
            return ReadFeedback(
                message: "I couldn’t hear a clear voice. Try once more.",
                symbol: "waveform.slash",
                kind: .technical
            )
        case .wrongSpeaker:
            return ReadFeedback(
                message: "I couldn’t tell whose voice that was. Try once more.",
                symbol: "person.wave.2.fill",
                kind: .technical
            )
        case .onDeviceRecognitionUnavailable:
            return ReadFeedback(
                message: onDeviceRecognitionUnavailableMessage,
                symbol: "iphone.and.arrow.forward",
                kind: .technical
            )
        case .serviceUnavailable:
            return ReadFeedback(
                message: "Listening is taking a short break. Try again.",
                symbol: "ear.badge.exclamationmark",
                kind: .technical
            )
        case .timedOut:
            return ReadFeedback(
                message: "I didn’t hear the word in time. Try again.",
                symbol: "timer",
                kind: .technical
            )
        case .corruptedInput:
            return ReadFeedback(
                message: "That recording didn’t come through. Try again.",
                symbol: "waveform.badge.exclamationmark",
                kind: .technical
            )
        }
    }

    private var onDeviceRecognitionUnavailableMessage: String {
        #if targetEnvironment(simulator)
            "Real voice checking needs a physical iPhone or iPad."
        #else
            "Private voice checking isn’t available on this device."
        #endif
    }

    private func showCompletion(
        _ summary: QuestAttemptSummary,
        after feedbackPlayback: Task<Void, Never>? = nil
    ) {
        let completedItemID = session.prompt.id
        let announcement =
            summary.completion == .needsPractice
            ? "We’ll practice this one again."
            : "You got it!"
        var didPresent = false
        withAnimation(
            .spring(
                response: reduceMotion ? 0.01 : TadaPrimitiveTokens.Motion.reaction,
                dampingFraction: 0.70
            )
        ) {
            didPresent = completionFeedbackLifecycle.present(
                summary,
                for: completedItemID
            )
        }
        guard didPresent else { return }
        announceForAccessibility(announcement)
        completionTask?.cancel()
        completionTask = Task { @MainActor in
            do {
                try await QuestAdvanceTimingPolicy.waitBeforeAdvance(
                    minimumFeedbackVisibility: .milliseconds(
                        reduceMotion ? 40 : 780
                    ),
                    feedbackPlayback: feedbackPlayback,
                    hasNextItem: session.currentItem < session.totalItems
                )
            } catch {
                return
            }
            guard completionFeedbackLifecycle.requestAdvance(for: completedItemID)
            else { return }
            onComplete(summary)
        }
    }

    private func completionFeedback(for summary: QuestAttemptSummary) -> some View {
        let isSuccess = summary.completion != .needsPractice
        return TadaFeedbackBurst(
            theme: theme,
            kind: isSuccess ? .success : .tryAgain,
            message: isSuccess ? "You got it!" : "We’ll practice this one again."
        )
    }

    private var successFeedbackTrigger: Bool {
        guard
            let pendingCompletion =
                completionFeedbackLifecycle
                .visibleFeedback(for: session.prompt.id)
        else { return false }
        return pendingCompletion.completion != .needsPractice
    }

    /// Clears word-scoped state while preserving the quest shell's identity.
    /// The previous word's feedback must never cover or disable the next word
    /// when SwiftUI coalesces the model's short saving route.
    private func resetForCurrentWordIfNeeded() {
        guard completionFeedbackLifecycle.transition(to: session.prompt.id) else {
            return
        }

        listeningTask?.cancel()
        completionTask?.cancel()
        feedbackPlaybackTask?.cancel()
        answerPlaybackTask?.cancel()
        hintPlaybackTask?.cancel()
        listeningTask = nil
        completionTask = nil
        feedbackPlaybackTask = nil
        answerPlaybackTask = nil
        hintPlaybackTask = nil
        starFeedbackEvent = nil

        attemptState = QuestAttemptStateMachine(
            policy: .read,
            incorrectAttemptLimit: session.incorrectAttemptLimit
        )
        isListening = false
        isPaused = false
        isCheckingPermission = false
        pendingAttemptTiming = .unmeasured
        replayCountSinceLastAttempt = 0
        isPlayingPronunciationHint = false
        responseClock.reset(at: questTimer.elapsedSeconds)
        questTimer.resume(from: .speechRecognition)
        questTimer.resume(from: .promptPlayback)
    }

    private func pause() {
        listeningTask?.cancel()
        hintPlaybackTask?.cancel()
        attemptState.cancelAttempt()
        isListening = false
        isCheckingPermission = false
        isPlayingPronunciationHint = false
        questTimer.suspend(for: .userPause)
        questTimer.resume(from: .speechRecognition)
        questTimer.resume(from: .promptPlayback)
        isPaused = true
    }

    private func cancelListeningForBackground() {
        listeningTask?.cancel()
        attemptState.cancelAttempt()
        isListening = false
        isCheckingPermission = false
        questTimer.resume(from: .speechRecognition)
    }

    private func resume() {
        isPaused = false
        questTimer.resume(from: .userPause)
    }
}

private struct ReadFeedback {
    let message: String
    let symbol: String
    var kind: TadaFeedbackKind = .tryAgain
    var showsParentGuidance = false
}
