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

struct CloudKitCanonicalRecoveryExecutor {
    func recover<T>(
        isolation: isolated (any Actor)? = #isolation,
        prepareDurableMarker: () throws -> Void,
        verifyOriginAccount: () async throws -> Void,
        replaceProfiles: () async throws -> Void,
        verifyRemoteManifest: () async throws -> T,
        completeDurableMarker: () throws -> Void
    ) async throws -> T {
        _ = isolation
        try prepareDurableMarker()
        try await verifyOriginAccount()
        try await replaceProfiles()
        try await verifyOriginAccount()
        let result = try await verifyRemoteManifest()
        try await verifyOriginAccount()
        try completeDurableMarker()
        return result
    }
}

struct CloudKitCanonicalRecoveryBindingProof {
    func requirePrivateReplacement(
        binding: ProfileCloudBinding,
        expectedZoneID: CKRecordZone.ID,
        expectedRootRecordID: CKRecord.ID,
        isAuthorizedForConfirmedAccount: Bool
    ) throws {
        switch binding.state {
        case .unbound:
            return
        case .privateOwner:
            guard binding.zoneID == expectedZoneID,
                binding.rootRecordID == nil
                    || binding.rootRecordID == expectedRootRecordID,
                isAuthorizedForConfirmedAccount
            else {
                throw CloudKitFamilySyncError.accountBindingMismatch
            }
        case .sharedParticipant, .revoked, .ownerDeleted, .participantLeft:
            throw CloudKitFamilySyncError.accountBindingMismatch
        }
    }
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

/// Remote root/zone deletion evidence must become a cross-device deletion
/// barrier before the payload zone is erased or local state turns terminal.
/// Keeping this as a distinct executor prevents those paths from accidentally
/// using the owner-ledger replay variant whose ledger step is intentionally a
/// no-op because the control record is already the fetched evidence.
struct CloudKitRemoteOwnerDeletionDominanceExecutor {
    func recover<T>(
        isolation: isolated (any Actor) = #isolation,
        record: FamilySyncRecord,
        verifyOriginAccount: () async throws -> Void,
        persistControlLedger: (FamilySyncRecord) async throws -> Void,
        eraseZone: () async throws -> Void,
        purgeLocalSources: () throws -> Void,
        commitRecovery: () throws -> T
    ) async throws -> T {
        _ = isolation
        return try await CloudKitOwnerDeletionRecoveryExecutor().recover(
            verifyOriginAccount: verifyOriginAccount,
            persistLedger: {
                try await persistControlLedger(record)
            },
            eraseZone: eraseZone,
            purgeLocalSources: purgeLocalSources,
            commitRecovery: commitRecovery
        )
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

/// Proves the Profile identity encoded in share metadata before CloudKit is
/// allowed to accept the share, then validates the newly readable root against
/// that same immutable identity before local commit.
enum CloudKitAcceptedShareRootProof {
    static func profileID(from rootRecordID: CKRecord.ID) throws -> ProfileID {
        guard
            let profileID = CloudKitDeterministicProfileRoute.profileID(
                from: rootRecordID
            )
        else {
            throw CloudKitFamilySyncError.malformedRecord(
                rootRecordID.recordName
            )
        }
        return profileID
    }

    static func validate(
        _ root: CKRecord,
        expectedRootRecordID: CKRecord.ID,
        expectedShareRecordID: CKRecord.ID?,
        profileID: ProfileID
    ) throws {
        guard root.recordType == CloudKitFamilyRecordCodec.Schema.rootRecordType,
            root.recordID == expectedRootRecordID,
            CloudKitDeterministicProfileRoute.profileID(
                from: root.recordID
            ) == profileID,
            let encodedProfileID = root[
                CloudKitFamilyRecordCodec.Schema.profileID
            ] as? String,
            UUID(uuidString: encodedProfileID) == profileID.rawValue,
            expectedShareRecordID == nil
                || root.share?.recordID == expectedShareRecordID
        else {
            throw CloudKitFamilySyncError.malformedRecord(
                expectedRootRecordID.recordName
            )
        }
    }
}

/// Executes the monotonic cleanup state machine under the transport's marker
/// claim. Attempted/accepted phases cannot reach deletion or marker completion
/// until the exact root+share have been observed and durably materialized.
struct CloudKitAcceptedShareRecoveryExecutor {
    func recover(
        isolation: isolated (any Actor)? = #isolation,
        marker: CloudKitPendingAcceptedShareCleanup,
        verifyOriginAccount: () async throws -> Void,
        completePrepared: (
            CloudKitPendingAcceptedShareCleanup
        ) throws -> Void,
        materialize: (
            CloudKitPendingAcceptedShareCleanup
        ) async throws -> CloudKitPendingAcceptedShareCleanup,
        deleteMaterializedShare: (
            CloudKitPendingAcceptedShareCleanup
        ) async throws -> Void,
        completeMaterialized: (
            CloudKitPendingAcceptedShareCleanup
        ) throws -> Void
    ) async throws {
        _ = isolation
        try await verifyOriginAccount()
        var current = marker
        switch current.effectivePhase {
        case .prepared:
            try completePrepared(current)
            return
        case .acceptanceAttempted, .accepted:
            current = try await materialize(current)
        case .materialized:
            break
        }
        try await verifyOriginAccount()
        try await deleteMaterializedShare(current)
        try await verifyOriginAccount()
        try completeMaterialized(current)
    }
}

/// A per-share failure is proof that this acceptance did not commit only when
/// the same invocation moved a never-attempted marker immediately into the
/// external call. A marker already in the attempted state may represent an
/// earlier server commit whose response was lost, so a later failure must not
/// clear it.
enum CloudKitAcceptedShareFailureProofPolicy {
    static func canClearAfterExplicitPerShareFailure(
        initialMarker: CloudKitPendingAcceptedShareCleanup,
        attemptedMarker: CloudKitPendingAcceptedShareCleanup
    ) -> Bool {
        initialMarker.effectivePhase == .prepared
            && attemptedMarker.effectivePhase == .acceptanceAttempted
    }
}

/// Couples the externally committed CloudKit acceptance with one atomic local
/// binding+marker commit. Any error before that commit compensates only while
/// the exact durable marker still exists; an idempotent second completion can
/// therefore never leave a share already made visible by the first path.
struct CloudKitAcceptedShareTransactionExecutor {
    func acceptAndCommit<T>(
        isolation: isolated (any Actor)? = #isolation,
        markerIsPending: () -> Bool,
        acceptAndValidate: () async throws -> T,
        commit: (T) throws -> Void,
        compensate: () async throws -> Void
    ) async throws -> T {
        _ = isolation
        do {
            let accepted = try await acceptAndValidate()
            try commit(accepted)
            return accepted
        } catch {
            if markerIsPending() {
                try? await compensate()
            }
            throw error
        }
    }
}

/// Keeps the all-origin accepted-share reservation check in front of every
/// private-zone side effect. The second preflight protects the local commit;
/// the transport's in-memory Profile claim prevents an acceptance from being
/// staged while the async CloudKit creation is in flight.
struct CloudKitPrivateRoutePreparationExecutor {
    func prepare<T>(
        isolation: isolated (any Actor)? = #isolation,
        preflight: () throws -> Void,
        createRemoteRoute: () async throws -> Void,
        commitLocalRoute: () throws -> T
    ) async throws -> T {
        _ = isolation
        try preflight()
        try await createRemoteRoute()
        try preflight()
        return try commitLocalRoute()
    }
}

struct CloudKitAcceptedShareOperationFence {
    private(set) var engineFetchIsClaimed = false
    private var cleanupMarkerIDs = Set<UUID>()

    var acceptanceCanStage: Bool { !engineFetchIsClaimed }

    mutating func claimEngineFetch() -> Bool {
        guard !engineFetchIsClaimed else { return false }
        engineFetchIsClaimed = true
        return true
    }

    mutating func releaseEngineFetch() {
        engineFetchIsClaimed = false
    }

    mutating func claimCleanup(
        _ marker: CloudKitPendingAcceptedShareCleanup
    ) -> Bool {
        cleanupMarkerIDs.insert(marker.id).inserted
    }

    mutating func releaseCleanup(
        _ marker: CloudKitPendingAcceptedShareCleanup
    ) {
        cleanupMarkerIDs.remove(marker.id)
    }
}

enum CloudKitAcceptedShareFetchFence {
    static func allowsEngineProgress(pendingMarkerCount: Int) -> Bool {
        pendingMarkerCount == 0
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

enum CloudKitTransportGenerationProof {
    static func require(
        expected: UInt64,
        privateGeneration: UInt64,
        sharedGeneration: UInt64,
        eventBufferIsActive: Bool
    ) throws {
        guard privateGeneration == expected,
            sharedGeneration == expected,
            eventBufferIsActive
        else {
            throw CloudKitFamilySyncError.accountBindingMismatch
        }
    }
}

enum CloudKitAcceptedShareBindingFactory {
    static func binding(
        profileID: ProfileID,
        rootRecordID: CKRecord.ID,
        originAccountRecordName: String
    ) -> ProfileCloudBinding {
        ProfileCloudBinding(
            profileID: profileID,
            state: .sharedParticipant,
            zoneName: rootRecordID.zoneID.zoneName,
            ownerName: rootRecordID.zoneID.ownerName,
            rootRecordName: rootRecordID.recordName,
            originAccountRecordName: originAccountRecordName,
            originErasureRoute: .participant
        )
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
public actor CloudKitFamilySyncTransport:
    FamilySyncTransport,
    FamilySyncCanonicalRecoveryTransport
{
    public nonisolated let capability = FamilySyncCapability.iCloud
    public nonisolated let initialProfilePolicy =
        FamilySyncInitialProfilePolicy.discoverBeforeCreating

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
    /// Serializes acceptance/recovery against CKSyncEngine fetch progression
    /// across actor reentrancy. A process crash drops these volatile claims but
    /// preserves every marker, which is when recovery takes ownership.
    private var acceptedShareOperationFence =
        CloudKitAcceptedShareOperationFence()
    private var claimedPrivateRouteProfileIDs = Set<ProfileID>()
    private var canonicalRecoveryInProgress = false

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

    public func replaceRemoteWithCanonicalRecords(
        _ records: [FamilySyncRecord],
        authorization: FamilySyncCanonicalRecoveryAuthorization
    ) async throws -> FamilySyncCanonicalRecoveryReceipt {
        guard !canonicalRecoveryInProgress else {
            throw CloudKitFamilySyncError.operationFailed(
                "Canonical recovery is already in progress"
            )
        }
        for record in records { try record.validateCompatibility() }
        let profileIDs = Array(Set(records.map(\.profileID))).sorted {
            $0.description < $1.description
        }
        let fingerprint = FamilySyncRecordSetFingerprint(records: records)
        guard profileIDs == authorization.expectedPlan.profileIDs,
            records.count == authorization.expectedPlan.recordCount,
            fingerprint == authorization.expectedPlan.recordSetFingerprint
        else {
            throw FamilySyncCanonicalRecoveryError.localSnapshotChanged
        }
        try await requireAuthorizedAccount()
        let account = try await currentAuthorizedAccountRecordName()
        canonicalRecoveryInProgress = true
        await cancelEngines()

        do {
            try stateStore.clear()
            let marker = try metadataStore.prepareCanonicalRecovery(
                authorization: authorization,
                originAccountRecordName: account
            )
            let receipt = try await CloudKitCanonicalRecoveryExecutor().recover(
                prepareDurableMarker: {
                    guard
                        try self.metadataStore.pendingCanonicalRecovery() == marker
                    else {
                        throw CloudKitFamilyPersistenceError.bindingConflict
                    }
                },
                verifyOriginAccount: {
                    try await self.requireCurrentAccountRecordName(account)
                },
                replaceProfiles: {
                    for profileID in profileIDs {
                        try await self.replaceCanonicalProfileZone(
                            profileID,
                            records: records.filter {
                                $0.profileID == profileID
                            },
                            accountRecordName: account
                        )
                    }
                },
                verifyRemoteManifest: {
                    let verified = try await self.fetchCanonicalRecords(
                        profileIDs: profileIDs,
                        accountRecordName: account
                    )
                    guard verified.count == records.count,
                        FamilySyncRecordSetFingerprint(records: verified)
                            == fingerprint
                    else {
                        throw FamilySyncCanonicalRecoveryError
                            .remoteVerificationFailed
                    }
                    return FamilySyncCanonicalRecoveryReceipt(
                        verifiedRemoteFingerprint: fingerprint,
                        recoveredRecordCount: verified.count
                    )
                },
                completeDurableMarker: {
                    try self.metadataStore.completeCanonicalRecovery(marker)
                }
            )
            try stateStore.clear()
            await rebuildEngines()
            canonicalRecoveryInProgress = false
            return receipt
        } catch {
            try? stateStore.clear()
            await rebuildEngines()
            canonicalRecoveryInProgress = false
            throw error
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
        let hasPendingCanonicalRecovery =
            try metadataStore.pendingCanonicalRecovery() != nil
        if canonicalRecoveryInProgress || hasPendingCanonicalRecovery {
            return FamilySyncTransportResult(
                failures: [
                    FamilySyncTransportFailure(key: nil, category: .conflict)
                ]
            )
        }
        if let accountChange = try await accountChangeBlockingUpload() {
            return FamilySyncTransportResult(accountChange: accountChange)
        }
        guard acceptedShareOperationFence.claimEngineFetch() else {
            return FamilySyncTransportResult(
                failures: [
                    FamilySyncTransportFailure(key: nil, category: .conflict)
                ]
            )
        }
        defer { acceptedShareOperationFence.releaseEngineFetch() }
        await rebuildEnginesAfterDurabilityFailureIfNeeded()
        let requestedProfileIDs = Set(profileIDs)
        let recoveryGeneration = privateDelegate.generation

        // A marker exists only when CloudKit may have accepted a share that
        // never reached the atomic local binding commit. Recover it before any
        // Profile can fall back to a private route or upload child payload.
        for marker in try metadataStore.pendingAcceptedShareCleanups() {
            guard claimAcceptedShareCleanup(marker) else { continue }
            do {
                try await recoverAcceptedShareCleanup(
                    marker,
                    generation: recoveryGeneration
                )
                releaseAcceptedShareCleanup(marker)
            } catch {
                releaseAcceptedShareCleanup(marker)
                throw error
            }
        }
        let remainingAcceptedShareMarkers =
            try metadataStore.pendingAcceptedShareCleanups()
        guard
            CloudKitAcceptedShareFetchFence.allowsEngineProgress(
                pendingMarkerCount: remainingAcceptedShareMarkers.count
            )
        else {
            // A concurrently accepting path owns this marker. Do not let
            // CKSyncEngine consume its unbound shared root/children or advance
            // the shared change token before the atomic binding commit.
            return FamilySyncTransportResult(
                failures: [
                    FamilySyncTransportFailure(key: nil, category: .conflict)
                ]
            )
        }

        guard
            await eventBuffer.retryStagedUnboundRecords(
                generation: recoveryGeneration
            )
        else {
            return result(
                await eventBuffer.drain(),
                reachedServerHead: false,
                replayedDurableInbox: false
            )
        }

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
                    binding: binding,
                    generation: recoveryGeneration
                )
            case .rootRecordDeletion, .zoneDeletion:
                let terminal = try await recoverAmbiguousRemoteRemoval(
                    marker,
                    binding: binding,
                    generation: recoveryGeneration
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
                        recovery.binding,
                        generation: recoveryGeneration
                    )
                },
                persistLedger: {},
                eraseZone: {
                    try await self.eraseOwnerPayloadZone(
                        zoneID,
                        binding: recovery.binding,
                        generation: recoveryGeneration
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
                _ = try await CloudKitRemoteOwnerDeletionDominanceExecutor().recover(
                    record: recovery.record,
                    verifyOriginAccount: {
                        try await self.requireCurrentAccountMatchesOrigin(
                            recovery.binding,
                            generation: recoveryGeneration
                        )
                    },
                    persistControlLedger: { record in
                        try await self.persistOwnerDeletionLedger(
                            record,
                            binding: recovery.binding,
                            generation: recoveryGeneration
                        )
                    },
                    eraseZone: {
                        try await self.eraseOwnerPayloadZone(
                            zoneID,
                            binding: recovery.binding,
                            generation: recoveryGeneration
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
                            recovery.binding,
                            generation: recoveryGeneration
                        )
                    },
                    leaveShare: {
                        try await self.leaveSharedProfile(
                            recovery.binding,
                            generation: recoveryGeneration
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
            switch recovery.binding.erasureRoute {
            case .owner:
                guard let zoneID = recovery.binding.zoneID else {
                    throw CloudKitFamilySyncError.operationFailed(
                        "Zone deletion recovery route is incomplete"
                    )
                }
                _ = try await CloudKitRemoteOwnerDeletionDominanceExecutor().recover(
                    record: recovery.record,
                    verifyOriginAccount: {
                        try await self.requireCurrentAccountMatchesOrigin(
                            recovery.binding,
                            generation: recoveryGeneration
                        )
                    },
                    persistControlLedger: { record in
                        try await self.persistOwnerDeletionLedger(
                            record,
                            binding: recovery.binding,
                            generation: recoveryGeneration
                        )
                    },
                    eraseZone: {
                        // The callback already proved this zone absent. Repeat
                        // the idempotent erase so the same proof contract is
                        // used after the deletion barrier is committed.
                        try await self.eraseOwnerPayloadZone(
                            zoneID,
                            binding: recovery.binding,
                            generation: recoveryGeneration
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
                            terminalEvidence: .zoneDeletion
                        )
                    }
                )
            case .participant:
                _ = try await CloudKitProvenZoneDeletionRecoveryExecutor().recover(
                    verifyOriginAccount: {
                        try await self.requireCurrentAccountMatchesOrigin(
                            recovery.binding,
                            generation: recoveryGeneration
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
            case .unresolved:
                throw CloudKitFamilySyncError.accountBindingMismatch
            }
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
        try await requireCurrentAccountRecordName(
            ledgerFetchAccount,
            generation: recoveryGeneration
        )
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
                        try await self.requireCurrentAccountMatchesOrigin(
                            binding,
                            generation: recoveryGeneration
                        )
                    },
                    persistLedger: {},
                    eraseZone: {
                        if binding.state != .ownerDeleted {
                            try await self.eraseOwnerPayloadZone(
                                zoneID,
                                binding: binding,
                                generation: recoveryGeneration
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
        let hasPendingCanonicalRecovery =
            try metadataStore.pendingCanonicalRecovery() != nil
        if canonicalRecoveryInProgress || hasPendingCanonicalRecovery {
            return FamilySyncTransportResult(
                failures: [
                    FamilySyncTransportFailure(key: nil, category: .conflict)
                ]
            )
        }
        if let accountChange = try await accountChangeBlockingUpload() {
            return FamilySyncTransportResult(accountChange: accountChange)
        }
        // `push` and direct transport clients are not required to perform a
        // fetch first. Give every next engine operation the same same-process
        // recovery path after a callback failed to reach durable storage.
        await rebuildEnginesAfterDurabilityFailureIfNeeded()
        guard try metadataStore.pendingAcceptedShareCleanups().isEmpty else {
            return FamilySyncTransportResult(
                failures: [
                    FamilySyncTransportFailure(key: nil, category: .conflict)
                ]
            )
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
        guard !receiptIDs.isEmpty else { return }
        let generation = privateDelegate.generation
        let accountRecordName = try await currentAuthorizedAccountRecordName()
        try await requireCurrentAccountRecordName(
            accountRecordName,
            generation: generation
        )
        try metadataStore.acknowledgeInbox(receiptIDs: receiptIDs)
    }

    public func quarantineFetchedChanges(
        receiptIDs: Set<UUID>,
        category: FamilySyncPrivacySafeErrorCategory
    ) async throws {
        guard !receiptIDs.isEmpty else { return }
        let generation = privateDelegate.generation
        let accountRecordName = try await currentAuthorizedAccountRecordName()
        try await requireCurrentAccountRecordName(
            accountRecordName,
            generation: generation
        )
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
        let generation = privateDelegate.generation
        let acceptingAccount = try await currentAuthorizedAccountRecordName()
        let fetched = try await container.shareMetadatas(for: [url])
        try await requireCurrentAccountRecordName(
            acceptingAccount,
            generation: generation
        )
        guard case .success(let metadata) = fetched[url] else {
            throw CloudKitFamilySyncError.operationFailed("Share metadata unavailable")
        }
        guard let rootRecordID = metadata.hierarchicalRootRecordID else {
            throw CloudKitFamilySyncError.operationFailed("Shared root unavailable")
        }
        let profileID = try CloudKitAcceptedShareRootProof.profileID(
            from: rootRecordID
        )
        guard acceptedShareOperationFence.acceptanceCanStage,
            !claimedPrivateRouteProfileIDs.contains(profileID)
        else {
            throw CloudKitFamilySyncError.operationFailed(
                "Profile synchronization already in progress"
            )
        }
        let preparation: CloudKitPreparedAcceptedShareCleanup
        do {
            preparation = try metadataStore.prepareAcceptedShareCleanup(
                profileID: profileID,
                rootRecordID: rootRecordID,
                shareRecordID: metadata.share.recordID,
                originAccountRecordName: acceptingAccount
            )
        } catch CloudKitFamilyPersistenceError.bindingConflict,
            CloudKitFamilyPersistenceError.accountBindingMismatch
        {
            // The deterministic root exposes collisions before CloudKit gains
            // access, so no compensation is needed and no existing route can
            // be replaced.
            throw CloudKitFamilySyncError.accountBindingMismatch
        }

        switch preparation.state {
        case .alreadyCommitted:
            return profileID
        case .staged(let initialMarker, _):
            guard claimAcceptedShareCleanup(initialMarker) else {
                let committed = metadataStore.binding(for: profileID)
                if committed == initialMarker.binding,
                    metadataStore.isBindingAuthorizedForConfirmedAccount(
                        committed
                    )
                {
                    return profileID
                }
                throw CloudKitFamilySyncError.operationFailed(
                    "Share acceptance already in progress"
                )
            }
            if initialMarker.effectivePhase == .materialized {
                do {
                    try await recoverAcceptedShareCleanup(
                        initialMarker,
                        generation: generation
                    )
                    releaseAcceptedShareCleanup(initialMarker)
                } catch {
                    releaseAcceptedShareCleanup(initialMarker)
                    throw error
                }
                return try await acceptShare(at: url)
            }
            do {
                let materialized =
                    try await CloudKitAcceptedShareTransactionExecutor()
                    .acceptAndCommit(
                        markerIsPending: {
                            self.metadataStore
                                .isAcceptedShareCleanupPending(initialMarker)
                        },
                        acceptAndValidate: {
                            try await self.requireCurrentAccountRecordName(
                                acceptingAccount,
                                generation: generation
                            )
                            let acceptedMarker: CloudKitPendingAcceptedShareCleanup
                            switch metadata.participantStatus {
                            case .pending:
                                let attemptedMarker: CloudKitPendingAcceptedShareCleanup
                                if initialMarker.effectivePhase == .prepared {
                                    // This durable transition is immediately
                                    // before the external acceptance call.
                                    attemptedMarker = try self.metadataStore
                                        .advanceAcceptedShareCleanup(
                                            initialMarker,
                                            to: .acceptanceAttempted
                                        )
                                } else {
                                    attemptedMarker = initialMarker
                                }
                                let accepted = try await self.container.accept([
                                    metadata
                                ])
                                try await self.requireCurrentAccountRecordName(
                                    acceptingAccount,
                                    generation: generation
                                )
                                guard let perShareResult = accepted[metadata]
                                else {
                                    throw CloudKitFamilySyncError.operationFailed(
                                        "Share acceptance result unavailable"
                                    )
                                }
                                switch perShareResult {
                                case .success:
                                    acceptedMarker = try self.metadataStore
                                        .advanceAcceptedShareCleanup(
                                            attemptedMarker,
                                            to: .accepted
                                        )
                                case .failure(let error):
                                    if CloudKitAcceptedShareFailureProofPolicy
                                        .canClearAfterExplicitPerShareFailure(
                                            initialMarker: initialMarker,
                                            attemptedMarker: attemptedMarker
                                        )
                                    {
                                        try self.metadataStore
                                            .completeAcceptedShareCleanup(
                                                attemptedMarker,
                                                proof:
                                                    .explicitAcceptanceFailure
                                            )
                                    }
                                    throw error
                                }
                            case .accepted:
                                let attemptedMarker =
                                    initialMarker.effectivePhase == .prepared
                                    ? try self.metadataStore
                                        .advanceAcceptedShareCleanup(
                                            initialMarker,
                                            to: .acceptanceAttempted
                                        ) : initialMarker
                                acceptedMarker = try self.metadataStore
                                    .advanceAcceptedShareCleanup(
                                        attemptedMarker,
                                        to: .accepted
                                    )
                            case .removed:
                                let proof: CloudKitAcceptedShareCleanupProof =
                                    initialMarker.effectivePhase == .prepared
                                    ? .preparedWithoutAcceptance
                                    : .metadataShowsRemovedParticipant
                                try self.metadataStore
                                    .completeAcceptedShareCleanup(
                                        initialMarker,
                                        proof: proof
                                    )
                                throw CloudKitFamilySyncError.operationFailed(
                                    "Share invitation is no longer active"
                                )
                            case .unknown:
                                throw CloudKitFamilySyncError.operationFailed(
                                    "Share participation status unavailable"
                                )
                            @unknown default:
                                throw CloudKitFamilySyncError.operationFailed(
                                    "Share participation status unavailable"
                                )
                            }
                            let root = try await self.sharedDatabase.record(
                                for: rootRecordID
                            )
                            try await self.requireCurrentAccountRecordName(
                                acceptingAccount,
                                generation: generation
                            )
                            try CloudKitAcceptedShareRootProof.validate(
                                root,
                                expectedRootRecordID: rootRecordID,
                                expectedShareRecordID:
                                    acceptedMarker.shareRecordID,
                                profileID: profileID
                            )
                            guard let shareRecordID = root.share?.recordID else {
                                throw CloudKitFamilySyncError.operationFailed(
                                    "Shared root is not linked to its share"
                                )
                            }
                            let materializedMarker = try self.metadataStore
                                .advanceAcceptedShareCleanup(
                                    acceptedMarker,
                                    to: .materialized,
                                    shareRecordID: shareRecordID
                                )
                            return (root, materializedMarker)
                        },
                        commit: { validated in
                            try self.metadataStore.commitAcceptedShareBinding(
                                validated.1.binding,
                                clearing: validated.1
                            )
                        },
                        compensate: {
                            try await self.recoverAcceptedShareCleanup(
                                initialMarker,
                                generation: generation
                            )
                        }
                    )
                // This cache is reconstructible. It is intentionally outside
                // the acceptance transaction: a cache write failure after the
                // atomic binding commit must never trigger participant leave.
                try metadataStore.saveSystemFields(
                    for: materialized.0,
                    scope: .sharedDatabase
                )
                releaseAcceptedShareCleanup(initialMarker)
                return profileID
            } catch {
                releaseAcceptedShareCleanup(initialMarker)
                throw error
            }
        }
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
        binding: ProfileCloudBinding,
        generation: UInt64? = nil
    ) async throws {
        let recordID = CloudKitFamilyDeletionLedgerCodec.recordID(
            for: tombstone.profileID
        )
        try await requireCurrentAccountMatchesOrigin(
            binding,
            generation: generation
        )
        let existing = try? await privateDatabase.record(for: recordID)
        try await requireCurrentAccountMatchesOrigin(
            binding,
            generation: generation
        )
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
            try await requireCurrentAccountMatchesOrigin(
                binding,
                generation: generation
            )
            let sanitized = try await privateDatabase.modifyRecords(
                saving: [existing],
                deleting: [],
                savePolicy: .ifServerRecordUnchanged,
                atomically: true
            )
            try await requireCurrentAccountMatchesOrigin(
                binding,
                generation: generation
            )
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
        try await requireCurrentAccountMatchesOrigin(
            binding,
            generation: generation
        )
        let zoneResult = try await privateDatabase.modifyRecordZones(
            saving: [controlZone],
            deleting: []
        )
        try await requireCurrentAccountMatchesOrigin(
            binding,
            generation: generation
        )
        if case .failure(let error) = zoneResult.saveResults[controlZone.zoneID],
            (error as? CKError)?.code != .serverRejectedRequest
        {
            throw error
        }

        let ledger = try CloudKitFamilyDeletionLedgerCodec.cloudRecord(
            for: tombstone
        )
        try await requireCurrentAccountMatchesOrigin(
            binding,
            generation: generation
        )
        let save = try await privateDatabase.modifyRecords(
            saving: [ledger],
            deleting: [],
            savePolicy: .changedKeys,
            atomically: true
        )
        try await requireCurrentAccountMatchesOrigin(
            binding,
            generation: generation
        )
        guard case .success = save.saveResults[ledger.recordID] else {
            try await requireCurrentAccountMatchesOrigin(
                binding,
                generation: generation
            )
            if let fetched = try? await privateDatabase.record(for: recordID),
                CloudKitFamilyDeletionLedgerCodec.familyRecord(from: fetched)?
                    .profileID == tombstone.profileID
            {
                try await requireCurrentAccountMatchesOrigin(
                    binding,
                    generation: generation
                )
                return
            }
            try await requireCurrentAccountMatchesOrigin(
                binding,
                generation: generation
            )
            throw CloudKitFamilySyncError.operationFailed(
                "Deletion ledger could not be committed"
            )
        }
    }

    private func eraseOwnerPayloadZone(
        _ zoneID: CKRecordZone.ID,
        binding: ProfileCloudBinding,
        generation: UInt64? = nil
    ) async throws {
        try await requireCurrentAccountMatchesOrigin(
            binding,
            generation: generation
        )
        let result = try await privateDatabase.modifyRecordZones(
            saving: [],
            deleting: [zoneID]
        )
        try await requireCurrentAccountMatchesOrigin(
            binding,
            generation: generation
        )
        try CloudKitTerminalDeletionProof.require(
            result.deleteResults[zoneID],
            acceptingAbsenceCodes: [.zoneNotFound, .unknownItem],
            operation: "Profile zone deletion result unavailable"
        )
    }

    private func claimAcceptedShareCleanup(
        _ marker: CloudKitPendingAcceptedShareCleanup
    ) -> Bool {
        acceptedShareOperationFence.claimCleanup(marker)
    }

    private func releaseAcceptedShareCleanup(
        _ marker: CloudKitPendingAcceptedShareCleanup
    ) {
        acceptedShareOperationFence.releaseCleanup(marker)
    }

    private func recoverAcceptedShareCleanup(
        _ marker: CloudKitPendingAcceptedShareCleanup,
        generation: UInt64
    ) async throws {
        guard
            let current = try metadataStore.pendingAcceptedShareCleanups()
                .first(where: { $0.id == marker.id })
        else { return }
        try await CloudKitAcceptedShareRecoveryExecutor().recover(
            marker: current,
            verifyOriginAccount: {
                try await self.requireCurrentAccountMatchesOrigin(
                    current.binding,
                    generation: generation
                )
            },
            completePrepared: { prepared in
                // This phase was persisted before any acceptance call could
                // start, so no remote grant exists to compensate.
                try self.metadataStore.completeAcceptedShareCleanup(
                    prepared,
                    proof: .preparedWithoutAcceptance
                )
            },
            materialize: { pending in
                // Accept completion may precede residual zone creation.
                // Unknown/zone/permission here are RETRY, never absence.
                let root = try await self.sharedDatabase.record(
                    for: pending.rootRecordID
                )
                try await self.requireCurrentAccountMatchesOrigin(
                    pending.binding,
                    generation: generation
                )
                try CloudKitAcceptedShareRootProof.validate(
                    root,
                    expectedRootRecordID: pending.rootRecordID,
                    expectedShareRecordID: pending.shareRecordID,
                    profileID: pending.profileID
                )
                guard let observedShareID = root.share?.recordID else {
                    throw CloudKitFamilySyncError.operationFailed(
                        "Accepted share has not materialized"
                    )
                }
                return try self.metadataStore.advanceAcceptedShareCleanup(
                    pending,
                    to: .materialized,
                    shareRecordID: observedShareID
                )
            },
            deleteMaterializedShare: { materialized in
                guard let shareRecordID = materialized.shareRecordID else {
                    throw CloudKitFamilySyncError.operationFailed(
                        "Accepted share deletion route unavailable"
                    )
                }
                try await self.deleteSharedParticipantShare(
                    shareRecordID,
                    binding: materialized.binding,
                    generation: generation,
                    acceptingMaterializedAbsence: true
                )
            },
            completeMaterialized: { materialized in
                try self.metadataStore.completeAcceptedShareCleanup(
                    materialized,
                    proof: .materializedShareDeletion
                )
            }
        )
    }

    private func leaveSharedProfile(
        _ binding: ProfileCloudBinding,
        generation: UInt64? = nil
    ) async throws {
        guard let rootID = binding.rootRecordID else {
            throw CloudKitFamilySyncError.malformedRecord(
                binding.profileID.description
            )
        }
        let root: CKRecord
        do {
            try await requireCurrentAccountMatchesOrigin(
                binding,
                generation: generation
            )
            root = try await sharedDatabase.record(for: rootID)
            try await requireCurrentAccountMatchesOrigin(
                binding,
                generation: generation
            )
        } catch let error as CKError
            where error.code == .unknownItem
            || error.code == .zoneNotFound
            || error.code == .permissionFailure
        {
            try await requireCurrentAccountMatchesOrigin(
                binding,
                generation: generation
            )
            return
        }
        guard let shareID = root.share?.recordID else {
            throw CloudKitFamilySyncError.operationFailed(
                "Shared leave proof unavailable"
            )
        }
        try await deleteSharedParticipantShare(
            shareID,
            binding: binding,
            generation: generation,
            acceptingMaterializedAbsence: true
        )
    }

    private func deleteSharedParticipantShare(
        _ shareID: CKRecord.ID,
        binding: ProfileCloudBinding,
        generation: UInt64?,
        acceptingMaterializedAbsence: Bool
    ) async throws {
        guard shareID.zoneID == binding.zoneID else {
            throw CloudKitFamilySyncError.accountBindingMismatch
        }
        try await requireCurrentAccountMatchesOrigin(
            binding,
            generation: generation
        )
        let result = try await sharedDatabase.modifyRecords(
            saving: [],
            deleting: [shareID],
            savePolicy: .ifServerRecordUnchanged,
            atomically: true
        )
        try await requireCurrentAccountMatchesOrigin(
            binding,
            generation: generation
        )
        try CloudKitTerminalDeletionProof.require(
            result.deleteResults[shareID],
            acceptingAbsenceCodes: acceptingMaterializedAbsence
                ? [.unknownItem, .zoneNotFound, .permissionFailure] : [],
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
            guard claimedPrivateRouteProfileIDs.insert(profileID).inserted else {
                throw CloudKitFamilySyncError.operationFailed(
                    "Profile route preparation already in progress"
                )
            }
            let zoneID = privateZoneID(for: profileID)
            let rootID = privateRootRecordID(for: profileID)
            let generation = privateDelegate.generation
            do {
                let account = try await currentAuthorizedAccountRecordName()
                let binding = ProfileCloudBinding(
                    profileID: profileID,
                    state: .privateOwner,
                    zoneName: zoneID.zoneName,
                    ownerName: zoneID.ownerName,
                    rootRecordName: rootID.recordName
                )
                let committed = try await CloudKitPrivateRoutePreparationExecutor()
                    .prepare(
                        preflight: {
                            try self.metadataStore
                                .ensurePrivateRoutePreparationAllowed(
                                    for: profileID
                                )
                        },
                        createRemoteRoute: {
                            try await self.preparePrivateZone(
                                zoneID,
                                profileID: profileID,
                                rootID: rootID,
                                accountRecordName: account,
                                generation: generation
                            )
                        },
                        commitLocalRoute: {
                            try self.metadataStore.save(binding: binding)
                            return self.metadataStore.binding(for: profileID)
                        }
                    )
                claimedPrivateRouteProfileIDs.remove(profileID)
                return committed
            } catch CloudKitFamilyPersistenceError.bindingConflict,
                CloudKitFamilyPersistenceError.accountBindingMismatch
            {
                claimedPrivateRouteProfileIDs.remove(profileID)
                throw CloudKitFamilySyncError.accountBindingMismatch
            } catch {
                claimedPrivateRouteProfileIDs.remove(profileID)
                throw error
            }
        }
    }

    private func replaceCanonicalProfileZone(
        _ profileID: ProfileID,
        records: [FamilySyncRecord],
        accountRecordName: String
    ) async throws {
        guard !records.isEmpty,
            records.allSatisfy({ $0.profileID == profileID })
        else {
            throw FamilySyncCanonicalRecoveryError.profileSetChanged
        }
        let zoneID = privateZoneID(for: profileID)
        let rootID = privateRootRecordID(for: profileID)
        let existing = metadataStore.binding(for: profileID)
        try CloudKitCanonicalRecoveryBindingProof().requirePrivateReplacement(
            binding: existing,
            expectedZoneID: zoneID,
            expectedRootRecordID: rootID,
            isAuthorizedForConfirmedAccount:
                metadataStore.isBindingAuthorizedForConfirmedAccount(existing)
        )

        try await requireCurrentAccountRecordName(accountRecordName)
        let deletion = try await privateDatabase.modifyRecordZones(
            saving: [],
            deleting: [zoneID]
        )
        try await requireCurrentAccountRecordName(accountRecordName)
        try CloudKitTerminalDeletionProof.require(
            deletion.deleteResults[zoneID],
            acceptingAbsenceCodes: [.zoneNotFound, .unknownItem],
            operation: "Canonical Profile zone deletion result unavailable"
        )
        try metadataStore.purgeCanonicalRecoveryTransportBytes(
            profileID: profileID,
            zoneID: zoneID
        )

        let zone = CKRecordZone(zoneID: zoneID)
        let zoneSave = try await privateDatabase.modifyRecordZones(
            saving: [zone],
            deleting: []
        )
        try await requireCurrentAccountRecordName(accountRecordName)
        guard case .success = zoneSave.saveResults[zoneID] else {
            throw CloudKitFamilySyncError.operationFailed(
                "Canonical Profile zone could not be recreated"
            )
        }

        let root = CKRecord(
            recordType: CloudKitFamilyRecordCodec.Schema.rootRecordType,
            recordID: rootID
        )
        root[CloudKitFamilyRecordCodec.Schema.profileID] =
            profileID.rawValue.uuidString as NSString
        let rootSave = try await privateDatabase.modifyRecords(
            saving: [root],
            deleting: [],
            savePolicy: .ifServerRecordUnchanged,
            atomically: true
        )
        try await requireCurrentAccountRecordName(accountRecordName)
        guard case .success(let savedRoot) = rootSave.saveResults[rootID] else {
            throw CloudKitFamilySyncError.operationFailed(
                "Canonical Profile root could not be recreated"
            )
        }
        try metadataStore.saveSystemFields(
            for: savedRoot,
            scope: .privateDatabase
        )

        let cloudRecords = try records.map { record in
            try CloudKitFamilyRecordCodec.cloudRecord(
                for: record,
                recordID: CKRecord.ID(
                    recordName: record.recordName,
                    zoneID: zoneID
                ),
                rootRecordID: rootID,
                scope: .privateDatabase,
                metadataStore: metadataStore,
                photoAssetSourceDirectory: photoAssetSourceDirectory
            )
        }
        let upload = try await privateDatabase.modifyRecords(
            saving: cloudRecords,
            deleting: [],
            savePolicy: .allKeys,
            atomically: true
        )
        try await requireCurrentAccountRecordName(accountRecordName)
        for cloudRecord in cloudRecords {
            guard
                case .success(let saved) = upload.saveResults[
                    cloudRecord.recordID
                ]
            else {
                throw CloudKitFamilySyncError.operationFailed(
                    "Canonical Profile records could not be uploaded"
                )
            }
            try metadataStore.saveSystemFields(
                for: saved,
                scope: .privateDatabase
            )
        }

        let verified = try await fetchCanonicalRecords(
            profileIDs: [profileID],
            accountRecordName: accountRecordName
        )
        guard verified.count == records.count,
            FamilySyncRecordSetFingerprint(records: verified)
                == FamilySyncRecordSetFingerprint(records: records)
        else {
            throw FamilySyncCanonicalRecoveryError.remoteVerificationFailed
        }
        try metadataStore.save(
            binding: ProfileCloudBinding(
                profileID: profileID,
                state: .privateOwner,
                zoneName: zoneID.zoneName,
                ownerName: zoneID.ownerName,
                rootRecordName: rootID.recordName,
                originAccountRecordName: accountRecordName
            )
        )
    }

    private func fetchCanonicalRecords(
        profileIDs: [ProfileID],
        accountRecordName: String
    ) async throws -> [FamilySyncRecord] {
        var records: [FamilySyncRecord] = []
        for profileID in profileIDs {
            let zoneID = privateZoneID(for: profileID)
            let query = CKQuery(
                recordType: CloudKitFamilyRecordCodec.Schema.itemRecordType,
                predicate: NSPredicate(value: true)
            )
            var page = try await privateDatabase.records(
                matching: query,
                inZoneWith: zoneID
            )
            while true {
                try await requireCurrentAccountRecordName(accountRecordName)
                for (_, result) in page.matchResults {
                    let cloudRecord = try result.get()
                    switch CloudKitFamilyRecordCodec.decode(cloudRecord) {
                    case .record(let record):
                        guard record.profileID == profileID else {
                            throw CloudKitFamilySyncError.malformedRecord(
                                cloudRecord.recordID.recordName
                            )
                        }
                        records.append(record)
                    case .quarantine:
                        throw FamilySyncCanonicalRecoveryError
                            .remoteVerificationFailed
                    }
                }
                guard let cursor = page.queryCursor else { break }
                page = try await privateDatabase.records(
                    continuingMatchFrom: cursor
                )
            }
        }
        return records
    }

    private func preparePrivateZone(
        _ zoneID: CKRecordZone.ID,
        profileID: ProfileID,
        rootID: CKRecord.ID,
        accountRecordName: String,
        generation: UInt64
    ) async throws {
        try await requireCurrentAccountRecordName(
            accountRecordName,
            generation: generation
        )
        let zone = CKRecordZone(zoneID: zoneID)
        let zoneResult = try await privateDatabase.modifyRecordZones(
            saving: [zone],
            deleting: []
        )
        try await requireCurrentAccountRecordName(
            accountRecordName,
            generation: generation
        )
        if case .failure(let error) = zoneResult.saveResults[zoneID],
            (error as? CKError)?.code != .serverRejectedRequest
        {
            throw CloudKitFamilySyncError.operationFailed(String(describing: error))
        }

        let fetched = try await privateDatabase.records(for: [rootID])
        try await requireCurrentAccountRecordName(
            accountRecordName,
            generation: generation
        )
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
        try await requireCurrentAccountRecordName(
            accountRecordName,
            generation: generation
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
        binding: ProfileCloudBinding,
        generation: UInt64
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
        try await requireCurrentAccountMatchesOrigin(
            binding,
            generation: generation
        )
        let results = try await privateDatabase.records(for: [recordID])
        try await requireCurrentAccountMatchesOrigin(
            binding,
            generation: generation
        )
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
        binding: ProfileCloudBinding,
        generation: UInt64
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
                    try await self.requireCurrentAccountMatchesOrigin(
                        binding,
                        generation: generation
                    )
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
                        _ = try await CloudKitRemoteOwnerDeletionDominanceExecutor()
                            .recover(
                                record: record,
                                verifyOriginAccount: {
                                    try await self
                                        .requireCurrentAccountMatchesOrigin(
                                            binding,
                                            generation: generation
                                        )
                                },
                                persistControlLedger: { record in
                                    try await self.persistOwnerDeletionLedger(
                                        record,
                                        binding: binding,
                                        generation: generation
                                    )
                                },
                                eraseZone: {
                                    try await self.eraseOwnerPayloadZone(
                                        zoneID,
                                        binding: binding,
                                        generation: generation
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
                                    binding,
                                    generation: generation
                                )
                            },
                            leaveShare: {
                                try await self.leaveSharedProfile(
                                    binding,
                                    generation: generation
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
                    case .unresolved:
                        throw CloudKitFamilySyncError.accountBindingMismatch
                    }
                },
                recoverZoneMissing: {
                    switch binding.erasureRoute {
                    case .owner:
                        guard let zoneID = binding.zoneID else {
                            throw CloudKitFamilySyncError.operationFailed(
                                "Ambiguous owner recovery route is incomplete"
                            )
                        }
                        _ = try await CloudKitRemoteOwnerDeletionDominanceExecutor()
                            .recover(
                                record: record,
                                verifyOriginAccount: {
                                    try await self.requireCurrentAccountMatchesOrigin(
                                        binding,
                                        generation: generation
                                    )
                                },
                                persistControlLedger: { record in
                                    try await self.persistOwnerDeletionLedger(
                                        record,
                                        binding: binding,
                                        generation: generation
                                    )
                                },
                                eraseZone: {
                                    try await self.eraseOwnerPayloadZone(
                                        zoneID,
                                        binding: binding,
                                        generation: generation
                                    )
                                },
                                purgeLocalSources: {
                                    try CloudKitProfilePhotoAssetCodec.removeSources(
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
                        _ = try await CloudKitProvenZoneDeletionRecoveryExecutor()
                            .recover(
                                verifyOriginAccount: {
                                    try await self.requireCurrentAccountMatchesOrigin(
                                        binding,
                                        generation: generation
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
                    case .unresolved:
                        throw CloudKitFamilySyncError.accountBindingMismatch
                    }
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
        _ binding: ProfileCloudBinding,
        generation: UInt64? = nil
    ) async throws {
        if let generation {
            try await requireActiveGeneration(generation)
        }
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
        if let generation {
            try await requireActiveGeneration(generation)
        }
    }

    private func currentAuthorizedAccountRecordName() async throws -> String {
        let current = try await container.userRecordID().recordName
        try await requireCurrentAccountRecordName(current)
        return current
    }

    private func requireCurrentAccountRecordName(
        _ expected: String,
        generation: UInt64? = nil
    ) async throws {
        if let generation {
            try await requireActiveGeneration(generation)
        }
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
        if let generation {
            try await requireActiveGeneration(generation)
        }
    }

    private func requireActiveGeneration(_ generation: UInt64) async throws {
        let isActive = await eventBuffer.isActive(generation)
        try CloudKitTransportGenerationProof.require(
            expected: generation,
            privateGeneration: privateDelegate.generation,
            sharedGeneration: sharedDelegate.generation,
            eventBufferIsActive: isActive
        )
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

    private func rebuildEnginesAfterDurabilityFailureIfNeeded() async {
        let failedGeneration = privateDelegate.generation
        guard
            await eventBuffer.requiresEngineRebuild(
                generation: failedGeneration
            )
        else { return }

        // `durabilityFailure` keeps every stateUpdate callback from persisting
        // while cancellation drains the failed engines. `rebuildEngines()`
        // then loads the last durable serialization, so callbacks consumed
        // only in memory are fetched again without requiring an app restart.
        await cancelEngines()
        await rebuildEngines()
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
            zoneName: CloudKitDeterministicProfileRoute.zoneName(
                for: profileID
            ),
            ownerName: CKCurrentUserDefaultName
        )
    }

    private func privateRootRecordID(for profileID: ProfileID) -> CKRecord.ID {
        CKRecord.ID(
            recordName: CloudKitDeterministicProfileRoute.rootRecordName(
                for: profileID
            ),
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
