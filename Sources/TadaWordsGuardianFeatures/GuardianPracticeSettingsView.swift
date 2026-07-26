import SwiftUI
import TadaWordsDomain

struct GuardianPracticeSettingsView: View {
    let section: GuardianSettingsSection
    let onBack: () -> Void
    let onSave: (ProfilePracticeSettings) -> Void

    private let profileID: ProfileID
    private let selectedHandwritingTool: HandwritingTool
    @State private var readDraft: GuardianRouteSettingsDraft
    @State private var writeDraft: GuardianRouteSettingsDraft
    @State private var voiceEnabled: Bool
    @State private var musicEnabled: Bool
    @State private var soundEffectsEnabled: Bool
    @State private var reducedSoundEnabled: Bool
    @State private var calmRescueEnabled: Bool
    @State private var notificationDraft: GuardianNotificationSettingsDraft
    @State private var leftHandedWritingControlsEnabled: Bool

    init(
        settings: ProfilePracticeSettings,
        section: GuardianSettingsSection,
        onBack: @escaping () -> Void,
        onSave: @escaping (ProfilePracticeSettings) -> Void
    ) {
        profileID = settings.profileID
        selectedHandwritingTool = settings.interface.selectedHandwritingTool
        self.section = section
        self.onBack = onBack
        self.onSave = onSave
        _readDraft = State(
            initialValue: GuardianRouteSettingsDraft(settings: settings.read)
        )
        _writeDraft = State(
            initialValue: GuardianRouteSettingsDraft(settings: settings.write)
        )
        _voiceEnabled = State(initialValue: settings.audio.voiceEnabled)
        _musicEnabled = State(initialValue: settings.audio.musicEnabled)
        _soundEffectsEnabled = State(
            initialValue: settings.audio.soundEffectsEnabled
        )
        _reducedSoundEnabled = State(
            initialValue: settings.audio.reducedSoundEnabled
        )
        _calmRescueEnabled = State(
            initialValue: settings.audio.calmEmergencyEnabled
        )
        _notificationDraft = State(
            initialValue: GuardianNotificationSettingsDraft(
                settings: settings.notifications
            )
        )
        _leftHandedWritingControlsEnabled = State(
            initialValue: settings.interface.leftHandedLayoutEnabled
        )
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: GuardianPrimitiveTokens.Spacing.large) {
                GuardianNavigationHeader(
                    title: section.navigationTitle,
                    onBack: onBack
                )

                settingsContent

                Button(section.saveButtonTitle) {
                    onSave(assembledSettings)
                }
                .buttonStyle(GuardianPrimaryButtonStyle())
            }
            .frame(maxWidth: 880, alignment: .leading)
            .padding(.horizontal, GuardianPrimitiveTokens.Spacing.medium)
            .padding(.vertical, GuardianPrimitiveTokens.Spacing.large)
            .frame(maxWidth: .infinity)
        }
        .scrollIndicators(.hidden)
    }

    @ViewBuilder
    private var settingsContent: some View {
        switch section {
        case .practicePlan:
            VStack(alignment: .leading, spacing: GuardianPrimitiveTokens.Spacing.small) {
                Text("Plan each practice route")
                    .font(.system(.title3, design: .rounded, weight: .bold))
                Text(
                    "Choose word counts, order, wrong answers allowed per word, and when Rescue time begins."
                )
                .font(.system(.body, design: .rounded, weight: .medium))
                .foregroundStyle(GuardianSemanticTokens.secondaryForeground)
                .frame(maxWidth: 680, alignment: .leading)
            }

            ViewThatFits(in: .horizontal) {
                HStack(alignment: .top, spacing: GuardianPrimitiveTokens.Spacing.medium) {
                    routeCards
                }

                VStack(spacing: GuardianPrimitiveTokens.Spacing.medium) {
                    routeCards
                }
            }

            Label(
                "Rescue time adds extra encouragement. It does not end practice.",
                systemImage: "info.circle"
            )
            .font(.system(.subheadline, design: .rounded, weight: .medium))
            .foregroundStyle(GuardianSemanticTokens.secondaryForeground)

        case .soundAndAccessibility:
            audioSettingsCard
            interfaceSettingsCard

        case .notifications:
            notificationSettingsCard
        }
    }

    /// The view emits a complete draft so controls remain reusable. The model
    /// applies only this page's visible section to the latest stored settings.
    private var assembledSettings: ProfilePracticeSettings {
        ProfilePracticeSettings(
            profileID: profileID,
            read: readDraft.settings,
            write: writeDraft.settings,
            audio: AudioPreferences(
                voiceEnabled: voiceEnabled,
                musicEnabled: musicEnabled,
                soundEffectsEnabled: soundEffectsEnabled,
                reducedSoundEnabled: reducedSoundEnabled,
                calmEmergencyEnabled: calmRescueEnabled
            ),
            notifications: notificationDraft.settings,
            interface: PracticeInterfacePreferences(
                leftHandedLayoutEnabled: leftHandedWritingControlsEnabled,
                selectedHandwritingTool: selectedHandwritingTool
            )
        )
    }

    @ViewBuilder
    private var routeCards: some View {
        GuardianRouteSettingsCard(mode: .read, draft: $readDraft)
        GuardianRouteSettingsCard(mode: .write, draft: $writeDraft)
    }

    private var audioSettingsCard: some View {
        GuardianCard {
            VStack(alignment: .leading, spacing: GuardianPrimitiveTokens.Spacing.medium) {
                Label("Audio", systemImage: "speaker.wave.2.fill")
                    .font(.system(.title3, design: .rounded, weight: .bold))

                Text("Each child can have their own bright, encouraging sound settings.")
                    .font(.system(.subheadline, design: .rounded, weight: .medium))
                    .foregroundStyle(GuardianSemanticTokens.secondaryForeground)

                Toggle("Voice", isOn: $voiceEnabled)
                    .accessibilityHint("Controls word pronunciation and the startup voice")
                if voiceEnabled {
                    Text("Word practice uses one consistent teacher voice.")
                        .font(.system(.caption, design: .rounded, weight: .medium))
                        .foregroundStyle(GuardianSemanticTokens.secondaryForeground)
                        .padding(.leading, 4)
                }
                Divider()
                Toggle("Music", isOn: $musicEnabled)
                    .accessibilityHint("Controls the current world’s background music")
                Divider()
                Toggle("Sound effects", isOn: $soundEffectsEnabled)
                    .accessibilityHint("Controls taps, retry cues, stars, and rewards")
                Divider()
                Toggle("Reduced sound", isOn: $reducedSoundEnabled)
                    .accessibilityHint("Uses fewer nonessential sound cues")
                Divider()
                Toggle("Calm Rescue", isOn: $calmRescueEnabled)
                    .accessibilityHint("Keeps Rescue time music gentle")
            }
        }
        .frame(maxWidth: 680, alignment: .leading)
    }

    private var notificationSettingsCard: some View {
        GuardianCard {
            VStack(alignment: .leading, spacing: GuardianPrimitiveTokens.Spacing.medium) {
                Label("Notifications", systemImage: "bell.badge.fill")
                    .font(.system(.title3, design: .rounded, weight: .bold))

                Text(
                    "Choose which family updates matter for this child. System notification permission is managed separately."
                )
                .font(.system(.subheadline, design: .rounded, weight: .medium))
                .foregroundStyle(GuardianSemanticTokens.secondaryForeground)

                Toggle("Daily reminder", isOn: $notificationDraft.dailyReminderEnabled)
                Divider()
                Toggle("Pool low", isOn: $notificationDraft.poolLowEnabled)
                Divider()
                Toggle("Quest completion", isOn: $notificationDraft.questCompletionEnabled)
                Divider()
                Toggle("Sync failure", isOn: $notificationDraft.syncFailureEnabled)
                Divider()
                Toggle("Weekly summary", isOn: $notificationDraft.weeklySummaryEnabled)
                Divider()
                notificationTimePicker(
                    title: "Daily reminder time",
                    hour: $notificationDraft.dailyReminderHour,
                    minute: $notificationDraft.dailyReminderMinute
                )
                Divider()
                notificationTimePicker(
                    title: "Quiet hours start",
                    hour: $notificationDraft.quietHoursStartHour,
                    minute: $notificationDraft.quietHoursStartMinute
                )
                notificationTimePicker(
                    title: "Quiet hours end",
                    hour: $notificationDraft.quietHoursEndHour,
                    minute: $notificationDraft.quietHoursEndMinute
                )
                Text(
                    "No reminders are scheduled during quiet hours. Lock-screen text never includes a child’s name, word, score, or accuracy."
                )
                .font(.system(.caption, design: .rounded, weight: .medium))
                .foregroundStyle(GuardianSemanticTokens.secondaryForeground)
                Button("Turn off all notifications", role: .destructive) {
                    notificationDraft.disableAll()
                }
                .buttonStyle(.bordered)
            }
        }
        .frame(maxWidth: 680, alignment: .leading)
    }

    private func notificationTimePicker(
        title: String,
        hour: Binding<Int>,
        minute: Binding<Int>
    ) -> some View {
        HStack {
            Text(title)
                .font(.system(.subheadline, design: .rounded, weight: .semibold))
            Spacer()
            Picker("Hour", selection: hour) {
                ForEach(0..<24, id: \.self) { value in
                    Text(String(format: "%02d", value)).tag(value)
                }
            }
            .labelsHidden()
            .pickerStyle(.menu)
            Text(":")
            Picker("Minute", selection: minute) {
                ForEach(0..<60, id: \.self) { value in
                    Text(String(format: "%02d", value)).tag(value)
                }
            }
            .labelsHidden()
            .pickerStyle(.menu)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(title)
        .accessibilityValue(
            String(format: "%02d:%02d", hour.wrappedValue, minute.wrappedValue)
        )
    }

    private var interfaceSettingsCard: some View {
        GuardianCard {
            VStack(alignment: .leading, spacing: GuardianPrimitiveTokens.Spacing.medium) {
                Label("Writing controls", systemImage: "hand.draw.fill")
                    .font(.system(.title3, design: .rounded, weight: .bold))

                Toggle(
                    "Left-handed writing controls",
                    isOn: $leftHandedWritingControlsEnabled
                )
                .accessibilityHint("Moves writing actions to the left side")
            }
        }
        .frame(maxWidth: 680, alignment: .leading)
    }
}

extension GuardianSettingsSection {
    fileprivate var navigationTitle: String {
        switch self {
        case .practicePlan:
            "Practice Plan"
        case .soundAndAccessibility:
            "Sound & Accessibility"
        case .notifications:
            "Notifications"
        }
    }

    fileprivate var saveButtonTitle: String {
        switch self {
        case .practicePlan:
            "Save practice plan"
        case .soundAndAccessibility:
            "Save sound & accessibility"
        case .notifications:
            "Save notifications"
        }
    }
}

private struct GuardianNotificationSettingsDraft {
    var dailyReminderEnabled: Bool
    var poolLowEnabled: Bool
    var questCompletionEnabled: Bool
    var syncFailureEnabled: Bool
    var weeklySummaryEnabled: Bool
    var dailyReminderHour: Int
    var dailyReminderMinute: Int
    var quietHoursStartHour: Int
    var quietHoursStartMinute: Int
    var quietHoursEndHour: Int
    var quietHoursEndMinute: Int

    init(settings: LearningNotificationPreferences) {
        dailyReminderEnabled = settings.dailyReminderEnabled
        poolLowEnabled = settings.poolLowEnabled
        questCompletionEnabled = settings.questCompletionEnabled
        syncFailureEnabled = settings.syncFailureEnabled
        weeklySummaryEnabled = settings.weeklySummaryEnabled
        dailyReminderHour = settings.dailyReminderTime.hour
        dailyReminderMinute = settings.dailyReminderTime.minute
        quietHoursStartHour = settings.quietHours.startsAt.hour
        quietHoursStartMinute = settings.quietHours.startsAt.minute
        quietHoursEndHour = settings.quietHours.endsAt.hour
        quietHoursEndMinute = settings.quietHours.endsAt.minute
    }

    var settings: LearningNotificationPreferences {
        LearningNotificationPreferences(
            dailyReminderEnabled: dailyReminderEnabled,
            poolLowEnabled: poolLowEnabled,
            questCompletionEnabled: questCompletionEnabled,
            syncFailureEnabled: syncFailureEnabled,
            weeklySummaryEnabled: weeklySummaryEnabled,
            dailyReminderTime: LearningReminderTime(
                hour: dailyReminderHour,
                minute: dailyReminderMinute
            ),
            quietHours: NotificationQuietHours(
                startsAt: LearningReminderTime(
                    hour: quietHoursStartHour,
                    minute: quietHoursStartMinute
                ),
                endsAt: LearningReminderTime(
                    hour: quietHoursEndHour,
                    minute: quietHoursEndMinute
                )
            )
        )
    }

    mutating func disableAll() {
        dailyReminderEnabled = false
        poolLowEnabled = false
        questCompletionEnabled = false
        syncFailureEnabled = false
        weeklySummaryEnabled = false
    }
}

private struct GuardianRouteSettingsCard: View {
    let mode: LearningMode
    @Binding var draft: GuardianRouteSettingsDraft

    var body: some View {
        GuardianCard {
            VStack(alignment: .leading, spacing: GuardianPrimitiveTokens.Spacing.large) {
                GuardianModeBadge(mode: mode)

                GuardianWordCountStepper(
                    mode: mode,
                    title: "New words",
                    accessibilityName: "new-word limit",
                    value: $draft.newWordLimit
                )

                Divider()

                GuardianWordCountStepper(
                    mode: mode,
                    title: "Review words",
                    accessibilityName: "review-word limit",
                    value: $draft.reviewWordLimit
                )

                VStack(alignment: .leading, spacing: GuardianPrimitiveTokens.Spacing.small) {
                    Text("Quest order")
                        .font(.system(.headline, design: .rounded, weight: .bold))
                    Picker("Quest order", selection: $draft.contentOrder) {
                        Text("New first")
                            .tag(QuestContentOrder.newThenReview)
                        Text("Review first")
                            .tag(QuestContentOrder.reviewThenNew)
                    }
                    .pickerStyle(.segmented)
                    .accessibilityLabel("\(mode.guardianTitle) quest order")
                    .accessibilityValue(
                        "\(mode.guardianTitle), \(draft.contentOrder.accessibilityTitle)"
                    )
                }

                Divider()

                Stepper(
                    value: $draft.emergencyMinutes,
                    in: GuardianRouteSettingsDraft.emergencyMinutesRange
                ) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Rescue timer")
                            .font(.system(.headline, design: .rounded, weight: .bold))
                        Text(draft.emergencyTimerSummary)
                            .font(.system(.subheadline, design: .rounded, weight: .medium))
                            .foregroundStyle(GuardianSemanticTokens.secondaryForeground)
                            .monospacedDigit()
                    }
                }
                .accessibilityLabel("\(mode.guardianTitle) Rescue timer")
                .accessibilityValue(
                    "\(mode.guardianTitle), \(draft.emergencyTimerSummary)"
                )
            }
        }
        .frame(minWidth: 300, maxWidth: .infinity)
    }
}

private struct GuardianWordCountStepper: View {
    let mode: LearningMode
    let title: String
    let accessibilityName: String
    @Binding var value: Int

    var body: some View {
        Stepper(value: $value, in: LearningRouteSettings.wordLimitRange) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(.headline, design: .rounded, weight: .bold))
                Text("\(value) \(value == 1 ? "word" : "words")")
                    .font(.system(.subheadline, design: .rounded, weight: .medium))
                    .foregroundStyle(GuardianSemanticTokens.secondaryForeground)
                    .monospacedDigit()
            }
        }
        .accessibilityLabel("\(mode.guardianTitle) \(accessibilityName)")
        .accessibilityValue("\(mode.guardianTitle), \(value) words")
    }
}

private struct GuardianRouteSettingsDraft {
    static var emergencyMinutesRange: ClosedRange<Int> {
        let secondsRange = LearningRouteSettings.emergencyAfterSecondsRange
        return (secondsRange.lowerBound / 60)...(secondsRange.upperBound / 60)
    }

    var newWordLimit: Int
    var reviewWordLimit: Int
    var contentOrder: QuestContentOrder
    var emergencyMinutes: Int

    init(settings: LearningRouteSettings) {
        newWordLimit = settings.newWordLimit
        reviewWordLimit = settings.reviewWordLimit
        contentOrder = settings.contentOrder
        emergencyMinutes = settings.emergencyAfterSeconds / 60
    }

    var settings: LearningRouteSettings {
        LearningRouteSettings(
            newWordLimit: newWordLimit,
            reviewWordLimit: reviewWordLimit,
            contentOrder: contentOrder,
            emergencyAfterSeconds: emergencyMinutes * 60
        )
    }

    var emergencyTimerSummary: String {
        "After \(emergencyMinutes) \(emergencyMinutes == 1 ? "minute" : "minutes")"
    }
}

extension QuestContentOrder {
    fileprivate var accessibilityTitle: String {
        switch self {
        case .newThenReview:
            "New words first"
        case .reviewThenNew:
            "Review words first"
        }
    }
}
