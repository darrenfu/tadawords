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

    /// Child reward is based on eventual success, independently of the strict
    /// first-response and guidance evidence used by mastery and scheduling.
    var earnsItemStar: Bool {
        finalResponseOutcome?.isCorrect == true
    }

    var firstIndependentOutcome: AttemptOutcome? {
        records.first { $0.evidence == .firstIndependentAttempt }?.outcome
    }

    var finalResponseOutcome: AttemptOutcome? {
        records.last { $0.outcome.isScorableResponse }?.outcome
    }

    var promptReplayCount: Int {
        records.reduce(into: 0) { count, record in
            count += record.replayCount
        }
    }

    var guidanceExposureCount: Int {
        records.count { $0.evidence == .helped }
    }
}

/// Owns the evidence boundary for one word encounter.
///
/// Read and Write default to two incorrect answers. A correct response
/// completes immediately at any point. In Read, an unclear or timed-out
/// recording consumes the retry budget without becoming accuracy evidence.
/// Other technical failures, and uncertain Write recognition, do not consume
/// the budget.
struct QuestAttemptStateMachine: Equatable, Sendable {
    static let technicalIssueSkipThreshold = 3

    let policy: QuestAttemptPolicy
    let incorrectAttemptLimit: Int
    private(set) var phase: QuestAttemptPhase = .ready
    private(set) var records: [QuestAttemptRecord] = []
    private(set) var validAttemptCount = 0
    private(set) var submissionCount = 0
    private(set) var incorrectAttemptCount = 0
    private(set) var usedGuidance = false
    private(set) var consecutiveTechnicalIssueCount = 0

    init(
        policy: QuestAttemptPolicy = .read,
        incorrectAttemptLimit: Int =
            LearningRouteSettings.defaultIncorrectAttemptLimit
    ) {
        self.policy = policy
        self.incorrectAttemptLimit = min(
            LearningRouteSettings.incorrectAttemptLimitRange.upperBound,
            max(
                LearningRouteSettings.incorrectAttemptLimitRange.lowerBound,
                incorrectAttemptLimit
            )
        )
    }

    var remainingIncorrectAttemptCount: Int {
        max(0, incorrectAttemptLimit - incorrectAttemptCount)
    }

    var canSkipAfterTechnicalIssues: Bool {
        guard consecutiveTechnicalIssueCount >= Self.technicalIssueSkipThreshold else {
            return false
        }
        guard case .feedback(let feedback) = phase else { return false }
        switch feedback {
        case .technicalRetry, .recognitionUncertain:
            return true
        case .tryAgain:
            return false
        }
    }

    @discardableResult
    mutating func beginAttempt() -> Bool {
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
            if policy == .read, reason.countsAsReadListeningMiss {
                receiveReadListeningMiss(
                    evidence: .technicalRetry,
                    outcome: .technicalFailure(reason),
                    confidence: result.confidence,
                    timing: timing,
                    replayCount: replayCount
                )
            } else {
                receiveTechnicalFailure(
                    reason,
                    confidence: result.confidence,
                    timing: timing,
                    replayCount: replayCount
                )
            }

        case .uncertain:
            if policy == .read {
                receiveReadListeningMiss(
                    evidence: .recognitionUncertain,
                    outcome: .recognitionUncertain,
                    confidence: result.confidence,
                    timing: timing,
                    replayCount: replayCount
                )
            } else {
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
            }

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
        } else {
            incorrectAttemptCount += 1
            if incorrectAttemptCount >= incorrectAttemptLimit {
                phase = .completed(.needsPractice)
            } else {
                phase = .feedback(
                    .tryAgain(
                        remainingAttempts: remainingIncorrectAttemptCount
                    )
                )
            }
        }
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

    private mutating func receiveReadListeningMiss(
        evidence: EncounterEvidence,
        outcome: AttemptOutcome,
        confidence: RecognitionConfidence?,
        timing: AttemptTiming,
        replayCount: Int
    ) {
        consecutiveTechnicalIssueCount = 0
        records.append(
            QuestAttemptRecord(
                evidence: evidence,
                outcome: outcome,
                confidence: confidence,
                timing: timing,
                replayCount: replayCount
            )
        )
        submissionCount += 1
        incorrectAttemptCount += 1
        if incorrectAttemptCount >= incorrectAttemptLimit {
            phase = .completed(.needsPractice)
        } else {
            phase = .feedback(
                .tryAgain(
                    remainingAttempts: remainingIncorrectAttemptCount
                )
            )
        }
    }

    private func completionForCorrectResponse() -> QuestAttemptCompletion {
        if usedGuidance {
            return .completedWithGuidance
        }
        if submissionCount == 1 {
            return .independentSuccess
        }
        return .completedAfterRetry
    }
}

extension TechnicalFailureReason {
    var countsAsReadListeningMiss: Bool {
        switch self {
        case .noUsableAudio, .timedOut:
            true
        case .permissionDenied, .wrongSpeaker, .onDeviceRecognitionUnavailable,
            .serviceUnavailable, .corruptedInput:
            false
        }
    }
}

/// Keeps transient completion feedback scoped to the word that produced it.
///
/// A quest deliberately keeps one stable SwiftUI identity while it advances
/// between words so the writing surface never moves. That also means `@State`
/// survives a word transition. This value prevents the prior word's overlay or
/// delayed completion callback from leaking into the next word.
struct QuestItemFeedbackLifecycle<ItemID: Equatable, Feedback: Equatable>:
    Equatable
{
    private(set) var itemID: ItemID
    private(set) var pendingFeedback: Feedback?
    private(set) var didRequestAdvance = false

    init(itemID: ItemID) {
        self.itemID = itemID
    }

    func visibleFeedback(for itemID: ItemID) -> Feedback? {
        self.itemID == itemID ? pendingFeedback : nil
    }

    @discardableResult
    mutating func present(_ feedback: Feedback, for itemID: ItemID) -> Bool {
        guard self.itemID == itemID else { return false }
        guard pendingFeedback == nil, !didRequestAdvance else { return false }
        pendingFeedback = feedback
        return true
    }

    @discardableResult
    mutating func requestAdvance(for itemID: ItemID) -> Bool {
        guard self.itemID == itemID, pendingFeedback != nil else { return false }
        guard !didRequestAdvance else { return false }
        didRequestAdvance = true
        return true
    }

    @discardableResult
    mutating func transition(to itemID: ItemID) -> Bool {
        guard self.itemID != itemID else { return false }
        self.itemID = itemID
        pendingFeedback = nil
        didRequestAdvance = false
        return true
    }
}
