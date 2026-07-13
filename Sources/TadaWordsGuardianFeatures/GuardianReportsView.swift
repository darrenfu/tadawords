import SwiftUI
import TadaWordsDomain

struct GuardianReportsView: View {
    let report: GuardianLearningReport?
    let selectedPeriod: GuardianReportPeriod
    let onBack: () -> Void
    let onSelectPeriod: (GuardianReportPeriod) -> Void
    let onCorrect: (AttemptID, AttemptOutcome) -> Void
    let onAuthorizeExport: () async -> Bool
    @State private var exportIsAuthorized = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: GuardianPrimitiveTokens.Spacing.large) {
                GuardianNavigationHeader(title: "Learning report", onBack: onBack)
                periodPicker

                if let report {
                    summary(report)
                    wordDetails(report)
                    if exportIsAuthorized {
                        ShareLink(item: report.csv) {
                            Label("Export CSV", systemImage: "square.and.arrow.up")
                        }
                        .buttonStyle(GuardianPrimaryButtonStyle())
                        .accessibilityHint("Shares a CSV copy of this report")
                    } else {
                        Button {
                            Task {
                                exportIsAuthorized = await onAuthorizeExport()
                            }
                        } label: {
                            Label("Unlock CSV export", systemImage: "lock.shield.fill")
                        }
                        .buttonStyle(GuardianPrimaryButtonStyle())
                    }
                } else {
                    GuardianCard {
                        ProgressView("Loading report…")
                            .frame(maxWidth: .infinity, minHeight: 120)
                    }
                }
            }
            .frame(maxWidth: 960, alignment: .leading)
            .padding(.horizontal, GuardianPrimitiveTokens.Spacing.medium)
            .padding(.vertical, GuardianPrimitiveTokens.Spacing.large)
            .frame(maxWidth: .infinity)
        }
        .scrollIndicators(.hidden)
    }

    private var periodPicker: some View {
        Picker(
            "Report period",
            selection: Binding(
                get: { selectedPeriod },
                set: { period in onSelectPeriod(period) }
            )
        ) {
            ForEach(GuardianReportPeriod.allCases, id: \.self) { period in
                Text(period.title).tag(period)
            }
        }
        .pickerStyle(.segmented)
        .frame(maxWidth: 420)
    }

    private func summary(_ report: GuardianLearningReport) -> some View {
        GuardianCard {
            VStack(alignment: .leading, spacing: GuardianPrimitiveTokens.Spacing.medium) {
                Text("Overview")
                    .font(.system(.title3, design: .rounded, weight: .bold))
                ViewThatFits(in: .horizontal) {
                    HStack(spacing: GuardianPrimitiveTokens.Spacing.large) {
                        metric("Quests", value: "\(report.completedQuestCount)")
                        metric("Points", value: "\(report.totalPoints)")
                        metric("Stars", value: "\(report.totalStars)")
                        metric(
                            "Accuracy",
                            value: percentage(report.trend.currentAccuracy)
                        )
                    }
                    VStack(alignment: .leading) {
                        metric("Quests", value: "\(report.completedQuestCount)")
                        metric("Points", value: "\(report.totalPoints)")
                        metric("Stars", value: "\(report.totalStars)")
                        metric(
                            "Accuracy",
                            value: percentage(report.trend.currentAccuracy)
                        )
                    }
                }

                Text(trendText(report.trend))
                    .font(.system(.subheadline, design: .rounded, weight: .medium))
                    .foregroundStyle(GuardianSemanticTokens.secondaryForeground)
            }
        }
    }

    private func wordDetails(_ report: GuardianLearningReport) -> some View {
        VStack(alignment: .leading, spacing: GuardianPrimitiveTokens.Spacing.medium) {
            Text("Word details")
                .font(.system(.title3, design: .rounded, weight: .bold))

            if report.words.isEmpty {
                GuardianCard {
                    Text("No independent attempts in this period yet.")
                        .font(.system(.body, design: .rounded, weight: .medium))
                }
            } else {
                ForEach(report.words) { word in
                    GuardianCard {
                        DisclosureGroup {
                            VStack(alignment: .leading, spacing: 12) {
                                ForEach(word.recentAttempts) { attempt in
                                    attemptRow(attempt)
                                }
                            }
                            .padding(.top, 10)
                        } label: {
                            HStack {
                                VStack(alignment: .leading, spacing: 3) {
                                    Text(word.prompt.displayText)
                                        .font(.system(.headline, design: .rounded, weight: .bold))
                                    Text(
                                        "\(word.correctCount) of \(word.independentAttemptCount) · \(percentage(word.accuracy))"
                                    )
                                    .font(.system(.caption, design: .rounded, weight: .medium))
                                    .foregroundStyle(GuardianSemanticTokens.secondaryForeground)
                                }
                                Spacer()
                                GuardianModeBadge(mode: word.prompt.learningMode)
                            }
                        }
                    }
                }
            }
        }
    }

    private func attemptRow(_ attempt: GuardianAttemptDetail) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Label(
                    attempt.effectiveOutcome.guardianTitle,
                    systemImage: attempt.effectiveOutcome.isCorrect
                        ? "checkmark.circle.fill"
                        : "xmark.circle.fill"
                )
                .font(.system(.subheadline, design: .rounded, weight: .semibold))
                Spacer()
                if let responseTime = attempt.responseTime {
                    Text(String(format: "%.1f sec", responseTime.seconds))
                        .monospacedDigit()
                }
                if attempt.wasCorrected {
                    Text("Corrected")
                        .foregroundStyle(GuardianSemanticTokens.primary)
                }
            }

            HStack {
                Text("Recognition wrong?")
                    .font(.system(.caption, design: .rounded, weight: .medium))
                    .foregroundStyle(GuardianSemanticTokens.secondaryForeground)
                Spacer()
                Button("Mark correct") {
                    onCorrect(attempt.id, .correct)
                }
                .buttonStyle(.bordered)
                Button("Mark incorrect", role: .destructive) {
                    onCorrect(attempt.id, .incorrect)
                }
                .buttonStyle(.bordered)
            }
            .controlSize(.large)
        }
        .padding(.vertical, 4)
    }

    private func metric(_ title: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(value)
                .font(.system(.title2, design: .rounded, weight: .bold))
                .monospacedDigit()
            Text(title)
                .font(.system(.caption, design: .rounded, weight: .medium))
                .foregroundStyle(GuardianSemanticTokens.secondaryForeground)
        }
        .frame(minWidth: 104, alignment: .leading)
    }

    private func percentage(_ value: Double?) -> String {
        guard let value else { return "—" }
        return "\(Int((value * 100).rounded()))%"
    }

    private func trendText(_ trend: GuardianReportTrend) -> String {
        guard let change = trend.accuracyChange else {
            return "Complete more independent attempts to compare with the previous period."
        }
        let points = Int((abs(change) * 100).rounded())
        if points == 0 { return "Accuracy is steady compared with the previous period." }
        return change > 0
            ? "Accuracy improved by \(points) percentage points."
            : "Accuracy is down \(points) percentage points; review the words below."
    }
}

extension AttemptOutcome {
    fileprivate var guardianTitle: String {
        switch self {
        case .correct:
            "Correct"
        case .incorrect:
            "Incorrect"
        case .recognitionUncertain:
            "Uncertain"
        case .technicalFailure:
            "Technical retry"
        case .skipped:
            "Skipped"
        }
    }
}
