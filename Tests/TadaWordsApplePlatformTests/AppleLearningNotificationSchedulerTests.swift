import Foundation
import TadaWordsDomain
import XCTest

@testable import TadaWordsApplePlatform

final class AppleLearningNotificationSchedulerTests: XCTestCase {
    func testPlanBuilderCreatesOnlyEnabledRelevantPrivacySafeKinds() {
        let profileID = ProfileID()
        let preferences = LearningNotificationPreferences(
            dailyReminderEnabled: true,
            poolLowEnabled: true,
            questCompletionEnabled: true,
            syncFailureEnabled: true,
            weeklySummaryEnabled: true
        )
        let context = LearningNotificationContext(
            profileID: profileID,
            readPoolCount: 1,
            writePoolCount: 8,
            completedQuestCountToday: 2,
            hasPendingSyncFailure: true,
            weeklyAttentionCount: 3
        )

        let plans = AppleLearningNotificationPlanBuilder.plans(
            preferences: preferences,
            context: context,
            calendar: Calendar(identifier: .gregorian)
        )

        XCTAssertEqual(Set(plans.map(\.kind)), Set(LearningNotificationKind.allCases))
        XCTAssertTrue(plans.allSatisfy { $0.identifier.contains(profileID.rawValue.uuidString) })
    }

    func testDailyReminderMovesToQuietHoursEnd() {
        let profileID = ProfileID()
        let preferences = LearningNotificationPreferences(
            dailyReminderEnabled: true,
            dailyReminderTime: LearningReminderTime(hour: 21, minute: 15),
            quietHours: NotificationQuietHours(
                startsAt: LearningReminderTime(hour: 20, minute: 0),
                endsAt: LearningReminderTime(hour: 8, minute: 30)
            )
        )
        let context = LearningNotificationContext(
            profileID: profileID,
            readPoolCount: 8,
            writePoolCount: 8,
            completedQuestCountToday: 0,
            hasPendingSyncFailure: false,
            weeklyAttentionCount: 0
        )

        let plan = AppleLearningNotificationPlanBuilder.plans(
            preferences: preferences,
            context: context,
            calendar: Calendar(identifier: .gregorian)
        ).first

        guard case .calendar(let components, true) = plan?.trigger else {
            return XCTFail("Expected a repeating calendar trigger")
        }
        XCTAssertEqual(components.hour, 8)
        XCTAssertEqual(components.minute, 30)
    }

    func testDisabledPreferencesProduceNoPlans() {
        let context = LearningNotificationContext(
            profileID: ProfileID(),
            readPoolCount: 0,
            writePoolCount: 0,
            completedQuestCountToday: 2,
            hasPendingSyncFailure: true,
            weeklyAttentionCount: 10
        )

        XCTAssertTrue(
            AppleLearningNotificationPlanBuilder.plans(
                preferences: .disabled,
                context: context,
                calendar: Calendar(identifier: .gregorian)
            ).isEmpty
        )
    }

    func testOneShotUpdatesWaitUntilQuietHoursEnd() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let now = try XCTUnwrap(
            calendar.date(from: DateComponents(year: 2026, month: 7, day: 12, hour: 21))
        )
        let preferences = LearningNotificationPreferences(
            syncFailureEnabled: true,
            quietHours: NotificationQuietHours(
                startsAt: LearningReminderTime(hour: 20, minute: 0),
                endsAt: LearningReminderTime(hour: 8, minute: 30)
            )
        )
        let context = LearningNotificationContext(
            profileID: ProfileID(),
            readPoolCount: 8,
            writePoolCount: 8,
            completedQuestCountToday: 0,
            hasPendingSyncFailure: true,
            weeklyAttentionCount: 0
        )

        let plan = AppleLearningNotificationPlanBuilder.plans(
            preferences: preferences,
            context: context,
            calendar: calendar,
            now: now
        ).first

        guard case .after(let seconds) = plan?.trigger else {
            return XCTFail("Expected a delayed one-shot notification")
        }
        XCTAssertEqual(seconds, 11.5 * 60 * 60, accuracy: 1)
    }
}
