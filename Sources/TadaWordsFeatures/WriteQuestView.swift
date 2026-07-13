import SwiftUI
import TadaWordsDesignSystem
import TadaWordsDomain

enum WriteQuestSideRail: Equatable {
    case prompt
    case actions
}

struct WriteQuestSideRailLayout: Equatable {
    let leading: WriteQuestSideRail
    let trailing: WriteQuestSideRail
}

enum WriteQuestControlLayoutPolicy {
    static func sideRails(
        leftHandedLayoutEnabled: Bool
    ) -> WriteQuestSideRailLayout {
        if leftHandedLayoutEnabled {
            WriteQuestSideRailLayout(leading: .actions, trailing: .prompt)
        } else {
            WriteQuestSideRailLayout(leading: .prompt, trailing: .actions)
        }
    }
}

struct WriteQuestView: View {
    let session: QuestSession
    let theme: TadaWorldTheme
    let recognitionService: any HandwritingRecognitionService
    let audioExperienceService: any AudioExperienceService
    let onSpeak: () async -> Void
    let onBack: () -> Void
    let onComplete: (QuestAttemptSummary) -> Void

    @ObservedObject private var questTimer: QuestTimerModel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var attemptState: QuestAttemptStateMachine
    @State private var strokes: [InkStroke] = []
    @State private var isPaused = false
    @State private var isChecking = false
    @State private var showClearConfirmation = false
    @State private var showHelp = false
    @State private var showGuidedWord = false
    @State private var isPlayingPrompt = false
    @State private var didPlayInitialPrompt = false
    @State private var promptPlaybackTask: Task<Void, Never>?
    @State private var recognitionTask: Task<Void, Never>?
    @State private var completionTask: Task<Void, Never>?
    @State private var pendingCompletion: QuestAttemptSummary?
    @State private var replayCountSinceLastAttempt = 0
    @State private var promptPauseSeconds: TimeInterval = 0
    @State private var responseClock: AttemptResponseClock
    @State private var pendingAttemptTiming = AttemptTiming.unmeasured

    init(
        session: QuestSession,
        questTimer: QuestTimerModel,
        theme: TadaWorldTheme,
        recognitionService: any HandwritingRecognitionService,
        audioExperienceService: any AudioExperienceService =
            SilentAudioExperienceService(),
        onSpeak: @escaping () async -> Void,
        onBack: @escaping () -> Void,
        onComplete: @escaping (QuestAttemptSummary) -> Void
    ) {
        self.session = session
        self.theme = theme
        self.recognitionService = recognitionService
        self.audioExperienceService = audioExperienceService
        self.onSpeak = onSpeak
        self.onBack = onBack
        self.onComplete = onComplete
        _questTimer = ObservedObject(
            wrappedValue: questTimer
        )
        _attemptState = State(
            initialValue: QuestAttemptStateMachine(policy: .write)
        )
        _responseClock = State(
            initialValue: AttemptResponseClock(
                startingAt: questTimer.elapsedSeconds
            )
        )
    }

    var body: some View {
        TadaWorldBackground(theme: theme, sceneStyle: .quest) {
            ZStack {
                VStack(spacing: TadaPrimitiveTokens.Spacing.small) {
                    QuestChrome(
                        mode: .write,
                        currentItem: session.currentItem,
                        totalItems: session.totalItems,
                        elapsedText: questTimer.elapsedText,
                        isEmergency: questTimer.isEmergency,
                        theme: theme,
                        onBack: onBack,
                        onPause: pause
                    )

                    GeometryReader { proxy in
                        writingLayout(isCompact: proxy.size.width < 760)
                            .padding(.horizontal, proxy.size.width < 760 ? 10 : 24)
                            .padding(.bottom, 10)
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .hiddenFromAccessibility(when: isPaused)

                TadaEmergencyAtmosphere(theme: theme, isActive: questTimer.isEmergency)

                if let pendingCompletion {
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
            }
        }
        .task {
            guard !didPlayInitialPrompt else { return }
            didPlayInitialPrompt = true
            let isNewWordStudy = session.source == .new
            if isNewWordStudy {
                attemptState.markStudyExposure()
                showGuidedWord = true
            }
            playPrompt(
                countsAsReplay: false,
                hidesStudyWordAfterPlayback: isNewWordStudy
            )
        }
        .onDisappear {
            promptPlaybackTask?.cancel()
            recognitionTask?.cancel()
            completionTask?.cancel()
            attemptState.cancelAttempt()
            Task {
                await audioExperienceService.setEmergencyMode(false)
            }
        }
        .task(id: questTimer.isEmergency) {
            await audioExperienceService.setEmergencyMode(questTimer.isEmergency)
        }
        .alert("Clear your writing?", isPresented: $showClearConfirmation) {
            Button("Keep it", role: .cancel) {}
            Button("Clear", role: .destructive) {
                strokes.removeAll()
            }
        } message: {
            Text("This removes every stroke from the writing area.")
        }
        .alert("Need a little help?", isPresented: $showHelp) {
            Button("Hear the word") {
                playPrompt()
            }
            Button("Show me", action: showWordHelp)
            Button("Keep writing", role: .cancel) {}
        } message: {
            Text("Listening again is free. Showing the word makes this a guided try.")
        }
        .sensoryFeedback(.success, trigger: successFeedbackTrigger)
    }

    private func writingLayout(isCompact: Bool) -> some View {
        let layout = WriteQuestControlLayoutPolicy.sideRails(
            leftHandedLayoutEnabled: session.interfacePreferences
                .leftHandedLayoutEnabled
        )
        return HStack(alignment: .center, spacing: isCompact ? 10 : 22) {
            sideRail(layout.leading, isCompact: isCompact)

            writingBoard
                .frame(maxWidth: .infinity, maxHeight: .infinity)

            sideRail(layout.trailing, isCompact: isCompact)
        }
    }

    @ViewBuilder
    private func sideRail(
        _ rail: WriteQuestSideRail,
        isCompact: Bool
    ) -> some View {
        Group {
            switch rail {
            case .prompt:
                promptRail(isCompact: isCompact)
            case .actions:
                actionRail(isCompact: isCompact)
            }
        }
        .frame(
            width: isCompact
                ? TadaLayoutTokens.compactActionRailWidth
                : TadaLayoutTokens.standardActionRailWidth
        )
    }

    private func promptRail(isCompact: Bool) -> some View {
        VStack(spacing: isCompact ? 10 : TadaPrimitiveTokens.Spacing.medium) {
            Button {
                playPrompt()
            } label: {
                VStack(spacing: 8) {
                    Image(
                        systemName: isPlayingPrompt ? "speaker.wave.3.fill" : "speaker.wave.2.fill"
                    )
                    .font(.system(size: isCompact ? 28 : 38, weight: .bold))
                    .symbolEffect(.variableColor.iterative, isActive: isPlayingPrompt)
                    Text("Hear")
                        .font(.system(.headline, design: .rounded, weight: .bold))
                }
                .frame(maxWidth: .infinity, minHeight: isCompact ? 76 : 96)
            }
            .buttonStyle(TadaPrimaryButtonStyle(fill: theme.primary, isCompact: true))
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Hear the word")
            .accessibilityHint("Plays the writing prompt again")

            Button {
                showHelp = true
            } label: {
                Label("Help", systemImage: "questionmark.circle.fill")
                    .font(.system(.subheadline, design: .rounded, weight: .bold))
                    .frame(maxWidth: .infinity, minHeight: 44)
            }
            .buttonStyle(.plain)
            .foregroundStyle(theme.primary)
            .background(
                theme.surface.opacity(0.80),
                in: RoundedRectangle(
                    cornerRadius: TadaPrimitiveTokens.Radius.small,
                    style: .continuous
                )
            )
            .disabled(isChecking)
        }
    }

    private var writingBoard: some View {
        VStack(spacing: 9) {
            HStack(spacing: TadaPrimitiveTokens.Spacing.small) {
                TadaWorldMascot(theme: theme, pose: .encouraging, size: 42)
                Label("Write the word you hear", systemImage: "pencil.line")
                    .font(.system(.headline, design: .rounded, weight: .bold))
                    .foregroundStyle(theme.primary)
            }

            if showGuidedWord {
                Text(session.prompt.displayText)
                    .font(.system(.title2, design: .rounded, weight: .bold))
                    .foregroundStyle(theme.primary)
                    .accessibilityLabel("Example spelling: \(session.prompt.displayText)")
            }

            HandwritingCanvasView(
                strokes: $strokes,
                inkColor: theme.ink,
                guideColor: theme.primary.opacity(0.34),
                elapsedSincePrompt: activeElapsedIncludingPromptPlayback
            )
            .allowsHitTesting(!isPlayingPrompt && !isChecking)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(
                Color.white.opacity(0.90),
                in: RoundedRectangle(
                    cornerRadius: TadaPrimitiveTokens.Radius.medium,
                    style: .continuous
                )
            )
            .overlay {
                RoundedRectangle(
                    cornerRadius: TadaPrimitiveTokens.Radius.medium,
                    style: .continuous
                )
                .strokeBorder(theme.primary.opacity(0.20), lineWidth: 1.5)
            }
            .overlay(alignment: .bottom) {
                Capsule()
                    .fill(theme.secondary.opacity(0.38))
                    .frame(height: TadaPrimitiveTokens.Depth.tactileLip)
                    .padding(.horizontal, TadaPrimitiveTokens.Spacing.large)
                    .offset(y: TadaPrimitiveTokens.Depth.tactileLip * 0.45)
            }
            .shadow(color: theme.ink.opacity(0.10), radius: 10, y: 5)

            letterSlots

            feedbackView
        }
    }

    private var letterSlots: some View {
        HStack(spacing: 8) {
            ForEach(Array(session.prompt.normalizedText.indices), id: \.self) { _ in
                Capsule()
                    .fill(theme.ink.opacity(0.30))
                    .frame(maxWidth: 54, minHeight: 4, maxHeight: 4)
            }
        }
        .frame(height: 10)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(session.prompt.normalizedText.count) letter spaces")
    }

    private func actionRail(isCompact: Bool) -> some View {
        let actionsAreDisabled = strokes.isEmpty || isChecking
        return VStack(spacing: isCompact ? 9 : 12) {
            Button(action: submit) {
                VStack(spacing: 5) {
                    Image(systemName: isChecking ? "hourglass" : "checkmark")
                        .font(.system(size: isCompact ? 25 : 34, weight: .heavy))
                    Text(isChecking ? "Checking" : "Done")
                        .font(.system(.headline, design: .rounded, weight: .bold))
                }
                .frame(maxWidth: .infinity, minHeight: isCompact ? 72 : 94)
            }
            .buttonStyle(
                TadaPrimaryButtonStyle(
                    fill: TadaPrimitiveTokens.ColorValue.success, isCompact: true)
            )
            .disabled(
                strokes.isEmpty || isChecking || isPlayingPrompt
                    || attemptState.completedSummary != nil
            )
            .accessibilityHint("Checks the whole handwritten word")

            Button(action: undoLastStroke) {
                Label("Undo", systemImage: "arrow.uturn.backward")
                    .font(.system(.subheadline, design: .rounded, weight: .bold))
                    .frame(maxWidth: .infinity, minHeight: 44)
            }
            .buttonStyle(.plain)
            .tadaDisabledControl(actionsAreDisabled, theme: theme)
            .disabled(strokes.isEmpty || isChecking)

            Button {
                showClearConfirmation = true
            } label: {
                Label("Clear", systemImage: "trash")
                    .font(.system(.subheadline, design: .rounded, weight: .semibold))
                    .frame(
                        maxWidth: .infinity,
                        minHeight: TadaPrimitiveTokens.TouchTarget.minimum
                    )
            }
            .buttonStyle(.plain)
            .tadaDisabledControl(actionsAreDisabled, theme: theme)
            .disabled(strokes.isEmpty || isChecking)
            .accessibilityHint("Asks before removing all strokes")
        }
    }

    @ViewBuilder
    private var feedbackView: some View {
        if let feedback = currentFeedback {
            HStack(spacing: TadaPrimitiveTokens.Spacing.small) {
                TadaWorldMascot(
                    theme: theme,
                    pose: feedback.kind == .technical ? .encouraging : .cheering,
                    size: 38
                )
                Label(feedback.message, systemImage: feedback.symbol)
                    .font(.system(.caption, design: .rounded, weight: .semibold))
                    .multilineTextAlignment(.center)
                    .foregroundStyle(theme.ink.opacity(0.72))

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
            .padding(.horizontal, 12)
            .padding(.vertical, 5)
            .background(theme.surface.opacity(0.92), in: Capsule())
            .frame(maxWidth: 480)
            .transition(.scale(scale: 0.92).combined(with: .opacity))
        }
    }

    private var currentFeedback: WriteFeedback? {
        guard case .feedback(let feedback) = attemptState.phase else { return nil }
        switch feedback {
        case .tryAgain(let remainingAttempts):
            return WriteFeedback(
                message: retryMessage(remainingAttempts: remainingAttempts),
                symbol: "pencil.and.scribble",
                kind: .tryAgain
            )
        case .rewriteAfterAnswer:
            return WriteFeedback(
                message: "Look, then write it one more time.",
                symbol: "textformat.abc",
                kind: .tryAgain
            )
        case .recognitionUncertain:
            return WriteFeedback(
                message: "I’m not sure about that writing. You can try again.",
                symbol: "questionmark.circle.fill",
                kind: .technical
            )
        case .technicalRetry(let reason):
            return WriteFeedback(
                message: technicalMessage(for: reason),
                symbol: "exclamationmark.arrow.triangle.2.circlepath",
                kind: .technical
            )
        }
    }

    private func undoLastStroke() {
        guard !strokes.isEmpty else { return }
        strokes.removeLast()
    }

    private func playPrompt(
        countsAsReplay: Bool = true,
        hidesStudyWordAfterPlayback: Bool = false
    ) {
        guard !isPlayingPrompt else { return }
        questTimer.suspend(for: .promptPlayback)
        isPlayingPrompt = true
        if countsAsReplay {
            replayCountSinceLastAttempt += 1
        }
        let playbackStartedAt = ProcessInfo.processInfo.systemUptime

        promptPlaybackTask?.cancel()
        promptPlaybackTask = Task { @MainActor in
            await onSpeak()
            guard !Task.isCancelled else { return }
            promptPauseSeconds += max(
                0,
                ProcessInfo.processInfo.systemUptime - playbackStartedAt
            )
            if hidesStudyWordAfterPlayback {
                try? await Task.sleep(for: .milliseconds(reduceMotion ? 80 : 700))
                guard !Task.isCancelled else { return }
                showGuidedWord = false
            }
            isPlayingPrompt = false
            if !isPaused {
                questTimer.resume(from: .promptPlayback)
            }
        }
    }

    private func pause() {
        promptPlaybackTask?.cancel()
        recognitionTask?.cancel()
        attemptState.cancelAttempt()
        isPlayingPrompt = false
        isChecking = false
        questTimer.suspend(for: .userPause)
        questTimer.resume(from: .promptPlayback)
        questTimer.resume(from: .handwritingRecognition)
        isPaused = true
    }

    private func resume() {
        isPaused = false
        questTimer.resume(from: .userPause)
    }

    private func submit() {
        guard !strokes.isEmpty, attemptState.beginAttempt() else { return }
        Task {
            await audioExperienceService.play(.click)
        }
        isChecking = true
        questTimer.suspend(for: .handwritingRecognition)

        let sample = HandwritingSample(
            strokes: strokes.map { HandwritingStroke(points: $0.points) },
            inputMethod: strokes.contains(where: { $0.inputMethod == .pencil })
                ? .pencil
                : .finger
        )
        pendingAttemptTiming = timing(for: sample)
        recognitionTask?.cancel()
        recognitionTask = Task { @MainActor in
            do {
                let result = try await recognitionService.recognize(
                    sample: sample,
                    prompt: session.prompt,
                    for: session.profileID
                )
                guard !Task.isCancelled, !isPaused else {
                    attemptState.cancelAttempt()
                    isChecking = false
                    return
                }
                receive(result)
            } catch is CancellationError {
                attemptState.cancelAttempt()
                isChecking = false
                if !Task.isCancelled, !isPaused {
                    questTimer.resume(from: .handwritingRecognition)
                }
            } catch {
                receive(
                    RecognitionResult(
                        decision: .technicalFailure(.serviceUnavailable)
                    )
                )
            }
        }
    }

    private func receive(_ result: RecognitionResult) {
        isChecking = false
        playFeedback(for: result.decision)
        let attemptReplayCount = replayCountSinceLastAttempt
        replayCountSinceLastAttempt = 0
        attemptState.receive(
            result,
            timing: pendingAttemptTiming,
            replayCount: attemptReplayCount
        )
        if let message = currentFeedback?.message {
            announceForAccessibility(message)
        }

        if let summary = attemptState.completedSummary {
            if summary.completion == .needsPractice,
                summary.records.contains(where: {
                    $0.outcome == .incorrect || $0.outcome == .recognitionUncertain
                })
            {
                showGuidedWord = true
            }
            showCompletion(summary)
        } else {
            if case .feedback(.rewriteAfterAnswer) = attemptState.phase {
                showGuidedWord = true
                strokes.removeAll()
                resetWritingAttemptClock()
            }
            if !isPaused {
                questTimer.resume(from: .handwritingRecognition)
            }
        }
    }

    private func playFeedback(for decision: RecognitionDecision) {
        let cue: FunctionalAudioCue
        switch decision {
        case .matched:
            cue = .correct
        case .notMatched:
            cue = .validRetry
        case .uncertain, .technicalFailure:
            cue = .technicalRetry
        }
        Task {
            await audioExperienceService.play(cue)
        }
    }

    private func moveOnAfterTechnicalIssues() {
        guard attemptState.skipAfterTechnicalIssues() else { return }
        guard let summary = attemptState.completedSummary else { return }
        showCompletion(summary)
    }

    private func timing(for sample: HandwritingSample) -> AttemptTiming {
        WriteAttemptTimingCalculator().timing(
            for: sample,
            promptPlaybackSeconds: promptPauseSeconds
        )
    }

    private func activeElapsedIncludingPromptPlayback() -> TimeInterval {
        responseClock.elapsed(at: questTimer.elapsedSeconds)
            + promptPauseSeconds
    }

    private func showWordHelp() {
        attemptState.useGuidance()
        showGuidedWord = true
        strokes.removeAll()
        resetWritingAttemptClock()
    }

    private func resetWritingAttemptClock() {
        responseClock.reset(at: questTimer.elapsedSeconds)
        promptPauseSeconds = 0
        pendingAttemptTiming = .unmeasured
    }

    private func showCompletion(_ summary: QuestAttemptSummary) {
        let announcement =
            summary.completion == .needsPractice
            ? "We’ll practice this one again."
            : "You got it!"
        announceForAccessibility(announcement)
        withAnimation(
            .spring(
                response: reduceMotion ? 0.01 : TadaPrimitiveTokens.Motion.reaction,
                dampingFraction: 0.70
            )
        ) {
            pendingCompletion = summary
        }
        completionTask?.cancel()
        completionTask = Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(reduceMotion ? 40 : 430))
            guard !Task.isCancelled else { return }
            onComplete(summary)
        }
    }

    private func completionFeedback(for summary: QuestAttemptSummary) -> some View {
        let isSuccess = summary.completion != .needsPractice
        return TadaFeedbackBurst(
            theme: theme,
            kind: isSuccess ? .success : .tryAgain,
            message: isSuccess
                ? "Beautiful writing!"
                : "It’s \(session.prompt.displayText). We’ll practice it again."
        )
    }

    private var successFeedbackTrigger: Bool {
        guard let pendingCompletion else { return false }
        return pendingCompletion.completion != .needsPractice
    }

    private func retryMessage(remainingAttempts: Int) -> String {
        if remainingAttempts == 1 {
            return "Nice work trying. Clear and write it one more time."
        }
        return "Nice work trying. You have \(remainingAttempts) more tries."
    }

    private func technicalMessage(for reason: TechnicalFailureReason) -> String {
        switch reason {
        case .corruptedInput:
            "That writing didn’t come through. Your progress is safe."
        case .serviceUnavailable:
            "Writing check is taking a short break. Please try again."
        case .timedOut:
            "The writing check took too long. Please try again."
        case .permissionDenied, .noUsableAudio, .wrongSpeaker,
            .onDeviceRecognitionUnavailable:
            "I couldn’t check that writing. Please try again."
        }
    }
}

/// Converts the active-item clock into durable handwriting timing. The point
/// clock already excludes app/user pauses through `QuestTimerModel`, but adds
/// prompt playback so the shared pace extractor can remove it exactly once.
struct WriteAttemptTimingCalculator: Sendable {
    func timing(
        for sample: HandwritingSample,
        promptPlaybackSeconds: TimeInterval
    ) -> AttemptTiming {
        let strokes = sample.strokes.filter { !$0.points.isEmpty }
        let allPoints = strokes.flatMap(\.points)
        guard let firstPoint = allPoints.min(by: elapsedBefore),
            let lastPoint = allPoints.max(by: elapsedBefore)
        else {
            return .unmeasured
        }

        let replayPauseSeconds = max(0, promptPlaybackSeconds)
        let firstStrokeSeconds = max(
            0,
            firstPoint.elapsedSincePrompt.seconds - replayPauseSeconds
        )
        let totalSecondsIncludingPromptPlayback = max(
            firstPoint.elapsedSincePrompt.seconds,
            lastPoint.elapsedSincePrompt.seconds
        )
        let activeResponseSeconds = max(
            firstStrokeSeconds,
            totalSecondsIncludingPromptPlayback - replayPauseSeconds
        )
        let activeStrokeSeconds = strokes.reduce(0) { total, stroke in
            guard let first = stroke.points.min(by: elapsedBefore),
                let last = stroke.points.max(by: elapsedBefore)
            else {
                return total
            }
            return total
                + max(
                    0,
                    last.elapsedSincePrompt.seconds - first.elapsedSincePrompt.seconds
                )
        }
        let idleSeconds = max(
            0,
            activeResponseSeconds - firstStrokeSeconds - activeStrokeSeconds
        )

        return AttemptTiming(
            totalResponseTime: ElapsedTime(
                seconds: totalSecondsIncludingPromptPlayback
            ),
            firstStrokeLatency: ElapsedTime(seconds: firstStrokeSeconds),
            activeStrokeTime: ElapsedTime(seconds: activeStrokeSeconds),
            idleTime: ElapsedTime(seconds: idleSeconds),
            replayPauseTime: ElapsedTime(seconds: replayPauseSeconds)
        )
    }

    private func elapsedBefore(
        _ left: HandwritingPoint,
        _ right: HandwritingPoint
    ) -> Bool {
        left.elapsedSincePrompt < right.elapsedSincePrompt
    }
}

private struct WriteFeedback {
    let message: String
    let symbol: String
    let kind: TadaFeedbackKind
}
