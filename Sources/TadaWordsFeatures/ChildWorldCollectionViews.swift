import SwiftUI
import TadaWordsDesignSystem
import TadaWordsDomain

struct ChildWorldPickerView: View {
    let profile: KidProfile
    let progression: WorldProgression?
    let onSelect: (WorldTheme) -> Void
    let onClose: () -> Void

    private let columns = [
        GridItem(.adaptive(minimum: 230), spacing: TadaPrimitiveTokens.Spacing.medium)
    ]

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: TadaPrimitiveTokens.Spacing.large) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Choose a World")
                            .font(.system(.largeTitle, design: .rounded, weight: .heavy))
                        Text(progressText)
                            .font(.system(.body, design: .rounded, weight: .semibold))
                            .foregroundStyle(TadaPrimitiveTokens.ColorValue.softInk)
                    }

                    LazyVGrid(columns: columns, spacing: TadaPrimitiveTokens.Spacing.medium) {
                        ForEach(orderedStates, id: \.world) { state in
                            worldCard(state)
                        }
                    }
                }
                .padding(TadaPrimitiveTokens.Spacing.large)
                .frame(maxWidth: 980, alignment: .leading)
                .frame(maxWidth: .infinity)
            }
            .background(TadaPrimitiveTokens.ColorValue.neutralSky.opacity(0.36))
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close", action: onClose)
                        .frame(minWidth: 44, minHeight: 44)
                }
            }
        }
    }

    private var orderedStates: [WorldUnlockState] {
        progression?.states
            ?? WorldProgression(profile: profile, completions: []).states
    }

    private var progressText: String {
        let count = progression?.completedTodayQuestCount ?? 0
        return "\(count) Today Quests complete · New worlds unlock at 3 and 8."
    }

    private func worldCard(_ state: WorldUnlockState) -> some View {
        let theme = TadaWorldTheme.from(state.world)
        let isCurrent = profile.selectedWorld == state.world
        return Button {
            guard state.isUnlocked else { return }
            onSelect(state.world)
            onClose()
        } label: {
            VStack(spacing: TadaPrimitiveTokens.Spacing.medium) {
                TadaWorldMascot(theme: theme, pose: .encouraging, size: 92)
                Text(theme.name)
                    .font(.system(.title2, design: .rounded, weight: .heavy))
                    .foregroundStyle(theme.ink)
                if isCurrent {
                    Label("Current world", systemImage: "checkmark.circle.fill")
                        .foregroundStyle(theme.primary)
                } else if state.isUnlocked {
                    Label("Ready to explore", systemImage: "sparkles")
                        .foregroundStyle(theme.primary)
                } else {
                    Label(
                        "Preview · \(state.requiredTodayQuestCount) quests",
                        systemImage: "lock.fill"
                    )
                    .foregroundStyle(theme.ink.opacity(0.68))
                }
            }
            .font(.system(.subheadline, design: .rounded, weight: .bold))
            .frame(maxWidth: .infinity, minHeight: 220)
            .padding(TadaPrimitiveTokens.Spacing.medium)
            .background(
                LinearGradient(
                    colors: [theme.backgroundTop, theme.backgroundBottom],
                    startPoint: .top,
                    endPoint: .bottom
                ),
                in: RoundedRectangle(
                    cornerRadius: TadaPrimitiveTokens.Radius.large,
                    style: .continuous
                )
            )
            .overlay {
                RoundedRectangle(
                    cornerRadius: TadaPrimitiveTokens.Radius.large,
                    style: .continuous
                )
                .strokeBorder(
                    isCurrent ? theme.primary : Color.white.opacity(0.8),
                    lineWidth: isCurrent ? 4 : 2
                )
            }
            .opacity(state.isUnlocked ? 1 : 0.78)
        }
        .buttonStyle(TadaTactileCardButtonStyle())
        .disabled(!state.isUnlocked || isCurrent)
        .accessibilityHint(
            state.isUnlocked
                ? "Changes the lobby, quests, rewards, and music to this world"
                : "This world is a preview and is still locked"
        )
    }
}

struct ChildCollectionView: View {
    let profile: KidProfile
    let collections: [WorldTheme: RewardCollection]
    let onClose: () -> Void

    @State private var selectedWorld: WorldTheme

    init(
        profile: KidProfile,
        collections: [WorldTheme: RewardCollection],
        onClose: @escaping () -> Void
    ) {
        self.profile = profile
        self.collections = collections
        self.onClose = onClose
        _selectedWorld = State(initialValue: profile.selectedWorld)
    }

    private let columns = [
        GridItem(.adaptive(minimum: 138), spacing: TadaPrimitiveTokens.Spacing.medium)
    ]

    var body: some View {
        let theme = TadaWorldTheme.from(selectedWorld)
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: TadaPrimitiveTokens.Spacing.large) {
                    Picker("World collection", selection: $selectedWorld) {
                        ForEach(WorldTheme.allCases, id: \.self) { world in
                            Text(world.displayName).tag(world)
                        }
                    }
                    .pickerStyle(.segmented)

                    HStack {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("\(theme.name) Collection")
                                .font(.system(.largeTitle, design: .rounded, weight: .heavy))
                            Text(collectionSummary)
                                .font(.system(.body, design: .rounded, weight: .semibold))
                                .foregroundStyle(theme.ink.opacity(0.68))
                        }
                        Spacer()
                        TadaWorldMascot(theme: theme, pose: .cheering, size: 76)
                    }

                    LazyVGrid(columns: columns, spacing: TadaPrimitiveTokens.Spacing.medium) {
                        ForEach(collectionItems, id: \.item.id) { state in
                            collectionCard(state, theme: theme)
                        }
                    }
                }
                .padding(TadaPrimitiveTokens.Spacing.large)
                .frame(maxWidth: 980, alignment: .leading)
                .frame(maxWidth: .infinity)
            }
            .background(
                LinearGradient(
                    colors: [
                        theme.backgroundTop.opacity(0.45), theme.backgroundBottom.opacity(0.45),
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            )
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close", action: onClose)
                        .frame(minWidth: 44, minHeight: 44)
                }
            }
        }
    }

    private var collectionItems: [RewardCollectionItemState] {
        collections[selectedWorld]?.items ?? []
    }

    private var collectionSummary: String {
        guard let collection = collections[selectedWorld] else {
            return "Complete a Today Quest here to find the first treasure."
        }
        return "\(collection.collectedCount) of \(collection.items.count) treasures found"
    }

    private func collectionCard(
        _ state: RewardCollectionItemState,
        theme: TadaWorldTheme
    ) -> some View {
        VStack(spacing: 9) {
            ZStack {
                Circle()
                    .fill(
                        state.isCollected
                            ? theme.primary.opacity(0.18)
                            : Color.gray.opacity(0.10)
                    )
                Image(
                    systemName: state.isCollected
                        ? state.item.presentationSymbol
                        : "lock.fill"
                )
                .font(.system(size: 30, weight: .bold))
                .foregroundStyle(
                    state.isCollected ? theme.primary : Color.gray.opacity(0.62)
                )
            }
            .frame(width: 68, height: 68)

            Text(state.item.displayName)
                .font(.system(.caption, design: .rounded, weight: .bold))
                .foregroundStyle(theme.ink)
                .multilineTextAlignment(.center)
                .lineLimit(2)

            if state.item.tier == .milestone {
                Text("Big milestone")
                    .font(.system(.caption2, design: .rounded, weight: .heavy))
                    .foregroundStyle(theme.primary)
            }
        }
        .frame(maxWidth: .infinity, minHeight: 138)
        .padding(10)
        .background(
            Color.white.opacity(state.isCollected ? 0.90 : 0.58),
            in: RoundedRectangle(
                cornerRadius: TadaPrimitiveTokens.Radius.medium,
                style: .continuous
            )
        )
        .accessibilityElement(children: .combine)
        .accessibilityValue(state.isCollected ? "Collected" : "Locked")
    }
}
