import XCTest

@testable import TadaWordsFeatures

final class ChildSpeechPermissionBoundaryTests: XCTestCase {
    func testChildBoundaryOnlyChecksExistingAuthorization() async {
        let recorder = SpeechAuthorizationCheckRecorder(result: true)
        let actions = SpeechPermissionActions {
            await recorder.check()
        }

        let isAuthorized = await actions.isAuthorized()
        let checkCount = await recorder.checkCount

        XCTAssertTrue(isAuthorized)
        XCTAssertEqual(checkCount, 1)
    }

    func testUnavailableBoundaryFailsClosedWithoutAnAuthorizationRequestCapability() async {
        let isAuthorized = await SpeechPermissionActions.unavailable.isAuthorized()

        XCTAssertFalse(isAuthorized)
    }
}

private actor SpeechAuthorizationCheckRecorder {
    private(set) var checkCount = 0
    private let result: Bool

    init(result: Bool) {
        self.result = result
    }

    func check() -> Bool {
        checkCount += 1
        return result
    }
}
