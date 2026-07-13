import SwiftUI
import TadaWordsDomain

struct GuardianFamilySyncView: View {
    let status: FamilySyncStatus
    let shareURL: URL?
    @Binding var shareURLText: String
    let onBack: () -> Void
    let onSyncNow: () -> Void
    let onCreateShare: () -> Void
    let onAcceptShare: () -> Void

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: GuardianPrimitiveTokens.Spacing.large) {
                GuardianNavigationHeader(title: "Family sync", onBack: onBack)
                GuardianCard {
                    VStack(alignment: .leading, spacing: 12) {
                        Label(statusTitle, systemImage: statusSymbol)
                            .font(.system(.title3, design: .rounded, weight: .bold))
                        Text(statusMessage)
                            .foregroundStyle(GuardianSemanticTokens.secondaryForeground)
                        Button("Sync now", action: onSyncNow)
                            .buttonStyle(.borderedProminent)
                            .disabled(isSyncing)
                    }
                }

                GuardianCard {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Invite another grown-up")
                            .font(.system(.headline, design: .rounded, weight: .bold))
                        Text(
                            "Invitations use Apple iCloud sharing. Learning still works if iCloud is not signed in."
                        )
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
            .frame(maxWidth: 760, alignment: .leading)
            .padding(GuardianPrimitiveTokens.Spacing.large)
            .frame(maxWidth: .infinity)
        }
    }

    private var isSyncing: Bool {
        if case .syncing = status { return true }
        return false
    }

    private var statusTitle: String {
        switch status {
        case .idle: "Ready to sync"
        case .syncing: "Syncing…"
        case .synced: "Up to date"
        case .pendingOffline: "Waiting for a connection"
        case .thisDeviceOnly: "Saved on this device"
        case .failed: "Sync needs attention"
        }
    }

    private var statusMessage: String {
        switch status {
        case .thisDeviceOnly(let message), .failed(let message): message
        case .pendingOffline: "Tada Words will retry without interrupting practice."
        case .synced: "Family learning data is current."
        case .syncing: "Local learning data stays available while this finishes."
        case .idle: "Sync is optional and never blocks a quest."
        }
    }

    private var statusSymbol: String {
        switch status {
        case .synced: "checkmark.icloud.fill"
        case .syncing, .pendingOffline: "arrow.triangle.2.circlepath.icloud"
        case .failed: "exclamationmark.icloud.fill"
        case .idle, .thisDeviceOnly: "externaldrive.fill"
        }
    }
}

struct GuardianVoiceprintEnrollmentView: View {
    let profile: KidProfile
    let progress: VoiceprintEnrollmentProgress?
    let isCapturing: Bool
    let onBack: () -> Void
    let onBegin: () -> Void
    let onCapture: () -> Void
    let onFinish: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: GuardianPrimitiveTokens.Spacing.large) {
            GuardianNavigationHeader(title: "Voice setup", onBack: onBack)
            GuardianCard {
                VStack(alignment: .leading, spacing: 14) {
                    Label("One-minute voice setup", systemImage: "waveform.badge.mic")
                        .font(.system(.title2, design: .rounded, weight: .bold))
                    Text(
                        "Ask \(profile.displayName) to speak naturally in a quiet spot. Audio is processed on this device; recordings are not saved or synced."
                    )
                    ProgressView(value: progressValue)
                    Text(progressText)
                        .font(.system(.subheadline, design: .rounded, weight: .semibold))
                        .monospacedDigit()

                    if progress == nil {
                        Button("Start voice setup", action: onBegin)
                            .buttonStyle(.borderedProminent)
                    } else {
                        Button(action: onCapture) {
                            Label(
                                isCapturing ? "Listening…" : "Record next sample",
                                systemImage: isCapturing ? "waveform" : "mic.circle.fill"
                            )
                        }
                        .buttonStyle(.borderedProminent)
                        .disabled(isCapturing)

                        Button("Finish setup", action: onFinish)
                            .buttonStyle(.bordered)
                            .disabled(progress?.isReadyToFinalize != true || isCapturing)
                    }
                }
            }
            Spacer()
        }
        .frame(maxWidth: 760, alignment: .leading)
        .padding(GuardianPrimitiveTokens.Spacing.large)
        .frame(maxWidth: .infinity)
    }

    private var progressValue: Double {
        guard let progress else { return 0 }
        return min(1, progress.acceptedSpeechDuration.seconds / 15)
    }

    private var progressText: String {
        guard let progress else {
            return "Six short, clear samples are usually enough."
        }
        return
            "\(progress.acceptedSegmentCount) clear samples · \(Int(progress.acceptedSpeechDuration.seconds)) seconds of speech"
    }
}
