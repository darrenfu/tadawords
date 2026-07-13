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
    private let decisionPolicy: AppleRecognitionDecisionPolicy

    public init(
        configuration: AppleHandwritingRecognitionConfiguration = .default
    ) {
        self.configuration = configuration
        self.renderer = HandwritingSampleRenderer(configuration: configuration)
        self.decisionPolicy = AppleRecognitionDecisionPolicy(
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
            return decisionPolicy.technicalFailure(.corruptedInput)
        }

        do {
            var request = RecognizeTextRequest()
            request.recognitionLevel = .accurate
            request.recognitionLanguages = [Locale.Language(identifier: "en-US")]
            request.automaticallyDetectsLanguage = false
            request.usesLanguageCorrection = false
            request.customWords = []
            request.minimumTextHeightFraction =
                configuration.minimumTextHeightFraction

            let observations = try await request.perform(on: image, orientation: .up)
            try Task.checkCancellation()

            let fragments = observations.compactMap(
                AppleRecognizedTextFragment.init(observation:)
            )
            guard let transcript = AppleHandwritingTranscriptResolver.resolve(fragments) else {
                return decisionPolicy.evaluate(
                    transcript: nil,
                    confidence: nil,
                    target: prompt
                )
            }

            return decisionPolicy.evaluate(
                transcript: transcript.letterSequence,
                confidence: transcript.confidence,
                target: prompt
            )
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            return decisionPolicy.technicalFailure(.serviceUnavailable)
        }
    }
}

struct AppleRecognizedTextFragment: Equatable, Sendable {
    let text: String
    let confidence: RecognitionConfidence
    let minimumX: CGFloat
    let verticalCenter: CGFloat

    init(
        text: String,
        confidence: RecognitionConfidence,
        minimumX: CGFloat,
        verticalCenter: CGFloat
    ) {
        self.text = text
        self.confidence = confidence
        self.minimumX = minimumX
        self.verticalCenter = verticalCenter
    }

    init?(observation: RecognizedTextObservation) {
        guard let candidate = observation.topCandidates(1).first else {
            return nil
        }

        let points = [
            observation.topLeft,
            observation.topRight,
            observation.bottomRight,
            observation.bottomLeft,
        ]
        self.init(
            text: candidate.string,
            confidence: RecognitionConfidence(Double(candidate.confidence)),
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
        _ fragments: [AppleRecognizedTextFragment]
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
