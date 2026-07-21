import SwiftUI
import TadaWordsDesignSystem
import TadaWordsDomain

struct ChildWorldPickerView: View {
    let profile: KidProfile
    let progression: WorldProgression?
    let currentLocalDay: LocalDay
    let onSelect: (WorldTheme) -> Void
    let onClose: () -> Void

    private let columns = [
        GridItem(.adaptive(minimum: 230), spacing: TadaPrimitiveTokens.Spacing.medium)
    ]

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: TadaPrimitiveTokens.Spacing.large) {
                    Text("Choose a World")
                        .font(.system(.largeTitle, design: .rounded, weight: .heavy))

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
                    Button(action: onClose) {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(.title2, design: .rounded, weight: .bold))
                            .frame(minWidth: 44, minHeight: 44)
                    }
                    .accessibilityLabel("Close")
                    .accessibilityHint("Returns to the Kid Lobby")
                }
            }
        }
    }

    private var orderedStates: [WorldUnlockState] {
        progression?.states
            ?? WorldProgression(
                profile: profile,
                completions: [],
                currentLocalDay: currentLocalDay
            ).states
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
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(theme.primary)
                } else if state.isUnlocked {
                    Image(systemName: "sparkles")
                        .foregroundStyle(theme.primary)
                } else {
                    Label(
                        state.remainingQualifyingDayCount == 1
                            ? "Preview · 1 more complete day"
                            : "Preview · \(state.remainingQualifyingDayCount) more complete days",
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
    let progression: WorldProgression?
    let collections: [WorldTheme: RewardCollection]
    let onSelectWorld: (WorldTheme) -> Void
    let onSelectCartoonIcon: (String) -> Void
    let onSelectTreasureAvatar: (RewardCatalogItem) -> Void
    let onSelectOriginalAvatar: () -> Void
    let onClose: () -> Void

    @State private var selectedWorld: WorldTheme

    init(
        profile: KidProfile,
        progression: WorldProgression?,
        collections: [WorldTheme: RewardCollection],
        onSelectWorld: @escaping (WorldTheme) -> Void,
        onSelectCartoonIcon: @escaping (String) -> Void,
        onSelectTreasureAvatar: @escaping (RewardCatalogItem) -> Void,
        onSelectOriginalAvatar: @escaping () -> Void,
        onClose: @escaping () -> Void
    ) {
        self.profile = profile
        self.progression = progression
        self.collections = collections
        self.onSelectWorld = onSelectWorld
        self.onSelectCartoonIcon = onSelectCartoonIcon
        self.onSelectTreasureAvatar = onSelectTreasureAvatar
        self.onSelectOriginalAvatar = onSelectOriginalAvatar
        self.onClose = onClose
        _selectedWorld = State(initialValue: profile.selectedWorld)
    }

    private let worldColumns = [
        GridItem(.adaptive(minimum: 210), spacing: TadaPrimitiveTokens.Spacing.medium)
    ]
    private let iconColumns = [
        GridItem(.adaptive(minimum: 118), spacing: TadaPrimitiveTokens.Spacing.medium)
    ]
    private let treasureColumns = [
        GridItem(.adaptive(minimum: 138), spacing: TadaPrimitiveTokens.Spacing.medium)
    ]

    private var theme: TadaWorldTheme {
        TadaWorldTheme.from(selectedWorld)
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: TadaPrimitiveTokens.Spacing.large) {
                    HStack(spacing: TadaPrimitiveTokens.Spacing.medium) {
                        Text("My Collection")
                            .font(.system(.largeTitle, design: .rounded, weight: .heavy))
                        Spacer()
                        TadaWorldMascot(theme: theme, pose: .cheering, size: 76)
                    }

                    collectionSectionHeader("My Worlds")
                    LazyVGrid(
                        columns: worldColumns,
                        spacing: TadaPrimitiveTokens.Spacing.medium
                    ) {
                        ForEach(orderedWorlds, id: \.self) { world in
                            worldCard(world)
                        }
                    }

                    collectionSectionHeader("My Icons")
                    LazyVGrid(
                        columns: iconColumns,
                        spacing: TadaPrimitiveTokens.Spacing.medium
                    ) {
                        if profile.avatar.isPhotoAvatar {
                            originalPhotoCard
                        }
                        ForEach(orderedIconAssetIDs, id: \.self) { assetID in
                            iconCard(assetID)
                        }
                    }

                    treasureWorldPicker

                    collectionSectionHeader(
                        "\(TadaWorldTheme.from(selectedWorld).name) Treasures"
                    )
                    LazyVGrid(
                        columns: treasureColumns,
                        spacing: TadaPrimitiveTokens.Spacing.medium
                    ) {
                        ForEach(collectionItems, id: \.item.id) { state in
                            collectionCard(
                                state,
                                theme: TadaWorldTheme.from(selectedWorld)
                            )
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
                    Button(action: onClose) {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(.title2, design: .rounded, weight: .bold))
                            .frame(minWidth: 44, minHeight: 44)
                    }
                    .accessibilityLabel("Close")
                    .accessibilityHint("Returns to the Kid Lobby")
                }
            }
        }
    }

    private var collectionItems: [RewardCollectionItemState] {
        collections[selectedWorld]?.items ?? []
    }

    private var treasureWorldPicker: some View {
        ScrollView(.horizontal) {
            HStack(spacing: TadaPrimitiveTokens.Spacing.small) {
                ForEach(WorldTheme.allCases, id: \.self) { world in
                    let worldTheme = TadaWorldTheme.from(world)
                    let isSelected = selectedWorld == world
                    Button {
                        selectedWorld = world
                    } label: {
                        Label(world.displayName, systemImage: worldTheme.motifSymbol)
                            .font(.system(.subheadline, design: .rounded, weight: .bold))
                            .foregroundStyle(
                                isSelected ? Color.white : worldTheme.ink
                            )
                            .padding(.horizontal, 14)
                            .frame(minHeight: TadaPrimitiveTokens.TouchTarget.minimum)
                            .background(
                                isSelected
                                    ? worldTheme.primary
                                    : Color.white.opacity(0.82),
                                in: Capsule()
                            )
                            .overlay {
                                Capsule()
                                    .strokeBorder(
                                        worldTheme.primary.opacity(
                                            isSelected ? 0 : 0.28
                                        ),
                                        lineWidth: 1.5
                                    )
                            }
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Show \(world.displayName) treasures")
                    .accessibilityAddTraits(isSelected ? .isSelected : [])
                }
            }
            .padding(.vertical, 2)
        }
        .scrollIndicators(.visible)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Treasure worlds")
    }

    private var orderedWorlds: [WorldTheme] {
        [profile.starterWorld]
            + WorldTheme.allCases.filter { $0 != profile.starterWorld }
    }

    private var orderedIconAssetIDs: [String] {
        if let progression {
            return progression.cartoonIconStates.map(\.assetID)
        }
        let starterAssetID =
            profile.avatar.cartoonAnimalAssetID
            ?? CosmeticProgressionCatalog.photoProfileFallbackCartoonIconAssetID
        return [starterAssetID]
            + CosmeticProgressionCatalog.cartoonIconAssetIDs.filter {
                $0 != starterAssetID
            }
    }

    private func collectionSectionHeader(_ title: String) -> some View {
        Text(title)
            .font(.system(.title2, design: .rounded, weight: .heavy))
    }

    private func worldCard(_ world: WorldTheme) -> some View {
        let worldTheme = TadaWorldTheme.from(world)
        let isUnlocked =
            progression?.unlockedWorlds.contains(world)
            ?? (world == profile.starterWorld
                || profile.guardianUnlockedWorlds.contains(world))
        let isCurrent = profile.selectedWorld == world
        return Button {
            guard isUnlocked else { return }
            onSelectWorld(world)
        } label: {
            HStack(spacing: TadaPrimitiveTokens.Spacing.medium) {
                TadaWorldMascot(theme: worldTheme, pose: .encouraging, size: 66)
                VStack(alignment: .leading, spacing: 5) {
                    Text(worldTheme.name)
                        .font(.system(.headline, design: .rounded, weight: .heavy))
                        .foregroundStyle(worldTheme.ink)
                    Image(
                        systemName: isCurrent
                            ? "checkmark.circle.fill"
                            : (isUnlocked ? "sparkles" : "lock.fill")
                    )
                    .font(.system(.title3, design: .rounded, weight: .bold))
                    .foregroundStyle(
                        isUnlocked ? worldTheme.primary : worldTheme.ink.opacity(0.60)
                    )
                }
                Spacer(minLength: 0)
            }
            .frame(maxWidth: .infinity, minHeight: 104, alignment: .leading)
            .padding(TadaPrimitiveTokens.Spacing.medium)
            .background(
                LinearGradient(
                    colors: [worldTheme.backgroundTop, worldTheme.backgroundBottom],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
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
                    isCurrent ? worldTheme.primary : Color.white.opacity(0.82),
                    lineWidth: isCurrent ? 4 : 2
                )
            }
            .opacity(isUnlocked ? 1 : 0.70)
        }
        .buttonStyle(TadaTactileCardButtonStyle())
        .disabled(!isUnlocked || isCurrent)
        .frame(minHeight: TadaPrimitiveTokens.TouchTarget.minimum)
        .accessibilityLabel(
            "\(world.displayName), \(isCurrent ? "using now" : (isUnlocked ? "earned" : "locked"))"
        )
        .accessibilityHint(isUnlocked ? "Uses this world" : "Preview only")
    }

    private var originalPhotoCard: some View {
        let isCurrent =
            profile.selectedCartoonIconAssetID == nil
            && profile.selectedTreasureAvatar == nil
        return Button(action: onSelectOriginalAvatar) {
            iconCardContent(
                avatar: profile.avatar,
                title: "My Photo",
                isUnlocked: true,
                isCurrent: isCurrent
            )
        }
        .buttonStyle(TadaTactileCardButtonStyle())
        .disabled(isCurrent)
        .frame(minHeight: TadaPrimitiveTokens.TouchTarget.minimum)
        .accessibilityLabel("My photo, \(isCurrent ? "using now" : "earned")")
    }

    private func iconCard(_ assetID: String) -> some View {
        let isUnlocked =
            progression?.unlockedCartoonIconAssetIDs.contains(assetID)
            ?? (assetID == profile.avatar.cartoonAnimalAssetID
                || (profile.avatar.isPhotoAvatar
                    && assetID
                        == CosmeticProgressionCatalog
                        .photoProfileFallbackCartoonIconAssetID))
        let isCurrent = profile.displayAvatar.cartoonAnimalAssetID == assetID
        return Button {
            guard isUnlocked else { return }
            onSelectCartoonIcon(assetID)
        } label: {
            iconCardContent(
                avatar: .cartoonAnimal(assetID: assetID),
                title: assetID.collectionDisplayName,
                isUnlocked: isUnlocked,
                isCurrent: isCurrent
            )
        }
        .buttonStyle(TadaTactileCardButtonStyle())
        .disabled(!isUnlocked || isCurrent)
        .frame(minHeight: TadaPrimitiveTokens.TouchTarget.minimum)
        .accessibilityLabel(
            "\(assetID.collectionDisplayName), \(isCurrent ? "using now" : (isUnlocked ? "earned" : "locked"))"
        )
        .accessibilityHint(isUnlocked ? "Uses this profile icon" : "Preview only")
    }

    private func iconCardContent(
        avatar: ProfileAvatar,
        title: String,
        isUnlocked: Bool,
        isCurrent: Bool
    ) -> some View {
        VStack(spacing: 8) {
            ZStack(alignment: .bottomTrailing) {
                Circle()
                    .fill(theme.primary.opacity(isUnlocked ? 0.18 : 0.07))
                ProfileAvatarContent(avatar: avatar, symbolSize: 38)
                    .clipShape(Circle())
                    .padding(8)
                    .opacity(isUnlocked ? 1 : 0.48)
                Image(
                    systemName: isCurrent
                        ? "checkmark.circle.fill"
                        : (isUnlocked ? "sparkles" : "lock.fill")
                )
                .font(.system(size: 18, weight: .heavy))
                .foregroundStyle(isUnlocked ? theme.primary : Color.gray)
                .background(Color.white, in: Circle())
            }
            .frame(width: 72, height: 72)

            Text(title)
                .font(.system(.caption, design: .rounded, weight: .bold))
                .foregroundStyle(theme.ink)
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity, minHeight: 130)
        .padding(10)
        .background(
            Color.white.opacity(isUnlocked ? 0.90 : 0.58),
            in: RoundedRectangle(
                cornerRadius: TadaPrimitiveTokens.Radius.medium,
                style: .continuous
            )
        )
    }

    private func collectionCard(
        _ state: RewardCollectionItemState,
        theme: TadaWorldTheme
    ) -> some View {
        let presentation = TreasureCardPresentation(
            state: state,
            selectedTreasureAvatar: profile.selectedTreasureAvatar
        )
        return Button {
            guard state.isCollected else { return }
            onSelectTreasureAvatar(state.item)
        } label: {
            VStack(spacing: 9) {
                ZStack(alignment: .bottomTrailing) {
                    Circle()
                        .fill(
                            state.isCollected
                                ? theme.primary.opacity(0.18)
                                : Color.gray.opacity(0.10)
                        )
                    Image(systemName: presentation.iconAssetID)
                        .font(.system(size: 30, weight: .bold))
                        .foregroundStyle(
                            state.isCollected
                                ? theme.primary
                                : Color.gray.opacity(0.48)
                        )
                        .grayscale(state.isCollected ? 0 : 1)
                        .opacity(state.isCollected ? 1 : 0.72)

                    if let badgeSymbol = presentation.badgeSymbol {
                        Image(systemName: badgeSymbol)
                            .font(.system(size: 16, weight: .heavy))
                            .foregroundStyle(
                                presentation.isCurrent
                                    ? theme.primary
                                    : Color.gray.opacity(0.88)
                            )
                            .padding(5)
                            .background(Color.white.opacity(0.96), in: Circle())
                            .overlay {
                                Circle()
                                    .strokeBorder(Color.white, lineWidth: 1)
                            }
                            .offset(x: 4, y: 4)
                    }
                }
                .frame(width: 68, height: 68)

                Text(state.item.displayName)
                    .font(.system(.caption, design: .rounded, weight: .bold))
                    .foregroundStyle(theme.ink)
                    .multilineTextAlignment(.center)
                    .lineLimit(2)

            }
            .frame(maxWidth: .infinity, minHeight: 148)
            .padding(10)
            .background(
                Color.white.opacity(state.isCollected ? 0.90 : 0.58),
                in: RoundedRectangle(
                    cornerRadius: TadaPrimitiveTokens.Radius.medium,
                    style: .continuous
                )
            )
            .overlay {
                RoundedRectangle(
                    cornerRadius: TadaPrimitiveTokens.Radius.medium,
                    style: .continuous
                )
                .strokeBorder(
                    presentation.isCurrent
                        ? theme.primary.opacity(0.82)
                        : Color.clear,
                    lineWidth: 3
                )
            }
        }
        .buttonStyle(TadaTactileCardButtonStyle())
        .disabled(!state.isCollected || presentation.isCurrent)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(state.item.displayName)
        .accessibilityValue(presentation.accessibilityValue)
        .accessibilityHint(
            state.isCollected && !presentation.isCurrent
                ? "Uses this treasure as your profile icon"
                : ""
        )
    }
}

struct TreasureCardPresentation: Equatable {
    let iconAssetID: String
    let isCurrent: Bool
    let badgeSymbol: String?
    let statusText: String
    let accessibilityValue: String

    init(
        state: RewardCollectionItemState,
        selectedTreasureAvatar: TreasureAvatarSelection?
    ) {
        iconAssetID = state.item.presentationSymbol
        isCurrent = selectedTreasureAvatar?.rewardItemID == state.item.id
        if isCurrent {
            badgeSymbol = "checkmark.circle.fill"
            statusText = "Using as icon"
            accessibilityValue = "Collected, using as profile icon"
        } else if state.isCollected {
            badgeSymbol = nil
            statusText =
                state.item.tier == .milestone
                ? "Milestone · Use as icon"
                : "Use as icon"
            accessibilityValue = "Collected, available as profile icon"
        } else {
            badgeSymbol = "lock.fill"
            statusText =
                state.item.tier == .milestone
                ? "Milestone · Locked"
                : "Locked"
            accessibilityValue = "Locked"
        }
    }
}

extension ProfileAvatar {
    fileprivate var cartoonAnimalAssetID: String? {
        guard case .cartoonAnimal(let assetID) = self else { return nil }
        return assetID
    }

    fileprivate var isPhotoAvatar: Bool {
        guard case .photo = self else { return false }
        return true
    }
}

extension String {
    fileprivate var collectionDisplayName: String {
        StarterProfileAvatar.option(for: self)?.name
            ?? (self == "beaver" ? "Beaver" : "Animal Friend")
    }
}
