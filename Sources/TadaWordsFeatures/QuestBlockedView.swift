import SwiftUI
import TadaWordsDesignSystem
import TadaWordsDomain

struct QuestBlockedView: View {
    let mode: LearningMode
    let reason: QuestBlockReason
    let theme: TadaWorldTheme
    let onRecover: () -> Void
    let onBack: () -> Void

    var body: some View {
        TadaWorldBackground(theme: theme, sceneStyle: .quest) {
            GeometryReader { proxy in
                ScrollView {
                    VStack(spacing: TadaPrimitiveTokens.Spacing.medium) {
                        HStack {
                            Button(action: onBack) {
                                Label("Quests", systemImage: "chevron.left")
                                    .font(.system(.subheadline, design: .rounded, weight: .bold))
                            }
                            .buttonStyle(
                                TadaPrimaryButtonStyle(
                                    fill: theme.surface,
                                    foreground: theme.ink,
                                    isCompact: true
                                ))
                            Spacer()
                            TadaPill(
                                symbol: mode == .read ? "book.pages.fill" : "pencil.line",
                                text: mode.title,
                                tint: theme.primary
                            )
                        }

                        Spacer(minLength: 0)
                        TadaChildStatePanel(
                            theme: theme,
                            symbol: reason.symbol,
                            title: reason.title,
                            message: reason.message
                        ) {
                            Button(reason.recoveryTitle, action: onRecover)
                                .buttonStyle(TadaPrimaryButtonStyle(fill: theme.primary))
                        }
                        Spacer(minLength: 0)
                    }
                    .padding(TadaPrimitiveTokens.Spacing.large)
                    .frame(maxWidth: .infinity, minHeight: proxy.size.height)
                }
                .scrollIndicators(.hidden)
            }
        }
    }
}
