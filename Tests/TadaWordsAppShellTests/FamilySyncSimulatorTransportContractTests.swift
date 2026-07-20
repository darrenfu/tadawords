import Foundation
import XCTest

final class FamilySyncSimulatorTransportContractTests: XCTestCase {
    func testAccountConfirmationWitnessResetsSecondDeviceDiscoveryCursor() throws {
        let support = try String(
            contentsOf: repositoryRoot.appendingPathComponent(
                "Apps/TadaWordsApp/FamilySyncSimulatorTestSupport.swift"
            ),
            encoding: .utf8
        )
        let normalized =
            support
            .components(separatedBy: .whitespacesAndNewlines)
            .filter { !$0.isEmpty }
            .joined(separator: " ")

        XCTAssertTrue(
            normalized.contains(
                "func confirmCurrentAccount() async throws -> FamilySyncAccountChange? {"
            ),
            "The simulator transport must witness FamilySyncTransport.confirmCurrentAccount instead of declaring an unrelated Void overload."
        )
        XCTAssertTrue(
            normalized.contains(
                "guard scenario == .secondDeviceAdoption else { return nil }"
            )
        )
        XCTAssertTrue(normalized.contains("deliveredRemoteBundle = false"))
        XCTAssertTrue(
            normalized.contains(
                "FileManager.default.removeItem(at: cursorMarkerURL)"
            ),
            "Account confirmation must clear the acknowledged fixture cursor so relaunch performs a full refetch."
        )
    }

    private var repositoryRoot: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
    }
}
