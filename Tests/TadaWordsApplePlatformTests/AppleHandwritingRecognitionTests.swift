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

    func testLazyPassTraversalDoesNotExecuteThirdRenderAfterSecondMatches() async {
        var executedPasses: [Int] = []

        let result = await AppleHandwritingPassTraversal.resolve(
            passes: [1, 2, 3]
        ) { pass in
            executedPasses.append(pass)
            return RecognitionResult(
                decision: pass == 2 ? .matched : .uncertain
            )
        }

        XCTAssertEqual(result?.decision, .matched)
        XCTAssertEqual(executedPasses, [1, 2])
    }

    func testLazyPassTraversalExecutesThirdRenderWhenEarlierPassesDoNotMatch() async {
        var executedPasses: [Int] = []

        let result = await AppleHandwritingPassTraversal.resolve(
            passes: [1, 2, 3]
        ) { pass in
            executedPasses.append(pass)
            return RecognitionResult(
                decision: pass == 3 ? .matched : .uncertain
            )
        }

        XCTAssertEqual(result?.decision, .matched)
        XCTAssertEqual(executedPasses, [1, 2, 3])
    }

    func testLazyPassTraversalStopsAfterTechnicalFailure() async {
        var executedPasses: [Int] = []

        let result = await AppleHandwritingPassTraversal.resolve(
            passes: [1, 2, 3]
        ) { pass in
            executedPasses.append(pass)
            return RecognitionResult(
                decision: pass == 2
                    ? .technicalFailure(.serviceUnavailable)
                    : .uncertain
            )
        }

        XCTAssertEqual(result?.decision, .technicalFailure(.serviceUnavailable))
        XCTAssertEqual(executedPasses, [1, 2])
    }

    func testInjectedOfSingleLowRankTargetBehindStrongOtDoesNotMatch() async throws {
        let (service, recorder) = makeInjectedOfService(passFragments: [
            [fragment(candidates: [("ot", 0.96), ("of", 0.72)], x: 0.1)],
            [],
            [],
        ])

        let result = try await service.recognize(
            sample: minimalHandwritingSample(),
            prompt: try WordPrompt(learningMode: .write, text: "of"),
            for: ProfileID()
        )

        XCTAssertNotEqual(result.decision, .matched)
        XCTAssertEqual(result.recognizedText, "of")
        let callCount = await recorder.callCount()
        XCTAssertEqual(callCount, 3)
    }

    func testInjectedOfCorroboratesLowRankTargetAcrossPasses() async throws {
        let (service, recorder) = makeInjectedOfService(passFragments: [
            [fragment(candidates: [("ot", 0.96), ("of", 0.72)], x: 0.1)],
            [fragment(candidates: [("on", 0.94), ("Of", 0.68)], x: 0.1)],
            [],
        ])

        let result = try await service.recognize(
            sample: minimalHandwritingSample(),
            prompt: try WordPrompt(learningMode: .write, text: "of"),
            for: ProfileID()
        )

        XCTAssertEqual(result.decision, .matched)
        XCTAssertEqual(result.recognizedText, "of")
        XCTAssertEqual(result.confidence, RecognitionConfidence(0.68))
        let callCount = await recorder.callCount()
        XCTAssertEqual(callCount, 3)
    }

    func testInjectedOfCollectsLaterOffBeforeAcceptingEarlyTopMatch() async throws {
        let (service, recorder) = makeInjectedOfService(passFragments: [
            [fragment("of", confidence: 1, x: 0.1)],
            [fragment(candidates: [("off", 1), ("of", 0.30)], x: 0.1)],
            [],
        ])

        let result = try await service.recognize(
            sample: minimalHandwritingSample(),
            prompt: try WordPrompt(learningMode: .write, text: "of"),
            for: ProfileID()
        )

        XCTAssertNotEqual(result.decision, .matched)
        XCTAssertEqual(result.recognizedText, "off")
        let callCount = await recorder.callCount()
        XCTAssertEqual(callCount, 3)
    }

    func testInjectedOfAcceptsZeroFAsTargetAlignedOShape() async throws {
        let (service, recorder) = makeInjectedOfService(passFragments: [
            [fragment("0F", confidence: 0.86, x: 0.1)],
            [],
            [],
        ])

        let result = try await service.recognize(
            sample: minimalHandwritingSample(),
            prompt: try WordPrompt(learningMode: .write, text: "of"),
            for: ProfileID()
        )

        XCTAssertEqual(result.decision, .matched)
        XCTAssertEqual(result.recognizedText, "of")
        XCTAssertEqual(result.confidence, RecognitionConfidence(0.86))
        let callCount = await recorder.callCount()
        XCTAssertEqual(callCount, 3)
    }

    func testInjectedOfZeroFFStillTriggersOffVeto() async throws {
        let (service, recorder) = makeInjectedOfService(passFragments: [
            [fragment("0f", confidence: 1, x: 0.1)],
            [fragment("0ff", confidence: 1, x: 0.1)],
            [],
        ])

        let result = try await service.recognize(
            sample: minimalHandwritingSample(),
            prompt: try WordPrompt(learningMode: .write, text: "of"),
            for: ProfileID()
        )

        XCTAssertNotEqual(result.decision, .matched)
        XCTAssertEqual(result.recognizedText, "off")
        let callCount = await recorder.callCount()
        XCTAssertEqual(callCount, 3)
    }

    func testLazyPassTraversalPropagatesCancellationWithoutExecutingLaterPasses() async {
        var executedPasses: [Int] = []

        do {
            _ = try await AppleHandwritingPassTraversal.resolve(
                passes: [1, 2, 3]
            ) { pass in
                executedPasses.append(pass)
                if pass == 2 {
                    throw CancellationError()
                }
                return RecognitionResult(decision: .uncertain)
            }
            XCTFail("Expected cancellation to propagate")
        } catch is CancellationError {
            XCTAssertEqual(executedPasses, [1, 2])
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    func testWritePipelineAcceptsOfAcrossCaseAndFragmentShapes() throws {
        let prompt = try WordPrompt(learningMode: .write, text: "of")
        let resolver = makeResultResolver()
        let cases = [
            [fragment("of", confidence: 0.92, x: 0.1)],
            [fragment("Of", confidence: 0.92, x: 0.1)],
            [fragment("OF", confidence: 0.92, x: 0.1)],
            [fragment("oF", confidence: 0.92, x: 0.1)],
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

    func testWritePipelineFindsExactOfBeyondFirstFiveVisionAlternatives() throws {
        let result = makeResultResolver().resolve(
            fragments: [
                fragment(
                    candidates: [
                        ("ot", 0.99),
                        ("or", 0.92),
                        ("on", 0.88),
                        ("if", 0.82),
                        ("off", 0.78),
                        ("oF", 0.67),
                    ],
                    x: 0.1
                )
            ],
            target: try WordPrompt(learningMode: .write, text: "of")
        )

        XCTAssertEqual(result.decision, .matched)
        XCTAssertEqual(result.recognizedText, "of")
        XCTAssertEqual(result.confidence, RecognitionConfidence(0.67))
    }

    func testWritePipelineAcceptsZeroOnlyAsTargetAlignedLetterO() throws {
        let ofPrompt = try WordPrompt(learningMode: .write, text: "of")
        let dogPrompt = try WordPrompt(learningMode: .write, text: "dog")
        let resolver = makeResultResolver()

        for equivalent in ["0f", "0F"] {
            let result = resolver.resolve(
                fragments: [fragment(equivalent, confidence: 0.84, x: 0.1)],
                target: ofPrompt
            )
            XCTAssertEqual(result.decision, .matched)
            XCTAssertEqual(result.recognizedText, "of")
        }
        for invalid in ["00", "90", "0t", "0ff", "+0", "f0"] {
            XCTAssertNotEqual(
                resolver.resolve(
                    fragments: [fragment(invalid, confidence: 0.98, x: 0.1)],
                    target: ofPrompt
                ).decision,
                .matched,
                "Unexpected of match for \(invalid)"
            )
        }
        XCTAssertEqual(
            resolver.resolve(
                fragments: [fragment("d0g", confidence: 0.81, x: 0.1)],
                target: dogPrompt
            ).decision,
            .matched
        )
    }

    func testWritePipelineRequiresLetterCorroborationForNineAsG() throws {
        let prompt = try WordPrompt(learningMode: .write, text: "go")
        let resolver = makeResultResolver()
        let childLetterEvidence = [
            fragment(candidates: [("90", 1), ("g0", 0.5)], x: 0.1)
        ]
        let numericEvidence = [
            fragment(candidates: [("90", 1), ("9", 0.3), ("0", 0.3)], x: 0.1)
        ]

        let childResult = resolver.resolve(
            fragments: childLetterEvidence,
            target: prompt
        )
        let numericResult = resolver.resolve(
            fragments: numericEvidence,
            target: prompt
        )

        XCTAssertEqual(childResult.decision, .matched)
        XCTAssertEqual(childResult.confidence, RecognitionConfidence(1))
        XCTAssertEqual(numericResult.decision, .notMatched)
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

    func testOfAloneUsesExpandedVisionCandidatesAndVocabulary() throws {
        let ofPrompt = try WordPrompt(learningMode: .write, text: "of")
        let goPrompt = try WordPrompt(learningMode: .write, text: "go")

        XCTAssertEqual(
            AppleHandwritingRecognitionVocabulary.words(for: ofPrompt),
            ["of", "Of", "OF", "oF"]
        )
        XCTAssertEqual(
            AppleHandwritingRecognitionVocabulary.words(for: goPrompt),
            ["go", "Go", "GO"]
        )
        XCTAssertEqual(AppleHandwritingVisionCandidatePolicy.limit(for: ofPrompt), 10)
        XCTAssertEqual(AppleHandwritingVisionCandidatePolicy.limit(for: goPrompt), 5)
    }

    func testProductionVisionPipelineAcceptsOfAndGoAcrossCaseForms() async throws {
        let service = AppleHandwritingRecognitionService()
        for word in ["of", "go"] {
            let prompt = try WordPrompt(learningMode: .write, text: word)
            let styles =
                word == "of"
                ? HandwritingFixtureStyle.allCases
                : [.lowercase, .initialCapital, .allCaps]
            for style in styles {
                let sample = handwritingFixture(word: word, style: style)
                let result = try await service.recognize(
                    sample: sample,
                    prompt: prompt,
                    for: ProfileID()
                )
                XCTAssertEqual(
                    result.decision,
                    .matched,
                    "Expected actual Vision pipeline to accept \(word) as \(style); got \(String(describing: result.recognizedText)) at \(String(describing: result.confidence))"
                )
            }
        }
    }

    func testProductionVisionPipelineAcceptsConnectedLowercaseOf() async throws {
        let prompt = try WordPrompt(learningMode: .write, text: "of")
        let result = try await AppleHandwritingRecognitionService().recognize(
            sample: connectedLowercaseOfFixture(),
            prompt: prompt,
            for: ProfileID()
        )

        XCTAssertEqual(
            result.decision,
            .matched,
            "Expected connected lowercase of to match; received "
                + String(describing: result.recognizedText)
                + " at "
                + String(describing: result.confidence)
        )
    }

    func testProductionVisionAcceptsNumericZeroFShapeForOf() async throws {
        let prompt = try WordPrompt(learningMode: .write, text: "of")
        let result = try await AppleHandwritingRecognitionService().recognize(
            sample: numericZeroFOfFixture(),
            prompt: prompt,
            for: ProfileID()
        )

        XCTAssertEqual(
            result.decision,
            .matched,
            "Expected a numeric-zero shape followed by f to match of; got "
                + String(describing: result.recognizedText)
                + " at "
                + String(describing: result.confidence)
        )
    }

    func testProductionVisionAcceptsAdversarialOfCorpus() async throws {
        let service = AppleHandwritingRecognitionService()
        let prompt = try WordPrompt(learningMode: .write, text: "of")

        for style in AdversarialOfStyle.allCases {
            let sample = adversarialOfFixture(style: style)
            let result = try await service.recognize(
                sample: sample,
                prompt: prompt,
                for: ProfileID()
            )
            XCTAssertEqual(
                result.decision,
                .matched,
                "Expected adversarial of style \(style.rawValue) to match; got "
                    + String(describing: result.recognizedText)
                    + " at "
                    + String(describing: result.confidence)
            )
        }
    }

    func testProductionVisionRejectsPairedAdversarialOfNeighbors() async throws {
        let service = AppleHandwritingRecognitionService()
        let prompt = try WordPrompt(learningMode: .write, text: "of")

        for style in AdversarialOfStyle.allCases {
            for neighbor in ["ot", "on", "or", "off", "if"] {
                let result = try await service.recognize(
                    sample: adversarialNeighborFixture(
                        word: neighbor,
                        style: style
                    ),
                    prompt: prompt,
                    for: ProfileID()
                )
                XCTAssertNotEqual(
                    result.decision,
                    .matched,
                    "Writing \(neighbor) as \(style.rawValue) must not pass for of"
                )
            }
        }
    }

    func testProductionVisionPassesExposeBoundedOfAndGoEvidence() async throws {
        let ofPrompt = try WordPrompt(learningMode: .write, text: "of")
        let ofConfigurations = AppleHandwritingRasterPassPolicy.configurations(
            startingWith: .default,
            target: ofPrompt
        )
        XCTAssertEqual(ofConfigurations.map(\.lineWidth), [26, 36, 60])
        XCTAssertEqual(ofConfigurations.map(\.canvasPadding), [54, 54, 54])

        let goPrompt = try WordPrompt(learningMode: .write, text: "go")
        let goConfigurations = AppleHandwritingRasterPassPolicy.configurations(
            startingWith: .default,
            target: goPrompt
        )
        XCTAssertEqual(goConfigurations.map(\.lineWidth), [26, 36])
        XCTAssertEqual(goConfigurations.map(\.canvasPadding), [54, 54])

        let ofSample = handwritingFixture(word: "of", style: .lowercase)
        let primaryOf = try await productionFragments(
            sample: ofSample,
            prompt: ofPrompt,
            configuration: ofConfigurations[0]
        )
        let fallbackOf = try await productionFragments(
            sample: ofSample,
            prompt: ofPrompt,
            configuration: ofConfigurations[1]
        )

        XCTAssertTrue(primaryOf.isEmpty)
        XCTAssertGreaterThanOrEqual(
            confidence(of: "of", in: fallbackOf) ?? 0,
            AppleRecognitionThresholds.handwriting.minimumMatchConfidence.value
        )

        let lowercaseGo = try await productionFragments(
            sample: handwritingFixture(word: "go", style: .lowercase),
            prompt: goPrompt,
            configuration: goConfigurations[0]
        )
        XCTAssertGreaterThanOrEqual(confidence(of: "90", in: lowercaseGo) ?? 0, 0.99)
        XCTAssertGreaterThanOrEqual(confidence(of: "g0", in: lowercaseGo) ?? 0, 0.49)

        let numericNinety = try await productionFragments(
            sample: numericNinetyFixture(),
            prompt: goPrompt,
            configuration: goConfigurations[0]
        )
        XCTAssertGreaterThanOrEqual(confidence(of: "90", in: numericNinety) ?? 0, 0.99)
        XCTAssertNil(confidence(of: "g0", in: numericNinety))
    }

    func testProductionVisionPipelineRejectsRealNeighborFixtures() async throws {
        let service = AppleHandwritingRecognitionService()
        let cases = [
            (target: "of", written: "on"),
            (target: "of", written: "if"),
            (target: "of", written: "ot"),
            (target: "of", written: "or"),
            (target: "of", written: "off"),
            (target: "go", written: "do"),
            (target: "go", written: "no"),
        ]

        for testCase in cases {
            let result = try await service.recognize(
                sample: neighborFixture(testCase.written),
                prompt: try WordPrompt(
                    learningMode: .write,
                    text: testCase.target
                ),
                for: ProfileID()
            )
            XCTAssertNotEqual(
                result.decision,
                .matched,
                "Writing \(testCase.written) must not pass for \(testCase.target)"
            )
        }

        let numericResult = try await service.recognize(
            sample: numericNinetyFixture(),
            prompt: try WordPrompt(learningMode: .write, text: "go"),
            for: ProfileID()
        )
        XCTAssertNotEqual(
            numericResult.decision,
            .matched,
            "A literal 90 must not pass for go"
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

    private func makeInjectedOfService(
        passFragments: [[AppleRecognizedTextFragment]]
    ) -> (AppleHandwritingRecognitionService, InjectedHandwritingPassRecorder) {
        let recorder = InjectedHandwritingPassRecorder(
            passFragments: passFragments
        )
        let recognizer = AppleHandwritingVisionRecognizer(
            recognition: { _, _, _ in
                await recorder.nextPass()
            }
        )
        return (
            AppleHandwritingRecognitionService(
                configuration: .default,
                visionRecognizer: recognizer
            ),
            recorder
        )
    }

    private func minimalHandwritingSample() -> HandwritingSample {
        HandwritingSample(
            strokes: [
                HandwritingStroke(points: [
                    point(x: 0.2, y: 0.3),
                    point(x: 0.8, y: 0.7),
                ])
            ],
            inputMethod: .finger
        )
    }

    private func point(x: Double, y: Double) -> HandwritingPoint {
        HandwritingPoint(
            location: TadaWordsDomain.NormalizedPoint(x: x, y: y),
            elapsedSincePrompt: .zero
        )
    }

    private enum HandwritingFixtureStyle: CaseIterable {
        case lowercase
        case initialCapital
        case allCaps
        case finalCapital
    }

    private enum AdversarialOfStyle: String, CaseIterable {
        case openO
        case doubleLoopO
        case loopedF
        case integratedCrossbar
        case tightOverlap
        case jitteredOvertrace
    }

    private func handwritingFixture(
        word: String,
        style: HandwritingFixtureStyle
    ) -> HandwritingSample {
        let strokes: [[HandwritingPoint]]
        switch (word, style) {
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
            strokes = []
        }
        return HandwritingSample(
            strokes: strokes.map(HandwritingStroke.init(points:)),
            inputMethod: .finger
        )
    }

    private func lowercaseO(centerX: Double) -> [[HandwritingPoint]] {
        [ellipse(centerX: centerX, centerY: 0.48, radiusX: 0.14, radiusY: 0.20)]
    }

    private func capitalO(centerX: Double) -> [[HandwritingPoint]] {
        [ellipse(centerX: centerX, centerY: 0.48, radiusX: 0.16, radiusY: 0.32)]
    }

    private func lowercaseF(centerX: Double) -> [[HandwritingPoint]] {
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

    private func connectedLowercaseOfFixture() -> HandwritingSample {
        var connectedStroke = ellipse(
            centerX: 0.27,
            centerY: 0.48,
            radiusX: 0.14,
            radiusY: 0.20
        )
        connectedStroke.append(
            contentsOf: points([
                (0.44, 0.46),
                (0.54, 0.38),
                (0.62, 0.23),
                (0.68, 0.14),
                (0.73, 0.13),
                (0.76, 0.17),
                (0.74, 0.26),
                (0.68, 0.39),
                (0.64, 0.55),
                (0.62, 0.76),
            ])
        )
        return HandwritingSample(
            strokes: [
                HandwritingStroke(points: connectedStroke),
                HandwritingStroke(
                    points: points([
                        (0.54, 0.36),
                        (0.62, 0.35),
                        (0.70, 0.35),
                        (0.79, 0.36),
                    ])
                ),
            ],
            inputMethod: .finger
        )
    }

    private func adversarialOfFixture(
        style: AdversarialOfStyle
    ) -> HandwritingSample {
        let strokes: [[HandwritingPoint]]
        switch style {
        case .openO:
            strokes = openO(centerX: 0.27) + lowercaseF(centerX: 0.68)
        case .doubleLoopO:
            strokes = doubleLoopO(centerX: 0.27) + lowercaseF(centerX: 0.68)
        case .loopedF:
            strokes = lowercaseO(centerX: 0.27) + loopedF(centerX: 0.68)
        case .integratedCrossbar:
            strokes = lowercaseO(centerX: 0.27) + integratedCrossbarF(centerX: 0.68)
        case .tightOverlap:
            return tightConnectedOfFixture()
        case .jitteredOvertrace:
            strokes = jittered(
                doubleLoopO(centerX: 0.27) + loopedF(centerX: 0.68)
            )
        }
        return sample(strokes: strokes)
    }

    private func adversarialNeighborFixture(
        word: String,
        style: AdversarialOfStyle
    ) -> HandwritingSample {
        let tight = style == .tightOverlap
        let firstCenter = tight ? 0.28 : 0.27
        let secondCenter = tight ? 0.56 : 0.70
        let firstO: [[HandwritingPoint]]
        switch style {
        case .openO:
            firstO = openO(centerX: firstCenter)
        case .doubleLoopO, .jitteredOvertrace:
            firstO = doubleLoopO(centerX: firstCenter)
        case .loopedF, .integratedCrossbar, .tightOverlap:
            firstO = lowercaseO(centerX: firstCenter)
        }

        let styledF: (Double) -> [[HandwritingPoint]] = { centerX in
            switch style {
            case .loopedF, .jitteredOvertrace:
                self.loopedF(centerX: centerX)
            case .integratedCrossbar:
                self.integratedCrossbarF(centerX: centerX)
            case .openO, .doubleLoopO, .tightOverlap:
                self.lowercaseF(centerX: centerX)
            }
        }

        let strokes: [[HandwritingPoint]]
        switch word {
        case "ot":
            strokes = firstO + lowercaseT(centerX: secondCenter)
        case "on":
            strokes = firstO + lowercaseN(centerX: secondCenter)
        case "or":
            strokes = firstO + lowercaseR(centerX: secondCenter)
        case "off":
            let firstF = tight ? 0.50 : 0.52
            let secondF = tight ? 0.63 : 0.79
            strokes = firstO + styledF(firstF) + styledF(secondF)
        case "if":
            strokes = lowercaseI(centerX: firstCenter) + styledF(secondCenter)
        default:
            strokes = []
        }
        return sample(
            strokes: style == .jitteredOvertrace ? jittered(strokes) : strokes
        )
    }

    private func openO(centerX: Double) -> [[HandwritingPoint]] {
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

    private func doubleLoopO(centerX: Double) -> [[HandwritingPoint]] {
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

    private func loopedF(centerX: Double) -> [[HandwritingPoint]] {
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

    private func integratedCrossbarF(centerX: Double) -> [[HandwritingPoint]] {
        [
            points([
                (centerX + 0.12, 0.17),
                (centerX + 0.06, 0.12),
                (centerX - 0.01, 0.13),
                (centerX - 0.06, 0.22),
                (centerX - 0.06, 0.43),
                (centerX - 0.06, 0.75),
                (centerX - 0.06, 0.48),
                (centerX - 0.06, 0.36),
                (centerX - 0.16, 0.36),
                (centerX - 0.04, 0.35),
                (centerX + 0.13, 0.36),
            ])
        ]
    }

    private func tightConnectedOfFixture() -> HandwritingSample {
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

    private func jittered(
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

    private func sample(
        strokes: [[HandwritingPoint]]
    ) -> HandwritingSample {
        HandwritingSample(
            strokes: strokes.map(HandwritingStroke.init(points:)),
            inputMethod: .finger
        )
    }

    private func capitalF(centerX: Double) -> [[HandwritingPoint]] {
        [
            points([(centerX - 0.09, 0.16), (centerX - 0.09, 0.80)]),
            points([(centerX - 0.09, 0.16), (centerX + 0.15, 0.16)]),
            points([(centerX - 0.09, 0.45), (centerX + 0.10, 0.45)]),
        ]
    }

    private func lowercaseG(centerX: Double) -> [[HandwritingPoint]] {
        [
            ellipse(centerX: centerX, centerY: 0.40, radiusX: 0.14, radiusY: 0.18),
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

    private func lowercaseN(centerX: Double) -> [[HandwritingPoint]] {
        [
            points([
                (centerX - 0.13, 0.69),
                (centerX - 0.13, 0.33),
                (centerX - 0.13, 0.54),
                (centerX - 0.08, 0.39),
                (centerX, 0.32),
                (centerX + 0.08, 0.36),
                (centerX + 0.12, 0.48),
                (centerX + 0.12, 0.69),
            ])
        ]
    }

    private func lowercaseI(centerX: Double) -> [[HandwritingPoint]] {
        [
            points([(centerX, 0.35), (centerX, 0.70)]),
            [point(x: centerX, y: 0.20)],
        ]
    }

    private func lowercaseD(centerX: Double) -> [[HandwritingPoint]] {
        lowercaseO(centerX: centerX) + [
            points([
                (centerX + 0.14, 0.72),
                (centerX + 0.14, 0.48),
                (centerX + 0.14, 0.25),
                (centerX + 0.14, 0.12),
            ])
        ]
    }

    private func lowercaseT(centerX: Double) -> [[HandwritingPoint]] {
        [
            points([
                (centerX, 0.22),
                (centerX, 0.38),
                (centerX, 0.55),
                (centerX, 0.72),
            ]),
            points([
                (centerX - 0.12, 0.36),
                (centerX, 0.35),
                (centerX + 0.12, 0.36),
            ]),
        ]
    }

    private func lowercaseR(centerX: Double) -> [[HandwritingPoint]] {
        [
            points([
                (centerX - 0.11, 0.70),
                (centerX - 0.11, 0.35),
                (centerX - 0.11, 0.52),
                (centerX - 0.05, 0.39),
                (centerX + 0.04, 0.34),
                (centerX + 0.12, 0.38),
            ])
        ]
    }

    private func neighborFixture(_ word: String) -> HandwritingSample {
        let strokes: [[HandwritingPoint]]
        switch word {
        case "on":
            strokes = lowercaseO(centerX: 0.27) + lowercaseN(centerX: 0.70)
        case "if":
            strokes = lowercaseI(centerX: 0.25) + lowercaseF(centerX: 0.68)
        case "ot":
            strokes = lowercaseO(centerX: 0.27) + lowercaseT(centerX: 0.70)
        case "or":
            strokes = lowercaseO(centerX: 0.27) + lowercaseR(centerX: 0.70)
        case "off":
            strokes =
                lowercaseO(centerX: 0.18)
                + lowercaseF(centerX: 0.50)
                + lowercaseF(centerX: 0.79)
        case "do":
            strokes = lowercaseD(centerX: 0.27) + lowercaseO(centerX: 0.72)
        case "no":
            strokes = lowercaseN(centerX: 0.27) + lowercaseO(centerX: 0.72)
        default:
            strokes = []
        }
        return HandwritingSample(
            strokes: strokes.map(HandwritingStroke.init(points:)),
            inputMethod: .finger
        )
    }

    private func numericNinetyFixture() -> HandwritingSample {
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
            ]))
        return HandwritingSample(
            strokes: [
                HandwritingStroke(points: nine),
                HandwritingStroke(
                    points: ellipse(
                        centerX: 0.72,
                        centerY: 0.48,
                        radiusX: 0.15,
                        radiusY: 0.31
                    )
                ),
            ],
            inputMethod: .finger
        )
    }

    private func numericZeroFOfFixture() -> HandwritingSample {
        sample(
            strokes: [
                ellipse(
                    centerX: 0.27,
                    centerY: 0.48,
                    radiusX: 0.11,
                    radiusY: 0.31
                )
            ] + lowercaseF(centerX: 0.68)
        )
    }

    private func capitalG(centerX: Double) -> [[HandwritingPoint]] {
        let arc = stride(from: 0.65, through: (Double.pi * 2) - 0.65, by: 0.12)
            .map { angle in
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

    private func ellipse(
        centerX: Double,
        centerY: Double,
        radiusX: Double,
        radiusY: Double
    ) -> [HandwritingPoint] {
        stride(from: 0.0, through: Double.pi * 2, by: Double.pi / 24).map {
            angle in
            point(
                x: centerX + (cos(angle) * radiusX),
                y: centerY + (sin(angle) * radiusY)
            )
        }
    }

    private func points(_ coordinates: [(Double, Double)]) -> [HandwritingPoint] {
        coordinates.map { point(x: $0.0, y: $0.1) }
    }

    private func productionFragments(
        sample: HandwritingSample,
        prompt: WordPrompt,
        configuration: AppleHandwritingRecognitionConfiguration
    ) async throws -> [AppleRecognizedTextFragment] {
        let image = try HandwritingSampleRenderer(configuration: configuration)
            .render(sample)
        return try await AppleHandwritingVisionRecognizer().recognize(
            image: image,
            prompt: prompt,
            minimumTextHeightFraction: configuration.minimumTextHeightFraction
        )
    }

    private func confidence(
        of text: String,
        in fragments: [AppleRecognizedTextFragment]
    ) -> Double? {
        fragments.lazy.flatMap(\.candidates).first {
            $0.text == text
        }.map {
            $0.confidence.value
        }
    }

}

private actor InjectedHandwritingPassRecorder {
    private let passFragments: [[AppleRecognizedTextFragment]]
    private var nextPassIndex = 0

    init(passFragments: [[AppleRecognizedTextFragment]]) {
        self.passFragments = passFragments
    }

    func nextPass() -> [AppleRecognizedTextFragment] {
        guard nextPassIndex < passFragments.count else {
            nextPassIndex += 1
            return []
        }
        defer { nextPassIndex += 1 }
        return passFragments[nextPassIndex]
    }

    func callCount() -> Int {
        nextPassIndex
    }
}
