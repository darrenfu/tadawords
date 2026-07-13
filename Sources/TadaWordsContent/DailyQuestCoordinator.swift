import Foundation
import TadaWordsDomain

/// An execution token produced only by `DailyQuestCoordinator`. Keeping its
/// initializer inside Content prevents callers from forging a Practice Again
/// run with newly selected words.
public struct DailyQuestLaunch: Hashable, Sendable {
    public let dailyPlan: DailyQuestPlan
    public let questPlan: QuestPlan
    public let runKind: DailyQuestRunKind
}

/// Application-facing orchestration for Daily Quest identity and reward rules.
/// It deliberately accepts an already-planned Today candidate, keeping word
/// selection in the existing Content/Learning pipeline.
public struct DailyQuestCoordinator: Sendable {
    private let repository: any DailyQuestRepository
    private let catalog: any RewardCatalogProviding
    private let timeZone: TimeZone

    public init(
        repository: any DailyQuestRepository,
        catalog: any RewardCatalogProviding = ThemedRewardCatalog(),
        timeZone: TimeZone
    ) {
        self.repository = repository
        self.catalog = catalog
        self.timeZone = timeZone
    }

    /// Persists the first candidate for Profile x Mode x Local Day and returns
    /// that same plan on later calls, even if a later candidate differs.
    public func loadOrCreateToday(
        candidate: QuestPlan,
        on date: Date
    ) async throws -> DailyQuestState {
        let localDay = LocalDay(date: date, timeZone: timeZone)
        let proposed = DailyQuestPlan(localDay: localDay, questPlan: candidate)
        let stored = try await repository.createPlanIfAbsent(proposed)
        return try await repository.state(for: stored.key)
    }

    public func state(
        profileID: ProfileID,
        learningMode: LearningMode,
        on date: Date
    ) async throws -> DailyQuestState {
        try await repository.state(
            for: key(
                profileID: profileID,
                learningMode: learningMode,
                on: date
            )
        )
    }

    /// Returns nil after Today is complete (the caller should present Practice
    /// Again instead). Today uses the persisted quest ID for attempt evidence.
    public func todayLaunch(from state: DailyQuestState) -> DailyQuestLaunch? {
        guard let plan = state.plan, state.todayCompletion == nil else {
            return nil
        }
        return DailyQuestLaunch(
            dailyPlan: plan,
            questPlan: plan.questPlan,
            runKind: .today
        )
    }

    /// Clones only the persisted words. They are all marked Review and receive
    /// a new run quest ID, so Practice Again cannot select/consume more New
    /// words or mix its attempt evidence into the original Today run.
    public func practiceAgainLaunch(
        from state: DailyQuestState,
        questID: QuestID = QuestID(),
        startedAt: Date
    ) -> DailyQuestLaunch? {
        guard let dailyPlan = state.plan, state.todayCompletion != nil else {
            return nil
        }
        let original = dailyPlan.questPlan
        let practicedWordIDs = original.orderedItems.map(\.wordPromptID)
        let practicePlan = QuestPlan(
            id: questID,
            profileID: original.profileID,
            configuration: original.configuration,
            reviewWordIDs: practicedWordIDs,
            newWordIDs: [],
            deferredReviewWordIDs: [],
            createdAt: startedAt
        )
        return DailyQuestLaunch(
            dailyPlan: dailyPlan,
            questPlan: practicePlan,
            runKind: .practiceAgain
        )
    }

    /// Callers should retain `completionID` until this write succeeds. Retrying
    /// with the same UUID is idempotent; Today's reward is written in the same
    /// atomic snapshot as the completion.
    public func complete(
        _ launch: DailyQuestLaunch,
        score: QuestScore,
        world: WorldTheme,
        completionID: DailyQuestCompletionID = DailyQuestCompletionID(),
        rewardGrantID: RewardGrantID = RewardGrantID(),
        completedAt: Date
    ) async throws -> DailyQuestCompletionWriteResult {
        let completion = DailyQuestCompletion(
            id: completionID,
            dailyPlanID: launch.dailyPlan.id,
            runQuestID: launch.questPlan.id,
            profileID: launch.dailyPlan.key.profileID,
            learningMode: launch.dailyPlan.key.learningMode,
            localDay: launch.dailyPlan.localDay,
            runKind: launch.runKind,
            points: score.points,
            stars: score.stars,
            completedAt: completedAt
        )

        let reward: RewardGrant?
        switch launch.runKind {
        case .today:
            let rewardKey = RewardGrantKey(
                profileID: completion.profileID,
                world: world,
                localDay: completion.localDay,
                learningMode: completion.learningMode
            )
            reward = RewardGrant(
                id: rewardGrantID,
                key: rewardKey,
                dailyPlanID: completion.dailyPlanID,
                completionID: completion.id,
                item: catalog.reward(for: rewardKey),
                grantedAt: completedAt
            )
        case .practiceAgain:
            reward = nil
        }

        return try await repository.recordCompletion(
            completion,
            proposedRewardGrant: reward
        )
    }

    public func completions(
        profileID: ProfileID,
        learningMode: LearningMode,
        on date: Date
    ) async throws -> [DailyQuestCompletion] {
        try await repository.completions(
            for: key(
                profileID: profileID,
                learningMode: learningMode,
                on: date
            )
        )
    }

    public func monthSummary(
        profileID: ProfileID,
        containing date: Date
    ) async throws -> DailyQuestMonthSummary {
        let month = LocalMonth(date: date, timeZone: timeZone)
        let completions = try await repository.completions(
            for: profileID,
            in: month
        )
        return DailyQuestMonthSummary(
            profileID: profileID,
            month: month,
            completions: completions
        )
    }

    public func worldProgression(
        for profile: KidProfile
    ) async throws -> WorldProgression {
        guard let history = repository as? any DailyQuestHistoryRepository else {
            return WorldProgression(profile: profile, completions: [])
        }
        return WorldProgression(
            profile: profile,
            completions: try await history.allCompletions(for: profile.id)
        )
    }

    public func rewardCollections(
        for profile: KidProfile
    ) async throws -> [WorldTheme: RewardCollection] {
        guard let history = repository as? any DailyQuestHistoryRepository else {
            return [:]
        }
        let grants = try await history.rewardGrants(for: profile.id)
        return Dictionary(
            uniqueKeysWithValues: WorldTheme.allCases.map { world in
                (
                    world,
                    RewardCollection(
                        profileID: profile.id,
                        world: world,
                        catalogItems: catalog.items(for: world),
                        rewardGrants: grants
                    )
                )
            }
        )
    }

    private func key(
        profileID: ProfileID,
        learningMode: LearningMode,
        on date: Date
    ) -> DailyQuestKey {
        DailyQuestKey(
            profileID: profileID,
            learningMode: learningMode,
            localDay: LocalDay(date: date, timeZone: timeZone)
        )
    }
}
