import Foundation
import XCTest

@testable import TadaWordsDomain

final class TeacherWordAudioTests: XCTestCase {
    func testPromptBuildsCanonicalServerOwnedVoiceRequest() throws {
        let prompt = try WordPrompt(learningMode: .read, text: "Dog")

        let request = TeacherWordAudioRequest(prompt: prompt)

        XCTAssertEqual(request.spokenText, "Dog")
        XCTAssertNil(request.pronunciationKey)
        XCTAssertEqual(request.usage, .readHint)
        XCTAssertEqual(request.speed, 0.90, accuracy: 0.000_1)
        XCTAssertEqual(request.voiceContractVersion, "canonical-teacher-v2")
    }

    func testWritePromptUsesTheSlowerBundledVariant() throws {
        let prompt = try WordPrompt(learningMode: .write, text: "at")

        let request = TeacherWordAudioRequest(prompt: prompt)

        XCTAssertEqual(request.usage, .writePrompt)
        XCTAssertEqual(request.speed, 0.82, accuracy: 0.000_1)
    }

    func testContextAndPronunciationKeyArePreserved() throws {
        let prompt = try WordPrompt(
            learningMode: .read,
            text: "read",
            audioCue: .contextual(
                "I read every day.",
                pronunciationKey: "present-tense"
            )
        )

        let request = TeacherWordAudioRequest(prompt: prompt)

        XCTAssertEqual(request.spokenText, "I read every day.")
        XCTAssertEqual(request.pronunciationKey, "present-tense")
        XCTAssertEqual(request.usage, .readHint)
    }

    func testEmptyRequestsAndClipsFailExplicitly() {
        XCTAssertThrowsError(
            try TeacherWordAudioRequest(spokenText: "  \n ")
        ) { error in
            XCTAssertEqual(error as? TeacherWordAudioError, .emptySpokenText)
        }
        XCTAssertThrowsError(
            try TeacherWordAudioClip(audioData: Data())
        ) { error in
            XCTAssertEqual(error as? TeacherWordAudioError, .emptyAudio)
        }
    }

    func testCachingProviderDownloadsOnce() async throws {
        let request = try TeacherWordAudioRequest(spokenText: "dog")
        let clip = try TeacherWordAudioClip(audioData: Data([1, 2, 3]))
        let upstream = TeacherAudioProviderStub(clip: clip)
        let cache = TeacherAudioCacheStub()
        let provider = CachingTeacherWordAudioProvider(
            upstream: upstream,
            cache: cache
        )

        let first = try await provider.audio(for: request)
        let second = try await provider.audio(for: request)
        let requestCount = await upstream.requestCount

        XCTAssertEqual(first, clip)
        XCTAssertEqual(second, clip)
        XCTAssertEqual(requestCount, 1)
    }
}

private actor TeacherAudioProviderStub: TeacherWordAudioProviding {
    private let clip: TeacherWordAudioClip
    private(set) var requestCount = 0

    init(clip: TeacherWordAudioClip) {
        self.clip = clip
    }

    func audio(
        for request: TeacherWordAudioRequest
    ) async throws -> TeacherWordAudioClip {
        _ = request
        requestCount += 1
        return clip
    }
}

private actor TeacherAudioCacheStub: TeacherWordAudioCaching {
    private var clips: [TeacherWordAudioRequest: TeacherWordAudioClip] = [:]

    func clip(
        for request: TeacherWordAudioRequest
    ) async throws -> TeacherWordAudioClip? {
        clips[request]
    }

    func store(
        _ clip: TeacherWordAudioClip,
        for request: TeacherWordAudioRequest
    ) async throws {
        clips[request] = clip
    }
}
