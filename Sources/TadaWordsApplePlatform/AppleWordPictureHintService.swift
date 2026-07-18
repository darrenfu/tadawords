@preconcurrency import Foundation
import ImageIO
import TadaWordsDomain

/// Resolves the deliberately small picture-hint catalog from the app bundle.
/// Missing, corrupt, or unexpectedly large artwork fails closed because a
/// picture is optional assistance and must never block a practice quest.
public actor AppleWordPictureHintService: WordPictureHintProviding {
    static let attribution =
        "Twemoji graphics by X Corp. and contributors, licensed CC-BY 4.0."
    static let maximumAssetSize = 128 * 1_024

    private static let productionRelativePath =
        "PictureHints/Twemoji-17.0.3"

    private let resourceRoot: URL?

    public init() {
        resourceRoot = Self.productionResourceRoot()
    }

    static func productionResourceRoot() -> URL? {
        Bundle.module.resourceURL?.appendingPathComponent(
            Self.productionRelativePath,
            isDirectory: true
        )
    }

    init(resourceRoot: URL?) {
        self.resourceRoot = resourceRoot
    }

    public func hint(for rawWord: String) async -> WordPictureHintAsset? {
        guard
            let descriptor = WordPictureHintCatalog.descriptor(for: rawWord),
            let resourceRoot
        else {
            return nil
        }

        let fileURL =
            resourceRoot
            .appendingPathComponent(descriptor.assetCode)
            .appendingPathExtension("png")
        guard
            let data = try? Data(contentsOf: fileURL, options: .mappedIfSafe),
            Self.isAcceptedAsset(data)
        else {
            return nil
        }

        return WordPictureHintAsset(
            imageData: data,
            accessibilityLabel: descriptor.accessibilityLabel,
            attribution: Self.attribution
        )
    }

    static func isAcceptedAsset(_ data: Data) -> Bool {
        guard data.count <= maximumAssetSize, isPNG(data) else {
            return false
        }
        guard
            let source = CGImageSourceCreateWithData(data as CFData, nil),
            CGImageSourceGetCount(source) == 1,
            CGImageSourceCreateImageAtIndex(source, 0, nil) != nil
        else {
            return false
        }
        return true
    }

    private static func isPNG(_ data: Data) -> Bool {
        let signature: [UInt8] = [0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A]
        return data.count >= signature.count
            && Array(data.prefix(signature.count)) == signature
    }
}
