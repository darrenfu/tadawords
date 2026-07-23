import CryptoKit
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
            authorizer: TestTeacherAudioAuthorizer(),
            dataLoader: { request in
                capturedRequest.value = request
                let checksum = SHA256.hash(data: audioData)
                    .map { String(format: "%02x", $0) }
                    .joined()
                let response = try XCTUnwrap(
                    HTTPURLResponse(
                        url: endpoint,
                        statusCode: 200,
                        httpVersion: nil,
                        headerFields: [
                            "Content-Type": "audio/mpeg",
                            "X-PawGoo-Audio-Checksum": checksum,
                            "X-PawGoo-Audio-Contract": "elevenlabs-teacher-v1",
                        ]
                    )
                )
                return (audioData, response)
            }
        )

        let clip = try await provider.audio(
            for: TeacherWordAudioRequest(
                spokenText: "read",
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
        XCTAssertEqual(payload["word"] as? String, "read")
        XCTAssertEqual(payload["pronunciationKey"] as? String, "present-tense")
        XCTAssertEqual(payload["usage"] as? String, "read_hint")
        XCTAssertEqual(payload["locale"] as? String, "en-US")
        XCTAssertEqual(payload["challenge"] as? String, "a".repeated(43))
        XCTAssertEqual(
            payload["contractVersion"] as? String,
            "elevenlabs-teacher-v1"
        )
        XCTAssertNotNil(request.value(forHTTPHeaderField: "X-PawGoo-App-Attest"))
        XCTAssertNil(payload["spokenText"])
        XCTAssertNil(payload["speed"])
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
            authorizer: TestTeacherAudioAuthorizer(),
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

    func testUnauthorizedResponseResetsAttestationAndRetriesOnce() async throws {
        let endpoint = try XCTUnwrap(URL(string: "https://audio.example/word"))
        let audioData = Data([0x49, 0x44, 0x33, 0x04])
        let authorizer = TestTeacherAudioAuthorizer()
        let requestCount = LockedCounter()
        let provider = RemoteTeacherWordAudioProvider(
            endpoint: endpoint,
            authorizer: authorizer,
            dataLoader: { _ in
                let count = requestCount.increment()
                if count == 1 {
                    return (
                        Data(),
                        try XCTUnwrap(
                            HTTPURLResponse(
                                url: endpoint,
                                statusCode: 401,
                                httpVersion: nil,
                                headerFields: nil
                            )
                        )
                    )
                }
                let checksum = SHA256.hash(data: audioData)
                    .map { String(format: "%02x", $0) }
                    .joined()
                return (
                    audioData,
                    try XCTUnwrap(
                        HTTPURLResponse(
                            url: endpoint,
                            statusCode: 200,
                            httpVersion: nil,
                            headerFields: [
                                "Content-Type": "audio/mpeg",
                                "X-PawGoo-Audio-Checksum": checksum,
                                "X-PawGoo-Audio-Contract":
                                    "elevenlabs-teacher-v1",
                            ]
                        )
                    )
                )
            }
        )

        let clip = try await provider.audio(
            for: TeacherWordAudioRequest(spokenText: "dog")
        )
        let resetCount = await authorizer.resetCount

        XCTAssertEqual(clip.audioData, audioData)
        XCTAssertEqual(requestCount.value, 2)
        XCTAssertEqual(resetCount, 1)
    }

    func testContractAndChecksumMismatchFailClosed() async throws {
        let endpoint = try XCTUnwrap(URL(string: "https://audio.example/word"))
        let audioData = Data([0x49, 0x44, 0x33, 0x04])
        let checksum = SHA256.hash(data: audioData)
            .map { String(format: "%02x", $0) }
            .joined()
        let cases: [(String, String, TeacherWordAudioError)] = [
            ("old-contract", checksum, .mismatchedAudioContract),
            (
                "elevenlabs-teacher-v1",
                String(repeating: "0", count: 64),
                .invalidAudioChecksum
            ),
        ]

        for (contract, responseChecksum, expectedError) in cases {
            let provider = RemoteTeacherWordAudioProvider(
                endpoint: endpoint,
                authorizer: TestTeacherAudioAuthorizer(),
                dataLoader: { _ in
                    (
                        audioData,
                        try XCTUnwrap(
                            HTTPURLResponse(
                                url: endpoint,
                                statusCode: 200,
                                httpVersion: nil,
                                headerFields: [
                                    "Content-Type": "audio/mpeg",
                                    "X-PawGoo-Audio-Checksum":
                                        responseChecksum,
                                    "X-PawGoo-Audio-Contract": contract,
                                ]
                            )
                        )
                    )
                }
            )

            do {
                _ = try await provider.audio(
                    for: TeacherWordAudioRequest(spokenText: "dog")
                )
                XCTFail("Expected response integrity validation to fail")
            } catch {
                XCTAssertEqual(error as? TeacherWordAudioError, expectedError)
            }
        }
    }

    func testOversizedRemoteAudioFailsBeforeChecksumOrCache() async throws {
        let endpoint = try XCTUnwrap(URL(string: "https://audio.example/word"))
        let maximum = TeacherWordAudioClip.maximumByteCount
        let provider = RemoteTeacherWordAudioProvider(
            endpoint: endpoint,
            authorizer: TestTeacherAudioAuthorizer(),
            dataLoader: { _ in
                (
                    Data(count: maximum + 1),
                    try XCTUnwrap(
                        HTTPURLResponse(
                            url: endpoint,
                            statusCode: 200,
                            httpVersion: nil,
                            headerFields: [
                                "Content-Type": "audio/mpeg",
                                "X-PawGoo-Audio-Checksum":
                                    String(repeating: "0", count: 64),
                                "X-PawGoo-Audio-Contract":
                                    "elevenlabs-teacher-v1",
                            ]
                        )
                    )
                )
            }
        )

        do {
            _ = try await provider.audio(
                for: TeacherWordAudioRequest(spokenText: "dog")
            )
            XCTFail("Expected the oversized response to fail")
        } catch {
            XCTAssertEqual(
                error as? TeacherWordAudioError,
                .responseTooLarge(maximumByteCount: maximum)
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

    func testFileCacheSeparatesUsageAndRejectsMutatedBytes() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(
                "TadaWordsTeacherAudioIntegrity-\(UUID().uuidString)",
                isDirectory: true
            )
        defer { try? FileManager.default.removeItem(at: directory) }
        let cache = FileTeacherWordAudioCache(directory: directory)
        let read = try TeacherWordAudioRequest(
            spokenText: "dog",
            usage: .readHint
        )
        let write = try TeacherWordAudioRequest(
            spokenText: "dog",
            usage: .writePrompt
        )
        let clip = try TeacherWordAudioClip(audioData: Data([1, 2, 3]))

        try await cache.store(clip, for: read)
        let writeClip = try await cache.clip(for: write)
        XCTAssertNil(writeClip)
        let audioURL = try XCTUnwrap(
            FileManager.default
                .contentsOfDirectory(
                    at: directory,
                    includingPropertiesForKeys: nil
                )
                .first(where: { $0.pathExtension == "mp3" })
        )
        try Data([9, 9, 9]).write(to: audioURL, options: .atomic)

        let mutatedReadClip = try await cache.clip(for: read)
        XCTAssertNil(mutatedReadClip)
        XCTAssertFalse(FileManager.default.fileExists(atPath: audioURL.path))
    }

    func testPipelineAllowsNetworkOnlyDuringParentPreparation() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(
                "TadaWordsTeacherAudioPipeline-\(UUID().uuidString)",
                isDirectory: true
            )
        defer { try? FileManager.default.removeItem(at: directory) }
        let endpoint = try XCTUnwrap(URL(string: "https://audio.example/word"))
        let audioData = Data([0x49, 0x44, 0x33, 0x04])
        let requestCount = LockedCounter()
        let remote = RemoteTeacherWordAudioProvider(
            endpoint: endpoint,
            authorizer: TestTeacherAudioAuthorizer(),
            dataLoader: { _ in
                requestCount.increment()
                let checksum = SHA256.hash(data: audioData)
                    .map { String(format: "%02x", $0) }
                    .joined()
                return (
                    audioData,
                    try XCTUnwrap(
                        HTTPURLResponse(
                            url: endpoint,
                            statusCode: 200,
                            httpVersion: nil,
                            headerFields: [
                                "Content-Type": "audio/mpeg",
                                "X-PawGoo-Audio-Checksum": checksum,
                                "X-PawGoo-Audio-Contract":
                                    "elevenlabs-teacher-v1",
                            ]
                        )
                    )
                )
            }
        )
        let pipeline = TeacherWordAudioPipeline(
            bundled: nil,
            remote: remote,
            cache: FileTeacherWordAudioCache(directory: directory)
        )
        let prompt = try WordPrompt(
            learningMode: .read,
            text: "dog"
        )
        let request = TeacherWordAudioRequest(prompt: prompt)

        do {
            _ = try await pipeline.audio(for: request)
            XCTFail("Child playback must not fetch a missing clip")
        } catch {
            XCTAssertEqual(
                error as? TeacherWordAudioError,
                .unavailableOfflineClip
            )
        }
        XCTAssertEqual(requestCount.value, 0)

        try await pipeline.prepare([prompt])
        let prepared = try await pipeline.audio(for: request)

        XCTAssertEqual(requestCount.value, 1)
        XCTAssertEqual(prepared.audioData, audioData)
    }
}

private actor TestTeacherAudioAuthorizer: TeacherAudioRequestAuthorizing {
    private(set) var resetCount = 0

    func authorize(
        body: @Sendable (String) throws -> Data
    ) async throws -> AuthorizedTeacherAudioRequest {
        AuthorizedTeacherAudioRequest(
            body: try body(String(repeating: "a", count: 43)),
            appAttestHeader: "test-app-attest"
        )
    }

    func resetRegistration() {
        resetCount += 1
    }
}

extension String {
    fileprivate func repeated(_ count: Int) -> String {
        String(repeating: self, count: count)
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

private final class LockedCounter: @unchecked Sendable {
    private let lock = NSLock()
    private var storedValue = 0

    var value: Int {
        lock.withLock { storedValue }
    }

    @discardableResult
    func increment() -> Int {
        lock.withLock {
            storedValue += 1
            return storedValue
        }
    }
}
