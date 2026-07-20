import XCTest

@testable import TadaWordsDomain

final class FamilySyncRemoteNotificationBridgeTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_735_689_600)

    func testRegisteredHandlerRunsForShareManagementReconciliation() async {
        let bridge = FamilySyncRemoteNotificationBridge()
        let recorder = FamilySyncNotificationRecorder()
        await bridge.register {
            await recorder.recordInvocation()
            return .newData
        }

        let result = await bridge.handleNotification()

        guard case .newData = result else {
            return XCTFail("A registered reconciliation must return its handler result.")
        }
        let invocationCount = await recorder.invocationCount
        XCTAssertEqual(invocationCount, 1)
    }

    func testNotificationArrivingBeforeBootstrapResumesAfterRegistration() async {
        let bridge = FamilySyncRemoteNotificationBridge()
        let pendingResult = Task {
            await bridge.handleNotification()
        }
        await Task.yield()

        await bridge.register { .noData }

        guard case .noData = await pendingResult.value else {
            return XCTFail("A pre-bootstrap notification must use the later handler.")
        }
    }

    func testRegistrationRequestPublishesBoundedPendingState() async {
        let bridge = FamilySyncRemoteNotificationBridge(
            clock: RemoteNotificationFixedClock(now: now)
        )
        let recorder = RemoteNotificationRegistrationRecorder()
        await bridge.configureRegistration(
            register: { attempt in
                guard attempt.isCurrent else { return false }
                await recorder.recordRegistration()
                return true
            },
            unregister: { await recorder.recordUnregistration() }
        )

        await bridge.requestRegistration()

        let state = await bridge.registrationState()
        XCTAssertEqual(
            state,
            .pending(since: now)
        )
        let registrationCount = await recorder.registrationCount
        let unregistrationCount = await recorder.unregistrationCount
        XCTAssertEqual(registrationCount, 1)
        XCTAssertEqual(unregistrationCount, 0)
    }

    func testRegistrationCallbacksPublishSuccessAndCoarseFailureOnly() async {
        let successfulBridge = FamilySyncRemoteNotificationBridge(
            clock: RemoteNotificationFixedClock(now: now)
        )
        await successfulBridge.configureRegistration(
            register: { _ in true },
            unregister: {}
        )

        await successfulBridge.requestRegistration()
        await successfulBridge.recordRegistrationSucceeded()
        let registeredState = await successfulBridge.registrationState()
        XCTAssertEqual(
            registeredState,
            .registered(at: now)
        )

        let failedBridge = FamilySyncRemoteNotificationBridge(
            clock: RemoteNotificationFixedClock(now: now)
        )
        await failedBridge.configureRegistration(
            register: { _ in true },
            unregister: {}
        )
        await failedBridge.requestRegistration()
        await failedBridge.recordRegistrationFailed(category: .configuration)
        let failedState = await failedBridge.registrationState()
        XCTAssertEqual(
            failedState,
            .failed(category: .configuration, at: now)
        )
    }

    func testRetryAfterFailureReturnsToPendingAndInvokesRegistrationAgain() async {
        let bridge = FamilySyncRemoteNotificationBridge(
            clock: RemoteNotificationFixedClock(now: now)
        )
        let recorder = RemoteNotificationRegistrationRecorder()
        await bridge.configureRegistration(
            register: { attempt in
                guard attempt.isCurrent else { return false }
                await recorder.recordRegistration()
                return true
            },
            unregister: {}
        )
        await bridge.requestRegistration()
        await bridge.recordRegistrationFailed(category: .connectivity)

        await bridge.requestRegistration()

        let state = await bridge.registrationState()
        XCTAssertEqual(
            state,
            .pending(since: now)
        )
        let registrationCount = await recorder.registrationCount
        XCTAssertEqual(registrationCount, 2)
    }

    func testStaleRetryAfterOptOutCannotRestoreRegistration() async {
        let bridge = FamilySyncRemoteNotificationBridge(
            clock: RemoteNotificationFixedClock(now: now)
        )
        let recorder = RemoteNotificationRegistrationRecorder()
        await bridge.configureRegistration(
            register: { attempt in
                guard attempt.isCurrent else { return false }
                await recorder.recordRegistration()
                return true
            },
            unregister: { await recorder.recordUnregistration() }
        )
        await bridge.requestRegistration()
        await bridge.recordRegistrationFailed(category: .connectivity)

        await bridge.requestUnregistration()
        await bridge.retryRegistrationIfRequested()

        let state = await bridge.registrationState()
        let registrationCount = await recorder.registrationCount
        let unregistrationCount = await recorder.unregistrationCount
        XCTAssertEqual(state, .notRequested)
        XCTAssertEqual(registrationCount, 1)
        XCTAssertEqual(unregistrationCount, 1)
    }

    func testUnregistrationMakesLateCallbacksInert() async {
        let bridge = FamilySyncRemoteNotificationBridge(
            clock: RemoteNotificationFixedClock(now: now)
        )
        await bridge.requestRegistration()

        await bridge.requestUnregistration()
        await bridge.recordRegistrationSucceeded()
        await bridge.recordRegistrationFailed(category: .system)

        let state = await bridge.registrationState()
        XCTAssertEqual(state, .notRequested)
    }

    func testConfigureAndOptOutSerializeRegisterBeforeUnregister() async {
        let bridge = FamilySyncRemoteNotificationBridge(
            clock: RemoteNotificationFixedClock(now: now)
        )
        let harness = RemoteNotificationRegistrationInterleavingHarness()
        await bridge.requestRegistration()

        let configuration = Task {
            await bridge.configureRegistration(
                register: { attempt in
                    guard attempt.isCurrent else { return false }
                    await harness.register()
                    return true
                },
                unregister: { await harness.unregister() }
            )
        }
        await harness.waitUntilRegistrationStarts()

        let optOut = Task {
            await bridge.requestUnregistration()
        }
        var observedOptOutIntent = false
        for _ in 0..<100 {
            if await bridge.registrationState() == .notRequested {
                observedOptOutIntent = true
                break
            }
            await Task.yield()
        }

        XCTAssertTrue(observedOptOutIntent)
        let eventsWhileRegistrationIsBlocked = await harness.events
        XCTAssertEqual(eventsWhileRegistrationIsBlocked, ["register-started"])

        await harness.finishRegistration()
        await configuration.value
        await optOut.value

        let finalEvents = await harness.events
        XCTAssertEqual(
            finalEvents,
            ["register-started", "register-finished", "unregister"]
        )
    }

    func testOptOutInvalidatesRegistrationBeforeSuspendedHandlerResumes() async {
        let bridge = FamilySyncRemoteNotificationBridge(
            clock: RemoteNotificationFixedClock(now: now)
        )
        let harness = RemoteNotificationStaleRegistrationHarness()
        await bridge.requestRegistration()

        let configuration = Task {
            await bridge.configureRegistration(
                register: { attempt in
                    await harness.register(attempt: attempt)
                },
                unregister: { await harness.unregister() }
            )
        }
        await harness.waitUntilRegistrationHandlerStarts()

        let optOut = Task {
            await bridge.requestUnregistration()
        }
        await waitForRegistrationState(.notRequested, on: bridge)

        await harness.resumeRegistrationHandler()
        await configuration.value
        await optOut.value

        let events = await harness.events
        XCTAssertEqual(
            events,
            ["registration-handler-started", "unregister"],
            "A handler suspended before its platform call must observe that its attempt was invalidated."
        )
    }

    func testCancelledPendingAttemptCannotOverwriteReplacementRequest() async {
        let bridge = FamilySyncRemoteNotificationBridge(
            clock: RemoteNotificationFixedClock(now: now)
        )
        await bridge.configureRegistration(
            register: { _ in true },
            unregister: {}
        )

        await bridge.requestRegistration()
        await bridge.requestUnregistration()
        await bridge.requestRegistration()

        let replacementInitialState = await bridge.registrationState()
        XCTAssertEqual(
            replacementInitialState,
            .unverified(at: now)
        )

        // UIKit gives this callback no request identifier. It could belong to
        // the cancelled request, so it must not be credited to its replacement.
        await bridge.recordRegistrationSucceeded()
        let stateAfterUnattributedCallbacks = await bridge.registrationState()
        XCTAssertEqual(
            stateAfterUnattributedCallbacks,
            .unverified(at: now)
        )
    }

    func testReplacementAttemptAcceptsItsCallbackAfterLateCancelledCallback() async {
        let bridge = FamilySyncRemoteNotificationBridge(
            clock: RemoteNotificationFixedClock(now: now)
        )
        await bridge.configureRegistration(
            register: { _ in true },
            unregister: {}
        )

        await bridge.requestRegistration()
        await bridge.requestUnregistration()
        await bridge.requestRegistration()

        // The first callback belongs to the cancelled attempt and must be
        // consumed without changing the replacement attempt.
        await bridge.recordRegistrationSucceeded()
        let stateAfterCancelledCallback = await bridge.registrationState()
        XCTAssertEqual(
            stateAfterCancelledCallback,
            .unverified(at: now)
        )

        // Once the stale generation is drained, the callback for the current
        // generation must be allowed to complete registration.
        await bridge.recordRegistrationSucceeded()
        let stateAfterReplacementCallback = await bridge.registrationState()
        XCTAssertEqual(
            stateAfterReplacementCallback,
            .registered(at: now)
        )
    }

    func testFreshBridgeDoesNotRestoreEarlierRegistrationState() async {
        let firstLaunch = FamilySyncRemoteNotificationBridge(
            clock: RemoteNotificationFixedClock(now: now)
        )
        await firstLaunch.configureRegistration(
            register: { _ in true },
            unregister: {}
        )
        await firstLaunch.requestRegistration()
        await firstLaunch.recordRegistrationSucceeded()

        let relaunched = FamilySyncRemoteNotificationBridge(
            clock: RemoteNotificationFixedClock(now: now)
        )

        let initialState = await relaunched.registrationState()
        XCTAssertEqual(initialState, .notRequested)
        await relaunched.requestRegistration()
        let pendingState = await relaunched.registrationState()
        XCTAssertEqual(
            pendingState,
            .pending(since: now)
        )
    }

    func testRegistrationStateStreamReplaysLatestStateAndBuffersOnlyNewestUpdate()
        async
    {
        let bridge = FamilySyncRemoteNotificationBridge(
            clock: RemoteNotificationFixedClock(now: now)
        )
        await bridge.configureRegistration(
            register: { _ in true },
            unregister: {}
        )
        await bridge.requestRegistration()
        let states = await bridge.registrationStates()
        var iterator = states.makeAsyncIterator()

        let pendingState = await iterator.next()
        XCTAssertEqual(pendingState, .pending(since: now))

        await bridge.recordRegistrationSucceeded()
        await bridge.requestUnregistration()
        await bridge.requestRegistration()
        await bridge.recordRegistrationFailed(category: .connectivity)
        let newestState = await iterator.next()
        XCTAssertEqual(
            newestState,
            .failed(category: .connectivity, at: now)
        )
    }
}

extension FamilySyncRemoteNotificationBridgeTests {
    fileprivate func waitForRegistrationState(
        _ expected: FamilySyncRemoteNotificationRegistrationState,
        on bridge: FamilySyncRemoteNotificationBridge
    ) async {
        for _ in 0..<100 {
            if await bridge.registrationState() == expected {
                return
            }
            await Task.yield()
        }
        XCTFail("Timed out waiting for registration state \(expected).")
    }
}

private actor FamilySyncNotificationRecorder {
    private(set) var invocationCount = 0

    func recordInvocation() {
        invocationCount += 1
    }
}

private actor RemoteNotificationRegistrationRecorder {
    private(set) var registrationCount = 0
    private(set) var unregistrationCount = 0

    func recordRegistration() {
        registrationCount += 1
    }

    func recordUnregistration() {
        unregistrationCount += 1
    }
}

private actor RemoteNotificationRegistrationInterleavingHarness {
    private(set) var events: [String] = []
    private var registrationStartWaiters: [CheckedContinuation<Void, Never>] = []
    private var registrationRelease: CheckedContinuation<Void, Never>?

    func register() async {
        events.append("register-started")
        let waiters = registrationStartWaiters
        registrationStartWaiters.removeAll()
        for waiter in waiters {
            waiter.resume()
        }
        await withCheckedContinuation { continuation in
            registrationRelease = continuation
        }
        events.append("register-finished")
    }

    func unregister() {
        events.append("unregister")
    }

    func waitUntilRegistrationStarts() async {
        guard !events.contains("register-started") else { return }
        await withCheckedContinuation { continuation in
            registrationStartWaiters.append(continuation)
        }
    }

    func finishRegistration() {
        registrationRelease?.resume()
        registrationRelease = nil
    }
}

private actor RemoteNotificationStaleRegistrationHarness {
    private(set) var events: [String] = []
    private var startWaiters: [CheckedContinuation<Void, Never>] = []
    private var registrationRelease: CheckedContinuation<Void, Never>?

    func register(
        attempt: FamilySyncRemoteNotificationRegistrationAttempt
    ) async -> Bool {
        events.append("registration-handler-started")
        let waiters = startWaiters
        startWaiters.removeAll()
        for waiter in waiters {
            waiter.resume()
        }
        await withCheckedContinuation { continuation in
            registrationRelease = continuation
        }
        guard attempt.isCurrent else { return false }
        events.append("register")
        return true
    }

    func unregister() {
        events.append("unregister")
    }

    func waitUntilRegistrationHandlerStarts() async {
        guard !events.contains("registration-handler-started") else { return }
        await withCheckedContinuation { continuation in
            startWaiters.append(continuation)
        }
    }

    func resumeRegistrationHandler() {
        registrationRelease?.resume()
        registrationRelease = nil
    }
}

private struct RemoteNotificationFixedClock: AppClock {
    let now: Date
}
