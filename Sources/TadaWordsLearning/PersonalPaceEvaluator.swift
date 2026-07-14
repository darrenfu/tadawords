import Foundation
import TadaWordsDomain

public struct PaceMeasurement: Equatable, Sendable {
    public let context: PaceContext
    public let elapsedTime: ElapsedTime

    public init(context: PaceContext, elapsedTime: ElapsedTime) {
        self.context = context
        self.elapsedTime = elapsedTime
    }
}

/// Assesses a child's current response against their own comparable history.
/// The reward band includes a modest slow-side grace for a young learner, while
/// the fast edge remains strict so guessing is not treated as better work.
public struct PersonalPaceEvaluator: Sendable {
    public let requiredBaselineSampleCount: Int
    public let slowerPaceGraceRatio: Double

    public init(
        requiredBaselineSampleCount: Int = 3,
        slowerPaceGraceRatio: Double = 0.25
    ) {
        self.requiredBaselineSampleCount = max(3, requiredBaselineSampleCount)
        self.slowerPaceGraceRatio = min(
            1,
            max(
                0,
                slowerPaceGraceRatio.isFinite ? slowerPaceGraceRatio : 0.25
            )
        )
    }

    public func assess(
        measurements: [PaceMeasurement],
        personalBands: [PersonalPaceBand]
    ) -> PersonalPaceAssessment {
        guard !measurements.isEmpty else { return .unavailable }

        let bandByContext = Dictionary(
            personalBands.map { ($0.context, $0) },
            uniquingKeysWith: { _, latest in latest }
        )
        let matchedMeasurements = measurements.compactMap { measurement -> MatchedPace? in
            guard let band = bandByContext[measurement.context] else { return nil }
            return MatchedPace(measurement: measurement, band: band)
        }

        guard matchedMeasurements.count == measurements.count else {
            return .calibrating(
                sampleCount: minimumAvailableSampleCount(
                    for: measurements,
                    bandByContext: bandByContext
                ),
                requiredSampleCount: requiredBaselineSampleCount
            )
        }

        let leastSampledBandCount =
            matchedMeasurements
            .map(\.band.sampleCount)
            .min() ?? 0
        guard leastSampledBandCount >= requiredBaselineSampleCount else {
            return .calibrating(
                sampleCount: leastSampledBandCount,
                requiredSampleCount: requiredBaselineSampleCount
            )
        }

        let medianDistance =
            matchedMeasurements
            .map(normalizedDistanceFromBand)
            .median()

        return medianDistance == 0
            ? .withinPersonalBand
            : .outsidePersonalBand
    }

    private func minimumAvailableSampleCount(
        for measurements: [PaceMeasurement],
        bandByContext: [PaceContext: PersonalPaceBand]
    ) -> Int {
        measurements.map { bandByContext[$0.context]?.sampleCount ?? 0 }.min() ?? 0
    }

    private func normalizedDistanceFromBand(_ matched: MatchedPace) -> Double {
        let elapsed = matched.measurement.elapsedTime.seconds
        let lowerBound = matched.band.lowerBound.seconds
        let upperBound =
            matched.band.upperBound.seconds
            * (1 + slowerPaceGraceRatio)
        let scale = max((lowerBound + upperBound) / 2, 0.001)

        if elapsed < lowerBound {
            return (lowerBound - elapsed) / scale
        }
        if elapsed > upperBound {
            return (elapsed - upperBound) / scale
        }
        return 0
    }
}

private struct MatchedPace {
    let measurement: PaceMeasurement
    let band: PersonalPaceBand
}

extension Array where Element == Double {
    fileprivate func median() -> Double {
        guard !isEmpty else { return .infinity }
        let sortedValues = sorted()
        let midpoint = sortedValues.count / 2
        if sortedValues.count.isMultiple(of: 2) {
            return (sortedValues[midpoint - 1] + sortedValues[midpoint]) / 2
        }
        return sortedValues[midpoint]
    }
}
