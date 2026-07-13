import Foundation
import TadaWordsDomain

public struct AppleRecognitionThresholds: Equatable, Sendable {
    public let minimumMatchConfidence: RecognitionConfidence
    public let minimumMismatchConfidence: RecognitionConfidence

    public init(
        minimumMatchConfidence: RecognitionConfidence,
        minimumMismatchConfidence: RecognitionConfidence
    ) {
        self.minimumMatchConfidence = minimumMatchConfidence
        self.minimumMismatchConfidence = max(
            minimumMatchConfidence,
            minimumMismatchConfidence
        )
    }

    public static let speech = AppleRecognitionThresholds(
        minimumMatchConfidence: RecognitionConfidence(0.60),
        minimumMismatchConfidence: RecognitionConfidence(0.80)
    )

    public static let handwriting = AppleRecognitionThresholds(
        minimumMatchConfidence: RecognitionConfidence(0.55),
        minimumMismatchConfidence: RecognitionConfidence(0.80)
    )
}

/// Converts an Apple recognizer's candidate into product-level evidence.
///
/// A low-confidence candidate is always uncertain. A mismatch only becomes an
/// incorrect answer when the recognizer is more confident than it needs to be
/// for a match. This intentionally favors a technical retry over teaching a
/// child from a machine's weak guess.
public struct AppleRecognitionDecisionPolicy: Sendable {
    public let thresholds: AppleRecognitionThresholds
    let matchPolicy: AppleRecognitionMatchPolicy

    public init(thresholds: AppleRecognitionThresholds) {
        self.thresholds = thresholds
        self.matchPolicy = .exactSpelling
    }

    init(
        thresholds: AppleRecognitionThresholds,
        matchPolicy: AppleRecognitionMatchPolicy
    ) {
        self.thresholds = thresholds
        self.matchPolicy = matchPolicy
    }

    public func evaluate(
        transcript: String?,
        confidence: RecognitionConfidence?,
        target: WordPrompt
    ) -> RecognitionResult {
        let recognizedText = transcript?.trimmingCharacters(
            in: .whitespacesAndNewlines
        )

        guard let recognizedText, !recognizedText.isEmpty else {
            return uncertainResult(recognizedText: nil, confidence: confidence)
        }
        guard let confidence else {
            return uncertainResult(
                recognizedText: recognizedText,
                confidence: nil
            )
        }

        let normalizedCandidate = matchPolicy.normalizedCandidate(from: recognizedText)
        if matchPolicy.matches(
            candidate: normalizedCandidate,
            target: target
        ) {
            let decision: RecognitionDecision =
                confidence >= thresholds.minimumMatchConfidence
                ? .matched
                : .uncertain
            return result(
                decision: decision,
                recognizedText: recognizedText,
                confidence: confidence
            )
        }

        let decision: RecognitionDecision =
            confidence >= thresholds.minimumMismatchConfidence
            ? .notMatched
            : .uncertain
        return result(
            decision: decision,
            recognizedText: recognizedText,
            confidence: confidence
        )
    }

    public func technicalFailure(_ reason: TechnicalFailureReason) -> RecognitionResult {
        result(
            decision: .technicalFailure(reason),
            recognizedText: nil,
            confidence: nil
        )
    }

    private func uncertainResult(
        recognizedText: String?,
        confidence: RecognitionConfidence?
    ) -> RecognitionResult {
        result(
            decision: .uncertain,
            recognizedText: recognizedText,
            confidence: confidence
        )
    }

    private func result(
        decision: RecognitionDecision,
        recognizedText: String?,
        confidence: RecognitionConfidence?
    ) -> RecognitionResult {
        RecognitionResult(
            decision: decision,
            recognizedText: recognizedText,
            confidence: confidence,
            // Speaker verification is a separate biometric capability. Apple's
            // speech recognizer does not provide it, so this adapter never guesses.
            targetSpeakerAssessment: .unavailable
        )
    }
}

/// The spelling policy is explicit so handwriting can never inherit speech's
/// pronunciation-only exceptions.
enum AppleRecognitionMatchPolicy: Equatable, Sendable {
    case exactSpelling
    case sightWordPronunciation

    func normalizedCandidate(from recognizedText: String) -> String? {
        switch self {
        case .exactSpelling:
            return try? EnglishWordNormalizer.normalize(recognizedText)
        case .sightWordPronunciation:
            return SpeechTranscriptNormalizer.normalize(recognizedText)
        }
    }

    func matches(candidate: String?, target: WordPrompt) -> Bool {
        guard let candidate else { return false }
        guard candidate != target.normalizedText else { return true }
        guard self == .sightWordPronunciation, target.learningMode == .read else {
            return false
        }
        return SightWordPronunciationEquivalencePolicy.areEquivalent(
            candidate,
            target.normalizedText
        )
    }
}

/// Removes only punctuation that speech transcription may add around a single
/// recognized word. Internal punctuation and multiword transcripts still fail
/// the domain normalizer, so this cannot turn a phrase or fuzzy match into a
/// correct sight-word answer.
private enum SpeechTranscriptNormalizer {
    static func normalize(_ transcript: String) -> String? {
        let boundaryCharacters = CharacterSet.whitespacesAndNewlines.union(
            .punctuationCharacters
        )
        let unwrapped = transcript.trimmingCharacters(in: boundaryCharacters)
        return try? EnglishWordNormalizer.normalize(unwrapped)
    }
}

/// A deliberately small allowlist of stable American-English homophones that
/// occur in early sight-word lists. This is not spelling-distance matching:
/// words outside these exact groups remain mismatches.
enum SightWordPronunciationEquivalencePolicy {
    private static let groups: [Set<String>] = [
        ["be", "bee"],
        ["blew", "blue"],
        ["brake", "break"],
        ["buy", "by", "bye"],
        ["flour", "flower"],
        ["for", "four"],
        ["hear", "here"],
        ["hole", "whole"],
        ["knew", "new"],
        ["know", "no"],
        ["meat", "meet"],
        ["one", "won"],
        ["pair", "pear"],
        ["peace", "piece"],
        ["plain", "plane"],
        ["right", "write"],
        ["role", "roll"],
        ["sea", "see"],
        ["son", "sun"],
        ["tail", "tale"],
        ["their", "there", "they're"],
        ["to", "too", "two"],
        ["wait", "weight"],
        ["weak", "week"],
        ["weather", "whether"],
        ["which", "witch"],
    ]

    static func areEquivalent(_ lhs: String, _ rhs: String) -> Bool {
        guard lhs != rhs else { return true }
        return groups.contains { group in
            group.contains(lhs) && group.contains(rhs)
        }
    }
}
