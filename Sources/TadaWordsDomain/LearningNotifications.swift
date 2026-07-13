import Foundation

public struct LearningReminderTime: Codable, Hashable, Sendable {
    public let hour: Int
    public let minute: Int

    public init(hour: Int, minute: Int) {
        self.hour = min(23, max(0, hour))
        self.minute = min(59, max(0, minute))
    }

    public static let afterSchool = LearningReminderTime(hour: 17, minute: 30)
}

public struct NotificationQuietHours: Codable, Hashable, Sendable {
    public let startsAt: LearningReminderTime
    public let endsAt: LearningReminderTime

    public init(
        startsAt: LearningReminderTime = LearningReminderTime(hour: 20, minute: 0),
        endsAt: LearningReminderTime = LearningReminderTime(hour: 8, minute: 0)
    ) {
        self.startsAt = startsAt
        self.endsAt = endsAt
    }

    public static let childFriendlyDefault = NotificationQuietHours()

    public func contains(_ date: Date, calendar: Calendar) -> Bool {
        let components = calendar.dateComponents([.hour, .minute], from: date)
        let value = (components.hour ?? 0) * 60 + (components.minute ?? 0)
        let start = startsAt.hour * 60 + startsAt.minute
        let end = endsAt.hour * 60 + endsAt.minute
        if start == end { return false }
        if start < end { return value >= start && value < end }
        return value >= start || value < end
    }
}

public struct LearningNotificationPreferences: Codable, Hashable, Sendable {
    public let dailyReminderEnabled: Bool
    public let poolLowEnabled: Bool
    public let questCompletionEnabled: Bool
    public let syncFailureEnabled: Bool
    public let weeklySummaryEnabled: Bool
    public let dailyReminderTime: LearningReminderTime
    public let quietHours: NotificationQuietHours

    public init(
        dailyReminderEnabled: Bool = false,
        poolLowEnabled: Bool = false,
        questCompletionEnabled: Bool = false,
        syncFailureEnabled: Bool = false,
        weeklySummaryEnabled: Bool = false,
        dailyReminderTime: LearningReminderTime = .afterSchool,
        quietHours: NotificationQuietHours = .childFriendlyDefault
    ) {
        self.dailyReminderEnabled = dailyReminderEnabled
        self.poolLowEnabled = poolLowEnabled
        self.questCompletionEnabled = questCompletionEnabled
        self.syncFailureEnabled = syncFailureEnabled
        self.weeklySummaryEnabled = weeklySummaryEnabled
        self.dailyReminderTime = dailyReminderTime
        self.quietHours = quietHours
    }

    public static let disabled = LearningNotificationPreferences()

    public var hasEnabledNotifications: Bool {
        dailyReminderEnabled || poolLowEnabled || questCompletionEnabled
            || syncFailureEnabled || weeklySummaryEnabled
    }
}

public enum LearningNotificationKind: String, Codable, CaseIterable, Hashable,
    Sendable
{
    case dailyReminder
    case poolLow
    case questCompletion
    case syncFailure
    case weeklySummary
}

public struct LearningNotificationContext: Hashable, Sendable {
    public let profileID: ProfileID
    public let readPoolCount: Int
    public let writePoolCount: Int
    public let completedQuestCountToday: Int
    public let hasPendingSyncFailure: Bool
    public let weeklyAttentionCount: Int

    public init(
        profileID: ProfileID,
        readPoolCount: Int,
        writePoolCount: Int,
        completedQuestCountToday: Int,
        hasPendingSyncFailure: Bool,
        weeklyAttentionCount: Int
    ) {
        self.profileID = profileID
        self.readPoolCount = max(0, readPoolCount)
        self.writePoolCount = max(0, writePoolCount)
        self.completedQuestCountToday = max(0, completedQuestCountToday)
        self.hasPendingSyncFailure = hasPendingSyncFailure
        self.weeklyAttentionCount = max(0, weeklyAttentionCount)
    }
}

public enum LearningNotificationAuthorization: Equatable, Sendable {
    case notDetermined
    case denied
    case authorized
}

public protocol LearningNotificationScheduling: Sendable {
    func authorizationStatus() async -> LearningNotificationAuthorization

    func requestAuthorization() async -> LearningNotificationAuthorization

    func reconcile(
        preferences: LearningNotificationPreferences,
        context: LearningNotificationContext,
        calendar: Calendar
    ) async throws

    func removeNotifications(for profileID: ProfileID) async
}

public enum LearningNotificationPrivacyCopy {
    public static func title(for kind: LearningNotificationKind) -> String {
        switch kind {
        case .dailyReminder:
            "A Tada Words quest is ready"
        case .poolLow:
            "A word pool needs a refill"
        case .questCompletion:
            "Today's Tada Words quests are complete"
        case .syncFailure:
            "Tada Words needs attention"
        case .weeklySummary:
            "Your weekly Tada Words summary is ready"
        }
    }

    public static func body(for kind: LearningNotificationKind) -> String {
        switch kind {
        case .dailyReminder:
            "Open the app when your family is ready to practice."
        case .poolLow:
            "Open Parents to add upcoming school words."
        case .questCompletion:
            "Open the app to see today's progress."
        case .syncFailure:
            "Open Parents to review sync status."
        case .weeklySummary:
            "Open Parents to review learning patterns."
        }
    }
}
