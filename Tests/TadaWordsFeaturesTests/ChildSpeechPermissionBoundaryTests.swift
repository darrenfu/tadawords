import XCTest

@testable import TadaWordsFeatures

final class ChildSpeechPermissionBoundaryTests: XCTestCase {
    func testMicrophoneTapResolvesAuthorizationExactlyOnce() async {
        let recorder = SpeechAuthorizationRecorder(result: true)
        let actions = SpeechPermissionActions(
            authorizeMicrophoneTap: {
                await recorder.authorize()
            }
        )

        let isAuthorized = await actions.authorizeMicrophoneTap()
        let authorizationCount = await recorder.authorizationCount

        XCTAssertTrue(isAuthorized)
        XCTAssertEqual(authorizationCount, 1)
    }

    func testUnavailableBoundaryFailsClosed() async {
        let isAuthorized =
            await SpeechPermissionActions.unavailable.authorizeMicrophoneTap()

        XCTAssertFalse(isAuthorized)
    }
}

private actor SpeechAuthorizationRecorder {
    private(set) var authorizationCount = 0
    private let result: Bool

    init(result: Bool) {
        self.result = result
    }

    func authorize() -> Bool {
        authorizationCount += 1
        return result
    }
}
