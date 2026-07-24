import Foundation
import XCTest

final class ChildSpeechPermissionRouteContractTests: XCTestCase {
    func testChildFeatureModuleCannotCallApplePermissionAPIsDirectly() throws {
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
            "requestAuthorization()",
        ] {
            XCTAssertFalse(
                combined.contains(forbiddenCapability),
                "Child features regained prompting capability: \(forbiddenCapability)"
            )
        }
        XCTAssertTrue(
            combined.contains("permissionActions.authorizeMicrophoneTap()")
        )
    }

    func testProfileSwitchReadEntryReplayAndRelaunchUseOneContextualBoundary() throws {
        let root = try source(
            repositoryRoot.appendingPathComponent(
                "Sources/TadaWordsFeatures/TadaWordsRootView.swift"
            )
        )

        XCTAssertEqual(
            root.components(separatedBy: "permissionActions: speechPermissionActions")
                .count - 1,
            1,
            "Every Read presentation, including replay after profile changes or relaunch, must use the root's single contextual boundary."
        )
        XCTAssertFalse(root.contains("requestSpeechPermissions"))
        XCTAssertFalse(root.contains("requestAuthorization"))
    }

    func testDemoDeepLinkUsesAuthorizedFixtureWithoutSystemCapability() throws {
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

    func testResolvedChildTapContinuesOriginalActionIntoRecognition() throws {
        let readQuest = try source(
            repositoryRoot.appendingPathComponent(
                "Sources/TadaWordsFeatures/ReadQuestView.swift"
            )
        )

        XCTAssertTrue(
            readQuest.contains("permissionActions.authorizeMicrophoneTap()")
        )
        XCTAssertTrue(readQuest.contains("guard isAuthorized else"))
        XCTAssertTrue(readQuest.contains("await listenForWord()"))
        XCTAssertFalse(readQuest.contains("requestSpeechPermissions"))
        XCTAssertFalse(readQuest.contains("requestAuthorization"))
    }

    func testAppShellRequestsOnlyWhenContextualStatusIsUndetermined() throws {
        let appShell = try source(
            repositoryRoot.appendingPathComponent(
                "Sources/TadaWordsAppShell/TadaWordsApplicationView.swift"
            )
        )

        XCTAssertTrue(
            appShell.contains(
                "guard current.hasUndeterminedPermission else {\n                    return current.isAuthorized"
            )
        )
        XCTAssertTrue(
            appShell.contains(
                "return await requestSpeechPermissions().isAuthorized"
            )
        )
        XCTAssertTrue(
            appShell.contains(
                "requestSpeechPermissions: requestSpeechPermissions"
            )
        )
    }

    func testReadCancelsPendingAuthorizationOnNavigationAndBackground() throws {
        let readQuest = try source(
            repositoryRoot.appendingPathComponent(
                "Sources/TadaWordsFeatures/ReadQuestView.swift"
            )
        )

        XCTAssertTrue(readQuest.contains(".onDisappear {"))
        XCTAssertTrue(readQuest.contains("listeningTask?.cancel()"))
        XCTAssertTrue(readQuest.contains("guard phase == .background else"))
        XCTAssertTrue(readQuest.contains("cancelListeningForBackground()"))
        XCTAssertTrue(
            readQuest.contains("guard !Task.isCancelled, !isPaused else")
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
