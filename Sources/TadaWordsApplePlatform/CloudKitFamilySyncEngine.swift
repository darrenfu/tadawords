@preconcurrency import CloudKit
import Foundation
import TadaWordsDomain

enum CloudKitFamilyRecordDecodeResult: Sendable {
    case record(FamilySyncRecord)
    case quarantine(
        category: FamilySyncPrivacySafeErrorCategory,
        envelopeData: Data?
    )
}

enum CloudKitFamilyRecordCodec {
    enum Schema {
        static let itemRecordType = "TadaFamilyItem"
        static let rootRecordType = "TadaProfileRoot"
        static let profileID = "profileID"
        static let kind = "kind"
        static let envelope = "envelope"
        static let schemaVersion = "schemaVersion"

        // Legacy v1 fields remain read-only for migration.
        static let payload = "payload"
        static let updatedAt = "updatedAt"
        static let deviceID = "deviceID"
        static let isDeleted = "isDeleted"
    }

    static func cloudRecord(
        for record: FamilySyncRecord,
        recordID: CKRecord.ID,
        rootRecordID: CKRecord.ID,
        scope: CloudKitFamilyDatabaseScope,
        metadataStore: CloudKitFamilyMetadataStore,
        photoAssetSourceDirectory: URL = FileManager.default.temporaryDirectory
            .appendingPathComponent(
                "TadaWordsProfilePhotoAssetSources",
                isDirectory: true
            )
    ) throws -> CKRecord {
        try record.validateCompatibility()
        let outboundRecord =
            try CloudKitProfilePhotoAssetCodec
            .canonicalizedForCurrentWriter(record)
        try outboundRecord.validateCompatibility()
        let stagedPhoto = try CloudKitProfilePhotoAssetCodec.stageIfNeeded(
            outboundRecord,
            sourceDirectory: photoAssetSourceDirectory
        )
        let envelopeRecord = stagedPhoto?.wireRecord ?? outboundRecord
        let cloudRecord =
            metadataStore.restoredRecord(id: recordID, scope: scope)
            ?? CKRecord(recordType: Schema.itemRecordType, recordID: recordID)
        let envelopeData: Data
        do {
            envelopeData = try JSONEncoder().encode(
                FamilySyncEnvelope(record: envelopeRecord)
            )
        } catch {
            CloudKitProfilePhotoAssetCodec.removeSource(
                at: stagedPhoto?.sourceURL
            )
            throw error
        }
        cloudRecord.parent = CKRecord.Reference(recordID: rootRecordID, action: .none)
        cloudRecord[Schema.profileID] =
            outboundRecord.profileID.rawValue.uuidString as NSString
        cloudRecord[Schema.kind] = outboundRecord.kind.rawValue as NSString
        cloudRecord[Schema.schemaVersion] = NSNumber(
            value: outboundRecord.schemaVersion
        )
        cloudRecord[Schema.envelope] = envelopeData as NSData
        if let stagedPhoto {
            do {
                try CloudKitProfilePhotoAssetCodec.attach(
                    stagedPhoto,
                    originalRecord: outboundRecord,
                    to: cloudRecord
                )
            } catch {
                CloudKitProfilePhotoAssetCodec.removeSource(
                    at: stagedPhoto.sourceURL
                )
                throw error
            }
        } else {
            cloudRecord[CloudKitProfilePhotoAssetCodec.Schema.asset] = nil
            cloudRecord[CloudKitProfilePhotoAssetCodec.Schema.metadata] = nil
            cloudRecord[
                CloudKitProfilePhotoAssetCodec.Schema.originalPayloadChecksum
            ] = nil
            cloudRecord[
                CloudKitProfilePhotoAssetCodec.Schema.originalPayloadSize
            ] = nil
        }
        return cloudRecord
    }

    static func decode(_ record: CKRecord) -> CloudKitFamilyRecordDecodeResult {
        if let data = record[Schema.envelope] as? Data {
            do {
                let envelope = try JSONDecoder().decode(FamilySyncEnvelope.self, from: data)
                guard envelope.recordName == record.recordID.recordName else {
                    return .quarantine(category: .compatibility, envelopeData: data)
                }
                let wireRecord = try envelope.decodedRecord()
                return .record(
                    try CloudKitProfilePhotoAssetCodec.restoringIfNeeded(
                        wireRecord: wireRecord,
                        cloudRecord: record
                    )
                )
            } catch {
                return .quarantine(category: .compatibility, envelopeData: data)
            }
        }

        guard let profileString = record[Schema.profileID] as? String,
            let profileUUID = UUID(uuidString: profileString),
            let kindString = record[Schema.kind] as? String,
            let kind = FamilySyncRecordKind(rawValue: kindString),
            let payload = record[Schema.payload] as? Data,
            let updatedAt = record[Schema.updatedAt] as? Date,
            let deviceID = record[Schema.deviceID] as? String,
            let isDeletedNumber = record[Schema.isDeleted] as? NSNumber
        else {
            return .quarantine(category: .compatibility, envelopeData: nil)
        }
        let legacyRecord = FamilySyncRecord(
            recordName: record.recordID.recordName,
            profileID: ProfileID(rawValue: profileUUID),
            kind: kind,
            payload: payload,
            updatedAt: updatedAt,
            deviceID: deviceID,
            isDeleted: isDeletedNumber.boolValue,
            schemaVersion: 1,
            minimumReadableVersion: 1,
            logicalRevision: FamilySyncLogicalRevision(
                counter: 0,
                deviceID: deviceID
            )
        )
        do {
            try legacyRecord.validateCompatibility()
            return .record(legacyRecord)
        } catch {
            return .quarantine(category: .compatibility, envelopeData: nil)
        }
    }
}

struct CloudKitFamilyOutgoingChange: Sendable {
    let acknowledgement: FamilySyncChangeAcknowledgement
    let record: CKRecord?
    let assetSourceURL: URL?

    init(
        acknowledgement: FamilySyncChangeAcknowledgement,
        record: CKRecord?,
        assetSourceURL: URL? = nil
    ) {
        self.acknowledgement = acknowledgement
        self.record = record
        self.assetSourceURL = assetSourceURL
    }
}

enum CloudKitFamilyEngineEvent: Sendable {
    case accountChange(CloudKitFamilyAccountEngineEvent)
    case fetchedRecords([CKRecord])
    case fetchedDeletions([CKRecord.ID])
    case deletedZones([CKRecordZone.ID])
    case sentRecords(saved: [CKRecord], failed: [(CKRecord, CKError)])
    case sentDeletions(saved: [CKRecord.ID], failed: [(CKRecord.ID, CKError)])
    case operationFailure(CKError)
}

enum CloudKitFamilyAccountEngineEvent: Sendable {
    case signedIn(recordName: String)
    case signedOut
    case switchedAccounts
}

actor CloudKitFamilySyncEventBuffer {
    private var activeGeneration: UInt64 = 1
    private var outgoing: [String: CloudKitFamilyOutgoingChange] = [:]
    private var incoming: [FamilySyncChangeKey: FamilySyncRecord] = [:]
    private var deletions: Set<FamilySyncChangeKey> = []
    private var acknowledgements: Set<FamilySyncChangeAcknowledgement> = []
    private var failures: [FamilySyncTransportFailure] = []
    private var accountChange: FamilySyncAccountChange?
    private var quarantinedRecordCount = 0
    private var receiptIDs: Set<UUID> = []
    private var receipts: [UUID: FamilySyncFetchedReceipt] = [:]
    private var durabilityFailure = false
    private var requiresFetchPass = false
    private let metadataStore: CloudKitFamilyMetadataStore

    init(metadataStore: CloudKitFamilyMetadataStore) {
        self.metadataStore = metadataStore
    }

    func nextGeneration() -> UInt64 {
        activeGeneration &+= 1
        cleanupOutgoingSources()
        outgoing.removeAll()
        incoming.removeAll()
        deletions.removeAll()
        acknowledgements.removeAll()
        failures.removeAll()
        accountChange = nil
        quarantinedRecordCount = 0
        receiptIDs.removeAll()
        receipts.removeAll()
        durabilityFailure = false
        requiresFetchPass = false
        return activeGeneration
    }

    func isActive(_ generation: UInt64) -> Bool {
        generation == activeGeneration
    }

    func canPersistEngineState(_ generation: UInt64) -> Bool {
        generation == activeGeneration && !durabilityFailure
    }

    func persistEngineState(
        _ serialization: CKSyncEngine.State.Serialization,
        scope: CloudKitFamilyDatabaseScope,
        generation: UInt64,
        stateStore: CloudKitFamilySyncStateStore
    ) {
        guard generation == activeGeneration,
            !durabilityFailure,
            accountChange == nil
        else { return }
        guard stateStore.save(serialization, scope: scope) else {
            durabilityFailure = true
            failures.append(
                FamilySyncTransportFailure(key: nil, category: .corruptState)
            )
            return
        }
    }

    func replay(
        _ entries: [CloudKitFamilyInboxEntry],
        generation: UInt64
    ) {
        guard generation == activeGeneration else { return }
        for entry in entries {
            receiptIDs.insert(entry.receiptID)
            if let record = entry.record {
                let key = FamilySyncChangeKey(
                    profileID: record.profileID,
                    recordName: record.recordName
                )
                receipts[entry.receiptID] = FamilySyncFetchedReceipt(
                    id: entry.receiptID,
                    key: key,
                    operation: .save,
                    revision: record.logicalRevision
                )
                if let existing = incoming[key] {
                    if Self.isInvariantConflict(existing, record) {
                        let conflictingIDs = Set(
                            receipts.values.filter { $0.key == key }.map(\.id)
                        )
                        do {
                            try metadataStore.quarantineInbox(
                                receiptIDs: conflictingIDs,
                                category: .conflict,
                                at: Date()
                            )
                            receiptIDs.subtract(conflictingIDs)
                            for id in conflictingIDs { receipts.removeValue(forKey: id) }
                            incoming.removeValue(forKey: key)
                            quarantinedRecordCount += conflictingIDs.count
                        } catch {
                            durabilityFailure = true
                            failures.append(
                                FamilySyncTransportFailure(
                                    key: key,
                                    category: .corruptState
                                )
                            )
                        }
                        continue
                    } else {
                        incoming[key] = FamilySyncConflictResolver.resolved(
                            local: existing,
                            remote: record
                        )
                    }
                } else {
                    incoming[key] = record
                }
            } else if let key = entry.deletionKey {
                deletions.insert(key)
                receipts[entry.receiptID] = FamilySyncFetchedReceipt(
                    id: entry.receiptID,
                    key: key,
                    operation: .delete,
                    revision: nil
                )
            }
        }
    }

    func register(
        _ change: CloudKitFamilyOutgoingChange,
        recordID: CKRecord.ID,
        scope: CloudKitFamilyDatabaseScope,
        generation: UInt64
    ) {
        guard generation == activeGeneration, accountChange == nil else {
            CloudKitProfilePhotoAssetCodec.removeSource(
                at: change.assetSourceURL
            )
            return
        }
        let key = Self.key(recordID, scope: scope)
        if let existing = outgoing[key],
            existing.assetSourceURL != change.assetSourceURL
        {
            CloudKitProfilePhotoAssetCodec.removeSource(
                at: existing.assetSourceURL
            )
        }
        outgoing[key] = change
    }

    func record(
        for recordID: CKRecord.ID,
        scope: CloudKitFamilyDatabaseScope,
        generation: UInt64
    ) -> CKRecord? {
        guard generation == activeGeneration, accountChange == nil else {
            return nil
        }
        guard let change = outgoing[Self.key(recordID, scope: scope)] else {
            return nil
        }
        guard
            !Self.isTerminal(
                metadataStore.binding(for: change.acknowledgement.key.profileID).state
            )
        else { return nil }
        return change.record
    }

    func discardOutgoing(
        for profileID: ProfileID,
        generation: UInt64
    ) {
        guard generation == activeGeneration else { return }
        let keys = outgoing.compactMap { key, change in
            change.acknowledgement.key.profileID == profileID ? key : nil
        }
        for key in keys {
            CloudKitProfilePhotoAssetCodec.removeSource(
                at: outgoing[key]?.assetSourceURL
            )
            outgoing.removeValue(forKey: key)
        }
    }

    func handle(
        _ event: CloudKitFamilyEngineEvent,
        scope: CloudKitFamilyDatabaseScope,
        generation: UInt64,
        now: Date = Date()
    ) {
        guard generation == activeGeneration else { return }
        // Once an account boundary is observed, every later callback from the
        // same engines is untrusted until confirmation installs a new
        // generation. This also covers callbacks already queued by CKSyncEngine
        // after its account-change event.
        guard accountChange == nil else { return }
        switch event {
        case .accountChange(let event):
            do {
                switch event {
                case .signedIn(let recordName):
                    accountChange = try metadataStore.handleAccountSignIn(
                        recordName: recordName
                    )
                case .signedOut:
                    try metadataStore.handleAccountSignOut()
                    accountChange = .signedOut
                case .switchedAccounts:
                    try metadataStore.handleAccountSignOut()
                    accountChange = .switchedAccounts
                }
            } catch {
                // Account metadata is a privacy boundary. Fail closed and stop
                // state-token persistence if that boundary cannot be written.
                durabilityFailure = true
                accountChange = .switchedAccounts
                failures.append(
                    FamilySyncTransportFailure(
                        key: nil,
                        category: .corruptState
                    )
                )
            }
        case .fetchedRecords(let records):
            // CKSyncEngine does not promise parent-before-child ordering. Bind
            // roots (and process terminal ledgers) before validating item
            // routes while preserving CloudKit order within each category.
            let orderedRecords = records.enumerated().sorted { left, right in
                let leftPriority = Self.fetchPriority(left.element)
                let rightPriority = Self.fetchPriority(right.element)
                return leftPriority == rightPriority
                    ? left.offset < right.offset
                    : leftPriority < rightPriority
            }.map(\.element)
            for cloudRecord in orderedRecords {
                if let binding = metadataStore.binding(
                    for: cloudRecord.recordID.zoneID
                ), Self.isTerminal(binding.state) {
                    // A callback already queued before terminal erasure must
                    // not recreate system fields or quarantine child payload.
                    continue
                }
                if cloudRecord.recordType
                    == CloudKitFamilyDeletionLedgerCodec.Schema.recordType
                {
                    guard scope == .privateDatabase,
                        let record =
                            CloudKitFamilyDeletionLedgerCodec
                            .familyRecord(from: cloudRecord)
                    else {
                        quarantine(
                            cloudRecord,
                            scope: scope,
                            category: .compatibility,
                            envelopeData: nil,
                            now: now
                        )
                        continue
                    }
                    do {
                        try metadataStore.saveSystemFields(
                            for: cloudRecord,
                            scope: scope
                        )
                        try metadataStore.markOwnerDeleted(
                            profileID: record.profileID
                        )
                        let receiptID = try metadataStore.appendInbox(
                            record: record,
                            recordID: cloudRecord.recordID,
                            scope: scope,
                            receivedAt: now
                        )
                        let key = FamilySyncChangeKey(
                            profileID: record.profileID,
                            recordName: record.recordName
                        )
                        receiptIDs.insert(receiptID)
                        receipts[receiptID] = FamilySyncFetchedReceipt(
                            id: receiptID,
                            key: key,
                            operation: .save,
                            revision: record.logicalRevision
                        )
                        incoming[key] = FamilySyncConflictResolver.resolved(
                            local: incoming[key],
                            remote: record
                        )
                    } catch {
                        durabilityFailure = true
                        failures.append(
                            FamilySyncTransportFailure(
                                key: nil,
                                category: .corruptState
                            )
                        )
                    }
                    continue
                }
                if cloudRecord.recordType == CloudKitFamilyRecordCodec.Schema.rootRecordType {
                    handleRootRecord(cloudRecord, scope: scope)
                    continue
                }
                if cloudRecord.recordType == CKRecord.SystemType.share {
                    do {
                        try metadataStore.saveSystemFields(for: cloudRecord, scope: scope)
                    } catch {
                        durabilityFailure = true
                        failures.append(
                            FamilySyncTransportFailure(key: nil, category: .corruptState)
                        )
                    }
                    continue
                }
                switch CloudKitFamilyRecordCodec.decode(cloudRecord) {
                case .record(let record):
                    guard
                        validatesCloudIdentity(
                            cloudRecord,
                            decoded: record,
                            scope: scope
                        )
                    else {
                        quarantine(
                            cloudRecord,
                            scope: scope,
                            category: .compatibility,
                            envelopeData: cloudRecord[
                                CloudKitFamilyRecordCodec.Schema.envelope
                            ] as? Data,
                            now: now
                        )
                        continue
                    }
                    let key = FamilySyncChangeKey(
                        profileID: record.profileID,
                        recordName: record.recordName
                    )
                    if let existing = incoming[key] {
                        if Self.isInvariantConflict(existing, record) {
                            let existingReceiptIDs = Set(
                                receipts.values.filter { $0.key == key }.map(\.id)
                            )
                            do {
                                try metadataStore.quarantineInbox(
                                    receiptIDs: existingReceiptIDs,
                                    category: .conflict,
                                    at: now
                                )
                                receiptIDs.subtract(existingReceiptIDs)
                                for id in existingReceiptIDs {
                                    receipts.removeValue(forKey: id)
                                }
                                incoming.removeValue(forKey: key)
                                quarantinedRecordCount += existingReceiptIDs.count
                            } catch {
                                durabilityFailure = true
                                failures.append(
                                    FamilySyncTransportFailure(
                                        key: key,
                                        category: .corruptState
                                    )
                                )
                            }
                            quarantine(
                                cloudRecord,
                                scope: scope,
                                category: .conflict,
                                envelopeData: cloudRecord[
                                    CloudKitFamilyRecordCodec.Schema.envelope
                                ] as? Data,
                                now: now
                            )
                            continue
                        }
                    }
                    do {
                        try metadataStore.saveSystemFields(for: cloudRecord, scope: scope)
                        let receiptID =
                            try metadataStore
                            .appendInboxReplacingQuarantine(
                                record: record,
                                recordID: cloudRecord.recordID,
                                scope: scope,
                                receivedAt: now
                            )
                        receiptIDs.insert(receiptID)
                        receipts[receiptID] = FamilySyncFetchedReceipt(
                            id: receiptID,
                            key: key,
                            operation: .save,
                            revision: record.logicalRevision
                        )
                    } catch {
                        durabilityFailure = true
                        failures.append(
                            FamilySyncTransportFailure(key: nil, category: .corruptState)
                        )
                        continue
                    }
                    incoming[key] = FamilySyncConflictResolver.resolved(
                        local: incoming[key],
                        remote: record
                    )
                case .quarantine(let category, let envelopeData):
                    quarantine(
                        cloudRecord,
                        scope: scope,
                        category: category,
                        envelopeData: envelopeData,
                        now: now
                    )
                }
            }
        case .fetchedDeletions(let recordIDs):
            for recordID in recordIDs {
                guard let binding = metadataStore.binding(for: recordID.zoneID) else {
                    quarantinedRecordCount += 1
                    continue
                }
                if recordID.recordName == binding.rootRecordName {
                    do {
                        try appendTerminalProfileRemoval(
                            profileID: binding.profileID,
                            recordID: recordID,
                            scope: scope,
                            now: now
                        )
                        // The durable purge fact is the recovery barrier. If
                        // the process dies after revoking the route but before
                        // writing that fact, the next fetch would refuse the
                        // revoked binding and could never replay the deletion.
                        try metadataStore.revokeBinding(for: recordID.zoneID)
                    } catch {
                        durabilityFailure = true
                        failures.append(
                            FamilySyncTransportFailure(
                                key: nil,
                                category: .corruptState
                            )
                        )
                    }
                    continue
                }
                let key = FamilySyncChangeKey(
                    profileID: binding.profileID,
                    recordName: recordID.recordName
                )
                do {
                    let receiptID = try metadataStore.appendInbox(
                        deletionKey: key,
                        recordID: recordID,
                        scope: scope,
                        receivedAt: now
                    )
                    receiptIDs.insert(receiptID)
                    receipts[receiptID] = FamilySyncFetchedReceipt(
                        id: receiptID,
                        key: key,
                        operation: .delete,
                        revision: nil
                    )
                    deletions.insert(key)
                } catch {
                    durabilityFailure = true
                    failures.append(
                        FamilySyncTransportFailure(key: key, category: .corruptState)
                    )
                    continue
                }
                try? metadataStore.removeSystemFields(id: recordID, scope: scope)
            }
        case .deletedZones(let zoneIDs):
            for zoneID in zoneIDs {
                do {
                    guard let binding = metadataStore.binding(for: zoneID) else {
                        quarantinedRecordCount += 1
                        continue
                    }
                    let recordID =
                        binding.rootRecordID
                        ?? CKRecord.ID(
                            recordName: "profile-\(binding.profileID)",
                            zoneID: zoneID
                        )
                    try appendTerminalProfileRemoval(
                        profileID: binding.profileID,
                        recordID: recordID,
                        scope: scope,
                        now: now
                    )
                    try metadataStore.revokeBinding(for: zoneID)
                } catch {
                    durabilityFailure = true
                    failures.append(
                        FamilySyncTransportFailure(key: nil, category: .corruptState)
                    )
                }
            }
        case .sentRecords(let saved, let failed):
            for record in saved {
                let key = Self.key(record.recordID, scope: scope)
                guard let change = outgoing[key] else { continue }
                if Self.isTerminal(
                    metadataStore.binding(
                        for: change.acknowledgement.key.profileID
                    ).state
                ) {
                    CloudKitProfilePhotoAssetCodec.removeSource(
                        at: change.assetSourceURL
                    )
                    outgoing.removeValue(forKey: key)
                    continue
                }
                do {
                    try metadataStore.saveSystemFields(for: record, scope: scope)
                    acknowledgements.insert(change.acknowledgement)
                    CloudKitProfilePhotoAssetCodec.removeSource(
                        at: change.assetSourceURL
                    )
                    outgoing.removeValue(forKey: key)
                } catch {
                    failures.append(
                        FamilySyncTransportFailure(
                            key: change.acknowledgement.key,
                            category: .corruptState
                        )
                    )
                }
            }
            for (record, error) in failed {
                appendFailure(for: record.recordID, error: error, scope: scope)
            }
        case .sentDeletions(let saved, let failed):
            for recordID in saved {
                let key = Self.key(recordID, scope: scope)
                guard let change = outgoing[key] else { continue }
                if Self.isTerminal(
                    metadataStore.binding(
                        for: change.acknowledgement.key.profileID
                    ).state
                ) {
                    CloudKitProfilePhotoAssetCodec.removeSource(
                        at: change.assetSourceURL
                    )
                    outgoing.removeValue(forKey: key)
                    continue
                }
                do {
                    try metadataStore.removeSystemFields(id: recordID, scope: scope)
                    acknowledgements.insert(change.acknowledgement)
                    outgoing.removeValue(forKey: key)
                } catch {
                    failures.append(
                        FamilySyncTransportFailure(
                            key: change.acknowledgement.key,
                            category: .corruptState
                        )
                    )
                }
            }
            for (recordID, error) in failed {
                appendFailure(for: recordID, error: error, scope: scope)
            }
        case .operationFailure(let error):
            failures.append(Self.failure(key: nil, error: error))
        }
    }

    func drain() -> FamilySyncTransportResult {
        let result = FamilySyncTransportResult(
            records: incoming.values.sorted { lhs, rhs in
                if lhs.profileID != rhs.profileID {
                    return lhs.profileID.description < rhs.profileID.description
                }
                return lhs.recordName < rhs.recordName
            },
            deletions: deletions.map(FamilySyncRemoteDeletion.init),
            acknowledged: acknowledgements,
            failures: failures,
            accountChange: accountChange,
            quarantinedRecordCount: quarantinedRecordCount,
            receiptIDs: receiptIDs,
            receipts: receipts.values.sorted {
                $0.id.uuidString < $1.id.uuidString
            },
            requiresFetchPass: requiresFetchPass
        )
        incoming.removeAll()
        deletions.removeAll()
        acknowledgements.removeAll()
        failures.removeAll()
        quarantinedRecordCount = 0
        receiptIDs.removeAll()
        receipts.removeAll()
        requiresFetchPass = false
        cleanupOutgoingSources()
        outgoing.removeAll()
        return result
    }

    func pendingAccountChange() -> FamilySyncAccountChange? {
        accountChange
    }

    func discardOutgoing(generation: UInt64) {
        guard generation == activeGeneration else { return }
        cleanupOutgoingSources()
        outgoing.removeAll()
    }

    func noteCorruptStateRecovery() {
        quarantinedRecordCount += 1
        failures.append(FamilySyncTransportFailure(key: nil, category: .corruptState))
    }

    func noteStatePersistenceFailure(_ generation: UInt64) {
        guard generation == activeGeneration else { return }
        durabilityFailure = true
        failures.append(
            FamilySyncTransportFailure(key: nil, category: .corruptState)
        )
    }

    private func quarantine(
        _ record: CKRecord,
        scope: CloudKitFamilyDatabaseScope,
        category: FamilySyncPrivacySafeErrorCategory,
        envelopeData: Data?,
        now: Date
    ) {
        quarantinedRecordCount += 1
        do {
            try metadataStore.quarantine(
                CloudKitFamilyQuarantineEntry(
                    id: UUID(),
                    scope: scope,
                    recordName: record.recordID.recordName,
                    zoneName: record.recordID.zoneID.zoneName,
                    ownerName: record.recordID.zoneID.ownerName,
                    reason: category,
                    envelopeData: envelopeData,
                    quarantinedAt: now
                )
            )
        } catch {
            durabilityFailure = true
            failures.append(FamilySyncTransportFailure(key: nil, category: .corruptState))
        }
    }

    private func appendTerminalProfileRemoval(
        profileID: ProfileID,
        recordID: CKRecord.ID,
        scope: CloudKitFamilyDatabaseScope,
        now: Date
    ) throws {
        // A deleted CKRecord/zone does not include its server deletion date.
        // Use a stable semantic date rather than the callback time: CloudKit
        // may replay the same zone deletion after process restart, and a fresh
        // timestamp would turn one terminal fact into a same-revision,
        // different-checksum conflict with a second inbox receipt.
        let semanticDeletionDate = Date(timeIntervalSince1970: 0)
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .secondsSince1970
        // The payload checksum is part of inbox deduplication. JSON object key
        // order is otherwise unspecified, so the same semantic tombstone could
        // acquire a second receipt after process restart.
        encoder.outputFormatting = [.sortedKeys]
        let record = FamilySyncRecord(
            recordName: "profile-\(profileID)",
            profileID: profileID,
            kind: .profileDeletion,
            payload: try encoder.encode(
                ProfileDeletionTombstone(
                    profileID: profileID,
                    deletedAt: semanticDeletionDate
                )
            ),
            updatedAt: semanticDeletionDate,
            deviceID: "cloud-share-revocation",
            isDeleted: true,
            logicalRevision: FamilySyncLogicalRevision(
                counter: 0,
                deviceID: "cloud-share-revocation"
            )
        )
        let key = FamilySyncChangeKey(
            profileID: profileID,
            recordName: record.recordName
        )
        let receiptID = try metadataStore.appendInbox(
            record: record,
            recordID: recordID,
            scope: scope,
            receivedAt: now
        )
        receiptIDs.insert(receiptID)
        receipts[receiptID] = FamilySyncFetchedReceipt(
            id: receiptID,
            key: key,
            operation: .save,
            revision: record.logicalRevision
        )
        incoming[key] = FamilySyncConflictResolver.resolved(
            local: incoming[key],
            remote: record
        )
    }

    private func handleRootRecord(
        _ record: CKRecord,
        scope: CloudKitFamilyDatabaseScope
    ) {
        guard
            let profileString = record[
                CloudKitFamilyRecordCodec.Schema.profileID
            ] as? String,
            let profileUUID = UUID(uuidString: profileString)
        else {
            quarantine(
                record,
                scope: scope,
                category: .compatibility,
                envelopeData: nil,
                now: Date()
            )
            return
        }
        let profileID = ProfileID(rawValue: profileUUID)
        let existing = metadataStore.binding(for: profileID)
        let expectedState: ProfileCloudBindingState =
            scope == .sharedDatabase
            ? .sharedParticipant
            : .privateOwner
        if existing.state != .unbound,
            existing.state != expectedState
                || existing.zoneID != record.recordID.zoneID
        {
            quarantine(
                record,
                scope: scope,
                category: .conflict,
                envelopeData: nil,
                now: Date()
            )
            return
        }
        do {
            try metadataStore.save(
                binding: ProfileCloudBinding(
                    profileID: profileID,
                    state: expectedState,
                    zoneName: record.recordID.zoneID.zoneName,
                    ownerName: record.recordID.zoneID.ownerName,
                    rootRecordName: record.recordID.recordName
                )
            )
            try metadataStore.saveSystemFields(for: record, scope: scope)
        } catch {
            durabilityFailure = true
            failures.append(FamilySyncTransportFailure(key: nil, category: .corruptState))
        }
    }

    private func validatesCloudIdentity(
        _ cloudRecord: CKRecord,
        decoded record: FamilySyncRecord,
        scope: CloudKitFamilyDatabaseScope
    ) -> Bool {
        guard cloudRecord.recordType == CloudKitFamilyRecordCodec.Schema.itemRecordType,
            cloudRecord.recordID.recordName == record.recordName,
            cloudRecord[CloudKitFamilyRecordCodec.Schema.profileID] as? String
                == record.profileID.rawValue.uuidString,
            cloudRecord[CloudKitFamilyRecordCodec.Schema.kind] as? String
                == record.kind.rawValue,
            let binding = metadataStore.binding(for: cloudRecord.recordID.zoneID),
            binding.profileID == record.profileID,
            binding.databaseScope == scope
        else { return false }
        if let schema = cloudRecord[
            CloudKitFamilyRecordCodec.Schema.schemaVersion
        ] as? NSNumber,
            schema.intValue != record.schemaVersion
        {
            return false
        }
        return true
    }

    private func appendFailure(
        for recordID: CKRecord.ID,
        error: CKError,
        scope: CloudKitFamilyDatabaseScope
    ) {
        let outgoingChange = outgoing[Self.key(recordID, scope: scope)]
        if error.code == .serverRecordChanged,
            let outgoingChange,
            outgoingChange.acknowledgement.operation == .save,
            let expectedCloudRecord = outgoingChange.record,
            let serverRecord = error.userInfo[
                CKRecordChangedErrorServerRecordKey
            ] as? CKRecord,
            case .record(let expected) = CloudKitFamilyRecordCodec.decode(
                expectedCloudRecord
            ),
            case .record(let server) = CloudKitFamilyRecordCodec.decode(serverRecord),
            validatesCloudIdentity(
                expectedCloudRecord,
                decoded: expected,
                scope: scope
            ),
            validatesCloudIdentity(serverRecord, decoded: server, scope: scope),
            expected == server
        {
            do {
                try metadataStore.saveSystemFields(for: serverRecord, scope: scope)
                acknowledgements.insert(outgoingChange.acknowledgement)
                CloudKitProfilePhotoAssetCodec.removeSource(
                    at: outgoingChange.assetSourceURL
                )
                outgoing.removeValue(forKey: Self.key(recordID, scope: scope))
                return
            } catch {
                failures.append(
                    FamilySyncTransportFailure(
                        key: outgoingChange.acknowledgement.key,
                        category: .corruptState
                    )
                )
                return
            }
        }
        if error.code == .serverRecordChanged,
            let serverRecord = error.userInfo[
                CKRecordChangedErrorServerRecordKey
            ] as? CKRecord,
            case .record(let server) = CloudKitFamilyRecordCodec.decode(serverRecord),
            validatesCloudIdentity(serverRecord, decoded: server, scope: scope)
        {
            let expected: FamilySyncRecord? = outgoingChange?.record.flatMap {
                if case .record(let record) = CloudKitFamilyRecordCodec.decode($0) {
                    return record
                }
                return nil
            }
            if let expected, Self.isInvariantConflict(expected, server) {
                quarantine(
                    serverRecord,
                    scope: scope,
                    category: .conflict,
                    envelopeData: serverRecord[
                        CloudKitFamilyRecordCodec.Schema.envelope
                    ] as? Data,
                    now: Date()
                )
            } else {
                do {
                    try metadataStore.saveSystemFields(
                        for: serverRecord,
                        scope: scope
                    )
                    _ = try metadataStore.appendInbox(
                        record: server,
                        recordID: serverRecord.recordID,
                        scope: scope,
                        receivedAt: Date()
                    )
                    requiresFetchPass = true
                } catch {
                    failures.append(
                        FamilySyncTransportFailure(
                            key: outgoingChange?.acknowledgement.key,
                            category: .corruptState
                        )
                    )
                    return
                }
            }
        }
        failures.append(
            Self.failure(key: outgoingChange?.acknowledgement.key, error: error)
        )
    }

    private static func failure(
        key: FamilySyncChangeKey?,
        error: CKError
    ) -> FamilySyncTransportFailure {
        let category: FamilySyncPrivacySafeErrorCategory
        switch error.code {
        case .networkFailure, .networkUnavailable:
            category = .connectivity
        case .requestRateLimited, .zoneBusy:
            category = .rateLimited
        case .serviceUnavailable, .internalError:
            category = .server
        case .notAuthenticated, .accountTemporarilyUnavailable:
            category = .account
        case .serverRecordChanged, .batchRequestFailed:
            category = .conflict
        default:
            category = .unknown
        }
        let retryAfter = (error.userInfo[CKErrorRetryAfterKey] as? NSNumber)?.doubleValue
        return FamilySyncTransportFailure(
            key: key,
            category: category,
            retryAfter: retryAfter
        )
    }

    private func cleanupOutgoingSources() {
        for change in outgoing.values {
            CloudKitProfilePhotoAssetCodec.removeSource(
                at: change.assetSourceURL
            )
        }
    }

    private static func key(
        _ recordID: CKRecord.ID,
        scope: CloudKitFamilyDatabaseScope
    ) -> String {
        "\(scope.rawValue)|\(recordID.zoneID.ownerName)|\(recordID.zoneID.zoneName)|\(recordID.recordName)"
    }

    private static func isInvariantConflict(
        _ first: FamilySyncRecord,
        _ second: FamilySyncRecord
    ) -> Bool {
        guard first.payloadChecksum != second.payloadChecksum else { return false }
        let immutable =
            first.kind == .attempt || first.kind == .attemptCorrection
            || second.kind == .attempt || second.kind == .attemptCorrection
        return immutable || first.logicalRevision == second.logicalRevision
    }

    private static func fetchPriority(_ record: CKRecord) -> Int {
        switch record.recordType {
        case CloudKitFamilyDeletionLedgerCodec.Schema.recordType:
            0
        case CloudKitFamilyRecordCodec.Schema.rootRecordType:
            1
        case CKRecord.SystemType.share:
            2
        default:
            3
        }
    }

    private static func isTerminal(
        _ state: ProfileCloudBindingState
    ) -> Bool {
        switch state {
        case .revoked, .ownerDeleted, .participantLeft:
            true
        case .unbound, .privateOwner, .sharedParticipant:
            false
        }
    }
}

final class CloudKitFamilySyncEngineDelegate: CKSyncEngineDelegate,
    @unchecked Sendable
{
    let scope: CloudKitFamilyDatabaseScope
    let generation: UInt64

    private let buffer: CloudKitFamilySyncEventBuffer
    private let stateStore: CloudKitFamilySyncStateStore

    init(
        scope: CloudKitFamilyDatabaseScope,
        generation: UInt64,
        buffer: CloudKitFamilySyncEventBuffer,
        stateStore: CloudKitFamilySyncStateStore
    ) {
        self.scope = scope
        self.generation = generation
        self.buffer = buffer
        self.stateStore = stateStore
    }

    func handleEvent(_ event: CKSyncEngine.Event, syncEngine: CKSyncEngine) async {
        _ = syncEngine
        guard await buffer.isActive(generation) else { return }
        switch event {
        case .stateUpdate(let update):
            // Generation validation and the file write are serialized by the
            // buffer actor. A stale delegate therefore cannot restore an old
            // account's CKSyncEngine token after the new state was cleared.
            await buffer.persistEngineState(
                update.stateSerialization,
                scope: scope,
                generation: generation,
                stateStore: stateStore
            )
        case .accountChange(let account):
            let accountEvent: CloudKitFamilyAccountEngineEvent
            switch account.changeType {
            case .signIn(let currentUser):
                accountEvent = .signedIn(recordName: currentUser.recordName)
            case .signOut:
                accountEvent = .signedOut
            case .switchAccounts:
                accountEvent = .switchedAccounts
            @unknown default:
                accountEvent = .switchedAccounts
            }
            // The generation check and metadata mutation happen in one actor
            // turn. A delegate that passed an earlier liveness check cannot
            // invalidate a newly confirmed account after engine replacement.
            await buffer.handle(
                .accountChange(accountEvent),
                scope: scope,
                generation: generation
            )
        case .fetchedRecordZoneChanges(let changes):
            await buffer.handle(
                .fetchedRecords(changes.modifications.map(\.record)),
                scope: scope,
                generation: generation
            )
            await buffer.handle(
                .fetchedDeletions(changes.deletions.map(\.recordID)),
                scope: scope,
                generation: generation
            )
        case .sentRecordZoneChanges(let changes):
            await buffer.handle(
                .sentRecords(
                    saved: changes.savedRecords,
                    failed: changes.failedRecordSaves.map { ($0.record, $0.error) }
                ),
                scope: scope,
                generation: generation
            )
            await buffer.handle(
                .sentDeletions(
                    saved: changes.deletedRecordIDs,
                    failed: changes.failedRecordDeletes.map { ($0.key, $0.value) }
                ),
                scope: scope,
                generation: generation
            )
        case .sentDatabaseChanges(let changes):
            for failed in changes.failedZoneSaves {
                await buffer.handle(
                    .operationFailure(failed.error),
                    scope: scope,
                    generation: generation
                )
            }
            for error in changes.failedZoneDeletes.values {
                await buffer.handle(
                    .operationFailure(error),
                    scope: scope,
                    generation: generation
                )
            }
        case .didFetchRecordZoneChanges(let event):
            if let error = event.error {
                await buffer.handle(
                    .operationFailure(error),
                    scope: scope,
                    generation: generation
                )
            }
        case .fetchedDatabaseChanges(let changes):
            await buffer.handle(
                .deletedZones(changes.deletions.map(\.zoneID)),
                scope: scope,
                generation: generation
            )
        case .willFetchChanges,
            .willFetchRecordZoneChanges, .didFetchChanges,
            .willSendChanges, .didSendChanges:
            break
        @unknown default:
            break
        }
    }

    func nextRecordZoneChangeBatch(
        _ context: CKSyncEngine.SendChangesContext,
        syncEngine: CKSyncEngine
    ) async -> CKSyncEngine.RecordZoneChangeBatch? {
        let pending = syncEngine.state.pendingRecordZoneChanges.filter {
            context.options.scope.contains($0)
        }
        guard
            var batch = await CKSyncEngine.RecordZoneChangeBatch(
                pendingChanges: pending,
                recordProvider: { [buffer, generation, scope] recordID in
                    await buffer.record(
                        for: recordID,
                        scope: scope,
                        generation: generation
                    )
                }
            )
        else { return nil }
        batch.atomicByZone = false
        return batch
    }
}
