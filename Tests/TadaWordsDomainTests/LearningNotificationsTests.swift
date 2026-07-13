import Foundation
import XCTest

@testable import TadaWordsDomain

final class LearningNotificationsTests: XCTestCase {
    func testQuietHoursSupportOvernightAndDaytimeRanges() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let overnight = NotificationQuietHours(
            startsAt: LearningReminderTime(hour: 20, minute: 0),
            endsAt: LearningReminderTime(hour: 8, minute: 0)
        )
        let daytime = NotificationQuietHours(
            startsAt: LearningReminderTime(hour: 12, minute: 0),
            endsAt: LearningReminderTime(hour: 14, minute: 0)
        )

        XCTAssertTrue(overnight.contains(date(hour: 21), calendar: calendar))
        XCTAssertTrue(overnight.contains(date(hour: 7), calendar: calendar))
        XCTAssertFalse(overnight.contains(date(hour: 12), calendar: calendar))
        XCTAssertTrue(daytime.contains(date(hour: 13), calendar: calendar))
        XCTAssertFalse(daytime.contains(date(hour: 15), calendar: calendar))
    }

    func testNotificationCopyNeverLeaksProfileOrLearningDetails() {
        for kind in LearningNotificationKind.allCases {
            let combined =
                LearningNotificationPrivacyCopy.title(for: kind)
                + LearningNotificationPrivacyCopy.body(for: kind)
            XCTAssertFalse(combined.localizedCaseInsensitiveContains("My Kid"))
            XCTAssertFalse(combined.localizedCaseInsensitiveContains("score"))
            XCTAssertFalse(combined.localizedCaseInsensitiveContains("voiceprint"))
        }
    }

    func testPreferencesDefaultCompletelyDisabled() {
        XCTAssertFalse(LearningNotificationPreferences.disabled.hasEnabledNotifications)
    }

    private func date(hour: Int) -> Date {
        Date(timeIntervalSince1970: TimeInterval(hour * 3_600))
    }
}
