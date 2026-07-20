import AVFoundation
import Speech
import TadaWordsDomain

public typealias ApplePermissionStatus = SpeechPermissionStatus
public typealias AppleSpeechPermissionState = SpeechPermissionState

public protocol AppleSpeechPermissionChecking: Sendable {
    func currentState() -> AppleSpeechPermissionState
}

struct AppleSpeechPermissionRequestPlan: Equatable {
    let requestsSpeechRecognition: Bool
    let requestsMicrophone: Bool

    init(
        requestsSpeechRecognition: Bool,
        requestsMicrophone: Bool
    ) {
        self.requestsSpeechRecognition = requestsSpeechRecognition
        self.requestsMicrophone = requestsMicrophone
    }

    init(state: AppleSpeechPermissionState) {
        self.init(
            requestsSpeechRecognition: state.speechRecognition == .notDetermined,
            requestsMicrophone: state.microphone == .notDetermined
        )
    }
}

public struct SystemAppleSpeechPermissionChecker: AppleSpeechPermissionChecking {
    public init() {}

    public func currentState() -> AppleSpeechPermissionState {
        AppleSpeechPermissionState(
            speechRecognition: ApplePermissionStatus(
                SFSpeechRecognizer.authorizationStatus()
            ),
            microphone: ApplePermissionStatus(
                AVCaptureDevice.authorizationStatus(for: .audio)
            )
        )
    }
}

/// The app calls this controller from an explicit guardian/user action.
/// Recognition services only inspect current authorization and never prompt.
public struct AppleSpeechPermissionController: Sendable {
    private let checker: any AppleSpeechPermissionChecking

    public init(
        checker: any AppleSpeechPermissionChecking = SystemAppleSpeechPermissionChecker()
    ) {
        self.checker = checker
    }

    public func currentState() -> AppleSpeechPermissionState {
        checker.currentState()
    }

    public func requestPermissions() async -> AppleSpeechPermissionState {
        let current = checker.currentState()
        let plan = AppleSpeechPermissionRequestPlan(state: current)

        if plan.requestsSpeechRecognition {
            _ = await requestSpeechRecognitionPermission()
        }
        if plan.requestsMicrophone {
            _ = await requestMicrophonePermission()
        }

        return checker.currentState()
    }

    private func requestSpeechRecognitionPermission() async -> ApplePermissionStatus {
        await withCheckedContinuation { continuation in
            SFSpeechRecognizer.requestAuthorization { status in
                continuation.resume(returning: ApplePermissionStatus(status))
            }
        }
    }

    private func requestMicrophonePermission() async -> ApplePermissionStatus {
        await withCheckedContinuation { continuation in
            AVCaptureDevice.requestAccess(for: .audio) { _ in
                continuation.resume(
                    returning: ApplePermissionStatus(
                        AVCaptureDevice.authorizationStatus(for: .audio)
                    )
                )
            }
        }
    }
}

extension ApplePermissionStatus {
    fileprivate init(_ status: SFSpeechRecognizerAuthorizationStatus) {
        switch status {
        case .notDetermined:
            self = .notDetermined
        case .restricted:
            self = .restricted
        case .denied:
            self = .denied
        case .authorized:
            self = .authorized
        @unknown default:
            self = .denied
        }
    }

    fileprivate init(_ status: AVAuthorizationStatus) {
        switch status {
        case .notDetermined:
            self = .notDetermined
        case .restricted:
            self = .restricted
        case .denied:
            self = .denied
        case .authorized:
            self = .authorized
        @unknown default:
            self = .denied
        }
    }
}
