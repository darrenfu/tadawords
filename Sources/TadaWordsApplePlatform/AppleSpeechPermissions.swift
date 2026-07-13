import AVFoundation
import Speech

public enum ApplePermissionStatus: String, Equatable, Sendable {
    case notDetermined
    case restricted
    case denied
    case authorized
}

public struct AppleSpeechPermissionState: Equatable, Sendable {
    public let speechRecognition: ApplePermissionStatus
    public let microphone: ApplePermissionStatus

    public init(
        speechRecognition: ApplePermissionStatus,
        microphone: ApplePermissionStatus
    ) {
        self.speechRecognition = speechRecognition
        self.microphone = microphone
    }

    public var isAuthorized: Bool {
        speechRecognition == .authorized && microphone == .authorized
    }
}

public protocol AppleSpeechPermissionChecking: Sendable {
    func currentState() -> AppleSpeechPermissionState
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

        if current.speechRecognition == .notDetermined {
            _ = await requestSpeechRecognitionPermission()
        }
        if current.microphone == .notDetermined {
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
