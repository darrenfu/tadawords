import TadaWordsDomain

public struct SpeechPermissionActions: Sendable {
    private let microphoneTapAuthorization: @Sendable () async -> Bool

    public init(
        authorizeMicrophoneTap: @escaping @Sendable () async -> Bool
    ) {
        microphoneTapAuthorization = authorizeMicrophoneTap
    }

    /// Resolves the original microphone tap. Production composition checks
    /// current status, requests only still-undetermined permissions, and
    /// returns true only when recording may start.
    public func authorizeMicrophoneTap() async -> Bool {
        await microphoneTapAuthorization()
    }

    public static let unavailable = SpeechPermissionActions(
        authorizeMicrophoneTap: {
            false
        }
    )

    static let demoAuthorized = SpeechPermissionActions(
        authorizeMicrophoneTap: {
            true
        }
    )
}

struct UnavailableSpeechRecognitionService: SpeechRecognitionService {
    func recognize(_ request: SpeechRecognitionRequest) async throws -> RecognitionResult {
        _ = request
        return RecognitionResult(
            decision: .technicalFailure(.serviceUnavailable)
        )
    }
}

struct UnavailableHandwritingRecognitionService: HandwritingRecognitionService {
    func recognize(
        sample: HandwritingSample,
        prompt: WordPrompt,
        for profileID: ProfileID
    ) async throws -> RecognitionResult {
        _ = sample
        _ = prompt
        _ = profileID
        return RecognitionResult(
            decision: .technicalFailure(.serviceUnavailable)
        )
    }
}

/// Preview and explicitly selected demo fixtures exercise the real quest UI
/// without inventing production learning evidence. Release app composition
/// cannot enter demo mode, so ordinary family sessions never select this
/// deterministic adapter.
struct DemoSpeechRecognitionService: SpeechRecognitionService {
    static let defaultDelay: Duration = .milliseconds(1_500)

    private let delay: Duration
    private let wait: @Sendable (Duration) async throws -> Void

    init(
        delay: Duration = Self.defaultDelay,
        wait: @escaping @Sendable (Duration) async throws -> Void = {
            try await Task.sleep(for: $0)
        }
    ) {
        self.delay = delay
        self.wait = wait
    }

    func recognize(
        _ request: SpeechRecognitionRequest
    ) async throws -> RecognitionResult {
        try Task.checkCancellation()
        try await wait(delay)
        try Task.checkCancellation()

        return RecognitionResult(
            decision: .matched,
            recognizedText: request.prompt.normalizedText,
            confidence: RecognitionConfidence(1)
        )
    }
}

struct DemoHandwritingRecognitionService: HandwritingRecognitionService {
    func recognize(
        sample: HandwritingSample,
        prompt: WordPrompt,
        for profileID: ProfileID
    ) async throws -> RecognitionResult {
        _ = profileID
        guard !sample.strokes.isEmpty else {
            return RecognitionResult(
                decision: .technicalFailure(.corruptedInput)
            )
        }
        return RecognitionResult(
            decision: .matched,
            recognizedText: prompt.normalizedText,
            confidence: RecognitionConfidence(1)
        )
    }
}
