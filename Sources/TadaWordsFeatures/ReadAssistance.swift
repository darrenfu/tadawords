import Foundation

struct WordPictureHint: Equatable, Sendable {
    let glyph: String
    let accessibilityLabel: String
}

/// Read help stays locked until two genuine wrong answers. Silence, permission
/// failures, and recognizer uncertainty never reveal the answer early.
enum ReadAssistancePolicy {
    static let incorrectAttemptThreshold = 2

    static func shouldReveal(
        validIncorrectAttemptCount: Int,
        isComplete: Bool
    ) -> Bool {
        !isComplete
            && validIncorrectAttemptCount >= incorrectAttemptThreshold
    }
}

/// Small, local and deterministic picture vocabulary. A missing entry returns
/// nil rather than guessing at a meaning for a parent-provided word.
enum WordPictureHintCatalog {
    private static let hints: [String: WordPictureHint] = [
        "airplane": .init(glyph: "✈️", accessibilityLabel: "an airplane"),
        "apple": .init(glyph: "🍎", accessibilityLabel: "an apple"),
        "baby": .init(glyph: "👶", accessibilityLabel: "a baby"),
        "ball": .init(glyph: "⚽️", accessibilityLabel: "a ball"),
        "banana": .init(glyph: "🍌", accessibilityLabel: "a banana"),
        "bear": .init(glyph: "🐻", accessibilityLabel: "a bear"),
        "bee": .init(glyph: "🐝", accessibilityLabel: "a bee"),
        "bicycle": .init(glyph: "🚲", accessibilityLabel: "a bicycle"),
        "bike": .init(glyph: "🚲", accessibilityLabel: "a bicycle"),
        "bird": .init(glyph: "🐦", accessibilityLabel: "a bird"),
        "boat": .init(glyph: "⛵️", accessibilityLabel: "a boat"),
        "book": .init(glyph: "📖", accessibilityLabel: "a book"),
        "bus": .init(glyph: "🚌", accessibilityLabel: "a bus"),
        "cake": .init(glyph: "🎂", accessibilityLabel: "a cake"),
        "car": .init(glyph: "🚗", accessibilityLabel: "a car"),
        "cat": .init(glyph: "🐱", accessibilityLabel: "a cat"),
        "chair": .init(glyph: "🪑", accessibilityLabel: "a chair"),
        "cheese": .init(glyph: "🧀", accessibilityLabel: "cheese"),
        "chicken": .init(glyph: "🐔", accessibilityLabel: "a chicken"),
        "cloud": .init(glyph: "☁️", accessibilityLabel: "a cloud"),
        "cookie": .init(glyph: "🍪", accessibilityLabel: "a cookie"),
        "cow": .init(glyph: "🐮", accessibilityLabel: "a cow"),
        "dog": .init(glyph: "🐶", accessibilityLabel: "a dog"),
        "duck": .init(glyph: "🦆", accessibilityLabel: "a duck"),
        "egg": .init(glyph: "🥚", accessibilityLabel: "an egg"),
        "elephant": .init(glyph: "🐘", accessibilityLabel: "an elephant"),
        "eye": .init(glyph: "👁️", accessibilityLabel: "an eye"),
        "fire": .init(glyph: "🔥", accessibilityLabel: "fire"),
        "fish": .init(glyph: "🐟", accessibilityLabel: "a fish"),
        "flower": .init(glyph: "🌼", accessibilityLabel: "a flower"),
        "frog": .init(glyph: "🐸", accessibilityLabel: "a frog"),
        "gift": .init(glyph: "🎁", accessibilityLabel: "a gift"),
        "grapes": .init(glyph: "🍇", accessibilityLabel: "grapes"),
        "hand": .init(glyph: "✋", accessibilityLabel: "a hand"),
        "heart": .init(glyph: "❤️", accessibilityLabel: "a heart"),
        "horse": .init(glyph: "🐴", accessibilityLabel: "a horse"),
        "house": .init(glyph: "🏠", accessibilityLabel: "a house"),
        "ice": .init(glyph: "🧊", accessibilityLabel: "ice"),
        "key": .init(glyph: "🔑", accessibilityLabel: "a key"),
        "lion": .init(glyph: "🦁", accessibilityLabel: "a lion"),
        "milk": .init(glyph: "🥛", accessibilityLabel: "milk"),
        "moon": .init(glyph: "🌙", accessibilityLabel: "the moon"),
        "mouse": .init(glyph: "🐭", accessibilityLabel: "a mouse"),
        "orange": .init(glyph: "🍊", accessibilityLabel: "an orange"),
        "pen": .init(glyph: "🖊️", accessibilityLabel: "a pen"),
        "pencil": .init(glyph: "✏️", accessibilityLabel: "a pencil"),
        "pig": .init(glyph: "🐷", accessibilityLabel: "a pig"),
        "pizza": .init(glyph: "🍕", accessibilityLabel: "pizza"),
        "rabbit": .init(glyph: "🐰", accessibilityLabel: "a rabbit"),
        "rain": .init(glyph: "🌧️", accessibilityLabel: "rain"),
        "rainbow": .init(glyph: "🌈", accessibilityLabel: "a rainbow"),
        "sheep": .init(glyph: "🐑", accessibilityLabel: "a sheep"),
        "shoe": .init(glyph: "👟", accessibilityLabel: "a shoe"),
        "snow": .init(glyph: "❄️", accessibilityLabel: "snow"),
        "star": .init(glyph: "⭐️", accessibilityLabel: "a star"),
        "sun": .init(glyph: "☀️", accessibilityLabel: "the sun"),
        "tiger": .init(glyph: "🐯", accessibilityLabel: "a tiger"),
        "train": .init(glyph: "🚂", accessibilityLabel: "a train"),
        "tree": .init(glyph: "🌳", accessibilityLabel: "a tree"),
        "truck": .init(glyph: "🚚", accessibilityLabel: "a truck"),
        "turtle": .init(glyph: "🐢", accessibilityLabel: "a turtle"),
        "water": .init(glyph: "💧", accessibilityLabel: "water"),
    ]

    static func hint(for rawWord: String) -> WordPictureHint? {
        hints[normalized(rawWord)]
    }

    private static func normalized(_ rawWord: String) -> String {
        rawWord
            .folding(options: [.diacriticInsensitive], locale: .current)
            .lowercased(with: Locale(identifier: "en_US_POSIX"))
            .components(separatedBy: CharacterSet.letters.inverted)
            .filter { !$0.isEmpty }
            .joined(separator: " ")
    }
}
