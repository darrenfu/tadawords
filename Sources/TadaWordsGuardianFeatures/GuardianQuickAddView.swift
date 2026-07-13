import SwiftUI
import TadaWordsContent
import TadaWordsDomain

struct GuardianQuickAddView: View {
    let onBack: () -> Void
    let onSubmit: (GuardianWordImportRequest) -> Void

    @State private var selectedMode: LearningMode = .read
    @State private var rawText = ""
    @State private var spokenContexts: [String: String] = [:]
    @State private var isAddingSpokenContext = false
    @FocusState private var inputIsFocused: Bool

    private var parsedWordCount: Int {
        GuardianBatchPreviewCounter.count(
            in: rawText,
            learningMode: selectedMode
        )
    }

    private var canSubmit: Bool {
        guard parsedWordCount > 0 else { return false }
        guard isAddingSpokenContext else { return true }
        return requiredContextWords.allSatisfy(contextIsValid)
    }

    private var requiredContextWords: [String] {
        let result = ManualWordBatchParser().parse(
            rawText,
            learningMode: selectedMode
        )
        var seen = Set<String>()
        return result.rejected.compactMap { rejection in
            guard
                case .invalidPrompt(
                    .contextRequired(let word, _)
                ) = rejection.reason,
                seen.insert(word).inserted
            else {
                return nil
            }
            return word
        }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: GuardianPrimitiveTokens.Spacing.large) {
                GuardianNavigationHeader(title: "Quick Add", onBack: onBack)

                VStack(alignment: .leading, spacing: GuardianPrimitiveTokens.Spacing.small) {
                    Text("Choose one pool")
                        .font(.system(.headline, design: .rounded, weight: .bold))
                    Text("Every word in this batch goes to the selected pool only.")
                        .font(.system(.subheadline, design: .rounded, weight: .medium))
                        .foregroundStyle(GuardianSemanticTokens.secondaryForeground)
                }

                Picker("Word pool", selection: $selectedMode) {
                    ForEach(LearningMode.allCases, id: \.self) { mode in
                        Label(mode.guardianTitle, systemImage: mode.guardianSymbol)
                            .tag(mode)
                    }
                }
                .pickerStyle(.segmented)
                .accessibilityHint("Read and Write pools remain separate")

                GuardianCard {
                    VStack(alignment: .leading, spacing: GuardianPrimitiveTokens.Spacing.medium) {
                        HStack {
                            GuardianModeBadge(mode: selectedMode, includesPoolSuffix: true)
                            Spacer()
                            Text("\(parsedWordCount) found")
                                .font(.system(.caption, design: .rounded, weight: .semibold))
                                .monospacedDigit()
                                .foregroundStyle(GuardianSemanticTokens.secondaryForeground)
                        }

                        ZStack(alignment: .topLeading) {
                            if rawText.isEmpty {
                                Text(
                                    "Type or paste words here\nOne per line, or separated by spaces or commas"
                                )
                                .font(.system(.body, design: .rounded, weight: .medium))
                                .foregroundStyle(
                                    GuardianSemanticTokens.secondaryForeground.opacity(0.72)
                                )
                                .padding(.horizontal, 6)
                                .padding(.vertical, 8)
                                .allowsHitTesting(false)
                            }

                            TextEditor(text: $rawText)
                                .font(.system(.title3, design: .rounded, weight: .medium))
                                .scrollContentBackground(.hidden)
                                .focused($inputIsFocused)
                                .frame(minHeight: 190)
                                .accessibilityLabel("Words to add")
                                .accessibilityHint("Type or paste one or more English words")
                        }
                        .padding(10)
                        .background(
                            GuardianSemanticTokens.background,
                            in: RoundedRectangle(
                                cornerRadius: GuardianPrimitiveTokens.Radius.medium,
                                style: .continuous
                            )
                        )
                        .overlay {
                            RoundedRectangle(
                                cornerRadius: GuardianPrimitiveTokens.Radius.medium,
                                style: .continuous
                            )
                            .strokeBorder(
                                inputIsFocused
                                    ? GuardianSemanticTokens.accent(for: selectedMode)
                                    : GuardianSemanticTokens.foreground.opacity(0.10),
                                lineWidth: inputIsFocused ? 2 : 1
                            )
                        }

                        Label(
                            "Adding to \(selectedMode.guardianTitle) Pool only",
                            systemImage: "arrow.down.circle.fill"
                        )
                        .font(.system(.subheadline, design: .rounded, weight: .semibold))
                        .foregroundStyle(GuardianSemanticTokens.accent(for: selectedMode))
                    }
                }

                if isAddingSpokenContext, !requiredContextWords.isEmpty {
                    spokenContextSection
                }

                Button {
                    inputIsFocused = false
                    if !requiredContextWords.isEmpty, !isAddingSpokenContext {
                        isAddingSpokenContext = true
                    } else {
                        onSubmit(
                            GuardianWordImportRequest(
                                rawText: rawText,
                                learningMode: selectedMode,
                                spokenContextsByNormalizedWord: submittedContexts
                            )
                        )
                    }
                } label: {
                    Label(
                        submitButtonTitle,
                        systemImage: submitButtonSymbol
                    )
                }
                .buttonStyle(
                    GuardianPrimaryButtonStyle(
                        tint: GuardianSemanticTokens.accent(for: selectedMode)
                    )
                )
                .disabled(!canSubmit)
                .opacity(canSubmit ? 1 : 0.48)
            }
            .frame(maxWidth: 720, alignment: .leading)
            .padding(.horizontal, GuardianPrimitiveTokens.Spacing.medium)
            .padding(.vertical, GuardianPrimitiveTokens.Spacing.large)
            .frame(maxWidth: .infinity)
        }
        .scrollDismissesKeyboard(.interactively)
        .onChange(of: selectedMode) {
            spokenContexts = [:]
            isAddingSpokenContext = false
        }
    }

    private var spokenContextSection: some View {
        GuardianCard {
            VStack(alignment: .leading, spacing: GuardianPrimitiveTokens.Spacing.medium) {
                VStack(alignment: .leading, spacing: 4) {
                    Label("Add spoken context", systemImage: "quote.bubble.fill")
                        .font(.system(.headline, design: .rounded, weight: .bold))
                    Text(
                        "A short sentence helps the app say an ambiguous word clearly. There is no pronunciation menu."
                    )
                    .font(.system(.subheadline, design: .rounded, weight: .medium))
                    .foregroundStyle(GuardianSemanticTokens.secondaryForeground)
                }

                ForEach(
                    requiredContextFields,
                    id: \GuardianSpokenContextField.id
                ) { (field: GuardianSpokenContextField) in
                    VStack(alignment: .leading, spacing: 6) {
                        Text(field.word)
                            .font(.system(.headline, design: .rounded, weight: .bold))
                        TextField(
                            "Use “\(field.word)” in a short sentence",
                            text: contextBinding(for: field.word),
                            axis: .vertical
                        )
                        .padding(12)
                        .background(
                            GuardianSemanticTokens.background,
                            in: RoundedRectangle(
                                cornerRadius: GuardianPrimitiveTokens.Radius.small,
                                style: .continuous
                            )
                        )
                        .overlay {
                            RoundedRectangle(
                                cornerRadius: GuardianPrimitiveTokens.Radius.small,
                                style: .continuous
                            )
                            .strokeBorder(
                                contextIsValid(field.word)
                                    ? GuardianSemanticTokens.success.opacity(0.7)
                                    : GuardianSemanticTokens.foreground.opacity(0.10),
                                lineWidth: 1
                            )
                        }
                        Text("Include the exact word “\(field.word)”.")
                            .font(.system(.caption, design: .rounded, weight: .medium))
                            .foregroundStyle(GuardianSemanticTokens.secondaryForeground)
                    }
                }
            }
        }
    }

    private var submittedContexts: [String: String] {
        Dictionary(
            uniqueKeysWithValues: requiredContextWords.compactMap { word in
                guard
                    let context = spokenContexts[word]?.trimmingCharacters(
                        in: .whitespacesAndNewlines
                    ), !context.isEmpty
                else {
                    return nil
                }
                return (word, context)
            }
        )
    }

    private var requiredContextFields: [GuardianSpokenContextField] {
        requiredContextWords.map {
            GuardianSpokenContextField(word: $0)
        }
    }

    private var submitButtonTitle: String {
        if !requiredContextWords.isEmpty, !isAddingSpokenContext {
            return "Continue for spoken context"
        }
        return parsedWordCount == 1
            ? "Add 1 word"
            : "Add \(parsedWordCount) words"
    }

    private var submitButtonSymbol: String {
        !requiredContextWords.isEmpty && !isAddingSpokenContext
            ? "arrow.right.circle.fill"
            : "plus.circle.fill"
    }

    private func contextBinding(for word: String) -> Binding<String> {
        Binding(
            get: { spokenContexts[word, default: ""] },
            set: { spokenContexts[word] = $0 }
        )
    }

    private func contextIsValid(_ word: String) -> Bool {
        guard let context = submittedContexts[word] else { return false }
        return
            (try? WordPrompt(
                learningMode: selectedMode,
                text: word,
                audioCue: .contextual(context)
            )) != nil
    }
}

private struct GuardianSpokenContextField: Identifiable {
    let word: String

    var id: String { word }
}
