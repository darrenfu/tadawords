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

    private func point(x: Double, y: Double) -> HandwritingPoint {
        HandwritingPoint(
            location: TadaWordsDomain.NormalizedPoint(x: x, y: y),
            elapsedSincePrompt: .zero
        )
    }
}
