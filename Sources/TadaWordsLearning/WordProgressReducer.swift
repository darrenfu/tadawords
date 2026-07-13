import Foundation
import TadaWordsDomain

public enum ProgressReductionError: Error, Equatable, Sendable {
    case mismatchedProfile
    case mismatchedWordPrompt
    case mismatchedLearningMode
}

/// Rebuilds a `WordProgress` snapshot from immutable encounter facts.
public struct WordProgressReducer: Sendable {
    public let scheduler: AdaptiveRetrievalScheduler

    public init(scheduler: AdaptiveRetrievalScheduler = AdaptiveRetrievalScheduler()) {
        self.scheduler = scheduler
    }

    /// Applies one unique event. Callers that cannot guarantee uniqueness
    /// should use `rebuild`, which de-duplicates by `AttemptID`.
    public func applying(
        _ attempt: AttemptEvent,
        to progress: WordProgress
    ) throws -> WordProgress {
        try applying(
            EffectiveAttempt(
                original: attempt,
                outcome: attempt.outcome,
                appliedCorrection: nil
            ),
            to: progress
        )
    }

    public func applying(
        _ attempt: EffectiveAttempt,
        to progress: WordProgress
    ) throws -> WordProgress {
        try validateIdentity(of: attempt.original, against: progress)

        let isValidIndependentAttempt =
            attempt.original.evidence.countsTowardAccuracy
            && attempt.outcome.isScorableResponse
        let attemptIncrement = isValidIndependentAttempt ? 1 : 0
        let correctIncrement = isValidIndependentAttempt && attempt.outcome.isCorrect ? 1 : 0
        let responseTime =
            isValidIndependentAttempt
            ? attempt.original.timing.totalResponseTime
            : nil
        let helpedIncrement = attempt.original.evidence == .helped ? 1 : 0
        let uncertainIncrement = isRecognitionUncertain(attempt.original) ? 1 : 0

        return WordProgress(
            profileID: progress.profileID,
            wordPromptID: progress.wordPromptID,
            learningMode: progress.learningMode,
            memoryState: scheduler.updatedMemoryState(
                from: progress.memoryState,
                using: attempt,
                signalContext: RetrievalSignalContext(
                    comparableMeanResponseTime: progress.firstIndependentMeanResponseTime
                )
            ),
            firstIndependentAttemptCount: progress.firstIndependentAttemptCount
                .addingClamped(attemptIncrement),
            firstIndependentCorrectCount: progress.firstIndependentCorrectCount
                .addingClamped(correctIncrement),
            firstIndependentResponseTimeTotal: ElapsedTime(
                seconds: progress.firstIndependentResponseTimeTotal.seconds
                    + (responseTime?.seconds ?? 0)
            ),
            firstIndependentTimedAttemptCount: progress.firstIndependentTimedAttemptCount
                .addingClamped(responseTime == nil ? 0 : 1),
            totalReplayCount: progress.totalReplayCount.addingClamped(
                attempt.original.replayCount
            ),
            helpedAttemptCount: progress.helpedAttemptCount.addingClamped(
                helpedIncrement
            ),
            uncertainAttemptCount: progress.uncertainAttemptCount.addingClamped(
                uncertainIncrement
            ),
            independentSuccessDates: progress.independentSuccessDates
                + (correctIncrement == 1 ? [attempt.original.occurredAt] : []),
            lastEncounterAt: latest(
                progress.lastEncounterAt,
                attempt.original.occurredAt
            )
        )
    }

    public func rebuild(
        profileID: ProfileID,
        wordPromptID: WordPromptID,
        learningMode: LearningMode,
        from attempts: [AttemptEvent],
        corrections: [AttemptCorrectionEvent] = []
    ) throws -> WordProgress {
        let relevantAttempts = attempts.filter {
            $0.profileID == profileID
                && $0.wordPromptID == wordPromptID
                && $0.learningMode == learningMode
        }
        let uniqueAttempts = uniqueAttemptsInChronologicalOrder(relevantAttempts)
        let effectiveAttempts = EffectiveAttemptResolver().resolve(
            uniqueAttempts,
            corrections: corrections
        )

        return try effectiveAttempts.reduce(
            WordProgress.unstarted(
                profileID: profileID,
                wordPromptID: wordPromptID,
                learningMode: learningMode
            )
        ) { progress, attempt in
            try applying(attempt, to: progress)
        }
    }

    private func validateIdentity(
        of attempt: AttemptEvent,
        against progress: WordProgress
    ) throws {
        guard attempt.profileID == progress.profileID else {
            throw ProgressReductionError.mismatchedProfile
        }
        guard attempt.wordPromptID == progress.wordPromptID else {
            throw ProgressReductionError.mismatchedWordPrompt
        }
        guard attempt.learningMode == progress.learningMode else {
            throw ProgressReductionError.mismatchedLearningMode
        }
    }

    private func uniqueAttemptsInChronologicalOrder(
        _ attempts: [AttemptEvent]
    ) -> [AttemptEvent] {
        var seenIDs = Set<AttemptID>()
        return attempts.sorted(by: attemptSort).filter { seenIDs.insert($0.id).inserted }
    }

    private func attemptSort(_ left: AttemptEvent, _ right: AttemptEvent) -> Bool {
        if left.occurredAt != right.occurredAt {
            return left.occurredAt < right.occurredAt
        }
        return left.id.rawValue.uuidString < right.id.rawValue.uuidString
    }

    private func latest(_ left: Date?, _ right: Date) -> Date {
        guard let left else { return right }
        return max(left, right)
    }

    private func isRecognitionUncertain(_ attempt: AttemptEvent) -> Bool {
        attempt.evidence == .recognitionUncertain
            || attempt.outcome == .recognitionUncertain
    }
}

extension Int {
    fileprivate func addingClamped(_ value: Int) -> Int {
        let (sum, overflow) = addingReportingOverflow(value)
        return overflow ? Int.max : Swift.max(0, sum)
    }
}
