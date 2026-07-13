import CoreGraphics
import XCTest

@testable import TadaWordsApplePlatform

final class AppleImageTextRecognitionTests: XCTestCase {
    func testResolverOrdersRowsTopToBottomAndWordsLeftToRight() {
        let fragments = [
            ApplePrintedTextFragment(text: "dog", minimumX: 0.6, verticalCenter: 0.8),
            ApplePrintedTextFragment(text: "cat", minimumX: 0.1, verticalCenter: 0.8),
            ApplePrintedTextFragment(text: "play", minimumX: 0.1, verticalCenter: 0.5),
        ]

        XCTAssertEqual(
            ApplePrintedTextResolver.resolve(fragments),
            ["cat", "dog", "play"]
        )
    }

    func testResolverDropsWhitespaceOnlyObservations() {
        XCTAssertEqual(
            ApplePrintedTextResolver.resolve([
                ApplePrintedTextFragment(text: "  ", minimumX: 0, verticalCenter: 1),
                ApplePrintedTextFragment(text: "read", minimumX: 0, verticalCenter: 0.5),
            ]),
            ["read"]
        )
    }
}
