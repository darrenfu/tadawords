import TadaWordsContent
import TadaWordsDomain
import XCTest

final class ManualWordBatchParserTests: XCTestCase {
    func testParsesCommaNewlineWhitespaceAndFullWidthComma() {
        let result = ManualWordBatchParser().parse(
            " Cat，\nＤＯＧ   CAN’T\tmother–in–law ",
            learningMode: .read
        )

        XCTAssertEqual(
            result.accepted.map(\.prompt.normalizedText),
            ["cat", "dog", "can't", "mother-in-law"]
        )
        XCTAssertEqual(result.accepted.map(\.inputPosition), [0, 1, 2, 3])
        XCTAssertTrue(result.rejected.isEmpty)
    }

    func testRejectsNormalizedDuplicatesInsideOneBatch() {
        let result = ManualWordBatchParser().parse(
            "Cat, ＣＡＴ cat, dog",
            learningMode: .read
        )

        XCTAssertEqual(result.accepted.map(\.prompt.normalizedText), ["cat", "dog"])
        XCTAssertEqual(
            result.rejected.map(\.reason),
            [
                .duplicateInBatch(normalizedText: "cat"),
                .duplicateInBatch(normalizedText: "cat"),
            ]
        )
    }

    func testReturnsTypedDomainValidationRejections() {
        let result = ManualWordBatchParser().parse(
            "good, 123, too",
            learningMode: .write
        )

        XCTAssertEqual(result.accepted.map(\.prompt.normalizedText), ["good"])
        XCTAssertEqual(
            result.rejected.map(\.reason),
            [
                .invalidPrompt(.unsupportedCharacters),
                .invalidPrompt(
                    .contextRequired(word: "too", reason: .homophone)
                ),
            ]
        )
    }

    func testContextCueAllowsOtherwiseAmbiguousWriteWord() {
        let result = ManualWordBatchParser().parse(
            "too",
            learningMode: .write,
            audioCuesByNormalizedWord: [
                "too": .contextual("This is too much.")
            ]
        )

        XCTAssertEqual(result.accepted.map(\.prompt.normalizedText), ["too"])
        XCTAssertTrue(result.rejected.isEmpty)
    }

    func testEmptyInputHasOneTypedRejection() {
        let result = ManualWordBatchParser().parse(
            " \n\t,， ",
            learningMode: .read
        )

        XCTAssertTrue(result.accepted.isEmpty)
        XCTAssertEqual(result.rejected.count, 1)
        XCTAssertEqual(result.rejected.first?.reason, .emptyBatch)
        XCTAssertNil(result.rejected.first?.inputPosition)
    }
}
