import TadaWordsDomain
import XCTest

@testable import TadaWordsLearning

final class QuestScorerTests: XCTestCase {
    func testEightyPercentAccuracyAndComfortablePaceEarnAllStars() {
        let wordIDs = (1...5).map(TestFixture.wordID)
        let plan = makePlan(wordIDs: wordIDs)
        let attempts = (1...5).map { number in
            TestFixture.attempt(
                number: number,
                wordNumber: number,
                outcome: number <= 4 ? .correct : .incorrect,
                at: TestFixture.now.addingTimeInterval(Double(number))
            )
        }
        let context = TestFixture.paceContext()
        let contexts = Dictionary(
            uniqueKeysWithValues: wordIDs.map { ($0, context) }
        )

        let score = QuestScorer().score(
            QuestScoringInput(
                plan: plan,
                completedWordIDs: Set(wordIDs),
                attempts: attempts,
                paceContextByWordID: contexts,
                personalPaceBands: [TestFixture.paceBand(context: context)]
            )
        )

        XCTAssertEqual(score.firstIndependentAttemptCount, 5)
        XCTAssertEqual(score.firstIndependentCorrectCount, 4)
        XCTAssertEqual(score.points, 84)
        XCTAssertEqual(score.personalPaceAssessment, .withinPersonalBand)
        XCTAssertEqual(
            score.stars.earned,
            [.completion, .accuracy, .personalPace]
        )
    }

    func testTechnicalUncertainGuidedAndDuplicateFirstAttemptsAreExcluded() {
        let wordIDs = (1...3).map(TestFixture.wordID)
        let plan = makePlan(wordIDs: wordIDs)
        let attempts = [
            TestFixture.attempt(number: 1, wordNumber: 1, outcome: .incorrect),
            TestFixture.attempt(
                number: 2,
                wordNumber: 1,
                outcome: .correct,
                at: TestFixture.now.addingTimeInterval(1)
            ),
            TestFixture.attempt(
                number: 3,
                wordNumber: 2,
                evidence: .technicalRetry,
                outcome: .technicalFailure(.noUsableAudio)
            ),
            TestFixture.attempt(
                number: 4,
                wordNumber: 2,
                evidence: .recognitionUncertain,
                outcome: .recognitionUncertain
            ),
            TestFixture.attempt(
                number: 5,
                wordNumber: 3,
                evidence: .guidedRetry,
                outcome: .correct
            ),
        ]

        let score = QuestScorer().score(
            QuestScoringInput(
                plan: plan,
                completedWordIDs: Set(wordIDs),
                attempts: attempts
            )
        )

        XCTAssertEqual(score.firstIndependentAttemptCount, 1)
        XCTAssertEqual(score.firstIndependentCorrectCount, 0)
        XCTAssertEqual(score.points, 0)
        XCTAssertEqual(score.stars.earned, [.completion])
        XCTAssertEqual(score.personalPaceAssessment, .unavailable)
    }

    func testCorrectionChangesEffectiveScoreWithoutMutatingAttempt() {
        let original = TestFixture.attempt(
            number: 1,
            wordNumber: 1,
            outcome: .incorrect
        )
        let correction = AttemptCorrectionEvent(
            originalAttemptID: original.id,
            correctedOutcome: .correct,
            reason: .guardianOverride,
            correctedAt: TestFixture.now.addingTimeInterval(1)
        )
        let context = TestFixture.paceContext()
        let plan = makePlan(wordIDs: [original.wordPromptID])

        let score = QuestScorer().score(
            QuestScoringInput(
                plan: plan,
                completedWordIDs: [original.wordPromptID],
                attempts: [original],
                corrections: [correction],
                paceContextByWordID: [original.wordPromptID: context],
                personalPaceBands: [TestFixture.paceBand(context: context)]
            )
        )

        XCTAssertEqual(score.points, 100)
        XCTAssertEqual(score.firstIndependentCorrectCount, 1)
        XCTAssertEqual(original.outcome, .incorrect)
    }

    func testCalibrationIsNeutralAndDoesNotAwardPaceStar() {
        let attempt = TestFixture.attempt(
            number: 1,
            wordNumber: 1,
            outcome: .correct
        )
        let context = TestFixture.paceContext()
        let score = QuestScorer().score(
            QuestScoringInput(
                plan: makePlan(wordIDs: [attempt.wordPromptID]),
                completedWordIDs: [attempt.wordPromptID],
                attempts: [attempt],
                paceContextByWordID: [attempt.wordPromptID: context],
                personalPaceBands: [
                    TestFixture.paceBand(context: context, sampleCount: 2)
                ]
            )
        )

        XCTAssertEqual(score.points, 100)
        XCTAssertEqual(
            score.personalPaceAssessment,
            .calibrating(sampleCount: 2, requiredSampleCount: 3)
        )
        XCTAssertTrue(score.stars.contains(.completion))
        XCTAssertTrue(score.stars.contains(.accuracy))
        XCTAssertFalse(score.stars.contains(.personalPace))
    }

    func testTooFastResponseDoesNotEarnPaceStar() {
        let attempt = TestFixture.attempt(
            number: 1,
            wordNumber: 1,
            outcome: .correct,
            responseSeconds: 0.2
        )
        let context = TestFixture.paceContext()
        let score = QuestScorer().score(
            QuestScoringInput(
                plan: makePlan(wordIDs: [attempt.wordPromptID]),
                completedWordIDs: [attempt.wordPromptID],
                attempts: [attempt],
                paceContextByWordID: [attempt.wordPromptID: context],
                personalPaceBands: [TestFixture.paceBand(context: context)]
            )
        )

        XCTAssertEqual(score.points, 80)
        XCTAssertEqual(score.personalPaceAssessment, .outsidePersonalBand)
        XCTAssertFalse(score.stars.contains(.personalPace))
    }

    func testMissingTimingCannotProducePaceStarFromPartialData() {
        let timedAttempt = TestFixture.attempt(
            number: 1,
            wordNumber: 1,
            outcome: .correct,
            responseSeconds: 2
        )
        let untimedAttempt = TestFixture.attempt(
            number: 2,
            wordNumber: 2,
            outcome: .correct,
            at: TestFixture.now.addingTimeInterval(1),
            responseSeconds: nil
        )
        let context = TestFixture.paceContext()
        let score = QuestScorer().score(
            QuestScoringInput(
                plan: makePlan(
                    wordIDs: [
                        timedAttempt.wordPromptID,
                        untimedAttempt.wordPromptID,
                    ]
                ),
                completedWordIDs: [
                    timedAttempt.wordPromptID,
                    untimedAttempt.wordPromptID,
                ],
                attempts: [timedAttempt, untimedAttempt],
                paceContextByWordID: [
                    timedAttempt.wordPromptID: context,
                    untimedAttempt.wordPromptID: context,
                ],
                personalPaceBands: [TestFixture.paceBand(context: context)]
            )
        )

        XCTAssertEqual(score.personalPaceAssessment, .unavailable)
        XCTAssertFalse(score.stars.contains(.personalPace))
        XCTAssertEqual(score.points, 80)
    }

    private func makePlan(wordIDs: [WordPromptID]) -> QuestPlan {
        QuestPlan(
            id: TestFixture.questID,
            profileID: TestFixture.profileID,
            configuration: .defaultRead,
            reviewWordIDs: [],
            newWordIDs: wordIDs,
            createdAt: TestFixture.now
        )
    }
}
