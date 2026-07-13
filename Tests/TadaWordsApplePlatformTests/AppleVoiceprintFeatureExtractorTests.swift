import Foundation
import TadaWordsDomain
import XCTest

@testable import TadaWordsApplePlatform

final class AppleVoiceprintFeatureExtractorTests: XCTestCase {
    func testExtractorIsDeterministicNormalizedAndRejectsSilence() throws {
        let extractor = AppleVoiceprintFeatureExtractor()
        let samples = sineWave(frequency: 220, duration: 1.2)

        let first = try extractor.embedding(from: samples, sampleRate: 16_000)
        let second = try extractor.embedding(from: samples, sampleRate: 16_000)

        XCTAssertEqual(first, second)
        XCTAssertEqual(first.vector.count, 32)
        XCTAssertEqual(
            first.vector.reduce(0) { $0 + $1 * $1 },
            1,
            accuracy: 0.0001
        )
        XCTAssertThrowsError(
            try extractor.embedding(
                from: [Float](repeating: 0, count: 16_000),
                sampleRate: 16_000
            )
        )
    }

    func testVerifierReturnsUnavailableWithoutEnrollment() async {
        let verifier = AppleVoiceprintVerifier(
            repository: EmptyVoiceprintRepository()
        )

        let assessment = await verifier.assess(
            profileID: ProfileID(),
            samples: sineWave(frequency: 220, duration: 1.2),
            sampleRate: 16_000
        )

        XCTAssertEqual(assessment, .unavailable)
    }

    private func sineWave(frequency: Double, duration: Double) -> [Float] {
        let sampleRate = 16_000.0
        return (0..<Int(sampleRate * duration)).map { index in
            Float(sin(2 * Double.pi * frequency * Double(index) / sampleRate) * 0.35)
        }
    }
}

private actor EmptyVoiceprintRepository: DeviceVoiceprintRepository {
    func template(for profileID: ProfileID) async throws -> DeviceVoiceprintTemplate? {
        nil
    }

    func save(_ template: DeviceVoiceprintTemplate) async throws {}

    func delete(for profileID: ProfileID) async throws {}
}
