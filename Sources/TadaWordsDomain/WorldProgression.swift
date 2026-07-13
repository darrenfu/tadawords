import Foundation

public struct WorldUnlockState: Equatable, Sendable {
    public let world: WorldTheme
    public let isUnlocked: Bool
    public let requiredTodayQuestCount: Int

    public init(
        world: WorldTheme,
        isUnlocked: Bool,
        requiredTodayQuestCount: Int
    ) {
        self.world = world
        self.isUnlocked = isUnlocked
        self.requiredTodayQuestCount = max(0, requiredTodayQuestCount)
    }
}

/// Unlocks are projections of immutable Today completions plus explicit
/// Guardian overrides. Practice Again never advances the track.
public struct WorldProgression: Equatable, Sendable {
    public let completedTodayQuestCount: Int
    public let states: [WorldUnlockState]

    public init(
        profile: KidProfile,
        completions: [DailyQuestCompletion]
    ) {
        let todayCount = completions.filter {
            $0.profileID == profile.id && $0.runKind == .today
        }.count
        completedTodayQuestCount = todayCount

        let orderedWorlds =
            [profile.starterWorld]
            + WorldTheme.allCases.filter { $0 != profile.starterWorld }
        let requirements = [0, 3, 8]
        states = orderedWorlds.enumerated().map { index, world in
            let requirement = requirements[min(index, requirements.count - 1)]
            return WorldUnlockState(
                world: world,
                isUnlocked: todayCount >= requirement
                    || profile.guardianUnlockedWorlds.contains(world),
                requiredTodayQuestCount: requirement
            )
        }
    }

    public var unlockedWorlds: Set<WorldTheme> {
        Set(states.filter(\.isUnlocked).map(\.world))
    }

    public func state(for world: WorldTheme) -> WorldUnlockState? {
        states.first { $0.world == world }
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
