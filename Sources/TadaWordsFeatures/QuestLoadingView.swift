import SwiftUI
import TadaWordsDesignSystem
import TadaWordsDomain

struct QuestLoadingView: View {
    let mode: LearningMode
    let phase: QuestLoadingPhase
    let theme: TadaWorldTheme
    let onBack: () -> Void

    var body: some View {
        TadaWorldBackground(theme: theme, sceneStyle: .quest) {
            GeometryReader { proxy in
                ScrollView {
                    VStack(spacing: TadaPrimitiveTokens.Spacing.large) {
                        if phase.allowsBackNavigation {
                            HStack {
                                Button(action: onBack) {
                                    Label("Quests", systemImage: "chevron.left")
                                        .font(
                                            .system(
                                                .subheadline,
                                                design: .rounded,
                                                weight: .bold
                                            )
                                        )
                                }
                                .buttonStyle(
                                    TadaPrimaryButtonStyle(
                                        fill: theme.surface,
                                        foreground: theme.ink,
                                        isCompact: true
                                    )
                                )
                                Spacer()
                            }
                        }

                        Spacer(minLength: 0)
                        TadaChildStatePanel(
                            theme: theme,
                            symbol: mode == .read ? "book.pages.fill" : "pencil.line",
                            title: phase.message,
                            message: mode == .read ? "Read quest" : "Write quest",
                            showsProgress: true
                        )
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
