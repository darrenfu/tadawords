import SwiftUI
import TadaWordsDesignSystem
import TadaWordsDomain

struct ChildLobbyView: View {
    let profile: KidProfile
    let theme: TadaWorldTheme
    let readAvailability: QuestAvailability
    let writeAvailability: QuestAvailability
    let readStatus: TodayQuestRouteStatus
    let writeStatus: TodayQuestRouteStatus
    let onChooseProfile: () -> Void
    let onOpenCalendar: () -> Void
    let onOpenWorlds: () -> Void
    let onOpenCollection: () -> Void
    let onStart: (LearningMode) -> Void

    @Environment(\.verticalSizeClass) private var verticalSizeClass

    private var isCompactHeight: Bool {
        verticalSizeClass == .compact
    }

    var body: some View {
        TadaWorldBackground(theme: theme, sceneStyle: .lobby) {
            GeometryReader { proxy in
                ScrollView {
                    VStack(spacing: isCompactHeight ? 10 : TadaPrimitiveTokens.Spacing.large) {
                        lobbyHeader

                        worldWelcome

                        ViewThatFits(in: .horizontal) {
                            HStack(
                                spacing: isCompactHeight
                                    ? 14 : TadaPrimitiveTokens.Spacing.large
                            ) {
                                questCards
                            }

                            VStack(spacing: TadaPrimitiveTokens.Spacing.medium) {
                                questCards
                            }
                        }
                        .frame(maxWidth: 920)

                        rewardPreview
                    }
                    .padding(.horizontal, TadaPrimitiveTokens.Spacing.large)
                    .padding(.vertical, isCompactHeight ? 8 : TadaPrimitiveTokens.Spacing.medium)
                    .frame(
                        maxWidth: .infinity,
                        minHeight: proxy.size.height,
                        alignment: .top
                    )
                }
                .scrollIndicators(.hidden)
            }
        }
    }

    @ViewBuilder
    private var questCards: some View {
        QuestEntranceCard(
            mode: .read,
            theme: theme,
            availability: readAvailability,
            status: readStatus,
            isCompact: isCompactHeight,
            action: { onStart(.read) }
        )
        QuestEntranceCard(
            mode: .write,
            theme: theme,
            availability: writeAvailability,
            status: writeStatus,
            isCompact: isCompactHeight,
            action: { onStart(.write) }
        )
    }

    private var lobbyHeader: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: TadaPrimitiveTokens.Spacing.medium) {
                playersButton
                Spacer()
                worldsButton
                calendarButton
                worldPill
            }

            VStack(spacing: TadaPrimitiveTokens.Spacing.small) {
                HStack(spacing: TadaPrimitiveTokens.Spacing.medium) {
                    playersButton
                    Spacer()
                    worldsButton
                    calendarButton
                }
                worldPill
            }
        }
    }

    private var playersButton: some View {
        Button(action: onChooseProfile) {
            Label("Players", systemImage: "person.2.fill")
                .font(.system(.subheadline, design: .rounded, weight: .bold))
        }
        .buttonStyle(
            TadaPrimaryButtonStyle(
                fill: theme.surface,
                foreground: theme.ink,
                isCompact: true
            ))
    }

    private var calendarButton: some View {
        Button(action: onOpenCalendar) {
            Label("Calendar", systemImage: "calendar")
                .font(.system(.subheadline, design: .rounded, weight: .bold))
        }
        .buttonStyle(
            TadaPrimaryButtonStyle(
                fill: theme.surface,
                foreground: theme.ink,
                isCompact: true
            )
        )
        .accessibilityHint("Shows this month’s completed quests")
    }

    private var worldsButton: some View {
        Button(action: onOpenWorlds) {
            Label("Worlds", systemImage: "globe.americas.fill")
                .font(.system(.subheadline, design: .rounded, weight: .bold))
        }
        .buttonStyle(
            TadaPrimaryButtonStyle(
                fill: theme.surface,
                foreground: theme.ink,
                isCompact: true
            )
        )
        .accessibilityHint("Preview or enter an unlocked world")
    }

    private var worldPill: some View {
        TadaPill(symbol: theme.motifSymbol, text: theme.name, tint: theme.primary)
    }

    private var worldWelcome: some View {
        HStack(spacing: isCompactHeight ? 12 : TadaPrimitiveTokens.Spacing.medium) {
            TadaWorldMascot(
                theme: theme,
                pose: .encouraging,
                size: isCompactHeight ? 56 : 82
            )

            VStack(alignment: .leading, spacing: 2) {
                Text("Ready, \(profile.displayName)?")
                    .font(
                        .system(
                            isCompactHeight ? .title2 : .largeTitle,
                            design: .rounded,
                            weight: .heavy
                        )
                    )
                    .lineLimit(1)
                Text("Choose today’s quest.")
                    .font(
                        .system(
                            isCompactHeight ? .subheadline : .title3,
                            design: .rounded,
                            weight: .medium
                        )
                    )
                    .foregroundStyle(theme.ink.opacity(0.68))
            }
        }
        .padding(.horizontal, isCompactHeight ? 16 : 20)
        .padding(.vertical, isCompactHeight ? 5 : 8)
        .background(theme.surface.opacity(0.58), in: Capsule())
        .accessibilityElement(children: .combine)
    }

    private var rewardPreview: some View {
        Button(action: onOpenCollection) {
            HStack(spacing: isCompactHeight ? 10 : TadaPrimitiveTokens.Spacing.medium) {
                TadaRewardBadge(
                    theme: theme,
                    isUnlocked: false,
                    size: isCompactHeight ? 46 : 60
                )
                VStack(alignment: .leading, spacing: 3) {
                    Text("Collection")
                        .font(.system(.caption, design: .rounded, weight: .semibold))
                        .foregroundStyle(theme.ink.opacity(0.64))
                    Text("See your world treasures")
                        .font(.system(.headline, design: .rounded, weight: .bold))
                        .lineLimit(1)
                }

                TadaRewardShelf(
                    theme: theme,
                    highlightedCount: 0,
                    isCompact: isCompactHeight,
                    visibleLimit: isCompactHeight ? 2 : 3
                )
            }
            .padding(.horizontal, isCompactHeight ? 12 : 18)
            .padding(.vertical, isCompactHeight ? 5 : 10)
            .background(theme.surface.opacity(0.72), in: Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
        .accessibilityHint("Opens your world collection")
    }
}

private struct QuestEntranceCard: View {
    let mode: LearningMode
    let theme: TadaWorldTheme
    let availability: QuestAvailability
    let status: TodayQuestRouteStatus
    let isCompact: Bool
    let action: () -> Void

    private var tokens: TadaQuestEntranceTokens {
        switch mode {
        case .read:
            .read(in: theme)
        case .write:
            .write(in: theme)
        }
    }

    private var blockReason: QuestBlockReason? {
        guard case .blocked(let reason) = availability else { return nil }
        return reason
    }

    private var routeSubtitle: String {
        status.action == .practiceAgain ? "Practice Again" : mode.instruction
    }

    var body: some View {
        Button(action: action) {
            HStack(spacing: isCompact ? 14 : TadaPrimitiveTokens.Spacing.large) {
                entranceIcon

                VStack(alignment: .leading, spacing: 5) {
                    Text(mode.title)
                        .font(
                            .system(
                                size: isCompact ? 32 : 38,
                                weight: .heavy,
                                design: .rounded
                            )
                        )
                        .foregroundStyle(theme.ink)
                    Text(routeSubtitle)
                        .font(.system(.headline, design: .rounded, weight: .semibold))
                        .foregroundStyle(theme.ink.opacity(0.65))

                    if status.action == .practiceAgain, blockReason == nil {
                        HStack(spacing: 8) {
                            Label(
                                "\(status.completedPoints ?? 0) pts",
                                systemImage: "sparkles"
                            )
                            Label(
                                "\(status.completedStars?.count ?? 0) stars",
                                systemImage: "star.fill"
                            )
                        }
                        .font(.system(.caption, design: .rounded, weight: .bold))
                        .foregroundStyle(tokens.accent)
                    }

                    if let blockReason {
                        Label(blockReason.title, systemImage: "exclamationmark.circle.fill")
                            .font(.system(.caption, design: .rounded, weight: .bold))
                            .foregroundStyle(TadaPrimitiveTokens.ColorValue.warning)
                            .padding(.top, 3)
                    }
                }

                Spacer(minLength: 4)

                ZStack {
                    Circle()
                        .fill(tokens.accent.opacity(0.13))
                    Image(systemName: "arrow.right")
                        .font(.system(.headline, design: .rounded, weight: .heavy))
                        .foregroundStyle(tokens.accent)
                }
                .frame(width: isCompact ? 34 : 40, height: isCompact ? 34 : 40)
                .accessibilityHidden(true)
            }
            .frame(maxWidth: .infinity, minHeight: isCompact ? 112 : 142)
            .padding(.horizontal, isCompact ? 16 : TadaPrimitiveTokens.Spacing.large)
            .background(
                RoundedRectangle(
                    cornerRadius: TadaPrimitiveTokens.Radius.large,
                    style: .continuous
                )
                .fill(Color.white.opacity(0.94))
                .overlay {
                    RoundedRectangle(
                        cornerRadius: TadaPrimitiveTokens.Radius.large,
                        style: .continuous
                    )
                    .fill(
                        LinearGradient(
                            colors: [tokens.accent.opacity(0.03), tokens.accent.opacity(0.16)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                }
            )
            .overlay {
                RoundedRectangle(
                    cornerRadius: TadaPrimitiveTokens.Radius.large,
                    style: .continuous
                )
                .strokeBorder(Color.white.opacity(0.72), lineWidth: 2)
            }
            .overlay(alignment: .bottom) {
                modePattern
                    .padding(.horizontal, 24)
                    .offset(y: TadaPrimitiveTokens.Depth.tactileLip * 0.35)
            }
            .shadow(
                color: tokens.accent.opacity(0.24),
                radius: TadaPrimitiveTokens.Depth.cardShadowRadius,
                y: TadaPrimitiveTokens.Depth.cardShadowY
            )
            .opacity(blockReason == nil ? 1 : 0.78)
        }
        .buttonStyle(TadaTactileCardButtonStyle())
        .frame(minWidth: isCompact ? 300 : 320, maxWidth: 448)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityLabel)
        .accessibilityHint(
            blockReason == nil ? "Starts a separate \(mode.title) quest" : "Opens help")
    }

    @ViewBuilder
    private var entranceIcon: some View {
        TadaModeMark(tokens: tokens, size: isCompact ? 76 : 96)
    }

    @ViewBuilder
    private var modePattern: some View {
        switch mode {
        case .read:
            HStack(spacing: 5) {
                ForEach(0..<5, id: \.self) { index in
                    Capsule()
                        .fill(tokens.accent)
                        .frame(width: 15, height: CGFloat(4 + (index % 3) * 3))
                }
            }
            .frame(maxWidth: .infinity)
        case .write:
            HStack(spacing: 8) {
                ForEach(0..<5, id: \.self) { _ in
                    Capsule()
                        .fill(tokens.accent)
                        .frame(maxWidth: 42, minHeight: 6, maxHeight: 6)
                }
            }
        }
    }

    private var accessibilityLabel: String {
        if let blockReason {
            return "\(mode.title) quest. \(blockReason.title)."
        }
        if status.action == .practiceAgain {
            return "\(mode.title) quest. Practice Again."
        }
        return "Start \(mode.title) quest. \(mode.instruction)"
    }
}
