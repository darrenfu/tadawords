@preconcurrency import CloudKit
import Foundation
import TadaWordsDomain
import XCTest

@testable import TadaWordsApplePlatform

final class CloudKitCanonicalGenerationCodecTests: XCTestCase {
    func testImmutableItemsAndPointerRoundTripExactFingerprint() throws {
        let snapshot = try fixture()
        let items =
            try CloudKitFamilyCanonicalGenerationCodec.itemRecords(
                for: snapshot
            )
        let pointer =
            try CloudKitFamilyCanonicalGenerationCodec.pointerRecord(
                for: snapshot,
                itemRecordNames: items.map(\.recordID.recordName),
                replacing: nil
            )
        let descriptor =
            try CloudKitFamilyCanonicalGenerationCodec.descriptor(
                from: pointer
            )

        let decoded =
            try CloudKitFamilyCanonicalGenerationCodec.snapshot(
                descriptor: descriptor,
                itemRecords: items
            )

        XCTAssertEqual(decoded, snapshot)
        XCTAssertEqual(
            pointer.recordID,
            CloudKitFamilyCanonicalGenerationCodec.pointerRecordID
        )
        XCTAssertTrue(
            (items + [pointer]).allSatisfy {
                $0.recordType
                    == CloudKitFamilyRecordCodec.Schema.itemRecordType
                    && Set($0.allKeys())
                        == [CloudKitFamilyRecordCodec.Schema.envelope]
            },
            "Canonical control records must reuse the deployed production schema"
        )
    }

    func testMissingItemFailsClosedBeforePointerCanBeTrusted() throws {
        let snapshot = try fixture()
        let items =
            try CloudKitFamilyCanonicalGenerationCodec.itemRecords(
                for: snapshot
            )
        let pointer =
            try CloudKitFamilyCanonicalGenerationCodec.pointerRecord(
                for: snapshot,
                itemRecordNames: items.map(\.recordID.recordName),
                replacing: nil
            )
        let descriptor =
            try CloudKitFamilyCanonicalGenerationCodec.descriptor(
                from: pointer
            )

        XCTAssertThrowsError(
            try CloudKitFamilyCanonicalGenerationCodec.snapshot(
                descriptor: descriptor,
                itemRecords: Array(items.dropLast())
            )
        )
    }

    func testManifestRetainsPreviousGenerationForRollback() throws {
        let snapshot = try fixture()
        let items =
            try CloudKitFamilyCanonicalGenerationCodec.itemRecords(
                for: snapshot
            )
        let manifest =
            try CloudKitFamilyCanonicalGenerationCodec.manifestRecord(
                for: snapshot,
                itemRecordNames: items.map(\.recordID.recordName)
            )

        XCTAssertEqual(
            manifest.recordID,
            CloudKitFamilyCanonicalGenerationCodec.manifestRecordID(
                for: snapshot.generationID
            )
        )
        XCTAssertEqual(
            try CloudKitFamilyCanonicalGenerationCodec.descriptor(
                from: manifest
            ).previousGenerationID,
            "generation-0"
        )
    }

    private func fixture() throws
        -> FamilySyncCanonicalGenerationSnapshot
    {
        let profileID = ProfileID()
        return FamilySyncCanonicalGenerationSnapshot(
            generationID: "generation-1",
            previousGenerationID: "generation-0",
            sourceInstallationID: "reading-ipad-3",
            createdAt: Date(timeIntervalSince1970: 100),
            records: [
                FamilySyncRecord(
                    recordName: "profile-\(profileID)",
                    profileID: profileID,
                    kind: .profile,
                    payload: Data("profile".utf8),
                    updatedAt: Date(timeIntervalSince1970: 90),
                    deviceID: "reading-ipad-3"
                ),
                FamilySyncRecord(
                    recordName: "word-1",
                    profileID: profileID,
                    kind: .wordPoolEntry,
                    payload: Data("albatross".utf8),
                    updatedAt: Date(timeIntervalSince1970: 91),
                    deviceID: "reading-ipad-3"
                ),
            ]
        )
    }
}
