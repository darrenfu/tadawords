import CoreGraphics
import Foundation
import ImageIO
import TadaWordsDomain
import UniformTypeIdentifiers
import XCTest

@testable import TadaWordsGuardianFeatures

final class ProfilePhotoPreparationTests: XCTestCase {
    func testLargeLibraryImageIsHardCappedByPixelsAndBytes() throws {
        let source = try makePNG(width: 1_600, height: 1_200)
        let prepared = try XCTUnwrap(ProfilePhotoPreparation.prepare(source))

        XCTAssertLessThanOrEqual(
            prepared.count,
            ProfilePhotoAttachmentPolicy.maximumByteCount
        )
        let imageSource = try XCTUnwrap(
            CGImageSourceCreateWithData(prepared as CFData, nil)
        )
        XCTAssertEqual(
            CGImageSourceGetType(imageSource) as String?,
            UTType.jpeg.identifier
        )
        let properties = try XCTUnwrap(
            CGImageSourceCopyPropertiesAtIndex(imageSource, 0, nil)
                as? [CFString: Any]
        )
        let width = try XCTUnwrap(
            properties[kCGImagePropertyPixelWidth] as? NSNumber
        ).intValue
        let height = try XCTUnwrap(
            properties[kCGImagePropertyPixelHeight] as? NSNumber
        ).intValue
        XCTAssertLessThanOrEqual(
            max(width, height),
            ProfilePhotoAttachmentPolicy.maximumPixelDimension
        )
    }

    func testNonImageInputIsRejected() {
        XCTAssertNil(ProfilePhotoPreparation.prepare(Data("not-image".utf8)))
    }

    private func makePNG(width: Int, height: Int) throws -> Data {
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        guard
            let context = CGContext(
                data: nil,
                width: width,
                height: height,
                bitsPerComponent: 8,
                bytesPerRow: width * 4,
                space: colorSpace,
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
            )
        else { throw FixtureError.imageCreation }
        for row in 0..<height {
            let shade = CGFloat(row % 255) / 255
            context.setFillColor(
                CGColor(
                    colorSpace: colorSpace,
                    components: [shade, 0.4, 1 - shade, 1]
                )!
            )
            context.fill(CGRect(x: 0, y: row, width: width, height: 1))
        }
        guard let image = context.makeImage() else {
            throw FixtureError.imageCreation
        }
        let data = NSMutableData()
        guard
            let destination = CGImageDestinationCreateWithData(
                data,
                UTType.png.identifier as CFString,
                1,
                nil
            )
        else { throw FixtureError.imageCreation }
        CGImageDestinationAddImage(destination, image, nil)
        guard CGImageDestinationFinalize(destination) else {
            throw FixtureError.imageCreation
        }
        return data as Data
    }

    private enum FixtureError: Error {
        case imageCreation
    }
}
