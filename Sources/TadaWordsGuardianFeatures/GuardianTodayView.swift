import Foundation
import SwiftUI
import TadaWordsDesignSystem
import TadaWordsDomain

struct GuardianTodayView: View {
    let snapshot: GuardianDashboardSnapshot
    let family: GuardianFamilySnapshot
    let onBack: () -> Void
    let onSelectProfile: (KidProfile) -> Void
    let onEditProfile: (KidProfile) -> Void
    let onOpenWordsAndPractice: () -> Void
    let onOpenProgressAndPerformance: () -> Void
    let onOpenAppAndFamily: () -> Void
    let syncState: GuardianSyncState

    var body: some View {
        TadaWorldBackground(theme: theme, sceneStyle: .lobby) {
            ScrollView {
                VStack(alignment: .leading, spacing: TadaPrimitiveTokens.Spacing.medium) {
                    header
                    profileStrip

                    HStack(alignment: .top, spacing: TadaPrimitiveTokens.Spacing.small) {
                        GuardianHomeNavigationTile(
                            title: "Words",
                            summary: wordPoolSummary,
                            symbol: "text.book.closed.fill",
                            tint: theme.primary,
                            fill: theme.primary.opacity(0.15),
                            accessibilityIdentifier: "guardian.home.words-and-practice",
                            action: onOpenWordsAndPractice
                        )
                        GuardianHomeNavigationTile(
                            title: "Progress",
                            summary: progressSummary,
                            symbol: "chart.line.uptrend.xyaxis",
                            tint: theme.secondary,
                            fill: theme.secondary.opacity(0.16),
                            accessibilityIdentifier: "guardian.home.progress-and-performance",
                            action: onOpenProgressAndPerformance
                        )
                        GuardianHomeNavigationTile(
                            title: "App & Family",
                            summary: "All profiles",
                            symbol: "gearshape.2.fill",
                            tint: theme.accent,
                            fill: theme.accent.opacity(0.18),
                            accessibilityIdentifier: "guardian.home.app-and-family",
                            action: onOpenAppAndFamily
                        )
                    }
                }
                .frame(maxWidth: 1040, alignment: .leading)
                .guardianParentPageInsets()
                .frame(maxWidth: .infinity)
            }
            .scrollIndicators(.hidden)
        }
    }

    private var header: some View {
        GuardianNavigationHeader(
            title: "Parent Home",
            onBack: onBack,
            backAccessibilityIdentifier: "guardian.home.back"
        )
        .accessibilityHint("Returns to the previous page")
    }

    private var profileStrip: some View {
        VStack(alignment: .leading, spacing: TadaPrimitiveTokens.Spacing.small) {
            Label("Kids", systemImage: "person.2.fill")
                .font(.system(.headline, design: .rounded, weight: .bold))

            ScrollView(.horizontal) {
                HStack(spacing: TadaPrimitiveTokens.Spacing.small) {
                    ForEach(family.profiles, id: \.id) { profile in
                        GuardianHomeProfileChip(
                            profile: profile,
                            isSelected: profile.id == snapshot.profile.id,
                            tint: profile.id == snapshot.profile.id
                                ? theme.primary
                                : theme.ink.opacity(0.58),
                            onSelect: { onSelectProfile(profile) },
                            onEdit: { onEditProfile(profile) }
                        )
                    }
                }
                .padding(.top, 6)
                .padding(.trailing, 6)
            }
            .scrollIndicators(.hidden)
        }
        .padding(TadaPrimitiveTokens.Spacing.medium)
        .background(
            theme.surface.opacity(0.94),
            in: RoundedRectangle(
                cornerRadius: TadaPrimitiveTokens.Radius.large,
                style: .continuous
            )
        )
    }

    private var wordPoolSummary: String {
        "\(snapshot.readPool.count) Read · \(snapshot.writePool.count) Write"
    }

    private var progressSummary: String {
        let quests = snapshot.todaySummary.completedQuestCount
        let attention = snapshot.needsAttention.count
        return "\(quests) quests · \(attention) to review"
    }

    private var theme: TadaWorldTheme {
        switch snapshot.profile.selectedWorld {
        case .moonpetalKingdom:
            .moonpetal
        case .buildItBay:
            .buildItBay
        case .pawsAndPines:
            .pawsAndPines
        case .dinoDiscovery:
            .dinoDiscovery
        case .firehouseHeroes:
            .firehouseHeroes
        case .brickworkCity:
            .brickworkCity
        case .frostlightWorld:
            .frostlightWorld
        case .coasterCarnival:
            .coasterCarnival
        }
    }
}

private struct GuardianHomeProfileChip: View {
    let profile: KidProfile
    let isSelected: Bool
    let tint: Color
    let onSelect: () -> Void
    let onEdit: () -> Void

    var body: some View {
        ZStack(alignment: .topTrailing) {
            Button(action: onSelect) {
                VStack(spacing: 5) {
                    GuardianProfileAvatarBadge(
                        profile: profile,
                        size: 48,
                        tint: tint
                    )
                    Text(profile.displayName)
                        .font(.system(.subheadline, design: .rounded, weight: .bold))
                        .lineLimit(1)
                }
                .frame(width: 104, height: 82)
                .foregroundStyle(GuardianSemanticTokens.foreground)
                .background(
                    isSelected ? tint.opacity(0.14) : Color.clear,
                    in: RoundedRectangle(
                        cornerRadius: TadaPrimitiveTokens.Radius.medium,
                        style: .continuous
                    )
                )
                .overlay {
                    RoundedRectangle(
                        cornerRadius: TadaPrimitiveTokens.Radius.medium,
                        style: .continuous
                    )
                    .strokeBorder(
                        isSelected
                            ? tint
                            : GuardianSemanticTokens.foreground.opacity(0.12),
                        lineWidth: isSelected ? 2.5 : 1
                    )
                }
            }
            .buttonStyle(.plain)
            .disabled(isSelected)
            .accessibilityLabel(
                isSelected
                    ? "\(profile.displayName), currently selected"
                    : "Switch to \(profile.displayName)"
            )
            .accessibilityIdentifier("guardian.home.profile.\(profile.id).select")

            Button(action: onEdit) {
                Image(systemName: "pencil.circle.fill")
                    .font(.system(size: 24, weight: .bold))
                    .symbolRenderingMode(.palette)
                    .foregroundStyle(.white, tint)
                    .frame(
                        width: TadaPrimitiveTokens.TouchTarget.minimum,
                        height: TadaPrimitiveTokens.TouchTarget.minimum
                    )
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .offset(x: 8, y: -8)
            .accessibilityLabel("Edit \(profile.displayName)")
            .accessibilityIdentifier("guardian.home.profile.\(profile.id).edit")
        }
    }
}

private struct GuardianHomeNavigationTile: View {
    let title: String
    let summary: String
    let symbol: String
    let tint: Color
    let fill: Color
    let accessibilityIdentifier: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 6) {
                Image(systemName: symbol)
                    .font(.system(.title, design: .rounded, weight: .bold))
                    .foregroundStyle(tint)
                    .accessibilityHidden(true)

                Spacer(minLength: 2)

                Text(title)
                    .font(.system(.headline, design: .rounded, weight: .bold))
                    .foregroundStyle(GuardianSemanticTokens.foreground)
                    .lineLimit(2)
                    .minimumScaleFactor(0.78)

                Text(summary)
                    .font(.system(.caption, design: .rounded, weight: .semibold))
                    .foregroundStyle(GuardianSemanticTokens.secondaryForeground)
                    .lineLimit(1)
                    .minimumScaleFactor(0.72)
            }
            .frame(maxWidth: .infinity, minHeight: 126, alignment: .leading)
            .padding(TadaPrimitiveTokens.Spacing.medium)
            .background(
                fill,
                in: RoundedRectangle(
                    cornerRadius: TadaPrimitiveTokens.Radius.large,
                    style: .continuous
                )
            )
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
        .accessibilityHint("Opens \(title)")
        .accessibilityIdentifier(accessibilityIdentifier)
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
            .guardianParentPageInsets()
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

enum GuardianAppAndFamilyFeature: CaseIterable, Equatable {
    case soundAndAccessibility
    case notifications
    case speechAndMicrophone
    case familySync
    case thirdPartyNotices

    var title: String {
        switch self {
        case .soundAndAccessibility:
            "Sound & Accessibility"
        case .notifications:
            "Notifications"
        case .speechAndMicrophone:
            "Speech & Microphone"
        case .familySync:
            "Family Sync"
        case .thirdPartyNotices:
            "Third-Party Notices"
        }
    }

    var accessibilityIdentifier: String {
        switch self {
        case .soundAndAccessibility:
            "guardian.app.sound-accessibility"
        case .notifications:
            "guardian.app.notifications"
        case .speechAndMicrophone:
            "guardian.app.speech-permissions"
        case .familySync:
            "guardian.app.sync"
        case .thirdPartyNotices:
            "guardian.app.third-party-notices"
        }
    }
}

struct GuardianAppAndFamilyView: View {
    let snapshot: GuardianDashboardSnapshot
    let syncState: GuardianSyncState
    let onBack: () -> Void
    let onOpenSoundAndAccessibility: () -> Void
    let onOpenNotifications: () -> Void
    let speechPermissionState: SpeechPermissionState
    let onOpenSpeechPermissions: () -> Void
    let onOpenFamilySync: () -> Void
    let onOpenThirdPartyNotices: () -> Void

    var body: some View {
        GuardianParentHubLayout(
            title: "App & Family",
            onBack: onBack
        ) {
            LazyVGrid(
                columns: [
                    GridItem(
                        .adaptive(minimum: 150, maximum: 260),
                        spacing: GuardianPrimitiveTokens.Spacing.small
                    )
                ],
                alignment: .leading,
                spacing: GuardianPrimitiveTokens.Spacing.small
            ) {
                GuardianAppNavigationTile(
                    title: GuardianAppAndFamilyFeature.soundAndAccessibility.title,
                    summary: audioSummary,
                    symbol: "speaker.wave.2.fill",
                    tint: GuardianPrimitiveTokens.ColorValue.indigo,
                    accessibilityIdentifier: GuardianAppAndFamilyFeature
                        .soundAndAccessibility.accessibilityIdentifier,
                    action: onOpenSoundAndAccessibility
                )
                GuardianAppNavigationTile(
                    title: GuardianAppAndFamilyFeature.notifications.title,
                    summary: snapshot.practiceSettings.notifications
                        .hasEnabledNotifications
                        ? "Family reminders are on"
                        : "Family reminders are off",
                    symbol: "bell.badge.fill",
                    tint: GuardianPrimitiveTokens.ColorValue.orange,
                    accessibilityIdentifier: GuardianAppAndFamilyFeature.notifications
                        .accessibilityIdentifier,
                    action: onOpenNotifications
                )
                GuardianAppNavigationTile(
                    title: GuardianAppAndFamilyFeature.speechAndMicrophone.title,
                    summary: GuardianSpeechPermissionPresentation.tileSummary(
                        for: speechPermissionState
                    ),
                    symbol: "waveform.badge.mic",
                    tint: GuardianPrimitiveTokens.ColorValue.indigo,
                    accessibilityIdentifier: GuardianAppAndFamilyFeature
                        .speechAndMicrophone.accessibilityIdentifier,
                    action: onOpenSpeechPermissions
                )
                GuardianAppNavigationTile(
                    title: GuardianAppAndFamilyFeature.familySync.title,
                    summary: familySyncSummary,
                    symbol: "person.2.badge.gearshape.fill",
                    tint: GuardianPrimitiveTokens.ColorValue.teal,
                    accessibilityIdentifier: GuardianAppAndFamilyFeature.familySync
                        .accessibilityIdentifier,
                    action: onOpenFamilySync
                )
                GuardianAppNavigationTile(
                    title: GuardianAppAndFamilyFeature.thirdPartyNotices.title,
                    summary: "Licenses and credits available offline",
                    symbol: "doc.text.magnifyingglass",
                    tint: GuardianPrimitiveTokens.ColorValue.blue,
                    accessibilityIdentifier: GuardianAppAndFamilyFeature
                        .thirdPartyNotices.accessibilityIdentifier,
                    action: onOpenThirdPartyNotices
                )
            }
            GuardianPrivacyAndSupportSection(appVersion: .current)
        }
    }

    private var audioSummary: String {
        let audio = snapshot.practiceSettings.audio
        let music = audio.musicEnabled ? "Music on" : "Music off"
        let voice = audio.voiceEnabled ? "Voice on" : "Voice off"
        let hand =
            snapshot.practiceSettings.interface.leftHandedLayoutEnabled
            ? "Left-handed controls"
            : "Right-handed controls"
        return "\(music) · \(voice) · \(hand)"
    }

    private var familySyncSummary: String {
        syncState == .thisDeviceOnly
            ? "Share profiles and progress across family devices"
            : syncState.title
    }
}

private struct GuardianAppNavigationTile: View {
    let title: String
    let summary: String
    let symbol: String
    let tint: Color
    let accessibilityIdentifier: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 5) {
                Image(systemName: symbol)
                    .font(.system(.title2, design: .rounded, weight: .bold))
                    .foregroundStyle(tint)
                    .accessibilityHidden(true)
                Text(title)
                    .font(.system(.headline, design: .rounded, weight: .bold))
                    .foregroundStyle(GuardianSemanticTokens.foreground)
                    .lineLimit(2)
                Text(summary)
                    .font(.system(.caption, design: .rounded, weight: .semibold))
                    .foregroundStyle(GuardianSemanticTokens.secondaryForeground)
                    .lineLimit(3)
            }
            .frame(maxWidth: .infinity, minHeight: 108, alignment: .leading)
            .padding(GuardianPrimitiveTokens.Spacing.medium)
            .background(
                tint.opacity(0.10),
                in: RoundedRectangle(
                    cornerRadius: GuardianPrimitiveTokens.Radius.medium,
                    style: .continuous
                )
            )
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(title). \(summary)")
        .accessibilityHint("Opens \(title)")
        .accessibilityIdentifier(accessibilityIdentifier)
    }
}

enum GuardianParentResource: String, CaseIterable, Equatable {
    case privacyPolicy
    case support

    var title: String {
        switch self {
        case .privacyPolicy:
            "Privacy Policy"
        case .support:
            "Support"
        }
    }

    var summary: String {
        switch self {
        case .privacyPolicy:
            "How Tada Words handles family data"
        case .support:
            "Help, troubleshooting, and contact"
        }
    }

    var symbol: String {
        switch self {
        case .privacyPolicy:
            "hand.raised.fill"
        case .support:
            "questionmark.bubble.fill"
        }
    }

    var destination: URL {
        switch self {
        case .privacyPolicy:
            URL(string: "https://pawgoo.app/en/tadawords/privacy")!
        case .support:
            URL(string: "https://pawgoo.app/en/support")!
        }
    }

    var accessibilityIdentifier: String {
        switch self {
        case .privacyPolicy:
            "guardian.app.privacy-policy"
        case .support:
            "guardian.app.support"
        }
    }
}

enum GuardianDataControlCopy {
    static let localProfileDeletion =
        "From Parent Home, tap the child card, choose Edit, then Delete profile. "
        + "This removes that child’s words, settings, quest history, rewards, and saved picture from this device."

    static let permissionManagement =
        "Use Speech & Microphone above to review or finish setup. To change access later, open the iOS Settings app, choose Apps, then Tada Words to review Camera, Photos, Microphone, Speech Recognition, and Notifications."
}

private struct GuardianPrivacyAndSupportSection: View {
    let appVersion: GuardianAppVersionPresentation

    var body: some View {
        GuardianCard {
            VStack(alignment: .leading, spacing: GuardianPrimitiveTokens.Spacing.small) {
                Label("Privacy & Support", systemImage: "hand.raised.fill")
                    .font(.system(.headline, design: .rounded, weight: .bold))

                LazyVGrid(
                    columns: [
                        GridItem(
                            .adaptive(minimum: 132, maximum: 220),
                            spacing: GuardianPrimitiveTokens.Spacing.small
                        )
                    ],
                    spacing: GuardianPrimitiveTokens.Spacing.small
                ) {
                    resourceLinks
                    GuardianDataControlGuide(
                        title: "Delete a local profile",
                        detail: GuardianDataControlCopy.localProfileDeletion,
                        symbol: "person.crop.circle.badge.minus",
                        accessibilityIdentifier: "guardian.app.local-profile-deletion"
                    )
                    GuardianDataControlGuide(
                        title: "Manage iOS permissions",
                        detail: GuardianDataControlCopy.permissionManagement,
                        symbol: "gearshape.fill",
                        accessibilityIdentifier: "guardian.app.permission-management"
                    )
                }

                Text(appVersion.footerText)
                    .font(.system(.caption, design: .rounded, weight: .medium))
                    .monospacedDigit()
                    .foregroundStyle(GuardianSemanticTokens.secondaryForeground)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .accessibilityLabel(appVersion.footerText)
                    .accessibilityIdentifier(
                        GuardianAppVersionPresentation.accessibilityIdentifier
                    )
            }
        }
        .accessibilityIdentifier("guardian.app.privacy-and-support")
    }

    @ViewBuilder private var resourceLinks: some View {
        ForEach(GuardianParentResource.allCases, id: \.self) { resource in
            GuardianParentResourceLink(resource: resource)
        }
    }
}

private struct GuardianParentResourceLink: View {
    let resource: GuardianParentResource

    var body: some View {
        Link(destination: resource.destination) {
            VStack(alignment: .leading, spacing: GuardianPrimitiveTokens.Spacing.xSmall) {
                Image(systemName: resource.symbol)
                    .font(.system(.title3, design: .rounded, weight: .bold))
                    .accessibilityHidden(true)
                Text(resource.title)
                    .font(.system(.subheadline, design: .rounded, weight: .bold))
                    .lineLimit(1)
                Text(resource.summary)
                    .font(.system(.caption, design: .rounded, weight: .medium))
                    .foregroundStyle(GuardianSemanticTokens.secondaryForeground)
                    .lineLimit(2)
            }
            .frame(maxWidth: .infinity, minHeight: 82, alignment: .leading)
            .padding(GuardianPrimitiveTokens.Spacing.small)
        }
        .buttonStyle(.plain)
        .foregroundStyle(GuardianSemanticTokens.primary)
        .background(
            GuardianSemanticTokens.primary.opacity(0.08),
            in: RoundedRectangle(
                cornerRadius: GuardianPrimitiveTokens.Radius.medium,
                style: .continuous
            )
        )
        .accessibilityElement(children: .combine)
        .accessibilityLabel(resource.title)
        .accessibilityHint("Opens \(resource.title) in your web browser")
        .accessibilityIdentifier(resource.accessibilityIdentifier)
    }
}

private struct GuardianDataControlGuide: View {
    let title: String
    let detail: String
    let symbol: String
    let accessibilityIdentifier: String

    var body: some View {
        VStack(alignment: .leading, spacing: GuardianPrimitiveTokens.Spacing.xSmall) {
            Image(systemName: symbol)
                .font(.system(.title3, design: .rounded, weight: .bold))
                .foregroundStyle(GuardianSemanticTokens.primary)
                .accessibilityHidden(true)
            Text(title)
                .font(.system(.subheadline, design: .rounded, weight: .bold))
                .lineLimit(1)
            Text(detail)
                .font(.system(.caption, design: .rounded, weight: .medium))
                .foregroundStyle(GuardianSemanticTokens.secondaryForeground)
                .lineLimit(3)
        }
        .frame(maxWidth: .infinity, minHeight: 82, alignment: .leading)
        .padding(GuardianPrimitiveTokens.Spacing.small)
        .background(
            GuardianSemanticTokens.primary.opacity(0.08),
            in: RoundedRectangle(
                cornerRadius: GuardianPrimitiveTokens.Radius.medium,
                style: .continuous
            )
        )
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(title). \(detail)")
        .accessibilityIdentifier(accessibilityIdentifier)
    }
}

struct GuardianNavigationTile: View {
    let title: String
    let summary: String
    let symbol: String
    let tint: Color
    let accessibilityIdentifier: String
    let theme: TadaWorldTheme?
    let action: () -> Void

    init(
        title: String,
        summary: String,
        symbol: String,
        tint: Color,
        accessibilityIdentifier: String,
        theme: TadaWorldTheme? = nil,
        action: @escaping () -> Void
    ) {
        self.title = title
        self.summary = summary
        self.symbol = symbol
        self.tint = tint
        self.accessibilityIdentifier = accessibilityIdentifier
        self.theme = theme
        self.action = action
    }

    var body: some View {
        Button(action: action) {
            card
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
        .accessibilityHint("Opens \(title)")
        .accessibilityIdentifier(accessibilityIdentifier)
    }

    @ViewBuilder
    private var card: some View {
        if let theme {
            TadaPanel(theme: theme) {
                tileContent(
                    foreground: theme.ink,
                    secondaryForeground: TadaSemanticColors.secondaryOnSurface(for: theme)
                )
            }
        } else {
            GuardianCard {
                tileContent(
                    foreground: GuardianSemanticTokens.foreground,
                    secondaryForeground: GuardianSemanticTokens.secondaryForeground
                )
            }
        }
    }

    private func tileContent(
        foreground: Color,
        secondaryForeground: Color
    ) -> some View {
        HStack(spacing: GuardianPrimitiveTokens.Spacing.medium) {
            Image(systemName: symbol)
                .font(.system(.title2, design: .rounded, weight: .bold))
                .foregroundStyle(tint)
                .frame(width: 38)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.system(.headline, design: .rounded, weight: .bold))
                    .foregroundStyle(foreground)
                Text(summary)
                    .font(.system(.subheadline, design: .rounded, weight: .medium))
                    .foregroundStyle(secondaryForeground)
                    .multilineTextAlignment(.leading)
                    .lineLimit(2)
            }

            Spacer(minLength: GuardianPrimitiveTokens.Spacing.small)

            Image(systemName: "chevron.right")
                .font(.system(.subheadline, design: .rounded, weight: .bold))
                .foregroundStyle(secondaryForeground)
                .accessibilityHidden(true)
        }
        .frame(maxWidth: .infinity, minHeight: 72, alignment: .leading)
    }
}

private struct GuardianParentHubLayout<Content: View>: View {
    let title: String
    let profile: KidProfile?
    let onBack: () -> Void
    let content: Content

    init(
        title: String,
        profile: KidProfile? = nil,
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
            VStack(alignment: .leading, spacing: GuardianPrimitiveTokens.Spacing.medium) {
                GuardianNavigationHeader(title: title, onBack: onBack)
                if let profile {
                    GuardianParentContextHeader(profile: profile)
                }
                content
            }
            .frame(maxWidth: 980, alignment: .leading)
            .guardianParentPageInsets()
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
    var tint = GuardianSemanticTokens.primary

    var body: some View {
        ZStack {
            Circle()
                .fill(tint.opacity(0.12))
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
        case .cartoonAnimal:
            starterProfileAvatar?.fallbackSystemImageName ?? "pawprint.fill"
        case .photo:
            "person.crop.circle.fill"
        case .treasure(_, let iconAssetID):
            iconAssetID
        }
    }
}
