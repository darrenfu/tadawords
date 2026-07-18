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
        generatedAt: Date = Date()
    ) {
        var fields = [
            "Tada Words Family Sync Diagnostics",
            "Schema: 1",
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
    let shareURL: URL?
    let canManageAccess: Bool
    @Binding var shareURLText: String
    let onBack: () -> Void
    let onSetEnabled: @MainActor (Bool) -> Void
    let onSyncNow: () -> Void
    let onCreateShare: () -> Void
    let onManageAccess: () -> Void
    let onAcceptShare: () -> Void

    private var presentation: GuardianFamilySyncPresentation {
        GuardianFamilySyncPresentation(status: status, isEnabled: isEnabled)
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
                        if presentation.showsSyncAction {
                            Button("Sync now", action: onSyncNow)
                                .buttonStyle(.borderedProminent)
                                .accessibilityIdentifier("guardian.sync.now")
                        }
                        ShareLink(
                            item: GuardianFamilySyncDiagnosticReport(
                                status: status,
                                isEnabled: isEnabled
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
