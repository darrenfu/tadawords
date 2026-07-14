import TadaWordsContent
import XCTest

final class RecognizedEnglishWordParserTests: XCTestCase {
    func testExtractsNormalizesAndDeduplicatesEnglishWordsInReadingOrder() {
        let words = RecognizedEnglishWordParser().parse([
            "THE, cat!",
            "Cat can’t co-operate.",
            "123 — dog",
        ])

        XCTAssertEqual(words, ["the", "cat", "can't", "co-operate", "dog"])
    }

    func testIgnoresNonEnglishNoiseAndEmptyFragments() {
        let words = RecognizedEnglishWordParser().parse([
            "   ",
            "你好 123 %",
            "we\nGO",
        ])

        XCTAssertEqual(words, ["we", "go"])
    }

    func testParseResultCountsValidOccurrencesBeforeDeduplication() {
        let result = RecognizedEnglishWordParser().parseResult([
            "cat cat CAT",
            "dog 123 dog!",
        ])

        XCTAssertEqual(result.uniqueWords, ["cat", "dog"])
        XCTAssertEqual(result.recognizedWordCount, 5)
    }
}
