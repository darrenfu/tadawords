import TadaWordsDomain
import XCTest

@testable import TadaWordsGuardianFeatures

final class GuardianSpeechPermissionTests: XCTestCase {
    func testPresentationDistinguishesFreshDeniedRestrictedAndReadyStates() {
        XCTAssertEqual(
            GuardianSpeechPermissionPresentation.tileSummary(
                for: state(.notDetermined, .notDetermined)
            ),
            "Parent setup needed"
        )
        XCTAssertEqual(
            GuardianSpeechPermissionPresentation.tileSummary(
                for: state(.denied, .authorized)
            ),
            "Check iOS Settings"
        )
        XCTAssertEqual(
            GuardianSpeechPermissionPresentation.tileSummary(
                for: state(.restricted, .notDetermined)
            ),
            "Finish setup; check iOS Settings"
        )
        XCTAssertEqual(
            GuardianSpeechPermissionPresentation.tileSummary(
                for: state(.authorized, .authorized)
            ),
            "Ready for Read Practice"
        )
    }

    @MainActor
    func testOpeningParentSetupReadsStatusWithoutRequestingPermission() async {
        let recorder = GuardianSpeechPermissionRecorder(
            current: state(.notDetermined, .notDetermined),
            requested: state(.authorized, .authorized)
        )
        let model = makeModel(recorder: recorder)

        await model.refreshSpeechPermissionStateAndWait()

        let counts = await recorder.counts()
        XCTAssertEqual(model.speechPermissionState, state(.notDetermined, .notDetermined))
        XCTAssertEqual(counts.checks, 1)
        XCTAssertEqual(counts.requests, 0)
    }

    @MainActor
    func testOnlyExplicitParentSetupRequestsAndPublishesBothStatuses() async {
        let recorder = GuardianSpeechPermissionRecorder(
            current: state(.notDetermined, .notDetermined),
            requested: state(.authorized, .denied)
        )
        let model = makeModel(recorder: recorder)

        await model.setUpSpeechPermissionsAndWait()

        let counts = await recorder.counts()
        XCTAssertEqual(model.speechPermissionState, state(.authorized, .denied))
        XCTAssertFalse(model.isRequestingSpeechPermissions)
        XCTAssertEqual(counts.checks, 0)
        XCTAssertEqual(counts.requests, 1)
    }

    @MainActor
    func testSpeechPermissionRouteReturnsToAppAndFamily() {
        let model = makeModel(
            recorder: GuardianSpeechPermissionRecorder(
                current: .unavailable,
                requested: .unavailable
            )
        )

        model.showSpeechPermissions()
        XCTAssertEqual(model.transitionKey, "speech-permissions")
        model.returnToParentSection()
        XCTAssertEqual(model.transitionKey, "parent-section-appAndFamily")
    }

    @MainActor
    private func makeModel(
        recorder: GuardianSpeechPermissionRecorder
    ) -> GuardianDashboardViewModel {
        GuardianDashboardViewModel(
            store: DemoGuardianFamilyStore(),
            audioPromptService: GuardianSpeechPermissionAudioStub(),
            currentSpeechPermissionState: {
                await recorder.currentState()
            },
            requestSpeechPermissions: {
                await recorder.request()
            }
        )
    }

    private func state(
        _ speech: SpeechPermissionStatus,
        _ microphone: SpeechPermissionStatus
    ) -> SpeechPermissionState {
        SpeechPermissionState(
            speechRecognition: speech,
            microphone: microphone
        )
    }
}

private actor GuardianSpeechPermissionRecorder {
    private let current: SpeechPermissionState
    private let requested: SpeechPermissionState
    private var checkCount = 0
    private var requestCount = 0

    init(
        current: SpeechPermissionState,
        requested: SpeechPermissionState
    ) {
        self.current = current
        self.requested = requested
    }

    func currentState() -> SpeechPermissionState {
        checkCount += 1
        return current
    }

    func request() -> SpeechPermissionState {
        requestCount += 1
        return requested
    }

    func counts() -> (checks: Int, requests: Int) {
        (checkCount, requestCount)
    }
}

private struct GuardianSpeechPermissionAudioStub: AudioPromptService {
    func play(_ prompt: WordPrompt, for profileID: ProfileID) async throws {
        _ = prompt
        _ = profileID
    }
}
