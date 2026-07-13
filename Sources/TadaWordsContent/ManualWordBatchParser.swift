import Foundation
import TadaWordsDomain

public struct ParsedManualWord: Hashable, Sendable {
    public let originalToken: String
    public let inputPosition: Int
    public let prompt: WordPrompt

    public init(
        originalToken: String,
        inputPosition: Int,
        prompt: WordPrompt
    ) {
        self.originalToken = originalToken
        self.inputPosition = max(0, inputPosition)
        self.prompt = prompt
    }
}

public enum ManualWordRejectionReason: Equatable, Sendable {
    case emptyBatch
    case duplicateInBatch(normalizedText: String)
    case invalidPrompt(WordPromptValidationError)
    case unexpectedValidationFailure
}

public struct ManualWordRejection: Equatable, Sendable {
    public let originalToken: String
    public let inputPosition: Int?
    public let reason: ManualWordRejectionReason

    public init(
        originalToken: String,
        inputPosition: Int?,
        reason: ManualWordRejectionReason
    ) {
        self.originalToken = originalToken
        self.inputPosition = inputPosition
        self.reason = reason
    }
}

public struct ManualWordBatchParseResult: Equatable, Sendable {
    public let accepted: [ParsedManualWord]
    public let rejected: [ManualWordRejection]

    public init(
        accepted: [ParsedManualWord],
        rejected: [ManualWordRejection]
    ) {
        self.accepted = accepted
        self.rejected = rejected
    }
}

/// Converts comma-, newline-, or whitespace-separated guardian input into
/// validated domain prompts. No alternate normalization path is maintained.
public struct ManualWordBatchParser: Sendable {
    private static let separators = CharacterSet.whitespacesAndNewlines.union(
        CharacterSet(charactersIn: ",，")
    )

    public init() {}

    public func parse(
        _ input: String,
        learningMode: LearningMode,
        audioCuesByNormalizedWord: [String: WordAudioCue] = [:]
    ) -> ManualWordBatchParseResult {
        let tokens =
            input
            .components(separatedBy: Self.separators)
            .filter { !$0.isEmpty }

        guard !tokens.isEmpty else {
            return ManualWordBatchParseResult(
                accepted: [],
                rejected: [
                    ManualWordRejection(
                        originalToken: input,
                        inputPosition: nil,
                        reason: .emptyBatch
                    )
                ]
            )
        }

        var accepted: [ParsedManualWord] = []
        var rejected: [ManualWordRejection] = []
        var seenNormalizedWords = Set<String>()

        for (position, token) in tokens.enumerated() {
            do {
                let normalizedWord = try EnglishWordNormalizer.normalize(token)
                let audioCue = audioCuesByNormalizedWord[normalizedWord] ?? .isolated
                let prompt = try WordPrompt(
                    learningMode: learningMode,
                    text: token,
                    audioCue: audioCue
                )

                guard seenNormalizedWords.insert(prompt.normalizedText).inserted else {
                    rejected.append(
                        ManualWordRejection(
                            originalToken: token,
                            inputPosition: position,
                            reason: .duplicateInBatch(
                                normalizedText: prompt.normalizedText
                            )
                        )
                    )
                    continue
                }

                accepted.append(
                    ParsedManualWord(
                        originalToken: token,
                        inputPosition: position,
                        prompt: prompt
                    )
                )
            } catch let error as WordPromptValidationError {
                rejected.append(
                    ManualWordRejection(
                        originalToken: token,
                        inputPosition: position,
                        reason: .invalidPrompt(error)
                    )
                )
            } catch {
                rejected.append(
                    ManualWordRejection(
                        originalToken: token,
                        inputPosition: position,
                        reason: .unexpectedValidationFailure
                    )
                )
            }
        }

        return ManualWordBatchParseResult(
            accepted: accepted,
            rejected: rejected
        )
    }
}
