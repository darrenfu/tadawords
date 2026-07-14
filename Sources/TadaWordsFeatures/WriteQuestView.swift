import SwiftUI
import TadaWordsDesignSystem
import TadaWordsDomain

#if os(iOS)
    import UIKit
#elseif os(macOS)
    import AppKit
#endif

enum WriteQuestSideRail: Equatable {
    case prompt
    case actions
}

struct WriteQuestSideRailLayout: Equatable {
    let leading: WriteQuestSideRail
    let trailing: WriteQuestSideRail
}

struct WriteQuestLayoutMetrics: Equatable {
    let railWidth: CGFloat
    let spacing: CGFloat
    let canvasWidth: CGFloat
}

enum WriteQuestControlLayoutPolicy {
    static let canvasWidthScale: CGFloat = 1.10

    static func sideRails(
        leftHandedLayoutEnabled: Bool
    ) -> WriteQuestSideRailLayout {
        if leftHandedLayoutEnabled {
            WriteQuestSideRailLayout(leading: .actions, trailing: .prompt)
        } else {
            WriteQuestSideRailLayout(leading: .prompt, trailing: .actions)
        }
    }

    static func metrics(
        availableWidth: CGFloat,
        isCompact: Bool
    ) -> WriteQuestLayoutMetrics {
        let baseRailWidth =
            isCompact
            ? TadaLayoutTokens.compactActionRailWidth
            : TadaLayoutTokens.standardActionRailWidth
        let spacing: CGFloat = isCompact ? 10 : 22
        let originalCanvasWidth = max(
            1,
            availableWidth - (baseRailWidth * 2) - (spacing * 2)
        )
        let desiredCanvasWidth = originalCanvasWidth * canvasWidthScale
        let minimumRailWidth: CGFloat = isCompact ? 68 : 88
        let maximumCanvasWidth = max(
            1,
            availableWidth - (minimumRailWidth * 2) - (spacing * 2)
        )
        let canvasWidth = min(desiredCanvasWidth, maximumCanvasWidth)
        let railWidth = max(
            minimumRailWidth,
            (availableWidth - canvasWidth - (spacing * 2)) / 2
        )
        return WriteQuestLayoutMetrics(
            railWidth: railWidth,
            spacing: spacing,
            canvasWidth: canvasWidth
        )
    }
}

enum WriteQuestTimingPolicy {
    /// Keeps the transient completion card readable instead of flashing past.
    static let completionFeedbackVisibility: Duration = .milliseconds(830)
}

enum WritePictureHintRequestPolicy {
    static func shouldRequest(
        decision: RecognitionDecision,
        validAttemptCount: Int,
        usedGuidance: Bool
    ) -> Bool {
        decision == .notMatched
            && validAttemptCount == 0
            && !usedGuidance
    }
}

enum WriteQuestInkEditor {
    /// Clears ink synchronously so the canvas responds in the same tap cycle.
    @discardableResult
    static func clear(_ strokes: inout [InkStroke]) -> Bool {
        guard !strokes.isEmpty else { return false }
        strokes.removeAll(keepingCapacity: true)
        return true
    }
}

enum WriteQuestHelpAction {
    /// Applies the one-tap writing hint without introducing a choice sheet.
    /// The caller owns the response-clock reset because it has access to the
    /// quest-scoped timer.
    static func revealWord(
        attemptState: inout QuestAttemptStateMachine,
        strokes: inout [InkStroke]
    ) {
        attemptState.useGuidance()
        strokes.removeAll(keepingCapacity: true)
    }
}

struct WriteQuestView: View {
    let session: QuestSession
    let theme: TadaWorldTheme
    let recognitionService: any HandwritingRecognitionService
    let audioExperienceService: any AudioExperienceService
    let pictureHintProvider: any WordPictureHintProviding
    let handwritingPreferenceStore: HandwritingPreferenceStore
    let onSpeak: () async -> Void
    let onBack: () -> Void
    let onComplete: (QuestAttemptSummary) -> Void

    @ObservedObject private var questTimer: QuestTimerModel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var attemptState: QuestAttemptStateMachine
    @State private var strokes: [InkStroke] = []
    @State private var isPaused = false
    @State private var isChecking = false
    @State private var showGuidedWord = false
    @State private var isPlayingPrompt = false
    @State private var didPlayInitialPrompt = false
    @State private var promptPlaybackTask: Task<Void, Never>?
    @State private var recognitionTask: Task<Void, Never>?
    @State private var pictureHintTask: Task<Void, Never>?
    @State private var completionTask: Task<Void, Never>?
    @State private var completionFeedbackLifecycle:
        QuestItemFeedbackLifecycle<
            WordPromptID,
            QuestAttemptSummary
        >
    @State private var replayCountSinceLastAttempt = 0
    @State private var promptPauseSeconds: TimeInterval = 0
    @State private var responseClock: AttemptResponseClock
    @State private var pendingAttemptTiming = AttemptTiming.unmeasured
    @State private var clearFeedbackTrigger = 0
    @State private var handwritingSelection = HandwritingSelectionState()
    @State private var isShowingToolbox = false
    @State private var pictureHintAsset: WordPictureHintAsset?
    @State private var isShowingPictureHint = false

    init(
        session: QuestSession,
        questTimer: QuestTimerModel,
        theme: TadaWorldTheme,
        recognitionService: any HandwritingRecognitionService,
        audioExperienceService: any AudioExperienceService =
            SilentAudioExperienceService(),
        pictureHintProvider: any WordPictureHintProviding =
            NoWordPictureHintProvider(),
        handwritingPreferenceStore: HandwritingPreferenceStore =
            HandwritingPreferenceStore(),
        onSpeak: @escaping () async -> Void,
        onBack: @escaping () -> Void,
        onComplete: @escaping (QuestAttemptSummary) -> Void
    ) {
        self.session = session
        self.theme = theme
        self.recognitionService = recognitionService
        self.audioExperienceService = audioExperienceService
        self.pictureHintProvider = pictureHintProvider
        self.handwritingPreferenceStore = handwritingPreferenceStore
        self.onSpeak = onSpeak
        self.onBack = onBack
        self.onComplete = onComplete
        _questTimer = ObservedObject(
            wrappedValue: questTimer
        )
        _attemptState = State(
            initialValue: QuestAttemptStateMachine(policy: .write)
        )
        _completionFeedbackLifecycle = State(
            initialValue: QuestItemFeedbackLifecycle(
                itemID: session.prompt.id
            )
        )
        _handwritingSelection = State(
            initialValue: handwritingPreferenceStore.selection(
                for: session.profileID
            )
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
                        let isCompact = proxy.size.width < 760
                        let horizontalPadding: CGFloat = isCompact ? 10 : 24
                        writingLayout(
                            isCompact: isCompact,
                            availableWidth: max(
                                1,
                                proxy.size.width - (horizontalPadding * 2)
                            )
                        )
                        .padding(.horizontal, horizontalPadding)
                        .padding(.bottom, 10)
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .hiddenFromAccessibility(when: isPaused)

                TadaEmergencyAtmosphere(theme: theme, isActive: questTimer.isEmergency)

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
            }
        }
        .task(id: session.prompt.id) {
            resetForCurrentWordIfNeeded()
            guard !didPlayInitialPrompt else { return }
            didPlayInitialPrompt = true
            playPrompt(countsAsReplay: false)
        }
        .onDisappear {
            promptPlaybackTask?.cancel()
            recognitionTask?.cancel()
            pictureHintTask?.cancel()
            completionTask?.cancel()
            attemptState.cancelAttempt()
            questTimer.resume(from: .handwritingRecognition)
            Task {
                await audioExperienceService.setEmergencyMode(false)
            }
        }
        .task(id: questTimer.isEmergency) {
            await audioExperienceService.setEmergencyMode(questTimer.isEmergency)
        }
        .onChange(of: strokes.isEmpty) { _, isEmpty in
            handwritingSelection.reconcileCanvas(hasInk: !isEmpty)
        }
        .onChange(of: handwritingSelection) { _, selection in
            handwritingPreferenceStore.save(
                selection,
                for: session.profileID
            )
        }
        .sensoryFeedback(.success, trigger: successFeedbackTrigger)
        .sensoryFeedback(.impact(weight: .medium), trigger: clearFeedbackTrigger)
    }

    private func writingLayout(
        isCompact: Bool,
        availableWidth: CGFloat
    ) -> some View {
        let layout = WriteQuestControlLayoutPolicy.sideRails(
            leftHandedLayoutEnabled: session.interfacePreferences
                .leftHandedLayoutEnabled
        )
        let metrics = WriteQuestControlLayoutPolicy.metrics(
            availableWidth: availableWidth,
            isCompact: isCompact
        )
        return HStack(alignment: .center, spacing: metrics.spacing) {
            sideRail(
                layout.leading,
                isCompact: isCompact,
                width: metrics.railWidth
            )

            writingBoard
                .frame(width: metrics.canvasWidth)
                .frame(maxHeight: .infinity)

            sideRail(
                layout.trailing,
                isCompact: isCompact,
                width: metrics.railWidth
            )
        }
    }

    @ViewBuilder
    private func sideRail(
        _ rail: WriteQuestSideRail,
        isCompact: Bool,
        width: CGFloat
    ) -> some View {
        Group {
            switch rail {
            case .prompt:
                promptRail(isCompact: isCompact)
            case .actions:
                actionRail(isCompact: isCompact)
            }
        }
        .frame(width: width)
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

            Button(action: showWordHelp) {
                Image(systemName: "questionmark.circle.fill")
                    .font(.system(size: isCompact ? 38 : 44, weight: .bold))
                    .symbolRenderingMode(.palette)
                    .foregroundStyle(theme.surface, theme.primary)
                    .frame(
                        width: TadaPrimitiveTokens.TouchTarget.minimum,
                        height: TadaPrimitiveTokens.TouchTarget.minimum
                    )
                    .contentShape(Circle())
            }
            .buttonStyle(.plain)
            .disabled(
                isChecking || isPlayingPrompt
                    || attemptState.completedSummary != nil
            )
            .accessibilityLabel("Show the word")
            .accessibilityHint("Shows the spelling and makes this a guided try")
        }
    }

    private var writingBoard: some View {
        VStack(spacing: 9) {
            HStack(spacing: TadaPrimitiveTokens.Spacing.small) {
                TadaWorldMascot(theme: theme, pose: .encouraging, size: 42)
                Label("Write the word you hear", systemImage: "pencil.line")
                    .font(.system(.headline, design: .rounded, weight: .bold))
                    .foregroundStyle(theme.primary)

                Spacer(minLength: 4)

                Button {
                    isShowingToolbox.toggle()
                } label: {
                    Image(
                        systemName: HandwritingToolPolicy.symbol(
                            for: handwritingSelection.tool
                        )
                    )
                    .font(.system(size: 23, weight: .bold))
                    .foregroundStyle(theme.primary)
                    .frame(
                        width: TadaPrimitiveTokens.TouchTarget.minimum,
                        height: TadaPrimitiveTokens.TouchTarget.minimum
                    )
                    .background(theme.surface.opacity(0.94), in: Circle())
                    .contentShape(Circle())
                }
                .buttonStyle(.plain)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("Writing tools")
                .accessibilityValue(
                    HandwritingToolPolicy.displayName(for: handwritingSelection.tool)
                )
                .accessibilityHint("Choose a writing tool")
                .popover(isPresented: $isShowingToolbox) {
                    HandwritingToolboxView(
                        selection: $handwritingSelection,
                        accentColor: theme.primary
                    )
                    .presentationCompactAdaptation(.popover)
                }
            }

            ZStack {
                HandwritingCanvasView(
                    strokes: $strokes,
                    selectedTool: handwritingSelection.tool,
                    selectedInk: handwritingSelection.ink,
                    isErasing: handwritingSelection.isErasing,
                    themeInkColor: theme.ink,
                    guideColor: theme.primary.opacity(0.34),
                    elapsedSincePrompt: activeElapsedIncludingPromptPlayback,
                    onWritingSound: playWritingSound,
                    onEraserTappedBlank: restorePenAfterBlankEraserTap
                )
                .allowsHitTesting(!isPlayingPrompt && !isChecking)

                VStack(spacing: 0) {
                    if showGuidedWord {
                        Text(session.prompt.displayText)
                            .font(.system(.title2, design: .rounded, weight: .bold))
                            .foregroundStyle(theme.primary)
                            .padding(.horizontal, 16)
                            .padding(.vertical, 6)
                            .background(theme.surface.opacity(0.94), in: Capsule())
                            .accessibilityLabel(
                                "Example spelling: \(session.prompt.displayText)"
                            )
                    }

                    Spacer(minLength: 0)

                    feedbackView
                        .padding(.bottom, 8)
                }
                .padding(.top, 8)
            }
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

            Button(action: toggleEraser) {
                Label(
                    handwritingSelection.isErasing ? "Erasing" : "Erase",
                    systemImage: handwritingSelection.isErasing
                        ? "eraser.fill" : "eraser"
                )
                .font(.system(.subheadline, design: .rounded, weight: .bold))
                .frame(maxWidth: .infinity, minHeight: 44)
            }
            .buttonStyle(.plain)
            .tadaDisabledControl(actionsAreDisabled, theme: theme)
            .disabled(strokes.isEmpty || isChecking)
            .background(
                handwritingSelection.isErasing
                    ? theme.secondary.opacity(0.34) : Color.clear,
                in: Capsule()
            )
            .accessibilityAddTraits(
                handwritingSelection.isErasing ? .isSelected : []
            )
            .accessibilityHint("Draw over just the marks you want to remove")

            Button(action: clearWriting) {
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
            .accessibilityHint("Removes all strokes immediately")
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

                if pictureHintAsset != nil {
                    pictureHintButton
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
                message: "Try writing it one more time.",
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

    private var pictureHintButton: some View {
        Button {
            isShowingPictureHint = true
        } label: {
            Image(systemName: "photo.circle.fill")
                .font(.system(size: 34, weight: .bold))
                .foregroundStyle(theme.primary)
                .frame(
                    width: TadaPrimitiveTokens.TouchTarget.minimum,
                    height: TadaPrimitiveTokens.TouchTarget.minimum
                )
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Show a picture hint")
        .accessibilityHint("Shows a picture for this word")
        .popover(isPresented: $isShowingPictureHint) {
            if let pictureHintAsset {
                WritePictureHintCard(
                    asset: pictureHintAsset,
                    accentColor: theme.primary
                )
                .presentationCompactAdaptation(.popover)
            }
        }
    }

    private func toggleEraser() {
        guard !strokes.isEmpty, !isChecking else { return }
        handwritingSelection.toggleEraser()
        announceForAccessibility(
            handwritingSelection.isErasing ? "Eraser selected." : "Eraser off."
        )
    }

    private func restorePenAfterBlankEraserTap() {
        guard handwritingSelection.isErasing else { return }
        handwritingSelection.stopErasing()
        announceForAccessibility(
            "\(HandwritingToolPolicy.displayName(for: handwritingSelection.tool)) selected."
        )
    }

    private func clearWriting() {
        guard WriteQuestInkEditor.clear(&strokes) else { return }
        handwritingSelection.reconcileCanvas(hasInk: false)
        clearFeedbackTrigger += 1
        announceForAccessibility("Writing cleared.")
        Task {
            await audioExperienceService.play(.click)
        }
    }

    private func playWritingSound(for tool: HandwritingTool) {
        Task {
            await audioExperienceService.play(.writing(tool: tool))
        }
    }

    private func playPrompt(
        countsAsReplay: Bool = true
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
        let shouldOfferPictureHint = WritePictureHintRequestPolicy.shouldRequest(
            decision: result.decision,
            validAttemptCount: attemptState.validAttemptCount,
            usedGuidance: attemptState.usedGuidance
        )
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
            showCompletion(summary)
        } else {
            if case .feedback(.rewriteAfterAnswer) = attemptState.phase {
                showGuidedWord = false
                if shouldOfferPictureHint {
                    loadPictureHint()
                }
                strokes.removeAll()
                handwritingSelection.stopErasing()
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
        guard !isChecking, !isPlayingPrompt,
            attemptState.completedSummary == nil
        else { return }
        WriteQuestHelpAction.revealWord(
            attemptState: &attemptState,
            strokes: &strokes
        )
        handwritingSelection.stopErasing()
        showGuidedWord = true
        isShowingPictureHint = false
        // The word remains visible while the child writes, so this is active
        // guided-response time. Prompt playback and recognition continue to
        // own their existing named timer suspensions.
        resetWritingAttemptClock()
        announceForAccessibility("The word is \(session.prompt.displayText).")
        Task {
            await audioExperienceService.play(.click)
        }
    }

    private func loadPictureHint() {
        pictureHintTask?.cancel()
        pictureHintTask = Task { @MainActor in
            let asset = await pictureHintProvider.hint(
                for: session.prompt.normalizedText
            )
            guard !Task.isCancelled else { return }
            pictureHintAsset = asset
        }
    }

    private func resetWritingAttemptClock() {
        responseClock.reset(at: questTimer.elapsedSeconds)
        promptPauseSeconds = 0
        pendingAttemptTiming = .unmeasured
    }

    private func showCompletion(_ summary: QuestAttemptSummary) {
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
                try await Task.sleep(
                    for: WriteQuestTimingPolicy.completionFeedbackVisibility
                )
            } catch {
                return
            }
            guard completionFeedbackLifecycle.requestAdvance(for: completedItemID)
            else { return }
            questTimer.resume(from: .handwritingRecognition)
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
                : "We’ll practice this one again."
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

    /// Resets only per-word state. The surrounding quest view keeps its stable
    /// identity so the canvas frame and touch coordinates do not move between
    /// words even when the model's short saving route is coalesced by SwiftUI.
    private func resetForCurrentWordIfNeeded() {
        guard completionFeedbackLifecycle.transition(to: session.prompt.id) else {
            return
        }

        promptPlaybackTask?.cancel()
        recognitionTask?.cancel()
        pictureHintTask?.cancel()
        completionTask?.cancel()
        promptPlaybackTask = nil
        recognitionTask = nil
        pictureHintTask = nil
        completionTask = nil

        attemptState = QuestAttemptStateMachine(policy: .write)
        strokes.removeAll(keepingCapacity: true)
        isPaused = false
        isChecking = false
        showGuidedWord = false
        isPlayingPrompt = false
        didPlayInitialPrompt = false
        replayCountSinceLastAttempt = 0
        promptPauseSeconds = 0
        pendingAttemptTiming = .unmeasured
        responseClock.reset(at: questTimer.elapsedSeconds)
        handwritingSelection.stopErasing()
        isShowingToolbox = false
        pictureHintAsset = nil
        isShowingPictureHint = false
        questTimer.resume(from: .promptPlayback)
        questTimer.resume(from: .handwritingRecognition)
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

private struct WritePictureHintCard: View {
    let asset: WordPictureHintAsset
    let accentColor: Color

    var body: some View {
        VStack(spacing: 10) {
            if let image {
                image
                    .resizable()
                    .scaledToFit()
                    .frame(width: 180, height: 150)
                    .clipShape(
                        RoundedRectangle(cornerRadius: 18, style: .continuous)
                    )
            } else {
                Image(systemName: "photo")
                    .font(.system(size: 54, weight: .bold))
                    .foregroundStyle(accentColor)
                    .frame(width: 180, height: 150)
            }

            Text("Picture hint")
                .font(.system(.headline, design: .rounded, weight: .bold))
                .foregroundStyle(accentColor)

            if !asset.attribution.isEmpty {
                Text(asset.attribution)
                    .font(.system(size: 9, design: .rounded))
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
        }
        .padding(16)
        .background(Color.white)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Picture hint: \(asset.accessibilityLabel)")
    }

    private var image: Image? {
        #if os(iOS)
            guard let platformImage = UIImage(data: asset.imageData) else { return nil }
            return Image(uiImage: platformImage)
        #elseif os(macOS)
            guard let platformImage = NSImage(data: asset.imageData) else { return nil }
            return Image(nsImage: platformImage)
        #else
            return nil
        #endif
    }
}

private struct HandwritingToolboxView: View {
    @Binding var selection: HandwritingSelectionState
    let accentColor: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Pick a pen")
                .font(.system(.headline, design: .rounded, weight: .bold))

            HStack(spacing: 10) {
                ForEach(HandwritingToolPolicy.selectableTools, id: \.self) { tool in
                    toolButton(tool)
                }
            }
        }
        .padding(16)
        .frame(width: 262)
        .background(Color.white)
        .accessibilityElement(children: .contain)
    }

    private func toolButton(_ tool: HandwritingTool) -> some View {
        let isSelected = selection.tool == tool
        let foreground = isSelected ? Color.white : accentColor
        let background = isSelected ? accentColor : accentColor.opacity(0.10)
        let shape = RoundedRectangle(cornerRadius: 13, style: .continuous)

        return Button {
            selection.selectTool(tool)
        } label: {
            VStack(spacing: 4) {
                Image(systemName: HandwritingToolPolicy.symbol(for: tool))
                    .font(.system(size: 22, weight: .bold))
                Text(HandwritingToolPolicy.displayName(for: tool))
                    .font(.system(size: 10, weight: .bold, design: .rounded))
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
            }
            .foregroundStyle(foreground)
            .frame(width: 70, height: 58)
            .background(background, in: shape)
            .contentShape(shape)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(HandwritingToolPolicy.displayName(for: tool))
        .accessibilityValue(isSelected ? "Selected" : "")
        .accessibilityAddTraits(isSelected ? .isSelected : [])
        .accessibilityHint("Uses this pen and turns the eraser off")
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
