import Foundation
import TadaWordsDomain

public protocol FamilySyncRecordStore: Sendable {
    func profileIDsForSync() async throws -> [ProfileID]

    func records(for profileID: ProfileID) async throws -> [FamilySyncRecord]

    func apply(_ records: [FamilySyncRecord], for profileID: ProfileID) async throws

    func validate(
        _ records: [FamilySyncRecord],
        for profileID: ProfileID
    ) async throws

    /// Applies a remote batch only when the repository-owned content still
    /// matches the snapshot read after CloudKit fetch. Implementations may
    /// override this to share a transaction/lease with local writers.
    func applyIfUnchanged(
        _ records: [FamilySyncRecord],
        for profileID: ProfileID,
        expected: FamilySyncRecordSetFingerprint
    ) async throws -> Bool

    func isProfileDeleted(_ profileID: ProfileID) async throws -> Bool
}

extension FamilySyncRecordStore {
    public func isProfileDeleted(_ profileID: ProfileID) async throws -> Bool {
        _ = profileID
        return false
    }

    public func validate(
        _ records: [FamilySyncRecord],
        for profileID: ProfileID
    ) async throws {
        guard records.allSatisfy({ $0.profileID == profileID }) else {
            throw FamilySyncRecordStoreContractError.profileMismatch
        }
        for record in records { try record.validateCompatibility() }
    }

    public func applyIfUnchanged(
        _ records: [FamilySyncRecord],
        for profileID: ProfileID,
        expected: FamilySyncRecordSetFingerprint
    ) async throws -> Bool {
        let current = try await self.records(for: profileID)
        guard FamilySyncRecordSetFingerprint(records: current) == expected else {
            return false
        }
        try await apply(records, for: profileID)
        return true
    }
}

public enum FamilySyncRecordStoreContractError: Error, Equatable, Sendable {
    case profileMismatch
}

public enum FamilySyncTrigger: String, Codable, CaseIterable, Sendable {
    case parentSyncNow
    case localMutation
    case foregroundActivation
    case remoteNotification
    case connectivityRecovery
    case shareAccepted
}

/// Keeps child and parent mutations local-first. Every trigger enters this one
/// idempotent reconciliation path; repository writes never await CloudKit.
public actor LocalFirstFamilySyncCoordinator: FamilySyncCoordinating {
    private let store: any FamilySyncRecordStore
    private let transport: any FamilySyncTransport
    private let preferenceRepository: any FamilySyncPreferenceRepository
    private let journalRepository: any FamilySyncJournalRepository
    private let deviceID: String
    private let clock: any AppClock
    private var currentStatus: FamilySyncStatus = .idle
    private var reconciliationInProgress = false
    private var needsAnotherPass = false
    private var consentGeneration: UInt64 = 0
    /// Actor-local desired state closes the reentrancy window while the
    /// preference or CloudKit cancellation is awaiting I/O.
    private var desiredEnabled: Bool?
    private var explicitlyRequestedProfileIDs: Set<ProfileID> = []

    public init(
        store: any FamilySyncRecordStore,
        transport: any FamilySyncTransport,
        preferenceRepository: any FamilySyncPreferenceRepository =
            InMemoryFamilySyncPreferenceRepository(),
        journalRepository: any FamilySyncJournalRepository =
            VolatileFamilySyncJournalRepository(),
        deviceID: String = "volatile-device",
        clock: any AppClock = SystemAppClock()
    ) {
        self.store = store
        self.transport = transport
        self.preferenceRepository = preferenceRepository
        self.journalRepository = journalRepository
        self.deviceID = deviceID.trimmingCharacters(in: .whitespacesAndNewlines)
        self.clock = clock
    }

    public func isEnabled() async -> Bool {
        guard transport.capability == .iCloud else { return false }
        if let desiredEnabled { return desiredEnabled }
        return (try? await preferenceRepository.isEnabled()) ?? false
    }

    public func setEnabled(_ isEnabled: Bool) async throws -> FamilySyncStatus {
        guard transport.capability == .iCloud else {
            if isEnabled { throw FamilySyncConsentError.deviceOnly }
            currentStatus = Self.deviceOnlyStatus
            return currentStatus
        }

        consentGeneration &+= 1
        if isEnabled {
            // Enabling remains fail-closed until both account confirmation and
            // durable consent succeed.
            desiredEnabled = false
            do {
                let accountChange = try await transport.confirmCurrentAccount()
                if accountChange != nil {
                    try await journalRepository
                        .invalidateAcknowledgementsForAccountChange(at: clock.now)
                }
                try await preferenceRepository.setEnabled(true, updatedAt: clock.now)
                desiredEnabled = true
                await FamilySyncRemoteNotificationBridge.shared
                    .requestRegistration()
            } catch {
                desiredEnabled = false
                await transport.suspend()
                throw error
            }
        } else {
            // Make the actor gate false before the first suspension point, and
            // persist opt-out before waiting for transport cancellation.
            desiredEnabled = false
            try await preferenceRepository.setEnabled(false, updatedAt: clock.now)
            await FamilySyncRemoteNotificationBridge.shared
                .requestUnregistration()
            await transport.suspend()
        }
        guard isEnabled else {
            currentStatus = Self.optedOutStatus
            return currentStatus
        }
        return await synchronize(trigger: .parentSyncNow)
    }

    public func synchronize() async -> FamilySyncStatus {
        await synchronize(trigger: .foregroundActivation)
    }

    public func synchronize(trigger: FamilySyncTrigger) async -> FamilySyncStatus {
        _ = trigger
        guard !reconciliationInProgress else {
            needsAnotherPass = true
            return currentStatus
        }
        reconciliationInProgress = true
        var immediatePassCount = 0
        repeat {
            needsAnotherPass = false
            currentStatus = await reconcile(generation: consentGeneration)
            immediatePassCount += 1
            if needsAnotherPass,
                immediatePassCount >= Self.maximumImmediateReconciliationPasses
            {
                needsAnotherPass = false
                currentStatus = .failed(
                    message:
                        "Sync needs attention. Local learning data is safe on this device.",
                    pendingCount: await durablePendingCount()
                )
            }
        } while needsAnotherPass
        reconciliationInProgress = false
        return currentStatus
    }

    public func status() async -> FamilySyncStatus {
        guard transport.capability == .iCloud else {
            currentStatus = Self.deviceOnlyStatus
            return currentStatus
        }
        guard await isEnabled() else {
            currentStatus = Self.optedOutStatus
            return currentStatus
        }
        guard currentStatus == .idle,
            let durable = try? await journalRepository.durableStatus()
        else { return currentStatus }
        switch durable.condition {
        case .waitingForConnection:
            currentStatus = Self.pendingOfflineStatus(from: durable)
        case .iCloudUnavailable:
            currentStatus = .iCloudUnavailable(
                message: Self.message(for: .account)
            )
        case .needsAttention:
            currentStatus = .failed(
                message: Self.message(for: durable.errorCategory ?? .unknown),
                pendingCount: durable.pendingCount
            )
        case .idle:
            if durable.pendingCount > 0 {
                currentStatus = Self.pendingOfflineStatus(from: durable)
            } else if let lastSuccessAt = durable.lastSuccessAt {
                currentStatus = .synced(at: lastSuccessAt)
            }
        }
        return currentStatus
    }

    public func createShare(for profileID: ProfileID) async throws -> URL {
        guard transport.capability == .iCloud else {
            throw FamilySyncConsentError.deviceOnly
        }
        guard await isEnabled() else {
            throw FamilySyncConsentError.optInRequired
        }
        return try await transport.createShare(for: profileID)
    }

    public func acceptShare(at url: URL) async throws {
        guard transport.capability == .iCloud else {
            throw FamilySyncConsentError.deviceOnly
        }
        guard await isEnabled() else {
            throw FamilySyncConsentError.optInRequired
        }
        let profileID = try await transport.acceptShare(at: url)
        explicitlyRequestedProfileIDs.insert(profileID)
        let result = await synchronize(trigger: .shareAccepted)
        if case .failed = result {
            throw FamilySyncReconciliationError.failedAfterAcceptingShare
        }
    }

    private func reconcile(generation: UInt64) async -> FamilySyncStatus {
        guard transport.capability == .iCloud else {
            currentStatus = Self.deviceOnlyStatus
            return currentStatus
        }
        guard await isEnabled() else {
            currentStatus = Self.optedOutStatus
            return currentStatus
        }

        let now = clock.now
        let profileIDs: [ProfileID]
        let versionedRecords: [FamilySyncRecord]
        do {
            profileIDs = Array(
                Set(try await store.profileIDsForSync())
                    .union(explicitlyRequestedProfileIDs)
            ).sorted { $0.description < $1.description }
            var rawRecords: [FamilySyncRecord] = []
            for profileID in profileIDs {
                rawRecords += try await store.records(for: profileID)
            }
            versionedRecords = try await journalRepository.reconcileLocalRecords(
                rawRecords,
                deviceID: deviceID,
                now: now
            )
        } catch {
            currentStatus = .failed(
                message: Self.privacySafeMessage(for: error),
                pendingCount: await durablePendingCount()
            )
            return currentStatus
        }

        let pendingCount = await durablePendingCount()
        currentStatus = .syncing(pendingCount: pendingCount)
        let availability = await transport.availability()
        guard availability == .available else {
            switch availability {
            case .available:
                break
            case .deviceOnly:
                currentStatus = Self.deviceOnlyStatus
            case .temporarilyUnavailable:
                try? await journalRepository.recordParentVisibleCondition(
                    .waitingForConnection,
                    errorCategory: .connectivity,
                    at: now
                )
                currentStatus = await pendingOfflineStatus(
                    fallbackPendingCount: pendingCount
                )
            case .noAccount, .restricted:
                try? await journalRepository.recordParentVisibleCondition(
                    .iCloudUnavailable,
                    errorCategory: .account,
                    at: now
                )
                currentStatus = .iCloudUnavailable(
                    message: Self.message(for: availability)
                )
            }
            return currentStatus
        }

        var dueChanges: [FamilySyncPendingOperation] = []
        do {
            var terminalProfileIDs = Set<ProfileID>()
            for profileID in profileIDs
            where try await store.isProfileDeleted(profileID) {
                terminalProfileIDs.insert(profileID)
            }
            let fetched = try await transport.fetchChanges(
                for: profileIDs,
                terminalProfileIDs: terminalProfileIDs
            )
            guard await acceptResult(for: generation) else { return currentStatus }
            if let accountChange = fetched.accountChange {
                try await journalRepository.invalidateAcknowledgementsForAccountChange(
                    at: now
                )
                currentStatus = .iCloudUnavailable(
                    message: Self.message(for: accountChange)
                )
                return currentStatus
            }

            let freshProfileIDs = try await store.profileIDsForSync()
            let freshRecords = try await versionedLocalRecords(
                profileIDs: freshProfileIDs,
                now: now
            )
            let protectedKeys = changedKeys(
                before: versionedRecords,
                after: freshRecords
            )
            let sanitized = try await sanitizeRemoteRecords(
                fetched.records,
                against: freshRecords,
                receipts: fetched.receipts,
                hasDurableReceipts: !fetched.receiptIDs.isEmpty
            )
            let remoteOutcome = try await applyRemoteWinners(
                sanitized.records,
                against: freshRecords,
                protectedKeys: protectedKeys
            )
            try await journalRepository.recordAppliedRemote(
                records: remoteOutcome.serverConfirmed,
                deletions: fetched.deletions,
                at: now
            )
            if needsAnotherPass || !remoteOutcome.deferredKeys.isEmpty {
                // At least one compare-and-apply lost to a local commit. Keep
                // every transport receipt durable and replay the batch; ACKing
                // here could discard the only copy of an unapplied record.
                currentStatus = .syncing(
                    pendingCount: await durablePendingCount()
                )
                return currentStatus
            }
            try await transport.acknowledgeFetchedChanges(
                receiptIDs: fetched.receiptIDs.subtracting(
                    sanitized.quarantinedReceiptIDs
                )
            )
            explicitlyRequestedProfileIDs.subtract(
                fetched.records.map(\.profileID)
            )
            if !fetched.failures.isEmpty {
                try await journalRepository.recordTransportResult(
                    acknowledged: [],
                    failures: fetched.failures,
                    at: now
                )
                currentStatus = await parentVisibleFailureStatus(
                    for: fetched.failures[0].category,
                    fallbackPendingCount: await durablePendingCount()
                )
                return currentStatus
            }

            // Replaying a durable transport inbox proves only that the fetched
            // bytes survived a prior process death. It does not prove this
            // device has fetched the current server head. Apply and ACK first,
            // then enter the same coalesced path again before any upload.
            if fetched.replayedDurableInbox || !fetched.reachedServerHead {
                needsAnotherPass = true
                currentStatus = .syncing(
                    pendingCount: await durablePendingCount()
                )
                return currentStatus
            }

            let postFetchProfileIDs = try await store.profileIDsForSync()
            let postFetchRecords = try await versionedLocalRecords(
                profileIDs: postFetchProfileIDs,
                now: now
            )
            dueChanges = try await journalRepository.pendingChanges(
                using: postFetchRecords,
                now: now
            ).filter { !sanitized.quarantinedKeys.contains($0.key) }
            let sent: FamilySyncTransportResult
            if dueChanges.isEmpty {
                sent = FamilySyncTransportResult()
            } else {
                try await journalRepository.recordAttempt(
                    keys: Set(dueChanges.map(\.key)),
                    at: now
                )
                sent = try await transport.sendChanges(dueChanges)
            }
            guard await acceptResult(for: generation) else { return currentStatus }
            if let accountChange = sent.accountChange {
                try await journalRepository.invalidateAcknowledgementsForAccountChange(
                    at: now
                )
                currentStatus = .iCloudUnavailable(
                    message: Self.message(for: accountChange)
                )
                return currentStatus
            }
            let conflictRequiresFetch =
                sent.requiresFetchPass
                || (sent.quarantinedRecordCount == 0
                    && sent.failures.contains { $0.category == .conflict })
            let durableFailures =
                conflictRequiresFetch
                ? sent.failures.filter { $0.category != .conflict }
                : sent.failures
            try await journalRepository.recordTransportResult(
                acknowledged: sent.acknowledged,
                failures: durableFailures,
                at: now
            )

            if conflictRequiresFetch {
                // `serverRecordChanged` has already persisted the server
                // record and fresh system fields. Consume that durable inbox,
                // ACK it, fetch the current head, and only then decide whether
                // the local winner still needs a change-tag retry.
                needsAnotherPass = true
                currentStatus = .syncing(
                    pendingCount: await durablePendingCount()
                )
                return currentStatus
            }

            let remaining = await durablePendingCount()
            let quarantinedCount =
                fetched.quarantinedRecordCount
                + sanitized.quarantinedRecordCount
                + sent.quarantinedRecordCount
            if quarantinedCount > 0 {
                try? await journalRepository.recordParentVisibleCondition(
                    .needsAttention,
                    errorCategory: .compatibility,
                    at: now
                )
                currentStatus = .failed(
                    message:
                        "Some newer or damaged sync data was kept aside. Local learning data is safe.",
                    pendingCount: remaining
                )
            } else if let failure = sent.failures.first {
                currentStatus = await parentVisibleFailureStatus(
                    for: failure.category,
                    fallbackPendingCount: remaining
                )
            } else if remaining > 0 {
                currentStatus = await pendingOfflineStatus(
                    fallbackPendingCount: remaining
                )
            } else {
                currentStatus = .synced(at: now)
            }
        } catch {
            let failures = dueChanges.map {
                FamilySyncTransportFailure(
                    key: $0.key,
                    category: Self.category(for: error)
                )
            }
            try? await journalRepository.recordTransportResult(
                acknowledged: [],
                failures: failures.isEmpty
                    ? [FamilySyncTransportFailure(key: nil, category: Self.category(for: error))]
                    : failures,
                at: now
            )
            currentStatus = await parentVisibleFailureStatus(
                for: Self.category(for: error),
                fallbackPendingCount: await durablePendingCount()
            )
        }
        return currentStatus
    }

    private func acceptResult(for generation: UInt64) async -> Bool {
        guard generation == consentGeneration else {
            if await isEnabled() {
                needsAnotherPass = true
                currentStatus = await pendingOfflineStatus(
                    fallbackPendingCount: await durablePendingCount()
                )
            } else {
                currentStatus = Self.optedOutStatus
            }
            return false
        }
        guard await isEnabled() else {
            currentStatus = Self.optedOutStatus
            return false
        }
        return true
    }

    private struct SanitizedRemoteRecords {
        let records: [FamilySyncRecord]
        let quarantinedReceiptIDs: Set<UUID>
        let quarantinedKeys: Set<FamilySyncChangeKey>
        let quarantinedRecordCount: Int
    }

    private struct RemoteApplyOutcome {
        let applied: [FamilySyncRecord]
        let serverConfirmed: [FamilySyncRecord]
        let deferredKeys: Set<FamilySyncChangeKey>
    }

    private func sanitizeRemoteRecords(
        _ remoteRecords: [FamilySyncRecord],
        against localRecords: [FamilySyncRecord],
        receipts: [FamilySyncFetchedReceipt],
        hasDurableReceipts: Bool
    ) async throws -> SanitizedRemoteRecords {
        var accepted: [FamilySyncRecord] = []
        var quarantined: [(FamilySyncRecord, FamilySyncPrivacySafeErrorCategory)] = []

        for profileID in Set(remoteRecords.map(\.profileID)).sorted(by: {
            $0.description < $1.description
        }) {
            var candidates = remoteRecords.filter { $0.profileID == profileID }
            while !candidates.isEmpty {
                do {
                    try await store.validate(candidates, for: profileID)
                    accepted += candidates
                    break
                } catch let error as RepositoryFamilySyncError {
                    let identity: (String, FamilySyncRecordKind)
                    switch error {
                    case .invalidRecordIdentity(let recordName, let kind),
                        .invalidRecordPayload(let recordName, let kind):
                        identity = (recordName, kind)
                    case .profileMismatch:
                        throw error
                    }
                    guard
                        let offending = candidates.first(where: {
                            $0.recordName == identity.0 && $0.kind == identity.1
                        })
                    else { throw error }
                    quarantined.append((offending, .compatibility))
                    candidates.removeAll { $0 == offending }
                }
            }
        }

        let localByKey = Dictionary(
            uniqueKeysWithValues: localRecords.map {
                (
                    FamilySyncChangeKey(
                        profileID: $0.profileID,
                        recordName: $0.recordName
                    ),
                    $0
                )
            }
        )
        accepted.removeAll { remote in
            let key = FamilySyncChangeKey(
                profileID: remote.profileID,
                recordName: remote.recordName
            )
            guard let local = localByKey[key],
                local.payloadChecksum != remote.payloadChecksum
            else { return false }
            let immutableConflict =
                remote.kind == .attempt
                || remote.kind == .attemptCorrection
            let revisionCollision = local.logicalRevision == remote.logicalRevision
            guard immutableConflict || revisionCollision else { return false }
            quarantined.append((remote, .conflict))
            return true
        }

        var receiptIDsByCategory: [FamilySyncPrivacySafeErrorCategory: Set<UUID>] = [:]
        for (record, category) in quarantined {
            let key = FamilySyncChangeKey(
                profileID: record.profileID,
                recordName: record.recordName
            )
            let matching = Set(
                receipts.filter {
                    $0.key == key && $0.operation == .save
                }.map(\.id)
            )
            if hasDurableReceipts, matching.isEmpty {
                throw FamilySyncReconciliationError.missingReceiptForQuarantine(key)
            }
            receiptIDsByCategory[category, default: []].formUnion(matching)
        }
        for (category, receiptIDs) in receiptIDsByCategory where !receiptIDs.isEmpty {
            try await transport.quarantineFetchedChanges(
                receiptIDs: receiptIDs,
                category: category
            )
        }
        return SanitizedRemoteRecords(
            records: accepted,
            quarantinedReceiptIDs: receiptIDsByCategory.values.reduce(into: []) {
                $0.formUnion($1)
            },
            quarantinedKeys: Set(
                quarantined.map {
                    FamilySyncChangeKey(
                        profileID: $0.0.profileID,
                        recordName: $0.0.recordName
                    )
                }),
            quarantinedRecordCount: quarantined.count
        )
    }

    private func applyRemoteWinners(
        _ remoteRecords: [FamilySyncRecord],
        against localRecords: [FamilySyncRecord],
        protectedKeys: Set<FamilySyncChangeKey>
    ) async throws -> RemoteApplyOutcome {
        let localByKey = Dictionary(
            uniqueKeysWithValues: localRecords.map {
                (
                    FamilySyncChangeKey(
                        profileID: $0.profileID,
                        recordName: $0.recordName
                    ),
                    $0
                )
            }
        )
        var winnersByProfile: [ProfileID: [FamilySyncRecord]] = [:]
        var serverConfirmed: [FamilySyncRecord] = []
        var deferredKeys = Set<FamilySyncChangeKey>()
        for remote in remoteRecords {
            try remote.validateCompatibility()
            let key = FamilySyncChangeKey(
                profileID: remote.profileID,
                recordName: remote.recordName
            )
            let profileIsDeleted = try await store.isProfileDeleted(
                remote.profileID
            )
            guard !profileIsDeleted || remote.kind == .profileDeletion else {
                // The durable deletion ledger dominates child-only stale deltas
                // even when no tombstone appears in this engine event batch.
                continue
            }
            if let local = localByKey[key],
                local.logicalRevision == remote.logicalRevision,
                local.payloadChecksum != remote.payloadChecksum
            {
                throw FamilySyncReconciliationError.conflictingRevision(key)
            }
            let winner = FamilySyncConflictResolver.resolved(
                local: localByKey[key],
                remote: remote
            )
            if protectedKeys.contains(key), winner == remote,
                localByKey[key] != remote
            {
                deferredKeys.insert(key)
                continue
            }
            guard winner == remote else { continue }
            if localByKey[key] == remote {
                serverConfirmed.append(remote)
                continue
            }
            winnersByProfile[remote.profileID, default: []].append(remote)
        }
        var applied: [FamilySyncRecord] = []
        for (profileID, records) in winnersByProfile {
            let expected = FamilySyncRecordSetFingerprint(
                records: localRecords.filter { $0.profileID == profileID }
            )
            let sorted = records.sorted { $0.recordName < $1.recordName }
            if try await store.applyIfUnchanged(
                sorted,
                for: profileID,
                expected: expected
            ) {
                applied += sorted
                serverConfirmed += sorted
            } else {
                // A local commit won the race after fetch. Never overwrite it;
                // the next pass assigns its durable revision and resolves from
                // a fresh server head.
                needsAnotherPass = true
                deferredKeys.formUnion(
                    sorted.map {
                        FamilySyncChangeKey(
                            profileID: $0.profileID,
                            recordName: $0.recordName
                        )
                    })
            }
        }
        return RemoteApplyOutcome(
            applied: applied,
            serverConfirmed: serverConfirmed,
            deferredKeys: deferredKeys
        )
    }

    private func versionedLocalRecords(
        profileIDs: [ProfileID],
        now: Date
    ) async throws -> [FamilySyncRecord] {
        var rawRecords: [FamilySyncRecord] = []
        for profileID in profileIDs {
            rawRecords += try await store.records(for: profileID)
        }
        return try await journalRepository.reconcileLocalRecords(
            rawRecords,
            deviceID: deviceID,
            now: now
        )
    }

    private func changedKeys(
        before: [FamilySyncRecord],
        after: [FamilySyncRecord]
    ) -> Set<FamilySyncChangeKey> {
        let beforeByKey = Dictionary(
            uniqueKeysWithValues: before.map {
                (FamilySyncChangeKey(profileID: $0.profileID, recordName: $0.recordName), $0)
            }
        )
        let afterByKey = Dictionary(
            uniqueKeysWithValues: after.map {
                (FamilySyncChangeKey(profileID: $0.profileID, recordName: $0.recordName), $0)
            }
        )
        return Set(beforeByKey.keys).union(afterByKey.keys).filter { key in
            guard let lhs = beforeByKey[key], let rhs = afterByKey[key] else {
                return true
            }
            return lhs.payloadChecksum != rhs.payloadChecksum
                || lhs.isDeleted != rhs.isDeleted
                || lhs.logicalRevision != rhs.logicalRevision
        }
    }

    private func durablePendingCount() async -> Int {
        (try? await journalRepository.durableStatus().pendingCount) ?? 0
    }

    private func pendingOfflineStatus(
        fallbackPendingCount: Int
    ) async -> FamilySyncStatus {
        guard let durable = try? await journalRepository.durableStatus() else {
            return .pendingOffline(pendingCount: fallbackPendingCount)
        }
        return Self.pendingOfflineStatus(from: durable)
    }

    private static func pendingOfflineStatus(
        from durable: FamilySyncDurableStatus
    ) -> FamilySyncStatus {
        .pendingOffline(
            pendingCount: durable.pendingCount,
            retryCount: durable.retryCount,
            nextRetryAt: durable.nextRetryAt
        )
    }

    private func parentVisibleFailureStatus(
        for category: FamilySyncPrivacySafeErrorCategory,
        fallbackPendingCount: Int
    ) async -> FamilySyncStatus {
        switch FamilySyncDurableStatus.condition(for: category) {
        case .waitingForConnection:
            await pendingOfflineStatus(
                fallbackPendingCount: fallbackPendingCount
            )
        case .iCloudUnavailable:
            .iCloudUnavailable(message: Self.message(for: category))
        case .needsAttention, .idle:
            .failed(
                message: Self.message(for: category),
                pendingCount: fallbackPendingCount
            )
        }
    }

    private static func message(for availability: FamilySyncAvailability) -> String {
        switch availability {
        case .available:
            "Sync is available."
        case .deviceOnly:
            "This version keeps learning data on this device."
        case .noAccount:
            "Sign in to iCloud to sync Tada Words."
        case .restricted:
            "iCloud sync is restricted on this device."
        case .temporarilyUnavailable:
            "Sync will retry when iCloud is available."
        }
    }

    private static func message(for change: FamilySyncAccountChange) -> String {
        switch change {
        case .signedIn:
            "iCloud account access changed. A parent must confirm Family Sync again."
        case .signedOut:
            "Sign in to iCloud, then ask a parent to confirm Family Sync again."
        case .switchedAccounts:
            "The iCloud account changed. Local data is safe and will not upload until a parent confirms Family Sync again."
        }
    }

    private static func message(
        for category: FamilySyncPrivacySafeErrorCategory
    ) -> String {
        switch category {
        case .account:
            "Check the iCloud account, then ask a parent to try again."
        case .connectivity, .rateLimited, .server:
            "Sync will retry. Local learning data is safe on this device."
        case .compatibility, .corruptState, .conflict, .unknown:
            "Sync needs attention. Local learning data is safe on this device."
        }
    }

    private static func privacySafeMessage(for error: Error) -> String {
        _ = error
        return "Sync could not finish. Local learning data is safe and will retry."
    }

    private static func category(
        for error: Error
    ) -> FamilySyncPrivacySafeErrorCategory {
        if let error = error as? FamilySyncEnvelopeError {
            _ = error
            return .compatibility
        }
        if let error = error as? FamilySyncTransportContractError,
            error == .corruptState
        {
            return .corruptState
        }
        return .unknown
    }

    private static let optedOutStatus = FamilySyncStatus.optedOut(
        message:
            "Family sync is off. Learning data stays on this device until a parent turns it on."
    )

    private static let maximumImmediateReconciliationPasses = 8

    private static let deviceOnlyStatus = FamilySyncStatus.deviceOnly(
        message:
            "This version keeps learning data on this device. Family sync and invitations are unavailable."
    )
}

public enum FamilySyncReconciliationError: Error, Equatable, Sendable {
    case failedAfterAcceptingShare
    case conflictingRevision(FamilySyncChangeKey)
    case missingReceiptForQuarantine(FamilySyncChangeKey)
}
