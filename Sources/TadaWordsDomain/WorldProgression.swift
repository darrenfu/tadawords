import Foundation

/// Stable cosmetic ordering. Append new entries so existing children keep the
/// same earn sequence after an app update.
public enum CosmeticProgressionCatalog {
    public static let worlds: [WorldTheme] = [
        .moonpetalKingdom,
        .buildItBay,
        .pawsAndPines,
        .dinoDiscovery,
        .firehouseHeroes,
        .brickworkCity,
        .frostlightWorld,
        .coasterCarnival,
    ]

    public static let cartoonIconAssetIDs: [String] = [
        "hare",
        "fox",
        "bear",
        "owl",
        "cat",
        "dog",
    ]

    public static let photoProfileFallbackCartoonIconAssetID = "hare"
}

public struct WorldUnlockState: Equatable, Sendable {
    public let world: WorldTheme
    public let isUnlocked: Bool
    public let requiredQualifyingDayCount: Int
    public let remainingQualifyingDayCount: Int

    public init(
        world: WorldTheme,
        isUnlocked: Bool,
        requiredQualifyingDayCount: Int,
        remainingQualifyingDayCount: Int
    ) {
        self.world = world
        self.isUnlocked = isUnlocked
        self.requiredQualifyingDayCount = max(0, requiredQualifyingDayCount)
        self.remainingQualifyingDayCount =
            isUnlocked
            ? 0
            : max(0, remainingQualifyingDayCount)
    }
}

public struct CartoonIconUnlockState: Equatable, Sendable {
    public let assetID: String
    public let isUnlocked: Bool
    public let requiredQualifyingDayCount: Int
    public let remainingQualifyingDayCount: Int

    public init(
        assetID: String,
        isUnlocked: Bool,
        requiredQualifyingDayCount: Int,
        remainingQualifyingDayCount: Int
    ) {
        self.assetID = assetID
        self.isUnlocked = isUnlocked
        self.requiredQualifyingDayCount = max(0, requiredQualifyingDayCount)
        self.remainingQualifyingDayCount =
            isUnlocked
            ? 0
            : max(0, remainingQualifyingDayCount)
    }
}

/// A qualifying day contains both a Read Today completion and a Write Today
/// completion for the same profile and local day. Cosmetics become available
/// only on a later local day, so completing today's pair never unlocks early.
public struct WorldProgression: Equatable, Sendable {
    public let qualifyingPriorDayCount: Int
    public let starterCartoonIconAssetID: String
    public let states: [WorldUnlockState]
    public let cartoonIconStates: [CartoonIconUnlockState]

    public init(
        profile: KidProfile,
        completions: [DailyQuestCompletion],
        currentLocalDay: LocalDay
    ) {
        let qualifyingDays = Self.qualifyingPriorDays(
            for: profile.id,
            completions: completions,
            currentLocalDay: currentLocalDay
        )
        qualifyingPriorDayCount = qualifyingDays.count

        // Grandfather the actively selected world for profiles that earned it
        // under an older progression rule. An app update must not take away
        // the world a child was already using.
        let alwaysUnlockedWorlds = profile.guardianUnlockedWorlds.union([
            profile.starterWorld, profile.selectedWorld,
        ])
        states = Self.worldStates(
            alwaysUnlockedWorlds: alwaysUnlockedWorlds,
            qualifyingPriorDayCount: qualifyingPriorDayCount
        )

        switch profile.avatar {
        case .cartoonAnimal(let assetID):
            starterCartoonIconAssetID = assetID
        case .photo, .treasure:
            starterCartoonIconAssetID =
                CosmeticProgressionCatalog.photoProfileFallbackCartoonIconAssetID
        }
        cartoonIconStates = Self.cartoonIconStates(
            starterAssetID: starterCartoonIconAssetID,
            qualifyingPriorDayCount: qualifyingPriorDayCount
        )
    }

    public var unlockedWorlds: Set<WorldTheme> {
        Set(states.filter(\.isUnlocked).map(\.world))
    }

    public var unlockedCartoonIconAssetIDs: Set<String> {
        Set(cartoonIconStates.filter(\.isUnlocked).map(\.assetID))
    }

    public func state(for world: WorldTheme) -> WorldUnlockState? {
        states.first { $0.world == world }
    }

    public func cartoonIconState(for assetID: String) -> CartoonIconUnlockState? {
        cartoonIconStates.first { $0.assetID == assetID }
    }

    private static func qualifyingPriorDays(
        for profileID: ProfileID,
        completions: [DailyQuestCompletion],
        currentLocalDay: LocalDay
    ) -> Set<LocalDay> {
        let modesByDay = completions.reduce(into: [LocalDay: Set<LearningMode>]()) {
            modesByDay, completion in
            guard completion.profileID == profileID,
                completion.runKind == .today,
                completion.localDay < currentLocalDay
            else { return }
            modesByDay[completion.localDay, default: []].insert(
                completion.learningMode
            )
        }
        return Set(
            modesByDay.compactMap { localDay, learningModes in
                learningModes.contains(.read) && learningModes.contains(.write)
                    ? localDay
                    : nil
            }
        )
    }

    private static func worldStates(
        alwaysUnlockedWorlds: Set<WorldTheme>,
        qualifyingPriorDayCount: Int
    ) -> [WorldUnlockState] {
        var nextRequiredDayCount = 0
        return CosmeticProgressionCatalog.worlds.map { world in
            let requiredDayCount: Int
            if alwaysUnlockedWorlds.contains(world) {
                requiredDayCount = 0
            } else {
                nextRequiredDayCount += 1
                requiredDayCount = nextRequiredDayCount
            }
            let isUnlocked =
                requiredDayCount == 0
                || qualifyingPriorDayCount >= requiredDayCount
            return WorldUnlockState(
                world: world,
                isUnlocked: isUnlocked,
                requiredQualifyingDayCount: requiredDayCount,
                remainingQualifyingDayCount: requiredDayCount
                    - qualifyingPriorDayCount
            )
        }
    }

    private static func cartoonIconStates(
        starterAssetID: String,
        qualifyingPriorDayCount: Int
    ) -> [CartoonIconUnlockState] {
        let orderedAssetIDs =
            [starterAssetID]
            + CosmeticProgressionCatalog.cartoonIconAssetIDs.filter {
                $0 != starterAssetID
            }
        return orderedAssetIDs.enumerated().map { index, assetID in
            let requiredDayCount = index
            let isUnlocked = qualifyingPriorDayCount >= requiredDayCount
            return CartoonIconUnlockState(
                assetID: assetID,
                isUnlocked: isUnlocked,
                requiredQualifyingDayCount: requiredDayCount,
                remainingQualifyingDayCount: requiredDayCount
                    - qualifyingPriorDayCount
            )
        }
    }
}

public struct RewardCollectionItemState: Equatable, Sendable {
    public let item: RewardCatalogItem
    public let isCollected: Bool

    public init(item: RewardCatalogItem, isCollected: Bool) {
        self.item = item
        self.isCollected = isCollected
    }
}

/// A theme-safe Collection projection. Permanent small rewards come from
/// grants; large milestones are derived from Today completions in that world.
public struct RewardCollection: Equatable, Sendable {
    public let profileID: ProfileID
    public let world: WorldTheme
    public let items: [RewardCollectionItemState]

    public init(
        profileID: ProfileID,
        world: WorldTheme,
        catalogItems: [RewardCatalogItem],
        rewardGrants: [RewardGrant]
    ) {
        self.profileID = profileID
        self.world = world
        let worldGrants = rewardGrants.filter {
            $0.key.profileID == profileID && $0.key.world == world
        }
        let grantedIDs = Set(worldGrants.map(\.item.id))
        let completedTodayQuestCount = Set(worldGrants.map(\.completionID)).count
        items =
            catalogItems
            .filter { $0.world == world }
            .map { item in
                let collected: Bool
                switch item.tier {
                case .smallCollectible:
                    collected = grantedIDs.contains(item.id)
                case .milestone:
                    collected =
                        completedTodayQuestCount
                        >= (item.requiredTodayQuestCount ?? .max)
                }
                return RewardCollectionItemState(
                    item: item,
                    isCollected: collected
                )
            }
    }

    public var collectedCount: Int {
        items.filter(\.isCollected).count
    }
}
