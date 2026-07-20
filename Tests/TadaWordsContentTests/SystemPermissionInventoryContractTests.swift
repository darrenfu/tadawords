import Foundation
import XCTest

final class SystemPermissionInventoryContractTests: XCTestCase {
    func testEveryUsageDescriptionIsCoveredByPermissionInventory() throws {
        let inventory = try permissionInventory()
        let expectedRowsByUsageKey = [
            "NSCameraUsageDescription": "| Camera |",
            "NSFaceIDUsageDescription": "| Device owner authentication / Face ID when available |",
            "NSMicrophoneUsageDescription": "| Microphone |",
            "NSPhotoLibraryUsageDescription": "| Photo Library |",
            "NSSpeechRecognitionUsageDescription": "| Speech Recognition |",
        ]

        for plistPath in [
            "Apps/TadaWordsApp/Info.plist",
            "Apps/TadaWordsApp/InfoLocalQA.plist",
        ] {
            let data = try Data(contentsOf: repositoryRoot.appendingPathComponent(plistPath))
            let propertyList = try XCTUnwrap(
                try PropertyListSerialization.propertyList(from: data, format: nil)
                    as? [String: Any]
            )
            let shippingUsageKeys = Set(
                propertyList.keys.filter { $0.hasPrefix("NS") && $0.hasSuffix("UsageDescription") }
            )

            XCTAssertEqual(shippingUsageKeys, Set(expectedRowsByUsageKey.keys))
            for usageKey in shippingUsageKeys {
                let row = try XCTUnwrap(expectedRowsByUsageKey[usageKey])
                XCTAssertTrue(inventory.contains(row), "Missing inventory row for \(usageKey)")
            }
        }
    }

    func testKnownShippingRequestSurfacesStayAtAuditedAdultOwnedSites() throws {
        let inventory = try permissionInventory()
        let shippingSources =
            try swiftSources(
                under: repositoryRoot.appendingPathComponent("Apps", isDirectory: true)
            )
            + swiftSources(
                under: repositoryRoot.appendingPathComponent("Sources", isDirectory: true)
            )
        let surfaces = [
            RequestSurface(
                sourceToken: "SFSpeechRecognizer.requestAuthorization",
                inventoryToken: "SFSpeechRecognizer.requestAuthorization",
                expectedPaths: ["Sources/TadaWordsApplePlatform/AppleSpeechPermissions.swift"]
            ),
            RequestSurface(
                sourceToken: "AVCaptureDevice.requestAccess(for: .audio)",
                inventoryToken: "AVCaptureDevice.requestAccess(for: .audio)",
                expectedPaths: ["Sources/TadaWordsApplePlatform/AppleSpeechPermissions.swift"]
            ),
            RequestSurface(
                sourceToken: "center.requestAuthorization(",
                inventoryToken: "UNUserNotificationCenter.requestAuthorization",
                expectedPaths: [
                    "Sources/TadaWordsApplePlatform/AppleLearningNotificationScheduler.swift"
                ]
            ),
            RequestSurface(
                sourceToken: "context.evaluatePolicy(",
                inventoryToken: "LAContext.evaluatePolicy(.deviceOwnerAuthentication)",
                expectedPaths: [
                    "Sources/TadaWordsApplePlatform/AppleSensitiveGuardianActionAuthorizer.swift"
                ]
            ),
            RequestSurface(
                sourceToken: "PhotosPicker(",
                inventoryToken: "PhotosPicker",
                expectedPaths: [
                    "Sources/TadaWordsGuardianFeatures/GuardianProfilesView.swift",
                    "Sources/TadaWordsGuardianFeatures/GuardianQuickAddView.swift",
                ]
            ),
            RequestSurface(
                sourceToken: "UIImagePickerController()",
                inventoryToken: "UIImagePickerController",
                expectedPaths: [
                    "Sources/TadaWordsGuardianFeatures/GuardianProfilesView.swift",
                    "Sources/TadaWordsGuardianFeatures/GuardianQuickAddView.swift",
                ]
            ),
            RequestSurface(
                sourceToken: "registerForRemoteNotifications()",
                inventoryToken: "registerForRemoteNotifications()",
                expectedPaths: ["Apps/TadaWordsApp/TadaWordsAppDelegate.swift"]
            ),
            RequestSurface(
                sourceToken: "UICloudSharingController(",
                inventoryToken: "CloudKit private/shared databases and share UI",
                expectedPaths: [
                    "Sources/TadaWordsApplePlatform/CloudKitFamilyAccessManager.swift"
                ]
            ),
        ]

        for surface in surfaces {
            let actualPaths = Set(
                try shippingSources.compactMap { url -> String? in
                    guard try source(url).contains(surface.sourceToken) else { return nil }
                    return relativePath(for: url)
                }
            )
            XCTAssertEqual(
                actualPaths,
                Set(surface.expectedPaths),
                "Unaudited shipping site for \(surface.sourceToken)"
            )
            XCTAssertTrue(
                inventory.contains(surface.inventoryToken),
                "Permission inventory omitted \(surface.inventoryToken)"
            )
            XCTAssertTrue(
                surface.expectedPaths.allSatisfy { !$0.contains("TadaWordsFeatures/") },
                "A child feature owns \(surface.sourceToken)"
            )
        }
    }

    func testInventoryLocksChildRoutesToCheckOnlyBehavior() throws {
        let inventory = try permissionInventory()
        let normalizedInventory =
            inventory
            .split(whereSeparator: \.isWhitespace)
            .joined(separator: " ")
        for route in [
            "App launch",
            "Profile selection or switch",
            "Read entry",
            "replay",
            "cold relaunch",
            "debug demo/deep-link fixture",
        ] {
            XCTAssertTrue(
                normalizedInventory.contains(route),
                "Missing negative child route: \(route)"
            )
        }

        for contract in [
            "cannot receive the Parents-only request closure",
            "`isAuthorized()` only",
            "one physical iPhone and one physical iPad",
        ] {
            XCTAssertTrue(
                normalizedInventory.contains(contract),
                "Missing release contract: \(contract)"
            )
        }
    }

    private struct RequestSurface {
        let sourceToken: String
        let inventoryToken: String
        let expectedPaths: [String]
    }

    private var repositoryRoot: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
    }

    private var permissionInventoryURL: URL {
        repositoryRoot.appendingPathComponent(
            "Docs/SYSTEM_PERMISSION_INVENTORY_v0.7.8.md"
        )
    }

    private func permissionInventory() throws -> String {
        try source(permissionInventoryURL)
    }

    private func swiftSources(under directory: URL) throws -> [URL] {
        let enumerator = try XCTUnwrap(
            FileManager.default.enumerator(
                at: directory,
                includingPropertiesForKeys: [.isRegularFileKey]
            )
        )
        return enumerator.compactMap { element -> URL? in
            guard let url = element as? URL, url.pathExtension == "swift" else { return nil }
            return url
        }
        .sorted { $0.path < $1.path }
    }

    private func relativePath(for url: URL) -> String {
        let prefix = repositoryRoot.path + "/"
        return url.path.hasPrefix(prefix) ? String(url.path.dropFirst(prefix.count)) : url.path
    }

    private func source(_ url: URL) throws -> String {
        try String(contentsOf: url, encoding: .utf8)
    }
}
