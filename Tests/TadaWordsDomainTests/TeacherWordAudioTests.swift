import Foundation
import XCTest

@testable import TadaWordsDomain

final class TeacherWordAudioTests: XCTestCase {
    func testPromptBuildsCanonicalServerOwnedVoiceRequest() throws {
        let prompt = try WordPrompt(learningMode: .read, text: "Dog")

        let request = TeacherWordAudioRequest(prompt: prompt)

        XCTAssertEqual(request.spokenText, "dog")
        XCTAssertNil(request.pronunciationKey)
        XCTAssertEqual(request.usage, .readHint)
        XCTAssertEqual(request.speed, 2.0 / 3.0, accuracy: 0.000_1)
        XCTAssertEqual(
            TeacherWordAudioRequest.vendorSpeed
                * TeacherWordAudioRequest.clientPlaybackRate,
            request.speed,
            accuracy: 0.000_1
        )
        XCTAssertEqual(request.voiceContractVersion, "elevenlabs-teacher-v1")
    }

    func testWritePromptUsesTheOneAndAHalfTimesSlowerCadence() throws {
        let prompt = try WordPrompt(learningMode: .write, text: "at")

        let request = TeacherWordAudioRequest(prompt: prompt)

        XCTAssertEqual(request.usage, .writePrompt)
        XCTAssertEqual(request.speed, 2.0 / 3.0, accuracy: 0.000_1)
    }

    func testContextIsNeverSentButPronunciationKeyIsPreserved() throws {
        let prompt = try WordPrompt(
            learningMode: .read,
            text: "read",
            audioCue: .contextual(
                "I read every day.",
                pronunciationKey: "present-tense"
            )
        )

        let request = TeacherWordAudioRequest(prompt: prompt)

        XCTAssertEqual(request.spokenText, "read")
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

    func testCachingProviderNeverReportsAnUnpersistedDownloadAsPrepared() async throws {
        let request = try TeacherWordAudioRequest(spokenText: "dog")
        let clip = try TeacherWordAudioClip(audioData: Data([1, 2, 3]))
        let provider = CachingTeacherWordAudioProvider(
            upstream: TeacherAudioProviderStub(clip: clip),
            cache: TeacherAudioCacheStub(
                storeError: TeacherWordAudioError.invalidAudioChecksum
            )
        )

        do {
            _ = try await provider.audio(for: request)
            XCTFail("Expected the failed durable store to remain visible")
        } catch {
            XCTAssertEqual(
                error as? TeacherWordAudioError,
                .invalidAudioChecksum
            )
        }
    }

    func testProviderChainFallsThroughOnlyForPackMiss() async throws {
        let request = try TeacherWordAudioRequest(spokenText: "dog")
        let clip = try TeacherWordAudioClip(audioData: Data([1, 2, 3]))
        let fallback = TeacherAudioProviderStub(clip: clip)
        let missing = FailingTeacherAudioProvider(
            error: TeacherWordAudioError.unavailableOfflineClip
        )
        let provider = FirstAvailableTeacherWordAudioProvider(
            providers: [missing, fallback]
        )

        let resolvedClip = try await provider.audio(for: request)
        XCTAssertEqual(resolvedClip, clip)
        let fallbackRequestCount = await fallback.requestCount
        XCTAssertEqual(fallbackRequestCount, 1)
    }

    func testProviderChainNeverChangesVoiceAfterOperationalFailure() async throws {
        let request = try TeacherWordAudioRequest(spokenText: "dog")
        let clip = try TeacherWordAudioClip(audioData: Data([1, 2, 3]))
        let fallback = TeacherAudioProviderStub(clip: clip)
        let rejected = FailingTeacherAudioProvider(
            error: TeacherWordAudioError.serverRejected(statusCode: 503)
        )
        let provider = FirstAvailableTeacherWordAudioProvider(
            providers: [rejected, fallback]
        )

        do {
            _ = try await provider.audio(for: request)
            XCTFail("Expected the operational failure to remain visible")
        } catch {
            XCTAssertEqual(
                error as? TeacherWordAudioError,
                .serverRejected(statusCode: 503)
            )
        }
        let fallbackRequestCount = await fallback.requestCount
        XCTAssertEqual(fallbackRequestCount, 0)
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
    private let storeError: TeacherWordAudioError?

    init(storeError: TeacherWordAudioError? = nil) {
        self.storeError = storeError
    }

    func clip(
        for request: TeacherWordAudioRequest
    ) async throws -> TeacherWordAudioClip? {
        clips[request]
    }

    func store(
        _ clip: TeacherWordAudioClip,
        for request: TeacherWordAudioRequest
    ) async throws {
        if let storeError { throw storeError }
        clips[request] = clip
    }
}

private struct FailingTeacherAudioProvider: TeacherWordAudioProviding {
    let error: TeacherWordAudioError

    func audio(
        for request: TeacherWordAudioRequest
    ) async throws -> TeacherWordAudioClip {
        _ = request
        throw error
    }
}
