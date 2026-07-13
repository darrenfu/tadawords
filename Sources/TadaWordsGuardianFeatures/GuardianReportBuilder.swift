import Foundation
import TadaWordsDomain
import TadaWordsLearning

struct GuardianReportBuilder: Sendable {
    func makeReport(
        profile: KidProfile,
        period: GuardianReportPeriod,
        now: Date,
        prompts: [WordPrompt],
        attempts: [AttemptEvent],
        corrections: [AttemptCorrectionEvent],
        completions: [DailyQuestCompletion]
    ) -> GuardianLearningReport {
        let duration = TimeInterval(period.rawValue * 86_400)
        let start = now.addingTimeInterval(-duration)
        let previousStart = start.addingTimeInterval(-duration)
        let effective = EffectiveAttemptResolver().resolve(
            attempts,
            corrections: corrections
        )
        let current = effective.filter {
            $0.original.occurredAt >= start && $0.original.occurredAt <= now
        }
        let previous = effective.filter {
            $0.original.occurredAt >= previousStart
                && $0.original.occurredAt < start
        }
        let currentCompletions = completions.filter {
            $0.completedAt >= start && $0.completedAt <= now
        }

        return GuardianLearningReport(
            profile: profile,
            period: period,
            startedAt: start,
            endedAt: now,
            completedQuestCount: currentCompletions.count,
            totalPoints: currentCompletions.map(\.points).reduce(0, +),
            totalStars: currentCompletions.map(\.stars.count).reduce(0, +),
            trend: GuardianReportTrend(
                currentAccuracy: accuracy(of: current),
                previousAccuracy: accuracy(of: previous),
                accuracyChange: accuracyChange(current: current, previous: previous),
                currentIndependentAttemptCount: scoredAttempts(current).count,
                previousIndependentAttemptCount: scoredAttempts(previous).count
            ),
            words: wordReports(
                prompts: prompts,
                effectiveAttempts: current
            )
        )
    }

    private func wordReports(
        prompts: [WordPrompt],
        effectiveAttempts: [EffectiveAttempt]
    ) -> [GuardianWordReport] {
        let promptByID = Dictionary(
            uniqueKeysWithValues: prompts.map { ($0.id, $0) }
        )
        let grouped = Dictionary(
            grouping: scoredAttempts(effectiveAttempts),
            by: { $0.original.wordPromptID }
        )
        return grouped.compactMap { promptID, attempts in
            guard let prompt = promptByID[promptID] else { return nil }
            let correctCount = attempts.filter { $0.outcome.isCorrect }.count
            let timings = attempts.compactMap { responseTime(for: $0.original) }
            let meanTime =
                timings.isEmpty
                ? nil
                : ElapsedTime(
                    seconds: timings.map(\.seconds).reduce(0, +)
                        / Double(timings.count)
                )
            return GuardianWordReport(
                prompt: prompt,
                independentAttemptCount: attempts.count,
                correctCount: correctCount,
                accuracy: attempts.isEmpty
                    ? nil
                    : Double(correctCount) / Double(attempts.count),
                meanResponseTime: meanTime,
                recentAttempts:
                    attempts
                    .sorted { $0.original.occurredAt > $1.original.occurredAt }
                    .prefix(10)
                    .map {
                        GuardianAttemptDetail(
                            id: $0.original.id,
                            occurredAt: $0.original.occurredAt,
                            originalOutcome: $0.original.outcome,
                            effectiveOutcome: $0.outcome,
                            responseTime: responseTime(for: $0.original),
                            wasCorrected: $0.appliedCorrection != nil
                        )
                    }
            )
        }.sorted { left, right in
            if left.accuracy != right.accuracy {
                return (left.accuracy ?? 1) < (right.accuracy ?? 1)
            }
            return left.prompt.normalizedText < right.prompt.normalizedText
        }
    }

    private func scoredAttempts(
        _ attempts: [EffectiveAttempt]
    ) -> [EffectiveAttempt] {
        attempts.filter {
            $0.original.evidence.countsTowardAccuracy
                && $0.outcome.isScorableResponse
        }
    }

    private func accuracy(of attempts: [EffectiveAttempt]) -> Double? {
        let scored = scoredAttempts(attempts)
        guard !scored.isEmpty else { return nil }
        return Double(scored.filter { $0.outcome.isCorrect }.count)
            / Double(scored.count)
    }

    private func accuracyChange(
        current: [EffectiveAttempt],
        previous: [EffectiveAttempt]
    ) -> Double? {
        guard let currentAccuracy = accuracy(of: current),
            let previousAccuracy = accuracy(of: previous)
        else { return nil }
        return currentAccuracy - previousAccuracy
    }

    private func responseTime(for attempt: AttemptEvent) -> ElapsedTime? {
        switch attempt.learningMode {
        case .read:
            return attempt.timing.speechOnsetLatency
                ?? attempt.timing.totalResponseTime
        case .write:
            guard let total = attempt.timing.totalResponseTime else { return nil }
            return ElapsedTime(
                seconds: total.seconds
                    - (attempt.timing.replayPauseTime?.seconds ?? 0)
            )
        }
    }
}
