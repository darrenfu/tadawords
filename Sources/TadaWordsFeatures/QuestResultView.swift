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
    @State private var displayedEarnedStarCount = 0
    @State private var activeTempoDotCount = 0
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
                .foregroundStyle(Color.yellow)
                .shadow(
                    color: Color.orange.opacity(0.28),
                    radius: 6,
                    y: 3
                )
            Text("×")
                .font(
                    .system(
                        size: size * 0.72,
                        weight: .heavy,
                        design: .rounded
                    )
                )
                .foregroundStyle(theme.ink)

            VStack(spacing: max(3, size * 0.10)) {
                QuestResultFlipNumberCard(
                    number: displayedEarnedStarCount,
                    size: size,
                    ink: theme.ink,
                    accent: theme.secondary,
                    surface: theme.surface
                )

                HStack(spacing: max(3, size * 0.08)) {
                    ForEach(
                        0..<max(0, result.earnedStarCount),
                        id: \.self
                    ) { index in
                        Circle()
                            .fill(
                                index < activeTempoDotCount
                                    ? Color.yellow
                                    : theme.ink.opacity(0.13)
                            )
                            .frame(
                                width: max(4, size * 0.11),
                                height: max(4, size * 0.11)
                            )
                            .scaleEffect(
                                index < activeTempoDotCount ? 1 : 0.72
                            )
                            .animation(
                                .easeOut(
                                    duration:
                                        QuestResultStarCountAnimation
                                        .flipDurationSeconds
                                ),
                                value: activeTempoDotCount
                            )
                    }
                }
                .frame(minHeight: max(4, size * 0.11))
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityIdentifier("quest-result.star-count")
        .accessibilityLabel("\(result.earnedStarCount) stars earned")
    }

    private func revealResults() async {
        guard revealPhase == 0 else { return }
        let delay = reduceMotion ? 40 : 210

        for phase in 1...5 {
            try? await Task.sleep(for: .milliseconds(delay))
            guard !Task.isCancelled else { return }
            if phase == 2 {
                displayedEarnedStarCount =
                    QuestResultStarCountAnimation.initialDisplayedCount(
                        earnedCount: result.earnedStarCount,
                        reduceMotion: reduceMotion
                    )
                activeTempoDotCount =
                    reduceMotion ? result.earnedStarCount : 0
            }
            withAnimation(
                .easeOut(duration: reduceMotion ? 0.01 : TadaPrimitiveTokens.Motion.celebration)
            ) {
                revealPhase = phase
            }
            if phase == 2 {
                await revealEarnedStarCount()
            } else if phase == 5 {
                resultSummaryIsFocused = true
                announceForAccessibility(resultAccessibilitySummary)
            }
        }
    }

    private func revealEarnedStarCount() async {
        let timeline = QuestResultStarCountAnimation.timeline(
            earnedCount: result.earnedStarCount
        )
        guard !timeline.isEmpty else {
            displayedEarnedStarCount = 0
            activeTempoDotCount = 0
            return
        }

        if reduceMotion {
            displayedEarnedStarCount = result.earnedStarCount
            activeTempoDotCount = result.earnedStarCount
        }

        for step in timeline {
            guard !Task.isCancelled else { return }
            if !reduceMotion {
                withAnimation(
                    .easeInOut(
                        duration:
                            QuestResultStarCountAnimation.flipDurationSeconds
                    )
                ) {
                    displayedEarnedStarCount = step.displayedCount
                    activeTempoDotCount = step.activeDotCount
                }
            }
            await audioExperienceService.play(step.cue)
            try? await Task.sleep(
                for: .milliseconds(
                    reduceMotion
                        ? 40
                        : QuestResultStarCountAnimation.millisecondsPerFlip
                )
            )
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

enum QuestResultStarCountAnimation {
    static let millisecondsPerFlip = 120
    static let flipDurationSeconds = 0.12

    static func steps(earnedCount: Int) -> [Int] {
        guard earnedCount > 0 else { return [] }
        return Array(1...earnedCount)
    }

    static func initialDisplayedCount(
        earnedCount: Int,
        reduceMotion: Bool
    ) -> Int {
        guard earnedCount > 0 else { return 0 }
        return reduceMotion ? earnedCount : 1
    }

    static func timeline(
        earnedCount: Int
    ) -> [QuestResultStarCountAnimationStep] {
        steps(earnedCount: earnedCount).map { count in
            QuestResultStarCountAnimationStep(
                displayedCount: count,
                activeDotCount: count,
                cue: .star(index: count - 1)
            )
        }
    }

    static func totalDurationMilliseconds(earnedCount: Int) -> Int {
        steps(earnedCount: earnedCount).count * millisecondsPerFlip
    }
}

struct QuestResultStarCountAnimationStep: Equatable, Sendable {
    let displayedCount: Int
    let activeDotCount: Int
    let cue: FunctionalAudioCue
}

private struct QuestResultFlipNumberCard: View {
    let number: Int
    let size: CGFloat
    let ink: Color
    let accent: Color
    let surface: Color

    var body: some View {
        ZStack {
            RoundedRectangle(
                cornerRadius: max(8, size * 0.22),
                style: .continuous
            )
            .fill(surface.opacity(0.94))
            .overlay {
                RoundedRectangle(
                    cornerRadius: max(8, size * 0.22),
                    style: .continuous
                )
                .strokeBorder(accent.opacity(0.24), lineWidth: 1)
            }
            .shadow(color: accent.opacity(0.16), radius: 5, y: 3)

            ZStack {
                Text("\(number)")
                    .font(
                        .system(
                            size: size * 0.70,
                            weight: .heavy,
                            design: .rounded
                        )
                    )
                    .monospacedDigit()
                    .foregroundStyle(ink)
                    .id(number)
                    .transition(
                        .asymmetric(
                            insertion: .modifier(
                                active: QuestResultFlipModifier(
                                    angle: 88,
                                    opacity: 0
                                ),
                                identity: QuestResultFlipModifier(
                                    angle: 0,
                                    opacity: 1
                                )
                            ),
                            removal: .modifier(
                                active: QuestResultFlipModifier(
                                    angle: -88,
                                    opacity: 0
                                ),
                                identity: QuestResultFlipModifier(
                                    angle: 0,
                                    opacity: 1
                                )
                            )
                        )
                    )
            }
            .clipped()
        }
        .frame(
            minWidth: max(44, size * 1.12),
            minHeight: max(40, size * 0.92)
        )
        .animation(
            .easeInOut(
                duration: QuestResultStarCountAnimation.flipDurationSeconds
            ),
            value: number
        )
    }
}

private struct QuestResultFlipModifier: ViewModifier {
    let angle: Double
    let opacity: Double

    func body(content: Content) -> some View {
        content
            .rotation3DEffect(
                .degrees(angle),
                axis: (x: 1, y: 0, z: 0),
                perspective: 0.62
            )
            .opacity(opacity)
    }
}
