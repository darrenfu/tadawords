import TadaWordsDomain
import XCTest

@testable import TadaWordsAppShell

final class ApplicationOrientationPolicyTests: XCTestCase {
    func testChildRouteRequestsLandscape() {
        XCTAssertEqual(
            ApplicationOrientationPolicy.mode(for: .child),
            .childLandscape
        )
    }

    func testParentAndFirstRunParentRoutesRequestFlexibleOrientation() {
        XCTAssertEqual(
            ApplicationOrientationPolicy.mode(for: .parents),
            .parentFlexible
        )
        XCTAssertEqual(
            ApplicationOrientationPolicy.mode(for: .firstRunParents),
            .parentFlexible
        )
    }
}
