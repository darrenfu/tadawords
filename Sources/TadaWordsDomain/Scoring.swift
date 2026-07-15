import Foundation

public enum QuestStar: String, Codable, CaseIterable, Hashable, Sendable {
    case completion
    case accuracy
    case personalPace
}

public struct QuestStars: Codable, Hashable, Sendable {
    public let earned: Set<QuestStar>

    public init(earned: Set<QuestStar> = []) {
        self.earned = earned
    }

    public var count: Int { earned.count }
    public var maximumCount: Int { QuestStar.allCases.count }

    public func contains(_ star: QuestStar) -> Bool {
        earned.contains(star)
    }
}

public enum LearningInputMethod: String, Codable, CaseIterable, Hashable, Sendable {
    case speech
    case fingerWriting
    case pencilWriting
    /// A theme-skinned, in-app A-Z keyboard. This is intentionally distinct
    /// from the system keyboard and from handwriting so personal pace history
    /// never compares typing with drawing letterforms.
    case letterKeyboard
}

/// The child-facing way to answer a Write quest.
///
/// Both choices use the same `.write` pool, scheduler, completion, and mastery
/// records. Only the response surface and comparable pace context differ.
public enum WriteQuestInputMethod: String, Codable, CaseIterable, Hashable, Sendable {
    case handwriting
    case letterKeyboard

    public var defaultLearningInputMethod: LearningInputMethod {
        switch self {
        case .handwriting:
            .fingerWriting
        case .letterKeyboard:
            .letterKeyboard
        }
    }
}

public enum WritingInputMethod: String, Codable, CaseIterable, Hashable, Sendable {
    case finger
    case pencil

    public var learningInputMethod: LearningInputMethod {
        switch self {
        case .finger:
            .fingerWriting
        case .pencil:
            .pencilWriting
        }
    }
}

public enum DeviceClass: String, Codable, CaseIterable, Hashable, Sendable {
    case phone
    case tablet
}

public struct PaceContext: Codable, Hashable, Sendable {
    public let learningMode: LearningMode
    public let deviceClass: DeviceClass
    public let inputMethod: LearningInputMethod
    public let wordLength: Int

    public init(
        learningMode: LearningMode,
        deviceClass: DeviceClass,
        inputMethod: LearningInputMethod,
        wordLength: Int
    ) {
        self.learningMode = learningMode
        self.deviceClass = deviceClass
        self.inputMethod = inputMethod
        self.wordLength = max(1, wordLength)
    }
}

/// A child's own comfortable interval for a comparable task. This is not a
/// leaderboard and must not be interpreted as "faster is better."
public struct PersonalPaceBand: Codable, Hashable, Sendable {
    public let context: PaceContext
    public let lowerBound: ElapsedTime
    public let upperBound: ElapsedTime
    public let sampleCount: Int

    public init(
        context: PaceContext,
        lowerBound: ElapsedTime,
        upperBound: ElapsedTime,
        sampleCount: Int
    ) {
        self.context = context
        self.lowerBound = min(lowerBound, upperBound)
        self.upperBound = max(lowerBound, upperBound)
        self.sampleCount = max(0, sampleCount)
    }

    public func contains(_ elapsedTime: ElapsedTime) -> Bool {
        lowerBound <= elapsedTime && elapsedTime <= upperBound
    }
}

public enum PersonalPaceAssessment: Codable, Hashable, Sendable {
    case unavailable
    case calibrating(sampleCount: Int, requiredSampleCount: Int)
    case withinPersonalBand
    case outsidePersonalBand
}

public struct QuestScore: Codable, Hashable, Sendable {
    public let points: Int
    public let firstIndependentCorrectCount: Int
    public let firstIndependentAttemptCount: Int
    public let stars: QuestStars
    public let personalPaceAssessment: PersonalPaceAssessment

    public init(
        points: Int,
        firstIndependentCorrectCount: Int,
        firstIndependentAttemptCount: Int,
        stars: QuestStars,
        personalPaceAssessment: PersonalPaceAssessment
    ) {
        let attemptCount = max(0, firstIndependentAttemptCount)
        self.points = max(0, points)
        self.firstIndependentCorrectCount = min(
            attemptCount,
            max(0, firstIndependentCorrectCount)
        )
        self.firstIndependentAttemptCount = attemptCount
        self.stars = stars
        self.personalPaceAssessment = personalPaceAssessment
    }

    public var firstIndependentAccuracy: Double? {
        guard firstIndependentAttemptCount > 0 else { return nil }
        return Double(firstIndependentCorrectCount) / Double(firstIndependentAttemptCount)
    }
}
