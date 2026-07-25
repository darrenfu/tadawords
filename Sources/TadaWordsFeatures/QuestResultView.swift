import SwiftUI
import TadaWordsDesignSystem
import TadaWordsDomain

struct QuestResultView: View {
    let result: QuestResultViewState
    let theme: TadaWorldTheme
    let audioExperienceService: any AudioExperienceService
    let onReplay: () -> Void
    let onContinue: () -> Void

    init(
        result: QuestResultViewState,
        theme: TadaWorldTheme,
        audioExperienceService: any AudioExperienceService =
            SilentAudioExperienceService(),
        onReplay: @escaping () -> Void,
        onContinue: @escaping () -> Void
    ) {
        self.result = result
        self.theme = theme
        self.audioExperienceService = audioExperienceService
        self.onReplay = onReplay
        self.onContinue = onContinue
    }

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.verticalSizeClass) private var verticalSizeClass
    @State private var revealPhase = 0
    @AccessibilityFocusState private var resultSummaryIsFocused: Bool

    var body: some View {
        TadaWorldBackground(theme: theme, sceneStyle: .celebration) {
            switch QuestResultLayoutMode.resolve(
                hasCompactHeight: verticalSizeClass == .compact
            ) {
            case .standard:
                standardContent
            case .compactLandscape:
                compactLandscapeContent
            }
        }
        .task {
            await revealResults()
        }
        .sensoryFeedback(.success, trigger: revealPhase == 4)
    }

    private var standardContent: some View {
        ScrollView {
            VStack(spacing: TadaPrimitiveTokens.Spacing.large) {
                completionHeader

                ViewThatFits(in: .horizontal) {
                    HStack(
                        alignment: .center,
                        spacing: TadaPrimitiveTokens.Spacing.xLarge
                    ) {
                        achievementPanel
                        rewardPanel
                    }

                    VStack(spacing: TadaPrimitiveTokens.Spacing.large) {
                        achievementPanel
                        rewardPanel
                    }
                }
                .frame(maxWidth: 900)

                resultActions
            }
            .frame(maxWidth: .infinity)
            .padding(.horizontal, TadaPrimitiveTokens.Spacing.large)
            .padding(.vertical, TadaPrimitiveTokens.Spacing.xLarge)
        }
    }

    private var compactLandscapeContent: some View {
        VStack(spacing: TadaPrimitiveTokens.Spacing.medium) {
            compactCompletionHeader

            HStack(alignment: .center, spacing: TadaPrimitiveTokens.Spacing.medium) {
                compactAchievementPanel
                    .layoutPriority(2)
                compactRewardPanel
                    .layoutPriority(1)
            }
            .frame(maxWidth: 900)

            resultActions
                .frame(maxWidth: 680)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(.horizontal, TadaPrimitiveTokens.Spacing.large)
        .padding(.vertical, TadaPrimitiveTokens.Spacing.small)
    }

    @ViewBuilder
    private var resultActions: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: TadaPrimitiveTokens.Spacing.medium) {
                actionButtons
            }
            VStack(spacing: TadaPrimitiveTokens.Spacing.small) {
                actionButtons
            }
        }
        .opacity(revealPhase >= 5 ? 1 : 0)
        .offset(y: revealPhase >= 5 ? 0 : 8)
        .allowsHitTesting(revealPhase >= 5)
        .accessibilityHidden(revealPhase < 5)
    }

    @ViewBuilder
    private var actionButtons: some View {
        if result.showsReplayAction {
            Button(action: onReplay) {
                Label(result.replayActionLabel, systemImage: "arrow.clockwise")
            }
            .buttonStyle(TadaPrimaryButtonStyle(fill: theme.secondary))
            .accessibilityHint("Practices only the words that need another try")
            .accessibilityIdentifier("quest-result.replay")
        }

        Button("Back to quests", action: onContinue)
            .buttonStyle(TadaPrimaryButtonStyle(fill: theme.primary))
    }

    private var completionHeader: some View {
        VStack(spacing: 0) {
            HStack(spacing: TadaPrimitiveTokens.Spacing.medium) {
                TadaWorldMascot(
                    theme: theme,
                    pose: .cheering,
                    size: TadaChildScaleTokens.Result.mascotRegular
                )
                ZStack {
                    Circle()
                        .fill(TadaPrimitiveTokens.ColorValue.success)
                    Image(systemName: "checkmark")
                        .font(.system(size: 38, weight: .heavy))
                        .foregroundStyle(Color.white)
                }
                .frame(width: 76, height: 76)
                .shadow(
                    color: TadaPrimitiveTokens.ColorValue.success.opacity(0.24),
                    radius: 12,
                    y: 6
                )
            }
            .accessibilityHidden(true)

        }
        .opacity(revealPhase >= 1 ? 1 : 0)
        .offset(y: revealPhase >= 1 ? 0 : 8)
        .accessibilityHidden(revealPhase < 1)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(resultAccessibilitySummary)
        .accessibilityFocused($resultSummaryIsFocused)
    }

    private var compactCompletionHeader: some View {
        HStack(spacing: TadaPrimitiveTokens.Spacing.medium) {
            TadaWorldMascot(
                theme: theme,
                pose: .cheering,
                size: TadaChildScaleTokens.Result.mascotCompact
            )

            ZStack {
                Circle()
                    .fill(TadaPrimitiveTokens.ColorValue.success)
                Image(systemName: "checkmark")
                    .font(.system(size: 27, weight: .heavy))
                    .foregroundStyle(Color.white)
            }
            .frame(width: 56, height: 56)
            .shadow(
                color: TadaPrimitiveTokens.ColorValue.success.opacity(0.24),
                radius: 10,
                y: 5
            )
            .accessibilityHidden(true)

        }
        .opacity(revealPhase >= 1 ? 1 : 0)
        .offset(y: revealPhase >= 1 ? 0 : 6)
        .accessibilityHidden(revealPhase < 1)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(resultAccessibilitySummary)
        .accessibilityFocused($resultSummaryIsFocused)
    }

    private var achievementPanel: some View {
        TadaPanel(theme: theme) {
            VStack(spacing: TadaPrimitiveTokens.Spacing.medium) {
                earnedStarSummary(size: 44)
                    .opacity(revealPhase >= 2 ? 1 : 0)
                    .accessibilityHidden(revealPhase < 2)

                HStack(spacing: 12) {
                    ResultMetric(symbol: "checkmark.circle.fill", value: "Complete", theme: theme)
                    accuracyMetric
                    ResultMetric(
                        symbol: "gauge.with.dots.needle.50percent", value: result.paceLabel,
                        theme: theme)
                }
                .opacity(revealPhase >= 3 ? 1 : 0)
                .accessibilityHidden(revealPhase < 3)

                Divider()
                    .overlay(theme.ink.opacity(0.12))
                    .opacity(revealPhase >= 3 ? 1 : 0)
                    .accessibilityHidden(true)

                HStack(alignment: .firstTextBaseline, spacing: 7) {
                    Text("\(result.points)")
                        .font(.system(size: 48, weight: .heavy, design: .rounded))
                        .monospacedDigit()
                    Text("points")
                        .font(.system(.headline, design: .rounded, weight: .semibold))
                        .foregroundStyle(theme.ink.opacity(0.62))
                }
                .accessibilityElement(children: .combine)
                .opacity(revealPhase >= 3 ? 1 : 0)
                .accessibilityHidden(revealPhase < 3)
            }
            .frame(minWidth: 340, maxWidth: 420)
        }
        .opacity(revealPhase >= 2 ? 1 : 0)
        .scaleEffect(revealPhase >= 2 ? 1 : 0.96)
        .accessibilityHidden(revealPhase < 2)
    }

    private var rewardPanel: some View {
        TadaPanel(theme: theme) {
            VStack(spacing: TadaPrimitiveTokens.Spacing.medium) {
                if result.showsNewCollectible {
                    TadaRewardBadge(
                        theme: theme,
                        isUnlocked: revealPhase >= 4,
                        size: TadaChildScaleTokens.Result.rewardRegular,
                        symbol: rewardSymbol
                    )
                } else {
                    practiceStatusSymbol(size: TadaChildScaleTokens.Result.rewardRegular)
                }

                if result.showsNewCollectible {
                    TadaRewardShelf(
                        theme: theme,
                        highlightedCount: revealPhase >= 4 ? 1 : 0
                    )
                }

                Text(
                    result.showsNewCollectible
                        ? rewardDisplayName
                        : practiceStatusTitle
                )
                .font(.system(.title2, design: .rounded, weight: .bold))
                .multilineTextAlignment(.center)
            }
            .frame(minWidth: 230, maxWidth: 260)
        }
        .opacity(revealPhase >= 4 ? 1 : 0)
        .scaleEffect(revealPhase >= 4 ? 1 : 0.92)
        .accessibilityHidden(revealPhase < 4)
    }

    private var compactAchievementPanel: some View {
        TadaPanel(theme: theme) {
            VStack(spacing: TadaPrimitiveTokens.Spacing.small) {
                HStack(spacing: TadaPrimitiveTokens.Spacing.medium) {
                    earnedStarSummary(size: 30)
                        .opacity(revealPhase >= 2 ? 1 : 0)
                        .accessibilityHidden(revealPhase < 2)
                }

                HStack(spacing: TadaPrimitiveTokens.Spacing.small) {
                    ResultMetric(
                        symbol: "checkmark.circle.fill",
                        value: "Complete",
                        theme: theme,
                        isCompact: true
                    )
                    accuracyMetric(isCompact: true)
                    ResultMetric(
                        symbol: "gauge.with.dots.needle.50percent",
                        value: result.paceLabel,
                        theme: theme,
                        isCompact: true
                    )
                }
                .opacity(revealPhase >= 3 ? 1 : 0)
                .accessibilityHidden(revealPhase < 3)

                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text("\(result.points)")
                        .font(.system(size: 36, weight: .heavy, design: .rounded))
                        .monospacedDigit()
                    Text("points")
                        .font(.system(.subheadline, design: .rounded, weight: .semibold))
                        .foregroundStyle(theme.ink.opacity(0.62))
                    Spacer()
                }
                .accessibilityElement(children: .combine)
                .opacity(revealPhase >= 3 ? 1 : 0)
                .accessibilityHidden(revealPhase < 3)
            }
            .frame(minWidth: 430, maxWidth: 540)
        }
        .opacity(revealPhase >= 2 ? 1 : 0)
        .scaleEffect(revealPhase >= 2 ? 1 : 0.96)
        .accessibilityHidden(revealPhase < 2)
    }

    private var compactRewardPanel: some View {
        TadaPanel(theme: theme) {
            HStack(spacing: TadaPrimitiveTokens.Spacing.medium) {
                if result.showsNewCollectible {
                    TadaRewardBadge(
                        theme: theme,
                        isUnlocked: revealPhase >= 4,
                        size: TadaChildScaleTokens.Result.rewardCompact,
                        symbol: rewardSymbol
                    )
                } else {
                    practiceStatusSymbol(size: TadaChildScaleTokens.Result.rewardCompact)
                }

                VStack(alignment: .leading, spacing: 4) {
                    Text(
                        result.showsNewCollectible
                            ? rewardDisplayName
                            : practiceStatusTitle
                    )
                    .font(.system(.headline, design: .rounded, weight: .bold))
                    .lineLimit(2)
                    .minimumScaleFactor(0.82)
                    if result.showsNewCollectible {
                        TadaRewardShelf(
                            theme: theme,
                            highlightedCount: revealPhase >= 4 ? 1 : 0,
                            isCompact: true
                        )
                    }
                }
            }
            .frame(minWidth: 230, maxWidth: 290)
        }
        .opacity(revealPhase >= 4 ? 1 : 0)
        .scaleEffect(revealPhase >= 4 ? 1 : 0.92)
        .accessibilityHidden(revealPhase < 4)
    }

    private func practiceStatusSymbol(size: CGFloat) -> some View {
        ZStack {
            Circle()
                .fill(theme.primary.opacity(0.12))
            Image(
                systemName: result.showsReplayAction
                    ? "arrow.clockwise.circle.fill"
                    : "checkmark.seal.fill"
            )
            .font(.system(size: size * 0.62, weight: .bold))
            .foregroundStyle(theme.primary)
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }

    private func earnedStarSummary(size: CGFloat) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "star.fill")
                .font(.system(size: size, weight: .bold))
                .foregroundStyle(theme.secondary)
                .shadow(
                    color: theme.secondary.opacity(0.28),
                    radius: 6,
                    y: 3
                )
            Text("× \(result.earnedStarCount)")
                .font(
                    .system(
                        size: size * 0.72,
                        weight: .heavy,
                        design: .rounded
                    )
                )
                .monospacedDigit()
                .foregroundStyle(theme.ink)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(result.earnedStarCount) stars earned")
    }

    private func revealResults() async {
        guard revealPhase == 0 else { return }
        let delay = reduceMotion ? 40 : 210

        for phase in 1...5 {
            try? await Task.sleep(for: .milliseconds(delay))
            guard !Task.isCancelled else { return }
            withAnimation(
                .easeOut(duration: reduceMotion ? 0.01 : TadaPrimitiveTokens.Motion.celebration)
            ) {
                revealPhase = phase
            }
            if phase == 2 {
                for starIndex in 0..<result.earnedStarCount {
                    await audioExperienceService.play(.star(index: starIndex))
                    try? await Task.sleep(for: .milliseconds(reduceMotion ? 40 : 105))
                }
            } else if phase == 4 {
                await audioExperienceService.play(.reward)
            } else if phase == 5 {
                resultSummaryIsFocused = true
                announceForAccessibility(resultAccessibilitySummary)
            }
        }
    }

    private var accuracyMetric: some View {
        accuracyMetric(isCompact: false)
    }

    private func accuracyMetric(isCompact: Bool) -> some View {
        if let percentage = result.firstTryAccuracyPercentage {
            return ResultMetric(
                symbol: "scope",
                value: "\(percentage)%",
                caption: "First try",
                theme: theme,
                isCompact: isCompact
            )
        }
        return ResultMetric(
            symbol: "minus.circle.fill",
            value: "Not scored",
            theme: theme,
            isCompact: isCompact
        )
    }

    private var resultAccessibilitySummary: String {
        let accuracySummary =
            result.firstTryAccuracyPercentage.map {
                "First try accuracy \($0) percent."
            } ?? "First try accuracy not scored."
        return
            "\(completionTitle). \(result.earnedStarCount) stars earned. \(result.points) points. \(accuracySummary) \(result.paceLabel)."
    }

    private var completionTitle: String {
        result.runKind == .practiceAgain
            ? "Practice complete"
            : "Quest complete"
    }

    private var practiceStatusTitle: String {
        result.showsReplayAction ? "Tricky words ready" : "All words are strong"
    }

    private var rewardDisplayName: String {
        result.rewardGrant?.item.displayName ?? theme.rewardName
    }

    private var rewardSymbol: String {
        result.rewardGrant?.item.presentationSymbol ?? theme.rewardSymbol
    }
}

private struct ResultMetric: View {
    let symbol: String
    let value: String
    var caption: String?
    let theme: TadaWorldTheme
    var isCompact = false

    var body: some View {
        VStack(spacing: 4) {
            Image(systemName: symbol)
                .font(.system(.title3, design: .rounded, weight: .bold))
                .foregroundStyle(theme.primary)
                .accessibilityHidden(true)
            Text(value)
                .font(.system(.caption, design: .rounded, weight: .bold))
                .lineLimit(1)
            if let caption {
                Text(caption)
                    .font(TadaTypography.metricCaption)
                    .foregroundStyle(TadaSemanticColors.secondaryOnSurface(for: theme))
            }
        }
        .frame(maxWidth: .infinity, minHeight: isCompact ? 50 : 66)
        .padding(.horizontal, isCompact ? 5 : 8)
        .background(
            theme.primary.opacity(0.08),
            in: RoundedRectangle(
                cornerRadius: TadaPrimitiveTokens.Radius.small,
                style: .continuous
            )
        )
        .accessibilityElement(children: .combine)
    }
}

enum QuestResultLayoutMode: Equatable {
    case standard
    case compactLandscape

    static func resolve(hasCompactHeight: Bool) -> QuestResultLayoutMode {
        hasCompactHeight ? .compactLandscape : .standard
    }
}
