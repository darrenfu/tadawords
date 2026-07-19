import Foundation
import XCTest

final class PrivacyManifestContractTests: XCTestCase {
    func testPrivacyManifestMatchesAuditedRequiredReasonContract() throws {
        let manifest = try loadManifest()
        let rawEntries = try XCTUnwrap(
            manifest["NSPrivacyAccessedAPITypes"] as? [[String: Any]]
        )

        let entries = try Dictionary(
            uniqueKeysWithValues: rawEntries.map { entry in
                let category = try XCTUnwrap(
                    entry["NSPrivacyAccessedAPIType"] as? String
                )
                let reasons = try XCTUnwrap(
                    entry["NSPrivacyAccessedAPITypeReasons"] as? [String]
                )
                return (category, reasons)
            }
        )

        XCTAssertEqual(
            entries,
            [
                "NSPrivacyAccessedAPICategoryFileTimestamp": ["C617.1"],
                "NSPrivacyAccessedAPICategorySystemBootTime": ["35F9.1"],
                "NSPrivacyAccessedAPICategoryUserDefaults": ["CA92.1"],
            ]
        )
    }

    func testPrivacyManifestKeepsTrackingAndCollectionDisabled() throws {
        let manifest = try loadManifest()

        XCTAssertEqual(manifest["NSPrivacyTracking"] as? Bool, false)
        XCTAssertEqual(
            manifest["NSPrivacyTrackingDomains"] as? [String],
            []
        )
        XCTAssertTrue(
            try XCTUnwrap(
                manifest["NSPrivacyCollectedDataTypes"] as? [[String: Any]]
            ).isEmpty
        )
    }

    private func loadManifest() throws -> [String: Any] {
        let repositoryRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let manifestURL = repositoryRoot.appendingPathComponent(
            "Apps/TadaWordsApp/PrivacyInfo.xcprivacy"
        )
        let data = try Data(contentsOf: manifestURL)
        return try XCTUnwrap(
            PropertyListSerialization.propertyList(from: data, format: nil)
                as? [String: Any]
        )
    }
}
