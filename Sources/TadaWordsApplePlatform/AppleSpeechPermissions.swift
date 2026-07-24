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

/// Serializes Speech Recognition and Microphone prompts for both the contextual
/// Read action and the optional guardian setup route.
public actor AppleSpeechPermissionController {
    private let checker: any AppleSpeechPermissionChecking
    private let speechRecognitionRequest: @Sendable () async -> ApplePermissionStatus
    private let microphoneRequest: @Sendable () async -> ApplePermissionStatus
    private var isRequesting = false

    public init(
        checker: any AppleSpeechPermissionChecking = SystemAppleSpeechPermissionChecker()
    ) {
        self.checker = checker
        speechRecognitionRequest = Self.requestSpeechRecognitionPermission
        microphoneRequest = Self.requestMicrophonePermission
    }

    init(
        checker: any AppleSpeechPermissionChecking,
        speechRecognitionRequest:
            @escaping @Sendable () async -> ApplePermissionStatus,
        microphoneRequest:
            @escaping @Sendable () async -> ApplePermissionStatus
    ) {
        self.checker = checker
        self.speechRecognitionRequest = speechRecognitionRequest
        self.microphoneRequest = microphoneRequest
    }

    public func currentState() -> AppleSpeechPermissionState {
        checker.currentState()
    }

    public func requestPermissions() async -> AppleSpeechPermissionState {
        let current = checker.currentState()
        guard !Task.isCancelled else { return current }

        // Swift actors are reentrant across awaits. Keep an explicit in-flight
        // gate so a rapid child tap or simultaneous guardian action cannot
        // create overlapping Apple prompts.
        guard !isRequesting else { return current }
        isRequesting = true
        defer { isRequesting = false }

        let plan = AppleSpeechPermissionRequestPlan(state: current)

        if plan.requestsSpeechRecognition {
            _ = await speechRecognitionRequest()
        }
        // A navigation/background cancellation cannot dismiss an Apple dialog
        // already on screen, but it must prevent the next dialog in the
        // sequence and any stale recording continuation.
        guard !Task.isCancelled else { return checker.currentState() }
        if plan.requestsMicrophone {
            _ = await microphoneRequest()
        }

        return checker.currentState()
    }

    private static func requestSpeechRecognitionPermission() async -> ApplePermissionStatus {
        await withCheckedContinuation { continuation in
            SFSpeechRecognizer.requestAuthorization { status in
                continuation.resume(returning: ApplePermissionStatus(status))
            }
        }
    }

    private static func requestMicrophonePermission() async -> ApplePermissionStatus {
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
