import TadaWordsDomain

struct QuestAttemptRecord: Equatable, Sendable {
    let evidence: EncounterEvidence
    let outcome: AttemptOutcome
    let confidence: RecognitionConfidence?
    let timing: AttemptTiming
    let replayCount: Int

    init(
        evidence: EncounterEvidence,
        outcome: AttemptOutcome,
        confidence: RecognitionConfidence?,
        timing: AttemptTiming = .unmeasured,
        replayCount: Int = 0
    ) {
        self.evidence = evidence
        self.outcome = outcome
        self.confidence = confidence
        self.timing = timing
        self.replayCount = max(0, replayCount)
    }
}

enum QuestAttemptFeedback: Equatable, Sendable {
    case tryAgain(remainingAttempts: Int)
    case rewriteAfterAnswer
    case technicalRetry(TechnicalFailureReason)
    case recognitionUncertain
}

enum QuestAttemptCompletion: Equatable, Sendable {
    /// Correct on the first independent response. Long-term mastery is a
    /// separate, cross-day memory-model decision.
    case independentSuccess
    case completedAfterRetry
    case completedWithGuidance
    case needsPractice
}

enum QuestAttemptPolicy: Equatable, Sendable {
    case read
    case write

    var maximumSubmissionCount: Int {
        switch self {
        case .read:
            QuestAttemptStateMachine.maximumValidAttemptCount
        case .write:
            2
        }
    }
}

enum QuestAttemptPhase: Equatable, Sendable {
    case ready
    case evaluating
    case feedback(QuestAttemptFeedback)
    case completed(QuestAttemptCompletion)
}

struct QuestAttemptSummary: Equatable, Sendable {
    let completion: QuestAttemptCompletion
    let records: [QuestAttemptRecord]
    let validAttemptCount: Int
    let usedGuidance: Bool
}

/// Owns the evidence boundary for one word encounter.
///
/// Read receives one independent attempt and at most two valid retries. Write
/// receives one submission, immediate answer feedback after an incorrect or
/// uncertain result, and exactly one guided rewrite. Technical failures consume
/// neither policy. Once an answer is exposed, later responses remain guided and
/// cannot establish long-term mastery.
struct QuestAttemptStateMachine: Equatable, Sendable {
    static let maximumValidAttemptCount = 3
    static let technicalIssueSkipThreshold = 3

    let policy: QuestAttemptPolicy
    private(set) var phase: QuestAttemptPhase = .ready
    private(set) var records: [QuestAttemptRecord] = []
    private(set) var validAttemptCount = 0
    private(set) var submissionCount = 0
    private(set) var usedGuidance = false
    private(set) var consecutiveTechnicalIssueCount = 0

    init(policy: QuestAttemptPolicy = .read) {
        self.policy = policy
    }

    var remainingValidAttemptCount: Int {
        switch policy {
        case .read:
            max(0, Self.maximumValidAttemptCount - validAttemptCount)
        case .write:
            max(0, policy.maximumSubmissionCount - submissionCount)
        }
    }

    var canSkipAfterTechnicalIssues: Bool {
        guard consecutiveTechnicalIssueCount >= Self.technicalIssueSkipThreshold else {
            return false
        }
        guard case .feedback(let feedback) = phase else { return false }
        switch feedback {
        case .technicalRetry, .recognitionUncertain:
            return true
        case .tryAgain, .rewriteAfterAnswer:
            return false
        }
    }

    @discardableResult
    mutating func beginAttempt() -> Bool {
        guard submissionCount < policy.maximumSubmissionCount else { return false }

        switch phase {
        case .ready, .feedback:
            phase = .evaluating
            return true
        case .evaluating, .completed:
            return false
        }
    }

    mutating func cancelAttempt() {
        guard phase == .evaluating else { return }
        phase = .ready
    }

    mutating func useGuidance() {
        guard !usedGuidance else { return }
        if case .completed = phase {
            return
        }

        usedGuidance = true
        records.append(
            QuestAttemptRecord(
                evidence: .helped,
                outcome: .skipped,
                confidence: nil
            )
        )
    }

    mutating func markStudyExposure() {
        guard records.allSatisfy({ $0.evidence != .studyExposed }) else { return }
        guard phase == .ready else { return }
        records.append(
            QuestAttemptRecord(
                evidence: .studyExposed,
                outcome: .skipped,
                confidence: nil
            )
        )
    }

    mutating func receive(
        _ result: RecognitionResult,
        timing: AttemptTiming = .unmeasured,
        replayCount: Int = 0
    ) {
        guard phase == .evaluating else { return }

        if result.targetSpeakerAssessment == .mismatched {
            receiveTechnicalFailure(
                .wrongSpeaker,
                confidence: result.confidence,
                timing: timing,
                replayCount: replayCount
            )
            return
        }

        switch result.decision {
        case .technicalFailure(let reason):
            receiveTechnicalFailure(
                reason,
                confidence: result.confidence,
                timing: timing,
                replayCount: replayCount
            )

        case .uncertain:
            if policy == .write {
                receiveUncertainWriting(
                    confidence: result.confidence,
                    timing: timing,
                    replayCount: replayCount
                )
                return
            }
            consecutiveTechnicalIssueCount += 1
            records.append(
                QuestAttemptRecord(
                    evidence: .recognitionUncertain,
                    outcome: .recognitionUncertain,
                    confidence: result.confidence,
                    timing: timing,
                    replayCount: replayCount
                )
            )
            phase = .feedback(.recognitionUncertain)

        case .matched, .notMatched:
            receiveValidResponse(
                result,
                timing: timing,
                replayCount: replayCount
            )
        }
    }

    @discardableResult
    mutating func skipAfterTechnicalIssues() -> Bool {
        guard canSkipAfterTechnicalIssues else { return false }
        phase = .completed(.needsPractice)
        return true
    }

    var completedSummary: QuestAttemptSummary? {
        guard case .completed(let completion) = phase else { return nil }
        return QuestAttemptSummary(
            completion: completion,
            records: records,
            validAttemptCount: validAttemptCount,
            usedGuidance: usedGuidance
        )
    }

    private mutating func receiveValidResponse(
        _ result: RecognitionResult,
        timing: AttemptTiming,
        replayCount: Int
    ) {
        consecutiveTechnicalIssueCount = 0
        let evidence: EncounterEvidence
        if usedGuidance {
            evidence = .guidedRetry
        } else if validAttemptCount == 0 {
            evidence = .firstIndependentAttempt
        } else {
            evidence = .unaidedRetry
        }

        let outcome = result.decision.attemptOutcome
        records.append(
            QuestAttemptRecord(
                evidence: evidence,
                outcome: outcome,
                confidence: result.confidence,
                timing: timing,
                replayCount: replayCount
            )
        )
        validAttemptCount += 1
        submissionCount += 1

        if outcome.isCorrect {
            phase = .completed(completionForCorrectResponse())
        } else if submissionCount >= policy.maximumSubmissionCount {
            phase = .completed(.needsPractice)
        } else if policy == .write {
            exposeAnswerForRewrite()
        } else {
            phase = .feedback(
                .tryAgain(remainingAttempts: remainingValidAttemptCount)
            )
        }
    }

    private mutating func receiveUncertainWriting(
        confidence: RecognitionConfidence?,
        timing: AttemptTiming,
        replayCount: Int
    ) {
        consecutiveTechnicalIssueCount = 0
        submissionCount += 1
        records.append(
            QuestAttemptRecord(
                evidence: .recognitionUncertain,
                outcome: .recognitionUncertain,
                confidence: confidence,
                timing: timing,
                replayCount: replayCount
            )
        )

        if submissionCount >= policy.maximumSubmissionCount {
            phase = .completed(.needsPractice)
        } else {
            exposeAnswerForRewrite()
        }
    }

    private mutating func exposeAnswerForRewrite() {
        usedGuidance = true
        records.append(
            QuestAttemptRecord(
                evidence: .feedbackExposed,
                outcome: .skipped,
                confidence: nil
            )
        )
        phase = .feedback(.rewriteAfterAnswer)
    }

    private mutating func receiveTechnicalFailure(
        _ reason: TechnicalFailureReason,
        confidence: RecognitionConfidence?,
        timing: AttemptTiming,
        replayCount: Int
    ) {
        consecutiveTechnicalIssueCount += 1
        records.append(
            QuestAttemptRecord(
                evidence: .technicalRetry,
                outcome: .technicalFailure(reason),
                confidence: confidence,
                timing: timing,
                replayCount: replayCount
            )
        )
        phase = .feedback(.technicalRetry(reason))
    }

    private func completionForCorrectResponse() -> QuestAttemptCompletion {
        if usedGuidance {
            return .completedWithGuidance
        }
        if validAttemptCount == 1 {
            return .independentSuccess
        }
        return .completedAfterRetry
    }
}
