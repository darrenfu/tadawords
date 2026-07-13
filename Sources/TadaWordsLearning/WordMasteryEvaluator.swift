import Foundation
import TadaWordsDomain

public enum WordMasteryStatus: Equatable, Sendable {
    case learning
    case mastered
}

public struct WordMasteryPolicy: Equatable, Sendable {
    public let minimumCrossDayIndependentSuccesses: Int
    public let futureRecallHorizonDays: Double
    public let targetRecallThreshold: Double

    public init(
        minimumCrossDayIndependentSuccesses: Int = 3,
        futureRecallHorizonDays: Double = 14,
        targetRecallThreshold: Double = 0.80
    ) {
        self.minimumCrossDayIndependentSuccesses = max(
            1,
            minimumCrossDayIndependentSuccesses
        )
        self.futureRecallHorizonDays = max(
            0,
            futureRecallHorizonDays.isFinite ? futureRecallHorizonDays : 14
        )
        self.targetRecallThreshold = min(
            1,
            max(
                0,
                targetRecallThreshold.isFinite ? targetRecallThreshold : 0.80
            )
        )
    }

    public static let `default` = WordMasteryPolicy()
}

/// Mastery is deliberately a presentation decision, never a terminal state.
/// A word can become Review again whenever predicted recall falls below the
/// threshold.
public struct WordMasteryEvaluator: Sendable {
    private static let secondsPerDay: TimeInterval = 86_400

    public let policy: WordMasteryPolicy

    public init(policy: WordMasteryPolicy = .default) {
        self.policy = policy
    }

    public func status(
        for progress: WordProgress,
        asOf date: Date,
        timeZone: TimeZone
    ) -> WordMasteryStatus {
        let successDays = Set(
            progress.independentSuccessDates.map {
                LocalDay(date: $0, timeZone: timeZone)
            }
        )
        guard successDays.count >= policy.minimumCrossDayIndependentSuccesses else {
            return .learning
        }

        let horizon = date.addingTimeInterval(
            policy.futureRecallHorizonDays * Self.secondsPerDay
        )
        guard
            progress.memoryState.predictedRecall(at: horizon)
                >= policy.targetRecallThreshold
        else {
            return .learning
        }
        return .mastered
    }
}
