import Foundation
import TadaWordsDomain

/// Converts OCR text fragments into normalized, unique English words while
/// preserving their first reading-order appearance.
public struct RecognizedEnglishWordParser: Sendable {
    public init() {}

    public func parse(_ fragments: [String]) -> [String] {
        var words: [String] = []
        var seen = Set<String>()

        for fragment in fragments {
            for token in Self.tokens(in: fragment) {
                guard let normalized = try? EnglishWordNormalizer.normalize(token),
                    seen.insert(normalized).inserted
                else {
                    continue
                }
                words.append(normalized)
            }
        }
        return words
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
