import Foundation

/// A deliberately small, concrete-word vocabulary for visual hints. Tada Words
/// never guesses an image for function words or abstract concepts such as
/// `the`, `come`, or `kind`.
public struct WordPictureHintDescriptor: Equatable, Hashable, Sendable {
    public let normalizedWord: String
    public let assetCode: String
    public let accessibilityLabel: String

    public init(
        normalizedWord: String,
        assetCode: String,
        accessibilityLabel: String
    ) {
        self.normalizedWord = normalizedWord
        self.assetCode = assetCode
        self.accessibilityLabel = accessibilityLabel
    }
}

public enum WordPictureHintCatalog {
    /// The unique Twemoji filenames required by the shipping catalog.
    /// Multiple spellings may intentionally share one asset (for example,
    /// `bike` and `bicycle`).
    public static var assetCodes: Set<String> {
        Set(entries.values.map(\.assetCode))
    }

    public static func descriptor(for rawWord: String) -> WordPictureHintDescriptor? {
        guard let normalized = try? EnglishWordNormalizer.normalize(rawWord),
            let entry = entries[normalized]
        else {
            return nil
        }
        return WordPictureHintDescriptor(
            normalizedWord: normalized,
            assetCode: entry.assetCode,
            accessibilityLabel: entry.accessibilityLabel
        )
    }

    private struct Entry {
        let assetCode: String
        let accessibilityLabel: String
    }

    private static let entries: [String: Entry] = [
        "airplane": .init(assetCode: "2708", accessibilityLabel: "an airplane"),
        "ant": .init(assetCode: "1f41c", accessibilityLabel: "an ant"),
        "apple": .init(assetCode: "1f34e", accessibilityLabel: "an apple"),
        "baby": .init(assetCode: "1f476", accessibilityLabel: "a baby"),
        "ball": .init(assetCode: "26bd", accessibilityLabel: "a ball"),
        "banana": .init(assetCode: "1f34c", accessibilityLabel: "a banana"),
        "bear": .init(assetCode: "1f43b", accessibilityLabel: "a bear"),
        "bee": .init(assetCode: "1f41d", accessibilityLabel: "a bee"),
        "bicycle": .init(assetCode: "1f6b2", accessibilityLabel: "a bicycle"),
        "bike": .init(assetCode: "1f6b2", accessibilityLabel: "a bicycle"),
        "bird": .init(assetCode: "1f426", accessibilityLabel: "a bird"),
        "boat": .init(assetCode: "26f5", accessibilityLabel: "a boat"),
        "book": .init(assetCode: "1f4d6", accessibilityLabel: "a book"),
        "bus": .init(assetCode: "1f68c", accessibilityLabel: "a bus"),
        "butterfly": .init(assetCode: "1f98b", accessibilityLabel: "a butterfly"),
        "cake": .init(assetCode: "1f382", accessibilityLabel: "a cake"),
        "candy": .init(assetCode: "1f36c", accessibilityLabel: "candy"),
        "car": .init(assetCode: "1f697", accessibilityLabel: "a car"),
        "cat": .init(assetCode: "1f431", accessibilityLabel: "a cat"),
        "chair": .init(assetCode: "1fa91", accessibilityLabel: "a chair"),
        "cheese": .init(assetCode: "1f9c0", accessibilityLabel: "cheese"),
        "chicken": .init(assetCode: "1f414", accessibilityLabel: "a chicken"),
        "cloud": .init(assetCode: "2601", accessibilityLabel: "a cloud"),
        "cookie": .init(assetCode: "1f36a", accessibilityLabel: "a cookie"),
        "cow": .init(assetCode: "1f42e", accessibilityLabel: "a cow"),
        "dinosaur": .init(assetCode: "1f996", accessibilityLabel: "a dinosaur"),
        "dog": .init(assetCode: "1f436", accessibilityLabel: "a dog"),
        "dragon": .init(assetCode: "1f409", accessibilityLabel: "a dragon"),
        "duck": .init(assetCode: "1f986", accessibilityLabel: "a duck"),
        "egg": .init(assetCode: "1f95a", accessibilityLabel: "an egg"),
        "elephant": .init(assetCode: "1f418", accessibilityLabel: "an elephant"),
        "eye": .init(assetCode: "1f441", accessibilityLabel: "an eye"),
        "fire": .init(assetCode: "1f525", accessibilityLabel: "fire"),
        "fish": .init(assetCode: "1f41f", accessibilityLabel: "a fish"),
        "flower": .init(assetCode: "1f33c", accessibilityLabel: "a flower"),
        "fox": .init(assetCode: "1f98a", accessibilityLabel: "a fox"),
        "frog": .init(assetCode: "1f438", accessibilityLabel: "a frog"),
        "gift": .init(assetCode: "1f381", accessibilityLabel: "a gift"),
        "giraffe": .init(assetCode: "1f992", accessibilityLabel: "a giraffe"),
        "grapes": .init(assetCode: "1f347", accessibilityLabel: "grapes"),
        "hand": .init(assetCode: "270b", accessibilityLabel: "a hand"),
        "heart": .init(assetCode: "2764", accessibilityLabel: "a heart"),
        "horse": .init(assetCode: "1f434", accessibilityLabel: "a horse"),
        "house": .init(assetCode: "1f3e0", accessibilityLabel: "a house"),
        "ice": .init(assetCode: "1f9ca", accessibilityLabel: "ice"),
        "key": .init(assetCode: "1f511", accessibilityLabel: "a key"),
        "lion": .init(assetCode: "1f981", accessibilityLabel: "a lion"),
        "milk": .init(assetCode: "1f95b", accessibilityLabel: "milk"),
        "monkey": .init(assetCode: "1f435", accessibilityLabel: "a monkey"),
        "moon": .init(assetCode: "1f319", accessibilityLabel: "the moon"),
        "mouse": .init(assetCode: "1f42d", accessibilityLabel: "a mouse"),
        "orange": .init(assetCode: "1f34a", accessibilityLabel: "an orange"),
        "owl": .init(assetCode: "1f989", accessibilityLabel: "an owl"),
        "panda": .init(assetCode: "1f43c", accessibilityLabel: "a panda"),
        "pen": .init(assetCode: "1f58a", accessibilityLabel: "a pen"),
        "pencil": .init(assetCode: "270f", accessibilityLabel: "a pencil"),
        "pig": .init(assetCode: "1f437", accessibilityLabel: "a pig"),
        "pizza": .init(assetCode: "1f355", accessibilityLabel: "pizza"),
        "pumpkin": .init(assetCode: "1f383", accessibilityLabel: "a pumpkin"),
        "rabbit": .init(assetCode: "1f430", accessibilityLabel: "a rabbit"),
        "rain": .init(assetCode: "1f327", accessibilityLabel: "rain"),
        "rainbow": .init(assetCode: "1f308", accessibilityLabel: "a rainbow"),
        "robot": .init(assetCode: "1f916", accessibilityLabel: "a robot"),
        "sheep": .init(assetCode: "1f411", accessibilityLabel: "a sheep"),
        "shoe": .init(assetCode: "1f45f", accessibilityLabel: "a shoe"),
        "snow": .init(assetCode: "2744", accessibilityLabel: "snow"),
        "star": .init(assetCode: "2b50", accessibilityLabel: "a star"),
        "sun": .init(assetCode: "2600", accessibilityLabel: "the sun"),
        "tiger": .init(assetCode: "1f42f", accessibilityLabel: "a tiger"),
        "train": .init(assetCode: "1f682", accessibilityLabel: "a train"),
        "tree": .init(assetCode: "1f333", accessibilityLabel: "a tree"),
        "truck": .init(assetCode: "1f69a", accessibilityLabel: "a truck"),
        "turtle": .init(assetCode: "1f422", accessibilityLabel: "a turtle"),
        "unicorn": .init(assetCode: "1f984", accessibilityLabel: "a unicorn"),
        "water": .init(assetCode: "1f4a7", accessibilityLabel: "water"),
    ]
}

public struct WordPictureHintAsset: Equatable, Sendable {
    public let imageData: Data
    public let accessibilityLabel: String
    public let attribution: String

    public init(
        imageData: Data,
        accessibilityLabel: String,
        attribution: String
    ) {
        self.imageData = imageData
        self.accessibilityLabel = accessibilityLabel
        self.attribution = attribution
    }
}

public protocol WordPictureHintProviding: Sendable {
    /// Returns a bundled child-safe hint when one is available.
    /// Ineligible/abstract words return nil.
    func hint(for rawWord: String) async -> WordPictureHintAsset?

    func prefetch(_ rawWords: [String]) async
}

extension WordPictureHintProviding {
    public func prefetch(_ rawWords: [String]) async {
        for word in rawWords {
            _ = await hint(for: word)
        }
    }
}

public struct NoWordPictureHintProvider: WordPictureHintProviding {
    public init() {}

    public func hint(for rawWord: String) async -> WordPictureHintAsset? {
        _ = rawWord
        return nil
    }

    public func prefetch(_ rawWords: [String]) async {
        _ = rawWords
    }
}
