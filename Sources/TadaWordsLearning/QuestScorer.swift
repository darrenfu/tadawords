import Foundation
import TadaWordsDomain

public struct QuestScoringPolicy: Equatable, Sendable {
    public let accuracyStarThreshold: Double
    public let accuracyPointMaximum: Int
    public let pacePointMaximum: Int
    public let requiredPaceBaselineSampleCount: Int

    public init(
        accuracyStarThreshold: Double = 0.8,
        accuracyPointMaximum: Int = 80,
        pacePointMaximum: Int = 20,
        requiredPaceBaselineSampleCount: Int = 3
    ) {
        self.accuracyStarThreshold =
            accuracyStarThreshold
            .finiteOr(0.8)
            .clamped(to: 0...1)
        self.accuracyPointMaximum = max(0, accuracyPointMaximum)
        self.pacePointMaximum = max(0, pacePointMaximum)
        self.requiredPaceBaselineSampleCount = max(
            3,
            requiredPaceBaselineSampleCount
        )
    }

    public static let `default` = QuestScoringPolicy()
}

public struct QuestScoringInput: Sendable {
    public let plan: QuestPlan
    public let completedWordIDs: Set<WordPromptID>
    public let attempts: [AttemptEvent]
    public let corrections: [AttemptCorrectionEvent]
    public let paceContextByWordID: [WordPromptID: PaceContext]
    public let personalPaceBands: [PersonalPaceBand]

    public init(
        plan: QuestPlan,
        completedWordIDs: Set<WordPromptID>,
        attempts: [AttemptEvent],
        corrections: [AttemptCorrectionEvent] = [],
        paceContextByWordID: [WordPromptID: PaceContext] = [:],
        personalPaceBands: [PersonalPaceBand] = []
    ) {
        self.plan = plan
        self.completedWordIDs = completedWordIDs
        self.attempts = attempts
        self.corrections = corrections
        self.paceContextByWordID = paceContextByWordID
        self.personalPaceBands = personalPaceBands
    }
}

/// Computes guardian-visible accuracy and child-visible stars from the same
/// narrow evidence boundary used by the memory scheduler.
public struct QuestScorer: Sendable {
    public let policy: QuestScoringPolicy

    public init(policy: QuestScoringPolicy = .default) {
        self.policy = policy
    }

    public func score(_ input: QuestScoringInput) -> QuestScore {
        let firstIndependentAttempts = eligibleFirstIndependentAttempts(input)
        let correctCount = firstIndependentAttempts.count { $0.outcome.isCorrect }
        let attemptCount = firstIndependentAttempts.count
        let accuracy =
            attemptCount > 0
            ? Double(correctCount) / Double(attemptCount)
            : 0
        let meetsAccuracyThreshold =
            attemptCount > 0
            && accuracy >= policy.accuracyStarThreshold

        let paceAssessment = assessPace(
            for: firstIndependentAttempts,
            input: input,
            meetsAccuracyThreshold: meetsAccuracyThreshold
        )
        let stars = stars(
            for: input,
            meetsAccuracyThreshold: meetsAccuracyThreshold,
            paceAssessment: paceAssessment
        )
        let points = points(
            accuracy: accuracy,
            paceAssessment: paceAssessment
        )

        return QuestScore(
            points: points,
            firstIndependentCorrectCount: correctCount,
            firstIndependentAttemptCount: attemptCount,
            stars: stars,
            personalPaceAssessment: paceAssessment
        )
    }

    private func eligibleFirstIndependentAttempts(
        _ input: QuestScoringInput
    ) -> [EffectiveAttempt] {
        let plannedWordIDs = Set(
            input.plan.reviewWordIDs + input.plan.newWordIDs
        )
        let questAttempts = input.attempts.filter { attempt in
            attempt.questID == input.plan.id
                && attempt.profileID == input.plan.profileID
                && attempt.learningMode == input.plan.configuration.learningMode
                && plannedWordIDs.contains(attempt.wordPromptID)
        }
        let effectiveAttempts = EffectiveAttemptResolver().resolve(
            questAttempts,
            corrections: input.corrections
        )

        var seenWordIDs = Set<WordPromptID>()
        return
            effectiveAttempts
            .sorted(by: effectiveAttemptSort)
            .filter { attempt in
                guard attempt.original.evidence.countsTowardAccuracy,
                    attempt.outcome.isScorableResponse
                else {
                    return false
                }
                return seenWordIDs.insert(attempt.original.wordPromptID).inserted
            }
    }

    private func assessPace(
        for attempts: [EffectiveAttempt],
        input: QuestScoringInput,
        meetsAccuracyThreshold: Bool
    ) -> PersonalPaceAssessment {
        guard meetsAccuracyThreshold else { return .unavailable }

        let correctAttempts = attempts.filter { $0.outcome.isCorrect }
        guard !correctAttempts.isEmpty else { return .unavailable }

        let measurements = correctAttempts.compactMap { attempt -> PaceMeasurement? in
            guard
                let context = input.paceContextByWordID[
                    attempt.original.wordPromptID
                ],
                let measurement = AttemptPaceMeasurementExtractor().measurement(
                    from: attempt.original,
                    context: context
                )
            else {
                return nil
            }
            return measurement
        }
        guard measurements.count == correctAttempts.count else {
            return .unavailable
        }

        return PersonalPaceEvaluator(
            requiredBaselineSampleCount: policy.requiredPaceBaselineSampleCount
        ).assess(
            measurements: measurements,
            personalBands: input.personalPaceBands
        )
    }

    private func stars(
        for input: QuestScoringInput,
        meetsAccuracyThreshold: Bool,
        paceAssessment: PersonalPaceAssessment
    ) -> QuestStars {
        var earned = Set<QuestStar>()
        let plannedWordIDs = Set(
            input.plan.reviewWordIDs + input.plan.newWordIDs
        )

        if !plannedWordIDs.isEmpty,
            plannedWordIDs.isSubset(of: input.completedWordIDs)
        {
            earned.insert(.completion)
        }
        if meetsAccuracyThreshold {
            earned.insert(.accuracy)
        }
        if meetsAccuracyThreshold,
            paceAssessment == .withinPersonalBand
        {
            earned.insert(.personalPace)
        }
        return QuestStars(earned: earned)
    }

    private func points(
        accuracy: Double,
        paceAssessment: PersonalPaceAssessment
    ) -> Int {
        let accuracyPoints = Int(
            (accuracy * Double(policy.accuracyPointMaximum)).rounded()
        )
        let pacePoints: Int

        switch paceAssessment {
        case .withinPersonalBand:
            pacePoints = policy.pacePointMaximum
        case .calibrating:
            // Calibration is neutral: the unavailable pace component follows
            // accuracy instead of penalizing the child for limited history.
            pacePoints = Int(
                (accuracy * Double(policy.pacePointMaximum)).rounded()
            )
        case .unavailable, .outsidePersonalBand:
            pacePoints = 0
        }

        let maximum = policy.accuracyPointMaximum + policy.pacePointMaximum
        return min(maximum, max(0, accuracyPoints + pacePoints))
    }

    private func effectiveAttemptSort(
        _ left: EffectiveAttempt,
        _ right: EffectiveAttempt
    ) -> Bool {
        if left.original.occurredAt != right.original.occurredAt {
            return left.original.occurredAt < right.original.occurredAt
        }
        return left.original.id.rawValue.uuidString
            < right.original.id.rawValue.uuidString
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
