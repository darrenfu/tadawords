import Foundation
import TadaWordsDomain
import XCTest

@testable import TadaWordsApplePlatform

final class AppleRemoteNotificationRegistrationObserverTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_735_689_600)

    func testSuccessfulCallbackRoutesWithoutAcceptingDeviceToken() async {
        let bridge = FamilySyncRemoteNotificationBridge(
            clock: AppleRemoteNotificationFixedClock(now: now)
        )
        let observer = AppleRemoteNotificationRegistrationObserver(bridge: bridge)
        await bridge.requestRegistration()

        await observer.didRegister()

        let state = await bridge.registrationState()
        XCTAssertEqual(
            state,
            .registered(at: now)
        )
    }

    func testFailureCallbackRoutesOnlyCoarseCategory() async {
        let bridge = FamilySyncRemoteNotificationBridge(
            clock: AppleRemoteNotificationFixedClock(now: now)
        )
        let observer = AppleRemoteNotificationRegistrationObserver(bridge: bridge)
        await bridge.requestRegistration()

        await observer.didFail(
            error: NSError(
                domain: NSCocoaErrorDomain,
                code: 3_000,
                userInfo: [
                    NSLocalizedDescriptionKey:
                        "sensitive-device-or-account-specific-debug-text"
                ]
            )
        )

        let state = await bridge.registrationState()
        XCTAssertEqual(
            state,
            .failed(category: .configuration, at: now)
        )
    }

    func testFailureClassifierDoesNotExposeErrorDomainCodeOrDescription() {
        XCTAssertEqual(
            AppleRemoteNotificationRegistrationObserver.failureCategory(
                for: NSError(
                    domain: NSURLErrorDomain,
                    code: NSURLErrorNotConnectedToInternet,
                    userInfo: nil
                )
            ),
            .connectivity
        )
        XCTAssertEqual(
            AppleRemoteNotificationRegistrationObserver.failureCategory(
                for: NSError(
                    domain: "private.example.error",
                    code: 42,
                    userInfo: [NSLocalizedDescriptionKey: "private details"]
                )
            ),
            .system
        )
    }

    func testAppDelegateDropsTokenAtCallbackBoundary() throws {
        let repositoryRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let delegateSource = try String(
            contentsOf: repositoryRoot.appendingPathComponent(
                "Apps/TadaWordsApp/TadaWordsAppDelegate.swift"
            ),
            encoding: .utf8
        )

        XCTAssertTrue(
            delegateSource.contains(
                "didRegisterForRemoteNotificationsWithDeviceToken _: Data"
            )
        )
        XCTAssertTrue(
            delegateSource.contains(
                "didFailToRegisterForRemoteNotificationsWithError error: Error"
            )
        )
        XCTAssertFalse(delegateSource.contains("deviceToken"))
        XCTAssertFalse(delegateSource.contains("token.map"))
        XCTAssertFalse(delegateSource.contains("token.base64EncodedString"))
    }
}

private struct AppleRemoteNotificationFixedClock: AppClock {
    let now: Date
}
