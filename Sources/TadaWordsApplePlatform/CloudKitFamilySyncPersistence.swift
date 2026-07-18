@preconcurrency import CloudKit
import Foundation
import TadaWordsDomain

enum CloudKitFamilyDatabaseScope: String, Codable, CaseIterable, Sendable {
    case privateDatabase
    case sharedDatabase
}

enum ProfileCloudBindingState: String, Codable, Equatable, Sendable {
    case unbound
    case privateOwner
    case sharedParticipant
    case revoked
    case ownerDeleted
    case participantLeft
}

struct ProfileCloudBinding: Codable, Equatable, Sendable {
    let profileID: ProfileID
    let state: ProfileCloudBindingState
    let zoneName: String?
    let ownerName: String?
    let rootRecordName: String?

    static func unbound(_ profileID: ProfileID) -> Self {
        Self(
            profileID: profileID,
            state: .unbound,
            zoneName: nil,
            ownerName: nil,
            rootRecordName: nil
        )
    }

    var databaseScope: CloudKitFamilyDatabaseScope? {
        switch state {
        case .unbound, .revoked, .ownerDeleted, .participantLeft:
            nil
        case .privateOwner:
            .privateDatabase
        case .sharedParticipant:
            .sharedDatabase
        }
    }

    var zoneID: CKRecordZone.ID? {
        guard let zoneName, let ownerName else { return nil }
        return CKRecordZone.ID(zoneName: zoneName, ownerName: ownerName)
    }

    var rootRecordID: CKRecord.ID? {
        guard let zoneID, let rootRecordName else { return nil }
        return CKRecord.ID(recordName: rootRecordName, zoneID: zoneID)
    }
}

struct CloudKitFamilyQuarantineEntry: Codable, Equatable, Sendable {
    let id: UUID
    let scope: CloudKitFamilyDatabaseScope
    let recordName: String
    let zoneName: String
    let ownerName: String
    let reason: FamilySyncPrivacySafeErrorCategory
    let envelopeData: Data?
    let quarantinedAt: Date
}

private struct CloudKitProtectedRecordKey: Codable, Equatable, Hashable {
    let scope: CloudKitFamilyDatabaseScope
    let recordName: String
    let zoneName: String
    let ownerName: String
}

private struct CloudKitSystemFieldsEntry: Codable, Equatable {
    let scope: CloudKitFamilyDatabaseScope
    let recordName: String
    let zoneName: String
    let ownerName: String
    let data: Data

    var key: String {
        "\(scope.rawValue)|\(ownerName)|\(zoneName)|\(recordName)"
    }
}

struct CloudKitFamilyInboxEntry: Codable, Equatable, Sendable {
    enum Operation: String, Codable, Equatable, Sendable {
        case save
        case delete
    }

    let receiptID: UUID
    let scope: CloudKitFamilyDatabaseScope
    let zoneName: String
    let ownerName: String
    let operation: Operation
    let record: FamilySyncRecord?
    let deletionKey: FamilySyncChangeKey?
    let receivedAt: Date
}

private struct CloudKitFamilyMetadataSnapshot: Codable {
    static let currentSchemaVersion = 1

    var schemaVersion = currentSchemaVersion
    var confirmedAccountRecordName: String?
    var requiresAccountConfirmation = true
    var bindings: [ProfileCloudBinding] = []
    var systemFields: [CloudKitSystemFieldsEntry] = []
    var quarantined: [CloudKitFamilyQuarantineEntry] = []
    var protectedRecordKeys: [CloudKitProtectedRecordKey] = []
    var inbox: [CloudKitFamilyInboxEntry] = []
}

enum CloudKitFamilyAccountGate: Equatable {
    case authorized
    case requiresConfirmation(FamilySyncAccountChange)
}

final class CloudKitFamilyMetadataStore: @unchecked Sendable {
    private let snapshotURL: URL
    private let lock = NSLock()
    private var cached: CloudKitFamilyMetadataSnapshot?
    private var loadFailed = false

    init(snapshotURL: URL) {
        self.snapshotURL = snapshotURL
    }

    func binding(for profileID: ProfileID) -> ProfileCloudBinding {
        withLock {
            let snapshot = loadLocked()
            return snapshot.bindings.first { $0.profileID == profileID }
                ?? .unbound(profileID)
        }
    }

    func binding(for zoneID: CKRecordZone.ID) -> ProfileCloudBinding? {
        withLock {
            loadLocked().bindings.first {
                $0.zoneName == zoneID.zoneName && $0.ownerName == zoneID.ownerName
            }
        }
    }

    func revokeBinding(for zoneID: CKRecordZone.ID) throws {
        try withLock {
            var snapshot = loadLocked()
            guard
                let index = snapshot.bindings.firstIndex(where: {
                    $0.zoneName == zoneID.zoneName && $0.ownerName == zoneID.ownerName
                })
            else { return }
            let existing = snapshot.bindings[index]
            let nextState: ProfileCloudBindingState =
                switch existing.state {
                case .ownerDeleted:
                    .ownerDeleted
                case .participantLeft:
                    .participantLeft
                case .unbound, .privateOwner, .sharedParticipant, .revoked:
                    .revoked
                }
            snapshot.bindings[index] = ProfileCloudBinding(
                profileID: existing.profileID,
                state: nextState,
                zoneName: existing.zoneName,
                ownerName: existing.ownerName,
                rootRecordName: existing.rootRecordName
            )
            // Revocation is a terminal privacy boundary too. Keep only the
            // minimal deletion fact that was durably appended before this
            // transition; all child payload, CKAsset metadata, quarantine,
            // and stale record locks for the former shared zone are removed
            // in the same atomic snapshot write.
            purgeTransportBytes(
                for: existing.profileID,
                zoneName: existing.zoneName,
                ownerName: existing.ownerName,
                snapshot: &snapshot
            )
            try persistLocked(snapshot)
        }
    }

    func markOwnerDeleted(
        profileID: ProfileID,
        previous: ProfileCloudBinding? = nil
    ) throws {
        try markTerminal(
            profileID: profileID,
            state: .ownerDeleted,
            previous: previous
        )
    }

    func markParticipantLeft(
        profileID: ProfileID,
        previous: ProfileCloudBinding? = nil
    ) throws {
        try markTerminal(
            profileID: profileID,
            state: .participantLeft,
            previous: previous
        )
    }

    private func markTerminal(
        profileID: ProfileID,
        state: ProfileCloudBindingState,
        previous: ProfileCloudBinding?
    ) throws {
        precondition(state == .ownerDeleted || state == .participantLeft)
        let source = previous ?? binding(for: profileID)
        let terminal = ProfileCloudBinding(
            profileID: profileID,
            state: state,
            zoneName: source.zoneName,
            ownerName: source.ownerName,
            rootRecordName: source.rootRecordName
        )
        try withLock {
            var snapshot = loadLocked()
            snapshot.bindings.removeAll { $0.profileID == profileID }
            snapshot.bindings.removeAll {
                terminal.zoneName != nil
                    && $0.zoneName == terminal.zoneName
                    && $0.ownerName == terminal.ownerName
            }
            snapshot.bindings.append(terminal)
            snapshot.bindings.sort {
                $0.profileID.description < $1.profileID.description
            }
            purgeTransportBytes(
                for: profileID,
                zoneName: terminal.zoneName,
                ownerName: terminal.ownerName,
                snapshot: &snapshot
            )
            try persistLocked(snapshot)
        }
    }

    private func purgeTransportBytes(
        for profileID: ProfileID,
        zoneName: String?,
        ownerName: String?,
        snapshot: inout CloudKitFamilyMetadataSnapshot
    ) {
        func matchesZone(_ candidateZone: String, _ candidateOwner: String) -> Bool {
            guard let zoneName, let ownerName else { return false }
            return candidateZone == zoneName && candidateOwner == ownerName
        }

        snapshot.systemFields.removeAll {
            matchesZone($0.zoneName, $0.ownerName)
        }
        snapshot.quarantined.removeAll {
            matchesZone($0.zoneName, $0.ownerName)
        }
        snapshot.protectedRecordKeys.removeAll {
            matchesZone($0.zoneName, $0.ownerName)
        }
        snapshot.inbox.removeAll { entry in
            let belongsToDeletedProfile =
                matchesZone(entry.zoneName, entry.ownerName)
                || entry.record?.profileID == profileID
                || entry.deletionKey?.profileID == profileID
            guard belongsToDeletedProfile else { return false }
            return !isPrivacyMinimalTerminalRemoval(
                entry,
                profileID: profileID
            )
        }
    }

    private func isPrivacyMinimalTerminalRemoval(
        _ entry: CloudKitFamilyInboxEntry,
        profileID: ProfileID
    ) -> Bool {
        guard entry.operation == .save,
            let record = entry.record,
            record.profileID == profileID,
            record.kind == .profileDeletion,
            record.isDeleted,
            let tombstone = try? JSONDecoder().decode(
                ProfileDeletionTombstone.self,
                from: record.payload
            ),
            tombstone.profileID == profileID,
            let object = try? JSONSerialization.jsonObject(with: record.payload),
            let fields = object as? [String: Any],
            Set(fields.keys) == Set(["profileID", "deletedAt"])
        else { return false }
        return true
    }

    func save(binding: ProfileCloudBinding) throws {
        try withLock {
            var snapshot = loadLocked()
            snapshot.bindings.removeAll { $0.profileID == binding.profileID }
            snapshot.bindings.removeAll {
                binding.zoneName != nil
                    && $0.zoneName == binding.zoneName
                    && $0.ownerName == binding.ownerName
            }
            snapshot.bindings.append(binding)
            snapshot.bindings.sort { $0.profileID.description < $1.profileID.description }
            try persistLocked(snapshot)
        }
    }

    @discardableResult
    func confirm(
        accountRecordName: String
    ) throws -> FamilySyncAccountChange? {
        try withLock {
            var snapshot = loadLocked()
            let accountChange: FamilySyncAccountChange?
            if let previous = snapshot.confirmedAccountRecordName {
                accountChange =
                    previous == accountRecordName ? nil : .switchedAccounts
            } else {
                accountChange = .signedIn
            }
            if accountChange == .switchedAccounts {
                invalidateBindingsAfterAccountChange(&snapshot)
            } else {
                // Cancellation may race a final old delegate callback. Even
                // when the account name is unchanged, no unacknowledged inbox
                // child byte is allowed to cross the new confirmation
                // boundary. A strictly minimal deletion receipt for a
                // terminal binding is the one exception: losing it after the
                // route is revoked would strand the local Profile forever.
                let terminalProfileIDs = Set(
                    snapshot.bindings.compactMap { binding -> ProfileID? in
                        switch binding.state {
                        case .revoked, .ownerDeleted, .participantLeft:
                            binding.profileID
                        case .unbound, .privateOwner, .sharedParticipant:
                            nil
                        }
                    }
                )
                snapshot.inbox.removeAll { entry in
                    guard let profileID = entry.record?.profileID,
                        terminalProfileIDs.contains(profileID)
                    else { return true }
                    return !isPrivacyMinimalTerminalRemoval(
                        entry,
                        profileID: profileID
                    )
                }
            }
            snapshot.confirmedAccountRecordName = accountRecordName
            snapshot.requiresAccountConfirmation = false
            try persistLocked(snapshot)
            return accountChange
        }
    }

    func accountGate(currentAccountRecordName: String) throws -> CloudKitFamilyAccountGate {
        try withLock {
            var snapshot = loadLocked()
            guard !loadFailed else {
                throw CloudKitFamilyPersistenceError.corruptMetadata
            }
            guard !snapshot.requiresAccountConfirmation,
                let confirmed = snapshot.confirmedAccountRecordName
            else {
                return .requiresConfirmation(.signedIn)
            }
            guard confirmed == currentAccountRecordName else {
                invalidateBindingsAfterAccountChange(&snapshot)
                snapshot.requiresAccountConfirmation = true
                try persistLocked(snapshot)
                return .requiresConfirmation(.switchedAccounts)
            }
            return .authorized
        }
    }

    func handleAccountSignIn(recordName: String) throws -> FamilySyncAccountChange? {
        try withLock {
            var snapshot = loadLocked()
            if !snapshot.requiresAccountConfirmation,
                snapshot.confirmedAccountRecordName == recordName
            {
                return nil
            }
            let change: FamilySyncAccountChange =
                snapshot.confirmedAccountRecordName == nil
                ? .signedIn
                : .switchedAccounts
            invalidateBindingsAfterAccountChange(&snapshot)
            snapshot.requiresAccountConfirmation = true
            try persistLocked(snapshot)
            return change
        }
    }

    func handleAccountSignOut() throws {
        try withLock {
            var snapshot = loadLocked()
            invalidateBindingsAfterAccountChange(&snapshot)
            snapshot.requiresAccountConfirmation = true
            try persistLocked(snapshot)
        }
    }

    func requireAccountConfirmation() throws {
        try withLock {
            var snapshot = loadLocked()
            snapshot.requiresAccountConfirmation = true
            try persistLocked(snapshot)
        }
    }

    func saveSystemFields(
        for record: CKRecord,
        scope: CloudKitFamilyDatabaseScope
    ) throws {
        let archiver = NSKeyedArchiver(requiringSecureCoding: true)
        record.encodeSystemFields(with: archiver)
        archiver.finishEncoding()
        let entry = CloudKitSystemFieldsEntry(
            scope: scope,
            recordName: record.recordID.recordName,
            zoneName: record.recordID.zoneID.zoneName,
            ownerName: record.recordID.zoneID.ownerName,
            data: archiver.encodedData
        )
        try withLock {
            var snapshot = loadLocked()
            snapshot.systemFields.removeAll { $0.key == entry.key }
            snapshot.systemFields.append(entry)
            try persistLocked(snapshot)
        }
    }

    func restoredRecord(
        id: CKRecord.ID,
        scope: CloudKitFamilyDatabaseScope
    ) -> CKRecord? {
        withLock {
            let key =
                "\(scope.rawValue)|\(id.zoneID.ownerName)|\(id.zoneID.zoneName)|\(id.recordName)"
            guard let data = loadLocked().systemFields.first(where: { $0.key == key })?.data,
                let unarchiver = try? NSKeyedUnarchiver(forReadingFrom: data)
            else { return nil }
            unarchiver.requiresSecureCoding = true
            defer { unarchiver.finishDecoding() }
            return CKRecord(coder: unarchiver)
        }
    }

    func removeSystemFields(
        id: CKRecord.ID,
        scope: CloudKitFamilyDatabaseScope
    ) throws {
        try withLock {
            var snapshot = loadLocked()
            snapshot.systemFields.removeAll {
                $0.scope == scope
                    && $0.recordName == id.recordName
                    && $0.zoneName == id.zoneID.zoneName
                    && $0.ownerName == id.zoneID.ownerName
            }
            try persistLocked(snapshot)
        }
    }

    func quarantine(_ entry: CloudKitFamilyQuarantineEntry) throws {
        try withLock {
            var snapshot = loadLocked()
            snapshot.quarantined.removeAll {
                $0.scope == entry.scope
                    && $0.recordName == entry.recordName
                    && $0.zoneName == entry.zoneName
                    && $0.ownerName == entry.ownerName
            }
            snapshot.quarantined.append(entry)
            let protectedKey = CloudKitProtectedRecordKey(
                scope: entry.scope,
                recordName: entry.recordName,
                zoneName: entry.zoneName,
                ownerName: entry.ownerName
            )
            if !snapshot.protectedRecordKeys.contains(protectedKey) {
                snapshot.protectedRecordKeys.append(protectedKey)
            }
            trimQuarantine(&snapshot)
            try persistLocked(snapshot)
        }
    }

    func quarantinedCount() -> Int {
        withLock { loadLocked().quarantined.count }
    }

    func isQuarantined(
        recordID: CKRecord.ID,
        scope: CloudKitFamilyDatabaseScope
    ) -> Bool {
        withLock {
            loadLocked().protectedRecordKeys.contains(
                CloudKitProtectedRecordKey(
                    scope: scope,
                    recordName: recordID.recordName,
                    zoneName: recordID.zoneID.zoneName,
                    ownerName: recordID.zoneID.ownerName
                )
            )
        }
    }

    func appendInbox(
        record: FamilySyncRecord,
        recordID: CKRecord.ID,
        scope: CloudKitFamilyDatabaseScope,
        receivedAt: Date
    ) throws -> UUID {
        try withLock {
            var snapshot = loadLocked()
            if let existing = snapshot.inbox.first(where: {
                $0.operation == .save
                    && $0.record == record
            }) {
                if clearQuarantine(
                    recordID: recordID,
                    scope: scope,
                    snapshot: &snapshot
                ) {
                    try persistLocked(snapshot)
                }
                return existing.receiptID
            }
            let entry = CloudKitFamilyInboxEntry(
                receiptID: UUID(),
                scope: scope,
                zoneName: recordID.zoneID.zoneName,
                ownerName: recordID.zoneID.ownerName,
                operation: .save,
                record: record,
                deletionKey: nil,
                receivedAt: receivedAt
            )
            snapshot.inbox.append(entry)
            _ = clearQuarantine(
                recordID: recordID,
                scope: scope,
                snapshot: &snapshot
            )
            try persistLocked(snapshot)
            return entry.receiptID
        }
    }

    /// Commits a fully decoded, identity-validated replacement and removes
    /// any older quarantine envelope/write lock for the same Cloud record in
    /// that exact atomic metadata snapshot.
    func appendInboxReplacingQuarantine(
        record: FamilySyncRecord,
        recordID: CKRecord.ID,
        scope: CloudKitFamilyDatabaseScope,
        receivedAt: Date
    ) throws -> UUID {
        try appendInbox(
            record: record,
            recordID: recordID,
            scope: scope,
            receivedAt: receivedAt
        )
    }

    func appendInbox(
        deletionKey: FamilySyncChangeKey,
        recordID: CKRecord.ID,
        scope: CloudKitFamilyDatabaseScope,
        receivedAt: Date
    ) throws -> UUID {
        try withLock {
            var snapshot = loadLocked()
            if let existing = snapshot.inbox.first(where: {
                $0.operation == .delete && $0.deletionKey == deletionKey
            }) {
                return existing.receiptID
            }
            let entry = CloudKitFamilyInboxEntry(
                receiptID: UUID(),
                scope: scope,
                zoneName: recordID.zoneID.zoneName,
                ownerName: recordID.zoneID.ownerName,
                operation: .delete,
                record: nil,
                deletionKey: deletionKey,
                receivedAt: receivedAt
            )
            snapshot.inbox.append(entry)
            try persistLocked(snapshot)
            return entry.receiptID
        }
    }

    func inboxEntries() -> [CloudKitFamilyInboxEntry] {
        withLock { loadLocked().inbox }
    }

    func acknowledgeInbox(receiptIDs: Set<UUID>) throws {
        guard !receiptIDs.isEmpty else { return }
        try withLock {
            var snapshot = loadLocked()
            snapshot.inbox.removeAll { receiptIDs.contains($0.receiptID) }
            try persistLocked(snapshot)
        }
    }

    func quarantineInbox(
        receiptIDs: Set<UUID>,
        category: FamilySyncPrivacySafeErrorCategory,
        at date: Date
    ) throws {
        guard !receiptIDs.isEmpty else { return }
        try withLock {
            var snapshot = loadLocked()
            let selected = snapshot.inbox.filter {
                receiptIDs.contains($0.receiptID)
            }
            guard selected.count == receiptIDs.count else {
                throw CloudKitFamilyPersistenceError.missingInboxReceipt
            }
            for entry in selected {
                let key =
                    entry.record.map {
                        FamilySyncChangeKey(
                            profileID: $0.profileID,
                            recordName: $0.recordName
                        )
                    } ?? entry.deletionKey
                guard let key else {
                    throw CloudKitFamilyPersistenceError.missingInboxReceipt
                }
                let envelopeData = try entry.record.map {
                    try JSONEncoder().encode(FamilySyncEnvelope(record: $0))
                }
                let quarantine = CloudKitFamilyQuarantineEntry(
                    id: UUID(),
                    scope: entry.scope,
                    recordName: key.recordName,
                    zoneName: entry.zoneName,
                    ownerName: entry.ownerName,
                    reason: category,
                    envelopeData: envelopeData,
                    quarantinedAt: date
                )
                snapshot.quarantined.removeAll {
                    $0.scope == quarantine.scope
                        && $0.recordName == quarantine.recordName
                        && $0.zoneName == quarantine.zoneName
                        && $0.ownerName == quarantine.ownerName
                }
                snapshot.quarantined.append(quarantine)
                let protectedKey = CloudKitProtectedRecordKey(
                    scope: quarantine.scope,
                    recordName: quarantine.recordName,
                    zoneName: quarantine.zoneName,
                    ownerName: quarantine.ownerName
                )
                if !snapshot.protectedRecordKeys.contains(protectedKey) {
                    snapshot.protectedRecordKeys.append(protectedKey)
                }
            }
            trimQuarantine(&snapshot)
            snapshot.inbox.removeAll { receiptIDs.contains($0.receiptID) }
            try persistLocked(snapshot)
        }
    }

    private func trimQuarantine(
        _ snapshot: inout CloudKitFamilyMetadataSnapshot
    ) {
        let maximumCount = 200
        guard snapshot.quarantined.count > maximumCount else { return }
        snapshot.quarantined.removeFirst(
            snapshot.quarantined.count - maximumCount
        )
        let retainedKeys = Set(
            snapshot.quarantined.map {
                CloudKitProtectedRecordKey(
                    scope: $0.scope,
                    recordName: $0.recordName,
                    zoneName: $0.zoneName,
                    ownerName: $0.ownerName
                )
            })
        // The protected-key index is a projection of quarantine. Evicting an
        // old diagnostic envelope must not leave an invisible permanent lock
        // that blocks that record forever.
        snapshot.protectedRecordKeys.removeAll {
            !retainedKeys.contains($0)
        }
    }

    @discardableResult
    private func clearQuarantine(
        recordID: CKRecord.ID,
        scope: CloudKitFamilyDatabaseScope,
        snapshot: inout CloudKitFamilyMetadataSnapshot
    ) -> Bool {
        let previousQuarantineCount = snapshot.quarantined.count
        let previousProtectedCount = snapshot.protectedRecordKeys.count
        snapshot.quarantined.removeAll {
            $0.scope == scope
                && $0.recordName == recordID.recordName
                && $0.zoneName == recordID.zoneID.zoneName
                && $0.ownerName == recordID.zoneID.ownerName
        }
        snapshot.protectedRecordKeys.removeAll {
            $0.scope == scope
                && $0.recordName == recordID.recordName
                && $0.zoneName == recordID.zoneID.zoneName
                && $0.ownerName == recordID.zoneID.ownerName
        }
        return snapshot.quarantined.count != previousQuarantineCount
            || snapshot.protectedRecordKeys.count != previousProtectedCount
    }

    private func invalidateBindingsAfterAccountChange(
        _ snapshot: inout CloudKitFamilyMetadataSnapshot
    ) {
        snapshot.bindings = snapshot.bindings.map { binding in
            switch binding.state {
            case .sharedParticipant:
                ProfileCloudBinding(
                    profileID: binding.profileID,
                    state: .revoked,
                    zoneName: binding.zoneName,
                    ownerName: binding.ownerName,
                    rootRecordName: binding.rootRecordName
                )
            case .privateOwner, .unbound:
                .unbound(binding.profileID)
            case .revoked, .ownerDeleted, .participantLeft:
                binding
            }
        }
        snapshot.systemFields.removeAll()
        // Transport-owned bytes are scoped to the CloudKit account that
        // fetched them. Never replay an old account's unacknowledged inbox or
        // let its quarantine locks block a newly confirmed account. Local app
        // repositories are deliberately untouched.
        snapshot.inbox.removeAll()
        snapshot.quarantined.removeAll()
        snapshot.protectedRecordKeys.removeAll()
    }

    private func loadLocked() -> CloudKitFamilyMetadataSnapshot {
        if let cached { return cached }
        guard FileManager.default.fileExists(atPath: snapshotURL.path) else {
            let empty = CloudKitFamilyMetadataSnapshot()
            cached = empty
            return empty
        }
        guard let data = try? Data(contentsOf: snapshotURL),
            let decoded = try? JSONDecoder().decode(
                CloudKitFamilyMetadataSnapshot.self,
                from: data
            ),
            decoded.schemaVersion == CloudKitFamilyMetadataSnapshot.currentSchemaVersion
        else {
            // Preserve unreadable routing/account/inbox bytes and latch the
            // failure. Reconfirming must never convert a formerly shared
            // profile into a fresh private zone after metadata corruption.
            loadFailed = true
            let empty = CloudKitFamilyMetadataSnapshot()
            cached = empty
            return empty
        }
        cached = decoded
        return decoded
    }

    private func persistLocked(_ snapshot: CloudKitFamilyMetadataSnapshot) throws {
        guard !loadFailed else {
            throw CloudKitFamilyPersistenceError.corruptMetadata
        }
        try FileManager.default.createDirectory(
            at: snapshotURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        do {
            try encoder.encode(snapshot).write(to: snapshotURL, options: .atomic)
        } catch {
            throw CloudKitFamilyPersistenceError.metadataWriteFailed
        }
        cached = snapshot
    }

    private func withLock<T>(_ body: () throws -> T) rethrows -> T {
        lock.lock()
        defer { lock.unlock() }
        return try body()
    }
}

enum CloudKitFamilyPersistenceError: Error, Equatable {
    case metadataWriteFailed
    case missingInboxReceipt
    case corruptMetadata
    case stateClearFailed
}

private struct CloudKitSyncStateSnapshot: Codable {
    static let currentSchemaVersion = 1

    let schemaVersion: Int
    let serialization: CKSyncEngine.State.Serialization

    init(serialization: CKSyncEngine.State.Serialization) {
        schemaVersion = Self.currentSchemaVersion
        self.serialization = serialization
    }
}

final class CloudKitFamilySyncStateStore: @unchecked Sendable {
    private let directory: URL
    private let lock = NSLock()
    private var corruptScopes: Set<CloudKitFamilyDatabaseScope> = []

    init(directory: URL) {
        self.directory = directory
    }

    func load(_ scope: CloudKitFamilyDatabaseScope) -> CKSyncEngine.State.Serialization? {
        withLock {
            let url = stateURL(scope)
            guard FileManager.default.fileExists(atPath: url.path) else { return nil }
            guard let data = try? Data(contentsOf: url),
                let snapshot = try? JSONDecoder().decode(
                    CloudKitSyncStateSnapshot.self,
                    from: data
                ),
                snapshot.schemaVersion == CloudKitSyncStateSnapshot.currentSchemaVersion
            else {
                corruptScopes.insert(scope)
                try? FileManager.default.removeItem(at: url)
                return nil
            }
            return snapshot.serialization
        }
    }

    @discardableResult
    func save(
        _ serialization: CKSyncEngine.State.Serialization,
        scope: CloudKitFamilyDatabaseScope
    ) -> Bool {
        withLock {
            do {
                try FileManager.default.createDirectory(
                    at: directory,
                    withIntermediateDirectories: true
                )
                try JSONEncoder().encode(
                    CloudKitSyncStateSnapshot(serialization: serialization)
                ).write(to: stateURL(scope), options: .atomic)
                corruptScopes.remove(scope)
                return true
            } catch {
                corruptScopes.insert(scope)
                return false
            }
        }
    }

    func clear() throws {
        try withLock {
            for scope in CloudKitFamilyDatabaseScope.allCases {
                let url = stateURL(scope)
                if FileManager.default.fileExists(atPath: url.path) {
                    do {
                        try FileManager.default.removeItem(at: url)
                    } catch {
                        throw CloudKitFamilyPersistenceError.stateClearFailed
                    }
                }
                guard !FileManager.default.fileExists(atPath: url.path) else {
                    throw CloudKitFamilyPersistenceError.stateClearFailed
                }
            }
            corruptScopes.removeAll()
        }
    }

    func recoveredCorruptState() -> Bool {
        withLock { !corruptScopes.isEmpty }
    }

    private func stateURL(_ scope: CloudKitFamilyDatabaseScope) -> URL {
        directory.appendingPathComponent("\(scope.rawValue)-engine-state.json")
    }

    private func withLock<T>(_ body: () throws -> T) rethrows -> T {
        lock.lock()
        defer { lock.unlock() }
        return try body()
    }
}
