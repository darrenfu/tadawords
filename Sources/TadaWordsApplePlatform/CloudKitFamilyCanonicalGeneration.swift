@preconcurrency import CloudKit
import Foundation
import TadaWordsDomain

enum CloudKitFamilyCanonicalGenerationCodec {
    enum Schema {
        // Reuse the already deployed production record type and Data field.
        // Control-zone identity plus reserved record names provide isolation.
        static let recordType = CloudKitFamilyRecordCodec.Schema.itemRecordType
        static let pointerRecordName = "active-family-sync-generation"
        static let payload = CloudKitFamilyRecordCodec.Schema.envelope
    }

    struct Descriptor: Codable, Equatable, Sendable {
        let generationID: String
        let previousGenerationID: String?
        let sourceInstallationID: String
        let createdAt: Date
        let recordNames: [String]
        let recordCount: Int
        let fingerprint: String
    }

    static var zoneID: CKRecordZone.ID {
        CloudKitFamilyDeletionLedgerCodec.controlZoneID
    }

    static var pointerRecordID: CKRecord.ID {
        CKRecord.ID(
            recordName: Schema.pointerRecordName,
            zoneID: zoneID
        )
    }

    static func manifestRecordID(for generationID: String) -> CKRecord.ID {
        CKRecord.ID(
            recordName: "canonical-manifest-\(generationID)",
            zoneID: zoneID
        )
    }

    static func isGenerationRecord(_ recordID: CKRecord.ID) -> Bool {
        recordID.zoneID == zoneID
            && (recordID == pointerRecordID
                || recordID.recordName.hasPrefix("canonical-"))
    }

    static func itemRecords(
        for snapshot: FamilySyncCanonicalGenerationSnapshot
    ) throws -> [CKRecord] {
        try snapshot.validate()
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        return try snapshot.records.enumerated().map { index, record in
            let recordName =
                "canonical-\(snapshot.generationID)-"
                + String(format: "%04d", index)
            let cloudRecord = CKRecord(
                recordType: Schema.recordType,
                recordID: CKRecord.ID(recordName: recordName, zoneID: zoneID)
            )
            cloudRecord[Schema.payload] = try encoder.encode(record) as NSData
            return cloudRecord
        }
    }

    static func pointerRecord(
        for snapshot: FamilySyncCanonicalGenerationSnapshot,
        itemRecordNames: [String],
        replacing existing: CKRecord?
    ) throws -> CKRecord {
        try snapshot.validate()
        let pointer =
            existing
            ?? CKRecord(
                recordType: Schema.recordType,
                recordID: pointerRecordID
            )
        guard pointer.recordType == Schema.recordType,
            pointer.recordID == pointerRecordID
        else {
            throw FamilySyncCanonicalRecoveryError.remoteVerificationFailed
        }
        pointer[Schema.payload] =
            try encodedDescriptor(
                for: snapshot,
                itemRecordNames: itemRecordNames
            ) as NSData
        return pointer
    }

    static func manifestRecord(
        for snapshot: FamilySyncCanonicalGenerationSnapshot,
        itemRecordNames: [String]
    ) throws -> CKRecord {
        let manifest = CKRecord(
            recordType: Schema.recordType,
            recordID: manifestRecordID(for: snapshot.generationID)
        )
        manifest[Schema.payload] =
            try encodedDescriptor(
                for: snapshot,
                itemRecordNames: itemRecordNames
            ) as NSData
        return manifest
    }

    static func descriptor(from pointer: CKRecord) throws -> Descriptor {
        guard
            pointer.recordType == Schema.recordType,
            let payload = pointer[Schema.payload] as? Data
        else {
            throw FamilySyncCanonicalRecoveryError.remoteVerificationFailed
        }
        let descriptor = try JSONDecoder().decode(
            Descriptor.self,
            from: payload
        )
        guard
            pointer.recordID == pointerRecordID
                || pointer.recordID
                    == manifestRecordID(for: descriptor.generationID),
            !descriptor.generationID.isEmpty,
            !descriptor.sourceInstallationID.isEmpty,
            descriptor.recordNames.count == descriptor.recordCount,
            Set(descriptor.recordNames).count == descriptor.recordNames.count,
            descriptor.recordNames.allSatisfy({
                $0.hasPrefix("canonical-\(descriptor.generationID)-")
            })
        else {
            throw FamilySyncCanonicalRecoveryError.remoteVerificationFailed
        }
        return descriptor
    }

    static func snapshot(
        descriptor: Descriptor,
        itemRecords: [CKRecord]
    ) throws -> FamilySyncCanonicalGenerationSnapshot {
        guard itemRecords.count == descriptor.recordCount else {
            throw FamilySyncCanonicalRecoveryError.remoteVerificationFailed
        }
        let decoder = JSONDecoder()
        let records = try itemRecords.map { cloudRecord -> FamilySyncRecord in
            guard cloudRecord.recordType == Schema.recordType,
                descriptor.recordNames.contains(
                    cloudRecord.recordID.recordName
                ),
                cloudRecord.recordID.recordName.hasPrefix(
                    "canonical-\(descriptor.generationID)-"
                ),
                let payload = cloudRecord[Schema.payload] as? Data
            else {
                throw FamilySyncCanonicalRecoveryError
                    .remoteVerificationFailed
            }
            return try decoder.decode(FamilySyncRecord.self, from: payload)
        }
        let snapshot = FamilySyncCanonicalGenerationSnapshot(
            generationID: descriptor.generationID,
            previousGenerationID: descriptor.previousGenerationID,
            sourceInstallationID: descriptor.sourceInstallationID,
            createdAt: descriptor.createdAt,
            records: records
        )
        try snapshot.validate()
        guard snapshot.recordSetFingerprint.value == descriptor.fingerprint,
            snapshot.records.count == descriptor.recordCount
        else {
            throw FamilySyncCanonicalRecoveryError.remoteVerificationFailed
        }
        return snapshot
    }

    private static func encodedDescriptor(
        for snapshot: FamilySyncCanonicalGenerationSnapshot,
        itemRecordNames: [String]
    ) throws -> Data {
        try snapshot.validate()
        let descriptor = Descriptor(
            generationID: snapshot.generationID,
            previousGenerationID: snapshot.previousGenerationID,
            sourceInstallationID: snapshot.sourceInstallationID,
            createdAt: snapshot.createdAt,
            recordNames: itemRecordNames,
            recordCount: snapshot.records.count,
            fingerprint: snapshot.recordSetFingerprint.value
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        return try encoder.encode(descriptor)
    }
}
