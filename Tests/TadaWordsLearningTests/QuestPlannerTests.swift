import TadaWordsDomain
import XCTest

@testable import TadaWordsLearning

final class QuestPlannerTests: XCTestCase {
    func testProtectedWorkConsumesBudgetAndCreatesExplicitReviewDebt() {
        let due = (1...4).map(TestFixture.wordID)
        let correction = TestFixture.wordID(5)
        let configuration = QuestConfiguration(
            learningMode: .read,
            newWordLimit: 5,
            reviewWordLimit: 3,
            attentionBudget: 3,
            contentOrder: .newThenReview
        )

        let plan = QuestPlanner().makePlan(
            profileID: TestFixture.profileID,
            configuration: configuration,
            input: QuestPlanningInput(
                dueReviewWordIDs: due,
                correctionWordIDs: [correction],
                newWordIDs: [TestFixture.wordID(6)]
            ),
            questID: TestFixture.questID,
            createdAt: TestFixture.now
        )

        XCTAssertEqual(plan.reviewWordIDs, Array(due.prefix(3)))
        XCTAssertEqual(plan.deferredReviewWordIDs, [due[3], correction])
        XCTAssertTrue(plan.newWordIDs.isEmpty)
        XCTAssertTrue(plan.hasReviewDebt)
    }

    func testNewFirstChangesPresentationButCannotDisplaceProtectedWork() {
        let protected = (1...3).map(TestFixture.wordID)
        let new = (4...7).map(TestFixture.wordID)
        let configuration = QuestConfiguration(
            learningMode: .read,
            newWordLimit: 5,
            reviewWordLimit: 1,
            attentionBudget: 5,
            contentOrder: .newThenReview
        )

        let plan = QuestPlanner().makePlan(
            profileID: TestFixture.profileID,
            configuration: configuration,
            input: QuestPlanningInput(
                dueReviewWordIDs: Array(protected.prefix(2)),
                correctionWordIDs: [protected[2]],
                newWordIDs: new
            ),
            createdAt: TestFixture.now
        )

        XCTAssertEqual(plan.reviewWordIDs, protected)
        XCTAssertEqual(plan.newWordIDs, Array(new.prefix(2)))
        XCTAssertEqual(
            plan.orderedItems.map(\.source),
            [.new, .new, .review, .review, .review]
        )
    }

    func testReviewFirstUsesSupplementalReviewBeforeNewWithinBudget() {
        let supplemental = (1...3).map(TestFixture.wordID)
        let new = (4...6).map(TestFixture.wordID)
        let configuration = QuestConfiguration(
            learningMode: .write,
            newWordLimit: 3,
            reviewWordLimit: 2,
            attentionBudget: 4,
            contentOrder: .reviewThenNew
        )

        let plan = QuestPlanner().makePlan(
            profileID: TestFixture.profileID,
            configuration: configuration,
            input: QuestPlanningInput(
                dueReviewWordIDs: [],
                supplementalReviewWordIDs: supplemental,
                newWordIDs: new
            ),
            createdAt: TestFixture.now
        )

        XCTAssertEqual(plan.reviewWordIDs, Array(supplemental.prefix(2)))
        XCTAssertEqual(plan.newWordIDs, Array(new.prefix(2)))
        XCTAssertEqual(
            plan.orderedItems.map(\.source),
            [.review, .review, .new, .new]
        )
    }

    func testReviewCategoryWinsWhenInputsContainDuplicates() {
        let word = TestFixture.wordID(1)
        let plan = QuestPlanner().makePlan(
            profileID: TestFixture.profileID,
            configuration: .defaultRead,
            input: QuestPlanningInput(
                dueReviewWordIDs: [word, word],
                correctionWordIDs: [word],
                supplementalReviewWordIDs: [word],
                newWordIDs: [word, word]
            ),
            createdAt: TestFixture.now
        )

        XCTAssertEqual(plan.reviewWordIDs, [word])
        XCTAssertTrue(plan.newWordIDs.isEmpty)
        XCTAssertTrue(plan.deferredReviewWordIDs.isEmpty)
    }
}
