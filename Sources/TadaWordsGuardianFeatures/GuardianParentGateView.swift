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
            Text("Grown-ups only")
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

            Button("Unlock", action: validateAnswer)
                .buttonStyle(GuardianPrimaryButtonStyle())
                .frame(maxWidth: 340)
                .disabled(answer.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                .accessibilityHint("Opens the guardian dashboard")

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
            .modifier(GuardianNumericKeyboardModifier())
            .accessibilityHint("Enter the number, then choose Unlock")
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
