public struct LearningRouteSettings: Codable, Hashable, Sendable {
    public static let wordLimitRange: ClosedRange<Int> = 0...20
    public static let emergencyAfterSecondsRange: ClosedRange<Int> = 60...3_600

    public let newWordLimit: Int
    public let reviewWordLimit: Int
    public let contentOrder: QuestContentOrder
    public let emergencyAfterSeconds: Int

    public init(
        newWordLimit: Int,
        reviewWordLimit: Int,
        contentOrder: QuestContentOrder,
        emergencyAfterSeconds: Int
    ) {
        self.newWordLimit = Self.clamp(
            newWordLimit,
            to: Self.wordLimitRange
        )
        self.reviewWordLimit = Self.clamp(
            reviewWordLimit,
            to: Self.wordLimitRange
        )
        self.contentOrder = contentOrder
        self.emergencyAfterSeconds = Self.clamp(
            emergencyAfterSeconds,
            to: Self.emergencyAfterSecondsRange
        )
    }

    public static let defaultRead = LearningRouteSettings(
        newWordLimit: 5,
        reviewWordLimit: 5,
        contentOrder: .newThenReview,
        emergencyAfterSeconds: 180
    )

    public static let defaultWrite = LearningRouteSettings(
        newWordLimit: 5,
        reviewWordLimit: 5,
        contentOrder: .newThenReview,
        emergencyAfterSeconds: 300
    )

    func questConfiguration(for learningMode: LearningMode) -> QuestConfiguration {
        QuestConfiguration(
            learningMode: learningMode,
            newWordLimit: newWordLimit,
            reviewWordLimit: reviewWordLimit,
            attentionBudget: attentionBudget,
            contentOrder: contentOrder
        )
    }

    private var attentionBudget: Int {
        newWordLimit + reviewWordLimit
    }

    private static func clamp(
        _ value: Int,
        to range: ClosedRange<Int>
    ) -> Int {
        min(range.upperBound, max(range.lowerBound, value))
    }

    private enum CodingKeys: String, CodingKey {
        case newWordLimit
        case reviewWordLimit
        case contentOrder
        case emergencyAfterSeconds
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            newWordLimit: try container.decode(Int.self, forKey: .newWordLimit),
            reviewWordLimit: try container.decode(
                Int.self,
                forKey: .reviewWordLimit
            ),
            contentOrder: try container.decode(
                QuestContentOrder.self,
                forKey: .contentOrder
            ),
            emergencyAfterSeconds: try container.decode(
                Int.self,
                forKey: .emergencyAfterSeconds
            )
        )
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(newWordLimit, forKey: .newWordLimit)
        try container.encode(reviewWordLimit, forKey: .reviewWordLimit)
        try container.encode(contentOrder, forKey: .contentOrder)
        try container.encode(
            emergencyAfterSeconds,
            forKey: .emergencyAfterSeconds
        )
    }
}

public struct PracticeModeConfiguration: Hashable, Sendable {
    public let questConfiguration: QuestConfiguration
    public let emergencyAfterSeconds: Int

    public init(
        questConfiguration: QuestConfiguration,
        emergencyAfterSeconds: Int
    ) {
        self.questConfiguration = questConfiguration
        self.emergencyAfterSeconds = min(
            LearningRouteSettings.emergencyAfterSecondsRange.upperBound,
            max(
                LearningRouteSettings.emergencyAfterSecondsRange.lowerBound,
                emergencyAfterSeconds
            )
        )
    }
}

public struct PracticeInterfacePreferences: Codable, Hashable, Sendable {
    public let leftHandedLayoutEnabled: Bool

    public init(leftHandedLayoutEnabled: Bool = false) {
        self.leftHandedLayoutEnabled = leftHandedLayoutEnabled
    }

    public static let `default` = PracticeInterfacePreferences()
}

public enum WordRecommendationMode: String, Codable, CaseIterable, Hashable,
    Sendable
{
    case manualOnly
    case parentFirstAutomaticFallback
    case gradeAutomatic
}

public struct ProfilePracticeSettings: Codable, Hashable, Sendable {
    public let profileID: ProfileID
    public let read: LearningRouteSettings
    public let write: LearningRouteSettings
    public let audio: AudioPreferences
    public let notifications: LearningNotificationPreferences
    public let interface: PracticeInterfacePreferences
    public let wordRecommendationMode: WordRecommendationMode

    public init(
        profileID: ProfileID,
        read: LearningRouteSettings = .defaultRead,
        write: LearningRouteSettings = .defaultWrite,
        audio: AudioPreferences = .default,
        notifications: LearningNotificationPreferences = .disabled,
        interface: PracticeInterfacePreferences = .default,
        wordRecommendationMode: WordRecommendationMode =
            .manualOnly
    ) {
        self.profileID = profileID
        self.read = read
        self.write = write
        self.audio = audio
        self.notifications = notifications
        self.interface = interface
        // Legacy automatic modes remain decodable for existing snapshots, but
        // V1 content is always sourced from a grown-up.
        _ = wordRecommendationMode
        self.wordRecommendationMode = .manualOnly
    }

    public static func defaults(
        for profileID: ProfileID
    ) -> ProfilePracticeSettings {
        ProfilePracticeSettings(profileID: profileID)
    }

    public func route(for learningMode: LearningMode) -> LearningRouteSettings {
        switch learningMode {
        case .read:
            read
        case .write:
            write
        }
    }

    public func configuration(
        for learningMode: LearningMode
    ) -> PracticeModeConfiguration {
        let route = route(for: learningMode)
        return PracticeModeConfiguration(
            questConfiguration: route.questConfiguration(for: learningMode),
            emergencyAfterSeconds: route.emergencyAfterSeconds
        )
    }

    private enum CodingKeys: String, CodingKey {
        case profileID
        case read
        case write
        case audio
        case notifications
        case interface
        case wordRecommendationMode
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            profileID: try container.decode(ProfileID.self, forKey: .profileID),
            read: try container.decode(LearningRouteSettings.self, forKey: .read),
            write: try container.decode(LearningRouteSettings.self, forKey: .write),
            audio: try container.decodeIfPresent(
                AudioPreferences.self,
                forKey: .audio
            ) ?? .default,
            notifications: try container.decodeIfPresent(
                LearningNotificationPreferences.self,
                forKey: .notifications
            ) ?? .disabled,
            interface: try container.decodeIfPresent(
                PracticeInterfacePreferences.self,
                forKey: .interface
            ) ?? .default,
            wordRecommendationMode: .manualOnly
        )
    }
}
