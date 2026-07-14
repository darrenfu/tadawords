import Foundation
import XCTest

@testable import TadaWordsDomain

final class WordPromptTests: XCTestCase {
    func testDisplayTextPreservesGuardianCaseWhileDeduplicationNormalizes() throws {
        let uppercase = try WordPrompt(learningMode: .read, text: "I")
        let lowercase = try WordPrompt(learningMode: .read, text: "i")

        XCTAssertEqual(uppercase.displayText, "I")
        XCTAssertEqual(uppercase.normalizedText, "i")
        XCTAssertEqual(uppercase.deduplicationKey, lowercase.deduplicationKey)
    }

    func testNormalizationMakesEquivalentManualEntriesDeduplicate() throws {
        let first = try WordPrompt(
            learningMode: .read,
            text: "  I\u{2019}M  "
        )
        let second = try WordPrompt(
            learningMode: .read,
            text: "i'm"
        )

        XCTAssertEqual(first.normalizedText, "i'm")
        XCTAssertEqual(first.deduplicationKey, second.deduplicationKey)
    }

    func testNormalizationRejectsPhrasesAndUnsupportedCharacters() {
        XCTAssertThrowsError(
            try WordPrompt(learningMode: .read, text: "two words")
        ) { error in
            XCTAssertEqual(
                error as? WordPromptValidationError,
                .multipleWordsNotSupported
            )
        }

        XCTAssertThrowsError(
            try WordPrompt(learningMode: .read, text: "word!")
        ) { error in
            XCTAssertEqual(
                error as? WordPromptValidationError,
                .unsupportedCharacters
            )
        }
    }

    func testAudioOnlyWriteHomophoneUsesCanonicalPronunciationWithoutContext() {
        XCTAssertNoThrow(
            try WordPrompt(learningMode: .write, text: "write")
        )

        XCTAssertNoThrow(
            try WordPrompt(
                learningMode: .write,
                text: "write",
                audioCue: .contextual("I write my name.")
            )
        )
    }

    func testHeteronymUsesCanonicalPronunciationWithoutContext() {
        XCTAssertNoThrow(
            try WordPrompt(learningMode: .read, text: "read")
        )

        XCTAssertNoThrow(
            try WordPrompt(
                learningMode: .read,
                text: "read",
                audioCue: .contextual("I read a book every day.")
            )
        )
    }

    func testVisualReadPromptDoesNotRequireHomophoneContext() {
        XCTAssertNoThrow(
            try WordPrompt(learningMode: .read, text: "write")
        )
    }

    func testLegacyContextualPromptRemainsDecodable() throws {
        let legacy = try WordPrompt(
            learningMode: .read,
            text: "read",
            audioCue: .contextual("I read a book every day.")
        )

        let encoded = try JSONEncoder().encode(legacy)
        let decoded = try JSONDecoder().decode(WordPrompt.self, from: encoded)

        XCTAssertEqual(decoded, legacy)
    }

    func testContextMustActuallyContainTarget() {
        XCTAssertThrowsError(
            try WordPrompt(
                learningMode: .write,
                text: "write",
                audioCue: .contextual("I use a pencil.")
            )
        ) { error in
            XCTAssertEqual(
                error as? WordPromptValidationError,
                .contextMustContainTarget(word: "write")
            )
        }
    }

    func testDecodingCannotBypassPromptSafetyValidation() throws {
        let valid = try WordPrompt(
            learningMode: .write,
            text: "write",
            audioCue: .contextual("I write my name.")
        )
        let encoded = try JSONEncoder().encode(valid)
        let object = try XCTUnwrap(
            JSONSerialization.jsonObject(with: encoded) as? [String: Any]
        )
        var invalidObject = object
        invalidObject["audioCue"] = [
            "spokenContext": "I use a pencil."
        ]
        let invalidData = try JSONSerialization.data(withJSONObject: invalidObject)

        XCTAssertThrowsError(try JSONDecoder().decode(WordPrompt.self, from: invalidData))
    }
}
