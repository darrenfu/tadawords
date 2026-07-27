import SwiftUI

struct GuardianImportReportView: View {
    let report: GuardianWordImportReport
    let onAddMore: () -> Void
    let onDone: () -> Void

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: GuardianPrimitiveTokens.Spacing.large) {
                HStack {
                    VStack(alignment: .leading, spacing: 3) {
                        Text("Import complete")
                            .font(.system(.largeTitle, design: .rounded, weight: .bold))
                        Text(
                            "\(report.processedCount) \(report.processedCount == 1 ? "entry" : "entries") checked"
                        )
                        .font(.system(.body, design: .rounded, weight: .medium))
                        .foregroundStyle(GuardianSemanticTokens.secondaryForeground)
                    }

                    Spacer()

                    GuardianModeBadge(mode: report.learningMode, includesPoolSuffix: true)
                }

                resultSummary

                if !report.accepted.isEmpty {
                    GuardianImportSection(
                        title: "Added",
                        symbol: "checkmark.circle.fill",
                        tint: GuardianSemanticTokens.success,
                        rows: report.accepted.map { GuardianImportRow(title: $0) }
                    )
                }

                if !report.duplicates.isEmpty {
                    GuardianImportSection(
                        title: "Already there",
                        symbol: "arrow.triangle.2.circlepath.circle.fill",
                        tint: GuardianPrimitiveTokens.ColorValue.orange,
                        rows: report.duplicates.map {
                            GuardianImportRow(
                                title: $0,
                                detail:
                                    "Kept the existing \(report.learningMode.guardianTitle) Pool entry."
                            )
                        }
                    )
                }

                if !report.rejected.isEmpty {
                    GuardianImportSection(
                        title: "Couldn’t add",
                        symbol: "exclamationmark.circle.fill",
                        tint: GuardianSemanticTokens.destructive,
                        rows: report.rejected.map {
                            GuardianImportRow(title: $0.sourceText, detail: $0.reason)
                        }
                    )
                }

                ViewThatFits(in: .horizontal) {
                    HStack(spacing: GuardianPrimitiveTokens.Spacing.medium) {
                        actionButtons
                    }
                    VStack(spacing: GuardianPrimitiveTokens.Spacing.small) {
                        actionButtons
                    }
                }
            }
            .frame(maxWidth: 760, alignment: .leading)
            .guardianParentPageInsets()
            .frame(maxWidth: .infinity)
        }
    }

    private var resultSummary: some View {
        HStack(spacing: GuardianPrimitiveTokens.Spacing.small) {
            GuardianReportCount(
                title: "Added",
                count: report.accepted.count,
                tint: GuardianSemanticTokens.success
            )
            GuardianReportCount(
                title: "Already there",
                count: report.duplicates.count,
                tint: GuardianPrimitiveTokens.ColorValue.orange
            )
            GuardianReportCount(
                title: "Couldn’t add",
                count: report.rejected.count,
                tint: GuardianSemanticTokens.destructive
            )
        }
    }

    @ViewBuilder
    private var actionButtons: some View {
        Button("Add more", action: onAddMore)
            .buttonStyle(
                GuardianSecondaryButtonStyle(
                    tint: GuardianSemanticTokens.accent(for: report.learningMode)
                )
            )
        Button("Done", action: onDone)
            .buttonStyle(GuardianPrimaryButtonStyle())
    }
}

private struct GuardianReportCount: View {
    let title: String
    let count: Int
    let tint: Color

    var body: some View {
        VStack(spacing: 4) {
            Text("\(count)")
                .font(.system(.title2, design: .rounded, weight: .bold))
                .monospacedDigit()
            Text(title)
                .font(.system(.caption, design: .rounded, weight: .semibold))
                .lineLimit(1)
                .minimumScaleFactor(0.75)
        }
        .frame(maxWidth: .infinity, minHeight: 78)
        .foregroundStyle(tint)
        .background(
            tint.opacity(0.09),
            in: RoundedRectangle(
                cornerRadius: GuardianPrimitiveTokens.Radius.medium,
                style: .continuous
            )
        )
        .accessibilityElement(children: .combine)
    }
}

private struct GuardianImportSection: View {
    let title: String
    let symbol: String
    let tint: Color
    let rows: [GuardianImportRow]

    var body: some View {
        GuardianCard {
            VStack(alignment: .leading, spacing: GuardianPrimitiveTokens.Spacing.medium) {
                Label(title, systemImage: symbol)
                    .font(.system(.headline, design: .rounded, weight: .bold))
                    .foregroundStyle(tint)

                ForEach(Array(rows.enumerated()), id: \.offset) { _, row in
                    VStack(alignment: .leading, spacing: 3) {
                        Text(row.title)
                            .font(.system(.body, design: .rounded, weight: .semibold))
                        if let detail = row.detail {
                            Text(detail)
                                .font(.system(.subheadline, design: .rounded, weight: .medium))
                                .foregroundStyle(GuardianSemanticTokens.secondaryForeground)
                        }
                    }
                    .accessibilityElement(children: .combine)
                }
            }
        }
    }
}

private struct GuardianImportRow {
    let title: String
    var detail: String?
}
