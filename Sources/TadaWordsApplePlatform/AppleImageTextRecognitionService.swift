import CoreGraphics
import Foundation
import ImageIO
import TadaWordsDomain
import Vision

/// Uses Apple's on-device Vision framework to read printed text from a photo.
/// Image bytes and recognized text never leave the device.
public struct AppleImageTextRecognitionService: ImageTextRecognizing, Sendable {
    public init() {}

    public func recognizeText(in imageData: Data) async throws -> [String] {
        try Task.checkCancellation()
        guard
            let source = CGImageSourceCreateWithData(imageData as CFData, nil),
            let image = CGImageSourceCreateImageAtIndex(source, 0, nil)
        else {
            throw ImageTextRecognitionError.invalidImage
        }

        var request = RecognizeTextRequest()
        request.recognitionLevel = .accurate
        request.recognitionLanguages = [Locale.Language(identifier: "en-US")]
        request.automaticallyDetectsLanguage = false
        request.usesLanguageCorrection = true
        request.minimumTextHeightFraction = 0.012

        do {
            let observations = try await request.perform(
                on: image,
                orientation: Self.orientation(for: source)
            )
            try Task.checkCancellation()
            let fragments = observations.compactMap(
                ApplePrintedTextFragment.init(observation:)
            )
            let text = ApplePrintedTextResolver.resolve(fragments)
            guard !text.isEmpty else {
                throw ImageTextRecognitionError.noTextFound
            }
            return text
        } catch is CancellationError {
            throw CancellationError()
        } catch let error as ImageTextRecognitionError {
            throw error
        } catch {
            throw ImageTextRecognitionError.unavailable
        }
    }

    private static func orientation(
        for source: CGImageSource
    ) -> CGImagePropertyOrientation {
        guard
            let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil)
                as? [CFString: Any],
            let rawValue = properties[kCGImagePropertyOrientation] as? UInt32,
            let orientation = CGImagePropertyOrientation(rawValue: rawValue)
        else {
            return .up
        }
        return orientation
    }
}

struct ApplePrintedTextFragment: Equatable, Sendable {
    let text: String
    let minimumX: CGFloat
    let verticalCenter: CGFloat

    init(text: String, minimumX: CGFloat, verticalCenter: CGFloat) {
        self.text = text
        self.minimumX = minimumX
        self.verticalCenter = verticalCenter
    }

    init?(observation: RecognizedTextObservation) {
        guard let candidate = observation.topCandidates(1).first else { return nil }
        let points = [
            observation.topLeft,
            observation.topRight,
            observation.bottomRight,
            observation.bottomLeft,
        ]
        self.init(
            text: candidate.string,
            minimumX: points.map(\.x).min() ?? 0,
            verticalCenter: points.map(\.y).reduce(0, +) / CGFloat(points.count)
        )
    }
}

enum ApplePrintedTextResolver {
    static func resolve(_ fragments: [ApplePrintedTextFragment]) -> [String] {
        fragments
            .filter { !$0.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
            .sorted { left, right in
                let leftRow = Int((left.verticalCenter * 24).rounded())
                let rightRow = Int((right.verticalCenter * 24).rounded())
                if leftRow != rightRow { return leftRow > rightRow }
                if left.minimumX != right.minimumX {
                    return left.minimumX < right.minimumX
                }
                return left.text < right.text
            }
            .map(\.text)
    }
}
