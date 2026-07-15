import SwiftUI
import TadaWordsDesignSystem
import TadaWordsDomain

struct GuardianTodayView: View {
    let snapshot: GuardianDashboardSnapshot
    let onLock: () -> Void
    let onOpenProfiles: () -> Void
    let onOpenWordsAndPractice: () -> Void
    let onOpenProgressAndPerformance: () -> Void
    let onOpenAppAndFamily: () -> Void
    let syncState: GuardianSyncState

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: GuardianPrimitiveTokens.Spacing.large) {
                header
                selectedKidCard

                LazyVGrid(
                    columns: [
                        GridItem(
                            .adaptive(minimum: 250, maximum: 360),
                            spacing: GuardianPrimitiveTokens.Spacing.medium,
                            alignment: .top
                        )
                    ],
                    alignment: .leading,
                    spacing: GuardianPrimitiveTokens.Spacing.medium
                ) {
                    GuardianNavigationTile(
                        title: "Words & Practice",
                        summary: wordPoolSummary,
                        symbol: "text.book.closed.fill",
                        tint: GuardianPrimitiveTokens.ColorValue.indigo,
                        accessibilityIdentifier: "guardian.home.words-and-practice",
                        action: onOpenWordsAndPractice
                    )
                    GuardianNavigationTile(
                        title: "Progress & Performance",
                        summary: progressSummary,
                        symbol: "chart.line.uptrend.xyaxis",
                        tint: GuardianPrimitiveTokens.ColorValue.teal,
                        accessibilityIdentifier: "guardian.home.progress-and-performance",
                        action: onOpenProgressAndPerformance
                    )
                    GuardianNavigationTile(
                        title: "App & Family",
                        summary: syncState.title,
                        symbol: "gearshape.2.fill",
                        tint: GuardianPrimitiveTokens.ColorValue.orange,
                        accessibilityIdentifier: "guardian.home.app-and-family",
                        action: onOpenAppAndFamily
                    )
                }
            }
            .frame(maxWidth: 960, alignment: .leading)
            .padding(.horizontal, GuardianPrimitiveTokens.Spacing.medium)
            .padding(.vertical, GuardianPrimitiveTokens.Spacing.large)
            .frame(maxWidth: .infinity)
        }
        .scrollIndicators(.hidden)
    }

    private var header: some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 3) {
                Text("Parent Home")
                    .font(.system(.largeTitle, design: .rounded, weight: .bold))
                Text("Everything you need, in three simple places.")
                    .font(.system(.subheadline, design: .rounded, weight: .medium))
                    .foregroundStyle(GuardianSemanticTokens.secondaryForeground)
            }

            Spacer()

            Button(action: onLock) {
                Label("Lock", systemImage: "lock.fill")
                    .font(.system(.subheadline, design: .rounded, weight: .semibold))
            }
            .buttonStyle(.bordered)
            .tint(GuardianSemanticTokens.secondaryForeground)
            .accessibilityHint("Locks parent tools and returns to child profiles")
            .accessibilityIdentifier("guardian.home.lock")
        }
    }

    private var selectedKidCard: some View {
        Button(action: onOpenProfiles) {
            GuardianCard {
                HStack(spacing: GuardianPrimitiveTokens.Spacing.medium) {
                    GuardianProfileAvatarBadge(profile: snapshot.profile, size: 72)

                    VStack(alignment: .leading, spacing: 4) {
                        Text("Kids")
                            .font(.system(.caption, design: .rounded, weight: .bold))
                            .foregroundStyle(GuardianSemanticTokens.primary)
                        Text(snapshot.profile.displayName)
                            .font(.system(.title2, design: .rounded, weight: .bold))
                        Text(snapshot.profile.guardianDetails)
                            .font(.system(.subheadline, design: .rounded, weight: .medium))
                            .foregroundStyle(GuardianSemanticTokens.secondaryForeground)
                            .lineLimit(2)
                    }

                    Spacer()

                    Image(systemName: "chevron.right")
                        .font(.system(.headline, design: .rounded, weight: .bold))
                        .foregroundStyle(GuardianSemanticTokens.secondaryForeground)
                        .accessibilityHidden(true)
                }
            }
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
        .accessibilityHint("Opens Kid profile management")
        .accessibilityIdentifier("guardian.home.selected-kid")
    }

    private var wordPoolSummary: String {
        "\(snapshot.readPool.count) Read · \(snapshot.writePool.count) Write words"
    }

    private var progressSummary: String {
        let quests = snapshot.todaySummary.completedQuestCount
        let attention = snapshot.needsAttention.count
        return "\(quests) of 2 quests today · \(attention) need attention"
    }
}

struct GuardianWordsAndPracticeView: View {
    let snapshot: GuardianDashboardSnapshot
    let onBack: () -> Void
    let onManageWords: () -> Void
    let onOpenPresets: () -> Void
    let onOpenPracticePlan: () -> Void

    var body: some View {
        GuardianParentHubLayout(
            title: "Words & Practice",
            profile: snapshot.profile,
            onBack: onBack
        ) {
            GuardianNavigationTile(
                title: "Manage Words",
                summary: wordManagementSummary,
                symbol: "text.badge.plus",
                tint: GuardianPrimitiveTokens.ColorValue.indigo,
                accessibilityIdentifier: "guardian.words.manage",
                action: onManageWords
            )
            GuardianNavigationTile(
                title: "Preset Word Lists",
                summary: "Browse by age, grade, and category",
                symbol: "books.vertical.fill",
                tint: GuardianPrimitiveTokens.ColorValue.blue,
                accessibilityIdentifier: "guardian.words.presets",
                action: onOpenPresets
            )
            GuardianNavigationTile(
                title: "Practice Plan",
                summary: practicePlanSummary,
                symbol: "calendar.badge.clock",
                tint: GuardianPrimitiveTokens.ColorValue.teal,
                accessibilityIdentifier: "guardian.words.practice-plan",
                action: onOpenPracticePlan
            )
        }
    }

    private var practicePlanSummary: String {
        let read = snapshot.practiceSettings.read
        let write = snapshot.practiceSettings.write
        return "Read \(read.newWordLimit) new · Write \(write.newWordLimit) new"
    }

    private var wordManagementSummary: String {
        let readCount = snapshot.readPool.count
        let writeCount = snapshot.writePool.count
        return "Type, scan, search, or remove · \(readCount) Read · \(writeCount) Write"
    }
}

struct GuardianProgressAndPerformanceView: View {
    let snapshot: GuardianDashboardSnapshot
    let syncState: GuardianSyncState
    let onBack: () -> Void
    let onOpenReports: () -> Void

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: GuardianPrimitiveTokens.Spacing.large) {
                GuardianNavigationHeader(title: "Progress & Performance", onBack: onBack)
                GuardianParentContextHeader(profile: snapshot.profile)
                todayStatusSection
                needsAttentionSection
                questCalendarSection
                GuardianNavigationTile(
                    title: "Learning Report",
                    summary: "Accuracy, speed, word details, and corrections",
                    symbol: "chart.bar.xaxis",
                    tint: GuardianPrimitiveTokens.ColorValue.teal,
                    accessibilityIdentifier: "guardian.progress.reports",
                    action: onOpenReports
                )
            }
            .frame(maxWidth: 880, alignment: .leading)
            .padding(.horizontal, GuardianPrimitiveTokens.Spacing.medium)
            .padding(.vertical, GuardianPrimitiveTokens.Spacing.large)
            .frame(maxWidth: .infinity)
        }
        .scrollIndicators(.hidden)
    }

    private var todayStatusSection: some View {
        GuardianCard {
            VStack(alignment: .leading, spacing: GuardianPrimitiveTokens.Spacing.medium) {
                HStack {
                    Text("Today’s progress")
                        .font(.system(.title3, design: .rounded, weight: .bold))
                    Spacer()
                    Label(syncState.title, systemImage: "externaldrive.fill.badge.checkmark")
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
                        "Nothing needs extra attention today.",
                        systemImage: "checkmark.circle.fill"
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
}

struct GuardianAppAndFamilyView: View {
    let snapshot: GuardianDashboardSnapshot
    let syncState: GuardianSyncState
    let onBack: () -> Void
    let onOpenSoundAndAccessibility: () -> Void
    let onOpenNotifications: () -> Void
    let onOpenFamilySync: () -> Void

    var body: some View {
        GuardianParentHubLayout(
            title: "App & Family",
            profile: snapshot.profile,
            onBack: onBack
        ) {
            GuardianNavigationTile(
                title: "Sound & Accessibility",
                summary: audioSummary,
                symbol: "speaker.wave.2.fill",
                tint: GuardianPrimitiveTokens.ColorValue.indigo,
                accessibilityIdentifier: "guardian.app.sound-accessibility",
                action: onOpenSoundAndAccessibility
            )
            GuardianNavigationTile(
                title: "Notifications",
                summary: snapshot.practiceSettings.notifications.hasEnabledNotifications
                    ? "Family reminders are on"
                    : "Family reminders are off",
                symbol: "bell.badge.fill",
                tint: GuardianPrimitiveTokens.ColorValue.orange,
                accessibilityIdentifier: "guardian.app.notifications",
                action: onOpenNotifications
            )
            GuardianNavigationTile(
                title: syncState == .thisDeviceOnly ? "Device Storage" : "Family Sync",
                summary: syncState.title,
                symbol: syncState == .thisDeviceOnly
                    ? "externaldrive.fill"
                    : "person.2.badge.gearshape.fill",
                tint: GuardianPrimitiveTokens.ColorValue.teal,
                accessibilityIdentifier: "guardian.app.sync",
                action: onOpenFamilySync
            )
        }
    }

    private var audioSummary: String {
        let audio = snapshot.practiceSettings.audio
        let music = audio.musicEnabled ? "Music on" : "Music off"
        let voice = audio.voiceEnabled ? "Voice on" : "Voice off"
        let usesLeftHandedControls =
            snapshot.practiceSettings.interface.leftHandedLayoutEnabled
        let hand = usesLeftHandedControls ? "Left-handed controls" : "Right-handed controls"
        return "\(music) · \(voice) · \(hand)"
    }
}

struct GuardianNavigationTile: View {
    let title: String
    let summary: String
    let symbol: String
    let tint: Color
    let accessibilityIdentifier: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            GuardianCard {
                HStack(spacing: GuardianPrimitiveTokens.Spacing.medium) {
                    Image(systemName: symbol)
                        .font(.system(.title2, design: .rounded, weight: .bold))
                        .foregroundStyle(tint)
                        .frame(width: 38)
                        .accessibilityHidden(true)

                    VStack(alignment: .leading, spacing: 4) {
                        Text(title)
                            .font(.system(.headline, design: .rounded, weight: .bold))
                            .foregroundStyle(GuardianSemanticTokens.foreground)
                        Text(summary)
                            .font(.system(.subheadline, design: .rounded, weight: .medium))
                            .foregroundStyle(GuardianSemanticTokens.secondaryForeground)
                            .multilineTextAlignment(.leading)
                            .lineLimit(2)
                    }

                    Spacer(minLength: GuardianPrimitiveTokens.Spacing.small)

                    Image(systemName: "chevron.right")
                        .font(.system(.subheadline, design: .rounded, weight: .bold))
                        .foregroundStyle(GuardianSemanticTokens.secondaryForeground)
                        .accessibilityHidden(true)
                }
                .frame(maxWidth: .infinity, minHeight: 72, alignment: .leading)
            }
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
        .accessibilityHint("Opens \(title)")
        .accessibilityIdentifier(accessibilityIdentifier)
    }
}

private struct GuardianParentHubLayout<Content: View>: View {
    let title: String
    let profile: KidProfile
    let onBack: () -> Void
    let content: Content

    init(
        title: String,
        profile: KidProfile,
        onBack: @escaping () -> Void,
        @ViewBuilder content: () -> Content
    ) {
        self.title = title
        self.profile = profile
        self.onBack = onBack
        self.content = content()
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: GuardianPrimitiveTokens.Spacing.large) {
                GuardianNavigationHeader(title: title, onBack: onBack)
                GuardianParentContextHeader(profile: profile)
                content
            }
            .frame(maxWidth: 880, alignment: .leading)
            .padding(.horizontal, GuardianPrimitiveTokens.Spacing.medium)
            .padding(.vertical, GuardianPrimitiveTokens.Spacing.large)
            .frame(maxWidth: .infinity)
        }
        .scrollIndicators(.hidden)
    }
}

private struct GuardianParentContextHeader: View {
    let profile: KidProfile

    var body: some View {
        HStack(spacing: GuardianPrimitiveTokens.Spacing.small) {
            GuardianProfileAvatarBadge(profile: profile, size: 44)
            VStack(alignment: .leading, spacing: 1) {
                Text(profile.displayName)
                    .font(.system(.headline, design: .rounded, weight: .bold))
                Text(profile.guardianDetails)
                    .font(.system(.caption, design: .rounded, weight: .medium))
                    .foregroundStyle(GuardianSemanticTokens.secondaryForeground)
                    .lineLimit(1)
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Settings for \(profile.displayName)")
    }
}

private struct GuardianProfileAvatarBadge: View {
    let profile: KidProfile
    let size: CGFloat

    var body: some View {
        ZStack {
            Circle()
                .fill(GuardianSemanticTokens.primary.opacity(0.12))
            GuardianProfileAvatarView(avatar: profile.avatar)
                .padding(size * 0.12)
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
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

extension KidProfile {
    fileprivate var guardianDetails: String {
        let age = ageYears.map { "Age \($0) · " } ?? ""
        return "\(age)\(schoolGrade.displayName) · \(selectedWorld.displayName)"
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
