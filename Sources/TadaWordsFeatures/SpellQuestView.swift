import Foundation
import SwiftUI
import TadaWordsDesignSystem
import TadaWordsDomain

/// Exact, case-insensitive A-Z spelling comparison. Punctuation and spaces in
/// a prompt are structural hints rather than keys, so a child can spell
/// "can't" with the four available letter keys.
struct SpellingAnswerEvaluator: Sendable {
    func normalizedLetters(in text: String) -> String {
        let folded = text.folding(
            options: [.caseInsensitive, .diacriticInsensitive],
            locale: Locale(identifier: "en_US_POSIX")
        ).lowercased()
        let scalars = folded.unicodeScalars.filter { scalar in
            (97...122).contains(scalar.value)
        }
        return String(String.UnicodeScalarView(scalars))
    }

    func matches(_ response: String, target: String) -> Bool {
        let normalizedTarget = normalizedLetters(in: target)
        return !normalizedTarget.isEmpty
            && normalizedLetters(in: response) == normalizedTarget
    }

    func letterCount(in target: String) -> Int {
        normalizedLetters(in: target).count
    }
}

struct LetterKeyboardInputState: Equatable, Sendable {
    let maximumLetterCount: Int
    private(set) var response = ""

    init(maximumLetterCount: Int, response: String = "") {
        self.maximumLetterCount = max(1, maximumLetterCount)
        self.response = String(
            SpellingAnswerEvaluator()
                .normalizedLetters(in: response)
                .prefix(self.maximumLetterCount)
        )
    }

    var isEmpty: Bool { response.isEmpty }
    var isFull: Bool { response.count >= maximumLetterCount }

    @discardableResult
    mutating func append(_ letter: Character) -> Bool {
        guard !isFull else { return false }
        let normalized = SpellingAnswerEvaluator().normalizedLetters(
            in: String(letter)
        )
        guard normalized.count == 1 else { return false }
        response.append(normalized)
        return true
    }

    @discardableResult
    mutating func removeLast() -> Bool {
        guard !response.isEmpty else { return false }
        response.removeLast()
        return true
    }

    mutating func clear() {
        response.removeAll(keepingCapacity: true)
    }
}

enum LetterKeyboardPhysicalInputAction: Equatable, Sendable {
    case append(Character)
    case delete
    case submit
}

/// Converts hardware-keyboard presses into the same constrained actions as the
/// on-screen child keyboard. System text entry remains disabled: only A-Z,
/// Delete/Backspace, and Return are accepted.
struct LetterKeyboardPhysicalInputPolicy: Sendable {
    func action(
        characters: String,
        isDelete: Bool = false,
        isSubmit: Bool = false,
        hasCommandModifier: Bool = false
    ) -> LetterKeyboardPhysicalInputAction? {
        guard !hasCommandModifier else { return nil }
        if isDelete {
            return .delete
        }
        if isSubmit {
            return .submit
        }

        guard characters.unicodeScalars.count == 1,
            let scalar = characters.unicodeScalars.first,
            (65...90).contains(scalar.value)
                || (97...122).contains(scalar.value)
        else {
            return nil
        }
        return .append(Character(characters.lowercased()))
    }
}

struct SpellQuestLayoutMetrics: Equatable, Sendable {
    let isHeightConstrained: Bool

    init(availableHeight: CGFloat) {
        isHeightConstrained = availableHeight < 560
    }

    var chromeHeight: CGFloat { isHeightConstrained ? 44 : 52 }
    var outerSpacing: CGFloat { isHeightConstrained ? 4 : 8 }
    var horizontalPadding: CGFloat { isHeightConstrained ? 10 : 18 }
    var bottomPadding: CGFloat { isHeightConstrained ? 4 : 12 }
    var boardSpacing: CGFloat { isHeightConstrained ? 4 : 12 }
    var boardPadding: CGFloat { isHeightConstrained ? 8 : 16 }
    var promptControlDiameter: CGFloat { isHeightConstrained ? 44 : 72 }
    var mascotDiameter: CGFloat { isHeightConstrained ? 32 : 44 }
    var responseSlotHeight: CGFloat { isHeightConstrained ? 36 : 52 }
    var responseLetterSize: CGFloat { isHeightConstrained ? 24 : 34 }
    var letterKeyHeight: CGFloat { isHeightConstrained ? 44 : 50 }
    var submissionControlHeight: CGFloat { isHeightConstrained ? 44 : 72 }
    var keyboardSpacing: CGFloat { isHeightConstrained ? 6 : 7 }
    var keyboardPadding: CGFloat { isHeightConstrained ? 6 : 10 }

    var minimumContentHeight: CGFloat {
        let keyboardHeight =
            letterKeyHeight * 3 + submissionControlHeight
            + keyboardSpacing * 3
            + keyboardPadding * 2
        let boardHeight =
            boardPadding * 2
            + promptControlDiameter
            + responseSlotHeight
            + keyboardHeight
            + boardSpacing * 2
        return chromeHeight + outerSpacing + boardHeight + bottomPadding
    }
}

struct SpellQuestView: View {
    let session: QuestSession
    let theme: TadaWorldTheme
    let audioExperienceService: any AudioExperienceService
    let onSpeak: () async -> Void
    let onBack: () -> Void
    let onComplete: (QuestAttemptSummary) -> Void

    @ObservedObject private var questTimer: QuestTimerModel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var attemptState: QuestAttemptStateMachine
    @State private var inputState: LetterKeyboardInputState
    @State private var isPaused = false
    @State private var isPlayingPrompt = false
    @State private var didPlayInitialPrompt = false
    @State private var showGuidedWord = false
    @State private var promptPlaybackTask: Task<Void, Never>?
    @State private var completionTask: Task<Void, Never>?
    @State private var feedbackPlaybackTask: Task<Void, Never>?
    @State private var completionFeedbackLifecycle:
        QuestItemFeedbackLifecycle<WordPromptID, QuestAttemptSummary>
    @State private var replayCountSinceLastAttempt = 0
    @State private var promptPauseSeconds: TimeInterval = 0
    @State private var responseClock: AttemptResponseClock
    @State private var keyFeedbackTrigger = 0
    @State private var starFeedbackEvent: QuestStarFeedbackEvent?
    @State private var starSlotFrames: [Int: CGRect] = [:]
    @FocusState private var acceptsPhysicalKeyboardInput: Bool

    private let evaluator = SpellingAnswerEvaluator()
    private let physicalKeyboardPolicy = LetterKeyboardPhysicalInputPolicy()

    init(
        session: QuestSession,
        questTimer: QuestTimerModel,
        theme: TadaWorldTheme,
        audioExperienceService: any AudioExperienceService =
            SilentAudioExperienceService(),
        onSpeak: @escaping () async -> Void,
        onBack: @escaping () -> Void,
        onComplete: @escaping (QuestAttemptSummary) -> Void
    ) {
        self.session = session
        self.theme = theme
        self.audioExperienceService = audioExperienceService
        self.onSpeak = onSpeak
        self.onBack = onBack
        self.onComplete = onComplete
        _questTimer = ObservedObject(wrappedValue: questTimer)
        _attemptState = State(
            initialValue: QuestAttemptStateMachine(
                policy: .write
            )
        )
        let letterCount = SpellingAnswerEvaluator().letterCount(
            in: session.prompt.normalizedText
        )
        _inputState = State(
            initialValue: LetterKeyboardInputState(
                maximumLetterCount: letterCount
            )
        )
        _completionFeedbackLifecycle = State(
            initialValue: QuestItemFeedbackLifecycle(
                itemID: session.prompt.id
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
            GeometryReader { proxy in
                let metrics = SpellQuestLayoutMetrics(
                    availableHeight: proxy.size.height
                )
                ZStack {
                    VStack(spacing: metrics.outerSpacing) {
                        QuestChrome(
                            mode: .write,
                            currentItem: session.currentItem,
                            totalItems: session.totalItems,
                            earnedStars: session.earnedItemCount,
                            starFeedback: starFeedbackEvent,
                            elapsedText: questTimer.elapsedText,
                            isEmergency: questTimer.isEmergency,
                            theme: theme,
                            isHeightConstrained: metrics.isHeightConstrained,
                            onBack: onBack,
                            onPause: pause
                        )
                        .zIndex(3)

                        spellingBoard(metrics: metrics)
                            .frame(maxWidth: 980, maxHeight: .infinity)
                            .padding(.horizontal, metrics.horizontalPadding)
                            .padding(.bottom, metrics.bottomPadding)
                            .focusable()
                            .focused($acceptsPhysicalKeyboardInput)
                            .focusEffectDisabled()
                            .onKeyPress { press in
                                handlePhysicalKeyboardPress(press)
                            }
                            .onTapGesture {
                                acceptsPhysicalKeyboardInput = true
                            }
                    }
                    .hiddenFromAccessibility(when: isPaused)

                    TadaEmergencyAtmosphere(
                        theme: theme,
                        isActive: questTimer.isEmergency
                    )

                    if let summary = completionFeedbackLifecycle.visibleFeedback(
                        for: session.prompt.id
                    ) {
                        completionFeedback(for: summary)
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
        .task(id: session.prompt.id) {
            resetForCurrentWordIfNeeded()
            acceptsPhysicalKeyboardInput = true
            guard !didPlayInitialPrompt else { return }
            didPlayInitialPrompt = true
            playPrompt(countsAsReplay: false)
        }
        .task(id: questTimer.isEmergency) {
            await audioExperienceService.setEmergencyMode(questTimer.isEmergency)
        }
        .onDisappear {
            promptPlaybackTask?.cancel()
            completionTask?.cancel()
            feedbackPlaybackTask?.cancel()
            attemptState.cancelAttempt()
            questTimer.resume(from: .promptPlayback)
            Task { await audioExperienceService.setEmergencyMode(false) }
        }
        .sensoryFeedback(.selection, trigger: keyFeedbackTrigger)
    }

    private func spellingBoard(metrics: SpellQuestLayoutMetrics) -> some View {
        VStack(spacing: metrics.boardSpacing) {
            HStack(spacing: 12) {
                TadaWorldMascot(
                    theme: theme,
                    pose: .encouraging,
                    size: metrics.mascotDiameter
                )

                Spacer()

                Button {
                    playPrompt()
                } label: {
                    Image(
                        systemName: isPlayingPrompt
                            ? "speaker.wave.3.fill" : "speaker.wave.2.fill"
                    )
                    .font(
                        .system(
                            metrics.isHeightConstrained ? .headline : .title2,
                            design: .rounded,
                            weight: .bold
                        )
                    )
                    .frame(
                        width: metrics.promptControlDiameter,
                        height: metrics.promptControlDiameter
                    )
                }
                .buttonStyle(
                    TadaPrimaryButtonStyle(fill: theme.primary, isCompact: true)
                )
                .disabled(isPlayingPrompt || isCompleted)
                .accessibilityLabel(isPlayingPrompt ? "Playing" : "Hear the word")
                .accessibilityHint("Plays the spelling prompt again")
            }

            if showGuidedWord {
                Text(session.prompt.displayText)
                    .font(
                        .system(
                            metrics.isHeightConstrained ? .headline : .title,
                            design: .rounded,
                            weight: .heavy
                        )
                    )
                    .foregroundStyle(theme.primary)
                    .padding(.horizontal, 18)
                    .padding(.vertical, metrics.isHeightConstrained ? 2 : 6)
                    .background(theme.surface.opacity(0.94), in: Capsule())
                    .accessibilityLabel(
                        "Example spelling: \(session.prompt.displayText)"
                    )
            }

            responseSlots(metrics: metrics)

            if let feedbackMessage {
                Label(feedbackMessage, systemImage: "arrow.counterclockwise.circle.fill")
                    .font(
                        .system(
                            metrics.isHeightConstrained ? .caption : .subheadline,
                            design: .rounded,
                            weight: .bold
                        )
                    )
                    .foregroundStyle(theme.ink.opacity(0.72))
                    .padding(.horizontal, 14)
                    .padding(.vertical, metrics.isHeightConstrained ? 2 : 6)
                    .background(theme.surface.opacity(0.92), in: Capsule())
            }

            ThemeLetterKeyboardView(
                theme: theme,
                metrics: metrics,
                isEnabled: !isPaused && !isPlayingPrompt && !isCompleted,
                onLetter: append,
                onDelete: removeLast,
                onDone: submit,
                canDelete: !inputState.isEmpty,
                canSubmit: !inputState.isEmpty
            )
        }
        .padding(metrics.boardPadding)
        .background(
            Color.white.opacity(0.90),
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
            .strokeBorder(theme.primary.opacity(0.18), lineWidth: 2)
        }
        .shadow(color: theme.ink.opacity(0.10), radius: 12, y: 6)
    }

    private func responseSlots(metrics: SpellQuestLayoutMetrics) -> some View {
        HStack(spacing: 8) {
            ForEach(0..<inputState.maximumLetterCount, id: \.self) { index in
                VStack(spacing: 3) {
                    Text(letter(at: index))
                        .font(
                            .system(
                                size: metrics.responseLetterSize,
                                weight: .heavy,
                                design: .rounded
                            )
                        )
                        .foregroundStyle(theme.ink)
                        .frame(
                            minWidth: 30,
                            minHeight: metrics.responseSlotHeight - 12
                        )
                    Capsule()
                        .fill(theme.primary.opacity(0.52))
                        .frame(width: 36, height: 4)
                }
            }
        }
        .frame(minHeight: metrics.responseSlotHeight)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(
            inputState.response.isEmpty
                ? "No letters entered"
                : "Entered \(inputState.response.uppercased())"
        )
    }

    private var isCompleted: Bool {
        attemptState.completedSummary != nil
    }

    private var feedbackMessage: String? {
        guard
            case .feedback(.tryAgain(let remainingAttempts)) =
                attemptState.phase
        else {
            return nil
        }
        if attemptState.usedGuidance {
            return "Look at the word above and spell it one more time."
        }
        return remainingAttempts == 1
            ? "Try spelling it one more time."
            : "Try again. You have \(remainingAttempts) more tries."
    }

    private func letter(at index: Int) -> String {
        let letters = Array(inputState.response.uppercased())
        guard letters.indices.contains(index) else { return " " }
        return String(letters[index])
    }

    private func append(_ letter: Character) {
        guard inputState.append(letter) else { return }
        keyFeedbackTrigger += 1
        Task { await audioExperienceService.play(.click) }
    }

    private func handlePhysicalKeyboardPress(
        _ press: KeyPress
    ) -> KeyPress.Result {
        guard !isPaused, !isPlayingPrompt, !isCompleted else {
            return .ignored
        }
        let blockedModifiers: EventModifiers = [.command, .control, .option]
        guard
            let action = physicalKeyboardPolicy.action(
                characters: press.characters,
                isDelete: press.key == .delete || press.key == .deleteForward,
                isSubmit: press.key == .return,
                hasCommandModifier: !press.modifiers
                    .intersection(blockedModifiers)
                    .isEmpty
            )
        else {
            return .ignored
        }

        switch action {
        case .append(let letter):
            append(letter)
        case .delete:
            removeLast()
        case .submit:
            submit()
        }
        return .handled
    }

    private func removeLast() {
        guard inputState.removeLast() else { return }
        keyFeedbackTrigger += 1
        Task { await audioExperienceService.play(.click) }
    }

    private func submit() {
        guard !inputState.isEmpty, attemptState.beginAttempt() else { return }
        let response = inputState.response
        let decision: RecognitionDecision =
            evaluator.matches(
                response,
                target: session.prompt.normalizedText
            ) ? .matched : .notMatched
        let activeSeconds = responseClock.elapsed(at: questTimer.elapsedSeconds)
        let timing = AttemptTiming(
            totalResponseTime: ElapsedTime(
                seconds: activeSeconds + promptPauseSeconds
            ),
            replayPauseTime: ElapsedTime(seconds: promptPauseSeconds)
        )
        let attemptReplayCount = replayCountSinceLastAttempt
        replayCountSinceLastAttempt = 0
        attemptState.receive(
            RecognitionResult(
                decision: decision,
                recognizedText: response,
                confidence: RecognitionConfidence(1)
            ),
            timing: timing,
            replayCount: attemptReplayCount
        )
        let shouldShowGuidedWord =
            attemptState.prepareGuidedImitationAttempt()
            || attemptState.usedGuidance
        showGuidedWord = shouldShowGuidedWord
        presentStarFeedback(for: decision)
        feedbackPlaybackTask?.cancel()
        let cue = QuestAttemptFeedbackPolicy.presentation(for: decision).cue
        let feedbackPlayback = Task {
            await audioExperienceService.play(cue)
        }
        feedbackPlaybackTask = feedbackPlayback

        if let summary = attemptState.completedSummary {
            showGuidedWord = summary.completion == .needsPractice
            showCompletion(summary, after: feedbackPlayback)
        } else if case .feedback(.tryAgain) = attemptState.phase {
            inputState.clear()
            resetResponseClock()
            announceForAccessibility(
                feedbackMessage ?? "Try spelling it again."
            )
        }
    }

    private func presentStarFeedback(for decision: RecognitionDecision) {
        if decision == .matched,
            attemptState.completedSummary?.earnsItemStar != true
        {
            return
        }
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

    private func playPrompt(countsAsReplay: Bool = true) {
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
        isPlayingPrompt = false
        questTimer.suspend(for: .userPause)
        questTimer.resume(from: .promptPlayback)
        isPaused = true
        acceptsPhysicalKeyboardInput = false
    }

    private func resume() {
        isPaused = false
        questTimer.resume(from: .userPause)
        acceptsPhysicalKeyboardInput = true
    }

    private func resetResponseClock() {
        responseClock.reset(at: questTimer.elapsedSeconds)
        promptPauseSeconds = 0
    }

    private func showCompletion(
        _ summary: QuestAttemptSummary,
        after feedbackPlayback: Task<Void, Never>? = nil
    ) {
        let completedItemID = session.prompt.id
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
        announceForAccessibility(
            summary.completion == .needsPractice
                ? "The correct spelling is \(session.prompt.displayText)."
                : "You got it!"
        )
        completionTask?.cancel()
        completionTask = Task { @MainActor in
            do {
                try await QuestAdvanceTimingPolicy.waitBeforeAdvance(
                    minimumFeedbackVisibility: reduceMotion
                        ? .milliseconds(40)
                        : WriteQuestTimingPolicy.completionFeedbackVisibility,
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

    private func completionFeedback(
        for summary: QuestAttemptSummary
    ) -> some View {
        let isSuccess = summary.completion != .needsPractice
        return TadaFeedbackBurst(
            theme: theme,
            kind: isSuccess ? .success : .tryAgain,
            message: isSuccess
                ? "Great spelling!"
                : "Correct spelling: \(session.prompt.displayText)"
        )
    }

    private func resetForCurrentWordIfNeeded() {
        guard completionFeedbackLifecycle.transition(to: session.prompt.id) else {
            return
        }
        promptPlaybackTask?.cancel()
        completionTask?.cancel()
        feedbackPlaybackTask?.cancel()
        promptPlaybackTask = nil
        completionTask = nil
        feedbackPlaybackTask = nil
        attemptState = QuestAttemptStateMachine(
            policy: .write
        )
        inputState = LetterKeyboardInputState(
            maximumLetterCount: evaluator.letterCount(
                in: session.prompt.normalizedText
            )
        )
        isPaused = false
        isPlayingPrompt = false
        didPlayInitialPrompt = false
        showGuidedWord = false
        replayCountSinceLastAttempt = 0
        promptPauseSeconds = 0
        starFeedbackEvent = nil
        acceptsPhysicalKeyboardInput = true
        responseClock.reset(at: questTimer.elapsedSeconds)
        questTimer.resume(from: .promptPlayback)
    }
}

private struct ThemeLetterKeyboardView: View {
    let theme: TadaWorldTheme
    let metrics: SpellQuestLayoutMetrics
    let isEnabled: Bool
    let onLetter: (Character) -> Void
    let onDelete: () -> Void
    let onDone: () -> Void
    let canDelete: Bool
    let canSubmit: Bool

    private let rows = [
        Array("QWERTYUIOP"),
        Array("ASDFGHJKL"),
        Array("ZXCVBNM"),
    ]

    var body: some View {
        let submission = KidSubmissionControl.spelling
        VStack(spacing: metrics.keyboardSpacing) {
            ForEach(Array(rows.enumerated()), id: \.offset) { rowIndex, row in
                HStack(spacing: metrics.keyboardSpacing) {
                    ForEach(row, id: \.self) { letter in
                        Button {
                            onLetter(letter)
                        } label: {
                            Text(String(letter))
                                .font(
                                    .system(
                                        size: rowIndex == 0 ? 23 : 25,
                                        weight: .heavy,
                                        design: .rounded
                                    )
                                )
                                .frame(
                                    maxWidth: .infinity,
                                    minHeight: metrics.letterKeyHeight
                                )
                        }
                        .buttonStyle(ThemeLetterKeyStyle(theme: theme))
                        .disabled(!isEnabled)
                        .accessibilityLabel("Letter \(String(letter))")
                        .accessibilityIdentifier("spell.key.\(letter)")
                    }
                }
                .padding(.horizontal, CGFloat(rowIndex) * 18)
            }

            HStack(spacing: 12) {
                Button(action: onDelete) {
                    Image(systemName: "delete.left.fill")
                        .font(.system(.title2, design: .rounded, weight: .bold))
                        .frame(
                            maxWidth: .infinity,
                            minHeight: metrics.submissionControlHeight
                        )
                }
                .buttonStyle(ThemeLetterKeyStyle(theme: theme))
                .disabled(!isEnabled || !canDelete)
                .accessibilityLabel("Delete last letter")
                .accessibilityHint("Removes the last letter")
                .accessibilityIdentifier("spell.delete")

                Button(action: onDone) {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(.largeTitle, design: .rounded, weight: .heavy))
                        .frame(
                            maxWidth: .infinity,
                            minHeight: metrics.submissionControlHeight
                        )
                }
                .buttonStyle(
                    TadaPrimaryButtonStyle(
                        fill: TadaPrimitiveTokens.ColorValue.success,
                        isCompact: true
                    )
                )
                .disabled(!isEnabled || !canSubmit)
                .accessibilityLabel(submission.accessibilityLabel)
                .accessibilityHint(submission.accessibilityHint)
                .accessibilityIdentifier(submission.accessibilityIdentifier)
            }
            .frame(maxWidth: 520)
        }
        .padding(metrics.keyboardPadding)
        .background(theme.secondary.opacity(0.14), in: RoundedRectangle(cornerRadius: 18))
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Theme letter keyboard")
    }
}

private struct ThemeLetterKeyStyle: ButtonStyle {
    let theme: TadaWorldTheme
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .foregroundStyle(theme.ink)
            .background(
                configuration.isPressed
                    ? theme.accent.opacity(0.42)
                    : theme.surface.opacity(0.96),
                in: RoundedRectangle(cornerRadius: 13, style: .continuous)
            )
            .overlay {
                RoundedRectangle(cornerRadius: 13, style: .continuous)
                    .strokeBorder(theme.primary.opacity(0.24), lineWidth: 1.5)
            }
            .shadow(
                color: theme.ink.opacity(configuration.isPressed ? 0.05 : 0.14),
                radius: configuration.isPressed ? 1 : 3,
                y: configuration.isPressed ? 1 : 3
            )
            .scaleEffect(configuration.isPressed ? 0.94 : 1)
            .saturation(isEnabled ? 1 : 0.2)
            .opacity(isEnabled ? 1 : 0.58)
            .animation(.easeOut(duration: 0.10), value: configuration.isPressed)
    }
}
