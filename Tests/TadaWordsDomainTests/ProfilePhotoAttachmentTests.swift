import Foundation
import TadaWordsDomain
import XCTest

final class ProfilePhotoAttachmentTests: XCTestCase {
    private let profileID = ProfileID(
        rawValue: UUID(uuidString: "81000000-0000-0000-0000-000000000001")!
    )

    func testPreparedJPEGCarriesBoundedVerifiableMetadata() throws {
        let data = jpeg(payloadByteCount: 32)
        let attachment = try ProfilePhotoAttachment(
            profileID: profileID,
            source: .photoLibrary,
            pixelWidth: 512,
            pixelHeight: 384,
            jpegData: data
        )

        XCTAssertEqual(attachment.metadata.profileID, profileID)
        XCTAssertEqual(attachment.metadata.contentType, "image/jpeg")
        XCTAssertEqual(attachment.metadata.byteCount, data.count)
        XCTAssertEqual(
            attachment.metadata.checksum,
            ProfilePhotoAttachment.checksum(for: data)
        )
        XCTAssertEqual(
            ProfileAvatar.preparedPhoto(attachment).embeddedPhotoData,
            data
        )
    }

    func testOversizedBytesAreRejectedBeforeTransport() {
        let data = jpeg(
            payloadByteCount:
                ProfilePhotoAttachmentPolicy.maximumByteCount
                + 1
        )

        XCTAssertThrowsError(
            try ProfilePhotoAttachment(
                profileID: profileID,
                source: .camera,
                pixelWidth: 512,
                pixelHeight: 512,
                jpegData: data
            )
        ) { error in
            guard
                case .exceedsMaximumByteCount =
                    error as? ProfilePhotoAttachmentValidationError
            else { return XCTFail("Unexpected error: \(error)") }
        }
    }

    func testIncomingChecksumAndByteCountMustMatchAsset() throws {
        let original = jpeg(payloadByteCount: 12)
        let attachment = try ProfilePhotoAttachment(
            profileID: profileID,
            source: .camera,
            pixelWidth: 100,
            pixelHeight: 80,
            jpegData: original
        )
        let changed = jpeg(payloadByteCount: 13)

        XCTAssertThrowsError(
            try ProfilePhotoAttachment(
                validating: attachment.metadata,
                jpegData: changed
            )
        ) { error in
            guard
                case .byteCountMismatch =
                    error as? ProfilePhotoAttachmentValidationError
            else { return XCTFail("Unexpected error: \(error)") }
        }

        let wrongChecksum = ProfilePhotoAttachmentMetadata(
            profileID: profileID,
            source: .camera,
            pixelWidth: 100,
            pixelHeight: 80,
            byteCount: original.count,
            checksum: String(repeating: "0", count: 64)
        )
        XCTAssertThrowsError(
            try ProfilePhotoAttachment(
                validating: wrongChecksum,
                jpegData: original
            )
        ) { error in
            XCTAssertEqual(
                error as? ProfilePhotoAttachmentValidationError,
                .checksumMismatch
            )
        }
    }

    func testInvalidJPEGAndPixelDimensionsAreRejected() {
        XCTAssertThrowsError(
            try ProfilePhotoAttachment(
                profileID: profileID,
                source: .camera,
                pixelWidth: 32,
                pixelHeight: 32,
                jpegData: Data([0, 1, 2, 3])
            )
        ) { error in
            XCTAssertEqual(
                error as? ProfilePhotoAttachmentValidationError,
                .invalidJPEG
            )
        }

        XCTAssertThrowsError(
            try ProfilePhotoAttachment(
                profileID: profileID,
                source: .camera,
                pixelWidth: 513,
                pixelHeight: 1,
                jpegData: jpeg(payloadByteCount: 8)
            )
        ) { error in
            guard
                case .exceedsMaximumPixelDimension =
                    error as? ProfilePhotoAttachmentValidationError
            else { return XCTFail("Unexpected error: \(error)") }
        }
    }

    private func jpeg(payloadByteCount: Int) -> Data {
        Data([0xFF, 0xD8])
            + Data(repeating: 0x2A, count: payloadByteCount)
            + Data([0xFF, 0xD9])
    }
}
