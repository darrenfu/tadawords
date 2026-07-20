public enum SpeechPermissionStatus: String, Codable, Equatable, Sendable {
    case notDetermined
    case restricted
    case denied
    case authorized
}

public struct SpeechPermissionState: Equatable, Sendable {
    public let speechRecognition: SpeechPermissionStatus
    public let microphone: SpeechPermissionStatus

    public init(
        speechRecognition: SpeechPermissionStatus,
        microphone: SpeechPermissionStatus
    ) {
        self.speechRecognition = speechRecognition
        self.microphone = microphone
    }

    public var isAuthorized: Bool {
        speechRecognition == .authorized && microphone == .authorized
    }

    public var hasUndeterminedPermission: Bool {
        speechRecognition == .notDetermined || microphone == .notDetermined
    }

    public var hasDeniedOrRestrictedPermission: Bool {
        switch (speechRecognition, microphone) {
        case (.denied, _), (.restricted, _), (_, .denied), (_, .restricted):
            true
        default:
            false
        }
    }

    public static let unavailable = SpeechPermissionState(
        speechRecognition: .restricted,
        microphone: .restricted
    )
}
