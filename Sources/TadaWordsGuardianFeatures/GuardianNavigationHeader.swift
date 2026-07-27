import SwiftUI
import TadaWordsDesignSystem

enum GuardianParentPageLayout {
    static let horizontalInset = GuardianPrimitiveTokens.Spacing.medium
    static let verticalInset = GuardianPrimitiveTokens.Spacing.medium
}

extension View {
    func guardianParentPageInsets() -> some View {
        frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, GuardianParentPageLayout.horizontalInset)
            .padding(.vertical, GuardianParentPageLayout.verticalInset)
    }
}

struct GuardianBackButton: View {
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: "chevron.left")
                .font(.system(.headline, design: .rounded, weight: .bold))
                .frame(
                    width: TadaPrimitiveTokens.TouchTarget.minimum,
                    height: TadaPrimitiveTokens.TouchTarget.minimum
                )
        }
        .buttonStyle(.plain)
        .background(GuardianSemanticTokens.surface, in: Circle())
        .accessibilityLabel("Back")
    }
}

struct GuardianNavigationHeader: View {
    let title: String
    let onBack: () -> Void
    var backAccessibilityIdentifier = "guardian.navigation.back"

    var body: some View {
        HStack(spacing: GuardianPrimitiveTokens.Spacing.medium) {
            GuardianBackButton(action: onBack)
                .accessibilityIdentifier(backAccessibilityIdentifier)

            Text(title)
                .font(.system(.title2, design: .rounded, weight: .bold))
                .lineLimit(2)
                .multilineTextAlignment(.leading)
                .fixedSize(horizontal: false, vertical: true)
                .layoutPriority(1)

            Spacer()
        }
    }
}
