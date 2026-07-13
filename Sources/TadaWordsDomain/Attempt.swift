import Foundation

public enum EncounterEvidence: String, Codable, CaseIterable, Hashable, Sendable {
    case studyExposed
    case firstIndependentAttempt
    case unaidedRetry
    case feedbackExposed
    case guidedRetry
    case helped
    case technicalRetry
    case recognitionUncertain

    /// Only the first valid response made before an answer is exposed belongs in
    /// guardian-facing accuracy and mastery calculations.
    public var countsTowardAccuracy: Bool {
        self == .firstIndependentAttempt
    }

    /// Memory schedulers must use the same narrow evidence boundary as accuracy.
    public var canUpdateMemory: Bool {
        self == .firstIndependentAttempt
    }

    public var isIndependentResponse: Bool {
        self == .firstIndependentAttempt || self == .unaidedRetry
    }

    public var hasAnswerExposure: Bool {
        switch self {
        case .feedbackExposed, .guidedRetry, .helped:
            true
        default:
            false
        }
    }

    public var isTechnicalEvidence: Bool {
        self == .technicalRetry || self == .recognitionUncertain
    }
}

public enum AttemptOutcome: Codable, Hashable, Sendable {
    case correct
    case incorrect
    case recognitionUncertain
    case technicalFailure(TechnicalFailureReason)
    case skipped

    public var isCorrect: Bool {
        self == .correct
    }

    public var isScorableResponse: Bool {
        self == .correct || self == .incorrect
    }
}

public enum TechnicalFailureReason: String, Codable, CaseIterable, Hashable, Sendable {
    case permissionDenied
    case noUsableAudio
    case wrongSpeaker
    case onDeviceRecognitionUnavailable
    case serviceUnavailable
    case timedOut
    case corruptedInput
}

public struct ElapsedTime: Codable, Hashable, Sendable, Comparable {
    public let seconds: TimeInterval

    /// Negative and non-finite measurements are normalized to zero at the
    /// adapter boundary so corrupt device timestamps cannot poison progress.
    public init(seconds: TimeInterval) {
        self.seconds = seconds.isFinite ? max(0, seconds) : 0
    }

    public static let zero = ElapsedTime(seconds: 0)

    public static func < (lhs: ElapsedTime, rhs: ElapsedTime) -> Bool {
        lhs.seconds < rhs.seconds
    }
}

public struct RecognitionConfidence: Codable, Hashable, Sendable, Comparable {
    public let value: Double

    /// Confidence is represented as a unit interval. Device adapters may return
    /// wider numeric ranges, so conversion is centralized here.
    public init(_ value: Double) {
        self.value = value.isFinite ? min(1, max(0, value)) : 0
    }

    public static func < (
        lhs: RecognitionConfidence,
        rhs: RecognitionConfidence
    ) -> Bool {
        lhs.value < rhs.value
    }
}

public struct AttemptTiming: Codable, Hashable, Sendable {
    public let totalResponseTime: ElapsedTime?
    public let speechOnsetLatency: ElapsedTime?
    public let firstStrokeLatency: ElapsedTime?
    public let activeStrokeTime: ElapsedTime?
    public let idleTime: ElapsedTime?
    public let replayPauseTime: ElapsedTime?

    public init(
        totalResponseTime: ElapsedTime? = nil,
        speechOnsetLatency: ElapsedTime? = nil,
        firstStrokeLatency: ElapsedTime? = nil,
        activeStrokeTime: ElapsedTime? = nil,
        idleTime: ElapsedTime? = nil,
        replayPauseTime: ElapsedTime? = nil
    ) {
        self.totalResponseTime = totalResponseTime
        self.speechOnsetLatency = speechOnsetLatency
        self.firstStrokeLatency = firstStrokeLatency
        self.activeStrokeTime = activeStrokeTime
        self.idleTime = idleTime
        self.replayPauseTime = replayPauseTime
    }

    public static let unmeasured = AttemptTiming()
}

/// An immutable fact captured during a learning encounter. Corrections are
/// appended as `AttemptCorrectionEvent` values; this event is never rewritten.
public struct AttemptEvent: Codable, Hashable, Sendable {
    public let id: AttemptID
    public let questID: QuestID?
    public let profileID: ProfileID
    public let wordPromptID: WordPromptID
    public let learningMode: LearningMode
    public let evidence: EncounterEvidence
    public let outcome: AttemptOutcome
    public let timing: AttemptTiming
    public let occurredAt: Date
    public let replayCount: Int
    public let recognitionConfidence: RecognitionConfidence?
    /// Device/input/task context captured with timing so pace history never
    /// mixes phone, tablet, speech, finger, Pencil, or different word lengths.
    public let paceContext: PaceContext?

    public init(
        id: AttemptID = AttemptID(),
        questID: QuestID? = nil,
        profileID: ProfileID,
        wordPromptID: WordPromptID,
        learningMode: LearningMode,
        evidence: EncounterEvidence,
        outcome: AttemptOutcome,
        timing: AttemptTiming = .unmeasured,
        occurredAt: Date,
        replayCount: Int = 0,
        recognitionConfidence: RecognitionConfidence? = nil,
        paceContext: PaceContext? = nil
    ) {
        self.id = id
        self.questID = questID
        self.profileID = profileID
        self.wordPromptID = wordPromptID
        self.learningMode = learningMode
        self.evidence = evidence
        self.outcome = outcome
        self.timing = timing
        self.occurredAt = occurredAt
        self.replayCount = max(0, replayCount)
        self.recognitionConfidence = recognitionConfidence
        self.paceContext = paceContext
    }
}

public struct AttemptCorrectionEvent: Codable, Hashable, Sendable {
    public let id: AttemptCorrectionID
    public let originalAttemptID: AttemptID
    public let correctedOutcome: AttemptOutcome
    public let reason: AttemptCorrectionReason
    public let correctedAt: Date

    public init(
        id: AttemptCorrectionID = AttemptCorrectionID(),
        originalAttemptID: AttemptID,
        correctedOutcome: AttemptOutcome,
        reason: AttemptCorrectionReason,
        correctedAt: Date
    ) {
        self.id = id
        self.originalAttemptID = originalAttemptID
        self.correctedOutcome = correctedOutcome
        self.reason = reason
        self.correctedAt = correctedAt
    }
}

public enum AttemptCorrectionReason: Codable, Hashable, Sendable {
    case guardianOverride
    case recognitionReevaluation(modelVersion: String)
    case duplicateEvent
    case other(String)
}
