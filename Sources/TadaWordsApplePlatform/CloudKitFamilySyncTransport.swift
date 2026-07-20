@preconcurrency import CloudKit
import Foundation
import TadaWordsDomain

public enum CloudKitFamilySyncError: Error, Sendable {
    case unavailable(FamilySyncAvailability)
    case malformedRecord(String)
    case missingShareURL
    case sharedBindingRevoked
    case accountBindingMismatch
    case accountConfirmationRequired(FamilySyncAccountChange)
    case operationFailed(String)
}

/// Makes the owner-ledger recovery barrier explicit and testable. The remote
/// payload zone must be absent before a terminal binding can ever be written;
/// receipt plus terminal route are committed atomically after that proof.
struct CloudKitOwnerDeletionRecoveryExecutor {
    func recover<T>(
        isolation: isolated (any Actor) = #isolation,
        verifyOriginAccount: () async throws -> Void,
        persistLedger: () async throws -> Void,
        eraseZone: () async throws -> Void,
        purgeLocalSources: () throws -> Void,
        commitRecovery: () throws -> T
    ) async throws -> T {
        _ = isolation
        try await verifyOriginAccount()
        try await persistLedger()
        // Fence both sides of the durable ledger stage and again immediately
        // before the destructive zone request. These deliberately separate
        // checks close account switches at either suspension boundary.
        try await verifyOriginAccount()
        try await verifyOriginAccount()
        try await eraseZone()
        try await verifyOriginAccount()
        try purgeLocalSources()
        // The metadata commit rechecks the persisted binding under its lock;
        // this live-account check additionally closes a switch during purge.
        try await verifyOriginAccount()
        return try commitRecovery()
    }

    func recover(
        isolation: isolated (any Actor) = #isolation,
        eraseZone: () async throws -> Void,
        commitRecovery: () throws -> UUID
    ) async throws -> UUID {
        _ = isolation
        try await eraseZone()
        return try commitRecovery()
    }
}

struct CloudKitParticipantLeaveExecutor {
    func leave<T>(
        isolation: isolated (any Actor) = #isolation,
        verifyOriginAccount: () async throws -> Void,
        leaveShare: () async throws -> Void,
        purgeLocalSources: () throws -> Void,
        commit: () throws -> T
    ) async throws -> T {
        _ = isolation
        try await verifyOriginAccount()
        try await leaveShare()
        try await verifyOriginAccount()
        try purgeLocalSources()
        try await verifyOriginAccount()
        return try commit()
    }
}

struct CloudKitProvenZoneDeletionRecoveryExecutor {
    func recover<T>(
        isolation: isolated (any Actor) = #isolation,
        verifyOriginAccount: () async throws -> Void,
        purgeLocalSources: () throws -> Void,
        commit: () throws -> T
    ) async throws -> T {
        _ = isolation
        try await verifyOriginAccount()
        try purgeLocalSources()
        try await verifyOriginAccount()
        return try commit()
    }
}

/// CloudKit batch APIs return per-item proof. A successful outer call is not
/// evidence that the requested zone/record deletion was committed, and a
/// missing dictionary entry must therefore fail closed.
enum CloudKitTerminalDeletionProof {
    static func require(
        _ result: Result<Void, any Error>?,
        acceptingAbsenceCodes: Set<CKError.Code>,
        operation: String
    ) throws {
        guard let result else {
            throw CloudKitFamilySyncError.operationFailed(operation)
        }
        switch result {
        case .success:
            return
        case .failure(let error):
            if let cloudError = error as? CKError,
                acceptingAbsenceCodes.contains(cloudError.code)
            {
                return
            }
            throw error
        }
    }
}

/// Decodes an exact CloudKit owner-ledger fetch. Every requested record must
/// have an explicit per-item result; an absent dictionary entry or outer
/// operation failure is not proof that a privacy deletion ledger is absent.
enum CloudKitOwnerDeletionLedgerFetchProof {
    static func records(
        requestedRecordIDs: [CKRecord.ID],
        results: [CKRecord.ID: Result<CKRecord, any Error>]
    ) throws -> [FamilySyncRecord] {
        var records: [FamilySyncRecord] = []
        for recordID in requestedRecordIDs {
            guard let result = results[recordID] else {
                throw CloudKitFamilySyncError.operationFailed(
                    "Missing deletion-ledger result for \(recordID.recordName)"
                )
            }
            switch result {
            case .success(let ledger):
                guard
                    let record =
                        CloudKitFamilyDeletionLedgerCodec.familyRecord(from: ledger),
                    CloudKitFamilyDeletionLedgerCodec.recordID(
                        for: record.profileID
                    ) == recordID
                else {
                    throw CloudKitFamilySyncError.malformedRecord(
                        recordID.recordName
                    )
                }
                records.append(record)
            case .failure(let error):
                if let cloudError = error as? CKError,
                    cloudError.code == .unknownItem
                        || cloudError.code == .zoneNotFound
                {
                    continue
                }
                throw error
            }
        }
        return records.sorted {
            $0.profileID.description < $1.profileID.description
        }
    }
}

enum CloudKitRemoteRootRevalidationProof: Equatable, Sendable {
    case exists
    case rootMissing
    case zoneMissing
}

enum CloudKitRemoteRootFetchProof {
    static func proof(
        _ result: Result<CKRecord, any Error>?,
        scope: CloudKitFamilyDatabaseScope,
        recordID: CKRecord.ID
    ) throws -> CloudKitRemoteRootRevalidationProof {
        guard let result else {
            throw CloudKitFamilySyncError.operationFailed(
                "Missing root revalidation result for \(recordID.recordName)"
            )
        }
        switch result {
        case .success:
            return .exists
        case .failure(let error):
            guard let cloudError = error as? CKError else { throw error }
            switch cloudError.code {
            case .unknownItem:
                return .rootMissing
            case .zoneNotFound:
                return .zoneMissing
            case .permissionFailure where scope == .sharedDatabase:
                return .zoneMissing
            default:
                throw error
            }
        }
    }
}

struct CloudKitAmbiguousRemoteRemovalRecoveryExecutor {
    func resolve(
        isolation: isolated (any Actor) = #isolation,
        verifyOriginAccount: () async throws -> Void,
        fetchRootProof: () async throws -> CloudKitRemoteRootRevalidationProof,
        discardMarker: () throws -> Void,
        recoverRootMissing: () async throws -> Void,
        recoverZoneMissing: () async throws -> Void
    ) async throws -> Bool {
        _ = isolation
        try await verifyOriginAccount()
        let proof = try await fetchRootProof()
        // A same-named private zone under a replacement account can report
        // unknownItem. Recheck the live identity before interpreting absence.
        try await verifyOriginAccount()
        switch proof {
        case .exists:
            try discardMarker()
            return false
        case .rootMissing:
            try await recoverRootMissing()
            return true
        case .zoneMissing:
            try await recoverZoneMissing()
            return true
        }
    }
}

/// One persistent CKSyncEngine per CloudKit database. The engine delegates
/// translate CloudKit callbacks into deterministic, unit-testable events; they
/// never start nested fetch/send operations.
public actor CloudKitFamilySyncTransport: FamilySyncTransport {
    public nonisolated let capability = FamilySyncCapability.iCloud

    private let container: CKContainer
    private let privateDatabase: CKDatabase
    private let sharedDatabase: CKDatabase
    private let metadataStore: CloudKitFamilyMetadataStore
    private let stateStore: CloudKitFamilySyncStateStore
    private let eventBuffer: CloudKitFamilySyncEventBuffer
    private let photoAssetSourceDirectory: URL

    private var privateDelegate: CloudKitFamilySyncEngineDelegate
    private var sharedDelegate: CloudKitFamilySyncEngineDelegate
    private var privateEngine: CKSyncEngine
    private var sharedEngine: CKSyncEngine

    public init(
        containerIdentifier: String = "iCloud.com.tadawords.app",
        stateDirectory: URL? = nil
    ) {
        let container = CKContainer(identifier: containerIdentifier)
        let resolvedDirectory = stateDirectory ?? Self.defaultStateDirectory()
        let metadataStore = CloudKitFamilyMetadataStore(
            snapshotURL: resolvedDirectory.appendingPathComponent(
                "cloudkit-sync-metadata.json"
            )
        )
        let stateStore = CloudKitFamilySyncStateStore(directory: resolvedDirectory)
        let photoAssetSourceDirectory = resolvedDirectory.appendingPathComponent(
            "profile-photo-asset-sources",
            isDirectory: true
        )
        // CKSyncEngine pending item changes are reconstructed from the durable
        // family journal after launch. Any source left by a process crash can
        // therefore be removed and deterministically staged again.
        try? CloudKitProfilePhotoAssetCodec.removeAbandonedSources(
            in: photoAssetSourceDirectory
        )
        let eventBuffer = CloudKitFamilySyncEventBuffer(
            metadataStore: metadataStore,
            liveAccountVerifier: CloudKitLiveAccountVerifier { binding in
                guard let origin = binding.originAccountRecordName,
                    metadataStore.isBindingAuthorizedForConfirmedAccount(binding)
                else {
                    throw CloudKitFamilySyncError.accountBindingMismatch
                }
                let current = try await container.userRecordID()
                guard current.recordName == origin,
                    metadataStore.isBindingAuthorizedForConfirmedAccount(binding)
                else {
                    throw CloudKitFamilySyncError.accountBindingMismatch
                }
            }
        )
        let privateDelegate = CloudKitFamilySyncEngineDelegate(
            scope: .privateDatabase,
            generation: 1,
            buffer: eventBuffer,
            stateStore: stateStore
        )
        let sharedDelegate = CloudKitFamilySyncEngineDelegate(
            scope: .sharedDatabase,
            generation: 1,
            buffer: eventBuffer,
            stateStore: stateStore
        )

        self.container = container
        privateDatabase = container.privateCloudDatabase
        sharedDatabase = container.sharedCloudDatabase
        self.metadataStore = metadataStore
        self.stateStore = stateStore
        self.eventBuffer = eventBuffer
        self.photoAssetSourceDirectory = photoAssetSourceDirectory
        self.privateDelegate = privateDelegate
        self.sharedDelegate = sharedDelegate
        privateEngine = Self.makeEngine(
            database: container.privateCloudDatabase,
            serialization: stateStore.load(.privateDatabase),
            delegate: privateDelegate,
            subscriptionID: "tada-family-private-v2"
        )
        sharedEngine = Self.makeEngine(
            database: container.sharedCloudDatabase,
            serialization: stateStore.load(.sharedDatabase),
            delegate: sharedDelegate,
            subscriptionID: "tada-family-shared-v2"
        )
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

    public func confirmCurrentAccount() async throws -> FamilySyncAccountChange? {
        try await requireAvailability()
        let account = try await container.userRecordID()
        await cancelEngines()
        // Invalidate old delegates before clearing/authorizing metadata so a
        // late callback cannot append previous-account bytes after the seal.
        _ = await eventBuffer.nextGeneration()
        try stateStore.clear()
        let accountChange = try metadataStore.confirm(
            accountRecordName: account.recordName
        )
        await rebuildEngines()
        return accountChange
    }

    public func suspend() async {
        await cancelEngines()
        try? metadataStore.requireAccountConfirmation()
        do {
            try stateStore.clear()
            await rebuildEngines()
        } catch {
            await eventBuffer.noteStatePersistenceFailure(
                privateDelegate.generation
            )
        }
    }

    public func prepareProfileZone(_ profileID: ProfileID) async throws {
        try await requireAuthorizedAccount()
        _ = try await binding(for: profileID)
    }

    public func fetchRecords(
        for profileID: ProfileID
    ) async throws -> [FamilySyncRecord] {
        try await fetchChanges(for: [profileID]).records.filter {
            $0.profileID == profileID
        }
    }

    public func push(
        _ records: [FamilySyncRecord],
        for profileID: ProfileID
    ) async throws {
        let result = try await sendChanges(
            records.map(FamilySyncPendingOperation.save)
        )
        if let failure = result.failures.first {
            throw CloudKitFamilySyncError.operationFailed(failure.category.rawValue)
        }
    }

    public func exchange(
        _ batch: FamilySyncTransportBatch
    ) async throws -> FamilySyncTransportResult {
        let fetched = try await fetchChanges(for: batch.profileIDs)
        if !fetched.records.isEmpty || !fetched.deletions.isEmpty
            || fetched.accountChange != nil || !fetched.receiptIDs.isEmpty
            || !fetched.failures.isEmpty || fetched.quarantinedRecordCount > 0
        {
            return fetched
        }
        return try await sendChanges(batch.changes)
    }

    public func fetchChanges(
        for profileIDs: [ProfileID]
    ) async throws -> FamilySyncTransportResult {
        try await fetchChanges(
            for: profileIDs,
            terminalProfileIDs: []
        )
    }

    public func fetchChanges(
        for profileIDs: [ProfileID],
        terminalProfileIDs: Set<ProfileID>
    ) async throws -> FamilySyncTransportResult {
        if let accountChange = try await accountChangeBlockingUpload() {
            return FamilySyncTransportResult(accountChange: accountChange)
        }
        let requestedProfileIDs = Set(profileIDs)

        var recoveredStagedRemoval = false
        for marker
            in try metadataStore
            .pendingAmbiguousRemoteRemovalRevalidations()
        {
            let binding = metadataStore.binding(for: marker.profileID)
            if binding.state == .ownerDeleted
                || binding.state == .revoked
                || binding.state == .participantLeft
            {
                continue
            }
            switch marker.evidence {
            case .ownerDeletionLedger:
                try await revalidateAmbiguousOwnerDeletionLedger(
                    marker,
                    binding: binding
                )
            case .rootRecordDeletion, .zoneDeletion:
                let terminal = try await recoverAmbiguousRemoteRemoval(
                    marker,
                    binding: binding
                )
                recoveredStagedRemoval = recoveredStagedRemoval || terminal
            }
        }

        for recovery in try metadataStore.pendingOwnerDeletionLedgerRecoveries() {
            guard let zoneID = recovery.binding.zoneID else {
                throw CloudKitFamilySyncError.operationFailed(
                    "Owner deletion recovery route is incomplete"
                )
            }
            _ = try await CloudKitOwnerDeletionRecoveryExecutor().recover(
                verifyOriginAccount: {
                    try await self.requireCurrentAccountMatchesOrigin(
                        recovery.binding
                    )
                },
                persistLedger: {},
                eraseZone: {
                    try await self.eraseOwnerPayloadZone(
                        zoneID,
                        binding: recovery.binding
                    )
                },
                purgeLocalSources: {
                    try CloudKitProfilePhotoAssetCodec.removeSources(
                        for: recovery.record.profileID,
                        in: self.photoAssetSourceDirectory
                    )
                },
                commitRecovery: {
                    try self.metadataStore.commitOwnerDeletionLedgerRecovery(
                        record: recovery.record,
                        recordID: recovery.recordID,
                        previous: recovery.binding,
                        receivedAt: recovery.receivedAt
                    )
                }
            )
            recoveredStagedRemoval = true
        }

        for recovery in try metadataStore.pendingRemoteRootRemovalRecoveries() {
            switch recovery.binding.erasureRoute {
            case .owner:
                guard let zoneID = recovery.binding.zoneID else {
                    throw CloudKitFamilySyncError.operationFailed(
                        "Root deletion recovery route is incomplete"
                    )
                }
                _ = try await CloudKitOwnerDeletionRecoveryExecutor().recover(
                    verifyOriginAccount: {
                        try await self.requireCurrentAccountMatchesOrigin(
                            recovery.binding
                        )
                    },
                    persistLedger: {},
                    eraseZone: {
                        try await self.eraseOwnerPayloadZone(
                            zoneID,
                            binding: recovery.binding
                        )
                    },
                    purgeLocalSources: {
                        try CloudKitProfilePhotoAssetCodec.removeSources(
                            for: recovery.record.profileID,
                            in: self.photoAssetSourceDirectory
                        )
                    },
                    commitRecovery: {
                        try self.metadataStore.commitRemoteProfileRemoval(
                            record: recovery.record,
                            recordID: recovery.recordID,
                            scope: recovery.scope,
                            receivedAt: recovery.receivedAt,
                            terminalEvidence: recovery.terminalEvidence
                        )
                    }
                )
            case .participant:
                _ = try await CloudKitParticipantLeaveExecutor().leave(
                    verifyOriginAccount: {
                        try await self.requireCurrentAccountMatchesOrigin(
                            recovery.binding
                        )
                    },
                    leaveShare: {
                        try await self.leaveSharedProfile(recovery.binding)
                    },
                    purgeLocalSources: {
                        try CloudKitProfilePhotoAssetCodec.removeSources(
                            for: recovery.record.profileID,
                            in: self.photoAssetSourceDirectory
                        )
                    },
                    commit: {
                        try self.metadataStore.commitRemoteProfileRemoval(
                            record: recovery.record,
                            recordID: recovery.recordID,
                            scope: recovery.scope,
                            receivedAt: recovery.receivedAt,
                            terminalEvidence: recovery.terminalEvidence
                        )
                    }
                )
            case .unresolved:
                throw CloudKitFamilySyncError.accountBindingMismatch
            }
            recoveredStagedRemoval = true
        }

        for recovery in try metadataStore.pendingRemoteZoneRemovalRecoveries() {
            _ = try await CloudKitProvenZoneDeletionRecoveryExecutor().recover(
                verifyOriginAccount: {
                    try await self.requireCurrentAccountMatchesOrigin(
                        recovery.binding
                    )
                },
                purgeLocalSources: {
                    try CloudKitProfilePhotoAssetCodec.removeSources(
                        for: recovery.record.profileID,
                        in: self.photoAssetSourceDirectory
                    )
                },
                commit: {
                    try self.metadataStore.commitRemoteProfileRemoval(
                        record: recovery.record,
                        recordID: recovery.recordID,
                        scope: recovery.scope,
                        receivedAt: recovery.receivedAt,
                        terminalEvidence: .zoneDeletion
                    )
                }
            )
            recoveredStagedRemoval = true
        }

        let generation = privateDelegate.generation
        if recoveredStagedRemoval {
            await eventBuffer.replay(
                metadataStore.replayableInboxEntries(),
                generation: generation
            )
            return result(
                await eventBuffer.drain(),
                reachedServerHead: false,
                replayedDurableInbox: true
            )
        }

        // A completed terminal receipt is replay-only. Never repeat a zone
        // erase merely because the process stopped before acknowledgement.
        let durableInbox = metadataStore.replayableInboxEntries()
        if !durableInbox.isEmpty {
            await eventBuffer.replay(durableInbox, generation: generation)
            let replayed = await eventBuffer.drain()
            return result(
                replayed,
                reachedServerHead: false,
                replayedDurableInbox: true
            )
        }

        let ledgerFetchAccount = try await currentAuthorizedAccountRecordName()
        let ledgerRecords = try await fetchOwnerDeletionLedgers(
            for: requestedProfileIDs
        )
        try await requireCurrentAccountRecordName(ledgerFetchAccount)
        if !ledgerRecords.isEmpty {
            var recoveredLedger = false
            for record in ledgerRecords {
                let recordID = CloudKitFamilyDeletionLedgerCodec.recordID(
                    for: record.profileID
                )
                let zoneID = privateZoneID(for: record.profileID)
                if metadataStore.binding(for: record.profileID).state
                    == .ownerDeleted
                {
                    continue
                }
                let binding: ProfileCloudBinding
                let receivedAt = Date()
                do {
                    let prepared =
                        try metadataStore
                        .prepareAndStageAmbiguousOwnerDeletionLedgerRecovery(
                            profileID: record.profileID,
                            zoneID: zoneID,
                            rootRecordName: privateRootRecordID(
                                for: record.profileID
                            ).recordName,
                            receivedAt: receivedAt,
                            expectedOriginAccountRecordName: ledgerFetchAccount
                        )
                    binding = prepared.binding
                    _ = try metadataStore.promoteAmbiguousRemoteRemoval(
                        markerID: prepared.markerID,
                        record: record
                    )
                } catch CloudKitFamilyPersistenceError.accountBindingMismatch,
                    CloudKitFamilyPersistenceError.bindingConflict
                {
                    return FamilySyncTransportResult(
                        failures: [
                            FamilySyncTransportFailure(key: nil, category: .account)
                        ]
                    )
                }
                _ = try await CloudKitOwnerDeletionRecoveryExecutor().recover(
                    verifyOriginAccount: {
                        try await self.requireCurrentAccountMatchesOrigin(binding)
                    },
                    persistLedger: {},
                    eraseZone: {
                        if binding.state != .ownerDeleted {
                            try await self.eraseOwnerPayloadZone(
                                zoneID,
                                binding: binding
                            )
                        }
                    },
                    purgeLocalSources: {
                        try CloudKitProfilePhotoAssetCodec.removeSources(
                            for: record.profileID,
                            in: self.photoAssetSourceDirectory
                        )
                    },
                    commitRecovery: {
                        try self.metadataStore.commitOwnerDeletionLedgerRecovery(
                            record: record,
                            recordID: recordID,
                            previous: binding,
                            receivedAt: receivedAt
                        )
                    }
                )
                recoveredLedger = true
            }
            if recoveredLedger {
                await eventBuffer.replay(
                    metadataStore.replayableInboxEntries(),
                    generation: generation
                )
                return result(
                    await eventBuffer.drain(),
                    reachedServerHead: false,
                    replayedDurableInbox: true
                )
            }
        }
        for profileID in requestedProfileIDs.subtracting(terminalProfileIDs) {
            do {
                _ = try await binding(for: profileID)
            } catch CloudKitFamilySyncError.accountBindingMismatch {
                return FamilySyncTransportResult(
                    failures: [
                        FamilySyncTransportFailure(key: nil, category: .account)
                    ]
                )
            }
        }
        if stateStore.recoveredCorruptState() {
            await eventBuffer.noteCorruptStateRecovery()
        }
        try await privateEngine.fetchChanges()
        try await sharedEngine.fetchChanges()
        return result(
            await eventBuffer.drain(),
            reachedServerHead: true,
            replayedDurableInbox: false
        )
    }

    public func sendChanges(
        _ changes: [FamilySyncPendingOperation]
    ) async throws -> FamilySyncTransportResult {
        if let accountChange = try await accountChangeBlockingUpload() {
            return FamilySyncTransportResult(accountChange: accountChange)
        }
        guard !metadataStore.hasPendingInboxWorkForCurrentAccount() else {
            return FamilySyncTransportResult(
                failures: [
                    FamilySyncTransportFailure(key: nil, category: .conflict)
                ]
            )
        }
        let removalResult = await processProfileRemovals(in: changes)
        let changes = changes.filter {
            !removalResult.handledProfileIDs.contains($0.key.profileID)
        }
        var bindings: [ProfileID: ProfileCloudBinding] = [:]
        for profileID in Set(changes.map { $0.key.profileID }) {
            let existing = metadataStore.binding(for: profileID)
            if existing.state == .unbound,
                !metadataStore.hasPersistedBinding(for: profileID)
            {
                bindings[profileID] = try await binding(for: profileID)
            } else {
                bindings[profileID] = existing
            }
        }
        var blockedFailures = removalResult.failures
        var attemptedPending:
            [CloudKitFamilyDatabaseScope: [CKSyncEngine.PendingRecordZoneChange]] = [:]

        for operation in changes {
            guard let binding = bindings[operation.key.profileID],
                metadataStore.isBindingAuthorizedForConfirmedAccount(binding),
                let destination = CloudKitFamilyWriteRoutePlanner.destination(
                    for: binding
                )
            else {
                // A revoked/left shared Profile must never fall back to a new
                // private zone. Keep this one journal key pending while other
                // healthy Profile routes continue in the same batch.
                blockedFailures.append(
                    FamilySyncTransportFailure(
                        key: operation.key,
                        category: .account
                    )
                )
                continue
            }
            let scope = destination.scope
            let zoneID = destination.zoneID
            let rootRecordID = destination.rootRecordID
            let recordID = CKRecord.ID(
                recordName: operation.key.recordName,
                zoneID: zoneID
            )
            if metadataStore.isQuarantined(recordID: recordID, scope: scope) {
                blockedFailures.append(
                    FamilySyncTransportFailure(
                        key: operation.key,
                        category: .compatibility
                    )
                )
                continue
            }
            let record: CKRecord?
            switch operation {
            case .save(let familyRecord):
                record = try CloudKitFamilyRecordCodec.cloudRecord(
                    for: familyRecord,
                    recordID: recordID,
                    rootRecordID: rootRecordID,
                    scope: scope,
                    metadataStore: metadataStore,
                    photoAssetSourceDirectory: photoAssetSourceDirectory
                )
            case .delete:
                record = nil
            }
            let generation = engineGeneration(for: scope)
            await eventBuffer.register(
                CloudKitFamilyOutgoingChange(
                    acknowledgement: FamilySyncChangeAcknowledgement(
                        operation: operation
                    ),
                    record: record,
                    assetSourceURL: (record?[
                        CloudKitProfilePhotoAssetCodec.Schema.asset
                    ] as? CKAsset)?.fileURL
                ),
                recordID: recordID,
                scope: scope,
                generation: generation
            )
            let pending: CKSyncEngine.PendingRecordZoneChange =
                record == nil
                ? .deleteRecord(recordID)
                : .saveRecord(recordID)
            let engine = engine(for: scope)
            let staleOrOpposite = engine.state.pendingRecordZoneChanges.filter {
                Self.recordID(for: $0) == recordID
            }
            if !staleOrOpposite.isEmpty {
                engine.state.remove(pendingRecordZoneChanges: staleOrOpposite)
            }
            engine.state.add(pendingRecordZoneChanges: [pending])
            attemptedPending[scope, default: []].append(pending)
        }

        do {
            try await privateEngine.sendChanges()
            try await sharedEngine.sendChanges()
        } catch {
            removeAttemptedPending(attemptedPending)
            await eventBuffer.discardOutgoing(
                generation: privateDelegate.generation
            )
            throw error
        }
        removeAttemptedPending(attemptedPending)
        let result = await eventBuffer.drain()
        return FamilySyncTransportResult(
            records: result.records,
            deletions: result.deletions,
            acknowledged: result.acknowledged.union(
                removalResult.acknowledged
            ),
            failures: result.failures + blockedFailures,
            accountChange: result.accountChange,
            quarantinedRecordCount: max(
                result.quarantinedRecordCount,
                metadataStore.quarantinedCount()
            ),
            receiptIDs: result.receiptIDs,
            receipts: result.receipts,
            profileErasureDispositions: result.profileErasureDispositions
                + removalResult.dispositions,
            reachedServerHead: result.reachedServerHead,
            replayedDurableInbox: result.replayedDurableInbox,
            requiresFetchPass: result.requiresFetchPass
        )
    }

    public func acknowledgeFetchedChanges(receiptIDs: Set<UUID>) async throws {
        try metadataStore.acknowledgeInbox(receiptIDs: receiptIDs)
    }

    public func quarantineFetchedChanges(
        receiptIDs: Set<UUID>,
        category: FamilySyncPrivacySafeErrorCategory
    ) async throws {
        try metadataStore.quarantineInbox(
            receiptIDs: receiptIDs,
            category: category,
            at: Date()
        )
    }

    public func createShare(for profileID: ProfileID) async throws -> URL {
        try await requireAuthorizedAccount()
        let binding = try await binding(for: profileID)
        guard binding.state == .privateOwner,
            let rootID = binding.rootRecordID
        else { throw CloudKitFamilySyncError.sharedBindingRevoked }
        let root = try await privateDatabase.record(for: rootID)
        if let shareReference = root.share {
            let result = try await privateDatabase.records(for: [shareReference.recordID])
            if let url = try CloudKitExistingShareLookup.url(
                from: result[shareReference.recordID],
                recordID: shareReference.recordID
            ) {
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
        guard case .success(let savedRoot) = result.saveResults[root.recordID],
            case .success(let saved as CKShare) = result.saveResults[share.recordID],
            let url = saved.url
        else { throw CloudKitFamilySyncError.missingShareURL }
        try metadataStore.saveSystemFields(for: savedRoot, scope: .privateDatabase)
        try metadataStore.saveSystemFields(for: saved, scope: .privateDatabase)
        return url
    }

    func accessManagementLocation(
        for profileID: ProfileID
    ) async throws -> CloudKitFamilyAccessLocation {
        try await requireAuthorizedAccount()
        let binding = try await binding(for: profileID)
        guard
            let location = CloudKitFamilyAccessRoutePlanner.location(
                for: binding
            )
        else {
            throw CloudKitFamilySyncError.sharedBindingRevoked
        }
        return location
    }

    public func acceptShare(at url: URL) async throws -> ProfileID {
        try await requireAuthorizedAccount()
        let fetched = try await container.shareMetadatas(for: [url])
        guard case .success(let metadata) = fetched[url] else {
            throw CloudKitFamilySyncError.operationFailed("Share metadata unavailable")
        }
        let accepted = try await container.accept([metadata])
        guard case .success = accepted[metadata] else {
            throw CloudKitFamilySyncError.operationFailed("Share acceptance failed")
        }
        guard let rootRecordID = metadata.hierarchicalRootRecordID else {
            throw CloudKitFamilySyncError.operationFailed("Shared root unavailable")
        }
        let root = try await sharedDatabase.record(for: rootRecordID)
        guard
            let profileString = root[
                CloudKitFamilyRecordCodec.Schema.profileID
            ] as? String,
            let profileUUID = UUID(uuidString: profileString)
        else {
            throw CloudKitFamilySyncError.malformedRecord(rootRecordID.recordName)
        }
        let profileID = ProfileID(rawValue: profileUUID)
        let acceptedBinding = ProfileCloudBinding(
            profileID: profileID,
            state: .sharedParticipant,
            zoneName: rootRecordID.zoneID.zoneName,
            ownerName: rootRecordID.zoneID.ownerName,
            rootRecordName: rootRecordID.recordName
        )
        do {
            try metadataStore.save(binding: acceptedBinding)
        } catch CloudKitFamilyPersistenceError.bindingConflict,
            CloudKitFamilyPersistenceError.accountBindingMismatch
        {
            // CloudKit acceptance is externally committed before the Profile
            // identity is known. If it collides with an existing local route,
            // leave the just-accepted share best-effort and never replace the
            // durable owner/participant provenance.
            try? await leaveSharedProfile(acceptedBinding)
            throw CloudKitFamilySyncError.accountBindingMismatch
        }
        try metadataStore.saveSystemFields(for: root, scope: .sharedDatabase)
        return profileID
    }

    private struct ProfileRemovalBatchResult: Sendable {
        var handledProfileIDs = Set<ProfileID>()
        var acknowledged = Set<FamilySyncChangeAcknowledgement>()
        var failures: [FamilySyncTransportFailure] = []
        var dispositions: [ProfileErasureTransportDisposition] = []
    }

    private func processProfileRemovals(
        in changes: [FamilySyncPendingOperation]
    ) async -> ProfileRemovalBatchResult {
        var result = ProfileRemovalBatchResult()
        let grouped = Dictionary(grouping: changes, by: { $0.key.profileID })
        for profileID in grouped.keys.sorted(by: {
            $0.description < $1.description
        }) {
            guard let operations = grouped[profileID],
                let tombstone = operations.compactMap({
                    operation -> FamilySyncRecord? in
                    guard case .save(let record) = operation,
                        record.kind == .profileDeletion,
                        record.isDeleted
                    else { return nil }
                    return record
                }).first
            else { continue }
            result.handledProfileIDs.insert(profileID)
            let tombstoneAcknowledgement = FamilySyncChangeAcknowledgement(
                operation: .save(tombstone)
            )
            let existing = metadataStore.binding(for: profileID)
            let bindingPlan = CloudKitFamilyProfileRemovalPlanner.bindingPlan(
                for: existing,
                hasPersistedBinding: metadataStore.hasPersistedBinding(
                    for: profileID
                )
            )
            let binding: ProfileCloudBinding
            do {
                switch bindingPlan {
                case .prepareOwnerBinding:
                    binding = try await self.binding(for: profileID)
                case .usePersisted(let persisted):
                    binding = persisted
                }
            } catch {
                let category = Self.failureCategory(for: error)
                let failureRoute: ProfileErasureRoute =
                    switch bindingPlan {
                    case .prepareOwnerBinding: .owner
                    case .usePersisted(let persisted): persisted.erasureRoute
                    }
                result.failures += operations.map {
                    FamilySyncTransportFailure(key: $0.key, category: category)
                }
                result.dispositions.append(
                    ProfileErasureTransportDisposition(
                        change: tombstoneAcknowledgement,
                        route: failureRoute,
                        outcome: .failed(category: category)
                    )
                )
                continue
            }
            let removalMode = CloudKitFamilyProfileRemovalPlanner.mode(
                for: binding,
                isOriginAccountAuthorized:
                    metadataStore.isBindingAuthorizedForConfirmedAccount(binding)
            )
            if case .accountBlocked(let route) = removalMode {
                result.failures += operations.map {
                    FamilySyncTransportFailure(key: $0.key, category: .account)
                }
                if route != .unresolved {
                    result.dispositions.append(
                        ProfileErasureTransportDisposition(
                            change: tombstoneAcknowledgement,
                            route: route,
                            outcome: .failed(category: .account)
                        )
                    )
                }
                continue
            }
            let terminalZoneID = binding.zoneID ?? privateZoneID(for: profileID)
            await eventBuffer.discardOutgoing(
                for: profileID,
                generation: privateDelegate.generation
            )
            removePendingEngineChanges(in: terminalZoneID)
            do {
                let route: ProfileErasureRoute
                switch removalMode {
                case .ownerGlobalDeletion:
                    route = .owner
                    try await CloudKitOwnerDeletionRecoveryExecutor().recover(
                        verifyOriginAccount: {
                            try await self.requireCurrentAccountMatchesOrigin(binding)
                        },
                        persistLedger: {
                            try await self.persistOwnerDeletionLedger(
                                tombstone,
                                binding: binding
                            )
                        },
                        eraseZone: {
                            try await self.eraseOwnerPayloadZone(
                                binding.zoneID ?? self.privateZoneID(for: profileID),
                                binding: binding
                            )
                        },
                        purgeLocalSources: {
                            try CloudKitProfilePhotoAssetCodec.removeSources(
                                for: profileID,
                                in: self.photoAssetSourceDirectory
                            )
                        },
                        commitRecovery: {
                            try self.metadataStore.commitAcknowledgedTerminalRemoval(
                                tombstone,
                                previous: binding,
                                terminalState: .ownerDeleted
                            )
                        }
                    )
                case .participantLeave:
                    route = .participant
                    try await CloudKitParticipantLeaveExecutor().leave(
                        verifyOriginAccount: {
                            try await self.requireCurrentAccountMatchesOrigin(binding)
                        },
                        leaveShare: {
                            try await self.leaveSharedProfile(binding)
                        },
                        purgeLocalSources: {
                            try CloudKitProfilePhotoAssetCodec.removeSources(
                                for: profileID,
                                in: self.photoAssetSourceDirectory
                            )
                        },
                        commit: {
                            try self.metadataStore.commitAcknowledgedTerminalRemoval(
                                tombstone,
                                previous: binding,
                                terminalState: .participantLeft
                            )
                        }
                    )
                case .alreadyTerminal(let terminalRoute):
                    route = terminalRoute
                    try await requireCurrentAccountMatchesOrigin(binding)
                    try CloudKitProfilePhotoAssetCodec.removeSources(
                        for: profileID,
                        in: photoAssetSourceDirectory
                    )
                    try await requireCurrentAccountMatchesOrigin(binding)
                case .accountBlocked:
                    preconditionFailure("Account-blocked removals return before CloudKit work")
                }
                result.acknowledged.formUnion(
                    operations.map(
                        FamilySyncChangeAcknowledgement.init(operation:)
                    )
                )
                result.dispositions.append(
                    ProfileErasureTransportDisposition(
                        change: tombstoneAcknowledgement,
                        route: route,
                        outcome: .completed
                    )
                )
            } catch {
                let category = Self.failureCategory(for: error)
                let route = binding.erasureRoute
                result.failures += operations.map {
                    FamilySyncTransportFailure(
                        key: $0.key,
                        category: category
                    )
                }
                result.dispositions.append(
                    ProfileErasureTransportDisposition(
                        change: tombstoneAcknowledgement,
                        route: route,
                        outcome: .failed(category: category)
                    )
                )
            }
        }
        return result
    }

    private func persistOwnerDeletionLedger(
        _ tombstone: FamilySyncRecord,
        binding: ProfileCloudBinding
    ) async throws {
        let recordID = CloudKitFamilyDeletionLedgerCodec.recordID(
            for: tombstone.profileID
        )
        try await requireCurrentAccountMatchesOrigin(binding)
        let existing = try? await privateDatabase.record(for: recordID)
        try await requireCurrentAccountMatchesOrigin(binding)
        if let existing {
            let removedUnexpectedFields =
                CloudKitFamilyDeletionLedgerCodec
                .removeUnexpectedApplicationFields(from: existing)
            guard
                CloudKitFamilyDeletionLedgerCodec.familyRecord(from: existing)?
                    .profileID == tombstone.profileID
            else {
                throw CloudKitFamilySyncError.malformedRecord(
                    recordID.recordName
                )
            }
            guard removedUnexpectedFields else { return }
            try await requireCurrentAccountMatchesOrigin(binding)
            let sanitized = try await privateDatabase.modifyRecords(
                saving: [existing],
                deleting: [],
                savePolicy: .ifServerRecordUnchanged,
                atomically: true
            )
            try await requireCurrentAccountMatchesOrigin(binding)
            guard case .success = sanitized.saveResults[recordID] else {
                throw CloudKitFamilySyncError.operationFailed(
                    "Deletion ledger could not be sanitized"
                )
            }
            return
        }

        let controlZone = CKRecordZone(
            zoneID: CloudKitFamilyDeletionLedgerCodec.controlZoneID
        )
        try await requireCurrentAccountMatchesOrigin(binding)
        let zoneResult = try await privateDatabase.modifyRecordZones(
            saving: [controlZone],
            deleting: []
        )
        try await requireCurrentAccountMatchesOrigin(binding)
        if case .failure(let error) = zoneResult.saveResults[controlZone.zoneID],
            (error as? CKError)?.code != .serverRejectedRequest
        {
            throw error
        }

        let ledger = try CloudKitFamilyDeletionLedgerCodec.cloudRecord(
            for: tombstone
        )
        try await requireCurrentAccountMatchesOrigin(binding)
        let save = try await privateDatabase.modifyRecords(
            saving: [ledger],
            deleting: [],
            savePolicy: .changedKeys,
            atomically: true
        )
        try await requireCurrentAccountMatchesOrigin(binding)
        guard case .success = save.saveResults[ledger.recordID] else {
            try await requireCurrentAccountMatchesOrigin(binding)
            if let fetched = try? await privateDatabase.record(for: recordID),
                CloudKitFamilyDeletionLedgerCodec.familyRecord(from: fetched)?
                    .profileID == tombstone.profileID
            {
                try await requireCurrentAccountMatchesOrigin(binding)
                return
            }
            try await requireCurrentAccountMatchesOrigin(binding)
            throw CloudKitFamilySyncError.operationFailed(
                "Deletion ledger could not be committed"
            )
        }
    }

    private func eraseOwnerPayloadZone(
        _ zoneID: CKRecordZone.ID,
        binding: ProfileCloudBinding
    ) async throws {
        try await requireCurrentAccountMatchesOrigin(binding)
        let result = try await privateDatabase.modifyRecordZones(
            saving: [],
            deleting: [zoneID]
        )
        try await requireCurrentAccountMatchesOrigin(binding)
        try CloudKitTerminalDeletionProof.require(
            result.deleteResults[zoneID],
            acceptingAbsenceCodes: [.zoneNotFound, .unknownItem],
            operation: "Profile zone deletion result unavailable"
        )
    }

    private func leaveSharedProfile(
        _ binding: ProfileCloudBinding
    ) async throws {
        guard let rootID = binding.rootRecordID else {
            throw CloudKitFamilySyncError.malformedRecord(
                binding.profileID.description
            )
        }
        let root: CKRecord
        do {
            try await requireCurrentAccountMatchesOrigin(binding)
            root = try await sharedDatabase.record(for: rootID)
            try await requireCurrentAccountMatchesOrigin(binding)
        } catch let error as CKError
            where error.code == .unknownItem
            || error.code == .zoneNotFound
            || error.code == .permissionFailure
        {
            try await requireCurrentAccountMatchesOrigin(binding)
            return
        }
        guard let shareID = root.share?.recordID else {
            throw CloudKitFamilySyncError.operationFailed(
                "Shared leave proof unavailable"
            )
        }
        try await requireCurrentAccountMatchesOrigin(binding)
        let result = try await sharedDatabase.modifyRecords(
            saving: [],
            deleting: [shareID],
            savePolicy: .ifServerRecordUnchanged,
            atomically: true
        )
        try await requireCurrentAccountMatchesOrigin(binding)
        try CloudKitTerminalDeletionProof.require(
            result.deleteResults[shareID],
            acceptingAbsenceCodes: [
                .unknownItem,
                .zoneNotFound,
                .permissionFailure,
            ],
            operation: "Shared leave result unavailable"
        )
    }

    private func binding(for profileID: ProfileID) async throws -> ProfileCloudBinding {
        let existing = metadataStore.binding(for: profileID)
        let hasPersistedBinding = metadataStore.hasPersistedBinding(for: profileID)
        if hasPersistedBinding,
            !metadataStore.isBindingAuthorizedForConfirmedAccount(existing)
        {
            throw CloudKitFamilySyncError.accountBindingMismatch
        }
        switch existing.state {
        case .sharedParticipant:
            guard existing.zoneID != nil, existing.rootRecordID != nil else {
                throw CloudKitFamilySyncError.malformedRecord(profileID.description)
            }
            // Never fall back to private when a shared zone is temporarily
            // unavailable. CKSyncEngine will retry the persisted shared route.
            return existing
        case .revoked, .ownerDeleted, .participantLeft:
            throw CloudKitFamilySyncError.sharedBindingRevoked
        case .privateOwner:
            return existing
        case .unbound:
            guard !hasPersistedBinding else {
                throw CloudKitFamilySyncError.accountBindingMismatch
            }
            let zoneID = privateZoneID(for: profileID)
            let rootID = privateRootRecordID(for: profileID)
            try await preparePrivateZone(zoneID, profileID: profileID, rootID: rootID)
            let binding = ProfileCloudBinding(
                profileID: profileID,
                state: .privateOwner,
                zoneName: zoneID.zoneName,
                ownerName: zoneID.ownerName,
                rootRecordName: rootID.recordName
            )
            try metadataStore.save(binding: binding)
            return binding
        }
    }

    private func preparePrivateZone(
        _ zoneID: CKRecordZone.ID,
        profileID: ProfileID,
        rootID: CKRecord.ID
    ) async throws {
        let zone = CKRecordZone(zoneID: zoneID)
        let zoneResult = try await privateDatabase.modifyRecordZones(
            saving: [zone],
            deleting: []
        )
        if case .failure(let error) = zoneResult.saveResults[zoneID],
            (error as? CKError)?.code != .serverRejectedRequest
        {
            throw CloudKitFamilySyncError.operationFailed(String(describing: error))
        }

        let fetched = try await privateDatabase.records(for: [rootID])
        if case .success(let root) = fetched[rootID] {
            try metadataStore.saveSystemFields(for: root, scope: .privateDatabase)
            return
        }
        let root = CKRecord(
            recordType: CloudKitFamilyRecordCodec.Schema.rootRecordType,
            recordID: rootID
        )
        root[CloudKitFamilyRecordCodec.Schema.profileID] =
            profileID.rawValue.uuidString as NSString
        let result = try await privateDatabase.modifyRecords(
            saving: [root],
            deleting: [],
            savePolicy: .ifServerRecordUnchanged,
            atomically: true
        )
        guard case .success(let saved) = result.saveResults[rootID] else {
            throw CloudKitFamilySyncError.operationFailed("Unable to create profile root")
        }
        try metadataStore.saveSystemFields(for: saved, scope: .privateDatabase)
    }

    private func fetchOwnerDeletionLedgers(
        for profileIDs: Set<ProfileID>
    ) async throws -> [FamilySyncRecord] {
        guard !profileIDs.isEmpty else { return [] }
        let recordIDs = profileIDs.map(
            CloudKitFamilyDeletionLedgerCodec.recordID(for:)
        )
        let results = try await privateDatabase.records(for: recordIDs)
        return try CloudKitOwnerDeletionLedgerFetchProof.records(
            requestedRecordIDs: recordIDs,
            results: results
        )
    }

    private func revalidateAmbiguousOwnerDeletionLedger(
        _ marker: CloudKitAmbiguousRemoteRemovalMarker,
        binding: ProfileCloudBinding
    ) async throws {
        guard marker.evidence == .ownerDeletionLedger,
            marker.scope == .privateDatabase,
            binding.erasureRoute == .owner
        else {
            throw CloudKitFamilySyncError.accountBindingMismatch
        }
        let recordID = CloudKitFamilyDeletionLedgerCodec.recordID(
            for: marker.profileID
        )
        try await requireCurrentAccountMatchesOrigin(binding)
        let results = try await privateDatabase.records(for: [recordID])
        try await requireCurrentAccountMatchesOrigin(binding)
        let records = try CloudKitOwnerDeletionLedgerFetchProof.records(
            requestedRecordIDs: [recordID],
            results: results
        )
        if let record = records.first {
            _ = try metadataStore.promoteAmbiguousRemoteRemoval(
                markerID: marker.id,
                record: record
            )
        } else {
            _ =
                try metadataStore
                .discardAmbiguousOwnerDeletionLedgerAbsence(marker)
        }
    }

    private func recoverAmbiguousRemoteRemoval(
        _ marker: CloudKitAmbiguousRemoteRemovalMarker,
        binding: ProfileCloudBinding
    ) async throws -> Bool {
        guard marker.evidence != .ownerDeletionLedger,
            binding.zoneID == marker.zoneID,
            binding.rootRecordName == marker.rootRecordName
        else {
            throw CloudKitFamilySyncError.accountBindingMismatch
        }
        let record = try CloudKitRemoteProfileRemovalRecordFactory.record(
            for: marker.profileID
        )
        return try await CloudKitAmbiguousRemoteRemovalRecoveryExecutor()
            .resolve(
                verifyOriginAccount: {
                    try await self.requireCurrentAccountMatchesOrigin(binding)
                },
                fetchRootProof: {
                    let database =
                        marker.scope == .privateDatabase
                        ? self.privateDatabase : self.sharedDatabase
                    let results = try await database.records(
                        for: [marker.rootRecordID]
                    )
                    return try CloudKitRemoteRootFetchProof.proof(
                        results[marker.rootRecordID],
                        scope: marker.scope,
                        recordID: marker.rootRecordID
                    )
                },
                discardMarker: {
                    try self.metadataStore.discardAmbiguousRemoteRemoval(
                        marker
                    )
                },
                recoverRootMissing: {
                    switch binding.erasureRoute {
                    case .owner:
                        guard let zoneID = binding.zoneID else {
                            throw CloudKitFamilySyncError.operationFailed(
                                "Ambiguous owner recovery route is incomplete"
                            )
                        }
                        _ = try await CloudKitOwnerDeletionRecoveryExecutor()
                            .recover(
                                verifyOriginAccount: {
                                    try await self
                                        .requireCurrentAccountMatchesOrigin(
                                            binding
                                        )
                                },
                                persistLedger: {},
                                eraseZone: {
                                    try await self.eraseOwnerPayloadZone(
                                        zoneID,
                                        binding: binding
                                    )
                                },
                                purgeLocalSources: {
                                    try CloudKitProfilePhotoAssetCodec
                                        .removeSources(
                                            for: marker.profileID,
                                            in: self.photoAssetSourceDirectory
                                        )
                                },
                                commitRecovery: {
                                    _ = try self.metadataStore
                                        .commitAmbiguousRemoteRemoval(
                                            marker,
                                            record: record
                                        )
                                }
                            )
                    case .participant:
                        _ = try await CloudKitParticipantLeaveExecutor().leave(
                            verifyOriginAccount: {
                                try await self.requireCurrentAccountMatchesOrigin(
                                    binding
                                )
                            },
                            leaveShare: {
                                try await self.leaveSharedProfile(binding)
                            },
                            purgeLocalSources: {
                                try CloudKitProfilePhotoAssetCodec.removeSources(
                                    for: marker.profileID,
                                    in: self.photoAssetSourceDirectory
                                )
                            },
                            commit: {
                                _ = try self.metadataStore
                                    .commitAmbiguousRemoteRemoval(
                                        marker,
                                        record: record
                                    )
                            }
                        )
                    case .unresolved:
                        throw CloudKitFamilySyncError.accountBindingMismatch
                    }
                },
                recoverZoneMissing: {
                    _ = try await CloudKitProvenZoneDeletionRecoveryExecutor()
                        .recover(
                            verifyOriginAccount: {
                                try await self.requireCurrentAccountMatchesOrigin(
                                    binding
                                )
                            },
                            purgeLocalSources: {
                                try CloudKitProfilePhotoAssetCodec.removeSources(
                                    for: marker.profileID,
                                    in: self.photoAssetSourceDirectory
                                )
                            },
                            commit: {
                                _ = try self.metadataStore
                                    .commitAmbiguousRemoteRemoval(
                                        marker,
                                        record: record
                                    )
                            }
                        )
                }
            )
    }

    private func requireAuthorizedAccount() async throws {
        try await requireAvailability()
        if let change = try await accountChangeBlockingUpload() {
            throw CloudKitFamilySyncError.accountConfirmationRequired(change)
        }
    }

    /// A durable binding is scoped to the Apple Account that created it.
    /// Re-read the live CloudKit identity at every destructive suspension
    /// boundary; metadata authorization alone cannot detect a switch that has
    /// occurred before CKSyncEngine delivers its account-change callback.
    private func requireCurrentAccountMatchesOrigin(
        _ binding: ProfileCloudBinding
    ) async throws {
        guard let origin = binding.originAccountRecordName,
            metadataStore.isBindingAuthorizedForConfirmedAccount(binding)
        else {
            throw CloudKitFamilySyncError.accountBindingMismatch
        }
        let current = try await container.userRecordID()
        guard current.recordName == origin,
            metadataStore.isBindingAuthorizedForConfirmedAccount(binding)
        else {
            throw CloudKitFamilySyncError.accountBindingMismatch
        }
    }

    private func currentAuthorizedAccountRecordName() async throws -> String {
        let current = try await container.userRecordID().recordName
        try await requireCurrentAccountRecordName(current)
        return current
    }

    private func requireCurrentAccountRecordName(
        _ expected: String
    ) async throws {
        let current = try await container.userRecordID().recordName
        guard current == expected else {
            throw CloudKitFamilySyncError.accountBindingMismatch
        }
        do {
            guard
                case .authorized = try metadataStore.accountGate(
                    currentAccountRecordName: current
                )
            else {
                throw CloudKitFamilySyncError.accountBindingMismatch
            }
        } catch {
            throw CloudKitFamilySyncError.accountBindingMismatch
        }
    }

    private func accountChangeBlockingUpload() async throws -> FamilySyncAccountChange? {
        let account = try await container.userRecordID()
        do {
            switch try metadataStore.accountGate(
                currentAccountRecordName: account.recordName
            ) {
            case .authorized:
                return nil
            case .requiresConfirmation(let change):
                return change
            }
        } catch CloudKitFamilyPersistenceError.corruptMetadata {
            throw FamilySyncTransportContractError.corruptState
        }
    }

    private func requireAvailability() async throws {
        let state = await availability()
        guard state == .available else {
            throw CloudKitFamilySyncError.unavailable(state)
        }
    }

    private func rebuildEngines() async {
        let generation = await eventBuffer.nextGeneration()
        let privateDelegate = CloudKitFamilySyncEngineDelegate(
            scope: .privateDatabase,
            generation: generation,
            buffer: eventBuffer,
            stateStore: stateStore
        )
        let sharedDelegate = CloudKitFamilySyncEngineDelegate(
            scope: .sharedDatabase,
            generation: generation,
            buffer: eventBuffer,
            stateStore: stateStore
        )
        self.privateDelegate = privateDelegate
        self.sharedDelegate = sharedDelegate
        privateEngine = Self.makeEngine(
            database: privateDatabase,
            serialization: stateStore.load(.privateDatabase),
            delegate: privateDelegate,
            subscriptionID: "tada-family-private-v2"
        )
        sharedEngine = Self.makeEngine(
            database: sharedDatabase,
            serialization: stateStore.load(.sharedDatabase),
            delegate: sharedDelegate,
            subscriptionID: "tada-family-shared-v2"
        )
    }

    private func cancelEngines() async {
        async let privateCancellation: Void = privateEngine.cancelOperations()
        async let sharedCancellation: Void = sharedEngine.cancelOperations()
        _ = await (privateCancellation, sharedCancellation)
    }

    private nonisolated func result(
        _ result: FamilySyncTransportResult,
        reachedServerHead: Bool,
        replayedDurableInbox: Bool
    ) -> FamilySyncTransportResult {
        let existingDispositionKeys = Set(
            result.profileErasureDispositions.map(\.change)
        )
        let recoveredDispositions = completedProfileErasureDispositions(
            in: result.records
        ).filter { !existingDispositionKeys.contains($0.change) }
        return FamilySyncTransportResult(
            records: result.records,
            deletions: result.deletions,
            acknowledged: result.acknowledged,
            failures: result.failures,
            accountChange: result.accountChange,
            quarantinedRecordCount: max(
                result.quarantinedRecordCount,
                metadataStore.quarantinedCount()
            ),
            receiptIDs: result.receiptIDs,
            receipts: result.receipts,
            profileErasureDispositions: result.profileErasureDispositions
                + recoveredDispositions,
            reachedServerHead: reachedServerHead,
            replayedDurableInbox: replayedDurableInbox,
            requiresFetchPass: result.requiresFetchPass
        )
    }

    private nonisolated func completedProfileErasureDispositions(
        in records: [FamilySyncRecord]
    ) -> [ProfileErasureTransportDisposition] {
        return records.compactMap { record in
            guard record.kind == .profileDeletion, record.isDeleted else {
                return nil
            }
            let binding = metadataStore.binding(for: record.profileID)
            guard metadataStore.isBindingAuthorizedForConfirmedAccount(binding)
            else { return nil }
            let route: ProfileErasureRoute
            switch binding.state {
            case .ownerDeleted:
                route = .owner
            case .revoked, .participantLeft:
                route = .participant
            case .unbound, .privateOwner, .sharedParticipant:
                return nil
            }
            return ProfileErasureTransportDisposition(
                change: FamilySyncChangeAcknowledgement(
                    key: FamilySyncChangeKey(
                        profileID: record.profileID,
                        recordName: record.recordName
                    ),
                    revision: record.logicalRevision,
                    operation: .save
                ),
                route: route,
                outcome: .completed
            )
        }
    }

    private func engine(
        for scope: CloudKitFamilyDatabaseScope
    ) -> CKSyncEngine {
        switch scope {
        case .privateDatabase:
            privateEngine
        case .sharedDatabase:
            sharedEngine
        }
    }

    private func removeAttemptedPending(
        _ attempted: [CloudKitFamilyDatabaseScope: [CKSyncEngine.PendingRecordZoneChange]]
    ) {
        for (scope, changes) in attempted where !changes.isEmpty {
            engine(for: scope).state.remove(
                pendingRecordZoneChanges: changes
            )
        }
    }

    private func removePendingEngineChanges(
        in zoneID: CKRecordZone.ID
    ) {
        for engine in [privateEngine, sharedEngine] {
            let recordChanges =
                CloudKitFamilyTerminalPendingPruner
                .recordChanges(
                    in: engine.state.pendingRecordZoneChanges,
                    matching: zoneID
                )
            if !recordChanges.isEmpty {
                engine.state.remove(
                    pendingRecordZoneChanges: recordChanges
                )
            }
            let databaseChanges =
                CloudKitFamilyTerminalPendingPruner
                .databaseChanges(
                    in: engine.state.pendingDatabaseChanges,
                    matching: zoneID
                )
            if !databaseChanges.isEmpty {
                engine.state.remove(
                    pendingDatabaseChanges: databaseChanges
                )
            }
        }
    }

    private func engineGeneration(
        for scope: CloudKitFamilyDatabaseScope
    ) -> UInt64 {
        switch scope {
        case .privateDatabase:
            privateDelegate.generation
        case .sharedDatabase:
            sharedDelegate.generation
        }
    }

    private func privateZoneID(for profileID: ProfileID) -> CKRecordZone.ID {
        CKRecordZone.ID(
            zoneName: "TadaProfile-\(profileID.rawValue.uuidString)",
            ownerName: CKCurrentUserDefaultName
        )
    }

    private func privateRootRecordID(for profileID: ProfileID) -> CKRecord.ID {
        CKRecord.ID(
            recordName: "profile-root-\(profileID.rawValue.uuidString)",
            zoneID: privateZoneID(for: profileID)
        )
    }

    private nonisolated static func makeEngine(
        database: CKDatabase,
        serialization: CKSyncEngine.State.Serialization?,
        delegate: any CKSyncEngineDelegate,
        subscriptionID: String
    ) -> CKSyncEngine {
        var configuration = CKSyncEngine.Configuration(
            database: database,
            stateSerialization: serialization,
            delegate: delegate
        )
        configuration.automaticallySync = false
        configuration.subscriptionID = subscriptionID
        let engine = CKSyncEngine(configuration)
        // The durable journal is the sole source of truth for retry timing and
        // exact revisions. Pending engine sends restored without the volatile
        // record provider/ack map are unsafe, so discard them and let the
        // journal re-register only currently due operations.
        let restoredRecordChanges = engine.state.pendingRecordZoneChanges
        if !restoredRecordChanges.isEmpty {
            engine.state.remove(pendingRecordZoneChanges: restoredRecordChanges)
        }
        let restoredDatabaseChanges = engine.state.pendingDatabaseChanges
        if !restoredDatabaseChanges.isEmpty {
            engine.state.remove(pendingDatabaseChanges: restoredDatabaseChanges)
        }
        return engine
    }

    private nonisolated static func recordID(
        for change: CKSyncEngine.PendingRecordZoneChange
    ) -> CKRecord.ID {
        switch change {
        case .saveRecord(let recordID), .deleteRecord(let recordID):
            recordID
        @unknown default:
            // Unknown future operations cannot be safely matched to a durable
            // journal key. Use a sentinel that never equals an app record ID.
            CKRecord.ID(recordName: "unsupported-pending-change")
        }
    }

    private nonisolated static func failureCategory(
        for error: Error
    ) -> FamilySyncPrivacySafeErrorCategory {
        if let familyError = error as? CloudKitFamilySyncError,
            case .accountBindingMismatch = familyError
        {
            return .account
        }
        guard let cloudError = error as? CKError else { return .unknown }
        switch cloudError.code {
        case .networkFailure, .networkUnavailable:
            return .connectivity
        case .requestRateLimited, .zoneBusy:
            return .rateLimited
        case .serviceUnavailable, .internalError:
            return .server
        case .notAuthenticated, .permissionFailure:
            return .account
        case .serverRecordChanged, .batchRequestFailed:
            return .conflict
        default:
            return .unknown
        }
    }

    private nonisolated static func defaultStateDirectory() -> URL {
        let root =
            (try? FileManager.default.url(
                for: .applicationSupportDirectory,
                in: .userDomainMask,
                appropriateFor: nil,
                create: true
            )) ?? FileManager.default.temporaryDirectory
        return root.appendingPathComponent(
            "TadaWords/FamilySync",
            isDirectory: true
        )
    }
}

struct CloudKitFamilyWriteDestination: Equatable, Sendable {
    let scope: CloudKitFamilyDatabaseScope
    let zoneID: CKRecordZone.ID
    let rootRecordID: CKRecord.ID
}

struct CloudKitFamilyAccessLocation: @unchecked Sendable {
    let scope: CloudKitFamilyDatabaseScope
    let rootRecordID: CKRecord.ID
}

/// Interprets CloudKit's per-record result without turning a transient read
/// failure into a second share-creation attempt. A confirmed missing share is
/// the only state in which the owner path may rebuild the stale reference.
enum CloudKitExistingShareLookup {
    static func url(
        from result: Result<CKRecord, any Error>?,
        recordID: CKRecord.ID
    ) throws -> URL? {
        guard let result else {
            throw CloudKitFamilySyncError.operationFailed(
                "Existing share result unavailable"
            )
        }
        switch result {
        case .success(let record):
            guard let share = record as? CKShare else {
                throw CloudKitFamilySyncError.malformedRecord(
                    recordID.recordName
                )
            }
            guard let url = share.url else {
                throw CloudKitFamilySyncError.missingShareURL
            }
            return url
        case .failure(let error as CKError) where error.code == .unknownItem:
            return nil
        case .failure(let error):
            throw error
        }
    }
}

enum CloudKitFamilyAccessRoutePlanner {
    static func location(
        for binding: ProfileCloudBinding
    ) -> CloudKitFamilyAccessLocation? {
        guard let scope = binding.databaseScope,
            let rootRecordID = binding.rootRecordID
        else { return nil }
        return CloudKitFamilyAccessLocation(
            scope: scope,
            rootRecordID: rootRecordID
        )
    }
}

/// Pure route seam used by the actual send path. Persisted binding state is
/// authoritative: a revoked or malformed shared route returns nil and can
/// never silently create a private owner zone.
enum CloudKitFamilyWriteRoutePlanner {
    static func destination(
        for binding: ProfileCloudBinding
    ) -> CloudKitFamilyWriteDestination? {
        guard let scope = binding.databaseScope,
            let zoneID = binding.zoneID,
            let rootRecordID = binding.rootRecordID
        else { return nil }
        return CloudKitFamilyWriteDestination(
            scope: scope,
            zoneID: zoneID,
            rootRecordID: rootRecordID
        )
    }
}

enum CloudKitFamilyTerminalPendingPruner {
    static func recordChanges(
        in changes: [CKSyncEngine.PendingRecordZoneChange],
        matching zoneID: CKRecordZone.ID
    ) -> [CKSyncEngine.PendingRecordZoneChange] {
        changes.filter { change in
            switch change {
            case .saveRecord(let recordID), .deleteRecord(let recordID):
                recordID.zoneID == zoneID
            @unknown default:
                false
            }
        }
    }

    static func databaseChanges(
        in changes: [CKSyncEngine.PendingDatabaseChange],
        matching zoneID: CKRecordZone.ID
    ) -> [CKSyncEngine.PendingDatabaseChange] {
        changes.filter { change in
            switch change {
            case .saveZone(let zone):
                zone.zoneID == zoneID
            case .deleteZone(let pendingZoneID):
                pendingZoneID == zoneID
            @unknown default:
                false
            }
        }
    }
}
