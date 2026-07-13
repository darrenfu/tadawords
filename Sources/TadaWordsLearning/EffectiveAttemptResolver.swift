import Foundation
import TadaWordsDomain

/// A read model that preserves the immutable original event while exposing the
/// latest append-only correction, when one exists.
public struct EffectiveAttempt: Hashable, Sendable {
    public let original: AttemptEvent
    public let outcome: AttemptOutcome
    public let appliedCorrection: AttemptCorrectionEvent?

    public init(
        original: AttemptEvent,
        outcome: AttemptOutcome,
        appliedCorrection: AttemptCorrectionEvent?
    ) {
        self.original = original
        self.outcome = outcome
        self.appliedCorrection = appliedCorrection
    }
}

/// Resolves corrections deterministically. Later timestamps win; UUID order is
/// the stable tie-break for corrections created at the same instant.
public struct EffectiveAttemptResolver: Sendable {
    public init() {}

    public func resolve(
        _ attempt: AttemptEvent,
        corrections: [AttemptCorrectionEvent]
    ) -> EffectiveAttempt {
        let latestCorrection =
            corrections
            .filter { $0.originalAttemptID == attempt.id }
            .max(by: correctionPrecedes)

        return EffectiveAttempt(
            original: attempt,
            outcome: latestCorrection?.correctedOutcome ?? attempt.outcome,
            appliedCorrection: latestCorrection
        )
    }

    public func resolve(
        _ attempts: [AttemptEvent],
        corrections: [AttemptCorrectionEvent]
    ) -> [EffectiveAttempt] {
        let latestCorrections = latestCorrectionByAttemptID(corrections)
        return attempts.map { attempt in
            let correction = latestCorrections[attempt.id]
            return EffectiveAttempt(
                original: attempt,
                outcome: correction?.correctedOutcome ?? attempt.outcome,
                appliedCorrection: correction
            )
        }
    }

    private func latestCorrectionByAttemptID(
        _ corrections: [AttemptCorrectionEvent]
    ) -> [AttemptID: AttemptCorrectionEvent] {
        corrections.reduce(into: [:]) { latest, candidate in
            guard let current = latest[candidate.originalAttemptID] else {
                latest[candidate.originalAttemptID] = candidate
                return
            }

            if correctionPrecedes(current, candidate) {
                latest[candidate.originalAttemptID] = candidate
            }
        }
    }

    private func correctionPrecedes(
        _ left: AttemptCorrectionEvent,
        _ right: AttemptCorrectionEvent
    ) -> Bool {
        if left.correctedAt != right.correctedAt {
            return left.correctedAt < right.correctedAt
        }
        return left.id.rawValue.uuidString < right.id.rawValue.uuidString
    }
}
