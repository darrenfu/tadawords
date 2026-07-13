import Foundation
import TadaWordsDomain

/// Inputs are already ordered within each priority group. The planner preserves
/// that order while enforcing capacity and de-duplication rules.
public struct QuestPlanningInput: Equatable, Sendable {
    public let dueReviewWordIDs: [WordPromptID]
    public let correctionWordIDs: [WordPromptID]
    public let supplementalReviewWordIDs: [WordPromptID]
    public let newWordIDs: [WordPromptID]

    public init(
        dueReviewWordIDs: [WordPromptID],
        correctionWordIDs: [WordPromptID] = [],
        supplementalReviewWordIDs: [WordPromptID] = [],
        newWordIDs: [WordPromptID]
    ) {
        self.dueReviewWordIDs = dueReviewWordIDs
        self.correctionWordIDs = correctionWordIDs
        self.supplementalReviewWordIDs = supplementalReviewWordIDs
        self.newWordIDs = newWordIDs
    }
}

/// Reserves attention for due and correction work before considering New.
/// Content order changes presentation, never the protected capacity decision.
public struct QuestPlanner: Sendable {
    public init() {}

    public func makePlan(
        profileID: ProfileID,
        configuration: QuestConfiguration,
        input: QuestPlanningInput,
        questID: QuestID = QuestID(),
        createdAt: Date
    ) -> QuestPlan {
        let dueReviewIDs = input.dueReviewWordIDs.stableUniqued()
        let dueSet = Set(dueReviewIDs)
        let correctionIDs = input.correctionWordIDs
            .stableUniqued()
            .filter { !dueSet.contains($0) }
        let protectedReviewIDs = dueReviewIDs + correctionIDs

        let protectedSelection = protectedReviewIDs.prefix(
            configuration.attentionBudget
        )
        let deferredReviewIDs = protectedReviewIDs.dropFirst(
            protectedSelection.count
        )

        let selectedProtectedIDs = Array(protectedSelection)
        let remainingCapacity = max(
            0,
            configuration.attentionBudget - selectedProtectedIDs.count
        )

        let allProtectedSet = Set(protectedReviewIDs)
        let supplementalReviewIDs = input.supplementalReviewWordIDs
            .stableUniqued()
            .filter { !allProtectedSet.contains($0) }
        let eligibleNewIDs = input.newWordIDs
            .stableUniqued()
            .filter {
                !allProtectedSet.contains($0)
                    && !supplementalReviewIDs.contains($0)
            }

        let supplementalReviewLimit = max(
            0,
            configuration.reviewWordLimit - selectedProtectedIDs.count
        )
        let optionalSelection = selectOptionalWork(
            supplementalReviewIDs: supplementalReviewIDs,
            newWordIDs: eligibleNewIDs,
            reviewLimit: supplementalReviewLimit,
            newLimit: configuration.newWordLimit,
            capacity: remainingCapacity,
            contentOrder: configuration.contentOrder
        )

        return QuestPlan(
            id: questID,
            profileID: profileID,
            configuration: configuration,
            reviewWordIDs: selectedProtectedIDs
                + optionalSelection.supplementalReviewWordIDs,
            newWordIDs: optionalSelection.newWordIDs,
            deferredReviewWordIDs: Array(deferredReviewIDs),
            createdAt: createdAt
        )
    }

    private func selectOptionalWork(
        supplementalReviewIDs: [WordPromptID],
        newWordIDs: [WordPromptID],
        reviewLimit: Int,
        newLimit: Int,
        capacity: Int,
        contentOrder: QuestContentOrder
    ) -> OptionalWorkSelection {
        guard capacity > 0 else { return .empty }

        switch contentOrder {
        case .newThenReview:
            let selectedNewIDs = Array(newWordIDs.prefix(min(newLimit, capacity)))
            let reviewCapacity = capacity - selectedNewIDs.count
            let selectedReviewIDs = Array(
                supplementalReviewIDs.prefix(min(reviewLimit, reviewCapacity))
            )
            return OptionalWorkSelection(
                supplementalReviewWordIDs: selectedReviewIDs,
                newWordIDs: selectedNewIDs
            )

        case .reviewThenNew:
            let selectedReviewIDs = Array(
                supplementalReviewIDs.prefix(min(reviewLimit, capacity))
            )
            let newCapacity = capacity - selectedReviewIDs.count
            let selectedNewIDs = Array(newWordIDs.prefix(min(newLimit, newCapacity)))
            return OptionalWorkSelection(
                supplementalReviewWordIDs: selectedReviewIDs,
                newWordIDs: selectedNewIDs
            )
        }
    }
}

private struct OptionalWorkSelection {
    let supplementalReviewWordIDs: [WordPromptID]
    let newWordIDs: [WordPromptID]

    static let empty = OptionalWorkSelection(
        supplementalReviewWordIDs: [],
        newWordIDs: []
    )
}

extension Array where Element: Hashable {
    fileprivate func stableUniqued() -> [Element] {
        var seen = Set<Element>()
        return filter { seen.insert($0).inserted }
    }
}
