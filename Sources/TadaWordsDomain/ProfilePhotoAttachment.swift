import CryptoKit
import Foundation

/// Privacy and transport limits for a parent-selected Profile photo.
///
/// The original camera/library image is never synchronized. UI adapters first
/// resize and encode a prepared JPEG that satisfies this policy; CloudKit
/// adapters then validate the bytes again before replacing an existing avatar.
public enum ProfilePhotoAttachmentPolicy {
    public static let maximumPixelDimension = 512
    public static let maximumByteCount = 256 * 1_024
    public static let contentType = "image/jpeg"
}

public enum ProfilePhotoAttachmentValidationError: Error, Equatable, Sendable {
    case emptyData
    case exceedsMaximumByteCount(actual: Int, maximum: Int)
    case invalidJPEG
    case invalidPixelDimensions(width: Int, height: Int)
    case exceedsMaximumPixelDimension(
        width: Int,
        height: Int,
        maximum: Int
    )
    case byteCountMismatch(expected: Int, actual: Int)
    case checksumMismatch
}

/// Metadata stored beside a CloudKit `CKAsset`. It deliberately includes the
/// Profile owner so an asset routed from another zone/profile cannot be
/// attached accidentally.
public struct ProfilePhotoAttachmentMetadata: Codable, Hashable, Sendable {
    public let profileID: ProfileID
    public let source: ProfileAvatar.PhotoSource
    public let contentType: String
    public let pixelWidth: Int
    public let pixelHeight: Int
    public let byteCount: Int
    public let checksum: String

    public init(
        profileID: ProfileID,
        source: ProfileAvatar.PhotoSource,
        contentType: String = ProfilePhotoAttachmentPolicy.contentType,
        pixelWidth: Int,
        pixelHeight: Int,
        byteCount: Int,
        checksum: String
    ) {
        self.profileID = profileID
        self.source = source
        self.contentType = contentType
        self.pixelWidth = pixelWidth
        self.pixelHeight = pixelHeight
        self.byteCount = byteCount
        self.checksum = checksum.lowercased()
    }

    public var stableAssetID: String {
        "profile-photo-\(profileID)-\(checksum)"
    }
}

public struct ProfilePhotoAttachment: Equatable, Sendable {
    public let metadata: ProfilePhotoAttachmentMetadata
    public let jpegData: Data

    /// Creates trusted metadata after an image adapter has inspected the actual
    /// decoded pixel dimensions.
    public init(
        profileID: ProfileID,
        source: ProfileAvatar.PhotoSource,
        pixelWidth: Int,
        pixelHeight: Int,
        jpegData: Data
    ) throws {
        let checksum = Self.checksum(for: jpegData)
        let metadata = ProfilePhotoAttachmentMetadata(
            profileID: profileID,
            source: source,
            pixelWidth: pixelWidth,
            pixelHeight: pixelHeight,
            byteCount: jpegData.count,
            checksum: checksum
        )
        try self.init(validating: metadata, jpegData: jpegData)
    }

    /// Revalidates untrusted metadata and bytes received from CloudKit.
    public init(
        validating metadata: ProfilePhotoAttachmentMetadata,
        jpegData: Data
    ) throws {
        guard !jpegData.isEmpty else {
            throw ProfilePhotoAttachmentValidationError.emptyData
        }
        guard jpegData.count <= ProfilePhotoAttachmentPolicy.maximumByteCount else {
            throw ProfilePhotoAttachmentValidationError.exceedsMaximumByteCount(
                actual: jpegData.count,
                maximum: ProfilePhotoAttachmentPolicy.maximumByteCount
            )
        }
        guard jpegData.count >= 4,
            jpegData[jpegData.startIndex] == 0xFF,
            jpegData[jpegData.index(after: jpegData.startIndex)] == 0xD8,
            jpegData[jpegData.index(jpegData.endIndex, offsetBy: -2)] == 0xFF,
            jpegData[jpegData.index(before: jpegData.endIndex)] == 0xD9,
            metadata.contentType == ProfilePhotoAttachmentPolicy.contentType
        else {
            throw ProfilePhotoAttachmentValidationError.invalidJPEG
        }
        guard metadata.pixelWidth > 0, metadata.pixelHeight > 0 else {
            throw ProfilePhotoAttachmentValidationError.invalidPixelDimensions(
                width: metadata.pixelWidth,
                height: metadata.pixelHeight
            )
        }
        guard
            metadata.pixelWidth
                <= ProfilePhotoAttachmentPolicy.maximumPixelDimension,
            metadata.pixelHeight
                <= ProfilePhotoAttachmentPolicy.maximumPixelDimension
        else {
            throw
                ProfilePhotoAttachmentValidationError
                .exceedsMaximumPixelDimension(
                    width: metadata.pixelWidth,
                    height: metadata.pixelHeight,
                    maximum: ProfilePhotoAttachmentPolicy.maximumPixelDimension
                )
        }
        guard metadata.byteCount == jpegData.count else {
            throw ProfilePhotoAttachmentValidationError.byteCountMismatch(
                expected: metadata.byteCount,
                actual: jpegData.count
            )
        }
        guard metadata.checksum == Self.checksum(for: jpegData) else {
            throw ProfilePhotoAttachmentValidationError.checksumMismatch
        }

        self.metadata = metadata
        self.jpegData = jpegData
    }

    public static func checksum(for data: Data) -> String {
        SHA256.hash(data: data)
            .map { String(format: "%02x", $0) }
            .joined()
    }
}

extension ProfileAvatar {
    public static func preparedPhoto(
        _ attachment: ProfilePhotoAttachment
    ) -> ProfileAvatar {
        .embeddedPhoto(
            data: attachment.jpegData,
            source: attachment.metadata.source
        )
    }
}
