import XCTest

@testable import TadaWordsGuardianFeatures

final class GuardianProfileCardLayoutPolicyTests: XCTestCase {
    func testFullWidthIPadUsesTwoReadableProfileColumns() {
        XCTAssertEqual(
            GuardianProfileCardLayoutPolicy.columnCount(for: 960),
            2
        )
        XCTAssertEqual(
            GuardianProfileCardLayoutPolicy.cardWidth(for: 960),
            472,
            accuracy: 0.001
        )
    }

    func testNarrowParentLayoutsUseOneProfileColumn() {
        for width: CGFloat in [802, 361] {
            XCTAssertEqual(
                GuardianProfileCardLayoutPolicy.columnCount(for: width),
                1
            )
            XCTAssertEqual(
                GuardianProfileCardLayoutPolicy.cardWidth(for: width),
                width,
                accuracy: 0.001
            )
        }
    }

    func testInvalidWidthStillProducesOneZeroWidthColumn() {
        XCTAssertEqual(
            GuardianProfileCardLayoutPolicy.columnCount(for: -1),
            1
        )
        XCTAssertEqual(
            GuardianProfileCardLayoutPolicy.cardWidth(for: -1),
            0,
            accuracy: 0.001
        )
    }
}
