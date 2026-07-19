import TadaWordsDomain
import XCTest

final class FamilySyncRemoteNotificationBridgeTests: XCTestCase {
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
}

private actor FamilySyncNotificationRecorder {
    private(set) var invocationCount = 0

    func recordInvocation() {
        invocationCount += 1
    }
}
