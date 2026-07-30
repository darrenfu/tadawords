import SwiftUI
import TadaWordsDesignSystem
import TadaWordsDomain

enum GuardianSpeechPermissionPresentation {
    static func tileSummary(for state: SpeechPermissionState) -> String {
        if state.isAuthorized {
            return "Ready for Read Practice"
        }
        if state.hasDeniedOrRestrictedPermission {
            return state.hasUndeterminedPermission
                ? "Finish setup; check iOS Settings"
                : "Check iOS Settings"
        }
        return "Parent setup needed"
    }

    static func title(for status: SpeechPermissionStatus) -> String {
        switch status {
        case .notDetermined:
            "Not set up"
        case .restricted:
            "Restricted"
        case .denied:
            "Off"
        case .authorized:
            "Ready"
        }
    }

    static func symbol(for status: SpeechPermissionStatus) -> String {
        switch status {
        case .notDetermined:
            "questionmark.circle.fill"
        case .restricted:
            "exclamationmark.shield.fill"
        case .denied:
            "xmark.circle.fill"
        case .authorized:
            "checkmark.circle.fill"
        }
    }

    static func tint(for status: SpeechPermissionStatus) -> Color {
        switch status {
        case .notDetermined:
            GuardianPrimitiveTokens.ColorValue.orange
        case .restricted, .denied:
            GuardianPrimitiveTokens.ColorValue.red
        case .authorized:
            GuardianSemanticTokens.success
        }
    }
}

struct GuardianSpeechPermissionSetupView: View {
    let state: SpeechPermissionState
    let isRequesting: Bool
    let onBack: () -> Void
    let onRequest: () -> Void

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: GuardianPrimitiveTokens.Spacing.large) {
                GuardianNavigationHeader(title: "Speech & Microphone", onBack: onBack)

                GuardianCard {
                    VStack(alignment: .leading, spacing: GuardianPrimitiveTokens.Spacing.medium) {
                        Label("Set up Read Practice", systemImage: "waveform.badge.mic")
                            .font(.system(.title2, design: .rounded, weight: .bold))
                        Text(
                            "You can review or finish setup here. If access has not been decided, the first microphone tap in Read Practice can also show Apple's Speech Recognition and Microphone prompts."
                        )
                        .font(.system(.body, design: .rounded, weight: .medium))
                        .foregroundStyle(GuardianSemanticTokens.secondaryForeground)

                        permissionRow(
                            title: "Speech Recognition",
                            status: state.speechRecognition,
                            identifier: "guardian.speech-permissions.speech-status"
                        )
                        permissionRow(
                            title: "Microphone",
                            status: state.microphone,
                            identifier: "guardian.speech-permissions.microphone-status"
                        )

                        if state.hasUndeterminedPermission {
                            Button(action: onRequest) {
                                Label(
                                    isRequesting ? "Waiting for iOS…" : "Set up access",
                                    systemImage: "hand.raised.fill"
                                )
                                .frame(maxWidth: .infinity)
                            }
                            .buttonStyle(.borderedProminent)
                            .disabled(isRequesting)
                            .accessibilityIdentifier(
                                "guardian.speech-permissions.request"
                            )
                        }

                        if state.hasDeniedOrRestrictedPermission {
                            Label(
                                "To change an access marked Off or Restricted, open iOS Settings › Apps › Tada Words. Then return here to see the new status.",
                                systemImage: "gearshape.fill"
                            )
                            .font(.system(.subheadline, design: .rounded, weight: .semibold))
                            .foregroundStyle(GuardianSemanticTokens.secondaryForeground)
                            .accessibilityIdentifier(
                                "guardian.speech-permissions.settings-guidance"
                            )
                        } else if state.isAuthorized {
                            Label(
                                "Ready. Your child can record in Read Practice.",
                                systemImage: "checkmark.seal.fill"
                            )
                            .font(.system(.headline, design: .rounded, weight: .bold))
                            .foregroundStyle(GuardianSemanticTokens.success)
                            .accessibilityIdentifier(
                                "guardian.speech-permissions.ready"
                            )
                        }
                    }
                }

                Spacer()
            }
            .frame(maxWidth: 760, alignment: .leading)
            .guardianParentPageInsets()
            .frame(maxWidth: .infinity)
        }
        .scrollIndicators(.hidden)
        .accessibilityIdentifier("guardian.speech-permissions.page")
    }

    private func permissionRow(
        title: String,
        status: SpeechPermissionStatus,
        identifier: String
    ) -> some View {
        HStack(spacing: GuardianPrimitiveTokens.Spacing.medium) {
            Image(systemName: GuardianSpeechPermissionPresentation.symbol(for: status))
                .font(.system(.title3, design: .rounded, weight: .bold))
                .foregroundStyle(GuardianSpeechPermissionPresentation.tint(for: status))
                .frame(width: 30)
                .accessibilityHidden(true)
            Text(title)
                .font(.system(.headline, design: .rounded, weight: .semibold))
            Spacer()
            Text(GuardianSpeechPermissionPresentation.title(for: status))
                .font(.system(.subheadline, design: .rounded, weight: .bold))
                .foregroundStyle(GuardianSpeechPermissionPresentation.tint(for: status))
        }
        .padding(GuardianPrimitiveTokens.Spacing.medium)
        .background(
            GuardianSemanticTokens.background,
            in: RoundedRectangle(
                cornerRadius: GuardianPrimitiveTokens.Radius.medium,
                style: .continuous
            )
        )
        .accessibilityElement(children: .combine)
        .accessibilityLabel(
            "\(title), \(GuardianSpeechPermissionPresentation.title(for: status))"
        )
        .accessibilityIdentifier(identifier)
    }
}
