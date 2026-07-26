import SwiftUI
import TadaWordsDesignSystem
import TadaWordsDomain

struct KidBackButton: View {
    let theme: TadaWorldTheme
    let destinationHint: String
    var accessibilityIdentifier: String?
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: "chevron.left")
                .font(.system(.title3, design: .rounded, weight: .bold))
                .frame(
                    width: TadaPrimitiveTokens.TouchTarget.minimum,
                    height: TadaPrimitiveTokens.TouchTarget.minimum
                )
                .contentShape(Circle())
        }
        .buttonStyle(
            KidCircularIconButtonStyle(
                fill: theme.surface.opacity(0.78),
                foreground: theme.ink.opacity(0.76)
            )
        )
        .accessibilityLabel("Back")
        .accessibilityHint(destinationHint)
        .accessibilityIdentifier(accessibilityIdentifier ?? "child.back")
    }
}

private struct KidCircularIconButtonStyle: ButtonStyle {
    let fill: Color
    let foreground: Color

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .foregroundStyle(foreground)
            .background(fill, in: Circle())
            .overlay {
                Circle().strokeBorder(Color.white.opacity(0.52), lineWidth: 1)
            }
            .scaleEffect(configuration.isPressed ? 0.92 : 1)
            .opacity(configuration.isPressed ? 0.76 : 1)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }
}

struct QuestChrome: View {
    let mode: LearningMode
    let currentItem: Int
    let totalItems: Int
    let earnedStars: Int
    let starFeedback: QuestStarFeedbackEvent?
    let elapsedText: String
    let isEmergency: Bool
    let theme: TadaWorldTheme
    var isHeightConstrained = false
    let onBack: () -> Void
    let onPause: () -> Void

    var body: some View {
        ViewThatFits(in: .horizontal) {
            fullChrome
            compactChrome
            ScrollView(.horizontal) {
                compactChrome
                    .fixedSize(horizontal: true, vertical: false)
            }
            .scrollIndicators(.hidden)
        }
        .padding(.horizontal, TadaPrimitiveTokens.Spacing.medium)
        .frame(minHeight: isHeightConstrained ? 44 : 52)
    }

    private var fullChrome: some View {
        HStack(spacing: TadaPrimitiveTokens.Spacing.medium) {
            backButton

            HStack(spacing: TadaPrimitiveTokens.Spacing.small) {
                TadaModeMark(tokens: modeTokens, size: 38)
                Text(mode.title)
                    .font(.system(.subheadline, design: .rounded, weight: .bold))
                    .foregroundStyle(modeTokens.accent)
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("\(mode.title) quest")

            starProgress

            Text("\(currentItem) of \(totalItems)")
                .font(.system(.caption, design: .rounded, weight: .semibold))
                .foregroundStyle(theme.ink.opacity(0.56))
                .accessibilityHidden(true)

            Spacer(minLength: TadaPrimitiveTokens.Spacing.small)

            rescueBadge

            timerLabel

            pauseButton
        }
    }

    private var compactChrome: some View {
        HStack(spacing: TadaLayoutTokens.questChromeCompactSpacing) {
            backButton

            TadaModeMark(tokens: modeTokens, size: 34)
                .accessibilityLabel("\(mode.title) quest")

            starProgress

            Spacer(minLength: 0)
            rescueBadge
            timerLabel
            pauseButton
        }
    }

    private var backButton: some View {
        KidBackButton(
            theme: theme,
            destinationHint: "Returns to the Kid Lobby",
            accessibilityIdentifier: "quest.back",
            action: onBack
        )
    }

    private var starProgress: some View {
        QuestStarProgressBar(
            earnedStarCount: earnedStars,
            totalStarCount: totalItems,
            feedbackEvent: starFeedback,
            accent: modeTokens.accent,
            surface: theme.surface
        )
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Quest progress")
        .accessibilityValue(
            "Item \(currentItem) of \(totalItems). "
                + "\(earnedStars) of \(totalItems) stars"
        )
    }

    @ViewBuilder
    private var rescueBadge: some View {
        if isEmergency {
            HStack(spacing: 4) {
                TadaWorldMascot(theme: theme, pose: .rescue, size: 34)
                Text("Rescue time")
                    .font(.system(.caption, design: .rounded, weight: .bold))
            }
            .foregroundStyle(TadaPrimitiveTokens.ColorValue.warning)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Rescue time is on")
        }
    }

    private var timerLabel: some View {
        Label(elapsedText, systemImage: "timer")
            .font(.system(.subheadline, design: .rounded, weight: .semibold))
            .monospacedDigit()
            .foregroundStyle(
                isEmergency
                    ? TadaPrimitiveTokens.ColorValue.warning
                    : theme.ink.opacity(0.62)
            )
            .accessibilityLabel(
                isEmergency
                    ? "Rescue time. Timer \(spokenTimer)"
                    : "Timer \(spokenTimer)"
            )
    }

    private var pauseButton: some View {
        Button(action: onPause) {
            Image(systemName: "pause.fill")
                .font(.system(.headline, design: .rounded, weight: .bold))
                .frame(
                    width: TadaPrimitiveTokens.TouchTarget.minimum,
                    height: TadaPrimitiveTokens.TouchTarget.minimum
                )
        }
        .buttonStyle(.plain)
        .foregroundStyle(theme.ink.opacity(0.72))
        .background(theme.surface.opacity(0.72), in: Circle())
        .accessibilityLabel("Pause quest")
        .accessibilityHint("Stops the timer and listening")
    }

    private var spokenTimer: String {
        let parts = elapsedText.split(separator: ":").compactMap { Int($0) }
        guard parts.count == 2 else { return elapsedText }
        return "\(parts[0]) minutes, \(parts[1]) seconds"
    }

    private var modeTokens: TadaQuestEntranceTokens {
        switch mode {
        case .read:
            .read(in: theme)
        case .write:
            .write(in: theme)
        }
    }
}

struct QuestPauseOverlay: View {
    let theme: TadaWorldTheme
    let onResume: () -> Void
    let onExit: () -> Void

    var body: some View {
        ZStack {
            Color.black.opacity(0.26)
                .ignoresSafeArea()

            TadaPanel(theme: theme) {
                VStack(spacing: TadaPrimitiveTokens.Spacing.medium) {
                    Image(systemName: "pause.circle.fill")
                        .font(.system(size: 54, weight: .bold))
                        .foregroundStyle(theme.primary)
                        .accessibilityHidden(true)

                    Text("Quest paused")
                        .font(.system(.title, design: .rounded, weight: .bold))
                    Text("The timer and listening are stopped.")
                        .font(.system(.body, design: .rounded, weight: .medium))
                        .foregroundStyle(theme.ink.opacity(0.68))
                        .multilineTextAlignment(.center)

                    Button("Keep going", action: onResume)
                        .buttonStyle(TadaPrimaryButtonStyle(fill: theme.primary))

                    Button("Back to quests", action: onExit)
                        .font(.system(.subheadline, design: .rounded, weight: .semibold))
                        .buttonStyle(.plain)
                        .foregroundStyle(theme.ink.opacity(0.66))
                        .frame(minHeight: TadaPrimitiveTokens.TouchTarget.minimum)
                }
                .frame(maxWidth: 320)
            }
            .padding(TadaPrimitiveTokens.Spacing.large)
        }
        .accessibilityAddTraits(.isModal)
    }
}
