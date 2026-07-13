import Foundation

/// A local image-to-text boundary used by grown-up word import.
///
/// Implementations return text fragments exactly as recognized. Parsing,
/// English-word validation, and de-duplication stay in the Content layer.
public protocol ImageTextRecognizing: Sendable {
    func recognizeText(in imageData: Data) async throws -> [String]
}

public enum ImageTextRecognitionError: Error, Equatable, Sendable {
    case unavailable
    case invalidImage
    case noTextFound
}

public struct NoImageTextRecognitionService: ImageTextRecognizing, Sendable {
    public init() {}

    public func recognizeText(in imageData: Data) async throws -> [String] {
        _ = imageData
        throw ImageTextRecognitionError.unavailable
    }
}
