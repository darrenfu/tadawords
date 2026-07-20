@preconcurrency import CloudKit
import Foundation
import ImageIO
import TadaWordsDomain
import UniformTypeIdentifiers

enum CloudKitProfilePhotoAssetError: Error, Equatable {
    case invalidProfilePayload
    case invalidJPEG
    case metadataMismatch
    case profileMismatch
    case missingAsset
    case sourcePersistenceFailed
    case originalPayloadMismatch
}

struct CloudKitStagedProfilePhotoAsset {
    let wireRecord: FamilySyncRecord
    let metadata: ProfilePhotoAttachmentMetadata
    let sourceURL: URL
}

/// Converts the local embedded avatar representation to a CloudKit CKAsset and
/// back. The wire envelope contains only a bounded reference, never JPEG/base64
/// bytes. Incoming bytes are rehydrated before the durable inbox append, so a
/// process crash after the callback can replay the complete local record.
enum CloudKitProfilePhotoAssetCodec {
    enum Schema {
        static let asset = "profilePhotoAsset"
        static let metadata = "profilePhotoMetadata"
        static let originalPayloadChecksum = "profilePhotoPayloadChecksum"
        static let originalPayloadSize = "profilePhotoPayloadSize"
    }

    /// Upgrades every Profile accepted by the current writer to the reviewed
    /// wire DTO before the envelope or CKAsset metadata is created. This also
    /// migrates legacy durable-outbox bytes and recalculates checksum/size, so
    /// a current outbound CloudKit record can never retain voiceprint state.
    static func canonicalizedForCurrentWriter(
        _ record: FamilySyncRecord
    ) throws -> FamilySyncRecord {
        guard record.kind == .profile else { return record }
        let payload: FamilySyncProfilePayload
        do {
            payload = try decoder().decode(
                FamilySyncProfilePayload.self,
                from: record.payload
            )
        } catch {
            throw CloudKitProfilePhotoAssetError.invalidProfilePayload
        }
        let encoded: Data
        do {
            encoded = try encoder().encode(payload)
        } catch {
            throw CloudKitProfilePhotoAssetError.invalidProfilePayload
        }
        return FamilySyncRecord(
            recordName: record.recordName,
            profileID: record.profileID,
            kind: record.kind,
            payload: encoded,
            updatedAt: record.updatedAt,
            deviceID: record.deviceID,
            isDeleted: record.isDeleted,
            schemaVersion: record.schemaVersion,
            minimumReadableVersion: record.minimumReadableVersion,
            logicalRevision: record.logicalRevision
        )
    }

    static func stageIfNeeded(
        _ record: FamilySyncRecord,
        sourceDirectory: URL,
        fileManager: FileManager = .default
    ) throws -> CloudKitStagedProfilePhotoAsset? {
        guard record.kind == .profile,
            let payload = try? decoder().decode(
                FamilySyncProfilePayload.self,
                from: record.payload
            ),
            case .photo(_, let source) = payload.avatar,
            let jpegData = payload.avatar.embeddedPhotoData
        else { return nil }

        let dimensions = try decodedJPEGDimensions(jpegData)
        let attachment = try ProfilePhotoAttachment(
            profileID: record.profileID,
            source: source,
            pixelWidth: dimensions.width,
            pixelHeight: dimensions.height,
            jpegData: jpegData
        )
        let sourceURL = try persistSource(
            attachment,
            directory: sourceDirectory,
            fileManager: fileManager
        )
        let wirePayload: Data
        do {
            let wireAvatar = ProfileAvatar.photo(
                assetID: attachment.metadata.stableAssetID,
                source: source
            )
            wirePayload = try encoder().encode(
                payload.replacingAvatar(wireAvatar)
            )
        } catch {
            throw CloudKitProfilePhotoAssetError.invalidProfilePayload
        }
        let wireRecord = FamilySyncRecord(
            recordName: record.recordName,
            profileID: record.profileID,
            kind: record.kind,
            payload: wirePayload,
            updatedAt: record.updatedAt,
            deviceID: record.deviceID,
            isDeleted: record.isDeleted,
            schemaVersion: record.schemaVersion,
            minimumReadableVersion: record.minimumReadableVersion,
            logicalRevision: record.logicalRevision
        )
        return CloudKitStagedProfilePhotoAsset(
            wireRecord: wireRecord,
            metadata: attachment.metadata,
            sourceURL: sourceURL
        )
    }

    static func attach(
        _ staged: CloudKitStagedProfilePhotoAsset,
        originalRecord: FamilySyncRecord,
        to cloudRecord: CKRecord
    ) throws {
        let metadataData: Data
        do {
            metadataData = try encoder().encode(staged.metadata)
        } catch {
            throw CloudKitProfilePhotoAssetError.metadataMismatch
        }
        cloudRecord[Schema.asset] = CKAsset(fileURL: staged.sourceURL)
        cloudRecord[Schema.metadata] = metadataData as NSData
        cloudRecord[Schema.originalPayloadChecksum] =
            originalRecord.payloadChecksum as NSString
        cloudRecord[Schema.originalPayloadSize] = NSNumber(
            value: originalRecord.payloadSize
        )
    }

    static func restoringIfNeeded(
        wireRecord: FamilySyncRecord,
        cloudRecord: CKRecord
    ) throws -> FamilySyncRecord {
        let hasAssetFields =
            cloudRecord[Schema.asset] != nil
            || cloudRecord[Schema.metadata] != nil
            || cloudRecord[Schema.originalPayloadChecksum] != nil
            || cloudRecord[Schema.originalPayloadSize] != nil
        guard hasAssetFields else {
            // Legacy profile envelopes may still contain their prepared image.
            return wireRecord
        }
        guard wireRecord.kind == .profile,
            let asset = cloudRecord[Schema.asset] as? CKAsset,
            let assetURL = asset.fileURL,
            let metadataData = cloudRecord[Schema.metadata] as? Data,
            let expectedPayloadChecksum = cloudRecord[
                Schema.originalPayloadChecksum
            ] as? String,
            let expectedPayloadSize = cloudRecord[
                Schema.originalPayloadSize
            ] as? NSNumber
        else { throw CloudKitProfilePhotoAssetError.missingAsset }

        let metadata: ProfilePhotoAttachmentMetadata
        let wireProfile: FamilySyncProfilePayload
        do {
            metadata = try decoder().decode(
                ProfilePhotoAttachmentMetadata.self,
                from: metadataData
            )
            wireProfile = try decoder().decode(
                FamilySyncProfilePayload.self,
                from: wireRecord.payload
            )
        } catch {
            throw CloudKitProfilePhotoAssetError.invalidProfilePayload
        }
        guard metadata.profileID == wireRecord.profileID,
            wireProfile.id == wireRecord.profileID
        else { throw CloudKitProfilePhotoAssetError.profileMismatch }
        guard case .photo(let assetID, let source) = wireProfile.avatar,
            assetID == metadata.stableAssetID,
            source == metadata.source
        else { throw CloudKitProfilePhotoAssetError.metadataMismatch }

        let jpegData: Data
        do {
            jpegData = try Data(contentsOf: assetURL, options: .mappedIfSafe)
        } catch {
            throw CloudKitProfilePhotoAssetError.missingAsset
        }
        let actualDimensions = try decodedJPEGDimensions(jpegData)
        guard actualDimensions.width == metadata.pixelWidth,
            actualDimensions.height == metadata.pixelHeight
        else { throw CloudKitProfilePhotoAssetError.metadataMismatch }
        let attachment = try ProfilePhotoAttachment(
            validating: metadata,
            jpegData: jpegData
        )
        let localPayload: Data
        do {
            let localAvatar = ProfileAvatar.preparedPhoto(attachment)
            if containsLegacyVoiceprintField(wireRecord.payload) {
                let legacy = try decoder().decode(
                    KidProfile.self,
                    from: wireRecord.payload
                )
                localPayload = try encoder().encode(
                    replacingAvatar(of: legacy, with: localAvatar)
                )
            } else {
                localPayload = try encoder().encode(
                    wireProfile.replacingAvatar(localAvatar)
                )
            }
        } catch {
            throw CloudKitProfilePhotoAssetError.invalidProfilePayload
        }
        guard localPayload.count == expectedPayloadSize.intValue,
            FamilySyncRecord.checksum(for: localPayload)
                == expectedPayloadChecksum
        else { throw CloudKitProfilePhotoAssetError.originalPayloadMismatch }

        let restored = FamilySyncRecord(
            recordName: wireRecord.recordName,
            profileID: wireRecord.profileID,
            kind: wireRecord.kind,
            payload: localPayload,
            updatedAt: wireRecord.updatedAt,
            deviceID: wireRecord.deviceID,
            isDeleted: wireRecord.isDeleted,
            schemaVersion: wireRecord.schemaVersion,
            minimumReadableVersion: wireRecord.minimumReadableVersion,
            logicalRevision: wireRecord.logicalRevision,
            payloadChecksum: expectedPayloadChecksum,
            payloadSize: expectedPayloadSize.intValue
        )
        try restored.validateCompatibility()
        return restored
    }

    static func removeAbandonedSources(
        in directory: URL,
        fileManager: FileManager = .default
    ) throws {
        guard fileManager.fileExists(atPath: directory.path) else { return }
        for url in try fileManager.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: nil
        )
        where url.lastPathComponent.hasPrefix("profile-photo-")
            || url.lastPathComponent.hasPrefix(".profile-photo-")
        {
            try fileManager.removeItem(at: url)
        }
    }

    static func removeSources(
        for profileID: ProfileID,
        in directory: URL,
        fileManager: FileManager = .default
    ) throws {
        guard fileManager.fileExists(atPath: directory.path) else { return }
        let profilePrefixes = [
            "profile-photo-\(profileID)-",
            ".profile-photo-\(profileID)-",
        ]
        for url in try fileManager.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: nil
        )
        where profilePrefixes.contains(where: {
            url.lastPathComponent.hasPrefix($0)
        }) {
            try fileManager.removeItem(at: url)
        }
    }

    static func removeSource(
        at url: URL?,
        fileManager: FileManager = .default
    ) {
        guard let url else { return }
        try? fileManager.removeItem(at: url)
    }

    private static func persistSource(
        _ attachment: ProfilePhotoAttachment,
        directory: URL,
        fileManager: FileManager
    ) throws -> URL {
        do {
            try fileManager.createDirectory(
                at: directory,
                withIntermediateDirectories: true
            )
            let sourceURL = directory.appendingPathComponent(
                attachment.metadata.stableAssetID + ".jpg",
                isDirectory: false
            )
            if fileManager.fileExists(atPath: sourceURL.path) {
                let existing = try Data(contentsOf: sourceURL)
                guard existing == attachment.jpegData else {
                    throw CloudKitProfilePhotoAssetError.sourcePersistenceFailed
                }
                return sourceURL
            }
            let temporaryURL = directory.appendingPathComponent(
                ".profile-photo-\(attachment.metadata.profileID)-\(UUID().uuidString).tmp"
            )
            do {
                try attachment.jpegData.write(to: temporaryURL)
                let handle = try FileHandle(forWritingTo: temporaryURL)
                try handle.synchronize()
                try handle.close()
                try fileManager.moveItem(at: temporaryURL, to: sourceURL)
            } catch {
                try? fileManager.removeItem(at: temporaryURL)
                throw error
            }
            return sourceURL
        } catch let error as CloudKitProfilePhotoAssetError {
            throw error
        } catch {
            throw CloudKitProfilePhotoAssetError.sourcePersistenceFailed
        }
    }

    private static func decodedJPEGDimensions(
        _ data: Data
    ) throws -> (width: Int, height: Int) {
        guard
            let source = CGImageSourceCreateWithData(data as CFData, nil),
            CGImageSourceGetType(source) as String? == UTType.jpeg.identifier,
            let properties = CGImageSourceCopyPropertiesAtIndex(
                source,
                0,
                [kCGImageSourceShouldCache: false] as CFDictionary
            ) as? [CFString: Any],
            let width = properties[kCGImagePropertyPixelWidth] as? NSNumber,
            let height = properties[kCGImagePropertyPixelHeight] as? NSNumber,
            width.intValue > 0,
            height.intValue > 0
        else { throw CloudKitProfilePhotoAssetError.invalidJPEG }
        return (width.intValue, height.intValue)
    }

    private static func replacingAvatar(
        of profile: KidProfile,
        with avatar: ProfileAvatar
    ) -> KidProfile {
        KidProfile(
            id: profile.id,
            displayName: profile.displayName,
            avatar: avatar,
            selectedWorld: profile.selectedWorld,
            starterWorld: profile.starterWorld,
            guardianUnlockedWorlds: profile.guardianUnlockedWorlds,
            selectedCartoonIconAssetID: profile.selectedCartoonIconAssetID,
            selectedTreasureAvatar: profile.selectedTreasureAvatar,
            schoolGrade: profile.schoolGrade,
            ageYears: profile.ageYears,
            voiceprintStatus: profile.voiceprintStatus,
            createdAt: profile.createdAt,
            updatedAt: profile.updatedAt
        )
    }

    private static func containsLegacyVoiceprintField(_ payload: Data) -> Bool {
        guard
            let object = try? JSONSerialization.jsonObject(with: payload)
                as? [String: Any]
        else { return false }
        return object.keys.contains("voiceprintStatus")
    }

    private static func encoder() -> JSONEncoder {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .secondsSince1970
        encoder.outputFormatting = [
            .prettyPrinted,
            .sortedKeys,
            .withoutEscapingSlashes,
        ]
        return encoder
    }

    private static func decoder() -> JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .secondsSince1970
        return decoder
    }
}
