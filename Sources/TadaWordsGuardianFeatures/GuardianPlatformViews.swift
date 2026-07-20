import SwiftUI
import TadaWordsDomain

/// Exportable support evidence deliberately limited to transport state. It
/// never includes a Profile ID, child name, word, photo, voice sample, or
/// repository payload.
struct GuardianFamilySyncDiagnosticReport: Equatable {
    let text: String

    init(
        status: FamilySyncStatus,
        isEnabled: Bool,
        profileErasure: GuardianProfileErasurePresentation? = nil,
        remoteNotificationRegistration:
            FamilySyncRemoteNotificationRegistrationState = .notRequested,
        generatedAt: Date = Date()
    ) {
        var fields = [
            "Tada Words Family Sync Diagnostics",
            "Schema: 2",
            "Generated: \(generatedAt.ISO8601Format())",
            "Enabled on this device: \(isEnabled ? "yes" : "no")",
        ]
        switch status {
        case .idle:
            fields.append("State: idle")
        case .optedOut:
            fields.append("State: opted_out")
        case .deviceOnly:
            fields.append("State: device_only")
        case .syncing(let pendingCount):
            fields.append("State: syncing")
            fields.append("Pending changes: \(pendingCount)")
        case .synced(let date):
            fields.append("State: synced")
            fields.append("Last success: \(date.ISO8601Format())")
        case .pendingOffline(
            let pendingCount,
            let retryCount,
            let nextRetryAt
        ):
            fields.append("State: waiting_for_connection")
            fields.append("Pending changes: \(pendingCount)")
            fields.append("Retry count: \(retryCount)")
            if let nextRetryAt {
                fields.append("Next retry: \(nextRetryAt.ISO8601Format())")
            }
        case .iCloudUnavailable:
            fields.append("State: icloud_unavailable")
        case .failed(_, let pendingCount):
            fields.append("State: needs_attention")
            fields.append("Pending changes: \(pendingCount)")
        }
        switch remoteNotificationRegistration {
        case .notRequested:
            fields.append("Push registration: not_requested")
        case .pending(let since):
            fields.append("Push registration: pending")
            fields.append("Push registration updated: \(since.ISO8601Format())")
        case .registered(let at):
            fields.append("Push registration: registered")
            fields.append("Push registration updated: \(at.ISO8601Format())")
        case .failed(let category, let at):
            fields.append("Push registration: failed")
            fields.append("Push registration failure: \(category.rawValue)")
            fields.append("Push registration updated: \(at.ISO8601Format())")
        }
        if let profileErasure {
            fields.append(
                "Profile erasure state: \(profileErasure.diagnosticState)"
            )
            if let count = profileErasure.count,
                let retryCount = profileErasure.retryCount
            {
                fields.append("Profile erasure count: \(count)")
                fields.append("Profile erasure retry count: \(retryCount)")
            } else {
                fields.append("Profile erasure count: unavailable")
                fields.append("Profile erasure retry count: unavailable")
            }
        }
        text = fields.joined(separator: "\n")
    }
}

struct GuardianFamilySyncPresentation: Equatable {
    let navigationTitle: String
    let title: String
    let message: String
    let symbol: String
    let showsPreferenceToggle: Bool
    let showsSyncAction: Bool
    let showsInvitationActions: Bool

    init(status: FamilySyncStatus, isEnabled: Bool) {
        if case .deviceOnly(let message) = status {
            navigationTitle = "Device storage"
            title = "This device only"
            self.message = message
            symbol = "externaldrive.fill"
            showsPreferenceToggle = false
            showsSyncAction = false
            showsInvitationActions = false
            return
        }

        navigationTitle = "Family sync"
        showsPreferenceToggle = true
        if !isEnabled || status.isOptedOut {
            title = "Family sync is off"
            message =
                "Learning data stays on this device until a parent turns on iCloud family sync."
            symbol = "externaldrive.fill"
            showsSyncAction = false
            showsInvitationActions = false
            return
        }

        switch status {
        case .idle:
            title = "Ready to sync"
            message = "Family sync is on and never blocks a quest."
            symbol = "icloud.fill"
            showsSyncAction = true
            showsInvitationActions = false
        case .optedOut:
            preconditionFailure("Opted-out state was handled above.")
        case .deviceOnly:
            preconditionFailure("Device-only state was handled above.")
        case .syncing(let pendingCount):
            title = "Syncing…"
            message =
                pendingCount == 1
                ? "1 change is safe on this device while it syncs."
                : "\(pendingCount) changes are safe on this device while they sync."
            symbol = "arrow.triangle.2.circlepath.icloud"
            showsSyncAction = false
            showsInvitationActions = false
        case .synced(let date):
            title = "Up to date"
            message = "Last synced \(Self.formatted(date))."
            symbol = "checkmark.icloud.fill"
            showsSyncAction = true
            showsInvitationActions = true
        case .pendingOffline(
            let pendingCount,
            let retryCount,
            let nextRetryAt
        ):
            title = "Waiting for a connection"
            let pendingMessage =
                pendingCount == 1
                ? "1 change is safe on this device. Tada Words will retry."
                : "\(pendingCount) changes are safe on this device. Tada Words will retry."
            if retryCount > 0, let nextRetryAt {
                message =
                    "\(pendingMessage) Retry \(retryCount) is scheduled for \(Self.formatted(nextRetryAt))."
            } else {
                message = pendingMessage
            }
            symbol = "arrow.triangle.2.circlepath.icloud"
            showsSyncAction = true
            showsInvitationActions = false
        case .iCloudUnavailable(let message):
            title = "iCloud is unavailable"
            self.message = message
            symbol = "exclamationmark.icloud.fill"
            showsSyncAction = true
            showsInvitationActions = false
        case .failed(let message, _):
            title = "Sync needs attention"
            self.message = message
            symbol = "exclamationmark.icloud.fill"
            showsSyncAction = true
            showsInvitationActions = false
        }
    }

    private static func formatted(_ date: Date) -> String {
        date.formatted(date: .abbreviated, time: .shortened)
    }
}

struct GuardianRemoteNotificationRegistrationPresentation {
    let title: String
    let message: String
    let symbol: String

    init(state: FamilySyncRemoteNotificationRegistrationState) {
        switch state {
        case .notRequested:
            title = "Push registration not requested"
            message = "It starts when a parent turns on Family Sync."
            symbol = "bell.slash.fill"
        case .pending:
            title = "Registering for background updates"
            message = "Waiting for Apple to finish this device’s registration."
            symbol = "hourglass"
        case .registered:
            title = "Background notifications registered"
            message =
                "Apple registered background notifications for this app. "
                + "CloudKit delivery is checked separately."
            symbol = "checkmark.circle.fill"
        case .failed(let category, _):
            title = "Background registration needs attention"
            message = "Registration failed (\(category.rawValue)). Try Family Sync again."
            symbol = "exclamationmark.triangle.fill"
        }
    }
}

enum GuardianProfileErasureAggregateState: Equatable {
    case requested
    case deleting
    case waitingForConnection
    case waitingForFamilySync
    case needsAttention
    case complete
    case unavailable

    fileprivate var severity: Int {
        switch self {
        case .complete:
            0
        case .requested:
            1
        case .deleting:
            2
        case .waitingForFamilySync, .waitingForConnection:
            3
        case .needsAttention:
            4
        case .unavailable:
            5
        }
    }

    fileprivate var diagnosticValue: String {
        switch self {
        case .requested:
            "requested"
        case .deleting:
            "deleting"
        case .waitingForConnection:
            "waiting_for_connection"
        case .waitingForFamilySync:
            "waiting_for_family_sync"
        case .needsAttention:
            "needs_attention"
        case .complete:
            "complete"
        case .unavailable:
            "unavailable"
        }
    }

    fileprivate var accessibilityValue: String {
        switch self {
        case .requested:
            "requested"
        case .deleting:
            "deleting"
        case .waitingForConnection:
            "waiting"
        case .waitingForFamilySync:
            "waiting-for-family-sync"
        case .needsAttention:
            "needs-attention"
        case .complete:
            "complete"
        case .unavailable:
            "unavailable"
        }
    }
}

struct GuardianProfileErasurePresentation: Equatable {
    let state: GuardianProfileErasureAggregateState
    let count: Int?
    let retryCount: Int?
    let title: String
    let message: String
    let symbol: String
    let showsRetryAction: Bool

    var diagnosticState: String { state.diagnosticValue }

    var accessibilityIdentifier: String {
        "guardian.sync.erasure.\(state.accessibilityValue)"
    }

    static let unavailable = Self(
        state: .unavailable,
        count: nil,
        retryCount: nil,
        title: "Deletion status needs attention",
        message:
            "Tada Words couldn’t read the saved deletion status. No child data was restored or replaced. Try again.",
        symbol: "exclamationmark.triangle.fill",
        showsRetryAction: true
    )

    static func make(
        lifecycles: [ProfileErasureLifecycle],
        isFamilySyncEnabled: Bool
    ) -> Self? {
        guard !lifecycles.isEmpty else { return nil }

        let severeState =
            lifecycles
            .map { aggregateState(for: $0.state) }
            .max { $0.severity < $1.severity }!
        let severeLifecycles = lifecycles.filter {
            aggregateState(for: $0.state) == severeState
        }

        if !isFamilySyncEnabled, severeState != .needsAttention,
            severeState != .complete
        {
            let active = lifecycles.filter { $0.state != .complete }
            return presentation(
                state: .waitingForFamilySync,
                count: active.count,
                retryCount: active.map(\.retryCount).max() ?? 0,
                isFamilySyncEnabled: false
            )
        }

        return presentation(
            state: severeState,
            count: severeLifecycles.count,
            retryCount: severeLifecycles.map(\.retryCount).max() ?? 0,
            isFamilySyncEnabled: isFamilySyncEnabled
        )
    }

    private static func aggregateState(
        for state: ProfileErasureState
    ) -> GuardianProfileErasureAggregateState {
        switch state {
        case .requested:
            .requested
        case .deleting:
            .deleting
        case .waitingForConnection:
            .waitingForConnection
        case .needsAttention:
            .needsAttention
        case .complete:
            .complete
        }
    }

    private static func presentation(
        state: GuardianProfileErasureAggregateState,
        count: Int,
        retryCount: Int,
        isFamilySyncEnabled: Bool
    ) -> Self {
        let profile = count == 1 ? "profile" : "profiles"
        let verb = count == 1 ? "is" : "are"
        switch state {
        case .requested:
            return Self(
                state: state,
                count: count,
                retryCount: retryCount,
                title: "Deletion queued",
                message:
                    "\(count) deleted \(profile) \(verb) gone from this device. iCloud cleanup will begin shortly.",
                symbol: "tray.full.fill",
                showsRetryAction: false
            )
        case .deleting:
            return Self(
                state: state,
                count: count,
                retryCount: retryCount,
                title: "Deleting profile data",
                message:
                    "\(count) deleted \(profile) \(verb) already gone from this device. Tada Words is finishing iCloud cleanup.",
                symbol: "trash.fill",
                showsRetryAction: false
            )
        case .waitingForConnection:
            return Self(
                state: state,
                count: count,
                retryCount: retryCount,
                title: "Deletion is safely waiting",
                message:
                    "\(count) deleted \(profile) \(verb) gone from this device. Tada Words will retry when iCloud is available.",
                symbol: "wifi.slash",
                showsRetryAction: isFamilySyncEnabled
            )
        case .waitingForFamilySync:
            return Self(
                state: state,
                count: count,
                retryCount: retryCount,
                title: "Deletion waiting for Family Sync",
                message:
                    "\(count) deleted \(profile) \(verb) already gone from this device. Turn on Family Sync to finish iCloud cleanup.",
                symbol: "icloud.slash.fill",
                showsRetryAction: false
            )
        case .needsAttention:
            let message =
                isFamilySyncEnabled
                ? "\(count) deleted \(profile) \(verb) gone from this device, but iCloud cleanup needs you to try again."
                : "\(count) deleted \(profile) \(verb) gone from this device. Turn on Family Sync, then try iCloud cleanup again."
            return Self(
                state: state,
                count: count,
                retryCount: retryCount,
                title: "Deletion needs attention",
                message: message,
                symbol: "exclamationmark.triangle.fill",
                showsRetryAction: isFamilySyncEnabled
            )
        case .complete:
            return Self(
                state: state,
                count: count,
                retryCount: retryCount,
                title: "Profile removal complete",
                message: "Remote cleanup for \(count) deleted \(profile) has finished.",
                symbol: "checkmark.circle.fill",
                showsRetryAction: false
            )
        case .unavailable:
            return .unavailable
        }
    }
}

extension FamilySyncStatus {
    fileprivate var isOptedOut: Bool {
        if case .optedOut = self { return true }
        return false
    }
}

@MainActor
struct GuardianFamilySyncView: View {
    let status: FamilySyncStatus
    let isEnabled: Bool
    let profileErasure: GuardianProfileErasurePresentation?
    let shareURL: URL?
    let canManageAccess: Bool
    @Binding var shareURLText: String
    let onBack: () -> Void
    let onSetEnabled: @MainActor (Bool) -> Void
    let onSyncNow: () -> Void
    let onCreateShare: () -> Void
    let onManageAccess: () -> Void
    let onAcceptShare: () -> Void
    let onRetryProfileErasure: () -> Void
    @State private var remoteNotificationRegistration:
        FamilySyncRemoteNotificationRegistrationState = .notRequested

    init(
        status: FamilySyncStatus,
        isEnabled: Bool,
        profileErasure: GuardianProfileErasurePresentation? = nil,
        shareURL: URL?,
        canManageAccess: Bool,
        shareURLText: Binding<String>,
        onBack: @escaping () -> Void,
        onSetEnabled: @escaping @MainActor (Bool) -> Void,
        onSyncNow: @escaping () -> Void,
        onCreateShare: @escaping () -> Void,
        onManageAccess: @escaping () -> Void,
        onAcceptShare: @escaping () -> Void,
        onRetryProfileErasure: @escaping () -> Void = {}
    ) {
        self.status = status
        self.isEnabled = isEnabled
        self.profileErasure = profileErasure
        self.shareURL = shareURL
        self.canManageAccess = canManageAccess
        _shareURLText = shareURLText
        self.onBack = onBack
        self.onSetEnabled = onSetEnabled
        self.onSyncNow = onSyncNow
        self.onCreateShare = onCreateShare
        self.onManageAccess = onManageAccess
        self.onAcceptShare = onAcceptShare
        self.onRetryProfileErasure = onRetryProfileErasure
    }

    private var presentation: GuardianFamilySyncPresentation {
        GuardianFamilySyncPresentation(status: status, isEnabled: isEnabled)
    }

    private var remoteNotificationPresentation: GuardianRemoteNotificationRegistrationPresentation {
        GuardianRemoteNotificationRegistrationPresentation(
            state: remoteNotificationRegistration
        )
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: GuardianPrimitiveTokens.Spacing.large) {
                GuardianNavigationHeader(title: presentation.navigationTitle, onBack: onBack)
                GuardianCard {
                    VStack(alignment: .leading, spacing: 12) {
                        Label(presentation.title, systemImage: presentation.symbol)
                            .font(.system(.title3, design: .rounded, weight: .bold))
                            .accessibilityIdentifier("guardian.sync.status")
                        Text(presentation.message)
                            .foregroundStyle(GuardianSemanticTokens.secondaryForeground)
                        Divider()
                        Label(
                            remoteNotificationPresentation.title,
                            systemImage: remoteNotificationPresentation.symbol
                        )
                        .font(.system(.headline, design: .rounded, weight: .bold))
                        .accessibilityIdentifier("guardian.sync.push-registration")
                        Text(remoteNotificationPresentation.message)
                            .foregroundStyle(GuardianSemanticTokens.secondaryForeground)
                        if presentation.showsSyncAction {
                            Button("Sync now", action: onSyncNow)
                                .buttonStyle(.borderedProminent)
                                .accessibilityIdentifier("guardian.sync.now")
                        }
                        ShareLink(
                            item: GuardianFamilySyncDiagnosticReport(
                                status: status,
                                isEnabled: isEnabled,
                                profileErasure: profileErasure,
                                remoteNotificationRegistration:
                                    remoteNotificationRegistration
                            ).text
                        ) {
                            Label(
                                "Share diagnostics",
                                systemImage: "doc.text.magnifyingglass"
                            )
                        }
                        .buttonStyle(.bordered)
                        .accessibilityIdentifier("guardian.sync.diagnostics")
                    }
                }

                if let profileErasure {
                    GuardianCard {
                        VStack(alignment: .leading, spacing: 12) {
                            Label(
                                profileErasure.title,
                                systemImage: profileErasure.symbol
                            )
                            .font(.system(.title3, design: .rounded, weight: .bold))
                            .accessibilityIdentifier("guardian.sync.erasure-status")

                            Text(profileErasure.message)
                                .foregroundStyle(
                                    GuardianSemanticTokens.secondaryForeground
                                )

                            if profileErasure.showsRetryAction {
                                Button("Try again", action: onRetryProfileErasure)
                                    .buttonStyle(.borderedProminent)
                                    .accessibilityIdentifier(
                                        "guardian.sync.erasure.retry"
                                    )
                            }
                        }
                    }
                    .accessibilityIdentifier("guardian.sync.erasure-card")
                }

                if presentation.showsPreferenceToggle {
                    GuardianCard {
                        VStack(alignment: .leading, spacing: 12) {
                            Toggle(
                                "Sync learning data with iCloud",
                                isOn: Binding(
                                    get: { isEnabled },
                                    set: { newValue in
                                        onSetEnabled(newValue)
                                    }
                                )
                            )
                            .font(.system(.headline, design: .rounded, weight: .bold))
                            .accessibilityIdentifier("guardian.sync.enabled")
                            Text(
                                "Turning this on sends profiles, word lists, progress, settings, and rewards to your iCloud. Voiceprints and raw recordings never sync. Turning it off stops future sync but does not erase records already uploaded."
                            )
                            .foregroundStyle(GuardianSemanticTokens.secondaryForeground)
                        }
                    }
                }

                if presentation.showsInvitationActions {
                    GuardianCard {
                        VStack(alignment: .leading, spacing: 12) {
                            Text("Invite another parent")
                                .font(.system(.headline, design: .rounded, weight: .bold))
                            Text("Invitations use Apple iCloud sharing.")
                                .foregroundStyle(GuardianSemanticTokens.secondaryForeground)
                            Button("Create invitation", action: onCreateShare)
                                .buttonStyle(.bordered)
                            if canManageAccess {
                                Button(action: onManageAccess) {
                                    Label(
                                        "Manage access",
                                        systemImage: "person.2.badge.gearshape"
                                    )
                                }
                                .buttonStyle(.bordered)
                                .accessibilityIdentifier(
                                    "guardian.sync.manage-access"
                                )
                            }
                            if let shareURL {
                                ShareLink(item: shareURL) {
                                    Label("Share invitation", systemImage: "square.and.arrow.up")
                                }
                                .buttonStyle(.borderedProminent)
                            }
                        }
                    }

                    GuardianCard {
                        VStack(alignment: .leading, spacing: 12) {
                            Text("Join a family")
                                .font(.system(.headline, design: .rounded, weight: .bold))
                            TextField("Paste invitation link", text: $shareURLText)
                                .textFieldStyle(.roundedBorder)
                            Button("Accept invitation", action: onAcceptShare)
                                .buttonStyle(.borderedProminent)
                        }
                    }
                }
            }
            .frame(maxWidth: 760, alignment: .leading)
            .padding(GuardianPrimitiveTokens.Spacing.large)
            .frame(maxWidth: .infinity)
        }
        .task {
            let states = await FamilySyncRemoteNotificationBridge.shared
                .registrationStates()
            for await state in states {
                guard !Task.isCancelled else { break }
                remoteNotificationRegistration = state
            }
        }
        .accessibilityIdentifier("guardian.sync.page")
    }
}

struct GuardianVoiceprintEnrollmentView: View {
    let profile: KidProfile
    let progress: VoiceprintEnrollmentProgress?
    let isCapturing: Bool
    let currentSentence: String?
    let currentSampleNumber: Int
    let sampleCount: Int
    let isPlayingPrompt: Bool
    let guidanceMessage: String?
    let onBack: () -> Void
    let onBegin: () -> Void
    let onReplaySentence: () -> Void
    let onCapture: () -> Void
    let onFinish: () -> Void

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: GuardianPrimitiveTokens.Spacing.large) {
                GuardianNavigationHeader(title: "Voice setup", onBack: onBack)
                GuardianCard {
                    VStack(alignment: .leading, spacing: 14) {
                        Label("One-minute voice setup", systemImage: "waveform.badge.mic")
                            .font(.system(.title2, design: .rounded, weight: .bold))
                        Text(
                            "\(profile.displayName) will hear and repeat \(sampleCount) short sentences. Use one child’s voice in a quiet spot."
                        )
                        ProgressView(value: progressValue)
                        Text(progressText)
                            .font(.system(.subheadline, design: .rounded, weight: .semibold))
                            .monospacedDigit()

                        if progress == nil {
                            Button("Start voice setup", action: onBegin)
                                .buttonStyle(.borderedProminent)
                        } else {
                            if let currentSentence {
                                VStack(alignment: .leading, spacing: 8) {
                                    Text("SAMPLE \(currentSampleNumber) OF \(sampleCount)")
                                        .font(.system(.caption, design: .rounded, weight: .heavy))
                                        .foregroundStyle(
                                            GuardianSemanticTokens.secondaryForeground
                                        )
                                    Text("“\(currentSentence)”")
                                        .font(.system(.title2, design: .rounded, weight: .bold))
                                        .fixedSize(horizontal: false, vertical: true)
                                }
                                .padding(16)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .background(
                                    GuardianSemanticTokens.primary.opacity(0.09),
                                    in: RoundedRectangle(cornerRadius: 18)
                                )

                                HStack(spacing: 12) {
                                    Button(action: onReplaySentence) {
                                        Label(
                                            isPlayingPrompt ? "Playing…" : "Hear sentence",
                                            systemImage: "speaker.wave.2.fill"
                                        )
                                    }
                                    .buttonStyle(.bordered)
                                    .disabled(isCapturing || isPlayingPrompt)

                                    Button(action: onCapture) {
                                        Label(
                                            isCapturing ? "Listening…" : "Record and repeat",
                                            systemImage: isCapturing
                                                ? "waveform"
                                                : "mic.circle.fill"
                                        )
                                    }
                                    .buttonStyle(.borderedProminent)
                                    .disabled(isCapturing || isPlayingPrompt)
                                }
                            }

                            if let guidanceMessage {
                                Label(
                                    guidanceMessage,
                                    systemImage: isCapturing ? "waveform" : "sparkles"
                                )
                                .font(.system(.subheadline, design: .rounded, weight: .semibold))
                                .foregroundStyle(GuardianSemanticTokens.secondaryForeground)
                            }

                            Button("Finish setup", action: onFinish)
                                .buttonStyle(.bordered)
                                .disabled(
                                    progress?.isReadyToFinalize != true
                                        || isCapturing
                                        || isPlayingPrompt
                                )
                        }

                        Label(
                            "Audio stays in memory only while each sample is analyzed. Recordings are never saved or synced.",
                            systemImage: "lock.shield.fill"
                        )
                        .font(.system(.caption, design: .rounded, weight: .medium))
                        .foregroundStyle(GuardianSemanticTokens.secondaryForeground)
                    }
                }
                Spacer()
            }
            .frame(maxWidth: 760, alignment: .leading)
            .padding(GuardianPrimitiveTokens.Spacing.large)
            .frame(maxWidth: .infinity)
        }
        .scrollIndicators(.hidden)
    }

    private var progressValue: Double {
        guard let progress else { return 0 }
        return min(1, Double(progress.acceptedSegmentCount) / Double(max(1, sampleCount)))
    }

    private var progressText: String {
        guard let progress else {
            return "Usually finished in about one minute."
        }
        return
            "\(progress.acceptedSegmentCount) of \(sampleCount) clear samples · \(Int(progress.acceptedSpeechDuration.seconds)) seconds"
    }
}
