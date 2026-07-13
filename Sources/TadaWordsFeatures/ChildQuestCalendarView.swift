import SwiftUI
import TadaWordsDesignSystem
import TadaWordsDomain

struct ChildQuestCalendarView: View {
    let profile: KidProfile?
    let summary: DailyQuestMonthSummary?
    let today: LocalDay
    let isLoading: Bool
    let loadFailed: Bool
    let theme: TadaWorldTheme
    let onRetry: () -> Void
    let onClose: () -> Void

    var body: some View {
        TadaWorldBackground(theme: theme, sceneStyle: .lobby) {
            VStack(spacing: 12) {
                header
                content
            }
            .padding(.horizontal, 22)
            .padding(.vertical, 14)
            .frame(maxWidth: 820, maxHeight: .infinity)
            .frame(maxWidth: .infinity)
        }
        .preferredColorScheme(.light)
    }

    private var header: some View {
        HStack(spacing: 14) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Quest Calendar")
                    .font(.system(.title, design: .rounded, weight: .heavy))
                if let profile {
                    Text("\(profile.displayName)’s completed quests")
                        .font(.system(.subheadline, design: .rounded, weight: .semibold))
                        .foregroundStyle(theme.ink.opacity(0.65))
                }
            }
            Spacer()
            Button(action: onClose) {
                Label("Close", systemImage: "xmark.circle.fill")
                    .font(.system(.headline, design: .rounded, weight: .bold))
            }
            .buttonStyle(
                TadaPrimaryButtonStyle(
                    fill: theme.surface,
                    foreground: theme.ink,
                    isCompact: true
                ))
        }
    }

    @ViewBuilder
    private var content: some View {
        if let summary {
            TadaQuestMonthCalendar(
                data: presentationData(for: summary),
                accent: theme.primary,
                surface: theme.surface.opacity(0.96),
                foreground: theme.ink
            )
        } else if loadFailed {
            TadaChildStatePanel(
                theme: theme,
                symbol: "calendar.badge.exclamationmark",
                title: "Calendar unavailable",
                message: "Your quest history is safe. Try loading it again."
            ) {
                Button("Try Again", action: onRetry)
                    .buttonStyle(TadaPrimaryButtonStyle(fill: theme.primary))
            }
        } else if isLoading {
            TadaChildStatePanel(
                theme: theme,
                symbol: "calendar",
                title: "Opening your calendar",
                message: "Loading completed quests…",
                showsProgress: true
            )
        } else {
            TadaChildStatePanel(
                theme: theme,
                symbol: "calendar",
                title: "No quests yet",
                message: "Complete a Read or Write quest to start your calendar."
            )
        }
    }

    private func presentationData(
        for summary: DailyQuestMonthSummary
    ) -> TadaQuestMonthCalendarData {
        let counts = Dictionary(
            uniqueKeysWithValues: summary.completionCountByDay.map { day, count in
                (day.day, count)
            }
        )
        let todayDay =
            summary.month.year == today.year && summary.month.month == today.month
            ? today.day
            : nil
        return TadaQuestMonthCalendarData(
            year: summary.month.year,
            month: summary.month.month,
            questCountByDay: counts,
            todayDay: todayDay
        )
    }
}
