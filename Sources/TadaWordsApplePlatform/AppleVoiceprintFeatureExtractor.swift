import Foundation
import TadaWordsDomain

public enum AppleVoiceprintFeatureExtractorError: Error, Equatable, Sendable {
    case invalidSampleRate
    case insufficientSpeech
    case invalidSamples
}

/// A small, deterministic on-device acoustic signature used by the device
/// voiceprint alpha. It stores no PCM and has no network dependency. The model
/// deliberately keeps a wide uncertain band so weak evidence never penalizes a
/// child.
public struct AppleVoiceprintFeatureExtractor: VoiceprintEmbeddingExtracting {
    public let modelIdentifier = "tada-acoustic-v1"

    private static let targetSampleRate = 16_000.0
    private static let segmentCount = 8
    private static let spectralFrequencies: [Double] = [
        120, 180, 260, 380, 550, 800, 1_150, 1_650, 2_300, 3_100, 4_000, 5_000,
    ]

    public init() {}

    public func embedding(
        from samples: [Float],
        sampleRate: Double
    ) throws -> VoiceprintEmbedding {
        guard sampleRate.isFinite, sampleRate > 0 else {
            throw AppleVoiceprintFeatureExtractorError.invalidSampleRate
        }
        guard samples.allSatisfy(\.isFinite) else {
            throw AppleVoiceprintFeatureExtractorError.invalidSamples
        }

        let resampled = resample(samples, sourceSampleRate: sampleRate)
        let trimmed = trimSilence(resampled)
        guard trimmed.count >= Int(Self.targetSampleRate * 0.65) else {
            throw AppleVoiceprintFeatureExtractorError.insufficientSpeech
        }

        var features: [Float] = []
        features.reserveCapacity(32)
        appendTemporalFeatures(from: trimmed, to: &features)
        appendSpectralFeatures(from: trimmed, to: &features)
        return try VoiceprintEmbedding(
            modelIdentifier: modelIdentifier,
            vector: features
        )
    }

    private func resample(
        _ samples: [Float],
        sourceSampleRate: Double
    ) -> [Float] {
        guard !samples.isEmpty else { return [] }
        let targetCount = max(
            1,
            Int(Double(samples.count) * Self.targetSampleRate / sourceSampleRate)
        )
        guard targetCount != samples.count else { return samples }

        return (0..<targetCount).map { targetIndex in
            let sourcePosition =
                Double(targetIndex) * sourceSampleRate
                / Self.targetSampleRate
            let lowerIndex = min(samples.count - 1, Int(sourcePosition))
            let upperIndex = min(samples.count - 1, lowerIndex + 1)
            let fraction = Float(sourcePosition - Double(lowerIndex))
            return samples[lowerIndex] * (1 - fraction)
                + samples[upperIndex] * fraction
        }
    }

    private func trimSilence(_ samples: [Float]) -> ArraySlice<Float> {
        guard let peak = samples.map({ abs($0) }).max(), peak > 0 else {
            return []
        }
        let threshold = max(0.004, peak * 0.04)
        guard let first = samples.firstIndex(where: { abs($0) >= threshold }),
            let last = samples.lastIndex(where: { abs($0) >= threshold })
        else {
            return []
        }
        return samples[first...last]
    }

    private func appendTemporalFeatures(
        from samples: ArraySlice<Float>,
        to features: inout [Float]
    ) {
        let materialized = Array(samples)
        let segmentLength = max(1, materialized.count / Self.segmentCount)
        for segmentIndex in 0..<Self.segmentCount {
            let lower = segmentIndex * segmentLength
            let upper =
                segmentIndex == Self.segmentCount - 1
                ? materialized.count
                : min(materialized.count, lower + segmentLength)
            let segment = materialized[lower..<upper]
            let rms = rootMeanSquare(segment)
            features.append(log1p(rms * 100))
            features.append(zeroCrossingRate(segment))
        }

        let full = materialized[...]
        let rms = rootMeanSquare(full)
        let meanAbsolute =
            full.reduce(Float.zero) { $0 + abs($1) }
            / Float(max(1, full.count))
        let peak = full.reduce(Float.zero) { max($0, abs($1)) }
        features.append(log1p(rms * 100))
        features.append(log1p(meanAbsolute * 100))
        features.append(log1p(peak * 100))
        features.append(zeroCrossingRate(full))
    }

    private func appendSpectralFeatures(
        from samples: ArraySlice<Float>,
        to features: inout [Float]
    ) {
        let maximumAnalyzedSamples = Int(Self.targetSampleRate * 3)
        let strideValue = max(1, samples.count / maximumAnalyzedSamples)
        let analyzed = samples.enumerated().compactMap { index, sample in
            index.isMultiple(of: strideValue) ? sample : nil
        }
        let effectiveRate = Self.targetSampleRate / Double(strideValue)
        for frequency in Self.spectralFrequencies {
            features.append(
                log1p(goertzelPower(analyzed, frequency: frequency, sampleRate: effectiveRate))
            )
        }
    }

    private func rootMeanSquare<C: Collection>(_ samples: C) -> Float
    where C.Element == Float {
        guard !samples.isEmpty else { return 0 }
        let energy = samples.reduce(Float.zero) { $0 + $1 * $1 }
        return sqrt(energy / Float(samples.count))
    }

    private func zeroCrossingRate<C: Collection>(_ samples: C) -> Float
    where C.Element == Float {
        guard samples.count > 1 else { return 0 }
        var crossings = 0
        var previous = samples.first ?? 0
        for sample in samples.dropFirst() {
            if (previous < 0 && sample >= 0) || (previous >= 0 && sample < 0) {
                crossings += 1
            }
            previous = sample
        }
        return Float(crossings) / Float(samples.count - 1)
    }

    private func goertzelPower(
        _ samples: [Float],
        frequency: Double,
        sampleRate: Double
    ) -> Float {
        guard frequency < sampleRate / 2, !samples.isEmpty else { return 0 }
        let coefficient = Float(2 * cos(2 * Double.pi * frequency / sampleRate))
        var first: Float = 0
        var second: Float = 0
        for sample in samples {
            let current = sample + coefficient * first - second
            second = first
            first = current
        }
        let power = first * first + second * second - coefficient * first * second
        return max(0, power / Float(samples.count))
    }
}

public actor AppleVoiceprintVerifier {
    private let repository: any DeviceVoiceprintRepository
    private let extractor: any VoiceprintEmbeddingExtracting
    private let policy: VoiceprintMatchPolicy

    public init(
        repository: any DeviceVoiceprintRepository,
        extractor: any VoiceprintEmbeddingExtracting = AppleVoiceprintFeatureExtractor(),
        policy: VoiceprintMatchPolicy = VoiceprintMatchPolicy()
    ) {
        self.repository = repository
        self.extractor = extractor
        self.policy = policy
    }

    public func assess(
        profileID: ProfileID,
        samples: [Float],
        sampleRate: Double
    ) async -> TargetSpeakerAssessment {
        do {
            guard let template = try await repository.template(for: profileID) else {
                return .unavailable
            }
            let candidate = try extractor.embedding(
                from: samples,
                sampleRate: sampleRate
            )
            let similarity = try template.embedding.cosineSimilarity(with: candidate)
            return policy.signal(for: similarity).targetSpeakerAssessment
        } catch {
            return .unavailable
        }
    }
}
