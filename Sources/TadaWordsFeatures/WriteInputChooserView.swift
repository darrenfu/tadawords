import SwiftUI
import TadaWordsDesignSystem
import TadaWordsDomain

/// A short child-facing fork inside the one shared Write quest.
/// Choosing either surface completes the same daily route (product rule B).
struct WriteInputChooserView: View {
    let theme: TadaWorldTheme
    let onSelect: (WriteQuestInputMethod) -> Void
    let onBack: () -> Void

    var body: some View {
        TadaWorldBackground(theme: theme, sceneStyle: .quest) {
            VStack(spacing: TadaPrimitiveTokens.Spacing.large) {
                header

                HStack(spacing: TadaPrimitiveTokens.Spacing.medium) {
                    TadaWorldMascot(theme: theme, pose: .encouraging, size: 64)
                    VStack(alignment: .leading, spacing: 4) {
                        Text("How do you want to spell?")
                            .font(.system(.largeTitle, design: .rounded, weight: .heavy))
                            .foregroundStyle(theme.ink)
                        Text("Either choice finishes today’s Write quest.")
                            .font(.system(.headline, design: .rounded, weight: .medium))
                            .foregroundStyle(theme.ink.opacity(0.65))
                    }
                }
                .accessibilityElement(children: .combine)

                ViewThatFits(in: .horizontal) {
                    HStack(spacing: TadaPrimitiveTokens.Spacing.large) {
                        choiceCards
                    }
                    VStack(spacing: TadaPrimitiveTokens.Spacing.medium) {
                        choiceCards
                    }
                }
                .frame(maxWidth: 900)

                Spacer(minLength: 0)
            }
            .padding(TadaPrimitiveTokens.Spacing.large)
        }
    }

    private var header: some View {
        HStack {
            Button(action: onBack) {
                Label("Quests", systemImage: "chevron.left")
                    .font(.system(.headline, design: .rounded, weight: .bold))
                    .frame(minHeight: TadaPrimitiveTokens.TouchTarget.minimum)
            }
            .buttonStyle(.plain)
            .foregroundStyle(theme.ink.opacity(0.74))
            .accessibilityIdentifier("write-method.back")

            Spacer()
        }
    }

    @ViewBuilder
    private var choiceCards: some View {
        choiceCard(
            method: .handwriting,
            title: "Write by Hand",
            subtitle: "Draw every letter",
            symbol: "pencil.and.scribble"
        )
        choiceCard(
            method: .letterKeyboard,
            title: "Spell with Letters",
            subtitle: "Tap A to Z",
            symbol: "character.cursor.ibeam"
        )
    }

    private func choiceCard(
        method: WriteQuestInputMethod,
        title: String,
        subtitle: String,
        symbol: String
    ) -> some View {
        Button {
            onSelect(method)
        } label: {
            VStack(spacing: TadaPrimitiveTokens.Spacing.medium) {
                ZStack {
                    Circle()
                        .fill(theme.primary.opacity(0.14))
                    Image(systemName: symbol)
                        .font(.system(size: 58, weight: .bold))
                        .foregroundStyle(theme.primary)
                }
                .frame(width: 112, height: 112)

                Text(title)
                    .font(.system(.title, design: .rounded, weight: .heavy))
                    .foregroundStyle(theme.ink)
                Text(subtitle)
                    .font(.system(.headline, design: .rounded, weight: .semibold))
                    .foregroundStyle(theme.ink.opacity(0.62))
            }
            .frame(maxWidth: .infinity, minHeight: 250)
            .padding(TadaPrimitiveTokens.Spacing.large)
            .background(Color.white.opacity(0.94))
            .clipShape(
                RoundedRectangle(
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
            .shadow(color: theme.primary.opacity(0.20), radius: 14, y: 8)
        }
        .buttonStyle(TadaTactileCardButtonStyle())
        .frame(minWidth: 300, maxWidth: 420)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(title)
        .accessibilityHint("Uses (subtitle.lowercased()) for this Write quest")
        .accessibilityIdentifier("write-method.\(method.rawValue)")
    }
}
