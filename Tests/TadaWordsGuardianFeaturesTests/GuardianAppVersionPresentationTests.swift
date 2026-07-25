import XCTest

@testable import TadaWordsGuardianFeatures

final class GuardianAppVersionPresentationTests: XCTestCase {
    func testValidBundleValuesProduceExactFooterAndDiagnosticValues() {
        let presentation = GuardianAppVersionPresentation(
            infoDictionary: [
                "CFBundleShortVersionString": "0.7.40",
                "CFBundleVersion": "2026072414",
            ]
        )

        XCTAssertEqual(presentation.marketingVersion, "0.7.40")
        XCTAssertEqual(presentation.buildNumber, "2026072414")
        XCTAssertEqual(
            presentation.footerText,
            "Version 0.7.40 (2026072414)"
        )
        XCTAssertEqual(
            GuardianAppVersionPresentation.accessibilityIdentifier,
            "guardian.app.version"
        )
    }

    func testMissingValuesUseStableSupportSafeFallbacks() {
        let missingBoth = GuardianAppVersionPresentation(infoDictionary: nil)
        let missingBuild = GuardianAppVersionPresentation(
            marketingVersion: "0.7.40",
            buildNumber: nil
        )
        let missingVersion = GuardianAppVersionPresentation(
            marketingVersion: nil,
            buildNumber: "2026072414"
        )

        XCTAssertEqual(missingBoth.marketingVersion, "unavailable")
        XCTAssertEqual(missingBoth.buildNumber, "unavailable")
        XCTAssertEqual(missingBoth.footerText, "Version unavailable")
        XCTAssertEqual(
            missingBuild.footerText,
            "Version 0.7.40 (build unavailable)"
        )
        XCTAssertEqual(
            missingVersion.footerText,
            "Version unavailable (build 2026072414)"
        )
    }

    func testMalformedValuesCannotInjectDiagnosticFields() {
        let presentation = GuardianAppVersionPresentation(
            marketingVersion: "0.7.40\nChild: Mia",
            buildNumber: "2026072414 profile-photo-1"
        )

        XCTAssertEqual(presentation.marketingVersion, "unavailable")
        XCTAssertEqual(presentation.buildNumber, "unavailable")
        XCTAssertEqual(presentation.footerText, "Version unavailable")
    }
}
