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
    private let rasterPassConfigurations: [AppleHandwritingRecognitionConfiguration]
    private let visionRecognizer: AppleHandwritingVisionRecognizer
    private let resultResolver: AppleHandwritingRecognitionResultResolver

    public init(
        configuration: AppleHandwritingRecognitionConfiguration = .default
    ) {
        self.rasterPassConfigurations =
            AppleHandwritingRasterPassPolicy.configurations(
                startingWith: configuration
            )
        self.visionRecognizer = AppleHandwritingVisionRecognizer()
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

        let images: [CGImage]
        do {
            images = try rasterPassConfigurations.map {
                try HandwritingSampleRenderer(configuration: $0).render(sample)
            }
        } catch {
            return resultResolver.technicalFailure(.corruptedInput)
        }

        do {
            var firstResult: RecognitionResult?
            for (image, passConfiguration) in zip(
                images,
                rasterPassConfigurations
            ) {
                let fragments = try await visionRecognizer.recognize(
                    image: image,
                    prompt: prompt,
                    minimumTextHeightFraction:
                        passConfiguration.minimumTextHeightFraction
                )
                try Task.checkCancellation()

                let result = resultResolver.resolve(
                    fragments: fragments,
                    target: prompt
                )
                if result.decision == .matched {
                    return result
                }
                if firstResult == nil {
                    firstResult = result
                }
            }
            return firstResult
                ?? resultResolver.resolve(fragments: [], target: prompt)
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            return resultResolver.technicalFailure(.serviceUnavailable)
        }
    }
}

enum AppleHandwritingRasterPassPolicy {
    /// One alternate raster is enough to recover thin, short lowercase words
    /// that produce no Vision observation at the primary operating point. The
    /// passes never vote or fuzzy-match: either pass must independently produce
    /// the complete target spelling.
    static func configurations(
        startingWith primary: AppleHandwritingRecognitionConfiguration
    ) -> [AppleHandwritingRecognitionConfiguration] {
        let fallbackLineWidth = max(Self.fallbackLineWidth, primary.lineWidth)
        if fallbackLineWidth != primary.lineWidth {
            return [
                primary,
                configuration(primary, lineWidth: fallbackLineWidth),
            ]
        }
        guard primary.canvasPadding != fallbackCanvasPadding else { return [primary] }
        return [
            primary,
            configuration(primary, canvasPadding: fallbackCanvasPadding),
        ]
    }

    private static let fallbackLineWidth: CGFloat = 36
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
    func recognize(
        image: CGImage,
        prompt: WordPrompt,
        minimumTextHeightFraction: Float
    ) async throws -> [AppleRecognizedTextFragment] {
        var request = RecognizeTextRequest()
        request.recognitionLevel = .accurate
        request.recognitionLanguages = [Locale.Language(identifier: "en-US")]
        request.automaticallyDetectsLanguage = false
        request.usesLanguageCorrection = true
        request.customWords = AppleHandwritingRecognitionVocabulary.words(
            for: prompt
        )
        request.minimumTextHeightFraction = minimumTextHeightFraction

        return try await request.perform(on: image, orientation: .up).compactMap(
            AppleRecognizedTextFragment.init(observation:)
        )
    }
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

    init?(observation: RecognizedTextObservation) {
        let candidates = observation.topCandidates(5).map {
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
        let candidates = [
            prompt.normalizedText,
            prompt.normalizedText.prefix(1).uppercased(with: locale)
                + prompt.normalizedText.dropFirst(),
            prompt.normalizedText.uppercased(with: locale),
        ]
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
