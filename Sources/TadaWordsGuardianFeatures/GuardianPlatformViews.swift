import SwiftUI
import TadaWordsDomain

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
        case .syncing:
            title = "Syncing…"
            message = "Local learning data stays available while this finishes."
            symbol = "arrow.triangle.2.circlepath.icloud"
            showsSyncAction = false
            showsInvitationActions = false
        case .synced:
            title = "Up to date"
            message = "Family learning data is current."
            symbol = "checkmark.icloud.fill"
            showsSyncAction = true
            showsInvitationActions = true
        case .pendingOffline:
            title = "Waiting for a connection"
            message = "Tada Words will retry without interrupting practice."
            symbol = "arrow.triangle.2.circlepath.icloud"
            showsSyncAction = true
            showsInvitationActions = false
        case .iCloudUnavailable(let message):
            title = "iCloud is unavailable"
            self.message = message
            symbol = "exclamationmark.icloud.fill"
            showsSyncAction = true
            showsInvitationActions = false
        case .failed(let message):
            title = "Sync needs attention"
            self.message = message
            symbol = "exclamationmark.icloud.fill"
            showsSyncAction = true
            showsInvitationActions = false
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
    let shareURL: URL?
    @Binding var shareURLText: String
    let onBack: () -> Void
    let onSetEnabled: @MainActor (Bool) -> Void
    let onSyncNow: () -> Void
    let onCreateShare: () -> Void
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
                        Text(presentation.message)
                            .foregroundStyle(GuardianSemanticTokens.secondaryForeground)
                        if presentation.showsSyncAction {
                            Button("Sync now", action: onSyncNow)
                                .buttonStyle(.borderedProminent)
                        }
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
