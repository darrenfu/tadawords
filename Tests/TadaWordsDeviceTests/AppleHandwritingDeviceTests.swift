import TadaWordsApplePlatform
import TadaWordsDomain
import XCTest

/// Physical-device coverage for the production Vision handwriting adapter.
///
/// These fixtures are synthetic vectors authored for this test target. They do
/// not contain or derive from a child's handwriting, image, profile, or audio.
final class AppleHandwritingDeviceTests: XCTestCase {
    private let recognitionService = AppleHandwritingRecognitionService()

    func testProductionServiceRecognizesOfAndGoAcrossSupportedCaseForms() async throws {
        #if targetEnvironment(simulator)
            throw XCTSkip("Run TadaWordsDeviceTests on a physical iPhone or iPad.")
        #endif

        for word in ["of", "go"] {
            let prompt = try WordPrompt(learningMode: .write, text: word)
            for caseForm in SyntheticHandwritingFixture.CaseForm.allCases {
                let result = try await recognitionService.recognize(
                    sample: SyntheticHandwritingFixture.sample(
                        word: word,
                        caseForm: caseForm
                    ),
                    prompt: prompt,
                    for: ProfileID()
                )

                XCTAssertEqual(
                    result.decision,
                    .matched,
                    "Expected production Vision to match \(word)/\(caseForm); "
                        + "received \(result.decision), transcript "
                        + "\(result.recognizedText ?? "nil"), confidence "
                        + "\(result.confidence?.value.description ?? "nil")"
                )
            }
        }
    }

    func testProductionServiceDoesNotAcceptWrongWordSamples() async throws {
        #if targetEnvironment(simulator)
            throw XCTSkip("Run TadaWordsDeviceTests on a physical iPhone or iPad.")
        #endif

        let controls = [
            (
                sampleWord: "of",
                targetWord: "go",
                sample: SyntheticHandwritingFixture.sample(
                    word: "of",
                    caseForm: .allCaps
                )
            ),
            (
                sampleWord: "go",
                targetWord: "of",
                sample: SyntheticHandwritingFixture.sample(
                    word: "go",
                    caseForm: .allCaps
                )
            ),
            (
                sampleWord: "xx",
                targetWord: "of",
                sample: SyntheticHandwritingFixture.unrelatedXXSample()
            ),
            (
                sampleWord: "90",
                targetWord: "go",
                sample: SyntheticHandwritingFixture.numericNinetySample()
            ),
        ]

        for control in controls {
            let prompt = try WordPrompt(
                learningMode: .write,
                text: control.targetWord
            )
            let result = try await recognitionService.recognize(
                sample: control.sample,
                prompt: prompt,
                for: ProfileID()
            )

            XCTAssertNotEqual(
                result.decision,
                .matched,
                "Wrong sample \(control.sampleWord) must not match target "
                    + "\(control.targetWord); transcript "
                    + "\(result.recognizedText ?? "nil")"
            )
        }
    }
}

private enum SyntheticHandwritingFixture {
    enum CaseForm: String, CaseIterable, CustomStringConvertible {
        case lowercase
        case initialCapital
        case allCaps

        var description: String { rawValue }
    }

    static func sample(word: String, caseForm: CaseForm) -> HandwritingSample {
        let strokes: [[HandwritingPoint]]
        switch (word, caseForm) {
        case ("of", .lowercase):
            strokes = lowercaseO(centerX: 0.27) + lowercaseF(centerX: 0.68)
        case ("of", .initialCapital):
            strokes = capitalO(centerX: 0.27) + lowercaseF(centerX: 0.68)
        case ("of", .allCaps):
            strokes = capitalO(centerX: 0.27) + capitalF(centerX: 0.68)
        case ("go", .lowercase):
            strokes = lowercaseG(centerX: 0.27) + lowercaseO(centerX: 0.72)
        case ("go", .initialCapital):
            strokes = capitalG(centerX: 0.27) + lowercaseO(centerX: 0.72)
        case ("go", .allCaps):
            strokes = capitalG(centerX: 0.27) + capitalO(centerX: 0.72)
        default:
            preconditionFailure("Unsupported synthetic word fixture: \(word)")
        }
        return sample(strokes: strokes)
    }

    static func unrelatedXXSample() -> HandwritingSample {
        sample(
            strokes: capitalX(centerX: 0.27) + capitalX(centerX: 0.72)
        )
    }

    static func numericNinetySample() -> HandwritingSample {
        var nine = ellipse(
            centerX: 0.27,
            centerY: 0.34,
            radiusX: 0.13,
            radiusY: 0.18
        )
        nine.append(
            contentsOf: points([
                (0.40, 0.36),
                (0.40, 0.52),
                (0.40, 0.68),
                (0.40, 0.80),
            ])
        )
        return sample(
            strokes: [
                nine,
                ellipse(
                    centerX: 0.72,
                    centerY: 0.48,
                    radiusX: 0.15,
                    radiusY: 0.31
                ),
            ]
        )
    }

    private static func sample(
        strokes: [[HandwritingPoint]]
    ) -> HandwritingSample {
        HandwritingSample(
            strokes: strokes.map(HandwritingStroke.init(points:)),
            inputMethod: .finger
        )
    }

    private static func lowercaseO(centerX: Double) -> [[HandwritingPoint]] {
        [ellipse(centerX: centerX, centerY: 0.48, radiusX: 0.14, radiusY: 0.20)]
    }

    private static func capitalO(centerX: Double) -> [[HandwritingPoint]] {
        [ellipse(centerX: centerX, centerY: 0.48, radiusX: 0.16, radiusY: 0.32)]
    }

    private static func lowercaseF(centerX: Double) -> [[HandwritingPoint]] {
        [
            points([
                (centerX + 0.10, 0.18),
                (centerX + 0.06, 0.13),
                (centerX, 0.12),
                (centerX - 0.05, 0.16),
                (centerX - 0.07, 0.24),
                (centerX - 0.07, 0.38),
                (centerX - 0.07, 0.55),
                (centerX - 0.07, 0.76),
            ]),
            points([
                (centerX - 0.15, 0.36),
                (centerX - 0.08, 0.35),
                (centerX, 0.35),
                (centerX + 0.09, 0.36),
            ]),
        ]
    }

    private static func capitalF(centerX: Double) -> [[HandwritingPoint]] {
        [
            points([(centerX - 0.09, 0.16), (centerX - 0.09, 0.80)]),
            points([(centerX - 0.09, 0.16), (centerX + 0.15, 0.16)]),
            points([(centerX - 0.09, 0.45), (centerX + 0.10, 0.45)]),
        ]
    }

    private static func lowercaseG(centerX: Double) -> [[HandwritingPoint]] {
        [
            ellipse(
                centerX: centerX,
                centerY: 0.40,
                radiusX: 0.14,
                radiusY: 0.18
            ),
            points([
                (centerX + 0.14, 0.38),
                (centerX + 0.14, 0.53),
                (centerX + 0.14, 0.68),
                (centerX + 0.10, 0.78),
                (centerX + 0.02, 0.83),
                (centerX - 0.07, 0.82),
                (centerX - 0.12, 0.77),
            ]),
        ]
    }

    private static func capitalG(centerX: Double) -> [[HandwritingPoint]] {
        let arc = stride(
            from: 0.65,
            through: (Double.pi * 2) - 0.65,
            by: 0.12
        ).map { angle in
            point(
                x: centerX + (cos(angle) * 0.17),
                y: 0.48 + (sin(angle) * 0.32)
            )
        }
        return [
            arc,
            points([
                (centerX + 0.02, 0.49),
                (centerX + 0.17, 0.49),
                (centerX + 0.17, 0.63),
            ]),
        ]
    }

    private static func capitalX(centerX: Double) -> [[HandwritingPoint]] {
        [
            points([(centerX - 0.14, 0.18), (centerX + 0.14, 0.79)]),
            points([(centerX + 0.14, 0.18), (centerX - 0.14, 0.79)]),
        ]
    }

    private static func ellipse(
        centerX: Double,
        centerY: Double,
        radiusX: Double,
        radiusY: Double
    ) -> [HandwritingPoint] {
        stride(
            from: 0.0,
            through: Double.pi * 2,
            by: Double.pi / 24
        ).map { angle in
            point(
                x: centerX + (cos(angle) * radiusX),
                y: centerY + (sin(angle) * radiusY)
            )
        }
    }

    private static func points(
        _ coordinates: [(Double, Double)]
    ) -> [HandwritingPoint] {
        coordinates.map { point(x: $0.0, y: $0.1) }
    }

    private static func point(x: Double, y: Double) -> HandwritingPoint {
        HandwritingPoint(
            location: NormalizedPoint(x: x, y: y),
            elapsedSincePrompt: .zero
        )
    }
}
