import TadaWordsDesignSystem
import XCTest

@MainActor
final class QuestMonthCalendarPresentationTests: XCTestCase {
    func testBadgeShowsExactQuestCountAndLeavesZeroBlank() {
        XCTAssertNil(TadaQuestMonthCalendar.badgeText(for: 0))
        XCTAssertNil(TadaQuestMonthCalendar.badgeText(for: -1))
        XCTAssertEqual(TadaQuestMonthCalendar.badgeText(for: 1), "1")
        XCTAssertEqual(TadaQuestMonthCalendar.badgeText(for: 2), "2")
        XCTAssertEqual(TadaQuestMonthCalendar.badgeText(for: 3), "3")
        XCTAssertEqual(TadaQuestMonthCalendar.badgeText(for: 12), "12")
    }

    func testCalendarUsesSundayFirstUSLayoutAcrossMonthBoundary() {
        let slots = TadaQuestCalendarLayout.sundayFirstSlots(
            year: 2026,
            month: 7
        )

        XCTAssertEqual(Array(slots.prefix(3)), [nil, nil, nil])
        XCTAssertEqual(slots[3], 1)
        XCTAssertEqual(slots.compactMap { $0 }.first, 1)
        XCTAssertEqual(slots.compactMap { $0 }.last, 31)
        XCTAssertEqual(slots.count % 7, 0)
    }
}
