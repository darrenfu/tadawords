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
        XCTAssertEqual(machine.phase, .feedback(.tryAgain(remainingAttempts: 2)))

        XCTAssertTrue(machine.beginAttempt())
        machine.receive(result(.matched))

        let summary = try XCTUnwrap(machine.completedSummary)
        XCTAssertEqual(summary.completion, .completedAfterRetry)
        XCTAssertEqual(summary.validAttemptCount, 2)
        XCTAssertEqual(
            summary.records.map(\.evidence),
            [.firstIndependentAttempt, .unaidedRetry]
        )
    }

    func testInitialAttemptPlusTwoRetriesIsHardLimit() throws {
        var machine = QuestAttemptStateMachine()

        for remainingAttempts in [2, 1] {
            XCTAssertTrue(machine.beginAttempt())
            machine.receive(result(.notMatched))
            XCTAssertEqual(
                machine.phase,
                .feedback(.tryAgain(remainingAttempts: remainingAttempts))
            )
        }

        XCTAssertTrue(machine.beginAttempt())
        machine.receive(result(.notMatched))

        let summary = try XCTUnwrap(machine.completedSummary)
        XCTAssertEqual(summary.completion, .needsPractice)
        XCTAssertEqual(summary.validAttemptCount, 3)
        XCTAssertEqual(machine.remainingValidAttemptCount, 0)
        XCTAssertFalse(machine.beginAttempt())
    }

    func testTechnicalAndUncertainResultsDoNotConsumeAttemptsOrBecomeWrongEvidence() throws {
        var machine = QuestAttemptStateMachine()

        XCTAssertTrue(machine.beginAttempt())
        machine.receive(result(.technicalFailure(.permissionDenied)))
        XCTAssertEqual(machine.validAttemptCount, 0)
        XCTAssertEqual(machine.remainingValidAttemptCount, 3)

        XCTAssertTrue(machine.beginAttempt())
        machine.receive(result(.uncertain))
        XCTAssertEqual(machine.validAttemptCount, 0)
        XCTAssertEqual(machine.remainingValidAttemptCount, 3)

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
        machine.receive(result(.matched))

        let summary = try XCTUnwrap(machine.completedSummary)
        XCTAssertEqual(summary.completion, .completedWithGuidance)
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
        XCTAssertEqual(machine.remainingValidAttemptCount, 3)
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
        var machine = QuestAttemptStateMachine()

        XCTAssertTrue(machine.beginAttempt())
        machine.receive(result(.uncertain))
        XCTAssertEqual(machine.consecutiveTechnicalIssueCount, 1)

        XCTAssertTrue(machine.beginAttempt())
        machine.receive(result(.notMatched))

        XCTAssertEqual(machine.consecutiveTechnicalIssueCount, 0)
        XCTAssertFalse(machine.canSkipAfterTechnicalIssues)
    }

    func testWriteIncorrectImmediatelyExposesAnswerAndAllowsOneRewrite() throws {
        var machine = QuestAttemptStateMachine(policy: .write)

        XCTAssertTrue(machine.beginAttempt())
        machine.receive(result(.notMatched))

        XCTAssertEqual(machine.phase, .feedback(.rewriteAfterAnswer))
        XCTAssertEqual(machine.submissionCount, 1)
        XCTAssertEqual(machine.remainingValidAttemptCount, 1)
        XCTAssertEqual(
            machine.records.map(\.evidence),
            [.firstIndependentAttempt, .feedbackExposed]
        )
        XCTAssertTrue(machine.usedGuidance)

        XCTAssertTrue(machine.beginAttempt())
        machine.receive(result(.notMatched))

        let summary = try XCTUnwrap(machine.completedSummary)
        XCTAssertEqual(summary.completion, .needsPractice)
        XCTAssertEqual(summary.validAttemptCount, 2)
        XCTAssertFalse(machine.beginAttempt())
    }

    func testWriteUncertainExposesAnswerWithoutCountingWrongThenEndsAfterRewrite() throws {
        var machine = QuestAttemptStateMachine(policy: .write)

        XCTAssertTrue(machine.beginAttempt())
        machine.receive(result(.uncertain))

        XCTAssertEqual(machine.phase, .feedback(.rewriteAfterAnswer))
        XCTAssertEqual(machine.validAttemptCount, 0)
        XCTAssertEqual(machine.submissionCount, 1)
        XCTAssertEqual(
            machine.records.map(\.evidence),
            [.recognitionUncertain, .feedbackExposed]
        )

        XCTAssertTrue(machine.beginAttempt())
        machine.receive(result(.matched))

        let summary = try XCTUnwrap(machine.completedSummary)
        XCTAssertEqual(summary.completion, .completedWithGuidance)
        XCTAssertEqual(summary.validAttemptCount, 1)
        XCTAssertEqual(summary.records.last?.evidence, .guidedRetry)
    }

    func testWriteTechnicalRetryDoesNotConsumeTheSingleRewrite() throws {
        var machine = QuestAttemptStateMachine(policy: .write)

        XCTAssertTrue(machine.beginAttempt())
        machine.receive(result(.notMatched))
        XCTAssertTrue(machine.beginAttempt())
        machine.receive(result(.technicalFailure(.serviceUnavailable)))

        XCTAssertEqual(machine.submissionCount, 1)
        XCTAssertTrue(machine.beginAttempt())
        machine.receive(result(.matched))

        let summary = try XCTUnwrap(machine.completedSummary)
        XCTAssertEqual(summary.completion, .completedWithGuidance)
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
