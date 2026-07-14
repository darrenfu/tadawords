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

    func testRecordingCoordinatorFinishesAudioOnSuccess() async throws {
        let audio = VoiceprintAudioExperienceSpy()
        let coordinator = VoiceprintRecordingAudioCoordinator(
            audioExperienceService: audio
        )

        let value = try await coordinator.capture { 42 }
        let events = await audio.events()

        XCTAssertEqual(value, 42)
        XCTAssertEqual(events, [.prepareRecording, .finishRecording])
    }

    func testRecordingCoordinatorFinishesAudioOnFailure() async {
        let audio = VoiceprintAudioExperienceSpy()
        let coordinator = VoiceprintRecordingAudioCoordinator(
            audioExperienceService: audio
        )

        do {
            let _: Int = try await coordinator.capture {
                throw VoiceprintTestError.captureFailed
            }
            XCTFail("Expected capture to fail")
        } catch {
            XCTAssertEqual(error as? VoiceprintTestError, .captureFailed)
        }

        let events = await audio.events()
        XCTAssertEqual(events, [.prepareRecording, .finishRecording])
    }

    private func sineWave(frequency: Double, duration: Double) -> [Float] {
        let sampleRate = 16_000.0
        return (0..<Int(sampleRate * duration)).map { index in
            Float(sin(2 * Double.pi * frequency * Double(index) / sampleRate) * 0.35)
        }
    }
}

private enum VoiceprintTestError: Error, Equatable {
    case captureFailed
}

private actor VoiceprintAudioExperienceSpy: AudioExperienceService {
    enum Event: Equatable {
        case prepareRecording
        case finishRecording
    }

    private var recordedEvents: [Event] = []

    func events() -> [Event] { recordedEvents }

    func playLaunchSignature() async {}
    func activate(world: WorldTheme, preferences: AudioPreferences) async {
        _ = world
        _ = preferences
    }
    func stopAmbientAudio() async {}
    func play(_ cue: FunctionalAudioCue) async { _ = cue }
    func prepareForVoicePrompt() async -> Bool { true }
    func finishVoicePrompt() async {}
    func prepareForRecording() async { recordedEvents.append(.prepareRecording) }
    func finishRecording() async { recordedEvents.append(.finishRecording) }
    func setApplicationActive(_ isActive: Bool) async { _ = isActive }
}

private actor EmptyVoiceprintRepository: DeviceVoiceprintRepository {
    func template(for profileID: ProfileID) async throws -> DeviceVoiceprintTemplate? {
        nil
    }

    func save(_ template: DeviceVoiceprintTemplate) async throws {}

    func delete(for profileID: ProfileID) async throws {}
}
