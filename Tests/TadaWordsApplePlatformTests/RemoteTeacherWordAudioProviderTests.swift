import Foundation
import TadaWordsDomain
import XCTest

@testable import TadaWordsApplePlatform

final class RemoteTeacherWordAudioProviderTests: XCTestCase {
    func testUnconfiguredEndpointFailsExplicitly() async throws {
        let provider = RemoteTeacherWordAudioProvider(
            endpoint: nil,
            dataLoader: { _ in
                XCTFail("An unconfigured provider must not make a request")
                throw URLError(.badURL)
            }
        )

        do {
            _ = try await provider.audio(
                for: TeacherWordAudioRequest(spokenText: "dog")
            )
            XCTFail("Expected an unconfigured endpoint error")
        } catch {
            XCTAssertEqual(error as? TeacherWordAudioError, .unconfiguredEndpoint)
        }
    }

    func testRequestUsesCanonicalSpeedAndContainsNoClientCredential() async throws {
        let capturedRequest = LockedTeacherAudioRequest()
        let audioData = Data([0x49, 0x44, 0x33, 0x04])
        let endpoint = try XCTUnwrap(
            URL(string: "https://audio.tadawords.example/v1/word")
        )
        let provider = RemoteTeacherWordAudioProvider(
            endpoint: endpoint,
            dataLoader: { request in
                capturedRequest.value = request
                let response = try XCTUnwrap(
                    HTTPURLResponse(
                        url: endpoint,
                        statusCode: 200,
                        httpVersion: nil,
                        headerFields: ["Content-Type": "audio/mpeg"]
                    )
                )
                return (audioData, response)
            }
        )

        let clip = try await provider.audio(
            for: TeacherWordAudioRequest(
                spokenText: "I read every day.",
                pronunciationKey: "present-tense"
            )
        )
        let request = try XCTUnwrap(capturedRequest.value)
        let body = try XCTUnwrap(request.httpBody)
        let payload = try XCTUnwrap(
            JSONSerialization.jsonObject(with: body) as? [String: Any]
        )

        XCTAssertEqual(clip.audioData, audioData)
        XCTAssertEqual(request.httpMethod, "POST")
        XCTAssertEqual(request.value(forHTTPHeaderField: "Accept"), "audio/mpeg")
        XCTAssertNil(request.value(forHTTPHeaderField: "Authorization"))
        XCTAssertNil(request.value(forHTTPHeaderField: "xi-api-key"))
        XCTAssertEqual(payload["spokenText"] as? String, "I read every day.")
        XCTAssertEqual(payload["pronunciationKey"] as? String, "present-tense")
        XCTAssertEqual(
            try XCTUnwrap(payload["speed"] as? Double),
            0.7,
            accuracy: 0.000_1
        )
        XCTAssertEqual(
            payload["contractVersion"] as? String,
            "canonical-teacher-v1"
        )
        XCTAssertNil(payload["voiceID"])
        XCTAssertNil(payload["apiKey"])
    }

    func testNonHTTPSAndNonAudioResponsesFailClosed() async throws {
        let insecure = RemoteTeacherWordAudioProvider(
            endpoint: URL(string: "http://audio.example/word"),
            dataLoader: { _ in
                throw URLError(.badURL)
            }
        )

        do {
            _ = try await insecure.audio(
                for: TeacherWordAudioRequest(spokenText: "dog")
            )
            XCTFail("Expected an invalid endpoint error")
        } catch {
            XCTAssertEqual(error as? TeacherWordAudioError, .invalidEndpoint)
        }

        let endpoint = try XCTUnwrap(URL(string: "https://audio.example/word"))
        let wrongContentType = RemoteTeacherWordAudioProvider(
            endpoint: endpoint,
            dataLoader: { _ in
                let response = try XCTUnwrap(
                    HTTPURLResponse(
                        url: endpoint,
                        statusCode: 200,
                        httpVersion: nil,
                        headerFields: ["Content-Type": "application/json"]
                    )
                )
                return (Data("{}".utf8), response)
            }
        )

        do {
            _ = try await wrongContentType.audio(
                for: TeacherWordAudioRequest(spokenText: "dog")
            )
            XCTFail("Expected an unsupported content type error")
        } catch {
            XCTAssertEqual(
                error as? TeacherWordAudioError,
                .unsupportedContentType("application/json")
            )
        }
    }

    func testFileCacheRoundTripsCanonicalClip() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(
                "TadaWordsTeacherAudioTests-\(UUID().uuidString)",
                isDirectory: true
            )
        defer { try? FileManager.default.removeItem(at: directory) }
        let cache = FileTeacherWordAudioCache(directory: directory)
        let request = try TeacherWordAudioRequest(spokenText: "dog")
        let clip = try TeacherWordAudioClip(audioData: Data([1, 2, 3]))

        let emptyCacheResult = try await cache.clip(for: request)
        XCTAssertNil(emptyCacheResult)
        try await cache.store(clip, for: request)
        let cachedClip = try await cache.clip(for: request)

        XCTAssertEqual(cachedClip, clip)
    }
}

private final class LockedTeacherAudioRequest: @unchecked Sendable {
    private let lock = NSLock()
    private var storedValue: URLRequest?

    var value: URLRequest? {
        get { lock.withLock { storedValue } }
        set { lock.withLock { storedValue = newValue } }
    }
}
