import TadaWordsDomain
import TadaWordsLearning

/// Keeps a New-first quest inside its original attention budget. A problematic
/// New encounter already consumed extra retry/help attention, so each such word
/// displaces the lowest-priority remaining Review item instead of making the
/// session longer. Dropped Review remains explicit debt for a later quest.
struct ProblemNewReviewReplacement: Sendable {
    func adjustedPlan(
        _ plan: QuestPlan,
        attempts: [AttemptEvent],
        personalPaceBands: [PersonalPaceBand]
    ) -> QuestPlan {
        guard plan.configuration.contentOrder == .newThenReview else {
            return plan
        }
        let problemCount = Set(
            plan.newWordIDs.filter { wordID in
                isProblemWord(
                    wordID,
                    attempts: attempts,
                    personalPaceBands: personalPaceBands
                )
            }
        ).count
        let dropCount = min(problemCount, plan.reviewWordIDs.count)
        guard dropCount > 0 else { return plan }

        let retainedReviewCount = plan.reviewWordIDs.count - dropCount
        let retainedReviews = Array(plan.reviewWordIDs.prefix(retainedReviewCount))
        let displacedReviews = Array(plan.reviewWordIDs.suffix(dropCount))
        return QuestPlan(
            id: plan.id,
            profileID: plan.profileID,
            configuration: plan.configuration,
            reviewWordIDs: retainedReviews,
            newWordIDs: plan.newWordIDs,
            deferredReviewWordIDs: displacedReviews + plan.deferredReviewWordIDs,
            createdAt: plan.createdAt
        )
    }

    private func isProblemWord(
        _ wordID: WordPromptID,
        attempts: [AttemptEvent],
        personalPaceBands: [PersonalPaceBand]
    ) -> Bool {
        let wordAttempts = attempts.filter { $0.wordPromptID == wordID }
        return wordAttempts.contains { attempt in
            if attempt.evidence == .helped
                || attempt.evidence == .recognitionUncertain
                || attempt.replayCount > 0
            {
                return true
            }
            if attempt.evidence == .firstIndependentAttempt,
                attempt.outcome == .incorrect
            {
                return true
            }
            return isRelativelySlow(
                attempt,
                personalPaceBands: personalPaceBands
            )
        }
    }

    private func isRelativelySlow(
        _ attempt: AttemptEvent,
        personalPaceBands: [PersonalPaceBand]
    ) -> Bool {
        guard attempt.evidence == .firstIndependentAttempt,
            let context = attempt.paceContext,
            let band = personalPaceBands.first(where: {
                $0.context == context && $0.sampleCount >= 3
            }),
            let measurement = AttemptPaceMeasurementExtractor().measurement(
                from: attempt,
                context: context
            )
        else { return false }
        return measurement.elapsedTime > band.upperBound
    }
}
