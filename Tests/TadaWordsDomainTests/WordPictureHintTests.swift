import XCTest

@testable import TadaWordsDomain

final class WordPictureHintTests: XCTestCase {
    func testConcreteWordsResolveCaseInsensitively() {
        XCTAssertEqual(
            WordPictureHintCatalog.descriptor(for: " DOG ")?.assetCode,
            "1f436"
        )
        XCTAssertEqual(
            WordPictureHintCatalog.descriptor(for: "Unicorn")?.assetCode,
            "1f984"
        )
        XCTAssertEqual(
            WordPictureHintCatalog.descriptor(for: "bike")?.assetCode,
            WordPictureHintCatalog.descriptor(for: "bicycle")?.assetCode
        )
        XCTAssertEqual(WordPictureHintCatalog.assetCodes.count, 74)
    }

    func testAbstractAndFunctionWordsFailClosed() {
        for word in ["the", "come", "help", "kind", "read"] {
            XCTAssertNil(WordPictureHintCatalog.descriptor(for: word), word)
        }
    }
}
