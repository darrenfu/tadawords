import TadaWordsDomain
import XCTest

@testable import TadaWordsFeatures

final class QuestAttemptStateMachineTests: XCTestCase {
    func testFirstIndependentMatchRecordsSuccessWithoutClaimingLongTermMastery() throws {
        var machine = QuestAttemptStateMachine()

        XCTAssertTrue(machine.beginAttempt())
        machine.receive(result(.matched))

        let summary = try XCTUnwrap(machine.completedSummary)
        XCTAssertEqual(summary.completion, .independentSuccess)
        XCTAssertEqual(summary.validAttemptCount, 1)
        XCTAssertEqual(summary.records.map(\.evidence), [.firstIndependentAttempt])
        XCTAssertEqual(summary.records.map(\.outcome), [.correct])
    }

    func testCorrectRetryCompletesWithoutEstablishingMastery() throws {
        var machine = QuestAttemptStateMachine()

        XCTAssertTrue(machine.beginAttempt())
        machine.receive(result(.notMatched))
        XCTAssertEqual(machine.phase, .feedback(.tryAgain(remainingAttempts: 1)))

        XCTAssertTrue(machine.beginAttempt())
        machine.receive(result(.matched))

        let summary = try XCTUnwrap(machine.completedSummary)
        XCTAssertEqual(summary.completion, .completedAfterRetry)
        XCTAssertTrue(summary.earnsItemStar)
        XCTAssertEqual(summary.firstIndependentOutcome, .incorrect)
        XCTAssertEqual(summary.finalResponseOutcome, .correct)
        XCTAssertEqual(summary.validAttemptCount, 2)
        XCTAssertEqual(
            summary.records.map(\.evidence),
            [.firstIndependentAttempt, .unaidedRetry]
        )
    }

    func testDefaultTwoIncorrectAnswersIsHardLimit() throws {
        var machine = QuestAttemptStateMachine()

        XCTAssertTrue(machine.beginAttempt())
        machine.receive(result(.notMatched))
        XCTAssertEqual(machine.phase, .feedback(.tryAgain(remainingAttempts: 1)))

        XCTAssertTrue(machine.beginAttempt())
        machine.receive(result(.notMatched))

        let summary = try XCTUnwrap(machine.completedSummary)
        XCTAssertEqual(summary.completion, .needsPractice)
        XCTAssertFalse(summary.earnsItemStar)
        XCTAssertEqual(summary.validAttemptCount, 2)
        XCTAssertEqual(machine.incorrectAttemptCount, 2)
        XCTAssertEqual(machine.remainingIncorrectAttemptCount, 0)
        XCTAssertFalse(machine.beginAttempt())
    }

    func testReadUncertainRecognitionConsumesRetryBudget() throws {
        var machine = QuestAttemptStateMachine(policy: .read)

        XCTAssertTrue(machine.beginAttempt())
        machine.receive(result(.uncertain))
        XCTAssertEqual(machine.phase, .feedback(.tryAgain(remainingAttempts: 1)))
        XCTAssertEqual(machine.submissionCount, 1)
        XCTAssertEqual(machine.incorrectAttemptCount, 1)
        XCTAssertEqual(machine.validAttemptCount, 0)

        XCTAssertTrue(machine.beginAttempt())
        machine.receive(result(.uncertain))

        let summary = try XCTUnwrap(machine.completedSummary)
        XCTAssertEqual(summary.completion, .needsPractice)
        XCTAssertEqual(machine.submissionCount, 2)
        XCTAssertEqual(machine.incorrectAttemptCount, 2)
        XCTAssertEqual(summary.validAttemptCount, 0)
        XCTAssertEqual(
            summary.records.map(\.evidence),
            [.recognitionUncertain, .recognitionUncertain]
        )
    }

    func testReadAudibilityFailuresConsumeRetryBudget() throws {
        var machine = QuestAttemptStateMachine(policy: .read)

        XCTAssertTrue(machine.beginAttempt())
        machine.receive(result(.technicalFailure(.timedOut)))
        XCTAssertEqual(machine.phase, .feedback(.tryAgain(remainingAttempts: 1)))

        XCTAssertTrue(machine.beginAttempt())
        machine.receive(result(.technicalFailure(.noUsableAudio)))

        let summary = try XCTUnwrap(machine.completedSummary)
        XCTAssertEqual(summary.completion, .needsPractice)
        XCTAssertEqual(machine.incorrectAttemptCount, 2)
        XCTAssertEqual(summary.validAttemptCount, 0)
        XCTAssertEqual(
            summary.records.map(\.outcome),
            [
                .technicalFailure(.timedOut),
                .technicalFailure(.noUsableAudio),
            ]
        )
    }

    func testCorrectAfterUnclearReadIsCompletedAfterRetry() throws {
        var machine = QuestAttemptStateMachine(policy: .read)

        XCTAssertTrue(machine.beginAttempt())
        machine.receive(result(.uncertain))
        XCTAssertTrue(machine.beginAttempt())
        machine.receive(result(.matched))

        let summary = try XCTUnwrap(machine.completedSummary)
        XCTAssertEqual(summary.completion, .completedAfterRetry)
        XCTAssertEqual(summary.validAttemptCount, 1)
    }

    func testCustomFiveIncorrectAnswerLimitIsHonored() throws {
        var machine = QuestAttemptStateMachine(incorrectAttemptLimit: 5)

        for remainingAttempts in [4, 3, 2, 1] {
            XCTAssertTrue(machine.beginAttempt())
            machine.receive(result(.notMatched))
            XCTAssertEqual(
                machine.phase,
                .feedback(.tryAgain(remainingAttempts: remainingAttempts))
            )
        }

        XCTAssertTrue(machine.beginAttempt())
        machine.receive(result(.notMatched))
        XCTAssertEqual(machine.completedSummary?.completion, .needsPractice)
        XCTAssertEqual(machine.incorrectAttemptCount, 5)
    }

    func testIncorrectAnswerLimitClampsToInternalSafetyRange() {
        XCTAssertEqual(
            QuestAttemptStateMachine(incorrectAttemptLimit: 0)
                .incorrectAttemptLimit,
            1
        )
        XCTAssertEqual(
            QuestAttemptStateMachine(incorrectAttemptLimit: 99)
                .incorrectAttemptLimit,
            5
        )
    }

    func testWriteTechnicalAndUncertainResultsDoNotConsumeAttemptsOrBecomeWrongEvidence()
        throws
    {
        var machine = QuestAttemptStateMachine(policy: .write)

        XCTAssertTrue(machine.beginAttempt())
        machine.receive(result(.technicalFailure(.permissionDenied)))
        XCTAssertEqual(machine.validAttemptCount, 0)
        XCTAssertEqual(machine.remainingIncorrectAttemptCount, 3)

        XCTAssertTrue(machine.beginAttempt())
        machine.receive(result(.uncertain))
        XCTAssertEqual(machine.validAttemptCount, 0)
        XCTAssertEqual(machine.remainingIncorrectAttemptCount, 3)

        XCTAssertTrue(machine.beginAttempt())
        machine.receive(result(.matched))

        let summary = try XCTUnwrap(machine.completedSummary)
        XCTAssertEqual(summary.completion, .independentSuccess)
        XCTAssertEqual(
            summary.records.map(\.evidence),
            [.technicalRetry, .recognitionUncertain, .firstIndependentAttempt]
        )
        XCTAssertEqual(
            summary.records.map(\.outcome),
            [
                .technicalFailure(.permissionDenied),
                .recognitionUncertain,
                .correct,
            ]
        )
    }

    func testGuidanceBeforeFirstResponseCanNeverEstablishMastery() throws {
        var machine = QuestAttemptStateMachine()

        machine.useGuidance()
        XCTAssertTrue(machine.beginAttempt())
        machine.receive(result(.matched), replayCount: 2)

        let summary = try XCTUnwrap(machine.completedSummary)
        XCTAssertEqual(summary.completion, .completedWithGuidance)
        XCTAssertTrue(summary.earnsItemStar)
        XCTAssertEqual(summary.promptReplayCount, 2)
        XCTAssertEqual(summary.guidanceExposureCount, 1)
        XCTAssertTrue(summary.usedGuidance)
        XCTAssertEqual(summary.validAttemptCount, 1)
        XCTAssertEqual(summary.records.map(\.evidence), [.helped, .guidedRetry])
        XCTAssertFalse(summary.records.contains { $0.evidence.canUpdateMemory })
    }

    func testMismatchedSpeakerIsTechnicalAndCannotConsumeAnAttempt() {
        var machine = QuestAttemptStateMachine()

        XCTAssertTrue(machine.beginAttempt())
        machine.receive(
            RecognitionResult(
                decision: .matched,
                confidence: RecognitionConfidence(0.99),
                targetSpeakerAssessment: .mismatched
            )
        )

        XCTAssertEqual(machine.validAttemptCount, 0)
        XCTAssertEqual(machine.remainingIncorrectAttemptCount, 2)
        XCTAssertEqual(machine.phase, .feedback(.technicalRetry(.wrongSpeaker)))
        XCTAssertEqual(machine.records.map(\.evidence), [.technicalRetry])
        XCTAssertEqual(machine.records.map(\.outcome), [.technicalFailure(.wrongSpeaker)])
    }

    func testGuidanceAfterWrongResponseKeepsLaterCorrectResponseGuided() throws {
        var machine = QuestAttemptStateMachine()

        XCTAssertTrue(machine.beginAttempt())
        machine.receive(result(.notMatched))
        machine.useGuidance()
        XCTAssertTrue(machine.beginAttempt())
        machine.receive(result(.matched))

        let summary = try XCTUnwrap(machine.completedSummary)
        XCTAssertEqual(summary.completion, .completedWithGuidance)
        XCTAssertEqual(
            summary.records.map(\.evidence),
            [.firstIndependentAttempt, .helped, .guidedRetry]
        )
    }

    func testCancelledRecognitionDoesNotConsumeAttempt() {
        var machine = QuestAttemptStateMachine()

        XCTAssertTrue(machine.beginAttempt())
        machine.cancelAttempt()

        XCTAssertEqual(machine.phase, .ready)
        XCTAssertEqual(machine.validAttemptCount, 0)
        XCTAssertTrue(machine.records.isEmpty)
        XCTAssertTrue(machine.beginAttempt())
    }

    func testAttemptMetadataTravelsWithImmutableRecord() throws {
        var machine = QuestAttemptStateMachine()
        let timing = AttemptTiming(
            totalResponseTime: ElapsedTime(seconds: 4.2),
            firstStrokeLatency: ElapsedTime(seconds: 1.1),
            replayPauseTime: ElapsedTime(seconds: 0.8)
        )

        XCTAssertTrue(machine.beginAttempt())
        machine.receive(
            result(.matched),
            timing: timing,
            replayCount: 2
        )

        let record = try XCTUnwrap(machine.completedSummary?.records.first)
        XCTAssertEqual(record.timing, timing)
        XCTAssertEqual(record.replayCount, 2)
    }

    func testThreeConsecutiveTechnicalIssuesOfferNeutralSkip() throws {
        var machine = QuestAttemptStateMachine()

        for index in 1...QuestAttemptStateMachine.technicalIssueSkipThreshold {
            XCTAssertTrue(machine.beginAttempt())
            machine.receive(result(.technicalFailure(.serviceUnavailable)))
            XCTAssertEqual(machine.validAttemptCount, 0)
            XCTAssertEqual(machine.consecutiveTechnicalIssueCount, index)
        }

        XCTAssertTrue(machine.canSkipAfterTechnicalIssues)
        XCTAssertTrue(machine.skipAfterTechnicalIssues())
        let summary = try XCTUnwrap(machine.completedSummary)
        XCTAssertEqual(summary.completion, .needsPractice)
        XCTAssertEqual(summary.validAttemptCount, 0)
        XCTAssertEqual(
            summary.records.map(\.evidence),
            [.technicalRetry, .technicalRetry, .technicalRetry]
        )
    }

    func testValidResponseResetsTechnicalIssueStreak() {
        var machine = QuestAttemptStateMachine(policy: .write)

        XCTAssertTrue(machine.beginAttempt())
        machine.receive(result(.uncertain))
        XCTAssertEqual(machine.consecutiveTechnicalIssueCount, 1)

        XCTAssertTrue(machine.beginAttempt())
        machine.receive(result(.notMatched))

        XCTAssertEqual(machine.consecutiveTechnicalIssueCount, 0)
        XCTAssertFalse(machine.canSkipAfterTechnicalIssues)
    }

    func testWriteRevealsAnswerAfterSecondWrongAndAllowsGuidedThirdAttempt() throws {
        var machine = QuestAttemptStateMachine(policy: .write)

        XCTAssertTrue(machine.beginAttempt())
        machine.receive(result(.notMatched))

        XCTAssertEqual(machine.phase, .feedback(.tryAgain(remainingAttempts: 2)))
        XCTAssertEqual(machine.submissionCount, 1)
        XCTAssertEqual(machine.remainingIncorrectAttemptCount, 2)
        XCTAssertEqual(machine.records.map(\.evidence), [.firstIndependentAttempt])
        XCTAssertFalse(machine.usedGuidance)
        XCTAssertFalse(machine.prepareGuidedImitationAttempt())

        XCTAssertTrue(machine.beginAttempt())
        machine.receive(result(.notMatched))

        XCTAssertEqual(machine.phase, .feedback(.tryAgain(remainingAttempts: 1)))
        XCTAssertTrue(machine.prepareGuidedImitationAttempt())
        XCTAssertTrue(machine.usedGuidance)
        XCTAssertEqual(
            machine.records.map(\.evidence),
            [.firstIndependentAttempt, .unaidedRetry, .helped]
        )

        XCTAssertTrue(machine.beginAttempt())
        machine.receive(result(.matched))

        let summary = try XCTUnwrap(machine.completedSummary)
        XCTAssertEqual(summary.completion, .completedWithGuidance)
        XCTAssertEqual(summary.validAttemptCount, 3)
        XCTAssertTrue(summary.earnsItemStar)
        XCTAssertEqual(summary.records.last?.evidence, .guidedRetry)
        XCTAssertFalse(machine.beginAttempt())
    }

    func testWriteThirdWrongCompletesAsNeedsPractice() throws {
        var machine = QuestAttemptStateMachine(policy: .write)

        for attempt in 1...3 {
            XCTAssertTrue(machine.beginAttempt())
            machine.receive(result(.notMatched))
            if attempt == 2 {
                XCTAssertTrue(machine.prepareGuidedImitationAttempt())
            }
        }

        let summary = try XCTUnwrap(machine.completedSummary)
        XCTAssertEqual(summary.completion, .needsPractice)
        XCTAssertEqual(summary.validAttemptCount, 3)
        XCTAssertFalse(summary.earnsItemStar)
        XCTAssertFalse(machine.beginAttempt())
    }

    func testWriteUncertainDoesNotExposeAnswerOrConsumeWrongAttempt() throws {
        var machine = QuestAttemptStateMachine(policy: .write)

        XCTAssertTrue(machine.beginAttempt())
        machine.receive(result(.uncertain))

        XCTAssertEqual(machine.phase, .feedback(.recognitionUncertain))
        XCTAssertEqual(machine.validAttemptCount, 0)
        XCTAssertEqual(machine.submissionCount, 0)
        XCTAssertEqual(machine.incorrectAttemptCount, 0)
        XCTAssertEqual(machine.records.map(\.evidence), [.recognitionUncertain])

        XCTAssertTrue(machine.beginAttempt())
        machine.receive(result(.matched))

        let summary = try XCTUnwrap(machine.completedSummary)
        XCTAssertEqual(summary.completion, .independentSuccess)
        XCTAssertEqual(summary.validAttemptCount, 1)
        XCTAssertEqual(summary.records.last?.evidence, .firstIndependentAttempt)
    }

    func testWriteTechnicalRetryDoesNotConsumeIncorrectAttemptLimit() throws {
        var machine = QuestAttemptStateMachine(policy: .write)

        XCTAssertTrue(machine.beginAttempt())
        machine.receive(result(.notMatched))
        XCTAssertTrue(machine.beginAttempt())
        machine.receive(result(.technicalFailure(.serviceUnavailable)))

        XCTAssertEqual(machine.submissionCount, 1)
        XCTAssertEqual(machine.incorrectAttemptCount, 1)
        XCTAssertTrue(machine.beginAttempt())
        machine.receive(result(.matched))

        let summary = try XCTUnwrap(machine.completedSummary)
        XCTAssertEqual(summary.completion, .completedAfterRetry)
        XCTAssertEqual(summary.validAttemptCount, 2)
    }

    func testStudyExposureIsRecordedOnceWithoutTurningLaterResponseIntoHelped() throws {
        var machine = QuestAttemptStateMachine(policy: .write)

        machine.markStudyExposure()
        machine.markStudyExposure()
        XCTAssertTrue(machine.beginAttempt())
        machine.receive(result(.matched))

        let summary = try XCTUnwrap(machine.completedSummary)
        XCTAssertEqual(summary.completion, .independentSuccess)
        XCTAssertEqual(
            summary.records.map(\.evidence),
            [.studyExposed, .firstIndependentAttempt]
        )
    }

    private func result(_ decision: RecognitionDecision) -> RecognitionResult {
        RecognitionResult(
            decision: decision,
            confidence: RecognitionConfidence(0.95)
        )
    }

}

final class QuestItemFeedbackLifecycleTests: XCTestCase {
    func testTransitionToSecondWordDismissesFirstFeedbackAndAllowsSecondFeedback() {
        let firstID = WordPromptID()
        let secondID = WordPromptID()
        let firstSummary = summary(completion: .independentSuccess)
        let secondSummary = summary(completion: .needsPractice)
        var lifecycle = QuestItemFeedbackLifecycle<
            WordPromptID,
            QuestAttemptSummary
        >(itemID: firstID)

        XCTAssertTrue(lifecycle.present(firstSummary, for: firstID))
        XCTAssertEqual(lifecycle.visibleFeedback(for: firstID), firstSummary)
        XCTAssertTrue(lifecycle.requestAdvance(for: firstID))
        XCTAssertFalse(lifecycle.requestAdvance(for: firstID))

        XCTAssertTrue(lifecycle.transition(to: secondID))
        XCTAssertNil(lifecycle.visibleFeedback(for: secondID))
        XCTAssertNil(lifecycle.visibleFeedback(for: firstID))
        XCTAssertFalse(lifecycle.requestAdvance(for: firstID))

        XCTAssertTrue(lifecycle.present(secondSummary, for: secondID))
        XCTAssertEqual(lifecycle.visibleFeedback(for: secondID), secondSummary)
        XCTAssertTrue(lifecycle.requestAdvance(for: secondID))
    }

    func testStaleDelayedCompletionCannotAdvanceTheNextWord() async {
        let firstID = WordPromptID()
        let secondID = WordPromptID()
        let firstSummary = summary(completion: .independentSuccess)
        var lifecycle = QuestItemFeedbackLifecycle<
            WordPromptID,
            QuestAttemptSummary
        >(itemID: firstID)
        XCTAssertTrue(lifecycle.present(firstSummary, for: firstID))

        await Task.yield()
        XCTAssertTrue(lifecycle.transition(to: secondID))

        XCTAssertFalse(lifecycle.requestAdvance(for: firstID))
        XCTAssertNil(lifecycle.visibleFeedback(for: secondID))
    }

    func testDuplicateCompletionCannotScheduleASecondAdvance() {
        let itemID = WordPromptID()
        let value = summary(completion: .independentSuccess)
        var lifecycle = QuestItemFeedbackLifecycle<
            WordPromptID,
            QuestAttemptSummary
        >(itemID: itemID)

        XCTAssertTrue(lifecycle.present(value, for: itemID))
        XCTAssertFalse(lifecycle.present(value, for: itemID))
        XCTAssertTrue(lifecycle.requestAdvance(for: itemID))
        XCTAssertFalse(lifecycle.requestAdvance(for: itemID))
    }

    private func summary(
        completion: QuestAttemptCompletion
    ) -> QuestAttemptSummary {
        QuestAttemptSummary(
            completion: completion,
            records: [
                QuestAttemptRecord(
                    evidence: .firstIndependentAttempt,
                    outcome: completion == .needsPractice ? .incorrect : .correct,
                    confidence: RecognitionConfidence(0.95)
                )
            ],
            validAttemptCount: 1,
            usedGuidance: false
        )
    }
}
