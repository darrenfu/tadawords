import Foundation
import TadaWordsDomain
import XCTest

@testable import TadaWordsApplePlatform

final class AppleRecognitionDecisionPolicyTests: XCTestCase {
    func testConfidentExactNormalizedTranscriptMatches() throws {
        let target = try WordPrompt(learningMode: .read, text: "i'm")
        let result = makePolicy().evaluate(
            transcript: "  I’M  ",
            confidence: RecognitionConfidence(0.60),
            target: target
        )

        XCTAssertEqual(result.decision, .matched)
        XCTAssertEqual(result.recognizedText, "I’M")
        XCTAssertEqual(result.targetSpeakerAssessment, .unavailable)
    }

    func testHandwritingAcceptsLowerInitialCapitalAndAllCaps() throws {
        let target = try WordPrompt(learningMode: .write, text: "cat")
        let policy = makePolicy()

        for candidate in ["cat", "Cat", "CAT"] {
            XCTAssertEqual(
                policy.evaluate(
                    transcript: candidate,
                    confidence: RecognitionConfidence(0.95),
                    target: target
                ).decision,
                .matched,
                "Expected \(candidate) to match without case sensitivity"
            )
        }
    }

    func testDownloadedChildSpeechTranscriptMatchesDespiteApplePunctuation() throws {
        // OpenSLR SLR101 utterance 000010168 is a six-year-old Mandarin-native
        // child saying "BYE". SpeechAnalyzer transcribes the checked-in WAV as
        // "Bye." on the current macOS runtime.
        let target = try WordPrompt(learningMode: .read, text: "bye")
        let result = makeSpeechPolicy().evaluate(
            transcript: "Bye.",
            confidence: RecognitionConfidence(0.95),
            target: target
        )

        XCTAssertEqual(result.decision, .matched)
        XCTAssertEqual(result.recognizedText, "Bye.")
    }

    func testSpeechBoundaryCleanupNeverAcceptsPhraseOrInternalPunctuation() throws {
        let target = try WordPrompt(learningMode: .read, text: "bye")
        let policy = makeSpeechPolicy()

        XCTAssertEqual(
            policy.evaluate(
                transcript: "\u{201c}Bye!\u{201d}",
                confidence: RecognitionConfidence(0.95),
                target: target
            ).decision,
            .matched
        )
        XCTAssertEqual(
            policy.evaluate(
                transcript: "b,ye",
                confidence: RecognitionConfidence(0.95),
                target: target
            ).decision,
            .notMatched
        )
        XCTAssertEqual(
            policy.evaluate(
                transcript: "bye now.",
                confidence: RecognitionConfidence(0.95),
                target: target
            ).decision,
            .notMatched
        )
    }

    func testExactSpellingDoesNotStripSpeechPunctuation() throws {
        let target = try WordPrompt(learningMode: .write, text: "look")
        let result = makePolicy().evaluate(
            transcript: "look.",
            confidence: RecognitionConfidence(0.95),
            target: target
        )

        XCTAssertEqual(result.decision, .notMatched)
    }

    func testExactTranscriptBelowMatchThresholdIsUncertain() throws {
        let target = try WordPrompt(learningMode: .read, text: "look")
        let result = makePolicy().evaluate(
            transcript: "look",
            confidence: RecognitionConfidence(0.59),
            target: target
        )

        XCTAssertEqual(result.decision, .uncertain)
    }

    func testMismatchNeedsHigherConfidenceToBecomeIncorrect() throws {
        let target = try WordPrompt(learningMode: .read, text: "look")
        let policy = makePolicy()

        let uncertain = policy.evaluate(
            transcript: "book",
            confidence: RecognitionConfidence(0.79),
            target: target
        )
        let incorrect = policy.evaluate(
            transcript: "book",
            confidence: RecognitionConfidence(0.80),
            target: target
        )

        XCTAssertEqual(uncertain.decision, .uncertain)
        XCTAssertEqual(incorrect.decision, .notMatched)
    }

    func testConfidentMultiwordTranscriptCannotMatchSingleTarget() throws {
        let target = try WordPrompt(learningMode: .read, text: "look")
        let result = makePolicy().evaluate(
            transcript: "look here",
            confidence: RecognitionConfidence(0.95),
            target: target
        )

        XCTAssertEqual(result.decision, .notMatched)
    }

    func testSpeechPolicyAcceptsExplicitSightWordHomophones() throws {
        let policy = makeSpeechPolicy()
        let examples = [
            (target: "to", transcript: "two"),
            (target: "two", transcript: "too"),
            (target: "there", transcript: "their"),
            (target: "their", transcript: "they’re"),
            (target: "one", transcript: "won"),
            (target: "write", transcript: "right"),
        ]

        for example in examples {
            let target = try WordPrompt(
                learningMode: .read,
                text: example.target,
                audioCue: contextualCueIfNeeded(for: example.target)
            )
            let result = policy.evaluate(
                transcript: example.transcript,
                confidence: RecognitionConfidence(0.60),
                target: target
            )

            XCTAssertEqual(
                result.decision,
                .matched,
                "Expected \(example.transcript) to be pronunciation-equivalent to \(example.target)"
            )
        }
    }

    func testLowConfidenceHomophoneRemainsUncertain() throws {
        let target = try WordPrompt(learningMode: .read, text: "two")
        let result = makeSpeechPolicy().evaluate(
            transcript: "too",
            confidence: RecognitionConfidence(0.59),
            target: target
        )

        XCTAssertEqual(result.decision, .uncertain)
    }

    func testSpeechPolicyAcceptsCuratedComeRecognizerSpellings() throws {
        let target = try WordPrompt(learningMode: .read, text: "come")
        let policy = makeSpeechPolicy()

        for transcript in ["kum", "cum"] {
            let result = policy.evaluate(
                transcript: transcript,
                confidence: RecognitionConfidence(0.60),
                target: target
            )

            XCTAssertEqual(
                result.decision,
                .matched,
                "Expected curated ASR spelling \(transcript) to match come"
            )
        }
    }

    func testComeAliasIsDirectionalAndDoesNotFuzzyMatchNeighbors() throws {
        let policy = makeSpeechPolicy()
        let come = try WordPrompt(learningMode: .read, text: "come")

        for transcript in ["some", "home", "came"] {
            XCTAssertEqual(
                policy.evaluate(
                    transcript: transcript,
                    confidence: RecognitionConfidence(0.95),
                    target: come
                ).decision,
                .notMatched,
                "Unlisted neighbor \(transcript) must not match come"
            )
        }

        let aliasAsTarget = try WordPrompt(learningMode: .read, text: "kum")
        XCTAssertEqual(
            policy.evaluate(
                transcript: "come",
                confidence: RecognitionConfidence(0.95),
                target: aliasAsTarget
            ).decision,
            .notMatched
        )
    }

    func testPronunciationAliasesDoNotEnableGeneralNearWordMatching() throws {
        let policy = makeSpeechPolicy()
        let examples = [
            (target: "cat", transcript: "cap"),
            (target: "look", transcript: "book"),
            (target: "can", transcript: "cab"),
        ]

        for example in examples {
            let target = try WordPrompt(
                learningMode: .read,
                text: example.target
            )
            XCTAssertEqual(
                policy.evaluate(
                    transcript: example.transcript,
                    confidence: RecognitionConfidence(0.95),
                    target: target
                ).decision,
                .notMatched
            )
        }
    }

    func testLowConfidenceComeAliasStillFailsClosedAsUncertain() throws {
        let target = try WordPrompt(learningMode: .read, text: "come")
        let result = makeSpeechPolicy().evaluate(
            transcript: "kum",
            confidence: RecognitionConfidence(0.59),
            target: target
        )

        XCTAssertEqual(result.decision, .uncertain)
    }

    func testComeAliasCannotBypassSingleTokenBoundaryNormalization() throws {
        let target = try WordPrompt(learningMode: .read, text: "come")
        let policy = makeSpeechPolicy()

        XCTAssertEqual(
            policy.evaluate(
                transcript: "“kum!”",
                confidence: RecognitionConfidence(0.95),
                target: target
            ).decision,
            .matched
        )
        for transcript in ["kum now", "k.um", "kum-word"] {
            XCTAssertEqual(
                policy.evaluate(
                    transcript: transcript,
                    confidence: RecognitionConfidence(0.95),
                    target: target
                ).decision,
                .notMatched
            )
        }
    }

    func testSpeechPolicyDoesNotFuzzyAcceptSimilarNonHomophone() throws {
        let target = try WordPrompt(learningMode: .read, text: "look")
        let result = makeSpeechPolicy().evaluate(
            transcript: "book",
            confidence: RecognitionConfidence(0.95),
            target: target
        )

        XCTAssertEqual(result.decision, .notMatched)
    }

    func testExactSpellingPolicyDoesNotAcceptHomophone() throws {
        let target = try WordPrompt(learningMode: .read, text: "two")
        let result = makePolicy().evaluate(
            transcript: "too",
            confidence: RecognitionConfidence(0.95),
            target: target
        )

        XCTAssertEqual(result.decision, .notMatched)
    }

    func testSpeechPolicyDoesNotApplyPronunciationEquivalenceToWriting() throws {
        let target = try WordPrompt(
            learningMode: .write,
            text: "two",
            audioCue: .contextual("I can count to two.")
        )
        let result = makeSpeechPolicy().evaluate(
            transcript: "too",
            confidence: RecognitionConfidence(0.95),
            target: target
        )

        XCTAssertEqual(result.decision, .notMatched)
    }

    func testComeAliasDoesNotApplyToWritingOrExactSpellingPolicy() throws {
        let readTarget = try WordPrompt(learningMode: .read, text: "come")
        let writeTarget = try WordPrompt(learningMode: .write, text: "come")

        XCTAssertEqual(
            makePolicy().evaluate(
                transcript: "kum",
                confidence: RecognitionConfidence(0.95),
                target: readTarget
            ).decision,
            .notMatched
        )
        XCTAssertEqual(
            makeSpeechPolicy().evaluate(
                transcript: "kum",
                confidence: RecognitionConfidence(0.95),
                target: writeTarget
            ).decision,
            .notMatched
        )
    }

    func testMissingTranscriptOrConfidenceFailsClosedAsUncertain() throws {
        let target = try WordPrompt(learningMode: .read, text: "look")
        let policy = makePolicy()

        XCTAssertEqual(
            policy.evaluate(
                transcript: nil,
                confidence: RecognitionConfidence(1),
                target: target
            ).decision,
            .uncertain
        )
        XCTAssertEqual(
            policy.evaluate(
                transcript: "look",
                confidence: nil,
                target: target
            ).decision,
            .uncertain
        )
    }

    func testTechnicalFailureIsTypedAndNeverClaimsSpeakerMatch() {
        let result = makePolicy().technicalFailure(.permissionDenied)

        XCTAssertEqual(result.decision, .technicalFailure(.permissionDenied))
        XCTAssertEqual(result.targetSpeakerAssessment, .unavailable)
        XCTAssertNil(result.recognizedText)
        XCTAssertNil(result.confidence)
    }

    func testMismatchThresholdCannotBeLowerThanMatchThreshold() {
        let thresholds = AppleRecognitionThresholds(
            minimumMatchConfidence: RecognitionConfidence(0.75),
            minimumMismatchConfidence: RecognitionConfidence(0.20)
        )

        XCTAssertEqual(
            thresholds.minimumMismatchConfidence,
            RecognitionConfidence(0.75)
        )
    }

    private func makePolicy() -> AppleRecognitionDecisionPolicy {
        AppleRecognitionDecisionPolicy(
            thresholds: AppleRecognitionThresholds(
                minimumMatchConfidence: RecognitionConfidence(0.60),
                minimumMismatchConfidence: RecognitionConfidence(0.80)
            )
        )
    }

    private func makeSpeechPolicy() -> AppleRecognitionDecisionPolicy {
        AppleRecognitionDecisionPolicy(
            thresholds: AppleRecognitionThresholds(
                minimumMatchConfidence: RecognitionConfidence(0.60),
                minimumMismatchConfidence: RecognitionConfidence(0.80)
            ),
            matchPolicy: .sightWordPronunciation
        )
    }

    private func contextualCueIfNeeded(for word: String) -> WordAudioCue {
        word == "write" ? .contextual("Please write the word write.") : .isolated
    }
}
