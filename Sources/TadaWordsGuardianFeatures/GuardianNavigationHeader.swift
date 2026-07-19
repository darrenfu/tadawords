import SwiftUI
import TadaWordsDesignSystem

struct GuardianNavigationHeader: View {
    let title: String
    let onBack: () -> Void

    var body: some View {
        HStack(spacing: GuardianPrimitiveTokens.Spacing.medium) {
            Button(action: onBack) {
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
