import Foundation
import TadaWordsDomain
import TadaWordsLearning

public struct DailyQuestContentRequest: Sendable {
    public let profileID: ProfileID
    public let configuration: QuestConfiguration
    public let date: Date
    public let previouslyStartedWordIDs: Set<WordPromptID>
    public let dueReviewWordIDs: [WordPromptID]
    public let correctionWordIDs: [WordPromptID]
    public let supplementalReviewWordIDs: [WordPromptID]

    public init(
        profileID: ProfileID,
        configuration: QuestConfiguration,
        date: Date,
        previouslyStartedWordIDs: Set<WordPromptID> = [],
        dueReviewWordIDs: [WordPromptID] = [],
        correctionWordIDs: [WordPromptID] = [],
        supplementalReviewWordIDs: [WordPromptID] = []
    ) {
        self.profileID = profileID
        self.configuration = configuration
        self.date = date
        self.previouslyStartedWordIDs = previouslyStartedWordIDs
        self.dueReviewWordIDs = dueReviewWordIDs
        self.correctionWordIDs = correctionWordIDs
        self.supplementalReviewWordIDs = supplementalReviewWordIDs
    }
}

/// Bridges pool selection to the existing Learning planner without making any
/// due-review or attention-budget decisions itself.
public struct DailyQuestContentProvider: Sendable {
    private let repository: any WordPoolRepository
    private let selector: DailyNewWordSelector

    public init(
        repository: any WordPoolRepository,
        timeZone: TimeZone
    ) {
        self.repository = repository
        self.selector = DailyNewWordSelector(timeZone: timeZone)
    }

    public func planningInput(
        for request: DailyQuestContentRequest
    ) async throws -> QuestPlanningInput {
        let entries = try await repository.entries(
            for: request.profileID,
            learningMode: request.configuration.learningMode,
            includingInactive: false
        )
        let protectedWordIDs = Set(
            request.dueReviewWordIDs
                + request.correctionWordIDs
                + request.supplementalReviewWordIDs
        )
        let excludedWordIDs = request.previouslyStartedWordIDs.union(
            protectedWordIDs
        )
        let selectedNewEntries = selector.select(
            from: entries,
            request: DailyNewWordSelectionRequest(
                profileID: request.profileID,
                learningMode: request.configuration.learningMode,
                date: request.date,
                limit: request.configuration.newWordLimit,
                excludingWordPromptIDs: excludedWordIDs
            )
        )

        return QuestPlanningInput(
            dueReviewWordIDs: request.dueReviewWordIDs,
            correctionWordIDs: request.correctionWordIDs,
            supplementalReviewWordIDs: request.supplementalReviewWordIDs,
            newWordIDs: selectedNewEntries.map(\.prompt.id)
        )
    }
}
