import Foundation
import TadaWordsDomain

/// Signals used to decide which review item should be presented first.
///
/// Due status and predicted recall are intentionally stronger than response
/// time, replay, and help counts. A child is never rushed merely because a
/// response was slow.
public struct ReviewPriorityCandidate: Equatable, Sendable {
    public let wordPromptID: WordPromptID
    public let nextReviewAt: Date
    public let predictedRecall: Double
    public let lapseCount: Int
    public let independentIncorrectRate: Double
    public let paceRatio: Double?
    public let replayCount: Int
    public let helpCount: Int
    public let uncertainCount: Int
    public let guardianRequeuedAt: Date?

    public init(
        wordPromptID: WordPromptID,
        nextReviewAt: Date,
        predictedRecall: Double = 1,
        lapseCount: Int,
        independentIncorrectRate: Double,
        paceRatio: Double? = nil,
        replayCount: Int = 0,
        helpCount: Int = 0,
        uncertainCount: Int = 0,
        guardianRequeuedAt: Date? = nil
    ) {
        self.wordPromptID = wordPromptID
        self.nextReviewAt = nextReviewAt
        self.predictedRecall =
            predictedRecall
            .finiteOr(1)
            .clamped(to: 0...1)
        self.lapseCount = max(0, lapseCount)
        self.independentIncorrectRate =
            independentIncorrectRate
            .finiteOr(0)
            .clamped(to: 0...1)
        self.paceRatio = paceRatio.map { $0.finiteOr(1) }.map { max(0, $0) }
        self.replayCount = max(0, replayCount)
        self.helpCount = max(0, helpCount)
        self.uncertainCount = max(0, uncertainCount)
        self.guardianRequeuedAt = guardianRequeuedAt
    }
}

/// Produces a stable, deterministic review order.
public struct ReviewPriorityRanker: Sendable {
    public init() {}

    public func ranked(
        _ candidates: [ReviewPriorityCandidate],
        asOf now: Date
    ) -> [ReviewPriorityCandidate] {
        candidates.enumerated().sorted { left, right in
            isHigherPriority(left, than: right, asOf: now)
        }.map(\.element)
    }

    private func isHigherPriority(
        _ left: EnumeratedSequence<[ReviewPriorityCandidate]>.Element,
        than right: EnumeratedSequence<[ReviewPriorityCandidate]>.Element,
        asOf now: Date
    ) -> Bool {
        let lhs = left.element
        let rhs = right.element

        let lhsIsDue = lhs.nextReviewAt <= now
        let rhsIsDue = rhs.nextReviewAt <= now
        if lhsIsDue != rhsIsDue {
            return lhsIsDue
        }

        if lhs.guardianRequeuedAt != rhs.guardianRequeuedAt {
            return (lhs.guardianRequeuedAt ?? .distantPast)
                > (rhs.guardianRequeuedAt ?? .distantPast)
        }

        if lhs.predictedRecall != rhs.predictedRecall {
            return lhs.predictedRecall < rhs.predictedRecall
        }

        if lhs.independentIncorrectRate != rhs.independentIncorrectRate {
            return lhs.independentIncorrectRate > rhs.independentIncorrectRate
        }

        if lhs.lapseCount != rhs.lapseCount {
            return lhs.lapseCount > rhs.lapseCount
        }

        let lhsPaceRatio = lhs.paceRatio ?? 1
        let rhsPaceRatio = rhs.paceRatio ?? 1
        if lhsPaceRatio != rhsPaceRatio {
            return lhsPaceRatio > rhsPaceRatio
        }

        if lhs.replayCount != rhs.replayCount {
            return lhs.replayCount > rhs.replayCount
        }

        if lhs.helpCount != rhs.helpCount {
            return lhs.helpCount > rhs.helpCount
        }

        if lhs.uncertainCount != rhs.uncertainCount {
            return lhs.uncertainCount > rhs.uncertainCount
        }

        if lhs.nextReviewAt != rhs.nextReviewAt {
            return lhs.nextReviewAt < rhs.nextReviewAt
        }

        return left.offset < right.offset
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
