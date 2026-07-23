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

    func testFailedPreparationLeavesPoolUnchangedForParentRetry() async throws {
        let repository = InMemoryWordPoolRepository()
        let preparer = RecordingAudioPreparer(
            error: TeacherWordAudioError.serverRejected(statusCode: 503)
        )
        let importer = ManualWordPoolImporter(
            repository: repository,
            audioPreparer: preparer
        )

        do {
            _ = try await importer.importBatch(
                "cat dog",
                profileID: ContentTestFixture.profileID,
                learningMode: .read,
                addedAt: ContentTestFixture.day
            )
            XCTFail("Expected preparation to fail")
        } catch {
            XCTAssertEqual(
                error as? TeacherWordAudioError,
                .serverRejected(statusCode: 503)
            )
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
    private let error: TeacherWordAudioError?
    private(set) var preparedWords: [String] = []

    init(error: TeacherWordAudioError? = nil) {
        self.error = error
    }

    func prepare(_ prompts: [WordPrompt]) async throws {
        if let error { throw error }
        preparedWords = prompts.map(\.normalizedText)
    }

    func requirePrepared(_ prompts: [WordPrompt]) async throws {
        _ = prompts
    }
}
