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
                                KidBackButton(
                                    theme: theme,
                                    destinationHint: "Returns to the Kid Lobby",
                                    accessibilityIdentifier: "quest-loading.back",
                                    action: onBack
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
