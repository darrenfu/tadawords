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
    private let practiceOrder: @Sendable ([WordPromptID]) -> [WordPromptID]

    public init(
        repository: any DailyQuestRepository,
        catalog: any RewardCatalogProviding = ThemedRewardCatalog(),
        timeZone: TimeZone,
        practiceOrder: @escaping @Sendable ([WordPromptID]) -> [WordPromptID] = {
            $0.shuffled()
        }
    ) {
        self.repository = repository
        self.catalog = catalog
        self.timeZone = timeZone
        self.practiceOrder = practiceOrder
    }

    /// Persists the first candidate for Profile x Mode x Local Day. A later
    /// candidate removes prompts that are no longer active, refills eligible
    /// replacements, and honors raised limits without changing the stable plan
    /// ID. Callers that own the Word Pool should provide its complete active ID
    /// set; nil retains the legacy expansion-only behavior for non-pool clients.
    public func loadOrCreateToday(
        candidate: QuestPlan,
        activeWordIDs: Set<WordPromptID>? = nil,
        on date: Date
    ) async throws -> DailyQuestState {
        let localDay = LocalDay(date: date, timeZone: timeZone)
        let proposed = DailyQuestPlan(localDay: localDay, questPlan: candidate)
        let stored = try await repository.createPlanIfAbsent(proposed)
        guard
            let updated = Self.reconciledPlan(
                stored: stored,
                candidate: proposed,
                activeWordIDs: activeWordIDs
            ),
            let reconciling = repository
                as? any DailyQuestPlanReconcilingRepository
        else {
            return try await repository.state(for: stored.key)
        }
        let reconciled = try await reconciling.reconcilePlan(updated)
        return try await repository.state(for: reconciled.key)
    }

    private static func reconciledPlan(
        stored: DailyQuestPlan,
        candidate: DailyQuestPlan,
        activeWordIDs: Set<WordPromptID>?
    ) -> DailyQuestPlan? {
        let existing = stored.questPlan
        let proposed = candidate.questPlan
        guard stored.key == candidate.key,
            existing.profileID == proposed.profileID,
            existing.configuration.learningMode
                == proposed.configuration.learningMode
        else { return nil }

        let raisedNewLimit =
            proposed.configuration.newWordLimit
            > existing.configuration.newWordLimit
        let raisedReviewLimit =
            proposed.configuration.reviewWordLimit
            > existing.configuration.reviewWordLimit

        let newTarget = max(
            existing.configuration.newWordLimit,
            proposed.configuration.newWordLimit
        )
        let reviewTarget = max(
            existing.configuration.reviewWordLimit,
            proposed.configuration.reviewWordLimit
        )
        let retainedNew =
            activeWordIDs.map { activeWordIDs in
                existing.newWordIDs.filter(activeWordIDs.contains)
            } ?? existing.newWordIDs
        let retainedReview =
            activeWordIDs.map { activeWordIDs in
                existing.reviewWordIDs.filter(activeWordIDs.contains)
            } ?? existing.reviewWordIDs
        let retainedDeferred =
            activeWordIDs.map { activeWordIDs in
                existing.deferredReviewWordIDs.filter(activeWordIDs.contains)
            } ?? existing.deferredReviewWordIDs
        let candidateNew =
            activeWordIDs.map { activeWordIDs in
                proposed.newWordIDs.filter(activeWordIDs.contains)
            } ?? proposed.newWordIDs
        let candidateReview =
            activeWordIDs.map { activeWordIDs in
                proposed.reviewWordIDs.filter(activeWordIDs.contains)
            } ?? proposed.reviewWordIDs
        let candidateDeferred =
            activeWordIDs.map { activeWordIDs in
                proposed.deferredReviewWordIDs.filter(activeWordIDs.contains)
            } ?? proposed.deferredReviewWordIDs
        let additionalNew = additions(
            from: candidateNew,
            excluding: Set(
                retainedNew
                    + retainedReview
                    + retainedDeferred
            ),
            count: raisedNewLimit || activeWordIDs != nil
                ? max(0, newTarget - retainedNew.count) : 0
        )
        let additionalReview = additions(
            from: candidateReview,
            excluding: Set(
                retainedReview
                    + retainedNew
                    + retainedDeferred
            ).union(additionalNew),
            count: raisedReviewLimit || activeWordIDs != nil
                ? max(0, reviewTarget - retainedReview.count) : 0
        )
        let selectedIDs = Set(
            retainedNew
                + additionalNew
                + retainedReview
                + additionalReview
        )
        let deferredReviewWordIDs = uniqued(
            retainedDeferred
                + (raisedNewLimit || raisedReviewLimit ? candidateDeferred : [])
        ).filter { !selectedIDs.contains($0) }
        let configuration = QuestConfiguration(
            learningMode: existing.configuration.learningMode,
            newWordLimit: newTarget,
            reviewWordLimit: reviewTarget,
            attentionBudget: newTarget + reviewTarget,
            contentOrder: existing.configuration.contentOrder
        )
        let expanded = QuestPlan(
            id: existing.id,
            profileID: existing.profileID,
            configuration: configuration,
            reviewWordIDs: retainedReview + additionalReview,
            newWordIDs: retainedNew + additionalNew,
            deferredReviewWordIDs: deferredReviewWordIDs,
            createdAt: existing.createdAt
        )
        guard expanded != existing else { return nil }
        return DailyQuestPlan(localDay: stored.localDay, questPlan: expanded)
    }

    private static func additions(
        from candidates: [WordPromptID],
        excluding excluded: Set<WordPromptID>,
        count: Int
    ) -> [WordPromptID] {
        guard count > 0 else { return [] }
        var seen = excluded
        return candidates.filter { seen.insert($0).inserted }.prefix(count).map {
            $0
        }
    }

    private static func uniqued(
        _ values: [WordPromptID]
    ) -> [WordPromptID] {
        var seen: Set<WordPromptID> = []
        return values.filter { seen.insert($0).inserted }
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
        guard let plan = state.plan, state.todayCompletion == nil,
            !plan.questPlan.orderedItems.isEmpty
        else {
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
        avoiding previousWordIDs: [WordPromptID]? = nil,
        questID: QuestID = QuestID(),
        startedAt: Date
    ) -> DailyQuestLaunch? {
        practiceAgainLaunch(
            from: state,
            replaying: nil,
            questID: questID,
            startedAt: startedAt,
            shufflesWords: true,
            previousWordIDs: previousWordIDs
        )
    }

    /// Creates a focused Practice Again run containing only the requested
    /// words from Today's persisted plan. Unknown IDs are ignored and an empty
    /// selection cannot produce a launch.
    public func practiceAgainLaunch(
        from state: DailyQuestState,
        replaying requestedWordIDs: [WordPromptID],
        questID: QuestID = QuestID(),
        startedAt: Date
    ) -> DailyQuestLaunch? {
        practiceAgainLaunch(
            from: state,
            replaying: Set(requestedWordIDs),
            questID: questID,
            startedAt: startedAt,
            shufflesWords: false,
            previousWordIDs: nil
        )
    }

    /// Starts a reward-free run from a newly selected pool candidate without
    /// replacing the canonical plan or its Today completion. The candidate is
    /// treated entirely as Review so freestyle cannot consume more New words.
    public func practiceAgainLaunch(
        from state: DailyQuestState,
        freshCandidate: QuestPlan,
        avoiding previousWordIDs: [WordPromptID]? = nil,
        questID: QuestID = QuestID(),
        startedAt: Date
    ) -> DailyQuestLaunch? {
        guard let dailyPlan = state.plan, state.todayCompletion != nil else {
            return nil
        }
        let original = dailyPlan.questPlan
        guard freshCandidate.profileID == original.profileID,
            freshCandidate.configuration.learningMode
                == original.configuration.learningMode
        else { return nil }
        return makePracticeAgainLaunch(
            dailyPlan: dailyPlan,
            wordIDs: freshCandidate.orderedItems.map(\.wordPromptID),
            configuration: original.configuration,
            questID: questID,
            startedAt: startedAt,
            shufflesWords: true,
            previousWordIDs: previousWordIDs
        )
    }

    private func practiceAgainLaunch(
        from state: DailyQuestState,
        replaying requestedWordIDs: Set<WordPromptID>?,
        questID: QuestID,
        startedAt: Date,
        shufflesWords: Bool,
        previousWordIDs: [WordPromptID]?
    ) -> DailyQuestLaunch? {
        guard let dailyPlan = state.plan, state.todayCompletion != nil else {
            return nil
        }
        let original = dailyPlan.questPlan
        let persistedWordIDs = original.orderedItems.map(\.wordPromptID)
        let practicedWordIDs =
            requestedWordIDs.map { requested in
                persistedWordIDs.filter(requested.contains)
            } ?? persistedWordIDs
        return makePracticeAgainLaunch(
            dailyPlan: dailyPlan,
            wordIDs: practicedWordIDs,
            configuration: original.configuration,
            questID: questID,
            startedAt: startedAt,
            shufflesWords: shufflesWords,
            previousWordIDs: previousWordIDs
        )
    }

    private func makePracticeAgainLaunch(
        dailyPlan: DailyQuestPlan,
        wordIDs: [WordPromptID],
        configuration: QuestConfiguration,
        questID: QuestID,
        startedAt: Date,
        shufflesWords: Bool,
        previousWordIDs: [WordPromptID]?
    ) -> DailyQuestLaunch? {
        guard !wordIDs.isEmpty else { return nil }
        let orderedWordIDs =
            shufflesWords
            ? reordered(wordIDs, avoiding: previousWordIDs) : wordIDs
        let practicePlan = QuestPlan(
            id: questID,
            profileID: dailyPlan.questPlan.profileID,
            configuration: configuration,
            reviewWordIDs: orderedWordIDs,
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

    /// The injected seam makes ordering deterministic in tests. A malformed
    /// result falls back to the input; an unchanged multi-word result rotates
    /// once so a repeat never preserves the immediately previous order.
    private func reordered(
        _ wordIDs: [WordPromptID],
        avoiding previousWordIDs: [WordPromptID]?
    ) -> [WordPromptID] {
        guard wordIDs.count > 1 else { return wordIDs }
        let proposed = practiceOrder(wordIDs)
        let isPermutation =
            proposed.count == wordIDs.count
            && Set(proposed) == Set(wordIDs)
        let valid = isPermutation ? proposed : wordIDs
        if let previousWordIDs, Set(previousWordIDs) == Set(wordIDs),
            valid == previousWordIDs
        {
            return Array(previousWordIDs.dropFirst()) + [previousWordIDs[0]]
        }
        guard valid == wordIDs else { return valid }
        return Array(wordIDs.dropFirst()) + [wordIDs[0]]
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
        for profile: KidProfile,
        on date: Date
    ) async throws -> WorldProgression {
        let currentLocalDay = LocalDay(date: date, timeZone: timeZone)
        guard let history = repository as? any DailyQuestHistoryRepository else {
            return WorldProgression(
                profile: profile,
                completions: [],
                currentLocalDay: currentLocalDay
            )
        }
        return WorldProgression(
            profile: profile,
            completions: try await history.allCompletions(for: profile.id),
            currentLocalDay: currentLocalDay
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
