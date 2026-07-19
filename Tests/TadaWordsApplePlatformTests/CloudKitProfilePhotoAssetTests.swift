@preconcurrency import CloudKit
import CoreGraphics
import Foundation
import ImageIO
import TadaWordsDomain
import UniformTypeIdentifiers
import XCTest

@testable import TadaWordsApplePlatform

final class CloudKitProfilePhotoAssetTests: XCTestCase {
    func testProductionCloudRecordUsesAssetAndEnvelopeHasNoPhotoBytes()
        throws
    {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let original = try fixture.familyRecord()
        let store = try fixture.configuredStore()
        let cloudRecord = try fixture.productionCloudRecord(
            for: original,
            store: store
        )

        XCTAssertNotNil(
            cloudRecord[CloudKitProfilePhotoAssetCodec.Schema.asset] as? CKAsset
        )
        let envelopeData = try XCTUnwrap(
            cloudRecord[CloudKitFamilyRecordCodec.Schema.envelope] as? Data
        )
        XCTAssertFalse(
            String(decoding: envelopeData, as: UTF8.self)
                .contains(fixture.jpegData.base64EncodedString())
        )
        guard
            case .record(let decoded) =
                CloudKitFamilyRecordCodec.decode(cloudRecord)
        else { return XCTFail("Expected hydrated Profile record") }
        XCTAssertEqual(decoded.payload, original.payload)
        XCTAssertEqual(decoded.payloadChecksum, original.payloadChecksum)
    }

    func testReplacingPhotoWithNonPhotoClearsStaleAssetFields() throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let store = try fixture.configuredStore()
        let photoRecord = try fixture.familyRecord()
        let savedPhoto = try fixture.productionCloudRecord(
            for: photoRecord,
            store: store
        )
        try store.saveSystemFields(for: savedPhoto, scope: .privateDatabase)

        let animalRecord = try fixture.familyRecord(
            avatar: .cartoonAnimal(assetID: "profile-fox"),
            revisionCounter: 5
        )
        let savedAnimal = try fixture.productionCloudRecord(
            for: animalRecord,
            store: store
        )

        XCTAssertNil(savedAnimal[CloudKitProfilePhotoAssetCodec.Schema.asset])
        XCTAssertNil(savedAnimal[CloudKitProfilePhotoAssetCodec.Schema.metadata])
        XCTAssertNil(
            savedAnimal[
                CloudKitProfilePhotoAssetCodec.Schema.originalPayloadChecksum
            ]
        )
        XCTAssertNil(
            savedAnimal[CloudKitProfilePhotoAssetCodec.Schema.originalPayloadSize]
        )
        guard
            case .record(let decoded) =
                CloudKitFamilyRecordCodec.decode(savedAnimal)
        else { return XCTFail("Expected non-photo Profile record") }
        XCTAssertEqual(decoded, animalRecord)
    }

    func testOutgoingPhotoUsesCKAssetAndWirePayloadContainsNoImageBytes()
        throws
    {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let original = try fixture.familyRecord()
        let staged = try XCTUnwrap(
            CloudKitProfilePhotoAssetCodec.stageIfNeeded(
                original,
                sourceDirectory: fixture.sourceDirectory
            )
        )
        let cloudRecord = fixture.cloudRecord()
        try CloudKitProfilePhotoAssetCodec.attach(
            staged,
            originalRecord: original,
            to: cloudRecord
        )

        XCTAssertTrue(FileManager.default.fileExists(atPath: staged.sourceURL.path))
        XCTAssertNotNil(cloudRecord[CloudKitProfilePhotoAssetCodec.Schema.asset] as? CKAsset)
        XCTAssertFalse(staged.wireRecord.payload.contains(fixture.jpegData))
        XCTAssertFalse(
            String(decoding: staged.wireRecord.payload, as: UTF8.self)
                .contains(fixture.jpegData.base64EncodedString())
        )
        let wireProfile = try fixture.decoder.decode(
            KidProfile.self,
            from: staged.wireRecord.payload
        )
        XCTAssertNil(wireProfile.avatar.embeddedPhotoData)
        XCTAssertEqual(
            wireProfile.avatar,
            .photo(
                assetID: staged.metadata.stableAssetID,
                source: .photoLibrary
            )
        )

        let restored = try CloudKitProfilePhotoAssetCodec.restoringIfNeeded(
            wireRecord: staged.wireRecord,
            cloudRecord: cloudRecord
        )
        XCTAssertEqual(restored.payload, original.payload)
        XCTAssertEqual(restored.payloadChecksum, original.payloadChecksum)
        XCTAssertEqual(restored.logicalRevision, original.logicalRevision)
    }

    func testIncomingProfileMetadataMismatchIsRejected() throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let original = try fixture.familyRecord()
        let staged = try XCTUnwrap(
            CloudKitProfilePhotoAssetCodec.stageIfNeeded(
                original,
                sourceDirectory: fixture.sourceDirectory
            )
        )
        let cloudRecord = fixture.cloudRecord()
        try CloudKitProfilePhotoAssetCodec.attach(
            staged,
            originalRecord: original,
            to: cloudRecord
        )
        let wrongMetadata = ProfilePhotoAttachmentMetadata(
            profileID: ProfileID(),
            source: staged.metadata.source,
            pixelWidth: staged.metadata.pixelWidth,
            pixelHeight: staged.metadata.pixelHeight,
            byteCount: staged.metadata.byteCount,
            checksum: staged.metadata.checksum
        )
        cloudRecord[CloudKitProfilePhotoAssetCodec.Schema.metadata] =
            try fixture.encoder.encode(wrongMetadata) as NSData

        XCTAssertThrowsError(
            try CloudKitProfilePhotoAssetCodec.restoringIfNeeded(
                wireRecord: staged.wireRecord,
                cloudRecord: cloudRecord
            )
        ) { error in
            XCTAssertEqual(
                error as? CloudKitProfilePhotoAssetError,
                .profileMismatch
            )
        }
    }

    func testIncomingCorruptAssetIsRejectedBeforeAvatarReplacement() throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let original = try fixture.familyRecord()
        let staged = try XCTUnwrap(
            CloudKitProfilePhotoAssetCodec.stageIfNeeded(
                original,
                sourceDirectory: fixture.sourceDirectory
            )
        )
        let cloudRecord = fixture.cloudRecord()
        try CloudKitProfilePhotoAssetCodec.attach(
            staged,
            originalRecord: original,
            to: cloudRecord
        )
        let corruptURL = fixture.directory.appendingPathComponent("corrupt.jpg")
        try Data(repeating: 0x7F, count: 300_000).write(to: corruptURL)
        cloudRecord[CloudKitProfilePhotoAssetCodec.Schema.asset] = CKAsset(
            fileURL: corruptURL
        )

        XCTAssertThrowsError(
            try CloudKitProfilePhotoAssetCodec.restoringIfNeeded(
                wireRecord: staged.wireRecord,
                cloudRecord: cloudRecord
            )
        )
    }

    func testStagedSourceSurvivesRecreationAndAbandonedCleanupIsScoped()
        throws
    {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let original = try fixture.familyRecord()
        let first = try XCTUnwrap(
            CloudKitProfilePhotoAssetCodec.stageIfNeeded(
                original,
                sourceDirectory: fixture.sourceDirectory
            )
        )
        let second = try XCTUnwrap(
            CloudKitProfilePhotoAssetCodec.stageIfNeeded(
                original,
                sourceDirectory: fixture.sourceDirectory
            )
        )
        let unrelated = fixture.sourceDirectory.appendingPathComponent("keep.txt")
        try Data("keep".utf8).write(to: unrelated)
        let interruptedTemporary = fixture.sourceDirectory.appendingPathComponent(
            ".profile-photo-interrupted.tmp"
        )
        try Data("prepared child image bytes".utf8).write(
            to: interruptedTemporary
        )

        XCTAssertEqual(first.sourceURL, second.sourceURL)
        XCTAssertEqual(try Data(contentsOf: second.sourceURL), fixture.jpegData)
        try CloudKitProfilePhotoAssetCodec.removeAbandonedSources(
            in: fixture.sourceDirectory
        )
        XCTAssertFalse(FileManager.default.fileExists(atPath: first.sourceURL.path))
        XCTAssertFalse(
            FileManager.default.fileExists(atPath: interruptedTemporary.path)
        )
        XCTAssertTrue(FileManager.default.fileExists(atPath: unrelated.path))
    }

    func testProfileScopedSourcePurgeKeepsOtherProfileAndUnrelatedFiles()
        throws
    {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let ownSource = try XCTUnwrap(
            CloudKitProfilePhotoAssetCodec.stageIfNeeded(
                fixture.familyRecord(),
                sourceDirectory: fixture.sourceDirectory
            )
        ).sourceURL
        let otherProfileID = ProfileID()
        let otherSource = fixture.sourceDirectory.appendingPathComponent(
            "profile-photo-\(otherProfileID)-checksum.jpg"
        )
        let unrelated = fixture.sourceDirectory.appendingPathComponent("keep.txt")
        try fixture.jpegData.write(to: otherSource)
        try Data("keep".utf8).write(to: unrelated)

        try CloudKitProfilePhotoAssetCodec.removeSources(
            for: fixture.profileID,
            in: fixture.sourceDirectory
        )

        XCTAssertFalse(FileManager.default.fileExists(atPath: ownSource.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: otherSource.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: unrelated.path))
    }

    func testFetchedPhotoIsHydratedBeforeDurableInboxAndReplaysAfterRestart()
        async throws
    {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let original = try fixture.familyRecord()
        let store = try fixture.configuredStore()
        let cloudRecord = try fixture.productionCloudRecord(
            for: original,
            store: store
        )
        let firstBuffer = CloudKitFamilySyncEventBuffer(metadataStore: store)

        await firstBuffer.handle(
            .fetchedRecords([cloudRecord]),
            scope: .privateDatabase,
            generation: 1
        )
        let first = await firstBuffer.drain()
        XCTAssertEqual(first.records, [original])
        XCTAssertEqual(first.receiptIDs.count, 1)

        let restartedStore = CloudKitFamilyMetadataStore(
            snapshotURL: fixture.metadataURL
        )
        let durableEntries = restartedStore.inboxEntries()
        XCTAssertEqual(durableEntries.count, 1)
        XCTAssertEqual(durableEntries.first?.record, original)
        let restartedBuffer = CloudKitFamilySyncEventBuffer(
            metadataStore: restartedStore
        )
        await restartedBuffer.replay(durableEntries, generation: 1)
        let replayed = await restartedBuffer.drain()
        XCTAssertEqual(replayed.records, [original])

        let profile = try fixture.decoder.decode(
            KidProfile.self,
            from: try XCTUnwrap(replayed.records.first).payload
        )
        XCTAssertEqual(profile.avatar.embeddedPhotoData, fixture.jpegData)
    }

    func testInvalidFetchedAssetIsQuarantinedAndNeverReachesInboxOrApply()
        async throws
    {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let original = try fixture.familyRecord()
        let store = try fixture.configuredStore()
        let cloudRecord = try fixture.productionCloudRecord(
            for: original,
            store: store
        )
        let wrongMetadata = ProfilePhotoAttachmentMetadata(
            profileID: ProfileID(),
            source: .photoLibrary,
            pixelWidth: 128,
            pixelHeight: 96,
            byteCount: fixture.jpegData.count,
            checksum: ProfilePhotoAttachment.checksum(for: fixture.jpegData)
        )
        cloudRecord[CloudKitProfilePhotoAssetCodec.Schema.metadata] =
            try fixture.encoder.encode(wrongMetadata) as NSData
        let buffer = CloudKitFamilySyncEventBuffer(metadataStore: store)

        await buffer.handle(
            .fetchedRecords([cloudRecord]),
            scope: .privateDatabase,
            generation: 1
        )
        let result = await buffer.drain()

        XCTAssertTrue(result.records.isEmpty)
        XCTAssertTrue(result.receiptIDs.isEmpty)
        XCTAssertEqual(result.quarantinedRecordCount, 1)
        XCTAssertTrue(store.inboxEntries().isEmpty)
        XCTAssertEqual(store.quarantinedCount(), 1)
    }

    func testSuccessfulAcknowledgementRemovesDurableStagedSource()
        async throws
    {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let original = try fixture.familyRecord()
        let store = try fixture.configuredStore()
        let cloudRecord = try fixture.productionCloudRecord(
            for: original,
            store: store
        )
        let sourceURL = try XCTUnwrap(
            (cloudRecord[CloudKitProfilePhotoAssetCodec.Schema.asset] as? CKAsset)?
                .fileURL
        )
        XCTAssertTrue(FileManager.default.fileExists(atPath: sourceURL.path))
        let operation = FamilySyncPendingOperation.save(original)
        let buffer = CloudKitFamilySyncEventBuffer(metadataStore: store)
        await buffer.register(
            CloudKitFamilyOutgoingChange(
                acknowledgement: FamilySyncChangeAcknowledgement(
                    operation: operation
                ),
                record: cloudRecord,
                assetSourceURL: sourceURL
            ),
            recordID: cloudRecord.recordID,
            scope: .privateDatabase,
            generation: 1
        )

        await buffer.handle(
            .sentRecords(saved: [cloudRecord], failed: []),
            scope: .privateDatabase,
            generation: 1
        )
        let result = await buffer.drain()

        XCTAssertEqual(
            result.acknowledged,
            [FamilySyncChangeAcknowledgement(operation: operation)]
        )
        XCTAssertFalse(FileManager.default.fileExists(atPath: sourceURL.path))
    }
}

private struct Fixture {
    let directory: URL
    let sourceDirectory: URL
    let profileID = ProfileID(
        rawValue: UUID(uuidString: "82000000-0000-0000-0000-000000000001")!
    )
    let jpegData: Data

    var metadataURL: URL {
        directory.appendingPathComponent("metadata.json")
    }

    init() throws {
        directory = FileManager.default.temporaryDirectory.appendingPathComponent(
            "TadaCloudPhoto-\(UUID().uuidString)",
            isDirectory: true
        )
        sourceDirectory = directory.appendingPathComponent(
            "asset-sources",
            isDirectory: true
        )
        try FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true
        )
        jpegData = try Self.jpeg(width: 128, height: 96)
    }

    var encoder: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .secondsSince1970
        encoder.outputFormatting = [
            .prettyPrinted,
            .sortedKeys,
            .withoutEscapingSlashes,
        ]
        return encoder
    }

    var decoder: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .secondsSince1970
        return decoder
    }

    func familyRecord(
        avatar: ProfileAvatar? = nil,
        revisionCounter: UInt64 = 4
    ) throws -> FamilySyncRecord {
        let profile = KidProfile(
            id: profileID,
            displayName: "Photo Kid",
            avatar: avatar
                ?? .embeddedPhoto(data: jpegData, source: .photoLibrary),
            selectedWorld: .moonpetalKingdom,
            createdAt: Date(timeIntervalSince1970: 2_172_000_000)
        )
        let revision = FamilySyncLogicalRevision(
            counter: revisionCounter,
            deviceID: "photo-device"
        )
        return FamilySyncRecord(
            recordName: "profile-\(profileID)",
            profileID: profileID,
            kind: .profile,
            payload: try encoder.encode(profile),
            updatedAt: profile.updatedAt,
            deviceID: revision.deviceID,
            logicalRevision: revision
        )
    }

    func cloudRecord() -> CKRecord {
        CKRecord(
            recordType: "TadaFamilyItem",
            recordID: CKRecord.ID(
                recordName: "profile-\(profileID)",
                zoneID: CKRecordZone.ID(
                    zoneName: "profile-\(profileID)",
                    ownerName: CKCurrentUserDefaultName
                )
            )
        )
    }

    func configuredStore() throws -> CloudKitFamilyMetadataStore {
        let store = CloudKitFamilyMetadataStore(snapshotURL: metadataURL)
        let zoneID = cloudRecord().recordID.zoneID
        try store.save(
            binding: ProfileCloudBinding(
                profileID: profileID,
                state: .privateOwner,
                zoneName: zoneID.zoneName,
                ownerName: zoneID.ownerName,
                rootRecordName: "root-\(profileID)"
            )
        )
        return store
    }

    func productionCloudRecord(
        for record: FamilySyncRecord,
        store: CloudKitFamilyMetadataStore
    ) throws -> CKRecord {
        let recordID = cloudRecord().recordID
        return try CloudKitFamilyRecordCodec.cloudRecord(
            for: record,
            recordID: recordID,
            rootRecordID: CKRecord.ID(
                recordName: "root-\(profileID)",
                zoneID: recordID.zoneID
            ),
            scope: .privateDatabase,
            metadataStore: store,
            photoAssetSourceDirectory: sourceDirectory
        )
    }

    func remove() {
        try? FileManager.default.removeItem(at: directory)
    }

    private static func jpeg(width: Int, height: Int) throws -> Data {
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
        context.setFillColor(
            CGColor(
                colorSpace: colorSpace,
                components: [0.35, 0.65, 0.95, 1]
            )!
        )
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        guard let image = context.makeImage() else {
            throw FixtureError.imageCreation
        }
        let data = NSMutableData()
        guard
            let destination = CGImageDestinationCreateWithData(
                data,
                UTType.jpeg.identifier as CFString,
                1,
                nil
            )
        else { throw FixtureError.imageCreation }
        CGImageDestinationAddImage(
            destination,
            image,
            [kCGImageDestinationLossyCompressionQuality: 0.8] as CFDictionary
        )
        guard CGImageDestinationFinalize(destination) else {
            throw FixtureError.imageCreation
        }
        return data as Data
    }

    private enum FixtureError: Error {
        case imageCreation
    }
}
