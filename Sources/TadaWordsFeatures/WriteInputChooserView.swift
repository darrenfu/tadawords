import SwiftUI
import TadaWordsDesignSystem
import TadaWordsDomain

enum WriteInputChooserPresentation {
    static let title = "Spell Mode"
    static let handwritingTitle = "Handwriting"
    static let typingTitle = "Typing"
}

/// A short child-facing fork inside the one shared Write quest.
/// Choosing either surface completes the same daily route (product rule B).
struct WriteInputChooserView: View {
    @Environment(\.verticalSizeClass) private var verticalSizeClass

    let theme: TadaWorldTheme
    let onSelect: (WriteQuestInputMethod) -> Void
    let onBack: () -> Void

    var body: some View {
        TadaWorldBackground(theme: theme, sceneStyle: .quest) {
            VStack(spacing: isCompactHeight ? 10 : TadaPrimitiveTokens.Spacing.large) {
                header

                HStack(spacing: TadaPrimitiveTokens.Spacing.medium) {
                    TadaWorldMascot(
                        theme: theme,
                        pose: .encouraging,
                        size: isCompactHeight ? 48 : 64
                    )
                    Text(WriteInputChooserPresentation.title)
                        .font(.system(.largeTitle, design: .rounded, weight: .heavy))
                        .foregroundStyle(theme.ink)
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
            .padding(.horizontal, TadaPrimitiveTokens.Spacing.large)
            .padding(.vertical, isCompactHeight ? 8 : TadaPrimitiveTokens.Spacing.large)
        }
    }

    private var isCompactHeight: Bool {
        verticalSizeClass == .compact
    }

    private var header: some View {
        HStack {
            KidBackButton(
                theme: theme,
                destinationHint: "Returns to the Kid Lobby",
                accessibilityIdentifier: "write-method.back",
                action: onBack
            )

            Spacer()
        }
    }

    @ViewBuilder
    private var choiceCards: some View {
        choiceCard(
            method: .handwriting,
            title: WriteInputChooserPresentation.handwritingTitle,
            hint: "Draw each letter by hand",
            symbol: "pencil.and.scribble"
        )
        choiceCard(
            method: .letterKeyboard,
            title: WriteInputChooserPresentation.typingTitle,
            hint: "Build the word with letter keys",
            symbol: "character.cursor.ibeam"
        )
    }

    private func choiceCard(
        method: WriteQuestInputMethod,
        title: String,
        hint: String,
        symbol: String
    ) -> some View {
        Button {
            onSelect(method)
        } label: {
            VStack(spacing: isCompactHeight ? 8 : TadaPrimitiveTokens.Spacing.medium) {
                ZStack {
                    Circle()
                        .fill(theme.primary.opacity(0.14))
                    Image(systemName: symbol)
                        .font(.system(size: isCompactHeight ? 42 : 58, weight: .bold))
                        .foregroundStyle(theme.primary)
                }
                .frame(
                    width: isCompactHeight ? 78 : 112,
                    height: isCompactHeight ? 78 : 112
                )

                Text(title)
                    .font(.system(.title, design: .rounded, weight: .heavy))
                    .foregroundStyle(theme.ink)
            }
            .frame(maxWidth: .infinity, minHeight: isCompactHeight ? 154 : 220)
            .padding(
                isCompactHeight
                    ? TadaPrimitiveTokens.Spacing.medium : TadaPrimitiveTokens.Spacing.large
            )
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
        .accessibilityHint(hint)
        .accessibilityIdentifier("write-method.\(method.rawValue)")
    }
}
