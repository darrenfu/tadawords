import Foundation
import XCTest

final class ChildSpeechPermissionRouteContractTests: XCTestCase {
    func testChildFeatureModuleCannotCallSystemPermissionRequestAPIs() throws {
        let featureSources = try swiftSources(
            under: repositoryRoot.appendingPathComponent(
                "Sources/TadaWordsFeatures",
                isDirectory: true
            )
        )
        let combined = try featureSources.map(source).joined(separator: "\n")

        for forbiddenCapability in [
            "SFSpeechRecognizer.requestAuthorization",
            "AVCaptureDevice.requestAccess",
            "requestSpeechAuthorization",
            "requestSpeechPermissions",
            "requestAuthorization()",
            ".requestPermissions()",
        ] {
            XCTAssertFalse(
                combined.contains(forbiddenCapability),
                "Child features regained prompting capability: \(forbiddenCapability)"
            )
        }
        XCTAssertTrue(combined.contains("permissionActions.isAuthorized()"))
    }

    func testProfileSwitchReadEntryReplayAndRelaunchUseOneCheckOnlyBoundary() throws {
        let root = try source(
            repositoryRoot.appendingPathComponent(
                "Sources/TadaWordsFeatures/TadaWordsRootView.swift"
            )
        )

        XCTAssertEqual(
            root.components(separatedBy: "permissionActions: speechPermissionActions")
                .count - 1,
            1,
            "Every Read presentation, including replay after profile changes or relaunch, must use the root's single child boundary."
        )
        XCTAssertFalse(root.contains("requestSpeechPermissions"))
        XCTAssertFalse(root.contains("requestAuthorization"))
    }

    func testDemoDeepLinkUsesAuthorizedCheckOnlyFixture() throws {
        let root = try source(
            repositoryRoot.appendingPathComponent(
                "Sources/TadaWordsFeatures/TadaWordsRootView.swift"
            )
        )
        let actions = try source(
            repositoryRoot.appendingPathComponent(
                "Sources/TadaWordsFeatures/QuestRecognitionDependencies.swift"
            )
        )

        XCTAssertTrue(root.contains("speechPermissionActions: .demoAuthorized"))
        XCTAssertTrue(root.contains("demoLaunchRoute: DemoLaunchRoute.current"))
        XCTAssertTrue(actions.contains("static let demoAuthorized"))
        XCTAssertFalse(actions.contains("requestAuthorization"))
        XCTAssertFalse(actions.contains("requestPermissions"))
    }

    func testAuthorizedChildPathContinuesToRecognitionWithoutParentCapability() throws {
        let readQuest = try source(
            repositoryRoot.appendingPathComponent(
                "Sources/TadaWordsFeatures/ReadQuestView.swift"
            )
        )

        XCTAssertTrue(readQuest.contains("permissionActions.isAuthorized()"))
        XCTAssertTrue(readQuest.contains("guard isAuthorized else"))
        XCTAssertTrue(readQuest.contains("await listenForWord()"))
        XCTAssertFalse(readQuest.contains("requestSpeechPermissions"))
        XCTAssertFalse(readQuest.contains("requestAuthorization"))
    }

    func testAppShellWiresPromptingOnlyIntoGuardianRoute() throws {
        let appShell = try source(
            repositoryRoot.appendingPathComponent(
                "Sources/TadaWordsAppShell/TadaWordsApplicationView.swift"
            )
        )

        XCTAssertTrue(
            appShell.contains(
                "speechPermissionActions = SpeechPermissionActions {\n            await currentSpeechPermissionState().isAuthorized"
            )
        )
        XCTAssertTrue(
            appShell.contains(
                "requestSpeechPermissions: requestSpeechPermissions"
            )
        )
        XCTAssertEqual(
            appShell.components(separatedBy: "requestSpeechPermissions:").count - 1,
            3,
            "The prompting closure should exist only as stored parent capability, production initializer input, and GuardianRootView output."
        )
    }

    private var repositoryRoot: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
    }

    private func swiftSources(under directory: URL) throws -> [URL] {
        let contents = try FileManager.default.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: nil
        )
        return
            contents
            .filter { $0.pathExtension == "swift" }
            .sorted { $0.lastPathComponent < $1.lastPathComponent }
    }

    private func source(_ url: URL) throws -> String {
        try String(contentsOf: url, encoding: .utf8)
    }
}
