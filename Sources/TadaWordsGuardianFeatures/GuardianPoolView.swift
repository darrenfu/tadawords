import SwiftUI
import TadaWordsDesignSystem
import TadaWordsDomain

struct GuardianPoolView: View {
    let mode: LearningMode
    let words: [WordPrompt]
    let routeSettings: LearningRouteSettings
    let onBack: () -> Void
    let onAddWords: () -> Void
    let onPlay: (WordPrompt) -> Void
    let onDeactivate: (WordPrompt) -> Void

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: GuardianPrimitiveTokens.Spacing.large) {
                GuardianNavigationHeader(title: "\(mode.guardianTitle) Pool", onBack: onBack)

                GuardianCard {
                    HStack(spacing: GuardianPrimitiveTokens.Spacing.medium) {
                        Image(systemName: mode.guardianSymbol)
                            .font(.system(.title, design: .rounded, weight: .bold))
                            .foregroundStyle(GuardianSemanticTokens.accent(for: mode))
                            .frame(width: 48, height: 48)
                            .background(
                                GuardianSemanticTokens.accent(for: mode).opacity(0.10),
                                in: RoundedRectangle(
                                    cornerRadius: GuardianPrimitiveTokens.Radius.small,
                                    style: .continuous
                                )
                            )
                            .accessibilityHidden(true)

                        VStack(alignment: .leading, spacing: 3) {
                            Text("\(words.count) \(words.count == 1 ? "word" : "words")")
                                .font(.system(.title2, design: .rounded, weight: .bold))
                                .monospacedDigit()
                            Text(
                                "New \(routeSettings.newWordLimit) · Review \(routeSettings.reviewWordLimit) per quest"
                            )
                            .font(.system(.subheadline, design: .rounded, weight: .medium))
                            .foregroundStyle(GuardianSemanticTokens.secondaryForeground)
                        }

                        Spacer()
                    }
                    .accessibilityElement(children: .combine)
                    .accessibilityValue(
                        "\(routeSettings.newWordLimit) new words and \(routeSettings.reviewWordLimit) review words per quest"
                    )
                }

                Button(action: onAddWords) {
                    Label("Add words", systemImage: "plus")
                }
                .buttonStyle(
                    GuardianPrimaryButtonStyle(
                        tint: GuardianSemanticTokens.accent(for: mode)
                    ))

                VStack(alignment: .leading, spacing: GuardianPrimitiveTokens.Spacing.small) {
                    Text("All \(mode.guardianTitle) words")
                        .font(.system(.headline, design: .rounded, weight: .bold))

                    if words.isEmpty {
                        GuardianCard {
                            VStack(spacing: GuardianPrimitiveTokens.Spacing.small) {
                                Image(systemName: "tray")
                                    .font(.system(.title, design: .rounded, weight: .semibold))
                                    .foregroundStyle(GuardianSemanticTokens.secondaryForeground)
                                Text("No words in this pool yet.")
                                    .font(.system(.body, design: .rounded, weight: .medium))
                            }
                            .frame(maxWidth: .infinity)
                        }
                    } else {
                        LazyVStack(spacing: 0) {
                            ForEach(words, id: \.id) { prompt in
                                GuardianWordRow(
                                    prompt: prompt,
                                    onPlay: { onPlay(prompt) },
                                    onDeactivate: { onDeactivate(prompt) }
                                )
                                if prompt.id != words.last?.id {
                                    Divider()
                                        .padding(.leading, 52)
                                }
                            }
                        }
                        .padding(.horizontal, GuardianPrimitiveTokens.Spacing.medium)
                        .background(
                            GuardianSemanticTokens.surface,
                            in: RoundedRectangle(
                                cornerRadius: GuardianPrimitiveTokens.Radius.medium,
                                style: .continuous
                            ))

                        Label(
                            "Removed words leave practice but keep their learning history.",
                            systemImage: "archivebox"
                        )
                        .font(.system(.caption, design: .rounded, weight: .medium))
                        .foregroundStyle(GuardianSemanticTokens.secondaryForeground)
                    }
                }
            }
            .frame(maxWidth: 760, alignment: .leading)
            .guardianParentPageInsets()
            .frame(maxWidth: .infinity)
        }
    }
}

private struct GuardianWordRow: View {
    let prompt: WordPrompt
    let onPlay: () -> Void
    let onDeactivate: () -> Void

    var body: some View {
        HStack(spacing: GuardianPrimitiveTokens.Spacing.medium) {
            Text(prompt.displayText.prefix(1).uppercased())
                .font(.system(.headline, design: .rounded, weight: .bold))
                .foregroundStyle(GuardianSemanticTokens.accent(for: prompt.learningMode))
                .frame(width: 36, height: 36)
                .background(
                    GuardianSemanticTokens.accent(for: prompt.learningMode).opacity(0.10),
                    in: Circle()
                )
                .accessibilityHidden(true)

            Text(prompt.displayText)
                .font(.system(.body, design: .rounded, weight: .semibold))

            Spacer()

            Button(action: onPlay) {
                Image(systemName: "speaker.wave.2.fill")
                    .frame(
                        width: TadaPrimitiveTokens.TouchTarget.minimum,
                        height: TadaPrimitiveTokens.TouchTarget.minimum
                    )
            }
            .buttonStyle(.borderless)
            .foregroundStyle(GuardianSemanticTokens.accent(for: prompt.learningMode))
            .accessibilityLabel("Play \(prompt.displayText)")

            Menu {
                Button(role: .destructive, action: onDeactivate) {
                    Label("Remove from active pool", systemImage: "archivebox")
                }
            } label: {
                Image(systemName: "ellipsis.circle")
                    .frame(
                        width: TadaPrimitiveTokens.TouchTarget.minimum,
                        height: TadaPrimitiveTokens.TouchTarget.minimum
                    )
            }
            .foregroundStyle(GuardianSemanticTokens.secondaryForeground)
            .accessibilityLabel("More actions for \(prompt.displayText)")
        }
        .padding(.vertical, 13)
    }
}
