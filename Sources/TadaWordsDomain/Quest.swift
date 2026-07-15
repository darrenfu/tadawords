import Foundation

public enum QuestContentOrder: String, Codable, CaseIterable, Hashable, Sendable {
    case newThenReview
    case reviewThenNew
}

public struct QuestConfiguration: Codable, Hashable, Sendable {
    public let learningMode: LearningMode
    public let newWordLimit: Int
    public let reviewWordLimit: Int
    public let attentionBudget: Int
    public let contentOrder: QuestContentOrder

    public init(
        learningMode: LearningMode,
        newWordLimit: Int,
        reviewWordLimit: Int,
        attentionBudget: Int,
        contentOrder: QuestContentOrder
    ) {
        self.learningMode = learningMode
        self.newWordLimit = max(0, newWordLimit)
        self.reviewWordLimit = max(0, reviewWordLimit)
        self.attentionBudget = max(0, attentionBudget)
        self.contentOrder = contentOrder
    }

    public static let defaultRead = QuestConfiguration(
        learningMode: .read,
        newWordLimit: 5,
        reviewWordLimit: 5,
        attentionBudget: 10,
        contentOrder: .newThenReview
    )

    public static let defaultWrite = QuestConfiguration(
        learningMode: .write,
        newWordLimit: 5,
        reviewWordLimit: 5,
        attentionBudget: 10,
        contentOrder: .newThenReview
    )
}

public enum QuestItemSource: String, Codable, CaseIterable, Hashable, Sendable {
    case review
    case new
}

public struct QuestPlanItem: Codable, Hashable, Sendable {
    public let wordPromptID: WordPromptID
    public let source: QuestItemSource

    public init(wordPromptID: WordPromptID, source: QuestItemSource) {
        self.wordPromptID = wordPromptID
        self.source = source
    }
}

public struct QuestPlan: Codable, Hashable, Sendable {
    public let id: QuestID
    public let profileID: ProfileID
    public let configuration: QuestConfiguration
    public let reviewWordIDs: [WordPromptID]
    public let newWordIDs: [WordPromptID]
    public let deferredReviewWordIDs: [WordPromptID]
    public let createdAt: Date

    public init(
        id: QuestID = QuestID(),
        profileID: ProfileID,
        configuration: QuestConfiguration,
        reviewWordIDs: [WordPromptID],
        newWordIDs: [WordPromptID],
        deferredReviewWordIDs: [WordPromptID] = [],
        createdAt: Date
    ) {
        let selectedReviewWordIDs = Self.uniqued(reviewWordIDs)
        let deferredReviewWordIDs = Self.uniqued(deferredReviewWordIDs).filter {
            !selectedReviewWordIDs.contains($0)
        }
        let dueWordIDs = Set(selectedReviewWordIDs + deferredReviewWordIDs)

        self.id = id
        self.profileID = profileID
        self.configuration = configuration
        self.reviewWordIDs = selectedReviewWordIDs
        self.newWordIDs = Self.uniqued(newWordIDs).filter {
            !dueWordIDs.contains($0)
        }
        self.deferredReviewWordIDs = deferredReviewWordIDs
        self.createdAt = createdAt
    }

    public var orderedItems: [QuestPlanItem] {
        let reviewItems = reviewWordIDs.map {
            QuestPlanItem(wordPromptID: $0, source: .review)
        }
        let newItems = newWordIDs.map {
            QuestPlanItem(wordPromptID: $0, source: .new)
        }

        switch configuration.contentOrder {
        case .newThenReview:
            return newItems + reviewItems
        case .reviewThenNew:
            return reviewItems + newItems
        }
    }

    public var hasReviewDebt: Bool {
        !deferredReviewWordIDs.isEmpty
    }

    private static func uniqued(_ values: [WordPromptID]) -> [WordPromptID] {
        var seen: Set<WordPromptID> = []
        return values.filter { seen.insert($0).inserted }
    }
}
