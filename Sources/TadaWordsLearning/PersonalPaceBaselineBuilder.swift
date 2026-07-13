import Foundation
import TadaWordsDomain

/// Transparent comfort-band tuning for a child's own comparable history.
public struct PersonalPaceBaselinePolicy: Equatable, Sendable {
    public let relativeTolerance: Double
    public let medianAbsoluteDeviationMultiplier: Double
    public let minimumToleranceSeconds: TimeInterval

    public init(
        relativeTolerance: Double = 0.35,
        medianAbsoluteDeviationMultiplier: Double = 1.5,
        minimumToleranceSeconds: TimeInterval = 0.25
    ) {
        self.relativeTolerance = max(
            0,
            relativeTolerance.isFinite ? relativeTolerance : 0.35
        )
        self.medianAbsoluteDeviationMultiplier = max(
            0,
            medianAbsoluteDeviationMultiplier.isFinite
                ? medianAbsoluteDeviationMultiplier
                : 1.5
        )
        self.minimumToleranceSeconds = max(
            0.01,
            minimumToleranceSeconds.isFinite ? minimumToleranceSeconds : 0.25
        )
    }

    public static let `default` = PersonalPaceBaselinePolicy()
}

/// Rebuilds personal comfortable bands from immutable historical attempts.
/// Each `PaceContext` is isolated; no global or peer speed benchmark is used.
public struct PersonalPaceBaselineBuilder: Sendable {
    public let policy: PersonalPaceBaselinePolicy

    public init(policy: PersonalPaceBaselinePolicy = .default) {
        self.policy = policy
    }

    public func bands(from measurements: [PaceMeasurement]) -> [PersonalPaceBand] {
        let grouped = Dictionary(grouping: validMeasurements(measurements), by: \.context)
        return grouped.map { context, samples in
            makeBand(context: context, samples: samples)
        }.sorted(by: bandOrder)
    }

    private func validMeasurements(
        _ measurements: [PaceMeasurement]
    ) -> [PaceMeasurement] {
        measurements.filter { $0.elapsedTime.seconds > 0 }
    }

    private func makeBand(
        context: PaceContext,
        samples: [PaceMeasurement]
    ) -> PersonalPaceBand {
        let durations = samples.map(\.elapsedTime.seconds).sorted()
        let center = durations.median()
        let medianAbsoluteDeviation = durations.map { abs($0 - center) }.median()
        let tolerance = max(
            policy.minimumToleranceSeconds,
            center * policy.relativeTolerance,
            medianAbsoluteDeviation * policy.medianAbsoluteDeviationMultiplier
        )
        return PersonalPaceBand(
            context: context,
            lowerBound: ElapsedTime(seconds: max(0.01, center - tolerance)),
            upperBound: ElapsedTime(seconds: center + tolerance),
            sampleCount: durations.count
        )
    }

    private func bandOrder(_ left: PersonalPaceBand, _ right: PersonalPaceBand) -> Bool {
        let lhs = left.context
        let rhs = right.context
        if lhs.learningMode != rhs.learningMode {
            return lhs.learningMode.rawValue < rhs.learningMode.rawValue
        }
        if lhs.deviceClass != rhs.deviceClass {
            return lhs.deviceClass.rawValue < rhs.deviceClass.rawValue
        }
        if lhs.inputMethod != rhs.inputMethod {
            return lhs.inputMethod.rawValue < rhs.inputMethod.rawValue
        }
        return lhs.wordLength < rhs.wordLength
    }
}

/// Applies the same timing eligibility rule to historical baselines and the
/// current quest score.
public struct AttemptPaceMeasurementExtractor: Sendable {
    public init() {}

    public func measurement(
        from attempt: AttemptEvent,
        context: PaceContext
    ) -> PaceMeasurement? {
        guard context.learningMode == attempt.learningMode else { return nil }
        guard let elapsedTime = elapsedTime(from: attempt), elapsedTime.seconds > 0 else {
            return nil
        }
        return PaceMeasurement(context: context, elapsedTime: elapsedTime)
    }

    public func elapsedTime(from attempt: AttemptEvent) -> ElapsedTime? {
        switch attempt.learningMode {
        case .read:
            return attempt.timing.speechOnsetLatency
                ?? attempt.timing.totalResponseTime

        case .write:
            guard let totalResponseTime = attempt.timing.totalResponseTime else {
                return nil
            }
            let replayPause = attempt.timing.replayPauseTime?.seconds ?? 0
            return ElapsedTime(
                seconds: totalResponseTime.seconds - replayPause
            )
        }
    }
}

extension Array where Element == Double {
    fileprivate func median() -> Double {
        guard !isEmpty else { return 0 }
        let values = sorted()
        let midpoint = values.count / 2
        if values.count.isMultiple(of: 2) {
            return (values[midpoint - 1] + values[midpoint]) / 2
        }
        return values[midpoint]
    }
}
