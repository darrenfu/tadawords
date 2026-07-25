import Foundation

public enum RecognitionDecision: Codable, Hashable, Sendable {
    case matched
    case notMatched
    case uncertain
    case technicalFailure(TechnicalFailureReason)

    public var attemptOutcome: AttemptOutcome {
        switch self {
        case .matched:
            .correct
        case .notMatched:
            .incorrect
        case .uncertain:
            .recognitionUncertain
        case .technicalFailure(let reason):
            .technicalFailure(reason)
        }
    }
}

public enum TargetSpeakerAssessment: String, Codable, CaseIterable, Hashable, Sendable {
    case matched
    case mismatched
    case unavailable
}

public struct RecognitionResult: Codable, Hashable, Sendable {
    public let decision: RecognitionDecision
    public let recognizedText: String?
    public let confidence: RecognitionConfidence?
    public let targetSpeakerAssessment: TargetSpeakerAssessment

    public init(
        decision: RecognitionDecision,
        recognizedText: String? = nil,
        confidence: RecognitionConfidence? = nil,
        targetSpeakerAssessment: TargetSpeakerAssessment = .unavailable
    ) {
        self.decision = decision
        self.recognizedText = recognizedText
        self.confidence = confidence
        self.targetSpeakerAssessment = targetSpeakerAssessment
    }
}

public enum SpeakerFilterPolicy: String, Codable, CaseIterable, Hashable, Sendable {
    case disabled
    /// Use an enrolled voiceprint as a confidence signal. A mismatch remains a
    /// technical retry and must never block the child from continuing.
    case useWhenAvailable
}

public struct SpeechRecognitionRequest: Codable, Hashable, Sendable {
    public let profileID: ProfileID
    public let prompt: WordPrompt
    public let maximumRecordingDuration: ElapsedTime
    public let speakerFilterPolicy: SpeakerFilterPolicy
    public let noiseSuppressionEnabled: Bool

    public init(
        profileID: ProfileID,
        prompt: WordPrompt,
        maximumRecordingDuration: ElapsedTime,
        speakerFilterPolicy: SpeakerFilterPolicy = .useWhenAvailable,
        noiseSuppressionEnabled: Bool = true
    ) {
        self.profileID = profileID
        self.prompt = prompt
        self.maximumRecordingDuration = maximumRecordingDuration
        self.speakerFilterPolicy = speakerFilterPolicy
        self.noiseSuppressionEnabled = noiseSuppressionEnabled
    }
}

public struct NormalizedPoint: Codable, Hashable, Sendable {
    public let x: Double
    public let y: Double

    public init(x: Double, y: Double) {
        self.x = x.isFinite ? min(1, max(0, x)) : 0
        self.y = y.isFinite ? min(1, max(0, y)) : 0
    }
}

public struct HandwritingPoint: Codable, Hashable, Sendable {
    public let location: NormalizedPoint
    public let elapsedSincePrompt: ElapsedTime
    public let pressure: Double?

    public init(
        location: NormalizedPoint,
        elapsedSincePrompt: ElapsedTime,
        pressure: Double? = nil
    ) {
        self.location = location
        self.elapsedSincePrompt = elapsedSincePrompt
        if let pressure, pressure.isFinite {
            self.pressure = min(1, max(0, pressure))
        } else {
            self.pressure = nil
        }
    }
}

public struct HandwritingStroke: Codable, Hashable, Sendable {
    public let points: [HandwritingPoint]

    public init(points: [HandwritingPoint]) {
        self.points = points
    }
}

public struct HandwritingSample: Codable, Hashable, Sendable {
    public let strokes: [HandwritingStroke]
    public let inputMethod: WritingInputMethod

    public init(strokes: [HandwritingStroke], inputMethod: WritingInputMethod) {
        self.strokes = strokes
        self.inputMethod = inputMethod
    }
}

public protocol AudioPromptService: Sendable {
    func play(_ prompt: WordPrompt, for profileID: ProfileID) async throws

    /// Speaks the complete enrollment sentence before a child records it.
    func playVoiceSetupSentence(
        _ sentence: String,
        for profileID: ProfileID
    ) async throws
}

/// Optional recovery capability for prompt services that can speak a word
/// without the remote teacher-audio path. Feature code uses this only after
/// the primary prompt reports a visible, non-fatal failure.
public protocol FallbackAudioPromptService: AudioPromptService {
    func playFallback(
        _ prompt: WordPrompt,
        for profileID: ProfileID
    ) async throws
}

extension AudioPromptService {
    public func playVoiceSetupSentence(
        _ sentence: String,
        for profileID: ProfileID
    ) async throws {
        _ = sentence
        _ = profileID
    }
}

public protocol SpeechRecognitionService: Sendable {
    func recognize(_ request: SpeechRecognitionRequest) async throws -> RecognitionResult
}

public protocol HandwritingRecognitionService: Sendable {
    func recognize(
        sample: HandwritingSample,
        prompt: WordPrompt,
        for profileID: ProfileID
    ) async throws -> RecognitionResult
}
