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
    private let renderer: HandwritingSampleRenderer
    private let resultResolver: AppleHandwritingRecognitionResultResolver

    public init(
        configuration: AppleHandwritingRecognitionConfiguration = .default
    ) {
        self.configuration = configuration
        self.renderer = HandwritingSampleRenderer(configuration: configuration)
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

        let image: CGImage
        do {
            image = try renderer.render(sample)
        } catch {
            return resultResolver.technicalFailure(.corruptedInput)
        }

        do {
            var request = RecognizeTextRequest()
            request.recognitionLevel = .accurate
            request.recognitionLanguages = [Locale.Language(identifier: "en-US")]
            request.automaticallyDetectsLanguage = false
            request.usesLanguageCorrection = false
            request.customWords = AppleHandwritingRecognitionVocabulary.words(
                for: prompt
            )
            request.minimumTextHeightFraction =
                configuration.minimumTextHeightFraction

            let observations = try await request.perform(on: image, orientation: .up)
            try Task.checkCancellation()

            let fragments = observations.compactMap(
                AppleRecognizedTextFragment.init(observation:)
            )
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
                                candidate.text
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

/// Vision occasionally emits the digit zero for a handwritten lowercase or
/// uppercase O. This is the only glyph substitution allowed here; the final
/// sequence must still equal the complete target exactly, so neighboring words
/// such as `on`, `or`, `ot`, and `off` remain mismatches.
private enum AppleHandwritingCandidateNormalizer {
    static func normalize(_ candidate: String) -> String? {
        let compact = candidate.components(
            separatedBy: .whitespacesAndNewlines
        ).joined()
        if let normalized = try? EnglishWordNormalizer.normalize(compact) {
            return normalized
        }
        guard compact.contains("0") else { return nil }
        return try? EnglishWordNormalizer.normalize(
            compact.replacingOccurrences(of: "0", with: "o")
        )
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
