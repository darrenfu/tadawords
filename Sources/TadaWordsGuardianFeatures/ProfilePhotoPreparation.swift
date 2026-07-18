import Foundation
import ImageIO
import TadaWordsDomain
import UniformTypeIdentifiers

/// Converts camera/library input to the only photo representation the Profile
/// repository accepts for sync. Pixel dimensions and encoded byte size are
/// both hard limits, not best-effort quality hints.
enum ProfilePhotoPreparation {
    static func prepare(_ data: Data) -> Data? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil) else {
            return nil
        }
        var maximumDimension = ProfilePhotoAttachmentPolicy.maximumPixelDimension
        let qualities: [Double] = [0.82, 0.72, 0.62, 0.52, 0.42, 0.34]

        while maximumDimension >= 96 {
            let thumbnailOptions: CFDictionary =
                [
                    kCGImageSourceCreateThumbnailFromImageAlways: true,
                    kCGImageSourceCreateThumbnailWithTransform: true,
                    kCGImageSourceThumbnailMaxPixelSize: maximumDimension,
                    kCGImageSourceShouldCacheImmediately: true,
                ] as CFDictionary
            guard
                let image = CGImageSourceCreateThumbnailAtIndex(
                    source,
                    0,
                    thumbnailOptions
                )
            else { return nil }

            for quality in qualities {
                let encoded = NSMutableData()
                guard
                    let destination = CGImageDestinationCreateWithData(
                        encoded,
                        UTType.jpeg.identifier as CFString,
                        1,
                        nil
                    )
                else { return nil }
                CGImageDestinationAddImage(
                    destination,
                    image,
                    [kCGImageDestinationLossyCompressionQuality: quality]
                        as CFDictionary
                )
                guard CGImageDestinationFinalize(destination) else { continue }
                let jpeg = encoded as Data
                if jpeg.count
                    <= ProfilePhotoAttachmentPolicy.maximumByteCount
                {
                    return jpeg
                }
            }
            maximumDimension = Int(floor(Double(maximumDimension) * 0.8))
        }
        return nil
    }
}
