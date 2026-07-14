import SwiftUI
import TadaWordsDesignSystem
import TadaWordsDomain

struct GuardianTodayView: View {
    let snapshot: GuardianDashboardSnapshot
    let onLock: () -> Void
    let onQuickAdd: () -> Void
    let onOpenPool: (LearningMode) -> Void
    let onOpenSettings: () -> Void
    let onOpenProfiles: () -> Void
    let onOpenReports: () -> Void
    let onOpenFamilySync: () -> Void
    let syncState: GuardianSyncState

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: GuardianPrimitiveTokens.Spacing.large) {
                header
                profileCard
                todayStatusSection
                poolSection
                quickAddButton
                needsAttentionSection
                questCalendarSection
                reportsButton
                familySyncButton
                settingsButton
            }
            .frame(maxWidth: 960, alignment: .leading)
            .padding(.horizontal, GuardianPrimitiveTokens.Spacing.medium)
            .padding(.vertical, GuardianPrimitiveTokens.Spacing.large)
            .frame(maxWidth: .infinity)
        }
        .scrollIndicators(.hidden)
    }

    private var questCalendarSection: some View {
        VStack(alignment: .leading, spacing: GuardianPrimitiveTokens.Spacing.medium) {
            Text("Quest Calendar")
                .font(.system(.title3, design: .rounded, weight: .bold))

            TadaQuestMonthCalendar(
                data: calendarPresentationData,
                accent: GuardianSemanticTokens.primary,
                surface: GuardianSemanticTokens.surface,
                foreground: GuardianSemanticTokens.foreground
            )
        }
    }

    private var calendarPresentationData: TadaQuestMonthCalendarData {
        let summary = snapshot.questCalendar
        let counts = Dictionary(
            uniqueKeysWithValues: summary.completionCountByDay.map { day, count in
                (day.day, count)
            }
        )
        let todayDay =
            summary.month.year == snapshot.today.year
                && summary.month.month == snapshot.today.month
            ? snapshot.today.day
            : nil
        return TadaQuestMonthCalendarData(
            year: summary.month.year,
            month: summary.month.month,
            questCountByDay: counts,
            todayDay: todayDay
        )
    }

    private var header: some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 3) {
                Text("Guardian")
                    .font(.system(.caption, design: .rounded, weight: .bold))
                    .foregroundStyle(GuardianSemanticTokens.primary)
                Text("Today")
                    .font(.system(.largeTitle, design: .rounded, weight: .bold))
            }

            Spacer()

            Button(action: onLock) {
                Label("Lock", systemImage: "lock.fill")
                    .font(.system(.subheadline, design: .rounded, weight: .semibold))
            }
            .buttonStyle(.bordered)
            .tint(GuardianSemanticTokens.secondaryForeground)
            .accessibilityHint("Returns to the Parent Gate")
        }
    }

    private var profileCard: some View {
        Button(action: onOpenProfiles) {
            GuardianCard {
                HStack(spacing: GuardianPrimitiveTokens.Spacing.medium) {
                    ZStack {
                        Circle()
                            .fill(GuardianSemanticTokens.primary.opacity(0.12))
                        GuardianProfileAvatarView(avatar: snapshot.profile.avatar)
                            .padding(8)
                    }
                    .frame(width: 72, height: 72)
                    .accessibilityHidden(true)

                    VStack(alignment: .leading, spacing: 4) {
                        Text(snapshot.profile.displayName)
                            .font(.system(.title2, design: .rounded, weight: .bold))
                        Text(profileDetails)
                            .font(.system(.subheadline, design: .rounded, weight: .medium))
                            .foregroundStyle(GuardianSemanticTokens.secondaryForeground)
                            .lineLimit(2)
                    }

                    Spacer()

                    Image(systemName: "person.crop.circle.badge.checkmark")
                        .font(.system(.title2, design: .rounded, weight: .semibold))
                        .foregroundStyle(GuardianSemanticTokens.success)
                        .accessibilityLabel("Active child profile")
                }
            }
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
        .accessibilityHint("Opens child profile management")
    }

    private var profileDetails: String {
        let age = snapshot.profile.ageYears.map { "Age \($0) · " } ?? ""
        return
            "\(age)\(snapshot.profile.schoolGrade.displayName) · \(snapshot.profile.selectedWorld.displayName)"
    }

    private var todayStatusSection: some View {
        GuardianCard {
            VStack(alignment: .leading, spacing: GuardianPrimitiveTokens.Spacing.medium) {
                HStack {
                    Text("Today’s progress")
                        .font(.system(.title3, design: .rounded, weight: .bold))
                    Spacer()
                    Label(
                        syncState.title,
                        systemImage: "externaldrive.fill.badge.checkmark"
                    )
                    .font(.system(.caption, design: .rounded, weight: .semibold))
                    .foregroundStyle(GuardianSemanticTokens.secondaryForeground)
                }

                ViewThatFits(in: .horizontal) {
                    HStack(spacing: GuardianPrimitiveTokens.Spacing.medium) {
                        todayRoute(.read)
                        todayRoute(.write)
                    }
                    VStack(spacing: GuardianPrimitiveTokens.Spacing.medium) {
                        todayRoute(.read)
                        todayRoute(.write)
                    }
                }

                Text(
                    "\(snapshot.todaySummary.completedQuestCount) quests · \(snapshot.todaySummary.totalPoints) points · \(snapshot.todaySummary.totalStars) stars"
                )
                .font(.system(.subheadline, design: .rounded, weight: .bold))
                .monospacedDigit()
                .foregroundStyle(GuardianSemanticTokens.primary)
            }
        }
    }

    private func todayRoute(_ mode: LearningMode) -> some View {
        let route = snapshot.todaySummary.route(mode)
        return VStack(alignment: .leading, spacing: 5) {
            HStack {
                GuardianModeBadge(mode: mode)
                Spacer()
                Image(systemName: route.completedToday ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(
                        route.completedToday
                            ? GuardianSemanticTokens.success
                            : GuardianSemanticTokens.secondaryForeground
                    )
            }
            Text(
                "\(route.newWordsAddedToday) added today · \(route.waitingPoolCount) in pool · \(route.dueReviewCount) due"
            )
            .font(.system(.caption, design: .rounded, weight: .medium))
            .foregroundStyle(GuardianSemanticTokens.secondaryForeground)
            if let points = route.points, let stars = route.stars {
                Text("\(points) points · \(stars.count) stars")
                    .font(.system(.subheadline, design: .rounded, weight: .bold))
                    .monospacedDigit()
            } else {
                Text("Today’s Quest not finished")
                    .font(.system(.subheadline, design: .rounded, weight: .semibold))
            }
        }
        .padding(GuardianPrimitiveTokens.Spacing.medium)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            GuardianSemanticTokens.background,
            in: RoundedRectangle(
                cornerRadius: GuardianPrimitiveTokens.Radius.medium,
                style: .continuous
            )
        )
    }

    private var poolSection: some View {
        VStack(alignment: .leading, spacing: GuardianPrimitiveTokens.Spacing.medium) {
            Text("Word pools")
                .font(.system(.title3, design: .rounded, weight: .bold))

            ViewThatFits(in: .horizontal) {
                HStack(spacing: GuardianPrimitiveTokens.Spacing.medium) {
                    poolCards
                }

                VStack(spacing: GuardianPrimitiveTokens.Spacing.medium) {
                    poolCards
                }
            }
        }
    }

    @ViewBuilder
    private var poolCards: some View {
        GuardianPoolSummaryCard(
            mode: .read,
            count: snapshot.readPool.count,
            routeSettings: snapshot.practiceSettings.read,
            onOpen: { onOpenPool(.read) }
        )
        GuardianPoolSummaryCard(
            mode: .write,
            count: snapshot.writePool.count,
            routeSettings: snapshot.practiceSettings.write,
            onOpen: { onOpenPool(.write) }
        )
    }

    private var quickAddButton: some View {
        Button(action: onQuickAdd) {
            HStack(spacing: GuardianPrimitiveTokens.Spacing.medium) {
                Image(systemName: "plus.circle.fill")
                    .font(.system(.title2, design: .rounded, weight: .bold))
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Manage Words")
                        .font(.system(.headline, design: .rounded, weight: .bold))
                    Text("Type or scan this week’s school list")
                        .font(.system(.subheadline, design: .rounded, weight: .medium))
                        .opacity(0.84)
                }
                Spacer()
                Image(systemName: "chevron.right")
                    .accessibilityHidden(true)
            }
        }
        .buttonStyle(GuardianPrimaryButtonStyle())
        .accessibilityElement(children: .combine)
        .accessibilityHint("Opens Read and Write word management")
    }

    private var needsAttentionSection: some View {
        GuardianCard {
            VStack(alignment: .leading, spacing: GuardianPrimitiveTokens.Spacing.medium) {
                HStack {
                    Text("Needs Attention")
                        .font(.system(.title3, design: .rounded, weight: .bold))
                    Spacer()
                    Text("\(snapshot.needsAttention.count)")
                        .font(.system(.subheadline, design: .rounded, weight: .bold))
                        .monospacedDigit()
                        .foregroundStyle(GuardianSemanticTokens.primary)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .background(GuardianSemanticTokens.primary.opacity(0.10), in: Capsule())
                        .accessibilityLabel("\(snapshot.needsAttention.count) words")
                }

                if snapshot.needsAttention.isEmpty {
                    Label(
                        "Nothing needs extra attention today.", systemImage: "checkmark.circle.fill"
                    )
                    .font(.system(.body, design: .rounded, weight: .medium))
                    .foregroundStyle(GuardianSemanticTokens.success)
                } else {
                    ForEach(Array(snapshot.needsAttention.prefix(5))) { item in
                        GuardianAttentionRow(item: item)
                    }
                }
            }
        }
    }

    private var settingsButton: some View {
        Button(action: onOpenSettings) {
            HStack {
                Label("Practice settings", systemImage: "slider.horizontal.3")
                    .font(.system(.headline, design: .rounded, weight: .semibold))
                Spacer()
                VStack(alignment: .trailing, spacing: 2) {
                    Text(snapshot.practiceSettings.read.guardianSummary(prefix: "Read"))
                    Text(snapshot.practiceSettings.write.guardianSummary(prefix: "Write"))
                }
                .font(.system(.caption, design: .rounded, weight: .medium))
                .foregroundStyle(GuardianSemanticTokens.secondaryForeground)
                .monospacedDigit()
                Image(systemName: "chevron.right")
                    .foregroundStyle(GuardianSemanticTokens.secondaryForeground)
                    .accessibilityHidden(true)
            }
            .padding(GuardianPrimitiveTokens.Spacing.medium)
            .background(
                GuardianSemanticTokens.surface,
                in: RoundedRectangle(
                    cornerRadius: GuardianPrimitiveTokens.Radius.medium,
                    style: .continuous
                ))
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
        .accessibilityHint("Changes word counts, order, and Rescue timers")
    }

    private var reportsButton: some View {
        Button(action: onOpenReports) {
            HStack {
                Label("Learning reports", systemImage: "chart.line.uptrend.xyaxis")
                    .font(.system(.headline, design: .rounded, weight: .semibold))
                Spacer()
                Text("7 and 30 days")
                    .font(.system(.caption, design: .rounded, weight: .medium))
                    .foregroundStyle(GuardianSemanticTokens.secondaryForeground)
                Image(systemName: "chevron.right")
                    .foregroundStyle(GuardianSemanticTokens.secondaryForeground)
            }
            .padding(GuardianPrimitiveTokens.Spacing.medium)
            .background(
                GuardianSemanticTokens.surface,
                in: RoundedRectangle(
                    cornerRadius: GuardianPrimitiveTokens.Radius.medium,
                    style: .continuous
                )
            )
        }
        .buttonStyle(.plain)
        .frame(minHeight: 44)
        .accessibilityHint("Opens accuracy, timing, word details, corrections, and CSV export")
    }

    private var familySyncButton: some View {
        Button(action: onOpenFamilySync) {
            HStack {
                Label(familySyncControlTitle, systemImage: familySyncControlSymbol)
                    .font(.system(.headline, design: .rounded, weight: .semibold))
                Spacer()
                Text(syncState.title)
                    .font(.system(.caption, design: .rounded, weight: .medium))
                    .foregroundStyle(GuardianSemanticTokens.secondaryForeground)
                Image(systemName: "chevron.right")
                    .foregroundStyle(GuardianSemanticTokens.secondaryForeground)
            }
            .padding(GuardianPrimitiveTokens.Spacing.medium)
            .background(
                GuardianSemanticTokens.surface,
                in: RoundedRectangle(
                    cornerRadius: GuardianPrimitiveTokens.Radius.medium,
                    style: .continuous
                )
            )
        }
        .buttonStyle(.plain)
        .frame(minHeight: 44)
        .accessibilityHint(familySyncAccessibilityHint)
    }

    private var familySyncAccessibilityHint: String {
        switch syncState {
        case .thisDeviceOnly:
            "Opens storage details. Learning data is saved on this device."
        case .off:
            "Opens the parent control for optional iCloud family sync."
        case .upToDate, .pending, .failed:
            "Opens iCloud sync and family invitation controls."
        }
    }

    private var familySyncControlTitle: String {
        syncState == .thisDeviceOnly ? "Device storage" : "Family sync"
    }

    private var familySyncControlSymbol: String {
        syncState == .thisDeviceOnly
            ? "externaldrive.fill"
            : "person.2.badge.gearshape.fill"
    }
}

private struct GuardianPoolSummaryCard: View {
    let mode: LearningMode
    let count: Int
    let routeSettings: LearningRouteSettings
    let onOpen: () -> Void

    var body: some View {
        Button(action: onOpen) {
            GuardianCard {
                VStack(alignment: .leading, spacing: GuardianPrimitiveTokens.Spacing.medium) {
                    HStack {
                        GuardianModeBadge(mode: mode, includesPoolSuffix: true)
                        Spacer()
                        Image(systemName: "chevron.right")
                            .foregroundStyle(GuardianSemanticTokens.secondaryForeground)
                            .accessibilityHidden(true)
                    }

                    HStack(alignment: .firstTextBaseline, spacing: 7) {
                        Text("\(count)")
                            .font(.system(size: 38, weight: .bold, design: .rounded))
                            .monospacedDigit()
                        Text(count == 1 ? "word" : "words")
                            .font(.system(.body, design: .rounded, weight: .medium))
                            .foregroundStyle(GuardianSemanticTokens.secondaryForeground)
                    }

                    Label(
                        routeSettings.guardianSummary(),
                        systemImage: "calendar"
                    )
                    .font(.system(.subheadline, design: .rounded, weight: .medium))
                    .foregroundStyle(GuardianSemanticTokens.secondaryForeground)
                }
            }
        }
        .buttonStyle(.plain)
        .frame(minWidth: 280, maxWidth: .infinity)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(mode.guardianTitle) Pool, \(count) words")
        .accessibilityValue(routeSettings.guardianAccessibilitySummary)
        .accessibilityHint("Shows only the \(mode.guardianTitle) Pool")
    }
}

extension LearningRouteSettings {
    fileprivate func guardianSummary(prefix: String? = nil) -> String {
        let summary = "New \(newWordLimit) · Review \(reviewWordLimit)"
        guard let prefix else { return summary }
        return "\(prefix): \(summary)"
    }

    fileprivate var guardianAccessibilitySummary: String {
        "\(newWordLimit) new words and \(reviewWordLimit) review words"
    }
}

private struct GuardianAttentionRow: View {
    let item: GuardianAttentionItem

    var body: some View {
        HStack(spacing: GuardianPrimitiveTokens.Spacing.medium) {
            Image(systemName: item.reason.symbol)
                .font(.system(.title3, design: .rounded, weight: .semibold))
                .foregroundStyle(GuardianPrimitiveTokens.ColorValue.orange)
                .frame(width: 30)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 2) {
                Text(item.prompt.displayText)
                    .font(.system(.headline, design: .rounded, weight: .bold))
                Text(item.reason.title)
                    .font(.system(.subheadline, design: .rounded, weight: .medium))
                    .foregroundStyle(GuardianSemanticTokens.secondaryForeground)
                Text(item.whyNow)
                    .font(.system(.caption, design: .rounded, weight: .medium))
                    .foregroundStyle(GuardianSemanticTokens.secondaryForeground)
            }

            Spacer()

            GuardianModeBadge(mode: item.prompt.learningMode)
        }
        .padding(.vertical, 3)
        .accessibilityElement(children: .combine)
    }
}

extension ProfileAvatar {
    var guardianPresentationSymbol: String {
        switch self {
        case .cartoonAnimal(let assetID):
            GuardianAnimalAvatar.option(for: assetID)?.symbol ?? "pawprint.fill"
        case .photo:
            "person.crop.circle.fill"
        case .treasure(_, let iconAssetID):
            iconAssetID
        }
    }
}
