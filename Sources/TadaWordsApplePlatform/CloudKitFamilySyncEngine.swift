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
    case finishedFetchingZone(CKRecordZone.ID, succeeded: Bool)
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

struct CloudKitLiveAccountVerifier: @unchecked Sendable {
    private let operation: (ProfileCloudBinding) async throws -> Void

    init(
        _ operation: @escaping (ProfileCloudBinding) async throws -> Void
    ) {
        self.operation = operation
    }

    func verify(_ binding: ProfileCloudBinding) async throws {
        try await operation(binding)
    }

    static let noOp = CloudKitLiveAccountVerifier { _ in }
}

actor CloudKitFamilySyncEventBuffer {
    private struct UnboundRoute: Hashable {
        let scope: CloudKitFamilyDatabaseScope
        let zoneName: String
        let ownerName: String

        init(
            scope: CloudKitFamilyDatabaseScope,
            zoneID: CKRecordZone.ID
        ) {
            self.scope = scope
            zoneName = zoneID.zoneName
            ownerName = zoneID.ownerName
        }
    }

    private struct StagedUnboundRecord {
        let cloudRecord: CKRecord
        let record: FamilySyncRecord
        let receivedAt: Date
    }

    private struct DeferredEngineState {
        let serialization: CKSyncEngine.State.Serialization
        let stateStore: CloudKitFamilySyncStateStore
    }

    private struct PendingConflictDisposition {
        let key: FamilySyncChangeKey
        let receiptIDs: Set<UUID>
        let candidate: CloudKitFamilyQuarantineEntry
        let quarantinedRecordCount: Int
    }

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
    private var durabilityFailureEpoch: UInt64 = 0
    private var retryableStagedResolutionFailureEpoch: UInt64?
    private var pendingConflictDispositions: [FamilySyncChangeKey: PendingConflictDisposition] = [:]
    private var requiresFetchPass = false
    private var ownerLedgerRecoveryProfileIDs = Set<ProfileID>()
    /// A newly installed device can receive child records before the Profile
    /// root that authorizes their zone. Keep those bytes process-local and
    /// withhold the CKSyncEngine cursor until the matching root either promotes
    /// them into the durable inbox or a successful per-zone fetch proves that
    /// no root exists and the records are durably quarantined.
    private var stagedUnboundRecords: [UnboundRoute: [StagedUnboundRecord]] = [:]
    private var rootlessRoutesReadyForQuarantine = Set<UnboundRoute>()
    private var deferredEngineStates: [CloudKitFamilyDatabaseScope: DeferredEngineState] = [:]
    private let metadataStore: CloudKitFamilyMetadataStore
    private let liveAccountVerifier: CloudKitLiveAccountVerifier
    private let beforePromotingStagedRecord: @Sendable (Int) -> Void

    init(
        metadataStore: CloudKitFamilyMetadataStore,
        liveAccountVerifier: CloudKitLiveAccountVerifier = .noOp,
        beforePromotingStagedRecord: @escaping @Sendable (Int) -> Void = { _ in }
    ) {
        self.metadataStore = metadataStore
        self.liveAccountVerifier = liveAccountVerifier
        self.beforePromotingStagedRecord = beforePromotingStagedRecord
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
        durabilityFailureEpoch = 0
        retryableStagedResolutionFailureEpoch = nil
        pendingConflictDispositions.removeAll()
        requiresFetchPass = false
        ownerLedgerRecoveryProfileIDs.removeAll()
        stagedUnboundRecords.removeAll()
        rootlessRoutesReadyForQuarantine.removeAll()
        deferredEngineStates.removeAll()
        return activeGeneration
    }

    func isActive(_ generation: UInt64) -> Bool {
        generation == activeGeneration
    }

    func canPersistEngineState(_ generation: UInt64) -> Bool {
        generation == activeGeneration && !durabilityFailure
            && pendingConflictDispositions.isEmpty
            && stagedUnboundRecords.isEmpty
    }

    /// A CKSyncEngine callback can advance the engine's process-local cursor
    /// before its corresponding metadata or inbox write reaches disk. When
    /// that happens, the current engines must be discarded so the next fetch
    /// starts again from the last state serialization that did reach disk.
    func requiresEngineRebuild(generation: UInt64) -> Bool {
        generation == activeGeneration && durabilityFailure
    }

    func persistEngineState(
        _ serialization: CKSyncEngine.State.Serialization,
        scope: CloudKitFamilyDatabaseScope,
        generation: UInt64,
        stateStore: CloudKitFamilySyncStateStore
    ) {
        guard generation == activeGeneration,
            !durabilityFailure,
            pendingConflictDispositions.isEmpty,
            accountChange == nil
        else { return }
        guard !hasStagedUnboundRecords(in: scope) else {
            deferredEngineStates[scope] = DeferredEngineState(
                serialization: serialization,
                stateStore: stateStore
            )
            return
        }
        deferredEngineStates.removeValue(forKey: scope)
        persistEngineStateNow(
            serialization,
            scope: scope,
            stateStore: stateStore
        )
    }

    /// Retries only the exact failed and not-yet-resolved suffix retained in
    /// memory after an inbox or quarantine write failed. This gives a live
    /// transport a recovery path even though CKSyncEngine's in-memory cursor
    /// has already consumed the callback. The durable engine token remains old
    /// until every retained candidate is durably accepted or quarantined.
    func retryStagedUnboundRecords(generation: UInt64) -> Bool {
        guard generation == activeGeneration, accountChange == nil else {
            return false
        }
        let routes = stagedUnboundRecords.keys.sorted {
            if $0.scope != $1.scope { return $0.scope.rawValue < $1.scope.rawValue }
            if $0.ownerName != $1.ownerName { return $0.ownerName < $1.ownerName }
            return $0.zoneName < $1.zoneName
        }
        guard let failureEpoch = retryableStagedResolutionFailureEpoch else {
            let hasReadyStagedResolution =
                !pendingConflictDispositions.isEmpty
                || routes.contains { route in
                    if rootlessRoutesReadyForQuarantine.contains(route) {
                        return true
                    }
                    let zoneID = CKRecordZone.ID(
                        zoneName: route.zoneName,
                        ownerName: route.ownerName
                    )
                    return metadataStore.binding(for: zoneID) != nil
                }
            if durabilityFailure, hasReadyStagedResolution {
                failures.append(
                    FamilySyncTransportFailure(key: nil, category: .corruptState)
                )
                return false
            }
            return true
        }
        guard durabilityFailure, failureEpoch == durabilityFailureEpoch else {
            failures.append(
                FamilySyncTransportFailure(key: nil, category: .corruptState)
            )
            return false
        }

        durabilityFailure = false
        retryableStagedResolutionFailureEpoch = nil
        for route in routes {
            let zoneID = CKRecordZone.ID(
                zoneName: route.zoneName,
                ownerName: route.ownerName
            )
            if rootlessRoutesReadyForQuarantine.contains(route) {
                quarantineStagedRecords(
                    for: zoneID,
                    scope: route.scope,
                    now: Date()
                )
            } else if metadataStore.binding(for: zoneID) != nil {
                promoteStagedRecords(for: zoneID, scope: route.scope)
            }
            if durabilityFailure { return false }
        }
        for pending in pendingConflictDispositions.values.sorted(by: {
            if $0.key.profileID != $1.key.profileID {
                return $0.key.profileID.description < $1.key.profileID.description
            }
            return $0.key.recordName < $1.key.recordName
        }) {
            guard pendingConflictDispositions[pending.key] != nil else { continue }
            if !persistConflictDisposition(pending) { return false }
        }
        return true
    }

    func replay(
        _ entries: [CloudKitFamilyInboxEntry],
        generation: UInt64
    ) {
        guard generation == activeGeneration, accountChange == nil else {
            return
        }
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
                        let candidate = CloudKitFamilyQuarantineEntry(
                            id: UUID(),
                            scope: entry.scope,
                            recordName: record.recordName,
                            zoneName: entry.zoneName,
                            ownerName: entry.ownerName,
                            reason: .conflict,
                            envelopeData: try? JSONEncoder().encode(
                                FamilySyncEnvelope(record: record)
                            ),
                            quarantinedAt: Date()
                        )
                        _ = beginConflictDisposition(
                            key: key,
                            receiptIDs: conflictingIDs,
                            candidate: candidate,
                            quarantinedRecordCount: conflictingIDs.count
                        )
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
    ) async {
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
                    let resolvedChange = try metadataStore.handleAccountSignIn(
                        recordName: recordName
                    )
                    accountChange = resolvedChange
                    if resolvedChange != nil {
                        sealBufferedStateForAccountBoundary()
                    }
                case .signedOut:
                    sealBufferedStateForAccountBoundary()
                    try metadataStore.handleAccountSignOut()
                    accountChange = .signedOut
                case .switchedAccounts:
                    sealBufferedStateForAccountBoundary()
                    try metadataStore.handleAccountSignOut()
                    accountChange = .switchedAccounts
                }
            } catch {
                // Account metadata is a privacy boundary. Fail closed and stop
                // state-token persistence if that boundary cannot be written.
                sealBufferedStateForAccountBoundary()
                markDurabilityFailure()
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
                guard generation == activeGeneration,
                    accountChange == nil
                else { break }
                if let binding = metadataStore.binding(
                    for: cloudRecord.recordID.zoneID
                ),
                    Self.isTerminal(binding.state)
                        || ownerLedgerRecoveryProfileIDs.contains(binding.profileID)
                {
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
                        if metadataStore.binding(for: record.profileID).state
                            == .ownerDeleted
                        {
                            continue
                        }
                        let zoneID = Self.privateZoneID(for: record.profileID)
                        let prepared =
                            try metadataStore
                            .prepareAndStageAmbiguousOwnerDeletionLedgerRecovery(
                                profileID: record.profileID,
                                zoneID: zoneID,
                                rootRecordName: Self.privateRootRecordID(
                                    for: record.profileID
                                ).recordName,
                                receivedAt: now
                            )
                        let binding = prepared.binding
                        ownerLedgerRecoveryProfileIDs.insert(record.profileID)
                        requiresFetchPass = true
                        do {
                            try await liveAccountVerifier.verify(binding)
                        } catch {
                            guard generation == activeGeneration,
                                accountChange == nil
                            else { continue }
                            throw error
                        }
                        guard generation == activeGeneration,
                            accountChange == nil
                        else { continue }
                        _ = try metadataStore.promoteAmbiguousRemoteRemoval(
                            markerID: prepared.markerID,
                            record: record
                        )
                        try metadataStore.saveSystemFields(
                            for: cloudRecord,
                            scope: scope
                        )
                    } catch CloudKitFamilyPersistenceError.accountBindingMismatch {
                        latchAccountBoundary()
                    } catch CloudKitFamilySyncError.accountBindingMismatch {
                        latchAccountBoundary()
                    } catch CloudKitFamilyPersistenceError.bindingConflict {
                        latchAccountBoundary()
                    } catch {
                        markDurabilityFailure()
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
                    handleRootRecord(cloudRecord, scope: scope, now: now)
                    continue
                }
                if cloudRecord.recordType == CKRecord.SystemType.share {
                    do {
                        try metadataStore.saveSystemFields(for: cloudRecord, scope: scope)
                    } catch {
                        markDurabilityFailure()
                        failures.append(
                            FamilySyncTransportFailure(key: nil, category: .corruptState)
                        )
                    }
                    continue
                }
                switch CloudKitFamilyRecordCodec.decode(cloudRecord) {
                case .record(let record):
                    if validatesCloudIdentity(
                        cloudRecord,
                        decoded: record,
                        scope: scope
                    ) {
                        acceptFetchedRecord(
                            cloudRecord,
                            decoded: record,
                            scope: scope,
                            now: now
                        )
                    } else if canStageUntilRoot(
                        cloudRecord,
                        decoded: record,
                        scope: scope
                    ) {
                        stageUntilRoot(
                            cloudRecord,
                            decoded: record,
                            scope: scope,
                            now: now
                        )
                    } else {
                        quarantine(
                            cloudRecord,
                            scope: scope,
                            category: .compatibility,
                            envelopeData: cloudRecord[
                                CloudKitFamilyRecordCodec.Schema.envelope
                            ] as? Data,
                            now: now
                        )
                    }
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
        case .finishedFetchingZone(let zoneID, let succeeded):
            finishFetchingZone(
                zoneID,
                scope: scope,
                succeeded: succeeded,
                generation: generation,
                now: now
            )
        case .fetchedDeletions(let recordIDs):
            for recordID in recordIDs {
                guard generation == activeGeneration,
                    accountChange == nil
                else { break }
                guard let binding = metadataStore.binding(for: recordID.zoneID) else {
                    quarantinedRecordCount += 1
                    continue
                }
                if Self.isTerminal(binding.state) {
                    guard Self.terminalBinding(binding, matches: scope) else {
                        quarantinedRecordCount += 1
                        continue
                    }
                    // The callback can have been queued before the terminal
                    // transition. Its payload has already been dominated by
                    // the durable Profile erasure and needs no receipt.
                    continue
                }
                guard binding.databaseScope == scope else {
                    quarantinedRecordCount += 1
                    continue
                }
                if ownerLedgerRecoveryProfileIDs.contains(binding.profileID) {
                    continue
                }
                if recordID.recordName == binding.rootRecordName {
                    do {
                        try await stageRootProfileRemoval(
                            profileID: binding.profileID,
                            recordID: recordID,
                            scope: scope,
                            now: now,
                            generation: generation
                        )
                    } catch CloudKitFamilyPersistenceError.accountBindingMismatch {
                        latchAccountBoundary()
                        break
                    } catch CloudKitFamilySyncError.accountBindingMismatch {
                        latchAccountBoundary()
                        break
                    } catch CloudKitFamilyPersistenceError.bindingConflict {
                        quarantinedRecordCount += 1
                    } catch {
                        markDurabilityFailure()
                        failures.append(
                            FamilySyncTransportFailure(
                                key: nil,
                                category: .corruptState
                            )
                        )
                    }
                    continue
                }
                guard
                    metadataStore.isBindingAuthorizedForConfirmedAccount(binding)
                else {
                    // Child deletions carry no privacy-minimal recovery route.
                    // Unlike the root callback above, they cannot be staged
                    // safely across an unobserved account boundary.
                    latchAccountBoundary()
                    break
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
                    markDurabilityFailure()
                    failures.append(
                        FamilySyncTransportFailure(key: key, category: .corruptState)
                    )
                    continue
                }
                try? metadataStore.removeSystemFields(id: recordID, scope: scope)
            }
        case .deletedZones(let zoneIDs):
            for zoneID in zoneIDs {
                guard generation == activeGeneration,
                    accountChange == nil
                else { break }
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
                    try await stageProvenZoneProfileRemoval(
                        profileID: binding.profileID,
                        recordID: recordID,
                        scope: scope,
                        now: now,
                        generation: generation
                    )
                } catch CloudKitFamilyPersistenceError.accountBindingMismatch {
                    latchAccountBoundary()
                    break
                } catch CloudKitFamilySyncError.accountBindingMismatch {
                    latchAccountBoundary()
                    break
                } catch CloudKitFamilyPersistenceError.bindingConflict {
                    quarantinedRecordCount += 1
                } catch {
                    markDurabilityFailure()
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
                    markDurabilityFailure()
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
                    markDurabilityFailure()
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
        let blockedConflictKeys = Set(pendingConflictDispositions.keys)
        let blockedConflictReceiptIDs = pendingConflictDispositions.values.reduce(
            into: Set<UUID>()
        ) { partial, pending in
            partial.formUnion(pending.receiptIDs)
        }
        let result = FamilySyncTransportResult(
            records: incoming.filter {
                !blockedConflictKeys.contains($0.key)
            }.map(\.value).sorted { lhs, rhs in
                if lhs.profileID != rhs.profileID {
                    return lhs.profileID.description < rhs.profileID.description
                }
                return lhs.recordName < rhs.recordName
            },
            deletions: deletions.filter {
                !blockedConflictKeys.contains($0)
            }.map(FamilySyncRemoteDeletion.init),
            acknowledged: acknowledgements,
            failures: failures,
            accountChange: accountChange,
            quarantinedRecordCount: quarantinedRecordCount,
            receiptIDs: receiptIDs.subtracting(blockedConflictReceiptIDs),
            receipts: receipts.values.filter {
                !blockedConflictReceiptIDs.contains($0.id)
                    && !blockedConflictKeys.contains($0.key)
            }.sorted {
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
        ownerLedgerRecoveryProfileIDs.removeAll()
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
        markDurabilityFailure()
        failures.append(
            FamilySyncTransportFailure(key: nil, category: .corruptState)
        )
    }

    @discardableResult
    private func quarantine(
        _ record: CKRecord,
        scope: CloudKitFamilyDatabaseScope,
        category: FamilySyncPrivacySafeErrorCategory,
        envelopeData: Data?,
        now: Date
    ) -> Bool {
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
            return true
        } catch {
            markDurabilityFailure()
            failures.append(FamilySyncTransportFailure(key: nil, category: .corruptState))
            return false
        }
    }

    private func stageProvenZoneProfileRemoval(
        profileID: ProfileID,
        recordID: CKRecord.ID,
        scope: CloudKitFamilyDatabaseScope,
        now: Date,
        generation: UInt64
    ) async throws {
        let binding = metadataStore.binding(for: profileID)
        let bindingMatchesScope: Bool =
            switch (scope, binding.state) {
            case (.privateDatabase, .privateOwner),
                (.privateDatabase, .ownerDeleted),
                (.sharedDatabase, .sharedParticipant),
                (.sharedDatabase, .revoked),
                (.sharedDatabase, .participantLeft):
                true
            default:
                false
            }
        guard binding.zoneID == recordID.zoneID,
            bindingMatchesScope
        else {
            throw CloudKitFamilyPersistenceError.accountBindingMismatch
        }
        guard !Self.isTerminal(binding.state) else { return }
        let markerID = try metadataStore.stageAmbiguousRemoteRemoval(
            profileID: profileID,
            recordID: recordID,
            scope: scope,
            evidence: .zoneDeletion,
            receivedAt: now
        )
        ownerLedgerRecoveryProfileIDs.insert(profileID)
        requiresFetchPass = true
        do {
            try await liveAccountVerifier.verify(binding)
        } catch {
            guard generation == activeGeneration, accountChange == nil else {
                return
            }
            throw error
        }
        guard generation == activeGeneration, accountChange == nil else {
            // A same-account rebuild or account switch won the actor race.
            // The marker remains durable for the new generation to revalidate.
            return
        }
        let record = try terminalProfileRemovalRecord(profileID: profileID)
        _ = try metadataStore.promoteAmbiguousRemoteRemoval(
            markerID: markerID,
            record: record
        )
    }

    private func stageRootProfileRemoval(
        profileID: ProfileID,
        recordID: CKRecord.ID,
        scope: CloudKitFamilyDatabaseScope,
        now: Date,
        generation: UInt64
    ) async throws {
        let binding = metadataStore.binding(for: profileID)
        guard binding.zoneID == recordID.zoneID,
            binding.rootRecordID == recordID,
            binding.databaseScope == scope,
            !Self.isTerminal(binding.state)
        else {
            throw CloudKitFamilyPersistenceError.bindingConflict
        }
        let markerID = try metadataStore.stageAmbiguousRemoteRemoval(
            profileID: profileID,
            recordID: recordID,
            scope: scope,
            evidence: .rootRecordDeletion,
            receivedAt: now
        )
        ownerLedgerRecoveryProfileIDs.insert(profileID)
        requiresFetchPass = true
        do {
            try await liveAccountVerifier.verify(binding)
        } catch {
            guard generation == activeGeneration, accountChange == nil else {
                return
            }
            throw error
        }
        guard generation == activeGeneration, accountChange == nil else {
            return
        }
        let record = try terminalProfileRemovalRecord(profileID: profileID)
        _ = try metadataStore.promoteAmbiguousRemoteRemoval(
            markerID: markerID,
            record: record
        )
    }

    private func terminalProfileRemovalRecord(
        profileID: ProfileID
    ) throws -> FamilySyncRecord {
        try CloudKitRemoteProfileRemovalRecordFactory.record(for: profileID)
    }

    private func canStageUntilRoot(
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
            let parentRecordID = cloudRecord.parent?.recordID,
            parentRecordID.zoneID == cloudRecord.recordID.zoneID,
            CloudKitDeterministicProfileRoute.matches(
                profileID: record.profileID,
                zoneName: cloudRecord.recordID.zoneID.zoneName,
                rootRecordName: parentRecordID.recordName
            ),
            metadataStore.binding(for: record.profileID).state == .unbound,
            !metadataStore.hasPersistedBinding(for: record.profileID),
            metadataStore.binding(for: cloudRecord.recordID.zoneID) == nil
        else { return false }
        if scope == .privateDatabase,
            cloudRecord.recordID.zoneID.ownerName != CKCurrentUserDefaultName
        {
            return false
        }
        if let schema = cloudRecord[
            CloudKitFamilyRecordCodec.Schema.schemaVersion
        ] as? NSNumber,
            schema.intValue != record.schemaVersion
        {
            return false
        }
        return true
    }

    private func stageUntilRoot(
        _ cloudRecord: CKRecord,
        decoded record: FamilySyncRecord,
        scope: CloudKitFamilyDatabaseScope,
        now: Date
    ) {
        let route = UnboundRoute(
            scope: scope,
            zoneID: cloudRecord.recordID.zoneID
        )
        if stagedUnboundRecords[route, default: []].contains(where: {
            $0.cloudRecord.recordID == cloudRecord.recordID
                && $0.record == record
        }) {
            return
        }
        stagedUnboundRecords[route, default: []].append(
            StagedUnboundRecord(
                cloudRecord: cloudRecord,
                record: record,
                receivedAt: now
            )
        )
    }

    @discardableResult
    private func beginConflictDisposition(
        key: FamilySyncChangeKey,
        receiptIDs: Set<UUID>,
        candidate: CloudKitFamilyQuarantineEntry,
        quarantinedRecordCount: Int
    ) -> Bool {
        let pending = PendingConflictDisposition(
            key: key,
            receiptIDs: receiptIDs,
            candidate: candidate,
            quarantinedRecordCount: quarantinedRecordCount
        )
        pendingConflictDispositions[key] = pending
        return persistConflictDisposition(pending)
    }

    private func persistConflictDisposition(
        _ pending: PendingConflictDisposition
    ) -> Bool {
        do {
            try metadataStore.quarantineConflict(
                receiptIDs: pending.receiptIDs,
                candidate: pending.candidate
            )
        } catch {
            markDurabilityFailure()
            retryableStagedResolutionFailureEpoch = durabilityFailureEpoch
            failures.append(
                FamilySyncTransportFailure(
                    key: pending.key,
                    category: .corruptState
                )
            )
            return false
        }

        // Only the atomic metadata commit authorizes removal from the
        // process-visible batch. Before that point drain() filters this key but
        // retains the exact receipt/candidate context above for retry.
        pendingConflictDispositions.removeValue(forKey: pending.key)
        incoming.removeValue(forKey: pending.key)
        deletions.remove(pending.key)
        receiptIDs.subtract(pending.receiptIDs)
        for id in pending.receiptIDs {
            receipts.removeValue(forKey: id)
        }
        quarantinedRecordCount += pending.quarantinedRecordCount
        return true
    }

    @discardableResult
    private func acceptFetchedRecord(
        _ cloudRecord: CKRecord,
        decoded record: FamilySyncRecord,
        scope: CloudKitFamilyDatabaseScope,
        now: Date
    ) -> Bool {
        let key = FamilySyncChangeKey(
            profileID: record.profileID,
            recordName: record.recordName
        )
        if let pending = pendingConflictDispositions[key] {
            guard !durabilityFailure else { return false }
            return persistConflictDisposition(pending)
        }
        if metadataStore.isConflictQuarantined(
            recordID: cloudRecord.recordID,
            scope: scope
        ) {
            // The record ID already has a durable invariant-conflict
            // disposition. Every replayed or later variant is covered by that
            // same fail-closed lock and must never re-enter the inbox.
            quarantinedRecordCount += 1
            return true
        }
        if let existing = incoming[key],
            Self.isInvariantConflict(existing, record)
        {
            let existingReceiptIDs = Set(
                receipts.values.filter { $0.key == key }.map(\.id)
            )
            let candidate = CloudKitFamilyQuarantineEntry(
                id: UUID(),
                scope: scope,
                recordName: cloudRecord.recordID.recordName,
                zoneName: cloudRecord.recordID.zoneID.zoneName,
                ownerName: cloudRecord.recordID.zoneID.ownerName,
                reason: .conflict,
                envelopeData: cloudRecord[
                    CloudKitFamilyRecordCodec.Schema.envelope
                ] as? Data,
                quarantinedAt: now
            )
            return beginConflictDisposition(
                key: key,
                receiptIDs: existingReceiptIDs,
                candidate: candidate,
                quarantinedRecordCount: existingReceiptIDs.count + 1
            )
        }
        do {
            try metadataStore.saveSystemFields(for: cloudRecord, scope: scope)
            let receiptID = try metadataStore.appendInboxReplacingQuarantine(
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
            markDurabilityFailure()
            failures.append(
                FamilySyncTransportFailure(key: nil, category: .corruptState)
            )
            return false
        }
        incoming[key] = FamilySyncConflictResolver.resolved(
            local: incoming[key],
            remote: record
        )
        return true
    }

    private func handleRootRecord(
        _ record: CKRecord,
        scope: CloudKitFamilyDatabaseScope,
        now: Date
    ) {
        guard
            let profileString = record[
                CloudKitFamilyRecordCodec.Schema.profileID
            ] as? String,
            let profileUUID = UUID(uuidString: profileString),
            record.parent == nil
        else {
            quarantine(
                record,
                scope: scope,
                category: .compatibility,
                envelopeData: nil,
                now: now
            )
            return
        }
        let profileID = ProfileID(rawValue: profileUUID)
        guard
            CloudKitDeterministicProfileRoute.matches(
                profileID: profileID,
                zoneName: record.recordID.zoneID.zoneName,
                rootRecordName: record.recordID.recordName
            ),
            scope != .privateDatabase
                || record.recordID.zoneID.ownerName == CKCurrentUserDefaultName
        else {
            quarantine(
                record,
                scope: scope,
                category: .compatibility,
                envelopeData: nil,
                now: now
            )
            return
        }
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
                now: now
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
            promoteStagedRecords(
                for: record.recordID.zoneID,
                scope: scope
            )
        } catch CloudKitFamilyPersistenceError.accountBindingMismatch {
            // A root fetched under a replacement Apple Account cannot claim a
            // Profile whose durable route belongs to the origin account.
            // Keep the old binding intact and surface only a privacy-safe
            // account category; never quarantine or log either account ID.
            latchAccountBoundary()
        } catch CloudKitFamilyPersistenceError.bindingConflict {
            quarantine(
                record,
                scope: scope,
                category: .conflict,
                envelopeData: nil,
                now: now
            )
        } catch {
            markDurabilityFailure()
            failures.append(FamilySyncTransportFailure(key: nil, category: .corruptState))
        }
    }

    private func promoteStagedRecords(
        for zoneID: CKRecordZone.ID,
        scope: CloudKitFamilyDatabaseScope
    ) {
        let route = UnboundRoute(scope: scope, zoneID: zoneID)
        guard !durabilityFailure else { return }
        guard let staged = stagedUnboundRecords[route] else {
            flushDeferredEngineStateIfUnblocked(for: scope)
            return
        }
        rootlessRoutesReadyForQuarantine.remove(route)
        for (index, candidate) in staged.enumerated() {
            beforePromotingStagedRecord(index)
            let resolved: Bool
            guard
                validatesCloudIdentity(
                    candidate.cloudRecord,
                    decoded: candidate.record,
                    scope: scope
                )
            else {
                resolved = quarantine(
                    candidate.cloudRecord,
                    scope: scope,
                    category: .compatibility,
                    envelopeData: candidate.cloudRecord[
                        CloudKitFamilyRecordCodec.Schema.envelope
                    ] as? Data,
                    now: candidate.receivedAt
                )
                if !resolved {
                    retainFailedStagedSuffix(
                        staged,
                        from: index,
                        route: route
                    )
                    return
                }
                continue
            }
            resolved = acceptFetchedRecord(
                candidate.cloudRecord,
                decoded: candidate.record,
                scope: scope,
                now: candidate.receivedAt
            )
            if !resolved {
                retainFailedStagedSuffix(
                    staged,
                    from: index,
                    route: route
                )
                return
            }
        }
        stagedUnboundRecords.removeValue(forKey: route)
        flushDeferredEngineStateIfUnblocked(for: scope)
    }

    private func finishFetchingZone(
        _ zoneID: CKRecordZone.ID,
        scope: CloudKitFamilyDatabaseScope,
        succeeded: Bool,
        generation: UInt64,
        now: Date
    ) {
        guard generation == activeGeneration, accountChange == nil else { return }
        let route = UnboundRoute(scope: scope, zoneID: zoneID)
        guard succeeded else {
            // A failed zone fetch is retryable. Keep the process-local candidate
            // and the old durable token until CKSyncEngine retries this zone.
            return
        }
        if metadataStore.binding(for: zoneID) != nil {
            promoteStagedRecords(for: zoneID, scope: scope)
            return
        }
        rootlessRoutesReadyForQuarantine.insert(route)
        quarantineStagedRecords(for: zoneID, scope: scope, now: now)
    }

    private func quarantineStagedRecords(
        for zoneID: CKRecordZone.ID,
        scope: CloudKitFamilyDatabaseScope,
        now: Date
    ) {
        let route = UnboundRoute(scope: scope, zoneID: zoneID)
        guard !durabilityFailure else { return }
        guard let unresolved = stagedUnboundRecords[route] else {
            rootlessRoutesReadyForQuarantine.remove(route)
            flushDeferredEngineStateIfUnblocked(for: scope)
            return
        }
        for (index, candidate) in unresolved.enumerated() {
            guard
                quarantine(
                    candidate.cloudRecord,
                    scope: scope,
                    category: .compatibility,
                    envelopeData: candidate.cloudRecord[
                        CloudKitFamilyRecordCodec.Schema.envelope
                    ] as? Data,
                    now: now
                )
            else {
                retainFailedStagedSuffix(
                    unresolved,
                    from: index,
                    route: route
                )
                return
            }
        }
        stagedUnboundRecords.removeValue(forKey: route)
        rootlessRoutesReadyForQuarantine.remove(route)
        // Only a successful per-zone boundary may classify a deterministic but
        // rootless candidate as hostile. Quarantine is durable before the token
        // that skips those bytes is allowed to advance.
        flushDeferredEngineStateIfUnblocked(for: scope)
    }

    private func retainFailedStagedSuffix(
        _ staged: [StagedUnboundRecord],
        from failedIndex: Int,
        route: UnboundRoute
    ) {
        stagedUnboundRecords[route] = Array(staged[failedIndex...])
        retryableStagedResolutionFailureEpoch = durabilityFailureEpoch
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
            binding.databaseScope == scope,
            let expectedRootRecordID = binding.rootRecordID,
            cloudRecord.parent?.recordID == expectedRootRecordID,
            metadataStore.isBindingAuthorizedForConfirmedAccount(binding)
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
                markDurabilityFailure()
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
                    markDurabilityFailure()
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

    private func markDurabilityFailure() {
        durabilityFailure = true
        durabilityFailureEpoch &+= 1
    }

    private func hasStagedUnboundRecords(
        in scope: CloudKitFamilyDatabaseScope
    ) -> Bool {
        stagedUnboundRecords.keys.contains { $0.scope == scope }
    }

    private func flushDeferredEngineStateIfUnblocked(
        for scope: CloudKitFamilyDatabaseScope
    ) {
        guard !hasStagedUnboundRecords(in: scope),
            !durabilityFailure,
            accountChange == nil,
            let deferred = deferredEngineStates.removeValue(forKey: scope)
        else { return }
        persistEngineStateNow(
            deferred.serialization,
            scope: scope,
            stateStore: deferred.stateStore
        )
    }

    private func persistEngineStateNow(
        _ serialization: CKSyncEngine.State.Serialization,
        scope: CloudKitFamilyDatabaseScope,
        stateStore: CloudKitFamilySyncStateStore
    ) {
        guard stateStore.save(serialization, scope: scope) else {
            markDurabilityFailure()
            failures.append(
                FamilySyncTransportFailure(key: nil, category: .corruptState)
            )
            return
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

    private func latchAccountBoundary() {
        accountChange = .switchedAccounts
        sealBufferedStateForAccountBoundary()
    }

    private func sealBufferedStateForAccountBoundary() {
        incoming.removeAll()
        deletions.removeAll()
        acknowledgements.removeAll()
        receiptIDs.removeAll()
        receipts.removeAll()
        requiresFetchPass = false
        ownerLedgerRecoveryProfileIDs.removeAll()
        stagedUnboundRecords.removeAll()
        rootlessRoutesReadyForQuarantine.removeAll()
        retryableStagedResolutionFailureEpoch = nil
        pendingConflictDispositions.removeAll()
        deferredEngineStates.removeAll()
        cleanupOutgoingSources()
        outgoing.removeAll()
    }

    private static func terminalBinding(
        _ binding: ProfileCloudBinding,
        matches scope: CloudKitFamilyDatabaseScope
    ) -> Bool {
        switch (binding.erasureRoute, scope) {
        case (.owner, .privateDatabase),
            (.participant, .sharedDatabase):
            true
        case (.owner, .sharedDatabase),
            (.participant, .privateDatabase),
            (.unresolved, _):
            false
        }
    }

    private static func privateZoneID(for profileID: ProfileID) -> CKRecordZone.ID {
        CKRecordZone.ID(
            zoneName: "TadaProfile-\(profileID.rawValue.uuidString)",
            ownerName: CKCurrentUserDefaultName
        )
    }

    private static func privateRootRecordID(for profileID: ProfileID) -> CKRecord.ID {
        CKRecord.ID(
            recordName: "profile-root-\(profileID.rawValue.uuidString)",
            zoneID: privateZoneID(for: profileID)
        )
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
            await buffer.handle(
                .finishedFetchingZone(
                    event.zoneID,
                    succeeded: event.error == nil
                ),
                scope: scope,
                generation: generation
            )
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
