import Foundation
import TadaWordsDomain

public struct QuestScoringPolicy: Equatable, Sendable {
    public let accuracyStarThreshold: Double
    public let accuracyPointMaximum: Int
    public let pacePointMaximum: Int
    public let requiredPaceBaselineSampleCount: Int
    public let slowerPaceGraceRatio: Double
    public let maximumUnaidedRecoveryCount: Int
    public let unaidedRecoveryRewardAccuracyFloor: Double

    public init(
        accuracyStarThreshold: Double = 0.75,
        accuracyPointMaximum: Int = 80,
        pacePointMaximum: Int = 20,
        requiredPaceBaselineSampleCount: Int = 3,
        slowerPaceGraceRatio: Double = 0.5,
        maximumUnaidedRecoveryCount: Int = 1,
        unaidedRecoveryRewardAccuracyFloor: Double = 0.8
    ) {
        self.accuracyStarThreshold =
            accuracyStarThreshold
            .finiteOr(0.75)
            .clamped(to: 0...1)
        self.accuracyPointMaximum = max(0, accuracyPointMaximum)
        self.pacePointMaximum = max(0, pacePointMaximum)
        self.requiredPaceBaselineSampleCount = max(
            3,
            requiredPaceBaselineSampleCount
        )
        self.slowerPaceGraceRatio = min(
            1,
            max(
                0,
                slowerPaceGraceRatio.isFinite ? slowerPaceGraceRatio : 0.5
            )
        )
        self.maximumUnaidedRecoveryCount = max(
            0,
            maximumUnaidedRecoveryCount
        )
        self.unaidedRecoveryRewardAccuracyFloor =
            unaidedRecoveryRewardAccuracyFloor
            .finiteOr(0.8)
            .clamped(to: 0...1)
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

/// Keeps guardian-visible accuracy on the memory scheduler's strict first-try
/// boundary while applying a small, explicit recovery grace to child rewards.
public struct QuestScorer: Sendable {
    public let policy: QuestScoringPolicy

    public init(policy: QuestScoringPolicy = .default) {
        self.policy = policy
    }

    public func score(_ input: QuestScoringInput) -> QuestScore {
        let questAttempts = effectiveQuestAttempts(input)
        let firstIndependentAttempts = eligibleFirstIndependentAttempts(
            from: questAttempts
        )
        let correctCount = firstIndependentAttempts.count { $0.outcome.isCorrect }
        let attemptCount = firstIndependentAttempts.count
        let accuracy =
            attemptCount > 0
            ? Double(correctCount) / Double(attemptCount)
            : 0
        let meetsFirstTryAccuracyThreshold =
            attemptCount > 0
            && accuracy >= policy.accuracyStarThreshold
        let receivesUnaidedRecoveryGrace =
            !meetsFirstTryAccuracyThreshold
            && qualifiesForUnaidedRecoveryGrace(
                firstIndependentAttempts: firstIndependentAttempts,
                questAttempts: questAttempts
            )
        let rewardAccuracy =
            receivesUnaidedRecoveryGrace
            ? max(
                accuracy,
                max(
                    policy.accuracyStarThreshold,
                    policy.unaidedRecoveryRewardAccuracyFloor
                )
            )
            : accuracy
        let meetsAccuracyStarRule =
            meetsFirstTryAccuracyThreshold || receivesUnaidedRecoveryGrace
        let completedPlannedWordIDs = Set(
            input.plan.reviewWordIDs + input.plan.newWordIDs
        )
        let isPerfectFirstTry =
            !completedPlannedWordIDs.isEmpty
            && completedPlannedWordIDs.isSubset(of: input.completedWordIDs)
            && attemptCount == completedPlannedWordIDs.count
            && correctCount == attemptCount
        let paceEligibleAttempts = paceEligibleCorrectAttempts(
            firstIndependentAttempts: firstIndependentAttempts,
            questAttempts: questAttempts
        )

        let paceAssessment = assessPace(
            for: paceEligibleAttempts,
            input: input,
            meetsAccuracyStarRule: meetsAccuracyStarRule
        )
        let stars = stars(
            for: input,
            meetsAccuracyStarRule: meetsAccuracyStarRule,
            isPerfectFirstTry: isPerfectFirstTry,
            paceAssessment: paceAssessment
        )
        let points = points(
            accuracy: rewardAccuracy,
            isPerfectFirstTry: isPerfectFirstTry,
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

    private func effectiveQuestAttempts(
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
        return EffectiveAttemptResolver().resolve(
            questAttempts,
            corrections: input.corrections
        )
        .sorted(by: effectiveAttemptSort)
    }

    private func eligibleFirstIndependentAttempts(
        from effectiveAttempts: [EffectiveAttempt]
    ) -> [EffectiveAttempt] {
        var seenWordIDs = Set<WordPromptID>()
        return
            effectiveAttempts
            .filter { attempt in
                guard attempt.original.evidence.countsTowardAccuracy,
                    attempt.outcome.isScorableResponse
                else {
                    return false
                }
                return seenWordIDs.insert(attempt.original.wordPromptID).inserted
            }
    }

    /// A single first-try miss can still meet the child-facing accuracy rule
    /// when the very next valid, unaided retry is correct. Help, answer
    /// exposure, a second failed retry, or multiple missed words do not receive
    /// this grace. Guardian-facing first-try accuracy remains unchanged.
    private func qualifiesForUnaidedRecoveryGrace(
        firstIndependentAttempts: [EffectiveAttempt],
        questAttempts: [EffectiveAttempt]
    ) -> Bool {
        guard policy.maximumUnaidedRecoveryCount > 0 else { return false }

        let missedFirstAttempts = firstIndependentAttempts.filter {
            !$0.outcome.isCorrect
        }
        guard !missedFirstAttempts.isEmpty,
            missedFirstAttempts.count <= policy.maximumUnaidedRecoveryCount
        else {
            return false
        }

        return missedFirstAttempts.allSatisfy { missedAttempt in
            firstUnaidedRetry(
                after: missedAttempt,
                in: questAttempts
            )?.outcome.isCorrect == true
        }
    }

    private func paceEligibleCorrectAttempts(
        firstIndependentAttempts: [EffectiveAttempt],
        questAttempts: [EffectiveAttempt]
    ) -> [EffectiveAttempt] {
        firstIndependentAttempts.compactMap { firstAttempt in
            if firstAttempt.outcome.isCorrect {
                return firstAttempt
            }
            guard
                let retry = firstUnaidedRetry(
                    after: firstAttempt,
                    in: questAttempts
                ),
                retry.outcome.isCorrect
            else {
                return nil
            }
            return retry
        }
    }

    /// Returns only the first valid independent retry. Technical and uncertain
    /// records are neutral; any answer exposure closes the recovery path.
    private func firstUnaidedRetry(
        after firstAttempt: EffectiveAttempt,
        in questAttempts: [EffectiveAttempt]
    ) -> EffectiveAttempt? {
        guard let firstIndex = questAttempts.firstIndex(of: firstAttempt) else {
            return nil
        }

        for candidate in questAttempts.dropFirst(firstIndex + 1) {
            guard
                candidate.original.wordPromptID
                    == firstAttempt.original.wordPromptID
            else {
                continue
            }
            if candidate.original.evidence.hasAnswerExposure {
                return nil
            }
            guard candidate.original.evidence == .unaidedRetry,
                candidate.outcome.isScorableResponse
            else {
                continue
            }
            return candidate
        }
        return nil
    }

    private func assessPace(
        for attempts: [EffectiveAttempt],
        input: QuestScoringInput,
        meetsAccuracyStarRule: Bool
    ) -> PersonalPaceAssessment {
        guard meetsAccuracyStarRule else { return .unavailable }

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
            requiredBaselineSampleCount: policy.requiredPaceBaselineSampleCount,
            slowerPaceGraceRatio: policy.slowerPaceGraceRatio
        ).assess(
            measurements: measurements,
            personalBands: input.personalPaceBands
        )
    }

    private func stars(
        for input: QuestScoringInput,
        meetsAccuracyStarRule: Bool,
        isPerfectFirstTry: Bool,
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
        if meetsAccuracyStarRule {
            earned.insert(.accuracy)
        }
        if meetsAccuracyStarRule,
            isPerfectFirstTry || earnsPaceStar(paceAssessment)
        {
            earned.insert(.personalPace)
        }
        return QuestStars(earned: earned)
    }

    private func earnsPaceStar(
        _ assessment: PersonalPaceAssessment
    ) -> Bool {
        switch assessment {
        case .withinPersonalBand, .calibrating:
            // Calibration is neutral and requires valid timing. It should not
            // make the baseline-building quests feel like an automatic failure.
            true
        case .unavailable, .outsidePersonalBand:
            false
        }
    }

    private func points(
        accuracy: Double,
        isPerfectFirstTry: Bool,
        paceAssessment: PersonalPaceAssessment
    ) -> Int {
        let accuracyPoints = Int(
            (accuracy * Double(policy.accuracyPointMaximum)).rounded()
        )
        let pacePoints: Int

        switch (isPerfectFirstTry, paceAssessment) {
        case (true, _):
            // A fully correct first try is the clearest child-facing success
            // signal. It receives the pace component even while a personal
            // baseline is still missing or a timing sample is unavailable.
            // Guardian accuracy remains the strict first-independent metric.
            pacePoints = policy.pacePointMaximum
        case (false, .withinPersonalBand):
            pacePoints = policy.pacePointMaximum
        case (false, .calibrating):
            // Calibration is neutral: the unavailable pace component follows
            // accuracy instead of penalizing the child for limited history.
            pacePoints = Int(
                (accuracy * Double(policy.pacePointMaximum)).rounded()
            )
        case (false, .unavailable), (false, .outsidePersonalBand):
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
