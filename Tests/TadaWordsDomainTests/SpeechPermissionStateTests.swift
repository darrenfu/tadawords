import TadaWordsDomain
import XCTest

final class SpeechPermissionStateTests: XCTestCase {
    func testAuthorizationRequiresSpeechAndMicrophoneTogether() {
        XCTAssertTrue(
            SpeechPermissionState(
                speechRecognition: .authorized,
                microphone: .authorized
            ).isAuthorized
        )
        XCTAssertFalse(
            SpeechPermissionState(
                speechRecognition: .authorized,
                microphone: .notDetermined
            ).isAuthorized
        )
        XCTAssertFalse(
            SpeechPermissionState(
                speechRecognition: .denied,
                microphone: .authorized
            ).isAuthorized
        )
    }

    func testSetupFlagsSeparatePromptableFromSettingsOnlyStates() {
        let fresh = SpeechPermissionState(
            speechRecognition: .notDetermined,
            microphone: .notDetermined
        )
        let mixed = SpeechPermissionState(
            speechRecognition: .denied,
            microphone: .notDetermined
        )
        let ready = SpeechPermissionState(
            speechRecognition: .authorized,
            microphone: .authorized
        )

        XCTAssertTrue(fresh.hasUndeterminedPermission)
        XCTAssertFalse(fresh.hasDeniedOrRestrictedPermission)
        XCTAssertTrue(mixed.hasUndeterminedPermission)
        XCTAssertTrue(mixed.hasDeniedOrRestrictedPermission)
        XCTAssertFalse(ready.hasUndeterminedPermission)
        XCTAssertFalse(ready.hasDeniedOrRestrictedPermission)
    }
}
