import CoreGraphics
import Foundation
import TadaWordsDomain
import Vision

public struct AppleHandwritingRecognitionConfiguration: Equatable, Sendable {
    public let canvasWidth: Int
    public let canvasHeight: Int
    public let lineWidth: CGFloat
    public let canvasPadding: CGFloat
    public let minimumTextHeightFraction: Float
    public let decisionThresholds: AppleRecognitionThresholds

    public init(
        canvasWidth: Int = 1_024,
        canvasHeight: Int = 512,
        lineWidth: CGFloat = 26,
        canvasPadding: CGFloat = 54,
        minimumTextHeightFraction: Float = 0.05,
        decisionThresholds: AppleRecognitionThresholds = .handwriting
    ) {
        self.canvasWidth = max(256, canvasWidth)
        self.canvasHeight = max(128, canvasHeight)
        self.lineWidth = max(2, lineWidth)
        self.canvasPadding = max(0, canvasPadding)
        self.minimumTextHeightFraction = min(
            1,
            max(0, minimumTextHeightFraction)
        )
        self.decisionThresholds = decisionThresholds
    }

    public static let `default` = AppleHandwritingRecognitionConfiguration()
}

/// Recognizes the letter sequence in a child's normalized vector strokes.
/// Stroke order, pressure, shape quality, and penmanship never affect scoring.
public struct AppleHandwritingRecognitionService:
    HandwritingRecognitionService,
    Sendable
{
    private let configuration: AppleHandwritingRecognitionConfiguration
    private let visionRecognizer: AppleHandwritingVisionRecognizer
    private let resultResolver: AppleHandwritingRecognitionResultResolver

    public init(
        configuration: AppleHandwritingRecognitionConfiguration = .default
    ) {
        self.init(
            configuration: configuration,
            visionRecognizer: AppleHandwritingVisionRecognizer()
        )
    }

    init(
        configuration: AppleHandwritingRecognitionConfiguration,
        visionRecognizer: AppleHandwritingVisionRecognizer
    ) {
        self.configuration = configuration
        self.visionRecognizer = visionRecognizer
        self.resultResolver = AppleHandwritingRecognitionResultResolver(
            thresholds: configuration.decisionThresholds
        )
    }

    public func recognize(
        sample: HandwritingSample,
        prompt: WordPrompt,
        for profileID: ProfileID
    ) async throws -> RecognitionResult {
        _ = profileID
        try Task.checkCancellation()

        let rasterPassConfigurations =
            AppleHandwritingRasterPassPolicy.configurations(
                startingWith: configuration,
                target: prompt
            )
        if AppleHandwritingOfEvidencePolicy.applies(to: prompt) {
            return try await recognizeOf(
                sample: sample,
                prompt: prompt,
                configurations: rasterPassConfigurations
            )
        }

        let result = try await AppleHandwritingPassTraversal.resolve(
            passes: rasterPassConfigurations,
            execute: { passConfiguration in
                try Task.checkCancellation()

                let image: CGImage
                do {
                    image = try HandwritingSampleRenderer(
                        configuration: passConfiguration
                    ).render(sample)
                } catch {
                    return resultResolver.technicalFailure(.corruptedInput)
                }

                do {
                    let fragments = try await visionRecognizer.recognize(
                        image: image,
                        prompt: prompt,
                        minimumTextHeightFraction:
                            passConfiguration.minimumTextHeightFraction
                    )
                    try Task.checkCancellation()
                    return resultResolver.resolve(
                        fragments: fragments,
                        target: prompt
                    )
                } catch is CancellationError {
                    throw CancellationError()
                } catch {
                    return resultResolver.technicalFailure(.serviceUnavailable)
                }
            }
        )
        return result ?? resultResolver.resolve(fragments: [], target: prompt)
    }

    /// `of` uses all three scales before deciding. This deliberately prevents
    /// an early exact hit from hiding `off` evidence exposed only by a later
    /// raster pass.
    private func recognizeOf(
        sample: HandwritingSample,
        prompt: WordPrompt,
        configurations: [AppleHandwritingRecognitionConfiguration]
    ) async throws -> RecognitionResult {
        var passFragments: [[AppleRecognizedTextFragment]] = []
        passFragments.reserveCapacity(configurations.count)

        for passConfiguration in configurations {
            try Task.checkCancellation()

            let image: CGImage
            do {
                image = try HandwritingSampleRenderer(
                    configuration: passConfiguration
                ).render(sample)
            } catch {
                return resultResolver.technicalFailure(.corruptedInput)
            }

            do {
                passFragments.append(
                    try await visionRecognizer.recognize(
                        image: image,
                        prompt: prompt,
                        minimumTextHeightFraction:
                            passConfiguration.minimumTextHeightFraction
                    )
                )
                try Task.checkCancellation()
            } catch is CancellationError {
                throw CancellationError()
            } catch {
                return resultResolver.technicalFailure(.serviceUnavailable)
            }
        }

        return AppleHandwritingOfEvidencePolicy(
            thresholds: configuration.decisionThresholds
        ).resolve(
            passFragments: passFragments,
            target: prompt,
            resultResolver: resultResolver
        )
    }
}

enum AppleHandwritingPassTraversal {
    /// Executes each complete render-and-recognize pass only after the previous
    /// pass failed to match. A successful or technical terminal result prevents
    /// later recovery passes from rendering at all.
    static func resolve<Pass>(
        passes: [Pass],
        execute: (Pass) async throws -> RecognitionResult
    ) async rethrows -> RecognitionResult? {
        var firstResult: RecognitionResult?
        for pass in passes {
            let result = try await execute(pass)
            if firstResult == nil {
                firstResult = result
            }
            switch result.decision {
            case .matched, .technicalFailure:
                return result
            case .notMatched, .uncertain:
                continue
            }
        }
        return firstResult
    }
}

/// Target-specific evidence aggregation for the short, visually ambiguous word
/// `of`. A complete top-ranked transcript can match at the normal handwriting
/// threshold. A target found only among lower-ranked candidates must recur at
/// two different raster scales. Any strong exact `off` transcript vetoes a
/// match because Vision was observed collapsing that spelling into `of`.
struct AppleHandwritingOfEvidencePolicy: Sendable {
    private let thresholds: AppleRecognitionThresholds

    init(thresholds: AppleRecognitionThresholds) {
        self.thresholds = thresholds
    }

    static func applies(to target: WordPrompt) -> Bool {
        target.normalizedText == targetText
    }

    func resolve(
        passFragments: [[AppleRecognizedTextFragment]],
        target: WordPrompt,
        resultResolver: AppleHandwritingRecognitionResultResolver
    ) -> RecognitionResult {
        precondition(Self.applies(to: target))
        let evidence = passFragments.map {
            AppleHandwritingOfPassEvidence(
                fragments: $0,
                target: target,
                resultResolver: resultResolver
            )
        }

        if let collision = evidence.compactMap(\.offCollision).max(
            by: { $0.confidence < $1.confidence }
        ) {
            return resultResolver.resolve(
                transcript: collision.letterSequence,
                confidence: collision.confidence,
                target: target
            )
        }

        if let directMatch = evidence.compactMap(\.topTarget).filter({
            $0.confidence >= thresholds.minimumMatchConfidence
        }).max(by: { $0.confidence < $1.confidence }) {
            return resultResolver.resolve(
                transcript: directMatch.letterSequence,
                confidence: directMatch.confidence,
                target: target
            )
        }

        let corroboratingTargets = evidence.compactMap(\.anyTarget).filter {
            $0.confidence >= Self.minimumCorroboratingConfidence
        }.sorted { $0.confidence > $1.confidence }
        if corroboratingTargets.count >= Self.requiredCorroboratingPasses {
            let confidence = corroboratingTargets[
                Self.requiredCorroboratingPasses - 1
            ].confidence
            return RecognitionResult(
                decision: .matched,
                recognizedText: target.normalizedText,
                confidence: confidence,
                targetSpeakerAssessment: .unavailable
            )
        }

        if let singleTarget = evidence.compactMap(\.anyTarget).max(
            by: { $0.confidence < $1.confidence }
        ) {
            return RecognitionResult(
                decision: .uncertain,
                recognizedText: target.normalizedText,
                confidence: singleTarget.confidence,
                targetSpeakerAssessment: .unavailable
            )
        }

        return evidence.first?.fallback
            ?? resultResolver.resolve(fragments: [], target: target)
    }

    /// Actual Vision traces use 0.50 for viable alternatives and 0.30 for weak
    /// guesses. Across the six positive styles and thirty paired negatives,
    /// 0.50 at two distinct scales recovered target evidence without admitting
    /// a non-`off` neighbor; `off` is handled by the explicit collision veto.
    private static let minimumCorroboratingConfidence =
        RecognitionConfidence(0.50)
    private static let requiredCorroboratingPasses = 2
    private static let targetText = "of"
}

private struct AppleHandwritingOfPassEvidence: Sendable {
    let topTarget: AppleHandwritingTranscript?
    let anyTarget: AppleHandwritingTranscript?
    let offCollision: AppleHandwritingTranscript?
    let fallback: RecognitionResult

    init(
        fragments: [AppleRecognizedTextFragment],
        target: WordPrompt,
        resultResolver: AppleHandwritingRecognitionResultResolver
    ) {
        let topOnlyFragments: [AppleRecognizedTextFragment] = fragments.compactMap {
            fragment -> AppleRecognizedTextFragment? in
            guard let candidate = fragment.candidates.first else { return nil }
            return AppleRecognizedTextFragment(
                candidates: [candidate],
                minimumX: fragment.minimumX,
                verticalCenter: fragment.verticalCenter
            )
        }
        self.topTarget = Self.exactTranscript(
            topOnlyFragments,
            matching: target.normalizedText
        )
        self.anyTarget = Self.exactTranscript(
            fragments,
            matching: target.normalizedText
        )
        let offTranscript = Self.exactTranscript(
            fragments,
            matching: "off"
        )
        self.offCollision =
            if let offTranscript,
                offTranscript.confidence >= Self.minimumOffCollisionConfidence
            {
                offTranscript
            } else {
                nil
            }
        self.fallback = resultResolver.resolve(
            fragments: topOnlyFragments,
            target: target
        )
    }

    private static let minimumOffCollisionConfidence =
        RecognitionConfidence(0.50)

    private static func exactTranscript(
        _ fragments: [AppleRecognizedTextFragment],
        matching normalizedTarget: String
    ) -> AppleHandwritingTranscript? {
        guard
            let transcript = AppleHandwritingTranscriptResolver.resolve(
                fragments,
                matching: normalizedTarget
            ),
            (try? EnglishWordNormalizer.normalize(transcript.letterSequence))
                == normalizedTarget
        else { return nil }
        return transcript
    }
}

enum AppleHandwritingRasterPassPolicy {
    /// v0.5 uses a primary raster plus one 36-point recovery pass. `of` alone
    /// adds a 60-point scale because actual connected and tightly overlapped
    /// fixtures were invisible to Vision at both legacy scales.
    static func configurations(
        startingWith primary: AppleHandwritingRecognitionConfiguration,
        target: WordPrompt
    ) -> [AppleHandwritingRecognitionConfiguration] {
        let legacyRecoveryLineWidth = max(
            Self.legacyRecoveryLineWidth,
            primary.lineWidth
        )
        var configurations: [AppleHandwritingRecognitionConfiguration]
        if legacyRecoveryLineWidth != primary.lineWidth {
            configurations = [
                primary,
                configuration(primary, lineWidth: legacyRecoveryLineWidth),
            ]
        } else if primary.canvasPadding != fallbackCanvasPadding {
            configurations = [
                primary,
                configuration(primary, canvasPadding: fallbackCanvasPadding),
            ]
        } else {
            configurations = [primary]
        }

        guard AppleHandwritingOfEvidencePolicy.applies(to: target) else {
            return configurations
        }
        let ofRecoveryLineWidth = max(Self.ofRecoveryLineWidth, primary.lineWidth)
        guard ofRecoveryLineWidth != primary.lineWidth,
            !configurations.contains(where: {
                $0.lineWidth == ofRecoveryLineWidth
                    && $0.canvasPadding == primary.canvasPadding
            })
        else { return configurations }
        configurations.append(
            configuration(primary, lineWidth: ofRecoveryLineWidth)
        )
        return configurations
    }

    private static let legacyRecoveryLineWidth: CGFloat = 36
    private static let ofRecoveryLineWidth: CGFloat = 60
    private static let fallbackCanvasPadding: CGFloat = 20

    private static func configuration(
        _ source: AppleHandwritingRecognitionConfiguration,
        lineWidth: CGFloat? = nil,
        canvasPadding: CGFloat? = nil
    ) -> AppleHandwritingRecognitionConfiguration {
        AppleHandwritingRecognitionConfiguration(
            canvasWidth: source.canvasWidth,
            canvasHeight: source.canvasHeight,
            lineWidth: lineWidth ?? source.lineWidth,
            canvasPadding: canvasPadding ?? source.canvasPadding,
            minimumTextHeightFraction: source.minimumTextHeightFraction,
            decisionThresholds: source.decisionThresholds
        )
    }
}

struct AppleHandwritingVisionRecognizer: Sendable {
    typealias InjectedRecognition =
        @Sendable (
            _ image: CGImage,
            _ prompt: WordPrompt,
            _ minimumTextHeightFraction: Float
        ) async throws -> [AppleRecognizedTextFragment]

    private let injectedRecognition: InjectedRecognition?

    init() {
        self.injectedRecognition = nil
    }

    init(recognition: @escaping InjectedRecognition) {
        self.injectedRecognition = recognition
    }

    func recognize(
        image: CGImage,
        prompt: WordPrompt,
        minimumTextHeightFraction: Float
    ) async throws -> [AppleRecognizedTextFragment] {
        if let injectedRecognition {
            return try await injectedRecognition(
                image,
                prompt,
                minimumTextHeightFraction
            )
        }

        var request = RecognizeTextRequest()
        request.recognitionLevel = .accurate
        request.recognitionLanguages = [Locale.Language(identifier: "en-US")]
        request.automaticallyDetectsLanguage = false
        request.usesLanguageCorrection = true
        request.customWords = AppleHandwritingRecognitionVocabulary.words(
            for: prompt
        )
        request.minimumTextHeightFraction = minimumTextHeightFraction
        let candidateLimit = AppleHandwritingVisionCandidatePolicy.limit(
            for: prompt
        )

        return try await request.perform(on: image, orientation: .up).compactMap {
            AppleRecognizedTextFragment(
                observation: $0,
                candidateLimit: candidateLimit
            )
        }
    }
}

enum AppleHandwritingVisionCandidatePolicy {
    static func limit(for target: WordPrompt) -> Int {
        AppleHandwritingOfEvidencePolicy.applies(to: target)
            ? ofCandidateLimit
            : legacyCandidateLimit
    }

    private static let legacyCandidateLimit = 5
    private static let ofCandidateLimit = 10
}

struct AppleRecognizedTextCandidate: Equatable, Sendable {
    let text: String
    let confidence: RecognitionConfidence
}

struct AppleRecognizedTextFragment: Equatable, Sendable {
    let candidates: [AppleRecognizedTextCandidate]
    let minimumX: CGFloat
    let verticalCenter: CGFloat

    var text: String { candidates.first?.text ?? "" }
    var confidence: RecognitionConfidence {
        candidates.first?.confidence ?? RecognitionConfidence(0)
    }

    init(
        text: String,
        confidence: RecognitionConfidence,
        minimumX: CGFloat,
        verticalCenter: CGFloat
    ) {
        self.candidates = [
            AppleRecognizedTextCandidate(text: text, confidence: confidence)
        ]
        self.minimumX = minimumX
        self.verticalCenter = verticalCenter
    }

    init(
        candidates: [AppleRecognizedTextCandidate],
        minimumX: CGFloat,
        verticalCenter: CGFloat
    ) {
        self.candidates = candidates
        self.minimumX = minimumX
        self.verticalCenter = verticalCenter
    }

    init?(observation: RecognizedTextObservation, candidateLimit: Int) {
        let candidates = observation.topCandidates(candidateLimit).map {
            AppleRecognizedTextCandidate(
                text: $0.string,
                confidence: RecognitionConfidence(Double($0.confidence))
            )
        }
        guard !candidates.isEmpty else {
            return nil
        }

        let points = [
            observation.topLeft,
            observation.topRight,
            observation.bottomRight,
            observation.bottomLeft,
        ]
        self.init(
            candidates: candidates,
            minimumX: points.map(\.x).min() ?? 0,
            verticalCenter: points.map(\.y).reduce(0, +) / CGFloat(points.count)
        )
    }
}

struct AppleHandwritingTranscript: Equatable, Sendable {
    let letterSequence: String
    let confidence: RecognitionConfidence
}

enum AppleHandwritingTranscriptResolver {
    static func resolve(
        _ fragments: [AppleRecognizedTextFragment],
        matching normalizedTarget: String? = nil
    ) -> AppleHandwritingTranscript? {
        let readableFragments = fragments.filter {
            !$0.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }
        guard !readableFragments.isEmpty else { return nil }

        let ordered = readableFragments.sorted { left, right in
            if left.minimumX != right.minimumX {
                return left.minimumX < right.minimumX
            }
            return left.verticalCenter > right.verticalCenter
        }

        if let normalizedTarget,
            let exactTargetTranscript = exactTargetTranscript(
                from: ordered,
                normalizedTarget: normalizedTarget
            )
        {
            return exactTargetTranscript
        }

        let letterSequence =
            ordered
            .map(\.text)
            .joined()
            .components(separatedBy: .whitespacesAndNewlines)
            .joined()
        guard !letterSequence.isEmpty else { return nil }

        let confidence =
            ordered.map(\.confidence).min()
            ?? RecognitionConfidence(0)
        return AppleHandwritingTranscript(
            letterSequence: letterSequence,
            confidence: confidence
        )
    }

    private static func exactTargetTranscript(
        from fragments: [AppleRecognizedTextFragment],
        normalizedTarget: String
    ) -> AppleHandwritingTranscript? {
        var partials = [
            "": AppleHandwritingPartialTranscript(
                normalizedSequence: "",
                confidence: RecognitionConfidence(1)
            )
        ]

        for fragment in fragments {
            var nextPartials: [String: AppleHandwritingPartialTranscript] = [:]
            for partial in partials.values {
                for candidate in fragment.candidates {
                    guard
                        let normalizedCandidate =
                            AppleHandwritingCandidateNormalizer.normalize(
                                candidate.text,
                                corroborating: fragment.candidates
                            )
                    else { continue }

                    let combined = partial.normalizedSequence + normalizedCandidate
                    guard normalizedTarget.hasPrefix(combined) else { continue }

                    let confidence = min(partial.confidence, candidate.confidence)
                    if let existing = nextPartials[combined],
                        existing.confidence >= confidence
                    {
                        continue
                    }
                    nextPartials[combined] = AppleHandwritingPartialTranscript(
                        normalizedSequence: combined,
                        confidence: confidence
                    )
                }
            }
            partials = nextPartials
            guard !partials.isEmpty else { return nil }
        }

        guard let match = partials[normalizedTarget] else { return nil }
        return AppleHandwritingTranscript(
            letterSequence: match.normalizedSequence,
            confidence: match.confidence
        )
    }
}

private struct AppleHandwritingPartialTranscript: Sendable {
    let normalizedSequence: String
    let confidence: RecognitionConfidence
}

/// Vision can emit `0` for a handwritten O and `9` for a single-storey g. Zero
/// is shape-equivalent to O. Nine is accepted as g only when another candidate
/// of the same length contains a literal g at that position. The final sequence
/// must still equal the complete target, so neighboring words and literal `90`
/// remain mismatches.
private enum AppleHandwritingCandidateNormalizer {
    static func normalize(
        _ candidate: String,
        corroborating candidates: [AppleRecognizedTextCandidate]
    ) -> String? {
        let compact = candidate.components(
            separatedBy: .whitespacesAndNewlines
        ).joined()
        if let normalized = try? EnglishWordNormalizer.normalize(compact) {
            return normalized
        }
        var glyphs = Array(compact)
        guard glyphs.contains("0") || glyphs.contains("9") else { return nil }
        for index in glyphs.indices {
            if glyphs[index] == "0" {
                glyphs[index] = "o"
            } else if glyphs[index] == "9" {
                guard
                    hasLiteralGCorroboration(
                        at: index,
                        candidateLength: glyphs.count,
                        candidates: candidates
                    )
                else { return nil }
                glyphs[index] = "g"
            }
        }
        return try? EnglishWordNormalizer.normalize(
            String(glyphs)
        )
    }

    private static func hasLiteralGCorroboration(
        at index: Int,
        candidateLength: Int,
        candidates: [AppleRecognizedTextCandidate]
    ) -> Bool {
        candidates.contains { candidate in
            let compact = candidate.text.components(
                separatedBy: .whitespacesAndNewlines
            ).joined().lowercased(with: Locale(identifier: "en_US_POSIX"))
            let characters = Array(compact)
            return characters.count == candidateLength
                && characters[index] == "g"
        }
    }
}

enum AppleHandwritingRecognitionVocabulary {
    static func words(for prompt: WordPrompt) -> [String] {
        let locale = Locale(identifier: "en_US_POSIX")
        var candidates = [
            prompt.normalizedText,
            prompt.normalizedText.prefix(1).uppercased(with: locale)
                + prompt.normalizedText.dropFirst(),
            prompt.normalizedText.uppercased(with: locale),
        ]
        if AppleHandwritingOfEvidencePolicy.applies(to: prompt) {
            candidates.append(
                prompt.normalizedText.prefix(1)
                    + prompt.normalizedText.dropFirst().uppercased(with: locale)
            )
        }
        var seen = Set<String>()
        return candidates.filter { seen.insert($0).inserted }
    }
}

struct AppleHandwritingRecognitionResultResolver: Sendable {
    private let decisionPolicy: AppleRecognitionDecisionPolicy

    init(thresholds: AppleRecognitionThresholds) {
        self.decisionPolicy = AppleRecognitionDecisionPolicy(
            thresholds: thresholds
        )
    }

    func resolve(
        fragments: [AppleRecognizedTextFragment],
        target: WordPrompt
    ) -> RecognitionResult {
        guard
            let transcript = AppleHandwritingTranscriptResolver.resolve(
                fragments,
                matching: target.normalizedText
            )
        else {
            return decisionPolicy.evaluate(
                transcript: nil,
                confidence: nil,
                target: target
            )
        }
        return decisionPolicy.evaluate(
            transcript: transcript.letterSequence,
            confidence: transcript.confidence,
            target: target
        )
    }

    func resolve(
        transcript: String?,
        confidence: RecognitionConfidence?,
        target: WordPrompt
    ) -> RecognitionResult {
        decisionPolicy.evaluate(
            transcript: transcript,
            confidence: confidence,
            target: target
        )
    }

    func technicalFailure(_ reason: TechnicalFailureReason) -> RecognitionResult {
        decisionPolicy.technicalFailure(reason)
    }
}

struct HandwritingSampleRenderer: Sendable {
    let configuration: AppleHandwritingRecognitionConfiguration

    func render(_ sample: HandwritingSample) throws -> CGImage {
        let strokes = sample.strokes.filter { !$0.points.isEmpty }
        guard !strokes.isEmpty else {
            throw HandwritingRenderingError.emptySample
        }

        let allPoints = strokes.flatMap(\.points).map(\.location)
        guard let bounds = NormalizedInkBounds(points: allPoints) else {
            throw HandwritingRenderingError.emptySample
        }

        let colorSpace = CGColorSpaceCreateDeviceGray()
        guard
            let context = CGContext(
                data: nil,
                width: configuration.canvasWidth,
                height: configuration.canvasHeight,
                bitsPerComponent: 8,
                bytesPerRow: 0,
                space: colorSpace,
                bitmapInfo: CGImageAlphaInfo.none.rawValue
            )
        else {
            throw HandwritingRenderingError.cannotCreateContext
        }

        let canvas = CGRect(
            x: 0,
            y: 0,
            width: configuration.canvasWidth,
            height: configuration.canvasHeight
        )
        context.setFillColor(gray: 1, alpha: 1)
        context.fill(canvas)
        context.setStrokeColor(gray: 0, alpha: 1)
        context.setFillColor(gray: 0, alpha: 1)
        context.setLineCap(.round)
        context.setLineJoin(.round)
        context.setLineWidth(configuration.lineWidth)
        context.setShouldAntialias(true)

        let transform = InkToCanvasTransform(
            bounds: bounds,
            canvasSize: canvas.size,
            padding: configuration.canvasPadding
        )
        for stroke in strokes {
            let points = stroke.points.map {
                transform.canvasPoint(for: $0.location)
            }
            guard let first = points.first else { continue }

            if points.count == 1 {
                let radius = configuration.lineWidth / 2
                context.fillEllipse(
                    in: CGRect(
                        x: first.x - radius,
                        y: first.y - radius,
                        width: radius * 2,
                        height: radius * 2
                    )
                )
                continue
            }

            context.beginPath()
            context.move(to: first)
            points.dropFirst().forEach(context.addLine(to:))
            context.strokePath()
        }

        guard let image = context.makeImage() else {
            throw HandwritingRenderingError.cannotCreateImage
        }
        return image
    }
}

private struct NormalizedInkBounds: Sendable {
    let minimumX: CGFloat
    let minimumY: CGFloat
    let width: CGFloat
    let height: CGFloat

    init?(points: [TadaWordsDomain.NormalizedPoint]) {
        guard !points.isEmpty else { return nil }

        let xs = points.map { CGFloat($0.x) }
        let ys = points.map { CGFloat($0.y) }
        guard let minimumX = xs.min(),
            let maximumX = xs.max(),
            let minimumY = ys.min(),
            let maximumY = ys.max()
        else {
            return nil
        }

        let centerX = (minimumX + maximumX) / 2
        let centerY = (minimumY + maximumY) / 2
        let width = max(maximumX - minimumX, 0.04)
        let height = max(maximumY - minimumY, 0.04)

        self.minimumX = centerX - (width / 2)
        self.minimumY = centerY - (height / 2)
        self.width = width
        self.height = height
    }
}

private struct InkToCanvasTransform: Sendable {
    private let bounds: NormalizedInkBounds
    private let scale: CGFloat
    private let horizontalOffset: CGFloat
    private let verticalOffset: CGFloat
    private let canvasHeight: CGFloat

    init(
        bounds: NormalizedInkBounds,
        canvasSize: CGSize,
        padding: CGFloat
    ) {
        self.bounds = bounds
        let safePadding = min(
            max(0, padding),
            min(canvasSize.width, canvasSize.height) * 0.4
        )
        let availableWidth = max(1, canvasSize.width - (safePadding * 2))
        let availableHeight = max(1, canvasSize.height - (safePadding * 2))
        let scale = min(
            availableWidth / bounds.width,
            availableHeight / bounds.height
        )
        let renderedWidth = bounds.width * scale
        let renderedHeight = bounds.height * scale

        self.scale = scale
        self.horizontalOffset = (canvasSize.width - renderedWidth) / 2
        self.verticalOffset = (canvasSize.height - renderedHeight) / 2
        self.canvasHeight = canvasSize.height
    }

    func canvasPoint(for point: TadaWordsDomain.NormalizedPoint) -> CGPoint {
        let x = horizontalOffset + ((CGFloat(point.x) - bounds.minimumX) * scale)
        let yFromTop =
            verticalOffset
            + ((CGFloat(point.y) - bounds.minimumY) * scale)
        return CGPoint(x: x, y: canvasHeight - yFromTop)
    }
}

enum HandwritingRenderingError: Error {
    case emptySample
    case cannotCreateContext
    case cannotCreateImage
}
