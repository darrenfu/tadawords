import Foundation
import TadaWordsDomain
import TadaWordsLearning

/// Builds a small, explainable Guardian read model from persisted learning
/// evidence. Pool membership is the boundary: inactive or unrelated words can
/// never surface here.
struct GuardianAttentionEvaluator: Sendable {
    static let maximumItemCount = 5

    func evaluate(
        activePrompts: [WordPrompt],
        progress: [WordProgress],
        attempts: [AttemptEvent],
        profileID: ProfileID,
        now: Date
    ) -> [GuardianAttentionItem] {
        let progressByPromptID = progress.reduce(
            into: [WordPromptID: WordProgress]()
        ) { result, item in
            guard item.profileID == profileID else { return }
            result[item.wordPromptID] = item
        }
        let attemptsByPromptID = Dictionary(
            grouping: attempts.filter { $0.profileID == profileID },
            by: \.wordPromptID
        )
        let personalPaceBands = Self.personalPaceBands(from: attempts)

        let candidates = activePrompts.compactMap { prompt -> Candidate? in
            guard
                let wordProgress = progressByPromptID[prompt.id],
                wordProgress.learningMode == prompt.learningMode,
                let promptAttempts = attemptsByPromptID[prompt.id],
                promptAttempts.contains(where: Self.isLearningEvidence)
            else {
                return nil
            }

            if let dueAt = wordProgress.memoryState.nextReviewAt, dueAt <= now {
                return Candidate(
                    item: GuardianAttentionItem(
                        prompt: prompt,
                        reason: .reviewDue,
                        whyNow: Self.reviewDueMessage(dueAt: dueAt, now: now)
                    ),
                    priority: 0,
                    severity: now.timeIntervalSince(dueAt),
                    lastEvidenceAt: wordProgress.lastEncounterAt
                )
            }

            let misses = max(
                0,
                wordProgress.firstIndependentAttemptCount
                    - wordProgress.firstIndependentCorrectCount
            )
            if misses >= 2 {
                return Candidate(
                    item: GuardianAttentionItem(
                        prompt: prompt,
                        reason: .missedOften,
                        whyNow:
                            "Missed \(misses) of \(wordProgress.firstIndependentAttemptCount) first tries."
                    ),
                    priority: 1,
                    severity: Self.missSeverity(
                        misses: misses,
                        attemptCount: wordProgress.firstIndependentAttemptCount
                    ),
                    lastEvidenceAt: wordProgress.lastEncounterAt
                )
            }

            if let slowEvidence = Self.slowEvidence(
                attempts: promptAttempts,
                personalPaceBands: personalPaceBands
            ) {
                return Candidate(
                    item: GuardianAttentionItem(
                        prompt: prompt,
                        reason: .takingExtraTime,
                        whyNow: String(
                            format:
                                "Average first try: %.1f seconds; personal comfort range ends at %.1f.",
                            slowEvidence.meanSeconds,
                            slowEvidence.personalUpperBoundSeconds
                        )
                    ),
                    priority: 2,
                    severity: slowEvidence.meanSeconds
                        / slowEvidence.personalUpperBoundSeconds,
                    lastEvidenceAt: wordProgress.lastEncounterAt
                )
            }

            return nil
        }

        return
            candidates
            .sorted(by: Self.precedes)
            .prefix(Self.maximumItemCount)
            .map { $0.item }
    }

    private static func isLearningEvidence(_ attempt: AttemptEvent) -> Bool {
        attempt.evidence.countsTowardAccuracy
            && attempt.outcome.isScorableResponse
    }

    private static func reviewDueMessage(dueAt: Date, now: Date) -> String {
        let overdueDays = Int(now.timeIntervalSince(dueAt) / 86_400)
        guard overdueDays > 0 else { return "Review became due today." }
        return overdueDays == 1
            ? "Review is 1 day overdue."
            : "Review is \(overdueDays) days overdue."
    }

    private static func missSeverity(misses: Int, attemptCount: Int) -> Double {
        guard attemptCount > 0 else { return 0 }
        let missRate = Double(misses) / Double(attemptCount)
        return missRate * 1_000 + Double(misses)
    }

    private static func personalPaceBands(
        from attempts: [AttemptEvent]
    ) -> [PaceContext: PersonalPaceBand] {
        let extractor = AttemptPaceMeasurementExtractor()
        let measurements = attempts.compactMap { attempt -> PaceMeasurement? in
            guard attempt.evidence == .firstIndependentAttempt,
                attempt.outcome.isScorableResponse,
                let context = attempt.paceContext
            else { return nil }
            return extractor.measurement(from: attempt, context: context)
        }
        return Dictionary(
            uniqueKeysWithValues: PersonalPaceBaselineBuilder()
                .bands(from: measurements)
                .filter { $0.sampleCount >= 3 }
                .map { ($0.context, $0) }
        )
    }

    private static func slowEvidence(
        attempts: [AttemptEvent],
        personalPaceBands: [PaceContext: PersonalPaceBand]
    ) -> SlowEvidence? {
        let extractor = AttemptPaceMeasurementExtractor()
        let measurements = attempts.compactMap { attempt -> PaceMeasurement? in
            guard attempt.evidence == .firstIndependentAttempt,
                attempt.outcome.isScorableResponse,
                let context = attempt.paceContext
            else { return nil }
            return extractor.measurement(from: attempt, context: context)
        }
        let grouped = Dictionary(grouping: measurements, by: \.context)
        return grouped.compactMap { context, samples -> SlowEvidence? in
            guard samples.count >= 2,
                let band = personalPaceBands[context]
            else { return nil }
            let mean =
                samples.map(\.elapsedTime.seconds).reduce(0, +)
                / Double(samples.count)
            guard mean > band.upperBound.seconds else { return nil }
            return SlowEvidence(
                meanSeconds: mean,
                personalUpperBoundSeconds: band.upperBound.seconds
            )
        }.max { left, right in
            left.meanSeconds / left.personalUpperBoundSeconds
                < right.meanSeconds / right.personalUpperBoundSeconds
        }
    }

    private static func precedes(_ left: Candidate, _ right: Candidate) -> Bool {
        if left.priority != right.priority {
            return left.priority < right.priority
        }
        if left.severity != right.severity {
            return left.severity > right.severity
        }
        if left.lastEvidenceAt != right.lastEvidenceAt {
            return (left.lastEvidenceAt ?? .distantPast)
                < (right.lastEvidenceAt ?? .distantPast)
        }
        if left.item.prompt.normalizedText != right.item.prompt.normalizedText {
            return left.item.prompt.normalizedText < right.item.prompt.normalizedText
        }
        return left.item.id.uuidString < right.item.id.uuidString
    }

    private struct Candidate {
        let item: GuardianAttentionItem
        let priority: Int
        let severity: Double
        let lastEvidenceAt: Date?
    }

    private struct SlowEvidence {
        let meanSeconds: TimeInterval
        let personalUpperBoundSeconds: TimeInterval
    }
}
