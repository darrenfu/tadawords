import Foundation
import TadaWordsContent
import TadaWordsDomain
import XCTest

final class TeacherAudioPreparationTests: XCTestCase {
    func testClientSourceContainsNoProviderCredentialMaterial() throws {
        let repositoryRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let fileManager = FileManager.default
        let roots = ["Apps", "Sources"].map {
            repositoryRoot.appendingPathComponent($0)
        }
        let textExtensions = Set(["swift", "plist", "json", "yml", "yaml", "xcprivacy"])
        let credentialPattern = try NSRegularExpression(
            pattern: #"sk_[A-Za-z0-9_-]{20,}"#
        )

        for root in roots {
            let files = try XCTUnwrap(
                fileManager.enumerator(
                    at: root,
                    includingPropertiesForKeys: [.isRegularFileKey]
                )
            )
            for case let file as URL in files {
                guard
                    textExtensions.contains(file.pathExtension.lowercased()),
                    let contents = try? String(contentsOf: file, encoding: .utf8)
                else { continue }
                for forbidden in [
                    "xi-api-key",
                    "ELEVENLABS_API_KEY",
                    "CARTESIA_API_KEY",
                ] {
                    XCTAssertFalse(
                        contents.contains(forbidden),
                        "Provider credential material entered client source: \(file.path)"
                    )
                }
                let fullRange = NSRange(contents.startIndex..., in: contents)
                XCTAssertNil(
                    credentialPattern.firstMatch(in: contents, range: fullRange),
                    "Credential-shaped material entered client source: \(file.path)"
                )
            }
        }
    }

    func testPreparationFailuresNeverBlockDifferentValidNewWords() async throws {
        let repository = InMemoryWordPoolRepository()
        let cases: [(word: String, failure: AudioPreparationFailure)] = [
            ("isabella", .teacher(.serverRejected(statusCode: 503))),
            ("marigold", .teacher(.serverRejected(statusCode: 429))),
            ("quokka", .teacher(.appAttestUnavailable)),
            ("zephyr", .teacher(.invalidResponse)),
            ("aluminum", .teacher(.invalidAudioChecksum)),
            ("flibbertigibbet", .offline),
        ]

        for testCase in cases {
            let preparer = RecordingAudioPreparer(failure: testCase.failure)
            let importer = ManualWordPoolImporter(
                repository: repository,
                audioPreparer: preparer
            )
            let result = try await importer.importBatch(
                testCase.word,
                profileID: ContentTestFixture.profileID,
                learningMode: .read,
                addedAt: ContentTestFixture.day
            )

            XCTAssertEqual(result.inserted.map(\.normalizedText), [testCase.word])
            let preparedWords = await preparer.preparedWords
            XCTAssertEqual(preparedWords, [testCase.word])
        }

        let entries = try await repository.entries(
            for: ContentTestFixture.profileID,
            learningMode: .read,
            includingInactive: true
        )
        XCTAssertEqual(Set(entries.map(\.normalizedText)), Set(cases.map(\.word)))
    }

    func testPreparationFailureDoesNotPartiallyRejectANewWordBatch() async throws {
        let repository = InMemoryWordPoolRepository()
        let preparer = RecordingAudioPreparer(
            failure: .teacher(.serverRejected(statusCode: 503))
        )
        let importer = ManualWordPoolImporter(
            repository: repository,
            audioPreparer: preparer
        )

        let result = try await importer.importBatch(
            "isabella periwinkle narwhal",
            profileID: ContentTestFixture.profileID,
            learningMode: .write,
            addedAt: ContentTestFixture.day
        )

        XCTAssertEqual(
            result.inserted.map(\.normalizedText),
            ["isabella", "periwinkle", "narwhal"]
        )
        XCTAssertTrue(result.rejected.isEmpty)
    }

    func testCancellationStillPreventsThePoolCommit() async throws {
        let repository = InMemoryWordPoolRepository()
        let importer = ManualWordPoolImporter(
            repository: repository,
            audioPreparer: RecordingAudioPreparer(failure: .cancelled)
        )

        do {
            _ = try await importer.importBatch(
                "isabella",
                profileID: ContentTestFixture.profileID,
                learningMode: .read,
                addedAt: ContentTestFixture.day
            )
            XCTFail("Cancellation must stop the import")
        } catch is CancellationError {
            // Expected.
        }

        let entries = try await repository.entries(
            for: ContentTestFixture.profileID,
            learningMode: .read,
            includingInactive: true
        )
        XCTAssertTrue(entries.isEmpty)
    }

    func testSuccessfulPreparationPrecedesAtomicPoolCommit() async throws {
        let repository = InMemoryWordPoolRepository()
        let preparer = RecordingAudioPreparer()
        let importer = ManualWordPoolImporter(
            repository: repository,
            audioPreparer: preparer
        )

        let result = try await importer.importBatch(
            "cat dog",
            profileID: ContentTestFixture.profileID,
            learningMode: .write,
            addedAt: ContentTestFixture.day
        )

        XCTAssertEqual(result.inserted.count, 2)
        let prepared = await preparer.preparedWords
        XCTAssertEqual(prepared, ["cat", "dog"])
    }
}

private actor RecordingAudioPreparer: TeacherWordAudioPreparing {
    private let failure: AudioPreparationFailure?
    private(set) var preparedWords: [String] = []

    init(failure: AudioPreparationFailure? = nil) {
        self.failure = failure
    }

    func prepare(_ prompts: [WordPrompt]) async throws {
        preparedWords = prompts.map(\.normalizedText)
        switch failure {
        case .teacher(let error):
            throw error
        case .offline:
            throw URLError(.notConnectedToInternet)
        case .cancelled:
            throw CancellationError()
        case nil:
            break
        }
    }

    func requirePrepared(_ prompts: [WordPrompt]) async throws {
        _ = prompts
    }
}

private enum AudioPreparationFailure: Sendable {
    case teacher(TeacherWordAudioError)
    case offline
    case cancelled
}
