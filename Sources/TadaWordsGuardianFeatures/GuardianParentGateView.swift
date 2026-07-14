import SwiftUI
import TadaWordsDesignSystem

struct GuardianParentGateView: View {
    let onExit: () -> Void
    let onContinue: () -> Void

    @State private var challenge = ParentGateChallenge.make()
    @State private var answer = ""
    @State private var showsError = false
    @FocusState private var answerIsFocused: Bool
    @AccessibilityFocusState private var errorIsFocused: Bool

    var body: some View {
        GeometryReader { proxy in
            ScrollView {
                ViewThatFits(in: .vertical) {
                    regularLayout
                        .frame(minHeight: proxy.size.height)
                    compactLayout
                        .frame(minHeight: proxy.size.height)
                }
                .frame(maxWidth: .infinity)
                .padding(GuardianPrimitiveTokens.Spacing.large)
            }
            .scrollDismissesKeyboard(.interactively)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var regularLayout: some View {
        VStack(spacing: GuardianPrimitiveTokens.Spacing.large) {
            Spacer(minLength: GuardianPrimitiveTokens.Spacing.small)
            gateEmblem(size: 126, symbolSize: 58)
            heading
            challengeForm
            Spacer(minLength: GuardianPrimitiveTokens.Spacing.small)
        }
    }

    private var compactLayout: some View {
        HStack(spacing: GuardianPrimitiveTokens.Spacing.xLarge) {
            VStack(spacing: GuardianPrimitiveTokens.Spacing.medium) {
                gateEmblem(size: 92, symbolSize: 42)
                heading
            }
            .frame(maxWidth: 360)

            challengeForm
                .frame(maxWidth: 390)
        }
    }

    private var heading: some View {
        VStack(spacing: GuardianPrimitiveTokens.Spacing.small) {
            Text("Parents only")
                .font(.system(.largeTitle, design: .rounded, weight: .bold))
            Text("Solve this to manage word pools and daily settings.")
                .font(.system(.body, design: .rounded, weight: .medium))
                .foregroundStyle(GuardianSemanticTokens.secondaryForeground)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 420)
        }
    }

    private var challengeForm: some View {
        VStack(spacing: GuardianPrimitiveTokens.Spacing.medium) {
            Text(challenge.question)
                .font(.system(size: 34, weight: .bold, design: .rounded))
                .monospacedDigit()
                .accessibilityLabel(challenge.accessibilityQuestion)

            numericAnswerField

            if showsError {
                Text("Not quite. Try again.")
                    .font(.system(.subheadline, design: .rounded, weight: .semibold))
                    .foregroundStyle(GuardianPrimitiveTokens.ColorValue.orange)
                    .accessibilityAddTraits(.isStaticText)
                    .accessibilityFocused($errorIsFocused)
            }

            Label("Unlocks automatically", systemImage: "bolt.fill")
                .font(.system(.subheadline, design: .rounded, weight: .semibold))
                .foregroundStyle(GuardianSemanticTokens.secondaryForeground)
                .accessibilityHint("The answer is checked after the last digit")

            Button(action: onExit) {
                Label("Back to Tada Words", systemImage: "chevron.left")
                    .font(.system(.subheadline, design: .rounded, weight: .semibold))
                    .frame(minHeight: TadaPrimitiveTokens.TouchTarget.minimum)
            }
            .buttonStyle(.plain)
            .foregroundStyle(GuardianSemanticTokens.secondaryForeground)
        }
    }

    private var numericAnswerField: some View {
        TextField("Answer", text: $answer)
            .font(.system(.title2, design: .rounded, weight: .semibold))
            .multilineTextAlignment(.center)
            .textFieldStyle(.roundedBorder)
            .frame(maxWidth: 220)
            .focused($answerIsFocused)
            .onSubmit(validateAnswer)
            .onChange(of: answer) { _, newValue in
                handleAnswerChange(newValue)
            }
            .modifier(GuardianNumericKeyboardModifier())
            .accessibilityHint("Enter the answer. It is checked automatically.")
    }

    private func gateEmblem(size: CGFloat, symbolSize: CGFloat) -> some View {
        ZStack {
            Circle()
                .fill(GuardianSemanticTokens.primary.opacity(0.10))
            Image(systemName: "lock.shield.fill")
                .font(.system(size: symbolSize, weight: .bold))
                .foregroundStyle(GuardianSemanticTokens.primary)
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }

    private func validateAnswer() {
        guard
            Int(answer.trimmingCharacters(in: .whitespacesAndNewlines))
                == challenge.answer
        else {
            showsError = true
            answer = ""
            answerIsFocused = true
            errorIsFocused = true
            return
        }

        showsError = false
        errorIsFocused = false
        answerIsFocused = false
        onContinue()
    }

    private func handleAnswerChange(_ value: String) {
        let digits = value.filter(\.isNumber)
        if digits != value {
            answer = digits
            return
        }

        let decision = ParentGateAnswerPolicy.decision(
            input: digits,
            expectedAnswer: challenge.answer
        )
        showsError = ParentGateAnswerPolicy.shouldShowError(
            after: decision,
            input: digits,
            wasShowingError: showsError
        )

        switch decision {
        case .incomplete:
            if !showsError {
                errorIsFocused = false
            }
        case .correct:
            validateAnswer()
        case .incorrect:
            answer = ""
            answerIsFocused = true
            errorIsFocused = true
        }
    }
}

private struct GuardianNumericKeyboardModifier: ViewModifier {
    func body(content: Content) -> some View {
        #if os(iOS)
            content.keyboardType(.numberPad)
        #else
            content
        #endif
    }
}

enum ParentGateAnswerDecision: Equatable {
    case incomplete
    case correct
    case incorrect
}

enum ParentGateAnswerPolicy {
    static func decision(
        input: String,
        expectedAnswer: Int
    ) -> ParentGateAnswerDecision {
        let expected = String(expectedAnswer)
        guard input.count >= expected.count else { return .incomplete }
        return input == expected ? .correct : .incorrect
    }

    static func shouldShowError(
        after decision: ParentGateAnswerDecision,
        input: String,
        wasShowingError: Bool
    ) -> Bool {
        switch decision {
        case .incomplete:
            // A wrong full-length answer is cleared programmatically. Keep
            // its feedback visible through that empty onChange callback, then
            // dismiss it as soon as the parent starts the next answer.
            input.isEmpty ? wasShowingError : false
        case .correct:
            false
        case .incorrect:
            true
        }
    }
}

private struct ParentGateChallenge {
    let left: Int
    let right: Int

    var answer: Int { left * right }
    var question: String { "\(left) × \(right) = ?" }
    var accessibilityQuestion: String { "What is \(left) times \(right)?" }

    static func make() -> ParentGateChallenge {
        let pairs = [(6, 7), (7, 8), (8, 6), (9, 7), (8, 9)]
        let pair = pairs.randomElement() ?? (7, 8)
        return ParentGateChallenge(left: pair.0, right: pair.1)
    }
}
