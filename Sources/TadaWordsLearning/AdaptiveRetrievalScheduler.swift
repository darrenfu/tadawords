import Foundation
import TadaWordsDomain

/// Transparent tuning values for adaptive Ebbinghaus retrieval.
///
/// Stability is adapted from outcomes. Scheduling itself is exact and
/// inspectable: `R(t) = exp(-t / stability)`, and review becomes due when `R`
/// reaches `targetRecallThreshold`.
public struct AdaptiveRetrievalPolicy: Equatable, Sendable {
    /// Initial stability after the first success. The legacy `Interval` name is
    /// retained for source compatibility; the actual review interval is derived
    /// from stability and `targetRecallThreshold`.
    public let firstSuccessIntervalDays: Double
    public let minimumIntervalDays: Double
    public let maximumIntervalDays: Double
    public let successMultiplier: Double
    public let consecutiveSuccessBonus: Double
    public let easeBonus: Double
    public let lapseMultiplier: Double
    public let maximumPostLapseIntervalDays: Double
    public let correctDifficultyStep: Double
    public let incorrectDifficultyStep: Double
    public let helpDifficultyStep: Double
    public let replayDifficultyStep: Double
    public let slowDifficultyStep: Double
    public let helpStabilityMultiplier: Double
    public let replayStabilityPenalty: Double
    public let slowStabilityMultiplier: Double
    public let slowPaceRatioThreshold: Double
    public let targetRecallThreshold: Double

    public init(
        firstSuccessIntervalDays: Double = 1,
        minimumIntervalDays: Double = 0.25,
        maximumIntervalDays: Double = 180,
        successMultiplier: Double = 1.55,
        consecutiveSuccessBonus: Double = 0.08,
        easeBonus: Double = 0.25,
        lapseMultiplier: Double = 0.35,
        maximumPostLapseIntervalDays: Double = 1,
        correctDifficultyStep: Double = 0.04,
        incorrectDifficultyStep: Double = 0.10,
        helpDifficultyStep: Double = 0.08,
        replayDifficultyStep: Double = 0.015,
        slowDifficultyStep: Double = 0.04,
        helpStabilityMultiplier: Double = 0.65,
        replayStabilityPenalty: Double = 0.08,
        slowStabilityMultiplier: Double = 0.85,
        slowPaceRatioThreshold: Double = 1.25,
        targetRecallThreshold: Double = 0.80
    ) {
        let minimum = max(0.01, minimumIntervalDays.finiteOr(0.25))
        let maximum = max(minimum, maximumIntervalDays.finiteOr(180))

        self.firstSuccessIntervalDays =
            firstSuccessIntervalDays
            .finiteOr(1)
            .clamped(to: minimum...maximum)
        self.minimumIntervalDays = minimum
        self.maximumIntervalDays = maximum
        self.successMultiplier = max(1, successMultiplier.finiteOr(1.55))
        self.consecutiveSuccessBonus = max(
            0,
            consecutiveSuccessBonus.finiteOr(0.08)
        )
        self.easeBonus = max(0, easeBonus.finiteOr(0.25))
        self.lapseMultiplier =
            lapseMultiplier
            .finiteOr(0.35)
            .clamped(to: 0...1)
        self.maximumPostLapseIntervalDays =
            maximumPostLapseIntervalDays
            .finiteOr(1)
            .clamped(to: minimum...maximum)
        self.correctDifficultyStep =
            correctDifficultyStep
            .finiteOr(0.04)
            .clamped(to: 0...1)
        self.incorrectDifficultyStep =
            incorrectDifficultyStep
            .finiteOr(0.10)
            .clamped(to: 0...1)
        self.helpDifficultyStep = helpDifficultyStep.finiteOr(0.08).clamped(to: 0...1)
        self.replayDifficultyStep =
            replayDifficultyStep
            .finiteOr(0.015)
            .clamped(to: 0...1)
        self.slowDifficultyStep = slowDifficultyStep.finiteOr(0.04).clamped(to: 0...1)
        self.helpStabilityMultiplier =
            helpStabilityMultiplier
            .finiteOr(0.65)
            .clamped(to: 0...1)
        self.replayStabilityPenalty =
            replayStabilityPenalty
            .finiteOr(0.08)
            .clamped(to: 0...1)
        self.slowStabilityMultiplier =
            slowStabilityMultiplier
            .finiteOr(0.85)
            .clamped(to: 0...1)
        self.slowPaceRatioThreshold = max(1, slowPaceRatioThreshold.finiteOr(1.25))
        self.targetRecallThreshold =
            targetRecallThreshold
            .finiteOr(0.80)
            .clamped(to: 0.01...0.99)
    }

    public static let `default` = AdaptiveRetrievalPolicy()
}

public struct RetrievalSignalContext: Equatable, Sendable {
    public let comparableMeanResponseTime: ElapsedTime?

    public init(comparableMeanResponseTime: ElapsedTime? = nil) {
        self.comparableMeanResponseTime = comparableMeanResponseTime
    }

    public static let empty = RetrievalSignalContext()
}

/// Updates memory only from a first, independent, valid response.
public struct AdaptiveRetrievalScheduler: Sendable {
    private static let secondsPerDay: TimeInterval = 86_400

    public let policy: AdaptiveRetrievalPolicy

    public init(policy: AdaptiveRetrievalPolicy = .default) {
        self.policy = policy
    }

    /// Days until recall reaches the policy threshold for the given stability.
    public func reviewIntervalDays(forStabilityDays stabilityDays: Double) -> Double {
        let normalizedStability = max(0, stabilityDays.finiteOr(0))
        return -log(policy.targetRecallThreshold) * normalizedStability
    }

    public func updatedMemoryState(
        from currentState: MemoryState,
        using attempt: AttemptEvent
    ) -> MemoryState {
        updatedMemoryState(
            from: currentState,
            using: EffectiveAttempt(
                original: attempt,
                outcome: attempt.outcome,
                appliedCorrection: nil
            ),
            signalContext: .empty
        )
    }

    public func updatedMemoryState(
        from currentState: MemoryState,
        using attempt: EffectiveAttempt,
        signalContext: RetrievalSignalContext = .empty
    ) -> MemoryState {
        if attempt.original.evidence == .helped {
            return helpedState(from: currentState)
        }

        guard attempt.original.evidence.canUpdateMemory,
            attempt.outcome.isScorableResponse,
            isChronologicallyValid(attempt.original, after: currentState)
        else {
            return currentState
        }

        switch attempt.outcome {
        case .correct:
            return correctState(
                from: currentState,
                using: attempt.original,
                signalContext: signalContext
            )
        case .incorrect:
            return incorrectState(
                from: currentState,
                using: attempt.original,
                signalContext: signalContext
            )
        case .recognitionUncertain, .technicalFailure, .skipped:
            return currentState
        }
    }

    private func isChronologicallyValid(
        _ attempt: AttemptEvent,
        after currentState: MemoryState
    ) -> Bool {
        guard let previousAttemptAt = currentState.lastIndependentAttemptAt else {
            return true
        }
        return attempt.occurredAt >= previousAttemptAt
    }

    private func correctState(
        from state: MemoryState,
        using attempt: AttemptEvent,
        signalContext: RetrievalSignalContext
    ) -> MemoryState {
        let consecutiveSuccesses = state.consecutiveIndependentSuccesses + 1
        let baseStabilityDays: Double

        if state.stabilityDays == 0 {
            baseStabilityDays = policy.firstSuccessIntervalDays
        } else {
            let boundedStreak = min(consecutiveSuccesses - 1, 5)
            let multiplier =
                policy.successMultiplier
                + (Double(boundedStreak) * policy.consecutiveSuccessBonus)
                + ((1 - state.difficulty) * policy.easeBonus)
            baseStabilityDays = (state.stabilityDays * multiplier)
                .clamped(to: policy.minimumIntervalDays...policy.maximumIntervalDays)
        }

        let penalties = signalPenalties(
            for: attempt,
            signalContext: signalContext
        )
        let stabilityDays = (baseStabilityDays * penalties.stabilityMultiplier)
            .clamped(to: policy.minimumIntervalDays...policy.maximumIntervalDays)

        return MemoryState(
            stabilityDays: stabilityDays,
            difficulty: state.difficulty - policy.correctDifficultyStep
                + penalties.difficultyIncrease,
            nextReviewAt: dueDate(
                after: attempt.occurredAt,
                stabilityDays: stabilityDays
            ),
            lastIndependentAttemptAt: attempt.occurredAt,
            consecutiveIndependentSuccesses: consecutiveSuccesses,
            lapseCount: state.lapseCount
        )
    }

    private func incorrectState(
        from state: MemoryState,
        using attempt: AttemptEvent,
        signalContext: RetrievalSignalContext
    ) -> MemoryState {
        let reducedStability = max(
            policy.minimumIntervalDays,
            state.stabilityDays * policy.lapseMultiplier
        )
        let baseStabilityDays = min(
            reducedStability,
            policy.maximumPostLapseIntervalDays
        )
        let penalties = signalPenalties(
            for: attempt,
            signalContext: signalContext
        )
        let stabilityDays = max(
            policy.minimumIntervalDays,
            baseStabilityDays * penalties.stabilityMultiplier
        )

        return MemoryState(
            stabilityDays: stabilityDays,
            difficulty: state.difficulty + policy.incorrectDifficultyStep
                + penalties.difficultyIncrease,
            nextReviewAt: dueDate(
                after: attempt.occurredAt,
                stabilityDays: stabilityDays
            ),
            lastIndependentAttemptAt: attempt.occurredAt,
            consecutiveIndependentSuccesses: 0,
            lapseCount: state.lapseCount + 1
        )
    }

    private func helpedState(from state: MemoryState) -> MemoryState {
        let adjustedStability =
            state.stabilityDays > 0
            ? max(
                policy.minimumIntervalDays,
                state.stabilityDays * policy.helpStabilityMultiplier
            )
            : 0
        let dueAt = state.lastIndependentAttemptAt.map {
            dueDate(after: $0, stabilityDays: adjustedStability)
        }
        return MemoryState(
            stabilityDays: adjustedStability,
            difficulty: state.difficulty + policy.helpDifficultyStep,
            nextReviewAt: dueAt,
            lastIndependentAttemptAt: state.lastIndependentAttemptAt,
            consecutiveIndependentSuccesses: 0,
            lapseCount: state.lapseCount
        )
    }

    private func signalPenalties(
        for attempt: AttemptEvent,
        signalContext: RetrievalSignalContext
    ) -> (stabilityMultiplier: Double, difficultyIncrease: Double) {
        let replayCount = min(4, attempt.replayCount)
        let replayMultiplier = max(
            0.5,
            1 - (Double(replayCount) * policy.replayStabilityPenalty)
        )
        let isSlow = isRelativelySlow(
            attempt,
            signalContext: signalContext
        )
        return (
            replayMultiplier * (isSlow ? policy.slowStabilityMultiplier : 1),
            (Double(replayCount) * policy.replayDifficultyStep)
                + (isSlow ? policy.slowDifficultyStep : 0)
        )
    }

    private func isRelativelySlow(
        _ attempt: AttemptEvent,
        signalContext: RetrievalSignalContext
    ) -> Bool {
        guard
            let baseline = signalContext.comparableMeanResponseTime?.seconds,
            baseline > 0,
            let response = effectiveResponseSeconds(for: attempt)
        else { return false }
        return response / baseline > policy.slowPaceRatioThreshold
    }

    private func effectiveResponseSeconds(for attempt: AttemptEvent) -> TimeInterval? {
        guard let total = attempt.timing.totalResponseTime?.seconds else { return nil }
        return max(0, total - (attempt.timing.replayPauseTime?.seconds ?? 0))
    }

    private func dueDate(after date: Date, stabilityDays: Double) -> Date {
        date.addingTimeInterval(
            reviewIntervalDays(forStabilityDays: stabilityDays) * Self.secondsPerDay
        )
    }
}

extension Double {
    fileprivate func finiteOr(_ fallback: Double) -> Double {
        isFinite ? self : fallback
    }

    fileprivate func clamped(to range: ClosedRange<Double>) -> Double {
        min(max(self, range.lowerBound), range.upperBound)
    }
}
