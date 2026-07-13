import Foundation

/// A compact, rebuildable Ebbinghaus memory state.
///
/// `stabilityDays` is the time constant in `R(t) = exp(-t / stability)`, where
/// `t` is the number of days since `lastIndependentAttemptAt`. The scheduler
/// chooses a transparent target-recall threshold and derives `nextReviewAt`
/// from this state; immutable attempts remain the source of truth.
public struct MemoryState: Codable, Hashable, Sendable {
    private static let secondsPerDay: TimeInterval = 86_400

    public let stabilityDays: Double
    public let difficulty: Double
    public let nextReviewAt: Date?
    public let lastIndependentAttemptAt: Date?
    public let consecutiveIndependentSuccesses: Int
    public let lapseCount: Int

    public init(
        stabilityDays: Double = 0,
        difficulty: Double = 0.5,
        nextReviewAt: Date? = nil,
        lastIndependentAttemptAt: Date? = nil,
        consecutiveIndependentSuccesses: Int = 0,
        lapseCount: Int = 0
    ) {
        self.stabilityDays = max(0, stabilityDays.isFinite ? stabilityDays : 0)
        self.difficulty = min(1, max(0, difficulty.isFinite ? difficulty : 0.5))
        self.nextReviewAt = nextReviewAt
        self.lastIndependentAttemptAt = lastIndependentAttemptAt
        self.consecutiveIndependentSuccesses = max(0, consecutiveIndependentSuccesses)
        self.lapseCount = max(0, lapseCount)
    }

    public static let unstarted = MemoryState()

    /// Predicted recall probability at `date` according to
    /// `R(t) = exp(-t / stability)`.
    ///
    /// An unstarted state has no established memory and returns `0`. Dates at
    /// or before the latest independent attempt return `1`.
    public func predictedRecall(at date: Date) -> Double {
        guard let lastIndependentAttemptAt, stabilityDays > 0 else { return 0 }
        let elapsedDays = max(
            0,
            date.timeIntervalSince(lastIndependentAttemptAt) / Self.secondsPerDay
        )
        return min(1, max(0, exp(-elapsedDays / stabilityDays)))
    }
}

/// A rebuildable snapshot. `AttemptEvent` and `AttemptCorrectionEvent` remain
/// the durable source for guardian corrections and future algorithm changes.
public struct WordProgress: Codable, Hashable, Sendable {
    public let profileID: ProfileID
    public let wordPromptID: WordPromptID
    public let learningMode: LearningMode
    public let memoryState: MemoryState
    public let firstIndependentAttemptCount: Int
    public let firstIndependentCorrectCount: Int
    public let firstIndependentResponseTimeTotal: ElapsedTime
    public let firstIndependentTimedAttemptCount: Int
    public let totalReplayCount: Int
    public let helpedAttemptCount: Int
    public let uncertainAttemptCount: Int
    /// Dates of first, independent correct responses. Immutable attempts remain
    /// authoritative; this rebuildable projection supports cross-day mastery.
    public let independentSuccessDates: [Date]
    public let lastEncounterAt: Date?

    public init(
        profileID: ProfileID,
        wordPromptID: WordPromptID,
        learningMode: LearningMode,
        memoryState: MemoryState = .unstarted,
        firstIndependentAttemptCount: Int = 0,
        firstIndependentCorrectCount: Int = 0,
        firstIndependentResponseTimeTotal: ElapsedTime = .zero,
        firstIndependentTimedAttemptCount: Int = 0,
        totalReplayCount: Int = 0,
        helpedAttemptCount: Int = 0,
        uncertainAttemptCount: Int = 0,
        independentSuccessDates: [Date] = [],
        lastEncounterAt: Date? = nil
    ) {
        let attemptCount = max(0, firstIndependentAttemptCount)
        let timedAttemptCount = min(
            attemptCount,
            max(0, firstIndependentTimedAttemptCount)
        )
        self.profileID = profileID
        self.wordPromptID = wordPromptID
        self.learningMode = learningMode
        self.memoryState = memoryState
        self.firstIndependentAttemptCount = attemptCount
        self.firstIndependentCorrectCount = min(
            attemptCount,
            max(0, firstIndependentCorrectCount)
        )
        self.firstIndependentResponseTimeTotal =
            timedAttemptCount > 0
            ? firstIndependentResponseTimeTotal
            : .zero
        self.firstIndependentTimedAttemptCount = timedAttemptCount
        self.totalReplayCount = max(0, totalReplayCount)
        self.helpedAttemptCount = max(0, helpedAttemptCount)
        self.uncertainAttemptCount = max(0, uncertainAttemptCount)
        self.independentSuccessDates = independentSuccessDates.sorted()
        self.lastEncounterAt = lastEncounterAt
    }

    public var firstIndependentAccuracy: Double? {
        guard firstIndependentAttemptCount > 0 else { return nil }
        return Double(firstIndependentCorrectCount) / Double(firstIndependentAttemptCount)
    }

    /// Mean response time across first, independent, scorable encounters.
    /// Missing device timing is excluded rather than treated as a zero-second
    /// response.
    public var firstIndependentMeanResponseTime: ElapsedTime? {
        guard firstIndependentTimedAttemptCount > 0 else { return nil }
        return ElapsedTime(
            seconds: firstIndependentResponseTimeTotal.seconds
                / Double(firstIndependentTimedAttemptCount)
        )
    }

    public static func unstarted(
        profileID: ProfileID,
        wordPromptID: WordPromptID,
        learningMode: LearningMode
    ) -> WordProgress {
        WordProgress(
            profileID: profileID,
            wordPromptID: wordPromptID,
            learningMode: learningMode
        )
    }

    private enum CodingKeys: String, CodingKey {
        case profileID
        case wordPromptID
        case learningMode
        case memoryState
        case firstIndependentAttemptCount
        case firstIndependentCorrectCount
        case firstIndependentResponseTimeTotal
        case firstIndependentTimedAttemptCount
        case totalReplayCount
        case helpedAttemptCount
        case uncertainAttemptCount
        case independentSuccessDates
        case lastEncounterAt
    }

    /// Decodes pre-signal snapshots by defaulting newly rebuildable aggregates
    /// to zero. A subsequent event-history rebuild will populate them exactly.
    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            profileID: try container.decode(ProfileID.self, forKey: .profileID),
            wordPromptID: try container.decode(
                WordPromptID.self,
                forKey: .wordPromptID
            ),
            learningMode: try container.decode(
                LearningMode.self,
                forKey: .learningMode
            ),
            memoryState: try container.decode(
                MemoryState.self,
                forKey: .memoryState
            ),
            firstIndependentAttemptCount: try container.decode(
                Int.self,
                forKey: .firstIndependentAttemptCount
            ),
            firstIndependentCorrectCount: try container.decode(
                Int.self,
                forKey: .firstIndependentCorrectCount
            ),
            firstIndependentResponseTimeTotal: try container.decodeIfPresent(
                ElapsedTime.self,
                forKey: .firstIndependentResponseTimeTotal
            ) ?? .zero,
            firstIndependentTimedAttemptCount: try container.decodeIfPresent(
                Int.self,
                forKey: .firstIndependentTimedAttemptCount
            ) ?? 0,
            totalReplayCount: try container.decodeIfPresent(
                Int.self,
                forKey: .totalReplayCount
            ) ?? 0,
            helpedAttemptCount: try container.decodeIfPresent(
                Int.self,
                forKey: .helpedAttemptCount
            ) ?? 0,
            uncertainAttemptCount: try container.decodeIfPresent(
                Int.self,
                forKey: .uncertainAttemptCount
            ) ?? 0,
            independentSuccessDates: try container.decodeIfPresent(
                [Date].self,
                forKey: .independentSuccessDates
            ) ?? [],
            lastEncounterAt: try container.decodeIfPresent(
                Date.self,
                forKey: .lastEncounterAt
            )
        )
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(profileID, forKey: .profileID)
        try container.encode(wordPromptID, forKey: .wordPromptID)
        try container.encode(learningMode, forKey: .learningMode)
        try container.encode(memoryState, forKey: .memoryState)
        try container.encode(
            firstIndependentAttemptCount,
            forKey: .firstIndependentAttemptCount
        )
        try container.encode(
            firstIndependentCorrectCount,
            forKey: .firstIndependentCorrectCount
        )
        try container.encode(
            firstIndependentResponseTimeTotal,
            forKey: .firstIndependentResponseTimeTotal
        )
        try container.encode(
            firstIndependentTimedAttemptCount,
            forKey: .firstIndependentTimedAttemptCount
        )
        try container.encode(totalReplayCount, forKey: .totalReplayCount)
        try container.encode(helpedAttemptCount, forKey: .helpedAttemptCount)
        try container.encode(uncertainAttemptCount, forKey: .uncertainAttemptCount)
        try container.encode(independentSuccessDates, forKey: .independentSuccessDates)
        try container.encodeIfPresent(lastEncounterAt, forKey: .lastEncounterAt)
    }
}
