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
            let caseForms =
                word == "of"
                ? SyntheticHandwritingFixture.CaseForm.allCases
                : [.lowercase, .initialCapital, .allCaps]
            for caseForm in caseForms {
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

    func testProductionServiceRecognizesAdversarialOfSamples() async throws {
        #if targetEnvironment(simulator)
            throw XCTSkip("Run TadaWordsDeviceTests on a physical iPhone or iPad.")
        #endif

        let prompt = try WordPrompt(learningMode: .write, text: "of")
        let samples = [
            ("numeric zero + f", SyntheticHandwritingFixture.numericZeroFOfSample()),
            ("open o", SyntheticHandwritingFixture.openOfSample()),
            ("double-loop o", SyntheticHandwritingFixture.doubleLoopOfSample()),
            ("tight connected", SyntheticHandwritingFixture.tightConnectedOfSample()),
            ("jittered overtrace", SyntheticHandwritingFixture.jitteredOfSample()),
        ]

        for (label, sample) in samples {
            let result = try await recognitionService.recognize(
                sample: sample,
                prompt: prompt,
                for: ProfileID()
            )

            XCTAssertEqual(
                result.decision,
                .matched,
                "Expected production Vision to match adversarial of (\(label)); "
                    + "received \(result.decision), transcript "
                    + "\(result.recognizedText ?? "nil"), confidence "
                    + "\(result.confidence?.value.description ?? "nil")"
            )
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
            (
                sampleWord: "90",
                targetWord: "of",
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

    func testProductionServiceRejectsCompressedOfNeighbors() async throws {
        #if targetEnvironment(simulator)
            throw XCTSkip("Run TadaWordsDeviceTests on a physical iPhone or iPad.")
        #endif

        let prompt = try WordPrompt(learningMode: .write, text: "of")
        let samples = [
            ("numeric zero + t", SyntheticHandwritingFixture.numericZeroTOfSample()),
            ("numeric zero + ff", SyntheticHandwritingFixture.numericZeroFFOfSample()),
            ("open-o off", SyntheticHandwritingFixture.openOffSample()),
            ("double-loop-o off", SyntheticHandwritingFixture.doubleLoopOffSample()),
            ("tight on", SyntheticHandwritingFixture.tightOnSample()),
            ("tight ot", SyntheticHandwritingFixture.tightOtSample()),
        ]

        for (label, sample) in samples {
            let result = try await recognitionService.recognize(
                sample: sample,
                prompt: prompt,
                for: ProfileID()
            )

            XCTAssertNotEqual(
                result.decision,
                .matched,
                "Wrong sample \(label) must not match of; transcript "
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
        case finalCapital

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
        case ("of", .finalCapital):
            strokes = lowercaseO(centerX: 0.27) + capitalF(centerX: 0.68)
        case ("go", .lowercase):
            strokes = lowercaseG(centerX: 0.27) + lowercaseO(centerX: 0.72)
        case ("go", .initialCapital):
            strokes = capitalG(centerX: 0.27) + lowercaseO(centerX: 0.72)
        case ("go", .allCaps):
            strokes = capitalG(centerX: 0.27) + capitalO(centerX: 0.72)
        case ("go", .finalCapital):
            strokes = lowercaseG(centerX: 0.27) + capitalO(centerX: 0.72)
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

    static func openOfSample() -> HandwritingSample {
        sample(strokes: openO(centerX: 0.27) + lowercaseF(centerX: 0.68))
    }

    static func numericZeroFOfSample() -> HandwritingSample {
        sample(
            strokes: numericZero(centerX: 0.27)
                + lowercaseF(centerX: 0.68)
        )
    }

    static func numericZeroTOfSample() -> HandwritingSample {
        sample(
            strokes: numericZero(centerX: 0.27)
                + lowercaseT(centerX: 0.68)
        )
    }

    static func numericZeroFFOfSample() -> HandwritingSample {
        sample(
            strokes: numericZero(centerX: 0.18)
                + lowercaseF(centerX: 0.50)
                + lowercaseF(centerX: 0.79)
        )
    }

    static func doubleLoopOfSample() -> HandwritingSample {
        sample(
            strokes: doubleLoopO(centerX: 0.27)
                + lowercaseF(centerX: 0.68)
        )
    }

    static func tightConnectedOfSample() -> HandwritingSample {
        var connected = ellipse(
            centerX: 0.31,
            centerY: 0.49,
            radiusX: 0.15,
            radiusY: 0.20
        )
        connected.append(
            contentsOf: points([
                (0.45, 0.47),
                (0.50, 0.38),
                (0.54, 0.22),
                (0.58, 0.13),
                (0.64, 0.12),
                (0.67, 0.18),
                (0.64, 0.27),
                (0.58, 0.38),
                (0.55, 0.55),
                (0.54, 0.76),
            ])
        )
        return sample(
            strokes: [
                connected,
                points([
                    (0.46, 0.36),
                    (0.54, 0.35),
                    (0.62, 0.35),
                    (0.70, 0.36),
                ]),
            ]
        )
    }

    static func jitteredOfSample() -> HandwritingSample {
        sample(
            strokes: jittered(
                doubleLoopO(centerX: 0.27) + loopedF(centerX: 0.68)
            )
        )
    }

    static func openOffSample() -> HandwritingSample {
        sample(
            strokes: openO(centerX: 0.27)
                + lowercaseF(centerX: 0.52)
                + lowercaseF(centerX: 0.79)
        )
    }

    static func doubleLoopOffSample() -> HandwritingSample {
        sample(
            strokes: doubleLoopO(centerX: 0.27)
                + lowercaseF(centerX: 0.52)
                + lowercaseF(centerX: 0.79)
        )
    }

    static func tightOnSample() -> HandwritingSample {
        sample(
            strokes: lowercaseO(centerX: 0.28)
                + lowercaseN(centerX: 0.56)
        )
    }

    static func tightOtSample() -> HandwritingSample {
        sample(
            strokes: lowercaseO(centerX: 0.28)
                + lowercaseT(centerX: 0.56)
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

    private static func numericZero(centerX: Double) -> [[HandwritingPoint]] {
        [ellipse(centerX: centerX, centerY: 0.48, radiusX: 0.11, radiusY: 0.31)]
    }

    private static func openO(centerX: Double) -> [[HandwritingPoint]] {
        [
            stride(
                from: 0.38,
                through: (Double.pi * 2) - 0.38,
                by: Double.pi / 24
            ).map { angle in
                point(
                    x: centerX + (cos(angle) * 0.14),
                    y: 0.48 + (sin(angle) * 0.20)
                )
            }
        ]
    }

    private static func doubleLoopO(centerX: Double) -> [[HandwritingPoint]] {
        [
            ellipse(
                centerX: centerX,
                centerY: 0.48,
                radiusX: 0.14,
                radiusY: 0.20
            )
                + ellipse(
                    centerX: centerX + 0.006,
                    centerY: 0.485,
                    radiusX: 0.135,
                    radiusY: 0.195
                )
        ]
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

    private static func loopedF(centerX: Double) -> [[HandwritingPoint]] {
        [
            points([
                (centerX - 0.04, 0.77),
                (centerX - 0.03, 0.58),
                (centerX - 0.02, 0.39),
                (centerX - 0.01, 0.23),
                (centerX + 0.04, 0.13),
                (centerX + 0.12, 0.12),
                (centerX + 0.15, 0.18),
                (centerX + 0.11, 0.26),
                (centerX + 0.03, 0.30),
                (centerX - 0.03, 0.27),
            ]),
            points([
                (centerX - 0.15, 0.37),
                (centerX - 0.06, 0.35),
                (centerX + 0.04, 0.35),
                (centerX + 0.13, 0.37),
            ]),
        ]
    }

    private static func lowercaseN(centerX: Double) -> [[HandwritingPoint]] {
        [
            points([
                (centerX - 0.12, 0.72),
                (centerX - 0.12, 0.38),
                (centerX - 0.12, 0.72),
                (centerX - 0.08, 0.48),
                (centerX, 0.37),
                (centerX + 0.09, 0.40),
                (centerX + 0.12, 0.52),
                (centerX + 0.12, 0.72),
            ])
        ]
    }

    private static func lowercaseT(centerX: Double) -> [[HandwritingPoint]] {
        [
            points([
                (centerX, 0.20),
                (centerX, 0.38),
                (centerX, 0.57),
                (centerX + 0.02, 0.72),
                (centerX + 0.09, 0.74),
            ]),
            points([
                (centerX - 0.12, 0.39),
                (centerX + 0.12, 0.39),
            ]),
        ]
    }

    private static func jittered(
        _ strokes: [[HandwritingPoint]]
    ) -> [[HandwritingPoint]] {
        strokes.enumerated().map { strokeIndex, stroke in
            stroke.enumerated().map { pointIndex, source in
                let phase = Double((strokeIndex * 17) + pointIndex)
                return point(
                    x: source.location.x + (sin(phase * 1.7) * 0.008),
                    y: source.location.y + (cos(phase * 1.1) * 0.011)
                )
            }
        }
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
