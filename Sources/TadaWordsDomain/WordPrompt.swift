import Foundation

public struct WordPrompt: Codable, Hashable, Sendable {
    public let id: WordPromptID
    public let learningMode: LearningMode
    public let displayText: String
    public let normalizedText: String
    public let audioCue: WordAudioCue

    public init(
        id: WordPromptID = WordPromptID(),
        learningMode: LearningMode,
        text: String,
        audioCue: WordAudioCue = .isolated
    ) throws {
        let normalizedText = try EnglishWordNormalizer.normalize(text)
        try EnglishPromptSafetyPolicy.validate(
            normalizedWord: normalizedText,
            learningMode: learningMode,
            audioCue: audioCue
        )

        self.id = id
        self.learningMode = learningMode
        self.displayText = EnglishWordNormalizer.displayForm(text)
        self.normalizedText = normalizedText
        self.audioCue = audioCue
    }

    public var deduplicationKey: WordPromptDeduplicationKey {
        WordPromptDeduplicationKey(
            learningMode: learningMode,
            normalizedText: normalizedText
        )
    }

    private enum CodingKeys: String, CodingKey {
        case id
        case learningMode
        case displayText
        case normalizedText
        case audioCue
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let id = try container.decode(WordPromptID.self, forKey: .id)
        let learningMode = try container.decode(LearningMode.self, forKey: .learningMode)
        let displayText = try container.decode(String.self, forKey: .displayText)
        let persistedNormalizedText = try container.decode(
            String.self,
            forKey: .normalizedText
        )
        let audioCue = try container.decode(WordAudioCue.self, forKey: .audioCue)

        try self.init(
            id: id,
            learningMode: learningMode,
            text: displayText,
            audioCue: audioCue
        )

        guard normalizedText == persistedNormalizedText else {
            throw DecodingError.dataCorruptedError(
                forKey: .normalizedText,
                in: container,
                debugDescription: "Persisted word normalization does not match its display text."
            )
        }
    }
}

public struct WordPromptDeduplicationKey: Codable, Hashable, Sendable {
    public let learningMode: LearningMode
    public let normalizedText: String

    public init(learningMode: LearningMode, normalizedText: String) {
        self.learningMode = learningMode
        self.normalizedText = normalizedText
    }
}

public struct WordAudioCue: Codable, Hashable, Sendable {
    public let spokenContext: String?
    public let pronunciationKey: String?

    public init(spokenContext: String? = nil, pronunciationKey: String? = nil) {
        self.spokenContext = spokenContext?.trimmingCharacters(in: .whitespacesAndNewlines)
        self.pronunciationKey = pronunciationKey?.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    public static let isolated = WordAudioCue()

    public static func contextual(
        _ spokenContext: String,
        pronunciationKey: String? = nil
    ) -> WordAudioCue {
        WordAudioCue(
            spokenContext: spokenContext,
            pronunciationKey: pronunciationKey
        )
    }
}

public enum WordPromptValidationError: Error, Equatable, Sendable {
    case emptyText
    case tooLong(maximumCharacterCount: Int)
    case multipleWordsNotSupported
    case unsupportedCharacters
    case contextRequired(word: String, reason: PromptAmbiguityReason)
    case contextMustContainTarget(word: String)
    case contextTooLong(maximumCharacterCount: Int)
}

public enum PromptAmbiguityReason: String, Codable, Equatable, Sendable {
    case homophone
    case heteronym
}

public enum EnglishWordNormalizer {
    public static let maximumCharacterCount = 32

    public static func normalize(_ source: String) throws -> String {
        let punctuationNormalized = normalizePunctuation(source)

        let normalized =
            punctuationNormalized
            .folding(options: [.widthInsensitive], locale: Locale(identifier: "en_US_POSIX"))
            .precomposedStringWithCanonicalMapping
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased(with: Locale(identifier: "en_US_POSIX"))

        guard !normalized.isEmpty else {
            throw WordPromptValidationError.emptyText
        }
        guard normalized.count <= maximumCharacterCount else {
            throw WordPromptValidationError.tooLong(
                maximumCharacterCount: maximumCharacterCount
            )
        }
        guard !normalized.contains(where: { $0.isWhitespace }) else {
            throw WordPromptValidationError.multipleWordsNotSupported
        }

        let pattern = #"^[a-z]+(?:['-][a-z]+)*$"#
        guard normalized.range(of: pattern, options: .regularExpression) != nil else {
            throw WordPromptValidationError.unsupportedCharacters
        }

        return normalized
    }

    public static func displayForm(_ source: String) -> String {
        normalizePunctuation(source)
            .folding(
                options: [.widthInsensitive],
                locale: Locale(identifier: "en_US_POSIX")
            )
            .precomposedStringWithCanonicalMapping
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func normalizePunctuation(_ source: String) -> String {
        source
            .replacingOccurrences(of: "\u{2018}", with: "'")
            .replacingOccurrences(of: "\u{2019}", with: "'")
            .replacingOccurrences(of: "\u{2010}", with: "-")
            .replacingOccurrences(of: "\u{2011}", with: "-")
            .replacingOccurrences(of: "\u{2013}", with: "-")
            .replacingOccurrences(of: "\u{2014}", with: "-")
    }
}

public enum EnglishPromptSafetyPolicy {
    public static let maximumContextCharacterCount = 120

    private static let audioAmbiguousWords: Set<String> = [
        "be", "bee", "blew", "blue", "brake", "break", "buy", "by", "bye",
        "flower", "flour", "for", "four", "hear", "here", "hole", "hour",
        "know", "knew", "meat", "meet", "new", "no", "one", "our", "pair",
        "peace", "pear", "piece", "plain", "plane", "right", "role", "roll",
        "sea", "see", "son", "sun", "tail", "tale", "their", "there",
        "they're", "to", "too", "two", "wait", "weak", "weather", "week",
        "weight", "whether", "which", "witch", "won", "whole", "write",
    ]

    private static let heteronyms: Set<String> = [
        "bass", "bow", "close", "content", "contract", "conduct", "desert",
        "digest", "does", "entrance", "invalid", "lead", "live", "minute",
        "object", "permit", "present", "produce", "project", "read", "record",
        "refuse", "row", "subject", "tear", "wind",
    ]

    public static func validate(
        normalizedWord: String,
        learningMode: LearningMode,
        audioCue: WordAudioCue
    ) throws {
        guard
            ambiguityReason(
                for: normalizedWord,
                learningMode: learningMode
            ) != nil
        else { return }

        // Canonical teacher pronunciation is the default. Context is optional
        // metadata a parent can add when they want a specific reading; it must
        // never prevent an otherwise valid school word from entering a pool.
        guard let context = audioCue.spokenContext, !context.isEmpty else {
            return
        }
        guard context.count <= maximumContextCharacterCount else {
            throw WordPromptValidationError.contextTooLong(
                maximumCharacterCount: maximumContextCharacterCount
            )
        }
        guard contextContainsTarget(context, normalizedTarget: normalizedWord) else {
            throw WordPromptValidationError.contextMustContainTarget(word: normalizedWord)
        }
    }

    public static func ambiguityReason(
        for normalizedWord: String,
        learningMode: LearningMode
    ) -> PromptAmbiguityReason? {
        if heteronyms.contains(normalizedWord) {
            return .heteronym
        } else if learningMode == .write, audioAmbiguousWords.contains(normalizedWord) {
            return .homophone
        } else {
            return nil
        }
    }

    private static func contextContainsTarget(
        _ context: String,
        normalizedTarget: String
    ) -> Bool {
        let lowercaseContext = context.lowercased(
            with: Locale(identifier: "en_US_POSIX")
        )
        let escapedTarget = NSRegularExpression.escapedPattern(
            for: normalizedTarget
        )
        let pattern = "(?<![a-z])\(escapedTarget)(?![a-z])"
        return lowercaseContext.range(
            of: pattern,
            options: .regularExpression
        ) != nil
    }
}
