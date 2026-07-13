import Foundation
import TadaWordsDomain
import XCTest

@testable import TadaWordsFeatures

final class ProblemNewReviewReplacementTests: XCTestCase {
    func testProblemNewDropsLowestPriorityReviewAndKeepsItAsDebt() {
        let plan = makePlan(order: .newThenReview)
        let attempt = makeAttempt(
            wordID: plan.newWordIDs[0],
            evidence: .firstIndependentAttempt,
            outcome: .incorrect
        )

        let adjusted = ProblemNewReviewReplacement().adjustedPlan(
            plan,
            attempts: [attempt],
            personalPaceBands: []
        )

        XCTAssertEqual(adjusted.reviewWordIDs, Array(plan.reviewWordIDs.prefix(1)))
        XCTAssertEqual(adjusted.deferredReviewWordIDs, [plan.reviewWordIDs[1]])
        XCTAssertEqual(adjusted.newWordIDs, plan.newWordIDs)
        XCTAssertEqual(adjusted.orderedItems.count, plan.orderedItems.count - 1)
    }

    func testHelpUncertainReplayAndRelativeSlowEachMarkNewAsProblematic() {
        let plan = makePlan(order: .newThenReview)
        let wordID = plan.newWordIDs[0]
        let context = PaceContext(
            learningMode: .read,
            deviceClass: .tablet,
            inputMethod: .speech,
            wordLength: 3
        )
        let band = PersonalPaceBand(
            context: context,
            lowerBound: ElapsedTime(seconds: 1),
            upperBound: ElapsedTime(seconds: 3),
            sampleCount: 3
        )
        let signals: [AttemptEvent] = [
            makeAttempt(wordID: wordID, evidence: .helped, outcome: .skipped),
            makeAttempt(
                wordID: wordID,
                evidence: .recognitionUncertain,
                outcome: .recognitionUncertain
            ),
            makeAttempt(
                wordID: wordID,
                evidence: .firstIndependentAttempt,
                outcome: .correct,
                replayCount: 1
            ),
            makeAttempt(
                wordID: wordID,
                evidence: .firstIndependentAttempt,
                outcome: .correct,
                responseSeconds: 6,
                paceContext: context
            ),
        ]

        for signal in signals {
            let adjusted = ProblemNewReviewReplacement().adjustedPlan(
                plan,
                attempts: [signal],
                personalPaceBands: [band]
            )
            XCTAssertEqual(adjusted.reviewWordIDs.count, 1)
        }
    }

    func testReviewFirstNeverChangesCurrentRun() {
        let plan = makePlan(order: .reviewThenNew)
        let attempt = makeAttempt(
            wordID: plan.newWordIDs[0],
            evidence: .firstIndependentAttempt,
            outcome: .incorrect
        )

        XCTAssertEqual(
            ProblemNewReviewReplacement().adjustedPlan(
                plan,
                attempts: [attempt],
                personalPaceBands: []
            ),
            plan
        )
    }

    func testRecalculationFromStableBaseDropsOneReviewPerUniqueProblem() {
        let plan = makePlan(order: .newThenReview)
        let attempts = plan.newWordIDs.map {
            makeAttempt(
                wordID: $0,
                evidence: .firstIndependentAttempt,
                outcome: .incorrect
            )
        }

        let adjusted = ProblemNewReviewReplacement().adjustedPlan(
            plan,
            attempts: attempts,
            personalPaceBands: []
        )

        XCTAssertTrue(adjusted.reviewWordIDs.isEmpty)
        XCTAssertEqual(adjusted.deferredReviewWordIDs, plan.reviewWordIDs)
    }

    private func makePlan(order: QuestContentOrder) -> QuestPlan {
        QuestPlan(
            profileID: ProfileID(),
            configuration: QuestConfiguration(
                learningMode: .read,
                newWordLimit: 2,
                reviewWordLimit: 2,
                attentionBudget: 4,
                contentOrder: order
            ),
            reviewWordIDs: [WordPromptID(), WordPromptID()],
            newWordIDs: [WordPromptID(), WordPromptID()],
            createdAt: Date(timeIntervalSince1970: 1)
        )
    }

    private func makeAttempt(
        wordID: WordPromptID,
        evidence: EncounterEvidence,
        outcome: AttemptOutcome,
        replayCount: Int = 0,
        responseSeconds: TimeInterval = 2,
        paceContext: PaceContext? = nil
    ) -> AttemptEvent {
        AttemptEvent(
            profileID: ProfileID(),
            wordPromptID: wordID,
            learningMode: .read,
            evidence: evidence,
            outcome: outcome,
            timing: AttemptTiming(
                totalResponseTime: ElapsedTime(seconds: responseSeconds),
                speechOnsetLatency: ElapsedTime(seconds: responseSeconds)
            ),
            occurredAt: Date(timeIntervalSince1970: 2),
            replayCount: replayCount,
            paceContext: paceContext
        )
    }
}
