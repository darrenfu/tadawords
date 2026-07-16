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

struct SpellQuestView: View {
    let session: QuestSession
    let theme: TadaWorldTheme
    let audioExperienceService: any AudioExperienceService
    let onSpeak: () async -> Void
    let onBack: () -> Void
    let onComplete: (QuestAttemptSummary) -> Void

    @ObservedObject private var questTimer: QuestTimerModel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var attemptState = QuestAttemptStateMachine(policy: .write)
    @State private var inputState: LetterKeyboardInputState
    @State private var isPaused = false
    @State private var isPlayingPrompt = false
    @State private var didPlayInitialPrompt = false
    @State private var showGuidedWord = false
    @State private var promptPlaybackTask: Task<Void, Never>?
    @State private var completionTask: Task<Void, Never>?
    @State private var completionFeedbackLifecycle:
        QuestItemFeedbackLifecycle<WordPromptID, QuestAttemptSummary>
    @State private var replayCountSinceLastAttempt = 0
    @State private var promptPauseSeconds: TimeInterval = 0
    @State private var responseClock: AttemptResponseClock
    @State private var keyFeedbackTrigger = 0

    private let evaluator = SpellingAnswerEvaluator()

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
            ZStack {
                VStack(spacing: 8) {
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

                    spellingBoard
                        .frame(maxWidth: 980, maxHeight: .infinity)
                        .padding(.horizontal, 18)
                        .padding(.bottom, 12)
                }
                .hiddenFromAccessibility(when: isPaused)

                TadaEmergencyAtmosphere(theme: theme, isActive: questTimer.isEmergency)

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
            }
        }
        .task(id: session.prompt.id) {
            resetForCurrentWordIfNeeded()
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
            attemptState.cancelAttempt()
            questTimer.resume(from: .promptPlayback)
            Task { await audioExperienceService.setEmergencyMode(false) }
        }
        .sensoryFeedback(.selection, trigger: keyFeedbackTrigger)
    }

    private var spellingBoard: some View {
        VStack(spacing: 12) {
            HStack(spacing: 12) {
                TadaWorldMascot(theme: theme, pose: .encouraging, size: 44)

                Spacer()

                Button {
                    playPrompt()
                } label: {
                    Image(
                        systemName: isPlayingPrompt
                            ? "speaker.wave.3.fill" : "speaker.wave.2.fill"
                    )
                    .font(.system(.title2, design: .rounded, weight: .bold))
                    .frame(
                        width: TadaChildScaleTokens.Action.primaryTouchDiameter,
                        height: TadaChildScaleTokens.Action.primaryTouchDiameter
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
                    .font(.system(.title, design: .rounded, weight: .heavy))
                    .foregroundStyle(theme.primary)
                    .padding(.horizontal, 18)
                    .padding(.vertical, 6)
                    .background(theme.surface.opacity(0.94), in: Capsule())
                    .accessibilityLabel(
                        "Example spelling: \(session.prompt.displayText)"
                    )
            }

            responseSlots

            if let feedbackMessage {
                Label(feedbackMessage, systemImage: "arrow.counterclockwise.circle.fill")
                    .font(.system(.subheadline, design: .rounded, weight: .bold))
                    .foregroundStyle(theme.ink.opacity(0.72))
                    .padding(.horizontal, 14)
                    .padding(.vertical, 6)
                    .background(theme.surface.opacity(0.92), in: Capsule())
            }

            ThemeLetterKeyboardView(
                theme: theme,
                isEnabled: !isPaused && !isPlayingPrompt && !isCompleted,
                onLetter: append,
                onDelete: removeLast,
                onDone: submit,
                canDelete: !inputState.isEmpty,
                canSubmit: !inputState.isEmpty
            )
        }
        .padding(16)
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

    private var responseSlots: some View {
        HStack(spacing: 8) {
            ForEach(0..<inputState.maximumLetterCount, id: \.self) { index in
                VStack(spacing: 3) {
                    Text(letter(at: index))
                        .font(.system(size: 34, weight: .heavy, design: .rounded))
                        .foregroundStyle(theme.ink)
                        .frame(minWidth: 30, minHeight: 40)
                    Capsule()
                        .fill(theme.primary.opacity(0.52))
                        .frame(width: 36, height: 4)
                }
            }
        }
        .frame(minHeight: 52)
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
        guard case .feedback(.rewriteAfterAnswer) = attemptState.phase else {
            return nil
        }
        return "Look, then spell it one more time."
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
        Task {
            await audioExperienceService.play(
                decision == .matched ? .correct : .validRetry
            )
        }

        if let summary = attemptState.completedSummary {
            showCompletion(summary)
        } else if case .feedback(.rewriteAfterAnswer) = attemptState.phase {
            showGuidedWord = true
            inputState.clear()
            resetResponseClock()
            announceForAccessibility(
                "The word is \(session.prompt.displayText). Spell it one more time."
            )
        }
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
    }

    private func resume() {
        isPaused = false
        questTimer.resume(from: .userPause)
    }

    private func resetResponseClock() {
        responseClock.reset(at: questTimer.elapsedSeconds)
        promptPauseSeconds = 0
    }

    private func showCompletion(_ summary: QuestAttemptSummary) {
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
                ? "We’ll practice this one again."
                : "You got it!"
        )
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
                : "We’ll practice this one again."
        )
    }

    private func resetForCurrentWordIfNeeded() {
        guard completionFeedbackLifecycle.transition(to: session.prompt.id) else {
            return
        }
        promptPlaybackTask?.cancel()
        completionTask?.cancel()
        promptPlaybackTask = nil
        completionTask = nil
        attemptState = QuestAttemptStateMachine(policy: .write)
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
        responseClock.reset(at: questTimer.elapsedSeconds)
        questTimer.resume(from: .promptPlayback)
    }
}

private struct ThemeLetterKeyboardView: View {
    let theme: TadaWorldTheme
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
        VStack(spacing: 7) {
            ForEach(Array(rows.enumerated()), id: \.offset) { rowIndex, row in
                HStack(spacing: 7) {
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
                                .frame(maxWidth: .infinity, minHeight: 50)
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
                            minHeight: submission.minimumTouchSize
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
                            minHeight: submission.minimumTouchSize
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
        .padding(10)
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
