import TadaWordsDesignSystem

enum ReadWordColorPolicy {
    static func token(worldID: TadaWorldID) -> TadaReadWordColorToken {
        TadaReadWordColorPalette.token(for: worldID)
    }
}
