import TadaWordsDesignSystem
import TadaWordsDomain

enum ReadWordColorPolicy {
    static func token(
        worldID: TadaWorldID,
        questID: QuestID,
        promptID: WordPromptID,
        currentItem: Int
    ) -> TadaReadWordColorToken {
        TadaReadWordColorPalette.token(
            for: worldID,
            stableKey: [
                questID.description,
                promptID.description,
                String(currentItem),
            ].joined(separator: "|")
        )
    }
}
