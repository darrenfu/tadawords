import Foundation
import TadaWordsDomain

/// Converts OCR text fragments into normalized, unique English words while
/// preserving their first reading-order appearance.
public struct RecognizedEnglishWordParser: Sendable {
    public init() {}

    public func parse(_ fragments: [String]) -> [String] {
        parseResult(fragments).uniqueWords
    }

    /// Returns both the de-duplicated import candidates and the number of valid
    /// English word occurrences on the source image. The latter is used for a
    /// per-image safety limit and therefore intentionally counts duplicates.
    public func parseResult(_ fragments: [String]) -> RecognizedEnglishWordParseResult {
        var words: [String] = []
        var seen = Set<String>()
        var recognizedWordCount = 0

        for fragment in fragments {
            for token in Self.tokens(in: fragment) {
                guard let normalized = try? EnglishWordNormalizer.normalize(token) else {
                    continue
                }
                recognizedWordCount += 1
                guard seen.insert(normalized).inserted else { continue }
                words.append(normalized)
            }
        }
        return RecognizedEnglishWordParseResult(
            uniqueWords: words,
            recognizedWordCount: recognizedWordCount
        )
    }

    private static func tokens(in source: String) -> [String] {
        let range = NSRange(source.startIndex..., in: source)
        return wordExpression.matches(in: source, range: range).compactMap { match in
            guard let tokenRange = Range(match.range, in: source) else { return nil }
            return String(source[tokenRange])
        }
    }

    private static let wordExpression = try! NSRegularExpression(
        pattern: #"[A-Za-z]+(?:['’\-‐‑–—][A-Za-z]+)*"#
    )
}

public struct RecognizedEnglishWordParseResult: Equatable, Sendable {
    public let uniqueWords: [String]
    public let recognizedWordCount: Int

    public init(uniqueWords: [String], recognizedWordCount: Int) {
        self.uniqueWords = uniqueWords
        self.recognizedWordCount = max(0, recognizedWordCount)
    }
}
