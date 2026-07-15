import Foundation
import TadaWordsDomain
import XCTest

@testable import TadaWordsApplePlatform

final class BundledTeacherWordAudioProviderTests: XCTestCase {
    func testProductionPackExposesFiveHundredWordsAndBothVariants() async throws {
        let provider = try XCTUnwrap(BundledTeacherWordAudioProvider.production())

        XCTAssertEqual(provider.bundledWordCount, 500)
        for word in [
            "a", "i", "at", "bun", "cat", "chick", "come", "near", "of",
            "swordfish",
        ] {
            for usage in [
                TeacherWordAudioUsage.readHint,
                TeacherWordAudioUsage.writePrompt,
            ] {
                let clip = try await provider.audio(
                    for: TeacherWordAudioRequest(
                        spokenText: word,
                        usage: usage
                    )
                )
                XCTAssertGreaterThan(clip.audioData.count, 1_000)
            }
        }
    }

    func testLoadsCaseInsensitiveReadAndWriteVariants() async throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let provider = try BundledTeacherWordAudioProvider(
            resourceRoot: fixture.root
        )

        let read = try await provider.audio(
            for: TeacherWordAudioRequest(
                spokenText: "DOG",
                usage: .readHint
            )
        )
        let write = try await provider.audio(
            for: TeacherWordAudioRequest(
                spokenText: "dog",
                usage: .writePrompt
            )
        )

        XCTAssertEqual(read.audioData, Data([1, 2, 3]))
        XCTAssertEqual(write.audioData, Data([4, 5, 6]))
    }

    func testUnknownOrContextualTextFallsBack() async throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let provider = try BundledTeacherWordAudioProvider(
            resourceRoot: fixture.root
        )

        for request in [
            try TeacherWordAudioRequest(spokenText: "cat"),
            try TeacherWordAudioRequest(spokenText: "The dog runs."),
            try TeacherWordAudioRequest(
                spokenText: "dog",
                pronunciationKey: "alternate"
            ),
        ] {
            do {
                _ = try await provider.audio(for: request)
                XCTFail("Expected the bundled provider to fail closed")
            } catch {
                XCTAssertEqual(
                    error as? TeacherWordAudioError,
                    .unavailableOfflineClip
                )
            }
        }
    }

    private struct Fixture {
        let root: URL

        init() throws {
            root = FileManager.default.temporaryDirectory.appendingPathComponent(
                "BundledTeacherWordAudioProviderTests-\(UUID().uuidString)",
                isDirectory: true
            )
            let read = root.appendingPathComponent("read-hint", isDirectory: true)
            let write = root.appendingPathComponent(
                "write-prompt",
                isDirectory: true
            )
            try FileManager.default.createDirectory(
                at: read,
                withIntermediateDirectories: true
            )
            try FileManager.default.createDirectory(
                at: write,
                withIntermediateDirectories: true
            )
            let manifest = """
                {
                  "words": ["dog"],
                  "variants": {
                    "read_hint": {"directory": "read-hint"},
                    "write_prompt": {"directory": "write-prompt"}
                  }
                }
                """
            try Data(manifest.utf8).write(
                to: root.appendingPathComponent("manifest.json")
            )
            try Data([1, 2, 3]).write(
                to: read.appendingPathComponent("dog.m4a")
            )
            try Data([4, 5, 6]).write(
                to: write.appendingPathComponent("dog.m4a")
            )
        }

        func remove() {
            try? FileManager.default.removeItem(at: root)
        }
    }
}
