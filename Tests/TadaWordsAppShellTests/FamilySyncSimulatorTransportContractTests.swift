import Foundation
import XCTest

final class FamilySyncSimulatorTransportContractTests: XCTestCase {
    func testAccountConfirmationWitnessResetsSecondDeviceDiscoveryCursor() throws {
        let normalized = try normalizedSource(
            at: "Apps/TadaWordsApp/FamilySyncSimulatorTestSupport.swift"
        )

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

    func testFamilySyncE2EUsesProcessIsolatedVoiceprintRepository() throws {
        let support = try normalizedSource(
            at: "Apps/TadaWordsApp/FamilySyncSimulatorTestSupport.swift"
        )
        XCTAssertTrue(
            support.contains(
                "static func voiceprintRepository( arguments: [String] = ProcessInfo.processInfo.arguments ) -> (any DeviceVoiceprintRepository)?"
            )
        )
        XCTAssertTrue(
            support.contains(
                "guard configuration(arguments: arguments) != nil else { return nil } return FamilySyncSimulatorDeviceVoiceprintRepository()"
            ),
            "Only an explicitly configured Family Sync E2E launch may replace the device Keychain repository."
        )
        XCTAssertTrue(
            support.contains(
                "private actor FamilySyncSimulatorDeviceVoiceprintRepository: DeviceVoiceprintRepository, FreshInstallationVoiceprintResetting"
            )
        )
        XCTAssertTrue(
            support.contains("templates.removeAll(keepingCapacity: false)"),
            "A clean-install fixture must clear every process-local template."
        )

        let app = try normalizedSource(
            at: "Apps/TadaWordsApp/TadaWordsApp.swift"
        )
        XCTAssertTrue(
            app.contains(
                "#if DEBUG && targetEnvironment(simulator) && !LOCAL_DEVICE_QA"
            )
        )
        XCTAssertTrue(
            app.contains(
                "FamilySyncSimulatorTestSupport.voiceprintRepository() ?? KeychainDeviceVoiceprintRepository()"
            )
        )
        XCTAssertTrue(
            app.contains(
                "#else baseVoiceprints = KeychainDeviceVoiceprintRepository() #endif"
            ),
            "Production and LocalQA must retain the device-only Keychain repository."
        )
    }

    private func normalizedSource(at relativePath: String) throws -> String {
        let source = try String(
            contentsOf: repositoryRoot.appendingPathComponent(relativePath),
            encoding: .utf8
        )
        return
            source
            .components(separatedBy: .whitespacesAndNewlines)
            .filter { !$0.isEmpty }
            .joined(separator: " ")
    }

    private var repositoryRoot: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
    }
}
