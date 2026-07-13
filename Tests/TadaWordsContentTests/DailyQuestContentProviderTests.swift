import TadaWordsContent
import TadaWordsDomain
import TadaWordsLearning
import XCTest

final class DailyQuestContentProviderTests: XCTestCase {
    func testProviderPassesProtectedInputsAndOnlySelectsUnstartedNewWords()
        async throws
    {
        let repository = InMemoryWordPoolRepository()
        _ = try await ManualWordPoolImporter(repository: repository).importBatch(
            "cat dog fox hen pig cow",
            profileID: ContentTestFixture.profileID,
            learningMode: .read,
            addedAt: ContentTestFixture.day
        )
        let entries = try await repository.entries(
            for: ContentTestFixture.profileID,
            learningMode: .read,
            includingInactive: false
        )
        let dueID = entries[0].prompt.id
        let correctionID = entries[1].prompt.id
        let startedID = entries[2].prompt.id

        let input = try await DailyQuestContentProvider(
            repository: repository,
            timeZone: ContentTestFixture.utc
        ).planningInput(
            for: DailyQuestContentRequest(
                profileID: ContentTestFixture.profileID,
                configuration: .defaultRead,
                date: ContentTestFixture.day,
                previouslyStartedWordIDs: [startedID],
                dueReviewWordIDs: [dueID],
                correctionWordIDs: [correctionID]
            )
        )

        XCTAssertEqual(input.dueReviewWordIDs, [dueID])
        XCTAssertEqual(input.correctionWordIDs, [correctionID])
        XCTAssertEqual(
            Set(input.newWordIDs),
            Set(entries.dropFirst(3).map(\.prompt.id))
        )
    }

    func testExistingPlannerAloneOwnsAttentionBudgetAndReviewDebt() async throws {
        let repository = InMemoryWordPoolRepository()
        _ = try await ManualWordPoolImporter(repository: repository).importBatch(
            "cat dog fox hen pig",
            profileID: ContentTestFixture.profileID,
            learningMode: .read,
            addedAt: ContentTestFixture.day
        )
        let dueIDs = [ContentTestFixture.wordID(90), ContentTestFixture.wordID(91)]
        let correctionID = ContentTestFixture.wordID(92)
        let configuration = QuestConfiguration(
            learningMode: .read,
            newWordLimit: 5,
            reviewWordLimit: 1,
            attentionBudget: 2,
            contentOrder: .newThenReview
        )
        let request = DailyQuestContentRequest(
            profileID: ContentTestFixture.profileID,
            configuration: configuration,
            date: ContentTestFixture.day,
            dueReviewWordIDs: dueIDs,
            correctionWordIDs: [correctionID]
        )
        let input = try await DailyQuestContentProvider(
            repository: repository,
            timeZone: ContentTestFixture.utc
        ).planningInput(for: request)

        let plan = QuestPlanner().makePlan(
            profileID: ContentTestFixture.profileID,
            configuration: configuration,
            input: input,
            createdAt: ContentTestFixture.day
        )

        XCTAssertEqual(plan.reviewWordIDs, dueIDs)
        XCTAssertEqual(plan.deferredReviewWordIDs, [correctionID])
        XCTAssertTrue(plan.newWordIDs.isEmpty)
    }

    func testProviderReadsOnlyConfiguredModePool() async throws {
        let repository = InMemoryWordPoolRepository()
        let importer = ManualWordPoolImporter(repository: repository)
        _ = try await importer.importBatch(
            "cat",
            profileID: ContentTestFixture.profileID,
            learningMode: .read,
            addedAt: ContentTestFixture.day
        )
        _ = try await importer.importBatch(
            "dog",
            profileID: ContentTestFixture.profileID,
            learningMode: .write,
            addedAt: ContentTestFixture.day
        )

        let input = try await DailyQuestContentProvider(
            repository: repository,
            timeZone: ContentTestFixture.utc
        ).planningInput(
            for: DailyQuestContentRequest(
                profileID: ContentTestFixture.profileID,
                configuration: .defaultWrite,
                date: ContentTestFixture.day
            )
        )
        let writeEntries = try await repository.entries(
            for: ContentTestFixture.profileID,
            learningMode: .write,
            includingInactive: false
        )

        XCTAssertEqual(input.newWordIDs, writeEntries.map(\.prompt.id))
    }
}
