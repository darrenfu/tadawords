@preconcurrency import CloudKit
import Foundation
import TadaWordsDomain

public enum CloudKitFamilySyncError: Error, Sendable {
    case unavailable(FamilySyncAvailability)
    case malformedRecord(String)
    case missingShareURL
    case operationFailed(String)
}

public actor CloudKitFamilySyncTransport: FamilySyncTransport {
    public nonisolated let capability = FamilySyncCapability.iCloud

    private enum Schema {
        static let itemRecordType = "TadaFamilyItem"
        static let rootRecordType = "TadaProfileRoot"
        static let profileID = "profileID"
        static let kind = "kind"
        static let payload = "payload"
        static let updatedAt = "updatedAt"
        static let deviceID = "deviceID"
        static let isDeleted = "isDeleted"
    }

    private let container: CKContainer
    private let privateDatabase: CKDatabase
    private let sharedDatabase: CKDatabase

    public init(containerIdentifier: String = "iCloud.com.tadawords.app") {
        let container = CKContainer(identifier: containerIdentifier)
        self.container = container
        privateDatabase = container.privateCloudDatabase
        sharedDatabase = container.sharedCloudDatabase
    }

    public func availability() async -> FamilySyncAvailability {
        do {
            switch try await container.accountStatus() {
            case .available:
                return .available
            case .noAccount:
                return .noAccount
            case .restricted:
                return .restricted
            case .couldNotDetermine, .temporarilyUnavailable:
                return .temporarilyUnavailable
            @unknown default:
                return .temporarilyUnavailable
            }
        } catch {
            return .temporarilyUnavailable
        }
    }

    public func prepareProfileZone(_ profileID: ProfileID) async throws {
        try await requireAvailability()
        let zone = CKRecordZone(zoneID: zoneID(for: profileID))
        let result = try await privateDatabase.modifyRecordZones(
            saving: [zone],
            deleting: []
        )
        if case .failure(let error) = result.saveResults[zone.zoneID] {
            throw CloudKitFamilySyncError.operationFailed(String(describing: error))
        }
        _ = try await rootRecord(for: profileID, createIfMissing: true)
    }

    public func fetchRecords(
        for profileID: ProfileID
    ) async throws -> [FamilySyncRecord] {
        try await requireAvailability()
        async let privateRecords = fetchRecords(
            database: privateDatabase,
            profileID: profileID,
            zoneID: zoneID(for: profileID)
        )
        async let sharedRecords = fetchSharedRecords(for: profileID)
        let combined = try await privateRecords + sharedRecords
        return Dictionary(grouping: combined, by: \.recordName)
            .values
            .compactMap { records in
                records.reduce(nil as FamilySyncRecord?) { resolved, record in
                    FamilySyncConflictResolver.resolved(
                        local: resolved,
                        remote: record
                    )
                }
            }
            .sorted { $0.recordName < $1.recordName }
    }

    public func push(
        _ records: [FamilySyncRecord],
        for profileID: ProfileID
    ) async throws {
        guard !records.isEmpty else { return }
        try await requireAvailability()
        let sharedRoot = try await sharedRootRecord(for: profileID)
        let destination: CloudKitFamilyWriteDestination
        switch CloudKitFamilyWriteRoute.select(
            sharedRootAvailable: sharedRoot != nil
        ) {
        case .sharedParticipant:
            guard let sharedRoot else {
                throw CloudKitFamilySyncError.operationFailed(
                    "Shared profile root is missing"
                )
            }
            destination = .shared(database: sharedDatabase, root: sharedRoot)
        case .privateOwner:
            try await prepareProfileZone(profileID)
            destination = .privateOwner(
                database: privateDatabase,
                root: try await rootRecord(for: profileID, createIfMissing: true)
            )
        }
        let database = destination.database
        let root = destination.root
        let destinationZoneID = root.recordID.zoneID
        let cloudRecords = try records.map { record -> CKRecord in
            guard record.profileID == profileID else {
                throw CloudKitFamilySyncError.malformedRecord(record.recordName)
            }
            let cloudRecord = CKRecord(
                recordType: Schema.itemRecordType,
                recordID: CKRecord.ID(
                    recordName: record.recordName,
                    zoneID: destinationZoneID
                )
            )
            cloudRecord.parent = CKRecord.Reference(record: root, action: .none)
            cloudRecord[Schema.profileID] = profileID.rawValue.uuidString
            cloudRecord[Schema.kind] = record.kind.rawValue
            cloudRecord[Schema.payload] = record.payload as NSData
            cloudRecord[Schema.updatedAt] = record.updatedAt as NSDate
            cloudRecord[Schema.deviceID] = record.deviceID as NSString
            cloudRecord[Schema.isDeleted] = NSNumber(value: record.isDeleted)
            return cloudRecord
        }
        let result = try await database.modifyRecords(
            saving: cloudRecords,
            deleting: [],
            savePolicy: .changedKeys,
            atomically: true
        )
        for cloudRecord in cloudRecords {
            if case .failure(let error) = result.saveResults[cloudRecord.recordID] {
                throw CloudKitFamilySyncError.operationFailed(String(describing: error))
            }
        }
    }

    public func createShare(for profileID: ProfileID) async throws -> URL {
        try await prepareProfileZone(profileID)
        let root = try await rootRecord(for: profileID, createIfMissing: true)
        if let shareReference = root.share {
            let result = try await privateDatabase.records(for: [shareReference.recordID])
            if case .success(let existingShare as CKShare) = result[shareReference.recordID],
                let url = existingShare.url
            {
                return url
            }
        }

        let share = CKShare(rootRecord: root)
        share[CKShare.SystemFieldKey.title] = "Tada Words family" as NSString
        share.publicPermission = .none
        let result = try await privateDatabase.modifyRecords(
            saving: [root, share],
            deleting: [],
            savePolicy: .ifServerRecordUnchanged,
            atomically: true
        )
        guard case .success(let saved as CKShare) = result.saveResults[share.recordID],
            let url = saved.url
        else {
            throw CloudKitFamilySyncError.missingShareURL
        }
        return url
    }

    public func acceptShare(at url: URL) async throws -> ProfileID {
        let fetched = try await container.shareMetadatas(for: [url])
        guard case .success(let metadata) = fetched[url] else {
            throw CloudKitFamilySyncError.operationFailed("Share metadata unavailable")
        }
        let accepted = try await container.accept([metadata])
        guard case .success = accepted[metadata] else {
            throw CloudKitFamilySyncError.operationFailed("Share acceptance failed")
        }
        guard let rootRecordID = metadata.hierarchicalRootRecordID else {
            throw CloudKitFamilySyncError.operationFailed(
                "Shared profile root is unavailable"
            )
        }
        let root = try await sharedDatabase.record(for: rootRecordID)
        guard let profileString = root[Schema.profileID] as? String,
            let profileUUID = UUID(uuidString: profileString)
        else {
            throw CloudKitFamilySyncError.malformedRecord(
                rootRecordID.recordName
            )
        }
        return ProfileID(rawValue: profileUUID)
    }

    private func fetchSharedRecords(
        for profileID: ProfileID
    ) async throws -> [FamilySyncRecord] {
        var records: [FamilySyncRecord] = []
        for zone in try await sharedDatabase.allRecordZones() {
            records += try await fetchRecords(
                database: sharedDatabase,
                profileID: profileID,
                zoneID: zone.zoneID
            )
        }
        return records
    }

    private func sharedRootRecord(
        for profileID: ProfileID
    ) async throws -> CKRecord? {
        for zone in try await sharedDatabase.allRecordZones() {
            let query = CKQuery(
                recordType: Schema.rootRecordType,
                predicate: NSPredicate(
                    format: "%K == %@",
                    Schema.profileID,
                    profileID.rawValue.uuidString
                )
            )
            let page = try await sharedDatabase.records(
                matching: query,
                inZoneWith: zone.zoneID,
                resultsLimit: 1
            )
            for (_, result) in page.matchResults {
                if case .success(let record) = result {
                    return record
                }
            }
        }
        return nil
    }

    private func fetchRecords(
        database: CKDatabase,
        profileID: ProfileID,
        zoneID: CKRecordZone.ID?
    ) async throws -> [FamilySyncRecord] {
        let query = CKQuery(
            recordType: Schema.itemRecordType,
            predicate: NSPredicate(
                format: "%K == %@",
                Schema.profileID,
                profileID.rawValue.uuidString
            )
        )
        do {
            var page = try await database.records(
                matching: query,
                inZoneWith: zoneID,
                resultsLimit: CKQueryOperation.maximumResults
            )
            var records = try decodedRecords(page.matchResults)
            while let cursor = page.queryCursor {
                page = try await database.records(
                    continuingMatchFrom: cursor,
                    resultsLimit: CKQueryOperation.maximumResults
                )
                records.append(contentsOf: try decodedRecords(page.matchResults))
            }
            return records
        } catch let error as CKError
            where error.code == .zoneNotFound || error.code == .unknownItem
        {
            return []
        }
    }

    private func decodedRecords(
        _ results: [(CKRecord.ID, Result<CKRecord, any Error>)]
    ) throws -> [FamilySyncRecord] {
        try results.compactMap { _, result in
            switch result {
            case .success(let record):
                return try Self.decode(record)
            case .failure(let error as CKError) where error.code == .unknownItem:
                return nil
            case .failure(let error):
                throw CloudKitFamilySyncError.operationFailed(
                    String(describing: error)
                )
            }
        }
    }

    private static func decode(_ record: CKRecord) throws -> FamilySyncRecord {
        guard let profileString = record[Schema.profileID] as? String,
            let profileUUID = UUID(uuidString: profileString),
            let kindString = record[Schema.kind] as? String,
            let kind = FamilySyncRecordKind(rawValue: kindString),
            let payload = record[Schema.payload] as? Data,
            let updatedAt = record[Schema.updatedAt] as? Date,
            let deviceID = record[Schema.deviceID] as? String,
            let isDeleted = record[Schema.isDeleted] as? Bool
        else {
            throw CloudKitFamilySyncError.malformedRecord(record.recordID.recordName)
        }
        return FamilySyncRecord(
            recordName: record.recordID.recordName,
            profileID: ProfileID(rawValue: profileUUID),
            kind: kind,
            payload: payload,
            updatedAt: updatedAt,
            deviceID: deviceID,
            isDeleted: isDeleted
        )
    }

    private func rootRecord(
        for profileID: ProfileID,
        createIfMissing: Bool
    ) async throws -> CKRecord {
        let recordID = rootRecordID(for: profileID)
        let fetched = try await privateDatabase.records(for: [recordID])
        if case .success(let record) = fetched[recordID] {
            return record
        }
        guard createIfMissing else {
            throw CloudKitFamilySyncError.operationFailed("Profile root is missing")
        }
        let root = CKRecord(recordType: Schema.rootRecordType, recordID: recordID)
        root[Schema.profileID] = profileID.rawValue.uuidString
        let result = try await privateDatabase.modifyRecords(
            saving: [root],
            deleting: [],
            savePolicy: .ifServerRecordUnchanged,
            atomically: true
        )
        guard case .success(let saved) = result.saveResults[recordID] else {
            throw CloudKitFamilySyncError.operationFailed("Unable to create profile root")
        }
        return saved
    }

    private func requireAvailability() async throws {
        let state = await availability()
        guard state == .available else {
            throw CloudKitFamilySyncError.unavailable(state)
        }
    }

    private func zoneID(for profileID: ProfileID) -> CKRecordZone.ID {
        CKRecordZone.ID(
            zoneName: "TadaProfile-\(profileID.rawValue.uuidString)",
            ownerName: CKCurrentUserDefaultName
        )
    }

    private func rootRecordID(for profileID: ProfileID) -> CKRecord.ID {
        CKRecord.ID(
            recordName: "profile-root-\(profileID.rawValue.uuidString)",
            zoneID: zoneID(for: profileID)
        )
    }
}

enum CloudKitFamilyWriteRoute: Equatable {
    case privateOwner
    case sharedParticipant

    static func select(sharedRootAvailable: Bool) -> Self {
        sharedRootAvailable ? .sharedParticipant : .privateOwner
    }
}

private struct CloudKitFamilyWriteDestination {
    let database: CKDatabase
    let root: CKRecord

    static func privateOwner(
        database: CKDatabase,
        root: CKRecord
    ) -> Self {
        Self(database: database, root: root)
    }

    static func shared(database: CKDatabase, root: CKRecord) -> Self {
        Self(database: database, root: root)
    }
}
