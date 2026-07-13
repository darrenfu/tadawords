import TadaWordsDomain
import XCTest

@testable import TadaWordsApplePlatform

final class AppleInterfaceOrientationPolicyTests: XCTestCase {
    func testChildRoutesStayLandscapeOnPhoneAndPad() {
        for family in [AppleDeviceFamily.phone, .pad] {
            XCTAssertEqual(
                AppleInterfaceOrientationPolicy.options(
                    for: .childLandscape,
                    deviceFamily: family
                ),
                .landscape
            )
        }
    }

    func testParentRoutesUseAllButUpsideDownOnPhone() {
        XCTAssertEqual(
            AppleInterfaceOrientationPolicy.options(
                for: .parentFlexible,
                deviceFamily: .phone
            ),
            .allButUpsideDown
        )
    }

    func testParentRoutesUseEveryOrientationOnPad() {
        XCTAssertEqual(
            AppleInterfaceOrientationPolicy.options(
                for: .parentFlexible,
                deviceFamily: .pad
            ),
            .all
        )
    }
}
