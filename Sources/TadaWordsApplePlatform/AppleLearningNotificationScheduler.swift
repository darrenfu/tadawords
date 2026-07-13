import Foundation
import TadaWordsDomain
@preconcurrency import UserNotifications

public actor AppleLearningNotificationScheduler: LearningNotificationScheduling {
    private let center: UNUserNotificationCenter

    public init(center: UNUserNotificationCenter = .current()) {
        self.center = center
    }

    public func authorizationStatus() async -> LearningNotificationAuthorization {
        let settings = await center.notificationSettings()
        return Self.map(settings.authorizationStatus)
    }

    public func requestAuthorization() async -> LearningNotificationAuthorization {
        do {
            let granted = try await center.requestAuthorization(
                options: [.alert, .sound]
            )
            return granted ? .authorized : .denied
        } catch {
            return .denied
        }
    }

    public func reconcile(
        preferences: LearningNotificationPreferences,
        context: LearningNotificationContext,
        calendar: Calendar
    ) async throws {
        await removeNotifications(for: context.profileID)
        guard preferences.hasEnabledNotifications else { return }
        guard await authorizationStatus() == .authorized else { return }

        let plans = AppleLearningNotificationPlanBuilder.plans(
            preferences: preferences,
            context: context,
            calendar: calendar
        )
        for plan in plans {
            let content = UNMutableNotificationContent()
            content.title = LearningNotificationPrivacyCopy.title(for: plan.kind)
            content.body = LearningNotificationPrivacyCopy.body(for: plan.kind)
            content.sound = .default
            content.userInfo = ["kind": plan.kind.rawValue]

            let trigger: UNNotificationTrigger
            switch plan.trigger {
            case .after(let seconds):
                trigger = UNTimeIntervalNotificationTrigger(
                    timeInterval: max(1, seconds),
                    repeats: false
                )
            case .calendar(let components, let repeats):
                trigger = UNCalendarNotificationTrigger(
                    dateMatching: components,
                    repeats: repeats
                )
            }
            try await center.add(
                UNNotificationRequest(
                    identifier: plan.identifier,
                    content: content,
                    trigger: trigger
                )
            )
        }
    }

    public func removeNotifications(for profileID: ProfileID) async {
        center.removePendingNotificationRequests(
            withIdentifiers: AppleLearningNotificationPlanBuilder.identifiers(
                for: profileID
            )
        )
    }

    private static func map(
        _ status: UNAuthorizationStatus
    ) -> LearningNotificationAuthorization {
        switch status {
        case .authorized, .provisional, .ephemeral:
            .authorized
        case .denied:
            .denied
        case .notDetermined:
            .notDetermined
        @unknown default:
            .denied
        }
    }
}

struct AppleLearningNotificationPlan: Equatable, Sendable {
    enum Trigger: Equatable, Sendable {
        case after(TimeInterval)
        case calendar(DateComponents, repeats: Bool)
    }

    let identifier: String
    let kind: LearningNotificationKind
    let trigger: Trigger
}

enum AppleLearningNotificationPlanBuilder {
    private static let lowPoolThreshold = 2

    static func identifiers(for profileID: ProfileID) -> [String] {
        LearningNotificationKind.allCases.map {
            identifier(profileID: profileID, kind: $0)
        }
    }

    static func plans(
        preferences: LearningNotificationPreferences,
        context: LearningNotificationContext,
        calendar: Calendar,
        now: Date = Date()
    ) -> [AppleLearningNotificationPlan] {
        var plans: [AppleLearningNotificationPlan] = []
        let immediateDelay = oneShotDelay(
            now: now,
            quietHours: preferences.quietHours,
            calendar: calendar
        )
        if preferences.dailyReminderEnabled {
            let time = adjustedReminderTime(
                preferences.dailyReminderTime,
                quietHours: preferences.quietHours
            )
            plans.append(
                plan(
                    profileID: context.profileID,
                    kind: .dailyReminder,
                    trigger: .calendar(
                        DateComponents(hour: time.hour, minute: time.minute),
                        repeats: true
                    )
                )
            )
        }
        if preferences.poolLowEnabled,
            min(context.readPoolCount, context.writePoolCount) < lowPoolThreshold
        {
            plans.append(
                plan(
                    profileID: context.profileID,
                    kind: .poolLow,
                    trigger: .after(immediateDelay)
                )
            )
        }
        if preferences.questCompletionEnabled,
            context.completedQuestCountToday >= 2
        {
            plans.append(
                plan(
                    profileID: context.profileID,
                    kind: .questCompletion,
                    trigger: .after(immediateDelay)
                )
            )
        }
        if preferences.syncFailureEnabled, context.hasPendingSyncFailure {
            plans.append(
                plan(
                    profileID: context.profileID,
                    kind: .syncFailure,
                    trigger: .after(immediateDelay)
                )
            )
        }
        if preferences.weeklySummaryEnabled, context.weeklyAttentionCount > 0 {
            let time = adjustedReminderTime(
                LearningReminderTime(hour: 18, minute: 0),
                quietHours: preferences.quietHours
            )
            plans.append(
                plan(
                    profileID: context.profileID,
                    kind: .weeklySummary,
                    trigger: .calendar(
                        DateComponents(
                            calendar: calendar,
                            timeZone: calendar.timeZone,
                            hour: time.hour,
                            minute: time.minute,
                            weekday: 1
                        ),
                        repeats: true
                    )
                )
            )
        }
        return plans
    }

    private static func plan(
        profileID: ProfileID,
        kind: LearningNotificationKind,
        trigger: AppleLearningNotificationPlan.Trigger
    ) -> AppleLearningNotificationPlan {
        AppleLearningNotificationPlan(
            identifier: identifier(profileID: profileID, kind: kind),
            kind: kind,
            trigger: trigger
        )
    }

    private static func identifier(
        profileID: ProfileID,
        kind: LearningNotificationKind
    ) -> String {
        "tada.\(profileID.rawValue.uuidString).\(kind.rawValue)"
    }

    private static func adjustedReminderTime(
        _ proposed: LearningReminderTime,
        quietHours: NotificationQuietHours
    ) -> LearningReminderTime {
        let proposedMinutes = proposed.hour * 60 + proposed.minute
        let start = quietHours.startsAt.hour * 60 + quietHours.startsAt.minute
        let end = quietHours.endsAt.hour * 60 + quietHours.endsAt.minute
        let isQuiet: Bool
        if start == end {
            isQuiet = false
        } else if start < end {
            isQuiet = proposedMinutes >= start && proposedMinutes < end
        } else {
            isQuiet = proposedMinutes >= start || proposedMinutes < end
        }
        return isQuiet ? quietHours.endsAt : proposed
    }

    private static func oneShotDelay(
        now: Date,
        quietHours: NotificationQuietHours,
        calendar: Calendar
    ) -> TimeInterval {
        guard quietHours.contains(now, calendar: calendar) else { return 5 }
        let end = DateComponents(
            hour: quietHours.endsAt.hour,
            minute: quietHours.endsAt.minute
        )
        guard
            let nextAllowed = calendar.nextDate(
                after: now,
                matching: end,
                matchingPolicy: .nextTime
            )
        else { return 5 }
        return max(5, nextAllowed.timeIntervalSince(now))
    }
}
