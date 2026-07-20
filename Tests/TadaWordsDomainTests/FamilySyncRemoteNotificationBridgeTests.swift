import TadaWordsDomain
import XCTest

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
            register: { await recorder.recordRegistration() },
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
        let bridge = FamilySyncRemoteNotificationBridge(
            clock: RemoteNotificationFixedClock(now: now)
        )

        await bridge.requestRegistration()
        await bridge.recordRegistrationSucceeded()
        let registeredState = await bridge.registrationState()
        XCTAssertEqual(
            registeredState,
            .registered(at: now)
        )

        await bridge.requestRegistration()
        await bridge.recordRegistrationFailed(category: .configuration)
        let failedState = await bridge.registrationState()
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
            register: { await recorder.recordRegistration() },
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

    func testFreshBridgeDoesNotRestoreEarlierRegistrationState() async {
        let firstLaunch = FamilySyncRemoteNotificationBridge(
            clock: RemoteNotificationFixedClock(now: now)
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
        await bridge.requestRegistration()
        let states = await bridge.registrationStates()
        var iterator = states.makeAsyncIterator()

        let pendingState = await iterator.next()
        XCTAssertEqual(pendingState, .pending(since: now))

        await bridge.recordRegistrationSucceeded()
        await bridge.requestRegistration()
        await bridge.recordRegistrationFailed(category: .connectivity)
        let newestState = await iterator.next()
        XCTAssertEqual(
            newestState,
            .failed(category: .connectivity, at: now)
        )
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

private struct RemoteNotificationFixedClock: AppClock {
    let now: Date
}
