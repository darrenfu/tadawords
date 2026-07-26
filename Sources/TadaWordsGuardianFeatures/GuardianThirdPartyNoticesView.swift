import SwiftUI
import TadaWordsDesignSystem

enum GuardianThirdPartyNoticesContent {
    static let title = "Third-Party Notices"
    static let attribution = "Twemoji graphics © X Corp. and other contributors."
    static let sourceDescription =
        "Tada Words includes 74 unmodified graphics from jdecked/twemoji 17.0.3."
    static let licenseDescription =
        "The graphics are licensed under the Creative Commons Attribution 4.0 International license."
    static let offlineDescription =
        "This notice and the picture-hint graphics are built into Tada Words and remain available offline."

    static let sourceURL = URL(string: "https://github.com/jdecked/twemoji")!
    static let licenseURL = URL(
        string: "https://creativecommons.org/licenses/by/4.0/"
    )!

    static let wordCatalogAttribution =
        "Word-frequency ranking data © Robyn Speer and contributors."
    static let wordCatalogDescription =
        "The disjoint 2,000-word offline and 4,000-word online Bella tiers are selected with wordfreq 3.1.1 data."
    static let wordCatalogLicenseDescription =
        "wordfreq data is available under Creative Commons Attribution-ShareAlike 4.0."
    static let wordCatalogSourceURL = URL(
        string: "https://github.com/rspeer/wordfreq"
    )!
    static let wordCatalogLicenseURL = URL(
        string: "https://creativecommons.org/licenses/by-sa/4.0/"
    )!
}

struct GuardianThirdPartyNoticesView: View {
    let onBack: () -> Void

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: GuardianPrimitiveTokens.Spacing.large) {
                GuardianNavigationHeader(
                    title: GuardianThirdPartyNoticesContent.title,
                    onBack: onBack
                )

                GuardianCard {
                    VStack(
                        alignment: .leading,
                        spacing: GuardianPrimitiveTokens.Spacing.medium
                    ) {
                        Label("Twemoji", systemImage: "face.smiling.inverse")
                            .font(.system(.title2, design: .rounded, weight: .bold))
                            .foregroundStyle(GuardianSemanticTokens.primary)

                        Text(GuardianThirdPartyNoticesContent.attribution)
                            .font(.system(.headline, design: .rounded, weight: .bold))
                            .accessibilityIdentifier(
                                "guardian.third-party-notices.twemoji-attribution"
                            )

                        Text(GuardianThirdPartyNoticesContent.sourceDescription)
                            .font(.system(.body, design: .rounded, weight: .medium))

                        Text(GuardianThirdPartyNoticesContent.licenseDescription)
                            .font(.system(.body, design: .rounded, weight: .medium))

                        Text(GuardianThirdPartyNoticesContent.offlineDescription)
                            .font(.system(.subheadline, design: .rounded, weight: .medium))
                            .foregroundStyle(GuardianSemanticTokens.secondaryForeground)

                        ViewThatFits(in: .horizontal) {
                            HStack(spacing: GuardianPrimitiveTokens.Spacing.small) {
                                resourceLinks
                            }
                            VStack(spacing: GuardianPrimitiveTokens.Spacing.small) {
                                resourceLinks
                            }
                        }
                    }
                }

                GuardianCard {
                    VStack(
                        alignment: .leading,
                        spacing: GuardianPrimitiveTokens.Spacing.medium
                    ) {
                        Label("Teacher word catalog", systemImage: "text.book.closed.fill")
                            .font(.system(.title2, design: .rounded, weight: .bold))
                            .foregroundStyle(GuardianSemanticTokens.primary)

                        Text(GuardianThirdPartyNoticesContent.wordCatalogAttribution)
                            .font(.system(.headline, design: .rounded, weight: .bold))

                        Text(GuardianThirdPartyNoticesContent.wordCatalogDescription)
                            .font(.system(.body, design: .rounded, weight: .medium))

                        Text(
                            GuardianThirdPartyNoticesContent
                                .wordCatalogLicenseDescription
                        )
                        .font(.system(.body, design: .rounded, weight: .medium))

                        ViewThatFits(in: .horizontal) {
                            HStack(spacing: GuardianPrimitiveTokens.Spacing.small) {
                                wordCatalogLinks
                            }
                            VStack(spacing: GuardianPrimitiveTokens.Spacing.small) {
                                wordCatalogLinks
                            }
                        }
                    }
                }
            }
            .frame(maxWidth: 760, alignment: .leading)
            .padding(.horizontal, GuardianPrimitiveTokens.Spacing.medium)
            .padding(.vertical, GuardianPrimitiveTokens.Spacing.large)
            .frame(maxWidth: .infinity)
        }
        .scrollIndicators(.hidden)
        .accessibilityIdentifier("guardian.third-party-notices")
    }

    @ViewBuilder private var resourceLinks: some View {
        GuardianNoticeLink(
            title: "Source project",
            symbol: "chevron.left.forwardslash.chevron.right",
            destination: GuardianThirdPartyNoticesContent.sourceURL,
            accessibilityIdentifier: "guardian.third-party-notices.source"
        )
        GuardianNoticeLink(
            title: "CC BY 4.0 license",
            symbol: "doc.text.fill",
            destination: GuardianThirdPartyNoticesContent.licenseURL,
            accessibilityIdentifier: "guardian.third-party-notices.license"
        )
    }

    @ViewBuilder private var wordCatalogLinks: some View {
        GuardianNoticeLink(
            title: "wordfreq source",
            symbol: "chevron.left.forwardslash.chevron.right",
            destination: GuardianThirdPartyNoticesContent.wordCatalogSourceURL,
            accessibilityIdentifier: "guardian.third-party-notices.wordfreq-source"
        )
        GuardianNoticeLink(
            title: "CC BY-SA 4.0 license",
            symbol: "doc.text.fill",
            destination: GuardianThirdPartyNoticesContent.wordCatalogLicenseURL,
            accessibilityIdentifier: "guardian.third-party-notices.wordfreq-license"
        )
    }
}

private struct GuardianNoticeLink: View {
    let title: String
    let symbol: String
    let destination: URL
    let accessibilityIdentifier: String

    var body: some View {
        Link(destination: destination) {
            Label(title, systemImage: symbol)
                .font(.system(.headline, design: .rounded, weight: .bold))
                .frame(
                    maxWidth: .infinity,
                    minHeight: TadaPrimitiveTokens.TouchTarget.minimum
                )
                .padding(.horizontal, GuardianPrimitiveTokens.Spacing.medium)
                .padding(.vertical, GuardianPrimitiveTokens.Spacing.small)
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
        .accessibilityLabel(title)
        .accessibilityHint("Opens \(title) in your web browser")
        .accessibilityIdentifier(accessibilityIdentifier)
    }
}
