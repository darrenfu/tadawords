import Foundation
import SwiftUI

/// Framework-neutral presentation data for the shared child and guardian
/// quest calendar. Domain repositories remain the only source of counts.
public struct TadaQuestMonthCalendarData: Equatable, Sendable {
    public let year: Int
    public let month: Int
    public let questCountByDay: [Int: Int]
    public let todayDay: Int?

    public init(
        year: Int,
        month: Int,
        questCountByDay: [Int: Int],
        todayDay: Int?
    ) {
        self.year = year
        self.month = month
        self.questCountByDay = questCountByDay.reduce(into: [:]) { result, entry in
            guard entry.key > 0, entry.value > 0 else { return }
            result[entry.key] = entry.value
        }
        self.todayDay = todayDay
    }
}

public enum TadaQuestCalendarLayout {
    /// Calendar slots ordered Sunday through Saturday. Nil values are the
    /// leading/trailing cells outside the requested month.
    public static func sundayFirstSlots(year: Int, month: Int) -> [Int?] {
        var calendar = Calendar(identifier: .gregorian)
        calendar.locale = Locale(identifier: "en_US")
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        calendar.firstWeekday = 1
        guard
            let firstDate = calendar.date(
                from: DateComponents(year: year, month: month, day: 1)
            ), let range = calendar.range(of: .day, in: .month, for: firstDate)
        else { return [] }

        let leadingBlankCount = calendar.component(.weekday, from: firstDate) - 1
        var slots = [Int?](repeating: nil, count: leadingBlankCount)
        slots.append(contentsOf: range.map(Optional.some))
        let trailingBlankCount = (7 - (slots.count % 7)) % 7
        slots.append(contentsOf: repeatElement(nil, count: trailingBlankCount))
        return slots
    }
}

public struct TadaQuestMonthCalendar: View {
    private static let weekdaySymbols = ["Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat"]

    private let data: TadaQuestMonthCalendarData
    private let accent: Color
    private let surface: Color
    private let foreground: Color

    @Environment(\.verticalSizeClass) private var verticalSizeClass

    public init(
        data: TadaQuestMonthCalendarData,
        accent: Color,
        surface: Color = .white,
        foreground: Color = .primary
    ) {
        self.data = data
        self.accent = accent
        self.surface = surface
        self.foreground = foreground
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: isCompactHeight ? 8 : 12) {
            Text(monthTitle)
                .font(
                    .system(
                        isCompactHeight ? .headline : .title2,
                        design: .rounded,
                        weight: .heavy
                    )
                )
                .foregroundStyle(foreground)
                .accessibilityAddTraits(.isHeader)

            LazyVGrid(columns: columns, spacing: isCompactHeight ? 4 : 8) {
                ForEach(Self.weekdaySymbols, id: \.self) { weekday in
                    Text(weekday)
                        .font(.system(.caption, design: .rounded, weight: .bold))
                        .foregroundStyle(foreground.opacity(0.58))
                        .frame(maxWidth: .infinity)
                        .accessibilityHidden(true)
                }

                ForEach(Array(calendarSlots.enumerated()), id: \.offset) { _, day in
                    if let day {
                        dayCell(day)
                    } else {
                        Color.clear
                            .frame(minHeight: cellHeight)
                            .accessibilityHidden(true)
                    }
                }
            }
        }
        .padding(isCompactHeight ? 12 : 18)
        .background(
            surface,
            in: RoundedRectangle(cornerRadius: 24, style: .continuous)
        )
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Quest calendar for \(monthTitle)")
    }

    private func dayCell(_ day: Int) -> some View {
        let count = data.questCountByDay[day, default: 0]
        let isToday = data.todayDay == day

        return VStack(spacing: 3) {
            Text("\(day)")
                .font(.system(.subheadline, design: .rounded, weight: isToday ? .heavy : .semibold))
                .foregroundStyle(foreground)
                .monospacedDigit()

            if count > 0 {
                Text(Self.badgeText(for: count) ?? "")
                    .font(.system(.caption2, design: .rounded, weight: .heavy))
                    .foregroundStyle(.white)
                    .monospacedDigit()
                    .padding(.horizontal, 7)
                    .padding(.vertical, 3)
                    .background(accent, in: Capsule())
            } else {
                Color.clear
                    .frame(height: 20)
                    .accessibilityHidden(true)
            }
        }
        .frame(maxWidth: .infinity, minHeight: cellHeight)
        .background(
            isToday ? accent.opacity(0.13) : Color.clear,
            in: RoundedRectangle(cornerRadius: 12, style: .continuous)
        )
        .overlay {
            if isToday {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .strokeBorder(accent.opacity(0.9), lineWidth: 2)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityLabel(day: day, count: count, isToday: isToday))
    }

    private var columns: [GridItem] {
        Array(
            repeating: GridItem(.flexible(minimum: 38), spacing: 6),
            count: 7
        )
    }

    private var isCompactHeight: Bool {
        verticalSizeClass == .compact
    }

    private var cellHeight: CGFloat {
        isCompactHeight ? 38 : 48
    }

    private var calendarSlots: [Int?] {
        TadaQuestCalendarLayout.sundayFirstSlots(
            year: data.year,
            month: data.month
        )
    }

    private var monthTitle: String {
        guard
            let date = calendar.date(
                from: DateComponents(year: data.year, month: data.month, day: 1)
            )
        else {
            return "Month \(data.month), \(data.year)"
        }
        return Self.monthFormatter.string(from: date)
    }

    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.locale = Locale(identifier: "en_US")
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        calendar.firstWeekday = 1
        return calendar
    }

    private func accessibilityLabel(day: Int, count: Int, isToday: Bool) -> String {
        let dateDescription = "\(monthTitle) \(day)"
        let todayDescription = isToday ? ", today" : ""
        let questDescription: String
        switch count {
        case 0:
            questDescription = "no quests completed"
        case 1:
            questDescription = "1 quest completed"
        default:
            questDescription = "\(count) quests completed"
        }
        return "\(dateDescription)\(todayDescription), \(questDescription)"
    }

    /// Exact counts avoid hiding enthusiastic Practice Again runs. Zero has
    /// no badge, keeping uncompleted days visually quiet.
    public static func badgeText(for count: Int) -> String? {
        count > 0 ? String(count) : nil
    }

    private static let monthFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "LLLL yyyy"
        return formatter
    }()
}
