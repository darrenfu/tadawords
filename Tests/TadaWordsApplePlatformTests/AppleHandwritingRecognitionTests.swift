import Foundation
import TadaWordsDomain
import XCTest

@testable import TadaWordsApplePlatform

final class AppleHandwritingRecognitionTests: XCTestCase {
    func testResolverOrdersFragmentsLeftToRightAndIgnoresOCRWhitespace() {
        let fragments = [
            fragment("ok", confidence: 0.81, x: 0.55),
            fragment("l ", confidence: 0.92, x: 0.10),
            fragment("o", confidence: 0.87, x: 0.32),
        ]

        let transcript = AppleHandwritingTranscriptResolver.resolve(fragments)

        XCTAssertEqual(transcript?.letterSequence, "look")
        XCTAssertEqual(transcript?.confidence, RecognitionConfidence(0.81))
    }

    func testResolverReturnsNilWithoutReadableFragments() {
        let transcript = AppleHandwritingTranscriptResolver.resolve([
            fragment("  \n", confidence: 1, x: 0.1)
        ])

        XCTAssertNil(transcript)
    }

    func testRendererRejectsEmptySample() {
        let renderer = HandwritingSampleRenderer(configuration: .default)
        let sample = HandwritingSample(strokes: [], inputMethod: .finger)

        XCTAssertThrowsError(try renderer.render(sample)) { error in
            XCTAssertTrue(error is HandwritingRenderingError)
        }
    }

    func testRendererProducesConfiguredImageFromNormalizedStrokes() throws {
        let configuration = AppleHandwritingRecognitionConfiguration(
            canvasWidth: 600,
            canvasHeight: 300
        )
        let renderer = HandwritingSampleRenderer(configuration: configuration)
        let sample = HandwritingSample(
            strokes: [
                HandwritingStroke(points: [
                    point(x: 0.1, y: 0.2),
                    point(x: 0.2, y: 0.8),
                    point(x: 0.3, y: 0.2),
                ])
            ],
            inputMethod: .pencil
        )

        let image = try renderer.render(sample)

        XCTAssertEqual(image.width, 600)
        XCTAssertEqual(image.height, 300)
    }

    func testServiceReturnsTypedFailureForEmptySample() async throws {
        let service = AppleHandwritingRecognitionService()
        let prompt = try WordPrompt(learningMode: .write, text: "look")

        let result = try await service.recognize(
            sample: HandwritingSample(strokes: [], inputMethod: .finger),
            prompt: prompt,
            for: ProfileID()
        )

        XCTAssertEqual(result.decision, .technicalFailure(.corruptedInput))
        XCTAssertEqual(result.targetSpeakerAssessment, .unavailable)
    }

    func testWritePipelineAcceptsOfAcrossCaseAndFragmentShapes() throws {
        let prompt = try WordPrompt(learningMode: .write, text: "of")
        let resolver = makeResultResolver()
        let cases = [
            [fragment("of", confidence: 0.92, x: 0.1)],
            [fragment("Of", confidence: 0.92, x: 0.1)],
            [fragment("OF", confidence: 0.92, x: 0.1)],
            [
                fragment("O", confidence: 0.91, x: 0.1),
                fragment("F", confidence: 0.88, x: 0.6),
            ],
            [fragment("o f", confidence: 0.86, x: 0.1)],
        ]

        for fragments in cases {
            XCTAssertEqual(
                resolver.resolve(fragments: fragments, target: prompt).decision,
                .matched
            )
        }
    }

    func testWritePipelineUsesExactTargetFromVisionAlternatives() throws {
        let prompt = try WordPrompt(learningMode: .write, text: "of")
        let fragments = [
            fragment(
                candidates: [
                    ("ot", 0.96),
                    ("OF", 0.72),
                    ("or", 0.66),
                ],
                x: 0.1
            )
        ]

        let result = makeResultResolver().resolve(
            fragments: fragments,
            target: prompt
        )

        XCTAssertEqual(result.decision, .matched)
        XCTAssertEqual(result.recognizedText, "of")
        XCTAssertEqual(result.confidence, RecognitionConfidence(0.72))
    }

    func testWritePipelineAcceptsZeroOnlyAsTargetAlignedLetterO() throws {
        let ofPrompt = try WordPrompt(learningMode: .write, text: "of")
        let dogPrompt = try WordPrompt(learningMode: .write, text: "dog")
        let resolver = makeResultResolver()

        XCTAssertEqual(
            resolver.resolve(
                fragments: [fragment("0f", confidence: 0.84, x: 0.1)],
                target: ofPrompt
            ).decision,
            .matched
        )
        XCTAssertEqual(
            resolver.resolve(
                fragments: [fragment("d0g", confidence: 0.81, x: 0.1)],
                target: dogPrompt
            ).decision,
            .matched
        )
    }

    func testWritePipelineRejectsUnrelatedOfNeighborsAndSymbols() throws {
        let prompt = try WordPrompt(learningMode: .write, text: "of")
        let resolver = makeResultResolver()

        for unrelated in ["if", "on", "or", "ot", "off", "o+", "+0"] {
            XCTAssertEqual(
                resolver.resolve(
                    fragments: [fragment(unrelated, confidence: 0.98, x: 0.1)],
                    target: prompt
                ).decision,
                .notMatched,
                "Unexpected match for unrelated OCR candidate \(unrelated)"
            )
        }
    }

    func testWritePipelineKeepsLowConfidenceExactAlternativeUncertain() throws {
        let prompt = try WordPrompt(learningMode: .write, text: "of")
        let fragments = [
            fragment(candidates: [("ot", 0.98), ("of", 0.54)], x: 0.1)
        ]

        XCTAssertEqual(
            makeResultResolver().resolve(
                fragments: fragments,
                target: prompt
            ).decision,
            .uncertain
        )
    }

    func testRecognitionVocabularyIncludesAllSupportedCaseForms() throws {
        let prompt = try WordPrompt(learningMode: .write, text: "of")

        XCTAssertEqual(
            AppleHandwritingRecognitionVocabulary.words(for: prompt),
            ["of", "Of", "OF"]
        )
    }

    private func fragment(
        _ text: String,
        confidence: Double,
        x: CGFloat
    ) -> AppleRecognizedTextFragment {
        AppleRecognizedTextFragment(
            text: text,
            confidence: RecognitionConfidence(confidence),
            minimumX: x,
            verticalCenter: 0.5
        )
    }

    private func fragment(
        candidates: [(String, Double)],
        x: CGFloat
    ) -> AppleRecognizedTextFragment {
        AppleRecognizedTextFragment(
            candidates: candidates.map {
                AppleRecognizedTextCandidate(
                    text: $0.0,
                    confidence: RecognitionConfidence($0.1)
                )
            },
            minimumX: x,
            verticalCenter: 0.5
        )
    }

    private func makeResultResolver() -> AppleHandwritingRecognitionResultResolver {
        AppleHandwritingRecognitionResultResolver(thresholds: .handwriting)
    }

    private func point(x: Double, y: Double) -> HandwritingPoint {
        HandwritingPoint(
            location: TadaWordsDomain.NormalizedPoint(x: x, y: y),
            elapsedSincePrompt: .zero
        )
    }
}
