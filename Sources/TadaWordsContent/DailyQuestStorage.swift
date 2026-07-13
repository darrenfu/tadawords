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
    }

    var snapshot: DailyQuestSnapshot {
        DailyQuestSnapshot(
            plans: plansByID.values.sorted(by: Self.planOrder),
            completions: completionsByID.values.sorted(by: Self.completionOrder),
            rewardGrants: rewardGrantsByID.values.sorted(by: Self.rewardOrder)
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
        completionsByID.values
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
        rewardGrantsByID.values
            .filter { $0.key.profileID == profileID }
            .sorted(by: Self.rewardOrder)
    }

    @discardableResult
    mutating func deleteHistory(for profileID: ProfileID) throws -> Bool {
        let current = snapshot
        let retainedPlans = current.plans.filter {
            $0.questPlan.profileID != profileID
        }
        guard retainedPlans.count != current.plans.count else { return false }
        let retainedPlanIDs = Set(retainedPlans.map(\.id))
        let retainedCompletions = current.completions.filter {
            retainedPlanIDs.contains($0.dailyPlanID)
        }
        let retainedCompletionIDs = Set(retainedCompletions.map(\.id))
        let retainedRewards = current.rewardGrants.filter {
            retainedCompletionIDs.contains($0.completionID)
        }
        self = try DailyQuestStorage(
            snapshot: DailyQuestSnapshot(
                plans: retainedPlans,
                completions: retainedCompletions,
                rewardGrants: retainedRewards
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
