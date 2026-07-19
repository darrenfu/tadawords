import Foundation
import TadaWordsDomain

enum DailyQuestStorageValidationError: Error, Equatable, Sendable {
    case duplicatePlanID(QuestID)
    case duplicatePlanKey(DailyQuestKey)
    case duplicateCompletionID(DailyQuestCompletionID)
    case duplicateTodayCompletion(dailyPlanID: QuestID)
    case orphanCompletion(
        completionID: DailyQuestCompletionID,
        dailyPlanID: QuestID
    )
    case completionDoesNotMatchPlan(DailyQuestCompletionID)
    case duplicateRewardGrantID(RewardGrantID)
    case duplicateRewardGrantKey(RewardGrantKey)
    case orphanRewardGrant(
        rewardGrantID: RewardGrantID,
        completionID: DailyQuestCompletionID
    )
    case duplicateRewardForCompletion(DailyQuestCompletionID)
    case missingRewardForTodayCompletion(DailyQuestCompletionID)
    case rewardGrantDoesNotMatchCompletion(RewardGrantID)
}

struct DailyQuestStorage: Sendable {
    private var plansByID: [QuestID: DailyQuestPlan] = [:]
    private var planIDByKey: [DailyQuestKey: QuestID] = [:]
    private var completionsByID: [DailyQuestCompletionID: DailyQuestCompletion] = [:]
    private var todayCompletionIDByPlanID: [QuestID: DailyQuestCompletionID] = [:]
    private var rewardGrantsByID: [RewardGrantID: RewardGrant] = [:]
    private var rewardGrantIDByKey: [RewardGrantKey: RewardGrantID] = [:]
    private var rewardGrantIDByCompletionID: [DailyQuestCompletionID: RewardGrantID] = [:]
    private var pendingCompletionsByID: [DailyQuestCompletionID: DailyQuestCompletion] = [:]
    private var pendingRewardGrantsByID: [RewardGrantID: RewardGrant] = [:]

    init() {}

    init(snapshot: DailyQuestSnapshot) throws {
        for plan in snapshot.plans {
            guard plansByID[plan.id] == nil else {
                throw DailyQuestStorageValidationError.duplicatePlanID(plan.id)
            }
            guard planIDByKey[plan.key] == nil else {
                throw DailyQuestStorageValidationError.duplicatePlanKey(plan.key)
            }
            plansByID[plan.id] = plan
            planIDByKey[plan.key] = plan.id
        }

        for completion in snapshot.completions {
            guard completionsByID[completion.id] == nil else {
                throw DailyQuestStorageValidationError.duplicateCompletionID(
                    completion.id
                )
            }
            guard let plan = plansByID[completion.dailyPlanID] else {
                throw DailyQuestStorageValidationError.orphanCompletion(
                    completionID: completion.id,
                    dailyPlanID: completion.dailyPlanID
                )
            }
            guard Self.matches(completion, plan: plan) else {
                throw
                    DailyQuestStorageValidationError
                    .completionDoesNotMatchPlan(completion.id)
            }
            if completion.runKind == .today {
                guard todayCompletionIDByPlanID[completion.dailyPlanID] == nil else {
                    throw DailyQuestStorageValidationError.duplicateTodayCompletion(
                        dailyPlanID: completion.dailyPlanID
                    )
                }
                todayCompletionIDByPlanID[completion.dailyPlanID] = completion.id
            }
            completionsByID[completion.id] = completion
        }

        for grant in snapshot.rewardGrants {
            guard rewardGrantsByID[grant.id] == nil else {
                throw DailyQuestStorageValidationError.duplicateRewardGrantID(
                    grant.id
                )
            }
            guard rewardGrantIDByKey[grant.key] == nil else {
                throw DailyQuestStorageValidationError.duplicateRewardGrantKey(
                    grant.key
                )
            }
            guard let completion = completionsByID[grant.completionID] else {
                throw DailyQuestStorageValidationError.orphanRewardGrant(
                    rewardGrantID: grant.id,
                    completionID: grant.completionID
                )
            }
            guard Self.matches(grant, completion: completion) else {
                throw
                    DailyQuestStorageValidationError
                    .rewardGrantDoesNotMatchCompletion(grant.id)
            }
            guard rewardGrantIDByCompletionID[grant.completionID] == nil else {
                throw
                    DailyQuestStorageValidationError
                    .duplicateRewardForCompletion(grant.completionID)
            }
            rewardGrantsByID[grant.id] = grant
            rewardGrantIDByKey[grant.key] = grant.id
            rewardGrantIDByCompletionID[grant.completionID] = grant.id
        }

        for completion in completionsByID.values where completion.runKind == .today {
            guard rewardGrantIDByCompletionID[completion.id] != nil else {
                throw
                    DailyQuestStorageValidationError
                    .missingRewardForTodayCompletion(completion.id)
            }
        }

        for completion in snapshot.pendingCompletions {
            guard completionsByID[completion.id] == nil,
                pendingCompletionsByID[completion.id] == nil
            else {
                throw DailyQuestStorageValidationError.duplicateCompletionID(
                    completion.id
                )
            }
            pendingCompletionsByID[completion.id] = completion
        }

        for grant in snapshot.pendingRewardGrants {
            guard rewardGrantsByID[grant.id] == nil,
                pendingRewardGrantsByID[grant.id] == nil
            else {
                throw DailyQuestStorageValidationError.duplicateRewardGrantID(
                    grant.id
                )
            }
            pendingRewardGrantsByID[grant.id] = grant
        }
    }

    var snapshot: DailyQuestSnapshot {
        DailyQuestSnapshot(
            plans: plansByID.values.sorted(by: Self.planOrder),
            completions: completionsByID.values.sorted(by: Self.completionOrder),
            rewardGrants: rewardGrantsByID.values.sorted(by: Self.rewardOrder),
            pendingCompletions: pendingCompletionsByID.values.sorted(
                by: Self.completionOrder
            ),
            pendingRewardGrants: pendingRewardGrantsByID.values.sorted(
                by: Self.rewardOrder
            )
        )
    }

    func state(for key: DailyQuestKey) -> DailyQuestState {
        guard let planID = planIDByKey[key], let plan = plansByID[planID] else {
            return DailyQuestState(
                plan: nil,
                todayCompletion: nil,
                rewardGrant: nil
            )
        }
        let completion = todayCompletionIDByPlanID[planID].flatMap {
            completionsByID[$0]
        }
        let reward = completion.flatMap { completion in
            rewardGrantIDByCompletionID[completion.id].flatMap {
                rewardGrantsByID[$0]
            }
        }
        return DailyQuestState(
            plan: plan,
            todayCompletion: completion,
            rewardGrant: reward
        )
    }

    mutating func createPlanIfAbsent(_ plan: DailyQuestPlan) throws
        -> (plan: DailyQuestPlan, inserted: Bool)
    {
        if let existingID = planIDByKey[plan.key],
            let existing = plansByID[existingID]
        {
            return (existing, false)
        }
        if let existing = plansByID[plan.id] {
            guard existing == plan else {
                throw DailyQuestRepositoryError.conflictingPlanID(plan.id)
            }
            return (existing, false)
        }
        plansByID[plan.id] = plan
        planIDByKey[plan.key] = plan.id
        return (plan, true)
    }

    func completions(for key: DailyQuestKey) -> [DailyQuestCompletion] {
        completionsByID.values
            .filter { $0.key == key }
            .sorted(by: Self.completionOrder)
    }

    func completions(
        for profileID: ProfileID,
        in month: LocalMonth
    ) -> [DailyQuestCompletion] {
        completionsByID.values
            .filter { completion in
                completion.profileID == profileID
                    && month.contains(completion.localDay)
            }
            .sorted(by: Self.completionOrder)
    }

    func allCompletions(
        for profileID: ProfileID
    ) -> [DailyQuestCompletion] {
        (Array(completionsByID.values)
            + Array(pendingCompletionsByID.values))
            .filter { $0.profileID == profileID }
            .sorted(by: Self.completionOrder)
    }

    func allPlans(for profileID: ProfileID) -> [DailyQuestPlan] {
        plansByID.values
            .filter { $0.questPlan.profileID == profileID }
            .sorted { lhs, rhs in
                if lhs.key.localDay != rhs.key.localDay {
                    return lhs.key.localDay < rhs.key.localDay
                }
                return lhs.id.description < rhs.id.description
            }
    }

    func rewardGrants(for profileID: ProfileID) -> [RewardGrant] {
        (Array(rewardGrantsByID.values)
            + Array(pendingRewardGrantsByID.values))
            .filter { $0.key.profileID == profileID }
            .sorted(by: Self.rewardOrder)
    }

    /// Installs sync-layer winners as one dependency-closed candidate. Plans,
    /// Today completions, and rewards use Profile x Mode x LocalDay business
    /// identity; Practice Again remains an immutable UUID set union.
    mutating func mergeCanonical(
        _ batch: DailyQuestCanonicalMergeBatch
    ) throws -> DailyQuestCanonicalMergeResult {
        let before = snapshot
        let incomingPlans = try Self.uniquePlans(in: batch.plans)
        let incomingToday = try Self.uniqueTodayCompletions(
            in: batch.completions
        )
        let incomingPracticeAgain = try Self.uniquePracticeAgainCompletions(
            in: batch.completions
        )
        let incomingRewards = try Self.uniqueRewards(
            in: batch.rewardGrants
        )

        var plansByKey = Dictionary(
            uniqueKeysWithValues: before.plans.map { ($0.key, $0) }
        )
        var todayByKey = Dictionary(
            uniqueKeysWithValues:
                before.completions
                .filter { $0.runKind == .today }
                .map { ($0.key, $0) }
        )
        var practiceAgainByID = Dictionary(
            uniqueKeysWithValues:
                before.completions
                .filter { $0.runKind == .practiceAgain }
                .map { ($0.id, $0) }
        )
        var rewardsByKey = Dictionary(
            uniqueKeysWithValues: before.rewardGrants.map {
                ($0.key.dailyQuestKey, $0)
            }
        )

        for (key, incoming) in incomingToday where incomingRewards[key] == nil {
            guard todayByKey[key] == incoming, rewardsByKey[key] != nil else {
                throw DailyQuestRepositoryError.incompleteCanonicalToday(key)
            }
        }

        for (key, plan) in incomingPlans {
            plansByKey[key] = plan
        }
        for (key, completion) in incomingToday {
            todayByKey[key] = completion
        }
        for (key, reward) in incomingRewards {
            rewardsByKey[key] = reward
        }
        for (id, completion) in incomingPracticeAgain {
            if let existing = practiceAgainByID[id],
                !Self.samePracticeAgainFact(existing, completion)
            {
                throw DailyQuestRepositoryError.conflictingCompletionID(id)
            }
            practiceAgainByID[id] = completion
        }

        let completionKeys = Set(todayByKey.keys)
            .union(practiceAgainByID.values.map(\.key))
        let dependencyKeys = completionKeys.union(rewardsByKey.keys)
        for key in dependencyKeys where plansByKey[key] == nil {
            throw DailyQuestRepositoryError.canonicalPlanNotFound(key)
        }
        for key in Set(todayByKey.keys).union(rewardsByKey.keys) {
            guard (todayByKey[key] == nil) == (rewardsByKey[key] == nil) else {
                throw DailyQuestRepositoryError.incompleteCanonicalToday(key)
            }
        }

        let remappedToday = try todayByKey.map { key, completion in
            guard let plan = plansByKey[key] else {
                throw DailyQuestRepositoryError.canonicalPlanNotFound(key)
            }
            return Self.remap(completion, to: plan)
        }
        let remappedTodayByKey = Dictionary(
            uniqueKeysWithValues: remappedToday.map { ($0.key, $0) }
        )
        let remappedPracticeAgain = try practiceAgainByID.values.map {
            completion in
            guard let plan = plansByKey[completion.key] else {
                throw DailyQuestRepositoryError.canonicalPlanNotFound(
                    completion.key
                )
            }
            return Self.remap(completion, to: plan)
        }
        let remappedRewards = try rewardsByKey.map { key, reward in
            guard let plan = plansByKey[key] else {
                throw DailyQuestRepositoryError.canonicalPlanNotFound(key)
            }
            guard let completion = remappedTodayByKey[key] else {
                throw DailyQuestRepositoryError.incompleteCanonicalToday(key)
            }
            return Self.remap(
                reward,
                dailyPlanID: plan.id,
                completionID: completion.id
            )
        }

        let merged = try DailyQuestStorage(
            snapshot: DailyQuestSnapshot(
                plans: Array(plansByKey.values),
                completions: remappedToday + remappedPracticeAgain,
                rewardGrants: remappedRewards
            )
        )
        let after = merged.snapshot
        self = merged
        return DailyQuestCanonicalMergeResult(
            didChange: before != after,
            affectedKeys: Set(incomingPlans.keys)
                .union(incomingToday.keys)
                .union(incomingPracticeAgain.values.map(\.key))
                .union(incomingRewards.keys)
        )
    }

    /// Durably joins sync facts that may arrive in any order. Incomplete
    /// dependency chains stay outside the runtime-authoritative collections;
    /// once plan + Today completion + reward are present, all references are
    /// remapped and promoted in one value-semantic commit.
    mutating func stageCanonical(
        _ batch: DailyQuestCanonicalMergeBatch
    ) throws -> DailyQuestCanonicalMergeResult {
        let before = snapshot
        let incomingPlans = try Self.uniquePlans(in: batch.plans)
        let incomingToday = try Self.uniqueTodayCompletions(
            in: batch.completions
        )
        let incomingPracticeAgain = try Self.uniquePracticeAgainCompletions(
            in: batch.completions
        )
        let incomingRewards = try Self.uniqueRewards(in: batch.rewardGrants)

        var plansByKey = Dictionary(
            uniqueKeysWithValues: before.plans.map { ($0.key, $0) }
        )
        var todayByKey = try Self.completionFactsByKey(
            committed: before.completions.filter { $0.runKind == .today },
            pending: before.pendingCompletions.filter {
                $0.runKind == .today
            }
        )
        var practiceAgainByID = try Self.practiceAgainFactsByID(
            committed: before.completions.filter {
                $0.runKind == .practiceAgain
            },
            pending: before.pendingCompletions.filter {
                $0.runKind == .practiceAgain
            }
        )
        var rewardsByKey = try Self.rewardFactsByKey(
            committed: before.rewardGrants,
            pending: before.pendingRewardGrants
        )

        for (key, plan) in incomingPlans {
            if let existing = plansByKey[key] {
                plansByKey[key] = Self.canonicalPlanWinner(existing, plan)
            } else {
                plansByKey[key] = plan
            }
        }
        for (key, completion) in incomingToday {
            if let existing = todayByKey[key] {
                todayByKey[key] = Self.canonicalTodayWinner(
                    existing,
                    completion
                )
            } else {
                todayByKey[key] = completion
            }
        }
        for (id, completion) in incomingPracticeAgain {
            if let existing = practiceAgainByID[id],
                !Self.samePracticeAgainFact(existing, completion)
            {
                throw DailyQuestRepositoryError.conflictingCompletionID(id)
            }
            practiceAgainByID[id] = completion
        }
        for (key, reward) in incomingRewards {
            if let existing = rewardsByKey[key] {
                rewardsByKey[key] = Self.canonicalRewardWinner(
                    existing,
                    reward
                )
            } else {
                rewardsByKey[key] = reward
            }
        }

        var committedToday: [DailyQuestCompletion] = []
        var committedRewards: [RewardGrant] = []
        var pendingCompletions: [DailyQuestCompletion] = []
        var pendingRewards: [RewardGrant] = []
        let todayKeys = Set(todayByKey.keys).union(rewardsByKey.keys)
        for key in todayKeys.sorted(by: Self.dailyKeyOrder) {
            let plan = plansByKey[key]
            let completion = todayByKey[key]
            let reward = rewardsByKey[key]
            if let plan, let completion, let reward {
                let remappedCompletion = Self.remap(completion, to: plan)
                let remappedReward = Self.remap(
                    reward,
                    dailyPlanID: plan.id,
                    completionID: remappedCompletion.id
                )
                guard
                    Self.matches(
                        remappedReward,
                        completion: remappedCompletion
                    )
                else {
                    throw
                        DailyQuestRepositoryError
                        .rewardDoesNotMatchCompletion(remappedReward.id)
                }
                committedToday.append(remappedCompletion)
                committedRewards.append(remappedReward)
            } else {
                if let completion { pendingCompletions.append(completion) }
                if let reward { pendingRewards.append(reward) }
            }
        }

        var committedPracticeAgain: [DailyQuestCompletion] = []
        for completion in practiceAgainByID.values.sorted(
            by: Self.completionOrder
        ) {
            if let plan = plansByKey[completion.key] {
                committedPracticeAgain.append(Self.remap(completion, to: plan))
            } else {
                pendingCompletions.append(completion)
            }
        }

        var promoted = try DailyQuestStorage(
            snapshot: DailyQuestSnapshot(
                plans: Array(plansByKey.values),
                completions: committedToday + committedPracticeAgain,
                rewardGrants: committedRewards
            )
        )
        promoted.pendingCompletionsByID = Dictionary(
            uniqueKeysWithValues: pendingCompletions.map { ($0.id, $0) }
        )
        promoted.pendingRewardGrantsByID = Dictionary(
            uniqueKeysWithValues: pendingRewards.map { ($0.id, $0) }
        )
        let after = promoted.snapshot
        self = promoted
        return DailyQuestCanonicalMergeResult(
            didChange: before != after,
            affectedKeys: Set(incomingPlans.keys)
                .union(incomingToday.keys)
                .union(incomingPracticeAgain.values.map(\.key))
                .union(incomingRewards.keys)
        )
    }

    @discardableResult
    mutating func deleteHistory(for profileID: ProfileID) throws -> Bool {
        let current = snapshot
        let retainedPlans = current.plans.filter {
            $0.questPlan.profileID != profileID
        }
        let retainedPlanIDs = Set(retainedPlans.map(\.id))
        let retainedCompletions = current.completions.filter {
            retainedPlanIDs.contains($0.dailyPlanID)
        }
        let retainedCompletionIDs = Set(retainedCompletions.map(\.id))
        let retainedRewards = current.rewardGrants.filter {
            retainedCompletionIDs.contains($0.completionID)
        }
        let retainedPendingCompletions = current.pendingCompletions.filter {
            $0.profileID != profileID
        }
        let retainedPendingRewards = current.pendingRewardGrants.filter {
            $0.key.profileID != profileID
        }
        guard
            retainedPlans.count != current.plans.count
                || retainedCompletions.count != current.completions.count
                || retainedRewards.count != current.rewardGrants.count
                || retainedPendingCompletions.count
                    != current.pendingCompletions.count
                || retainedPendingRewards.count
                    != current.pendingRewardGrants.count
        else { return false }
        self = try DailyQuestStorage(
            snapshot: DailyQuestSnapshot(
                plans: retainedPlans,
                completions: retainedCompletions,
                rewardGrants: retainedRewards,
                pendingCompletions: retainedPendingCompletions,
                pendingRewardGrants: retainedPendingRewards
            )
        )
        return true
    }

    mutating func recordCompletion(
        _ completion: DailyQuestCompletion,
        proposedRewardGrant: RewardGrant?
    ) throws -> DailyQuestCompletionWriteResult {
        if let existing = completionsByID[completion.id] {
            guard existing == completion else {
                throw DailyQuestRepositoryError.conflictingCompletionID(
                    completion.id
                )
            }
            let reward = rewardGrantIDByCompletionID[completion.id].flatMap {
                rewardGrantsByID[$0]
            }
            return DailyQuestCompletionWriteResult(
                completion: existing,
                rewardGrant: reward,
                insertedCompletion: false,
                grantedReward: false
            )
        }

        guard let plan = plansByID[completion.dailyPlanID] else {
            throw DailyQuestRepositoryError.planNotFound(
                completion.dailyPlanID
            )
        }
        guard Self.matches(completion, plan: plan) else {
            throw DailyQuestRepositoryError.completionDoesNotMatchPlan(
                completion.id
            )
        }

        switch completion.runKind {
        case .today:
            if let existingID = todayCompletionIDByPlanID[completion.dailyPlanID] {
                throw DailyQuestRepositoryError.todayAlreadyCompleted(existingID)
            }
            guard let proposedRewardGrant else {
                throw DailyQuestRepositoryError.missingTodayReward(
                    completion.id
                )
            }
            guard Self.matches(proposedRewardGrant, completion: completion) else {
                throw DailyQuestRepositoryError.rewardDoesNotMatchCompletion(
                    proposedRewardGrant.id
                )
            }
            guard rewardGrantsByID[proposedRewardGrant.id] == nil else {
                throw DailyQuestRepositoryError.conflictingRewardGrantID(
                    proposedRewardGrant.id
                )
            }
            guard rewardGrantIDByKey[proposedRewardGrant.key] == nil else {
                throw DailyQuestRepositoryError.rewardAlreadyGranted(
                    proposedRewardGrant.key
                )
            }

            completionsByID[completion.id] = completion
            todayCompletionIDByPlanID[completion.dailyPlanID] = completion.id
            rewardGrantsByID[proposedRewardGrant.id] = proposedRewardGrant
            rewardGrantIDByKey[proposedRewardGrant.key] = proposedRewardGrant.id
            rewardGrantIDByCompletionID[completion.id] = proposedRewardGrant.id
            return DailyQuestCompletionWriteResult(
                completion: completion,
                rewardGrant: proposedRewardGrant,
                insertedCompletion: true,
                grantedReward: true
            )

        case .practiceAgain:
            guard proposedRewardGrant == nil else {
                throw DailyQuestRepositoryError.practiceAgainCannotGrantReward
            }
            completionsByID[completion.id] = completion
            return DailyQuestCompletionWriteResult(
                completion: completion,
                rewardGrant: nil,
                insertedCompletion: true,
                grantedReward: false
            )
        }
    }

    private static func matches(
        _ completion: DailyQuestCompletion,
        plan: DailyQuestPlan
    ) -> Bool {
        guard completion.dailyPlanID == plan.id, completion.key == plan.key else {
            return false
        }
        switch completion.runKind {
        case .today:
            return completion.runQuestID == plan.id
        case .practiceAgain:
            return completion.runQuestID != plan.id
        }
    }

    private static func matches(
        _ grant: RewardGrant,
        completion: DailyQuestCompletion
    ) -> Bool {
        completion.runKind == .today
            && grant.dailyPlanID == completion.dailyPlanID
            && grant.completionID == completion.id
            && grant.key.profileID == completion.profileID
            && grant.key.localDay == completion.localDay
            && grant.key.learningMode == completion.learningMode
            && grant.item.world == grant.key.world
    }

    private static func completionFactsByKey(
        committed: [DailyQuestCompletion],
        pending: [DailyQuestCompletion]
    ) throws -> [DailyQuestKey: DailyQuestCompletion] {
        var result: [DailyQuestKey: DailyQuestCompletion] = [:]
        for completion in committed + pending {
            if let existing = result[completion.key],
                existing != completion,
                existing.id != completion.id
            {
                throw
                    DailyQuestRepositoryError
                    .conflictingCanonicalTodayCompletion(completion.key)
            }
            result[completion.key] = completion
        }
        return result
    }

    private static func practiceAgainFactsByID(
        committed: [DailyQuestCompletion],
        pending: [DailyQuestCompletion]
    ) throws -> [DailyQuestCompletionID: DailyQuestCompletion] {
        var result: [DailyQuestCompletionID: DailyQuestCompletion] = [:]
        for completion in committed + pending {
            if let existing = result[completion.id],
                !samePracticeAgainFact(existing, completion)
            {
                throw DailyQuestRepositoryError.conflictingCompletionID(
                    completion.id
                )
            }
            result[completion.id] = completion
        }
        return result
    }

    private static func rewardFactsByKey(
        committed: [RewardGrant],
        pending: [RewardGrant]
    ) throws -> [DailyQuestKey: RewardGrant] {
        var result: [DailyQuestKey: RewardGrant] = [:]
        for reward in committed + pending {
            let key = reward.key.dailyQuestKey
            if let existing = result[key], existing != reward,
                existing.id != reward.id
            {
                throw DailyQuestRepositoryError.conflictingCanonicalReward(key)
            }
            result[key] = reward
        }
        return result
    }

    private static func dailyKeyOrder(
        _ left: DailyQuestKey,
        _ right: DailyQuestKey
    ) -> Bool {
        if left.profileID != right.profileID {
            return left.profileID.description < right.profileID.description
        }
        if left.localDay != right.localDay {
            return left.localDay < right.localDay
        }
        return left.learningMode.rawValue < right.learningMode.rawValue
    }

    private static func canonicalPlanWinner(
        _ left: DailyQuestPlan,
        _ right: DailyQuestPlan
    ) -> DailyQuestPlan {
        if left.questPlan.createdAt != right.questPlan.createdAt {
            return left.questPlan.createdAt > right.questPlan.createdAt
                ? left : right
        }
        return left.id.description >= right.id.description ? left : right
    }

    private static func canonicalTodayWinner(
        _ left: DailyQuestCompletion,
        _ right: DailyQuestCompletion
    ) -> DailyQuestCompletion {
        if left.completedAt != right.completedAt {
            return left.completedAt > right.completedAt ? left : right
        }
        return left.id.description >= right.id.description ? left : right
    }

    private static func canonicalRewardWinner(
        _ left: RewardGrant,
        _ right: RewardGrant
    ) -> RewardGrant {
        if left.grantedAt != right.grantedAt {
            return left.grantedAt > right.grantedAt ? left : right
        }
        return left.id.description >= right.id.description ? left : right
    }

    private static func uniquePlans(
        in plans: [DailyQuestPlan]
    ) throws -> [DailyQuestKey: DailyQuestPlan] {
        var result: [DailyQuestKey: DailyQuestPlan] = [:]
        for plan in plans {
            if let existing = result[plan.key], existing != plan {
                throw DailyQuestRepositoryError.conflictingCanonicalPlan(
                    plan.key
                )
            }
            result[plan.key] = plan
        }
        return result
    }

    private static func uniqueTodayCompletions(
        in completions: [DailyQuestCompletion]
    ) throws -> [DailyQuestKey: DailyQuestCompletion] {
        var result: [DailyQuestKey: DailyQuestCompletion] = [:]
        for completion in completions where completion.runKind == .today {
            if let existing = result[completion.key], existing != completion {
                throw
                    DailyQuestRepositoryError
                    .conflictingCanonicalTodayCompletion(completion.key)
            }
            result[completion.key] = completion
        }
        return result
    }

    private static func uniquePracticeAgainCompletions(
        in completions: [DailyQuestCompletion]
    ) throws -> [DailyQuestCompletionID: DailyQuestCompletion] {
        var result: [DailyQuestCompletionID: DailyQuestCompletion] = [:]
        for completion in completions where completion.runKind == .practiceAgain {
            if let existing = result[completion.id], existing != completion {
                throw DailyQuestRepositoryError.conflictingCompletionID(
                    completion.id
                )
            }
            result[completion.id] = completion
        }
        return result
    }

    private static func uniqueRewards(
        in rewards: [RewardGrant]
    ) throws -> [DailyQuestKey: RewardGrant] {
        var result: [DailyQuestKey: RewardGrant] = [:]
        for reward in rewards {
            let key = reward.key.dailyQuestKey
            if let existing = result[key], existing != reward {
                throw DailyQuestRepositoryError.conflictingCanonicalReward(key)
            }
            result[key] = reward
        }
        return result
    }

    private static func samePracticeAgainFact(
        _ left: DailyQuestCompletion,
        _ right: DailyQuestCompletion
    ) -> Bool {
        left.id == right.id
            && left.runQuestID == right.runQuestID
            && left.profileID == right.profileID
            && left.learningMode == right.learningMode
            && left.localDay == right.localDay
            && left.runKind == .practiceAgain
            && right.runKind == .practiceAgain
            && left.points == right.points
            && left.stars == right.stars
            && left.completedAt == right.completedAt
    }

    private static func remap(
        _ completion: DailyQuestCompletion,
        to plan: DailyQuestPlan
    ) -> DailyQuestCompletion {
        DailyQuestCompletion(
            id: completion.id,
            dailyPlanID: plan.id,
            runQuestID: completion.runKind == .today
                ? plan.id
                : completion.runQuestID,
            profileID: completion.profileID,
            learningMode: completion.learningMode,
            localDay: completion.localDay,
            runKind: completion.runKind,
            points: completion.points,
            stars: completion.stars,
            completedAt: completion.completedAt
        )
    }

    private static func remap(
        _ reward: RewardGrant,
        dailyPlanID: QuestID,
        completionID: DailyQuestCompletionID
    ) -> RewardGrant {
        RewardGrant(
            id: reward.id,
            key: reward.key,
            dailyPlanID: dailyPlanID,
            completionID: completionID,
            item: reward.item,
            grantedAt: reward.grantedAt
        )
    }

    private static func planOrder(_ left: DailyQuestPlan, _ right: DailyQuestPlan) -> Bool {
        if left.key.localDay != right.key.localDay {
            return left.key.localDay < right.key.localDay
        }
        if left.key.profileID != right.key.profileID {
            return left.key.profileID.rawValue.uuidString
                < right.key.profileID.rawValue.uuidString
        }
        return left.key.learningMode.rawValue < right.key.learningMode.rawValue
    }

    private static func completionOrder(
        _ left: DailyQuestCompletion,
        _ right: DailyQuestCompletion
    ) -> Bool {
        if left.completedAt != right.completedAt {
            return left.completedAt < right.completedAt
        }
        return left.id.rawValue.uuidString < right.id.rawValue.uuidString
    }

    private static func rewardOrder(_ left: RewardGrant, _ right: RewardGrant) -> Bool {
        if left.grantedAt != right.grantedAt {
            return left.grantedAt < right.grantedAt
        }
        return left.id.rawValue.uuidString < right.id.rawValue.uuidString
    }
}
