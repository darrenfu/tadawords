@preconcurrency import CloudKit
import Foundation
import TadaWordsDomain

/// The only durable Cloud payload that survives an owner Profile erasure.
/// It deliberately excludes nickname, avatar, word, attempt, reward, and
/// asset data; CloudKit system fields plus these four scalar fields are enough
/// to make deletion terminal on every stale owner device.
enum CloudKitFamilyDeletionLedgerCodec {
    enum Schema {
        static let recordType = "TadaProfileDeletionLedger"
        static let profileID = "profileID"
        static let revisionCounter = "revisionCounter"
        static let revisionDeviceID = "revisionDeviceID"
        static let envelopeSchemaVersion = "envelopeSchemaVersion"
    }

    static let controlZoneID = CKRecordZone.ID(
        zoneName: "TadaFamilyDeletionControl-v1",
        ownerName: CKCurrentUserDefaultName
    )

    static func recordID(for profileID: ProfileID) -> CKRecord.ID {
        CKRecord.ID(
            recordName: "deleted-profile-\(profileID.rawValue.uuidString)",
            zoneID: controlZoneID
        )
    }

    static func cloudRecord(for tombstone: FamilySyncRecord) throws -> CKRecord {
        guard tombstone.kind == .profileDeletion, tombstone.isDeleted else {
            throw CloudKitFamilySyncError.malformedRecord(
                tombstone.recordName
            )
        }
        let record = CKRecord(
            recordType: Schema.recordType,
            recordID: recordID(for: tombstone.profileID)
        )
        record[Schema.profileID] =
            tombstone.profileID.rawValue.uuidString as NSString
        record[Schema.revisionCounter] =
            NSNumber(value: tombstone.logicalRevision.counter)
        record[Schema.revisionDeviceID] =
            tombstone.logicalRevision.deviceID as NSString
        record[Schema.envelopeSchemaVersion] =
            NSNumber(value: tombstone.schemaVersion)
        return record
    }

    static func familyRecord(from ledger: CKRecord) -> FamilySyncRecord? {
        guard ledger.recordType == Schema.recordType,
            ledger.recordID.zoneID == controlZoneID,
            Set(ledger.allKeys()) == allowedApplicationFieldNames,
            let profileString = ledger[Schema.profileID] as? String,
            let profileUUID = UUID(uuidString: profileString),
            let counter = ledger[Schema.revisionCounter] as? NSNumber,
            let deviceID = ledger[Schema.revisionDeviceID] as? String,
            !deviceID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
            ledger[Schema.envelopeSchemaVersion] is NSNumber
        else { return nil }
        let profileID = ProfileID(rawValue: profileUUID)
        let deletedAt = ledger.modificationDate ?? .distantPast
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .secondsSince1970
        encoder.outputFormatting = [.sortedKeys]
        guard
            let payload = try? encoder.encode(
                ProfileDeletionTombstone(
                    profileID: profileID,
                    deletedAt: deletedAt
                )
            )
        else { return nil }
        return FamilySyncRecord(
            recordName: "profile-\(profileID)",
            profileID: profileID,
            kind: .profileDeletion,
            payload: payload,
            updatedAt: deletedAt,
            deviceID: deviceID,
            isDeleted: true,
            // The control-ledger shape is independently fixed and contains no
            // versioned child payload. Materialize a locally readable
            // tombstone even when a newer app wrote the informational envelope
            // version, so older clients can still enforce deletion.
            schemaVersion: FamilySyncRecord.currentSchemaVersion,
            logicalRevision: FamilySyncLogicalRevision(
                counter: counter.uint64Value,
                deviceID: deviceID
            )
        )
    }

    static let allowedApplicationFieldNames: Set<String> = [
        Schema.profileID,
        Schema.revisionCounter,
        Schema.revisionDeviceID,
        Schema.envelopeSchemaVersion,
    ]

    @discardableResult
    static func removeUnexpectedApplicationFields(from record: CKRecord) -> Bool {
        let unexpected = Set(record.allKeys()).subtracting(
            allowedApplicationFieldNames
        )
        for key in unexpected {
            record[key] = nil
        }
        return !unexpected.isEmpty
    }
}

enum CloudKitFamilyProfileRemovalMode: Equatable, Sendable {
    case ownerGlobalDeletion
    case participantLeave
    case alreadyTerminal
}

/// Pure classification used by the live send path and deletion acceptance
/// tests. Most importantly, `.sharedParticipant` can never select the owner's
/// private control ledger.
enum CloudKitFamilyProfileRemovalPlanner {
    static func mode(
        for binding: ProfileCloudBinding
    ) -> CloudKitFamilyProfileRemovalMode {
        switch binding.state {
        case .privateOwner, .unbound, .ownerDeleted:
            .ownerGlobalDeletion
        case .sharedParticipant:
            .participantLeave
        case .revoked, .participantLeft:
            .alreadyTerminal
        }
    }
}
