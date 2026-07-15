import CoreGraphics

enum GuardianProfileCardLayoutPolicy {
    static let maximumContentWidth: CGFloat = 960
    static let minimumCardWidth: CGFloat = 420
    static let cardSpacing: CGFloat = 16

    static func columnCount(for contentWidth: CGFloat) -> Int {
        let safeWidth = max(contentWidth, 0)
        return max(
            1,
            Int((safeWidth + cardSpacing) / (minimumCardWidth + cardSpacing))
        )
    }

    static func cardWidth(for contentWidth: CGFloat) -> CGFloat {
        let safeWidth = max(contentWidth, 0)
        let columns = CGFloat(columnCount(for: safeWidth))
        let totalSpacing = cardSpacing * (columns - 1)
        return max(0, (safeWidth - totalSpacing) / columns)
    }
}
