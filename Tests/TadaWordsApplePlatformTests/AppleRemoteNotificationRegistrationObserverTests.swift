import Darwin
import Foundation
import TadaWordsDomain
import XCTest

@testable import TadaWordsApplePlatform

final class AppleRemoteNotificationRegistrationObserverTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_735_689_600)

    @MainActor
    func testSuccessfulCallbackRoutesWithoutAcceptingDeviceToken() async {
        let bridge = FamilySyncRemoteNotificationBridge(
            clock: AppleRemoteNotificationFixedClock(now: now)
        )
        let observer = AppleRemoteNotificationRegistrationObserver(bridge: bridge)
        await configureRegistration(bridge: bridge, observer: observer)
        await bridge.requestRegistration()

        observer.enqueueDidRegister()
        await observer.finishPendingCallbacks()

        let state = await bridge.registrationState()
        XCTAssertEqual(
            state,
            .registered(at: now)
        )
    }

    @MainActor
    func testFailureCallbackRoutesOnlyCoarseCategory() async {
        let bridge = FamilySyncRemoteNotificationBridge(
            clock: AppleRemoteNotificationFixedClock(now: now)
        )
        let observer = AppleRemoteNotificationRegistrationObserver(bridge: bridge)
        await configureRegistration(bridge: bridge, observer: observer)
        await bridge.requestRegistration()

        observer.enqueueDidFail(
            error: NSError(
                domain: NSCocoaErrorDomain,
                code: 3_000,
                userInfo: [
                    NSLocalizedDescriptionKey:
                        "sensitive-device-or-account-specific-debug-text"
                ]
            )
        )
        await observer.finishPendingCallbacks()

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
                    domain: NSPOSIXErrorDomain,
                    code: Int(ENETUNREACH),
                    userInfo: nil
                )
            ),
            .connectivity
        )
        for nonNetworkCode in [EACCES, EINVAL] {
            XCTAssertEqual(
                AppleRemoteNotificationRegistrationObserver.failureCategory(
                    for: NSError(
                        domain: NSPOSIXErrorDomain,
                        code: Int(nonNetworkCode),
                        userInfo: nil
                    )
                ),
                .system
            )
        }
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

    @MainActor
    func testCallbackIngressPreservesFirstTerminalResult() async {
        let bridge = FamilySyncRemoteNotificationBridge(
            clock: AppleRemoteNotificationFixedClock(now: now)
        )
        let observer = AppleRemoteNotificationRegistrationObserver(bridge: bridge)
        await configureRegistration(bridge: bridge, observer: observer)
        await bridge.requestRegistration()

        observer.enqueueDidFail(category: .connectivity)
        observer.enqueueDidRegister()
        await observer.finishPendingCallbacks()

        let callbackState = await bridge.registrationState()
        XCTAssertEqual(
            callbackState,
            .failed(category: .connectivity, at: now)
        )
    }

    @MainActor
    func testCancelledStartedAttemptKeepsCallbacksUnverifiedAfterSuccessThenFailure()
        async
    {
        let bridge = FamilySyncRemoteNotificationBridge(
            clock: AppleRemoteNotificationFixedClock(now: now)
        )
        let observer = AppleRemoteNotificationRegistrationObserver(bridge: bridge)
        await configureRegistration(bridge: bridge, observer: observer)

        await bridge.requestRegistration()
        await bridge.requestUnregistration()
        await bridge.requestRegistration()

        observer.enqueueDidRegister()
        observer.enqueueDidFail(category: .connectivity)
        await observer.finishPendingCallbacks()

        let callbackState = await bridge.registrationState()
        XCTAssertEqual(
            callbackState,
            .unverified(at: now)
        )
    }

    @MainActor
    func testCancelledStartedAttemptKeepsCallbacksUnverifiedAfterFailureThenSuccess()
        async
    {
        let bridge = FamilySyncRemoteNotificationBridge(
            clock: AppleRemoteNotificationFixedClock(now: now)
        )
        let observer = AppleRemoteNotificationRegistrationObserver(bridge: bridge)
        await configureRegistration(bridge: bridge, observer: observer)

        await bridge.requestRegistration()
        await bridge.requestUnregistration()
        await bridge.requestRegistration()

        observer.enqueueDidFail(category: .connectivity)
        observer.enqueueDidRegister()
        await observer.finishPendingCallbacks()

        let callbackState = await bridge.registrationState()
        XCTAssertEqual(
            callbackState,
            .unverified(at: now)
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
        XCTAssertTrue(
            delegateSource.contains(
                "remoteNotificationRegistrationObserver.enqueueDidRegister()"
            )
        )
        XCTAssertTrue(
            delegateSource.contains(
                "remoteNotificationRegistrationObserver.enqueueDidFail(category: category)"
            )
        )
        XCTAssertFalse(delegateSource.contains("deviceToken"))
        XCTAssertFalse(delegateSource.contains("token.map"))
        XCTAssertFalse(delegateSource.contains("token.base64EncodedString"))
    }
}

@MainActor
private func configureRegistration(
    bridge: FamilySyncRemoteNotificationBridge,
    observer: AppleRemoteNotificationRegistrationObserver
) async {
    await bridge.configureRegistration(
        register: { attempt in
            await MainActor.run {
                guard attempt.isCurrent else { return false }
                observer.registrationDidStart(attempt)
                return true
            }
        },
        unregister: {}
    )
}

private struct AppleRemoteNotificationFixedClock: AppClock {
    let now: Date
}
