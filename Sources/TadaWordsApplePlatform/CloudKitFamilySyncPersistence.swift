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
    /// Transport-only account provenance. It never enters Family Sync domain
    /// records, Parent diagnostics, or child-facing state.
    let originAccountRecordName: String?
    let originErasureRoute: ProfileErasureRoute?

    init(
        profileID: ProfileID,
        state: ProfileCloudBindingState,
        zoneName: String?,
        ownerName: String?,
        rootRecordName: String?,
        originAccountRecordName: String? = nil,
        originErasureRoute: ProfileErasureRoute? = nil
    ) {
        self.profileID = profileID
        self.state = state
        self.zoneName = zoneName
        self.ownerName = ownerName
        self.rootRecordName = rootRecordName
        self.originAccountRecordName = originAccountRecordName
        self.originErasureRoute = originErasureRoute
    }

    static func unbound(_ profileID: ProfileID) -> Self {
        Self(
            profileID: profileID,
            state: .unbound,
            zoneName: nil,
            ownerName: nil,
            rootRecordName: nil,
            originAccountRecordName: nil,
            originErasureRoute: nil
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

    var erasureRoute: ProfileErasureRoute {
        if let originErasureRoute { return originErasureRoute }
        switch state {
        case .privateOwner, .ownerDeleted:
            return .owner
        case .sharedParticipant, .revoked, .participantLeft:
            return .participant
        case .unbound:
            return .unresolved
        }
    }

    func assigningOrigin(
        accountRecordName: String?,
        route: ProfileErasureRoute? = nil
    ) -> Self {
        Self(
            profileID: profileID,
            state: state,
            zoneName: zoneName,
            ownerName: ownerName,
            rootRecordName: rootRecordName,
            originAccountRecordName: originAccountRecordName ?? accountRecordName,
            originErasureRoute: originErasureRoute
                ?? route
                ?? (erasureRoute == .unresolved ? nil : erasureRoute)
        )
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

private struct CloudKitAcknowledgedTerminalRemoval: Codable, Equatable {
    let profileID: ProfileID
    let logicalRevision: FamilySyncLogicalRevision
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
    /// Identifies which CloudKit fact authorizes a terminal Profile removal.
    /// This must remain optional so metadata written before the evidence split
    /// is still readable; an absent value is never upgraded by guessing.
    let terminalEvidence: CloudKitFamilyTerminalEvidence?

    init(
        receiptID: UUID,
        scope: CloudKitFamilyDatabaseScope,
        zoneName: String,
        ownerName: String,
        operation: Operation,
        record: FamilySyncRecord?,
        deletionKey: FamilySyncChangeKey?,
        receivedAt: Date,
        terminalEvidence: CloudKitFamilyTerminalEvidence? = nil
    ) {
        self.receiptID = receiptID
        self.scope = scope
        self.zoneName = zoneName
        self.ownerName = ownerName
        self.operation = operation
        self.record = record
        self.deletionKey = deletionKey
        self.receivedAt = receivedAt
        self.terminalEvidence = terminalEvidence
    }
}

enum CloudKitFamilyTerminalEvidence: String, Codable, Equatable, Sendable {
    /// A privacy-minimal record in the private control zone. The payload zone
    /// still needs an explicit erase/absence proof before terminal commit.
    case ownerDeletionLedger
    /// Only the Profile root record was deleted. The payload zone may still
    /// contain child records, so transport recovery must finish the removal.
    case rootRecordDeletion
    /// CKSyncEngine reported that the entire bound zone was deleted.
    case zoneDeletion
}

struct CloudKitStagedOwnerDeletionLedgerRecovery: Equatable, Sendable {
    let record: FamilySyncRecord
    let recordID: CKRecord.ID
    let binding: ProfileCloudBinding
    let receivedAt: Date
}

struct CloudKitStagedRemoteRootRemovalRecovery: Equatable, Sendable {
    let record: FamilySyncRecord
    let recordID: CKRecord.ID
    let scope: CloudKitFamilyDatabaseScope
    let binding: ProfileCloudBinding
    let receivedAt: Date
    let terminalEvidence: CloudKitFamilyTerminalEvidence?
}

struct CloudKitStagedRemoteZoneRemovalRecovery: Equatable, Sendable {
    let record: FamilySyncRecord
    let recordID: CKRecord.ID
    let scope: CloudKitFamilyDatabaseScope
    let binding: ProfileCloudBinding
    let receivedAt: Date
}

enum CloudKitAmbiguousRemoteRemovalEvidence: String, Codable, Equatable, Sendable {
    case ownerDeletionLedger
    case rootRecordDeletion
    case zoneDeletion
}

struct CloudKitAmbiguousRemoteRemovalMarker: Codable, Equatable, Sendable {
    let id: UUID
    let profileID: ProfileID
    let scope: CloudKitFamilyDatabaseScope
    let zoneName: String
    let ownerName: String
    let rootRecordName: String
    let originAccountRecordName: String
    let evidence: CloudKitAmbiguousRemoteRemovalEvidence
    let provisionalBindingCreated: Bool
    let receivedAt: Date

    init(
        id: UUID,
        profileID: ProfileID,
        scope: CloudKitFamilyDatabaseScope,
        zoneName: String,
        ownerName: String,
        rootRecordName: String,
        originAccountRecordName: String,
        evidence: CloudKitAmbiguousRemoteRemovalEvidence,
        provisionalBindingCreated: Bool = false,
        receivedAt: Date
    ) {
        self.id = id
        self.profileID = profileID
        self.scope = scope
        self.zoneName = zoneName
        self.ownerName = ownerName
        self.rootRecordName = rootRecordName
        self.originAccountRecordName = originAccountRecordName
        self.evidence = evidence
        self.provisionalBindingCreated = provisionalBindingCreated
        self.receivedAt = receivedAt
    }

    private enum CodingKeys: String, CodingKey {
        case id
        case profileID
        case scope
        case zoneName
        case ownerName
        case rootRecordName
        case originAccountRecordName
        case evidence
        case provisionalBindingCreated
        case receivedAt
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        profileID = try container.decode(ProfileID.self, forKey: .profileID)
        scope = try container.decode(
            CloudKitFamilyDatabaseScope.self,
            forKey: .scope
        )
        zoneName = try container.decode(String.self, forKey: .zoneName)
        ownerName = try container.decode(String.self, forKey: .ownerName)
        rootRecordName = try container.decode(
            String.self,
            forKey: .rootRecordName
        )
        originAccountRecordName = try container.decode(
            String.self,
            forKey: .originAccountRecordName
        )
        evidence = try container.decode(
            CloudKitAmbiguousRemoteRemovalEvidence.self,
            forKey: .evidence
        )
        provisionalBindingCreated =
            try container.decodeIfPresent(
                Bool.self,
                forKey: .provisionalBindingCreated
            ) ?? false
        receivedAt = try container.decode(Date.self, forKey: .receivedAt)
    }

    var zoneID: CKRecordZone.ID {
        CKRecordZone.ID(zoneName: zoneName, ownerName: ownerName)
    }

    var rootRecordID: CKRecord.ID {
        CKRecord.ID(recordName: rootRecordName, zoneID: zoneID)
    }
}

struct CloudKitPreparedOwnerDeletionLedgerRecovery: Equatable, Sendable {
    let binding: ProfileCloudBinding
    let wasCreated: Bool
}

struct CloudKitPreparedAmbiguousOwnerDeletionLedgerRecovery: Equatable, Sendable {
    let binding: ProfileCloudBinding
    let markerID: UUID
    let provisionalBindingCreated: Bool
}

enum CloudKitRemoteProfileRemovalRecordFactory {
    static func record(for profileID: ProfileID) throws -> FamilySyncRecord {
        // CloudKit deletion callbacks do not carry a deletion date. Keep the
        // semantic tombstone stable across callback replay and crash recovery.
        let semanticDeletionDate = Date(timeIntervalSince1970: 0)
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .secondsSince1970
        encoder.outputFormatting = [.sortedKeys]
        return FamilySyncRecord(
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
    }
}

private struct CloudKitFamilyMetadataSnapshot: Codable {
    static let currentSchemaVersion = 2

    var schemaVersion = currentSchemaVersion
    var confirmedAccountRecordName: String?
    var requiresAccountConfirmation = true
    var bindings: [ProfileCloudBinding] = []
    var systemFields: [CloudKitSystemFieldsEntry] = []
    var quarantined: [CloudKitFamilyQuarantineEntry] = []
    var protectedRecordKeys: [CloudKitProtectedRecordKey] = []
    var inbox: [CloudKitFamilyInboxEntry] = []
    var ambiguousRemoteRemovals: [CloudKitAmbiguousRemoteRemovalMarker]? = []
    // Optional so metadata written by the first schema-v2 development builds
    // remains readable. New snapshots always persist an explicit array.
    var acknowledgedTerminalRemovals: [CloudKitAcknowledgedTerminalRemoval]? = []
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
            guard isAuthorized(existing, in: snapshot) else {
                throw CloudKitFamilyPersistenceError.accountBindingMismatch
            }
            let nextState: ProfileCloudBindingState =
                switch existing.state {
                case .sharedParticipant, .revoked:
                    .revoked
                case .participantLeft:
                    .participantLeft
                case .unbound, .privateOwner, .ownerDeleted:
                    throw CloudKitFamilyPersistenceError.bindingConflict
                }
            snapshot.bindings[index] = ProfileCloudBinding(
                profileID: existing.profileID,
                state: nextState,
                zoneName: existing.zoneName,
                ownerName: existing.ownerName,
                rootRecordName: existing.rootRecordName,
                originAccountRecordName: existing.originAccountRecordName,
                originErasureRoute: existing.originErasureRoute
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
        try withLock {
            var snapshot = loadLocked()
            guard
                let persisted = snapshot.bindings.first(where: {
                    $0.profileID == profileID
                }),
                previous == nil || previous == persisted,
                isAuthorized(persisted, in: snapshot)
            else {
                throw CloudKitFamilyPersistenceError.accountBindingMismatch
            }
            switch state {
            case .ownerDeleted:
                guard
                    persisted.state == .privateOwner
                        || persisted.state == .ownerDeleted,
                    persisted.erasureRoute == .owner
                else {
                    throw CloudKitFamilyPersistenceError.bindingConflict
                }
            case .participantLeft:
                guard
                    persisted.state == .sharedParticipant
                        || persisted.state == .revoked
                        || persisted.state == .participantLeft,
                    persisted.erasureRoute == .participant
                else {
                    throw CloudKitFamilyPersistenceError.bindingConflict
                }
            case .unbound, .privateOwner, .sharedParticipant, .revoked:
                preconditionFailure("Only terminal binding states are accepted")
            }
            let terminal = ProfileCloudBinding(
                profileID: profileID,
                state: state,
                zoneName: persisted.zoneName,
                ownerName: persisted.ownerName,
                rootRecordName: persisted.rootRecordName,
                originAccountRecordName: persisted.originAccountRecordName,
                originErasureRoute: persisted.originErasureRoute
                    ?? (state == .ownerDeleted ? .owner : .participant)
            )
            snapshot.bindings.removeAll { $0.profileID == profileID }
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
        snapshot.ambiguousRemoteRemovals?.removeAll { marker in
            marker.profileID == profileID
                || matchesZone(marker.zoneName, marker.ownerName)
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

    private func retainOnlyTerminalReceipt(
        _ receiptID: UUID,
        for profileID: ProfileID,
        snapshot: inout CloudKitFamilyMetadataSnapshot
    ) {
        snapshot.inbox.removeAll { entry in
            guard entry.receiptID != receiptID else { return false }
            return entry.record?.profileID == profileID
                || entry.deletionKey?.profileID == profileID
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
            if let existing = snapshot.bindings.first(where: {
                $0.profileID == binding.profileID
            }) {
                if existing.originAccountRecordName == nil {
                    // Any persisted route without account provenance is
                    // ambiguous. Older builds could leave an unbound route
                    // after switching accounts, and partial legacy metadata
                    // may lack provenance for an active route. Only absence of
                    // a binding proves this is a fresh Profile.
                    throw CloudKitFamilyPersistenceError.accountBindingMismatch
                }
                if let origin = existing.originAccountRecordName,
                    snapshot.requiresAccountConfirmation
                        || snapshot.confirmedAccountRecordName != origin
                {
                    throw CloudKitFamilyPersistenceError.accountBindingMismatch
                }
                guard canReplace(existing, with: binding) else {
                    throw CloudKitFamilyPersistenceError.bindingConflict
                }
            }
            if snapshot.bindings.contains(where: {
                $0.profileID != binding.profileID
                    && binding.zoneName != nil
                    && $0.zoneName == binding.zoneName
                    && $0.ownerName == binding.ownerName
            }) {
                throw CloudKitFamilyPersistenceError.bindingConflict
            }
            let stamped = binding.assigningOrigin(
                accountRecordName: snapshot.confirmedAccountRecordName
            )
            snapshot.bindings.removeAll { $0.profileID == stamped.profileID }
            snapshot.bindings.append(stamped)
            snapshot.bindings.sort { $0.profileID.description < $1.profileID.description }
            try persistLocked(snapshot)
        }
    }

    func hasPersistedBinding(for profileID: ProfileID) -> Bool {
        withLock {
            loadLocked().bindings.contains { $0.profileID == profileID }
        }
    }

    func isBindingAuthorizedForConfirmedAccount(
        _ binding: ProfileCloudBinding
    ) -> Bool {
        withLock {
            isAuthorized(binding, in: loadLocked())
        }
    }

    /// Validates an owner deletion ledger against durable account/route
    /// provenance and creates a recovery-only owner binding only when no
    /// binding has ever existed for this Profile or deterministic zone.
    func prepareOwnerDeletionLedgerRecovery(
        profileID: ProfileID,
        zoneID: CKRecordZone.ID,
        rootRecordName: String,
        expectedOriginAccountRecordName: String? = nil
    ) throws -> CloudKitPreparedOwnerDeletionLedgerRecovery {
        try withLock {
            var snapshot = loadLocked()
            guard !loadFailed, !snapshot.requiresAccountConfirmation,
                let confirmed = snapshot.confirmedAccountRecordName,
                expectedOriginAccountRecordName == nil
                    || expectedOriginAccountRecordName == confirmed
            else {
                throw CloudKitFamilyPersistenceError.accountBindingMismatch
            }
            if let existing = snapshot.bindings.first(where: {
                $0.profileID == profileID
            }) {
                guard isAuthorized(existing, in: snapshot) else {
                    throw CloudKitFamilyPersistenceError.accountBindingMismatch
                }
                guard
                    existing.state == .privateOwner
                        || existing.state == .ownerDeleted,
                    existing.erasureRoute == .owner,
                    existing.zoneID == zoneID,
                    existing.rootRecordName == rootRecordName
                else {
                    throw CloudKitFamilyPersistenceError.bindingConflict
                }
                return CloudKitPreparedOwnerDeletionLedgerRecovery(
                    binding: existing,
                    wasCreated: false
                )
            }
            guard
                !snapshot.bindings.contains(where: {
                    $0.zoneName == zoneID.zoneName && $0.ownerName == zoneID.ownerName
                })
            else {
                throw CloudKitFamilyPersistenceError.bindingConflict
            }
            let recovery = ProfileCloudBinding(
                profileID: profileID,
                state: .privateOwner,
                zoneName: zoneID.zoneName,
                ownerName: zoneID.ownerName,
                rootRecordName: rootRecordName,
                originAccountRecordName: confirmed,
                originErasureRoute: .owner
            )
            snapshot.bindings.append(recovery)
            snapshot.bindings.sort {
                $0.profileID.description < $1.profileID.description
            }
            try persistLocked(snapshot)
            return CloudKitPreparedOwnerDeletionLedgerRecovery(
                binding: recovery,
                wasCreated: true
            )
        }
    }

    /// Creates or validates the deterministic owner route and stages its
    /// no-payload callback marker in one metadata snapshot. A process crash can
    /// therefore never expose a newly created binding without the provenance
    /// needed to roll it back after exact control-ledger absence proof.
    func prepareAndStageAmbiguousOwnerDeletionLedgerRecovery(
        profileID: ProfileID,
        zoneID: CKRecordZone.ID,
        rootRecordName: String,
        receivedAt: Date,
        expectedOriginAccountRecordName: String? = nil
    ) throws -> CloudKitPreparedAmbiguousOwnerDeletionLedgerRecovery {
        try withLock {
            var snapshot = loadLocked()
            guard !loadFailed, !snapshot.requiresAccountConfirmation,
                let confirmed = snapshot.confirmedAccountRecordName,
                expectedOriginAccountRecordName == nil
                    || expectedOriginAccountRecordName == confirmed
            else {
                throw CloudKitFamilyPersistenceError.accountBindingMismatch
            }

            let binding: ProfileCloudBinding
            let wasCreated: Bool
            if let existing = snapshot.bindings.first(where: {
                $0.profileID == profileID
            }) {
                guard isAuthorized(existing, in: snapshot) else {
                    throw CloudKitFamilyPersistenceError.accountBindingMismatch
                }
                guard existing.state == .privateOwner,
                    existing.erasureRoute == .owner,
                    existing.zoneID == zoneID,
                    existing.rootRecordName == rootRecordName
                else {
                    throw CloudKitFamilyPersistenceError.bindingConflict
                }
                binding = existing
                wasCreated = false
            } else {
                guard
                    !snapshot.bindings.contains(where: {
                        $0.zoneName == zoneID.zoneName
                            && $0.ownerName == zoneID.ownerName
                    })
                else {
                    throw CloudKitFamilyPersistenceError.bindingConflict
                }
                binding = ProfileCloudBinding(
                    profileID: profileID,
                    state: .privateOwner,
                    zoneName: zoneID.zoneName,
                    ownerName: zoneID.ownerName,
                    rootRecordName: rootRecordName,
                    originAccountRecordName: confirmed,
                    originErasureRoute: .owner
                )
                wasCreated = true
            }

            var markers = snapshot.ambiguousRemoteRemovals ?? []
            if let existingMarker = markers.first(where: {
                $0.profileID == profileID
                    && $0.zoneID == zoneID
                    && $0.originAccountRecordName == confirmed
                    && $0.evidence == .ownerDeletionLedger
            }) {
                return CloudKitPreparedAmbiguousOwnerDeletionLedgerRecovery(
                    binding: binding,
                    markerID: existingMarker.id,
                    provisionalBindingCreated:
                        existingMarker.provisionalBindingCreated
                )
            }

            let marker = CloudKitAmbiguousRemoteRemovalMarker(
                id: UUID(),
                profileID: profileID,
                scope: .privateDatabase,
                zoneName: zoneID.zoneName,
                ownerName: zoneID.ownerName,
                rootRecordName: rootRecordName,
                originAccountRecordName: confirmed,
                evidence: .ownerDeletionLedger,
                provisionalBindingCreated: wasCreated,
                receivedAt: receivedAt
            )
            if wasCreated {
                snapshot.bindings.append(binding)
                snapshot.bindings.sort {
                    $0.profileID.description < $1.profileID.description
                }
            }
            markers.append(marker)
            snapshot.ambiguousRemoteRemovals = markers.sorted { left, right in
                if left.profileID != right.profileID {
                    return left.profileID.description
                        < right.profileID.description
                }
                return left.evidence.rawValue < right.evidence.rawValue
            }
            try persistLocked(snapshot)
            return CloudKitPreparedAmbiguousOwnerDeletionLedgerRecovery(
                binding: binding,
                markerID: marker.id,
                provisionalBindingCreated: wasCreated
            )
        }
    }

    /// After CloudKit proves the owner's payload zone is absent, atomically
    /// persists the minimal deletion receipt and terminal binding. Rechecking
    /// the exact binding and confirmed account inside this single lock keeps a
    /// mid-flight Apple Account change from writing old-account evidence into
    /// the newly confirmed account's metadata.
    func commitOwnerDeletionLedgerRecovery(
        record: FamilySyncRecord,
        recordID: CKRecord.ID,
        previous: ProfileCloudBinding,
        receivedAt: Date
    ) throws -> UUID {
        try withLock {
            var snapshot = loadLocked()
            guard
                record.profileID == previous.profileID,
                record.recordName == "profile-\(record.profileID)",
                record.kind == .profileDeletion,
                record.isDeleted,
                recordID
                    == CloudKitFamilyDeletionLedgerCodec.recordID(
                        for: record.profileID
                    ),
                let index = snapshot.bindings.firstIndex(where: {
                    $0.profileID == record.profileID
                }),
                snapshot.bindings[index] == previous,
                isAuthorized(previous, in: snapshot)
            else {
                throw CloudKitFamilyPersistenceError.accountBindingMismatch
            }
            guard
                previous.state == .privateOwner
                    || previous.state == .ownerDeleted,
                previous.erasureRoute == .owner,
                previous.zoneID != nil,
                previous.rootRecordID != nil
            else {
                throw CloudKitFamilyPersistenceError.bindingConflict
            }
            let candidate = CloudKitFamilyInboxEntry(
                receiptID: UUID(),
                scope: .privateDatabase,
                zoneName: recordID.zoneID.zoneName,
                ownerName: recordID.zoneID.ownerName,
                operation: .save,
                record: record,
                deletionKey: nil,
                receivedAt: receivedAt,
                terminalEvidence: .ownerDeletionLedger
            )
            guard
                isPrivacyMinimalTerminalRemoval(
                    candidate,
                    profileID: record.profileID
                )
            else {
                throw CloudKitFamilyPersistenceError.bindingConflict
            }

            let appendResult = appendInboxEntry(
                record: record,
                recordID: recordID,
                scope: .privateDatabase,
                receivedAt: receivedAt,
                terminalEvidence: .ownerDeletionLedger,
                snapshot: &snapshot
            )
            snapshot.bindings[index] = ProfileCloudBinding(
                profileID: previous.profileID,
                state: .ownerDeleted,
                zoneName: previous.zoneName,
                ownerName: previous.ownerName,
                rootRecordName: previous.rootRecordName,
                originAccountRecordName: previous.originAccountRecordName,
                originErasureRoute: .owner
            )
            purgeTransportBytes(
                for: previous.profileID,
                zoneName: previous.zoneName,
                ownerName: previous.ownerName,
                snapshot: &snapshot
            )
            retainOnlyTerminalReceipt(
                appendResult.receiptID,
                for: previous.profileID,
                snapshot: &snapshot
            )
            try persistLocked(snapshot)
            return appendResult.receiptID
        }
    }

    func hasAcknowledgedTerminalRemoval(_ record: FamilySyncRecord) -> Bool {
        withLock {
            let marker = CloudKitAcknowledgedTerminalRemoval(
                profileID: record.profileID,
                logicalRevision: record.logicalRevision
            )
            return (loadLocked().acknowledgedTerminalRemovals ?? []).contains(marker)
        }
    }

    func recordAcknowledgedTerminalRemoval(_ record: FamilySyncRecord) throws {
        try withLock {
            var snapshot = loadLocked()
            guard
                let binding = snapshot.bindings.first(where: {
                    $0.profileID == record.profileID
                }),
                isAuthorized(binding, in: snapshot),
                binding.state == .ownerDeleted || binding.state == .participantLeft
                    || binding.state == .revoked
            else {
                throw CloudKitFamilyPersistenceError.accountBindingMismatch
            }
            let marker = CloudKitAcknowledgedTerminalRemoval(
                profileID: record.profileID,
                logicalRevision: record.logicalRevision
            )
            var markers = snapshot.acknowledgedTerminalRemovals ?? []
            markers.removeAll { $0.profileID == marker.profileID }
            markers.append(marker)
            snapshot.acknowledgedTerminalRemovals = markers.sorted {
                $0.profileID.description < $1.profileID.description
            }
            try persistLocked(snapshot)
        }
    }

    /// Atomically advances a locally initiated removal to terminal and records
    /// the exact tombstone acknowledgement. A crash cannot leave a terminal
    /// binding without its durable acknowledgement marker.
    func commitAcknowledgedTerminalRemoval(
        _ record: FamilySyncRecord,
        previous: ProfileCloudBinding,
        terminalState: ProfileCloudBindingState
    ) throws {
        precondition(
            terminalState == .ownerDeleted || terminalState == .participantLeft
        )
        try withLock {
            var snapshot = loadLocked()
            guard
                record.profileID == previous.profileID,
                record.kind == .profileDeletion,
                record.isDeleted,
                let index = snapshot.bindings.firstIndex(where: {
                    $0.profileID == previous.profileID
                }),
                snapshot.bindings[index] == previous,
                isAuthorized(previous, in: snapshot),
                let tombstone = try? JSONDecoder().decode(
                    ProfileDeletionTombstone.self,
                    from: record.payload
                ),
                tombstone.profileID == previous.profileID
            else {
                throw CloudKitFamilyPersistenceError.accountBindingMismatch
            }
            let route: ProfileErasureRoute
            switch terminalState {
            case .ownerDeleted:
                guard previous.state == .privateOwner,
                    previous.erasureRoute == .owner
                else {
                    throw CloudKitFamilyPersistenceError.bindingConflict
                }
                route = .owner
            case .participantLeft:
                guard previous.state == .sharedParticipant,
                    previous.erasureRoute == .participant
                else {
                    throw CloudKitFamilyPersistenceError.bindingConflict
                }
                route = .participant
            default:
                preconditionFailure("Only terminal removal states are accepted")
            }
            snapshot.bindings[index] = ProfileCloudBinding(
                profileID: previous.profileID,
                state: terminalState,
                zoneName: previous.zoneName,
                ownerName: previous.ownerName,
                rootRecordName: previous.rootRecordName,
                originAccountRecordName: previous.originAccountRecordName,
                originErasureRoute: previous.originErasureRoute ?? route
            )
            purgeTransportBytes(
                for: previous.profileID,
                zoneName: previous.zoneName,
                ownerName: previous.ownerName,
                snapshot: &snapshot
            )
            let marker = CloudKitAcknowledgedTerminalRemoval(
                profileID: record.profileID,
                logicalRevision: record.logicalRevision
            )
            var markers = snapshot.acknowledgedTerminalRemovals ?? []
            markers.removeAll { $0.profileID == marker.profileID }
            markers.append(marker)
            snapshot.acknowledgedTerminalRemovals = markers.sorted {
                $0.profileID.description < $1.profileID.description
            }
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
                let bindingsByProfileID = Dictionary(
                    uniqueKeysWithValues: snapshot.bindings.map {
                        ($0.profileID, $0)
                    }
                )
                snapshot.inbox.removeAll { entry in
                    guard let profileID = entry.record?.profileID,
                        let binding = bindingsByProfileID[profileID],
                        binding.originAccountRecordName == accountRecordName,
                        isPrivacyMinimalTerminalRemoval(
                            entry,
                            profileID: profileID
                        )
                    else { return true }
                    let isLegacyTerminalReceipt =
                        entry.terminalEvidence == nil
                        && (binding.state == .ownerDeleted
                            || binding.state == .revoked
                            || binding.state == .participantLeft)
                    return entry.terminalEvidence == nil
                        && !isLegacyTerminalReceipt
                }
            }
            snapshot.confirmedAccountRecordName = accountRecordName
            snapshot.requiresAccountConfirmation = false
            if accountChange != .switchedAccounts {
                snapshot.bindings = snapshot.bindings.map { binding in
                    guard binding.erasureRoute != .unresolved else { return binding }
                    return binding.assigningOrigin(
                        accountRecordName: accountRecordName
                    )
                }
            }
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
        receivedAt: Date,
        terminalEvidence: CloudKitFamilyTerminalEvidence? = nil
    ) throws -> UUID {
        try withLock {
            var snapshot = loadLocked()
            let result = appendInboxEntry(
                record: record,
                recordID: recordID,
                scope: scope,
                receivedAt: receivedAt,
                terminalEvidence: terminalEvidence,
                snapshot: &snapshot
            )
            guard result.didMutate else { return result.receiptID }
            try persistLocked(snapshot)
            return result.receiptID
        }
    }

    /// Durably stages a root-record deletion without claiming that the
    /// Profile payload zone is absent. The transport recovery pass must finish
    /// the owner-zone erase (or participant leave), purge local CKAsset source
    /// bytes, and only then atomically advance the binding and expose receipt.
    func stageRemoteRootProfileRemoval(
        record: FamilySyncRecord,
        recordID: CKRecord.ID,
        scope: CloudKitFamilyDatabaseScope,
        receivedAt: Date
    ) throws -> UUID {
        try withLock {
            var snapshot = loadLocked()
            guard
                let binding = snapshot.bindings.first(where: {
                    $0.profileID == record.profileID
                }),
                binding.zoneID == recordID.zoneID,
                binding.rootRecordID == recordID,
                binding.databaseScope == scope,
                isAuthorized(binding, in: snapshot)
            else {
                throw CloudKitFamilyPersistenceError.accountBindingMismatch
            }
            switch (scope, binding.state) {
            case (.privateDatabase, .privateOwner),
                (.sharedDatabase, .sharedParticipant):
                break
            default:
                throw CloudKitFamilyPersistenceError.bindingConflict
            }
            let candidate = CloudKitFamilyInboxEntry(
                receiptID: UUID(),
                scope: scope,
                zoneName: recordID.zoneID.zoneName,
                ownerName: recordID.zoneID.ownerName,
                operation: .save,
                record: record,
                deletionKey: nil,
                receivedAt: receivedAt,
                terminalEvidence: .rootRecordDeletion
            )
            guard
                isPrivacyMinimalTerminalRemoval(
                    candidate,
                    profileID: record.profileID
                )
            else {
                throw CloudKitFamilyPersistenceError.bindingConflict
            }
            let appendResult = appendInboxEntry(
                record: record,
                recordID: recordID,
                scope: scope,
                receivedAt: receivedAt,
                terminalEvidence: .rootRecordDeletion,
                snapshot: &snapshot
            )
            guard appendResult.didMutate else {
                return appendResult.receiptID
            }
            try persistLocked(snapshot)
            return appendResult.receiptID
        }
    }

    /// A deleted-zone callback is sufficient remote proof, but local asset
    /// source cleanup can still fail. Persist the proof first so restart can
    /// retry purge and terminal commit without relying on callback redelivery.
    func stageRemoteZoneProfileRemoval(
        record: FamilySyncRecord,
        recordID: CKRecord.ID,
        scope: CloudKitFamilyDatabaseScope,
        receivedAt: Date
    ) throws -> UUID {
        try withLock {
            var snapshot = loadLocked()
            guard
                let binding = snapshot.bindings.first(where: {
                    $0.profileID == record.profileID
                }),
                binding.zoneID == recordID.zoneID,
                isAuthorized(binding, in: snapshot)
            else {
                throw CloudKitFamilyPersistenceError.accountBindingMismatch
            }
            switch (scope, binding.state) {
            case (.privateDatabase, .privateOwner),
                (.sharedDatabase, .sharedParticipant):
                break
            default:
                throw CloudKitFamilyPersistenceError.bindingConflict
            }
            let candidate = CloudKitFamilyInboxEntry(
                receiptID: UUID(),
                scope: scope,
                zoneName: recordID.zoneID.zoneName,
                ownerName: recordID.zoneID.ownerName,
                operation: .save,
                record: record,
                deletionKey: nil,
                receivedAt: receivedAt,
                terminalEvidence: .zoneDeletion
            )
            guard
                isPrivacyMinimalTerminalRemoval(
                    candidate,
                    profileID: record.profileID
                )
            else {
                throw CloudKitFamilyPersistenceError.bindingConflict
            }
            let appendResult = appendInboxEntry(
                record: record,
                recordID: recordID,
                scope: scope,
                receivedAt: receivedAt,
                terminalEvidence: .zoneDeletion,
                snapshot: &snapshot
            )
            guard appendResult.didMutate else {
                return appendResult.receiptID
            }
            try persistLocked(snapshot)
            return appendResult.receiptID
        }
    }

    /// Atomically records a remote root/zone deletion and advances only the
    /// matching, currently authorized route. Private owner deletion remains an
    /// owner erasure; a shared participant removal remains participant-scoped.
    func commitRemoteProfileRemoval(
        record: FamilySyncRecord,
        recordID: CKRecord.ID,
        scope: CloudKitFamilyDatabaseScope,
        receivedAt: Date,
        terminalEvidence: CloudKitFamilyTerminalEvidence? = .zoneDeletion
    ) throws -> UUID? {
        try withLock {
            var snapshot = loadLocked()
            guard
                let index = snapshot.bindings.firstIndex(where: {
                    $0.zoneName == recordID.zoneID.zoneName
                        && $0.ownerName == recordID.zoneID.ownerName
                })
            else {
                throw CloudKitFamilyPersistenceError.bindingConflict
            }
            let existing = snapshot.bindings[index]
            guard existing.profileID == record.profileID,
                isAuthorized(existing, in: snapshot)
            else {
                throw CloudKitFamilyPersistenceError.accountBindingMismatch
            }

            let nextState: ProfileCloudBindingState
            let route: ProfileErasureRoute
            switch (scope, existing.state) {
            case (.privateDatabase, .privateOwner),
                (.privateDatabase, .ownerDeleted):
                nextState = .ownerDeleted
                route = .owner
            case (.sharedDatabase, .sharedParticipant),
                (.sharedDatabase, .revoked):
                nextState = .revoked
                route = .participant
            case (.sharedDatabase, .participantLeft):
                nextState = .participantLeft
                route = .participant
            case (.privateDatabase, .unbound),
                (.privateDatabase, .sharedParticipant),
                (.privateDatabase, .revoked),
                (.privateDatabase, .participantLeft),
                (.sharedDatabase, .unbound),
                (.sharedDatabase, .privateOwner),
                (.sharedDatabase, .ownerDeleted):
                throw CloudKitFamilyPersistenceError.bindingConflict
            }
            guard existing.erasureRoute == route else {
                throw CloudKitFamilyPersistenceError.bindingConflict
            }
            let candidate = CloudKitFamilyInboxEntry(
                receiptID: UUID(),
                scope: scope,
                zoneName: recordID.zoneID.zoneName,
                ownerName: recordID.zoneID.ownerName,
                operation: .save,
                record: record,
                deletionKey: nil,
                receivedAt: receivedAt,
                terminalEvidence: terminalEvidence
            )
            guard
                isPrivacyMinimalTerminalRemoval(
                    candidate,
                    profileID: record.profileID
                )
            else {
                throw CloudKitFamilyPersistenceError.bindingConflict
            }
            switch terminalEvidence {
            case .rootRecordDeletion:
                guard recordID == existing.rootRecordID else {
                    throw CloudKitFamilyPersistenceError.bindingConflict
                }
            case .zoneDeletion:
                break
            case .ownerDeletionLedger:
                // Control ledgers have their own exact-record-ID recovery
                // commit and can never authorize a payload-zone transition.
                throw CloudKitFamilyPersistenceError.bindingConflict
            case nil:
                // Only an already-terminal legacy schema-v2 receipt may lack
                // evidence. Active bindings require an explicit proof source.
                guard
                    existing.state == .ownerDeleted
                        || existing.state == .revoked
                        || existing.state == .participantLeft
                else {
                    throw CloudKitFamilyPersistenceError.bindingConflict
                }
            }
            if isAcknowledgedTerminalRemoval(record, in: snapshot),
                existing.state == nextState
            {
                return nil
            }

            let appendResult = appendInboxEntry(
                record: record,
                recordID: recordID,
                scope: scope,
                receivedAt: receivedAt,
                terminalEvidence: terminalEvidence,
                snapshot: &snapshot
            )
            snapshot.bindings[index] = ProfileCloudBinding(
                profileID: existing.profileID,
                state: nextState,
                zoneName: existing.zoneName,
                ownerName: existing.ownerName,
                rootRecordName: existing.rootRecordName,
                originAccountRecordName: existing.originAccountRecordName,
                originErasureRoute: existing.originErasureRoute ?? route
            )
            purgeTransportBytes(
                for: existing.profileID,
                zoneName: existing.zoneName,
                ownerName: existing.ownerName,
                snapshot: &snapshot
            )
            retainOnlyTerminalReceipt(
                appendResult.receiptID,
                for: existing.profileID,
                snapshot: &snapshot
            )
            try persistLocked(snapshot)
            return appendResult.receiptID
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
        withLock {
            let snapshot = loadLocked()
            return snapshot.inbox.filter {
                isInboxEntryAuthorized($0, in: snapshot)
            }
        }
    }

    func replayableInboxEntries() -> [CloudKitFamilyInboxEntry] {
        withLock {
            let snapshot = loadLocked()
            return snapshot.inbox.filter { entry in
                guard isInboxEntryAuthorized(entry, in: snapshot) else {
                    return false
                }
                guard entry.terminalEvidence != nil,
                    let profileID = entry.record?.profileID,
                    let binding = snapshot.bindings.first(where: {
                        $0.profileID == profileID
                    })
                else { return true }
                return binding.state == .ownerDeleted
                    || binding.state == .revoked
                    || binding.state == .participantLeft
            }
        }
    }

    func hasPendingInboxWorkForCurrentAccount() -> Bool {
        withLock {
            let snapshot = loadLocked()
            if snapshot.inbox.contains(where: {
                isInboxEntryAuthorized($0, in: snapshot)
            }) {
                return true
            }
            return (snapshot.ambiguousRemoteRemovals ?? []).contains { marker in
                guard
                    let binding = snapshot.bindings.first(where: {
                        $0.profileID == marker.profileID
                    })
                else { return false }
                return marker.originAccountRecordName
                    == binding.originAccountRecordName
                    && isAuthorized(binding, in: snapshot)
            }
        }
    }

    @discardableResult
    func stageAmbiguousRemoteRemoval(
        profileID: ProfileID,
        recordID: CKRecord.ID,
        scope: CloudKitFamilyDatabaseScope,
        evidence: CloudKitAmbiguousRemoteRemovalEvidence,
        receivedAt: Date
    ) throws -> UUID {
        try withLock {
            var snapshot = loadLocked()
            guard !loadFailed,
                let binding = snapshot.bindings.first(where: {
                    $0.profileID == profileID
                }),
                let origin = binding.originAccountRecordName,
                binding.zoneID == recordID.zoneID,
                let rootRecordName = binding.rootRecordName
            else {
                throw CloudKitFamilyPersistenceError.accountBindingMismatch
            }
            switch evidence {
            case .ownerDeletionLedger:
                guard scope == .privateDatabase,
                    binding.state == .privateOwner,
                    binding.erasureRoute == .owner
                else {
                    throw CloudKitFamilyPersistenceError.bindingConflict
                }
            case .rootRecordDeletion, .zoneDeletion:
                switch (scope, binding.state) {
                case (.privateDatabase, .privateOwner),
                    (.sharedDatabase, .sharedParticipant):
                    break
                default:
                    throw CloudKitFamilyPersistenceError.bindingConflict
                }
            }
            if evidence == .rootRecordDeletion
                || evidence == .ownerDeletionLedger,
                recordID != binding.rootRecordID
            {
                throw CloudKitFamilyPersistenceError.bindingConflict
            }
            var markers = snapshot.ambiguousRemoteRemovals ?? []
            if let existing = markers.first(where: {
                $0.profileID == profileID
                    && $0.zoneID == recordID.zoneID
                    && $0.originAccountRecordName == origin
                    && $0.evidence == evidence
            }) {
                return existing.id
            }
            let marker = CloudKitAmbiguousRemoteRemovalMarker(
                id: UUID(),
                profileID: profileID,
                scope: scope,
                zoneName: recordID.zoneID.zoneName,
                ownerName: recordID.zoneID.ownerName,
                rootRecordName: rootRecordName,
                originAccountRecordName: origin,
                evidence: evidence,
                provisionalBindingCreated: false,
                receivedAt: receivedAt
            )
            markers.append(marker)
            snapshot.ambiguousRemoteRemovals = markers.sorted {
                $0.profileID.description < $1.profileID.description
            }
            try persistLocked(snapshot)
            return marker.id
        }
    }

    /// Atomically promotes an account-fenced callback observation into the
    /// explicit durable recovery inbox. A crash can therefore leave either
    /// the privacy-minimal marker or the staged inbox fact, never both.
    @discardableResult
    func promoteAmbiguousRemoteRemoval(
        markerID: UUID,
        record: FamilySyncRecord
    ) throws -> UUID {
        try withLock {
            var snapshot = loadLocked()
            guard
                let marker = (snapshot.ambiguousRemoteRemovals ?? []).first(
                    where: { $0.id == markerID }
                ),
                let binding = snapshot.bindings.first(where: {
                    $0.profileID == marker.profileID
                }),
                isAuthorized(binding, in: snapshot),
                binding.zoneID == marker.zoneID,
                binding.rootRecordName == marker.rootRecordName,
                binding.originAccountRecordName
                    == marker.originAccountRecordName,
                record.profileID == marker.profileID
            else {
                throw CloudKitFamilyPersistenceError.accountBindingMismatch
            }
            switch marker.evidence {
            case .ownerDeletionLedger:
                guard marker.scope == .privateDatabase,
                    binding.state == .privateOwner,
                    binding.erasureRoute == .owner
                else {
                    throw CloudKitFamilyPersistenceError.bindingConflict
                }
            case .rootRecordDeletion, .zoneDeletion:
                switch (marker.scope, binding.state) {
                case (.privateDatabase, .privateOwner),
                    (.sharedDatabase, .sharedParticipant):
                    break
                default:
                    throw CloudKitFamilyPersistenceError.bindingConflict
                }
            }

            let terminalEvidence: CloudKitFamilyTerminalEvidence =
                switch marker.evidence {
                case .ownerDeletionLedger: .ownerDeletionLedger
                case .rootRecordDeletion: .rootRecordDeletion
                case .zoneDeletion: .zoneDeletion
                }
            let stagedRecordID: CKRecord.ID =
                marker.evidence == .ownerDeletionLedger
                ? CloudKitFamilyDeletionLedgerCodec.recordID(
                    for: marker.profileID
                )
                : marker.rootRecordID
            let candidate = CloudKitFamilyInboxEntry(
                receiptID: UUID(),
                scope: marker.scope,
                zoneName: marker.zoneName,
                ownerName: marker.ownerName,
                operation: .save,
                record: record,
                deletionKey: nil,
                receivedAt: marker.receivedAt,
                terminalEvidence: terminalEvidence
            )
            guard
                isPrivacyMinimalTerminalRemoval(
                    candidate,
                    profileID: marker.profileID
                )
            else {
                throw CloudKitFamilyPersistenceError.bindingConflict
            }

            let appendResult = appendInboxEntry(
                record: record,
                recordID: stagedRecordID,
                scope: marker.scope,
                receivedAt: marker.receivedAt,
                terminalEvidence: terminalEvidence,
                snapshot: &snapshot
            )
            snapshot.ambiguousRemoteRemovals?.removeAll {
                $0.id == marker.id
            }
            try persistLocked(snapshot)
            return appendResult.receiptID
        }
    }

    func pendingAmbiguousRemoteRemovalRevalidations() throws
        -> [CloudKitAmbiguousRemoteRemovalMarker]
    {
        try withLock {
            let snapshot = loadLocked()
            guard !loadFailed, !snapshot.requiresAccountConfirmation,
                let confirmed = snapshot.confirmedAccountRecordName
            else {
                throw CloudKitFamilyPersistenceError.accountBindingMismatch
            }
            return try (snapshot.ambiguousRemoteRemovals ?? []).compactMap {
                marker in
                guard marker.originAccountRecordName == confirmed else {
                    return nil
                }
                guard
                    let binding = snapshot.bindings.first(where: {
                        $0.profileID == marker.profileID
                    }),
                    isAuthorized(binding, in: snapshot),
                    binding.zoneID == marker.zoneID,
                    binding.rootRecordName == marker.rootRecordName
                else {
                    throw CloudKitFamilyPersistenceError.bindingConflict
                }
                switch (marker.scope, binding.state) {
                case (.privateDatabase, .privateOwner),
                    (.sharedDatabase, .sharedParticipant):
                    return marker
                case (.privateDatabase, .ownerDeleted),
                    (.sharedDatabase, .revoked),
                    (.sharedDatabase, .participantLeft):
                    return nil
                default:
                    throw CloudKitFamilyPersistenceError.bindingConflict
                }
            }.sorted { left, right in
                if left.profileID != right.profileID {
                    return left.profileID.description
                        < right.profileID.description
                }
                return left.evidence.rawValue < right.evidence.rawValue
            }
        }
    }

    func discardAmbiguousRemoteRemoval(
        _ marker: CloudKitAmbiguousRemoteRemovalMarker
    ) throws {
        try withLock {
            var snapshot = loadLocked()
            guard
                !marker.provisionalBindingCreated,
                let binding = snapshot.bindings.first(where: {
                    $0.profileID == marker.profileID
                }),
                isAuthorized(binding, in: snapshot),
                (snapshot.ambiguousRemoteRemovals ?? []).contains(marker)
            else {
                throw CloudKitFamilyPersistenceError.accountBindingMismatch
            }
            snapshot.ambiguousRemoteRemovals?.removeAll { $0.id == marker.id }
            try persistLocked(snapshot)
        }
    }

    /// Applies exact control-ledger absence proof. A provisional owner binding
    /// is removed only with its marker in the same snapshot and only while no
    /// other evidence still depends on that route. If another marker exists,
    /// this marker remains as durable creation provenance for a later pass.
    @discardableResult
    func discardAmbiguousOwnerDeletionLedgerAbsence(
        _ marker: CloudKitAmbiguousRemoteRemovalMarker
    ) throws -> Bool {
        try withLock {
            var snapshot = loadLocked()
            guard marker.evidence == .ownerDeletionLedger,
                let bindingIndex = snapshot.bindings.firstIndex(where: {
                    $0.profileID == marker.profileID
                }),
                snapshot.ambiguousRemoteRemovals?.contains(marker) == true,
                isAuthorized(snapshot.bindings[bindingIndex], in: snapshot),
                snapshot.bindings[bindingIndex].state == .privateOwner,
                snapshot.bindings[bindingIndex].erasureRoute == .owner,
                snapshot.bindings[bindingIndex].zoneID == marker.zoneID,
                snapshot.bindings[bindingIndex].rootRecordName
                    == marker.rootRecordName,
                snapshot.bindings[bindingIndex].originAccountRecordName
                    == marker.originAccountRecordName
            else {
                throw CloudKitFamilyPersistenceError.accountBindingMismatch
            }

            guard marker.provisionalBindingCreated else {
                snapshot.ambiguousRemoteRemovals?.removeAll {
                    $0.id == marker.id
                }
                try persistLocked(snapshot)
                return true
            }

            let hasOtherMarker = (snapshot.ambiguousRemoteRemovals ?? [])
                .contains {
                    $0.profileID == marker.profileID && $0.id != marker.id
                }
            if hasOtherMarker {
                return false
            }

            let hasExplicitInbox = snapshot.inbox.contains { entry in
                entry.record?.profileID == marker.profileID
                    || entry.deletionKey?.profileID == marker.profileID
            }
            let hasAcknowledgement =
                (snapshot.acknowledgedTerminalRemovals ?? []).contains {
                    $0.profileID == marker.profileID
                }
            snapshot.ambiguousRemoteRemovals?.removeAll {
                $0.id == marker.id
            }
            if !hasExplicitInbox && !hasAcknowledgement {
                let binding = snapshot.bindings[bindingIndex]
                purgeTransportBytes(
                    for: marker.profileID,
                    zoneName: binding.zoneName,
                    ownerName: binding.ownerName,
                    snapshot: &snapshot
                )
                snapshot.bindings.removeAll {
                    $0.profileID == marker.profileID
                }
            }
            try persistLocked(snapshot)
            return true
        }
    }

    func commitAmbiguousRemoteRemoval(
        _ marker: CloudKitAmbiguousRemoteRemovalMarker,
        record: FamilySyncRecord
    ) throws -> UUID {
        try withLock {
            var snapshot = loadLocked()
            guard marker.evidence != .ownerDeletionLedger else {
                throw CloudKitFamilyPersistenceError.bindingConflict
            }
            guard
                let index = snapshot.bindings.firstIndex(where: {
                    $0.profileID == marker.profileID
                }),
                snapshot.ambiguousRemoteRemovals?.contains(marker) == true,
                isAuthorized(snapshot.bindings[index], in: snapshot),
                record.profileID == marker.profileID,
                isPrivacyMinimalTerminalRemoval(
                    CloudKitFamilyInboxEntry(
                        receiptID: UUID(),
                        scope: marker.scope,
                        zoneName: marker.zoneName,
                        ownerName: marker.ownerName,
                        operation: .save,
                        record: record,
                        deletionKey: nil,
                        receivedAt: marker.receivedAt,
                        terminalEvidence: marker.evidence == .rootRecordDeletion
                            ? .rootRecordDeletion : .zoneDeletion
                    ),
                    profileID: marker.profileID
                )
            else {
                throw CloudKitFamilyPersistenceError.accountBindingMismatch
            }
            let binding = snapshot.bindings[index]
            let terminalState: ProfileCloudBindingState
            let route: ProfileErasureRoute
            switch (marker.scope, binding.state) {
            case (.privateDatabase, .privateOwner):
                terminalState = .ownerDeleted
                route = .owner
            case (.sharedDatabase, .sharedParticipant):
                terminalState = .revoked
                route = .participant
            default:
                throw CloudKitFamilyPersistenceError.bindingConflict
            }
            guard binding.zoneID == marker.zoneID,
                binding.rootRecordName == marker.rootRecordName,
                binding.erasureRoute == route
            else {
                throw CloudKitFamilyPersistenceError.bindingConflict
            }
            let evidence: CloudKitFamilyTerminalEvidence
            switch marker.evidence {
            case .ownerDeletionLedger:
                // A control-zone ledger is an intent/fact that still requires
                // payload-zone absence proof; it can never directly terminal.
                throw CloudKitFamilyPersistenceError.bindingConflict
            case .rootRecordDeletion:
                evidence = .rootRecordDeletion
            case .zoneDeletion:
                evidence = .zoneDeletion
            }
            let appendResult = appendInboxEntry(
                record: record,
                recordID: marker.rootRecordID,
                scope: marker.scope,
                receivedAt: marker.receivedAt,
                terminalEvidence: evidence,
                snapshot: &snapshot
            )
            snapshot.bindings[index] = ProfileCloudBinding(
                profileID: binding.profileID,
                state: terminalState,
                zoneName: binding.zoneName,
                ownerName: binding.ownerName,
                rootRecordName: binding.rootRecordName,
                originAccountRecordName: binding.originAccountRecordName,
                originErasureRoute: binding.originErasureRoute ?? route
            )
            purgeTransportBytes(
                for: binding.profileID,
                zoneName: binding.zoneName,
                ownerName: binding.ownerName,
                snapshot: &snapshot
            )
            retainOnlyTerminalReceipt(
                appendResult.receiptID,
                for: binding.profileID,
                snapshot: &snapshot
            )
            try persistLocked(snapshot)
            return appendResult.receiptID
        }
    }

    /// Returns privacy-minimal owner ledgers that a prior CKSyncEngine callback
    /// durably staged but could not prove against the payload zone before the
    /// process stopped. Any malformed route fails closed instead of allowing
    /// general inbox replay to expose a local deletion prematurely.
    func pendingOwnerDeletionLedgerRecoveries() throws
        -> [CloudKitStagedOwnerDeletionLedgerRecovery]
    {
        try withLock {
            let snapshot = loadLocked()
            guard !loadFailed, !snapshot.requiresAccountConfirmation,
                snapshot.confirmedAccountRecordName != nil
            else {
                throw CloudKitFamilyPersistenceError.accountBindingMismatch
            }

            var recoveries: [CloudKitStagedOwnerDeletionLedgerRecovery] = []
            for entry in snapshot.inbox where isInboxEntryAuthorized(entry, in: snapshot) {
                guard entry.operation == .save,
                    entry.scope == .privateDatabase,
                    let record = entry.record,
                    record.kind == .profileDeletion,
                    record.isDeleted
                else { continue }
                // Only the private control zone can contain the authoritative
                // owner ledger. Profile-zone receipts represent a staged root
                // deletion or an already-proven zone deletion and must flow to
                // their own recovery/general-replay paths.
                guard
                    entry.zoneName
                        == CloudKitFamilyDeletionLedgerCodec.controlZoneID.zoneName,
                    entry.ownerName
                        == CloudKitFamilyDeletionLedgerCodec.controlZoneID.ownerName
                else { continue }
                guard
                    entry.terminalEvidence == nil
                        || entry.terminalEvidence == .ownerDeletionLedger
                else {
                    throw CloudKitFamilyPersistenceError.bindingConflict
                }
                guard
                    isPrivacyMinimalTerminalRemoval(
                        entry,
                        profileID: record.profileID
                    )
                else {
                    throw CloudKitFamilyPersistenceError.bindingConflict
                }

                let recordID = CloudKitFamilyDeletionLedgerCodec.recordID(
                    for: record.profileID
                )
                let expectedZoneID = CKRecordZone.ID(
                    zoneName: "TadaProfile-\(record.profileID.rawValue.uuidString)",
                    ownerName: CKCurrentUserDefaultName
                )
                let expectedRootName =
                    "profile-root-\(record.profileID.rawValue.uuidString)"
                guard
                    entry.zoneName == recordID.zoneID.zoneName,
                    entry.ownerName == recordID.zoneID.ownerName,
                    let binding = snapshot.bindings.first(where: {
                        $0.profileID == record.profileID
                    }),
                    isAuthorized(binding, in: snapshot),
                    binding.erasureRoute == .owner,
                    binding.zoneID == expectedZoneID,
                    binding.rootRecordName == expectedRootName
                else {
                    throw CloudKitFamilyPersistenceError.bindingConflict
                }
                if binding.state == .ownerDeleted {
                    // Zone erasure and the atomic terminal commit already
                    // succeeded before the prior process stopped. General
                    // inbox replay below may now expose the durable receipt;
                    // never erase a second time merely because it is unacked.
                    continue
                }
                guard binding.state == .privateOwner else {
                    throw CloudKitFamilyPersistenceError.bindingConflict
                }
                recoveries.append(
                    CloudKitStagedOwnerDeletionLedgerRecovery(
                        record: record,
                        recordID: recordID,
                        binding: binding,
                        receivedAt: entry.receivedAt
                    )
                )
            }

            guard
                Set(recoveries.map { $0.record.profileID }).count
                    == recoveries.count
            else {
                throw CloudKitFamilyPersistenceError.corruptMetadata
            }
            return recoveries.sorted {
                $0.record.profileID.description
                    < $1.record.profileID.description
            }
        }
    }

    /// Returns root-only deletion facts that survived a callback/process
    /// boundary. They are intentionally distinct from owner control ledgers:
    /// the bound payload zone has not yet been proven absent.
    func pendingRemoteRootRemovalRecoveries() throws
        -> [CloudKitStagedRemoteRootRemovalRecovery]
    {
        try withLock {
            let snapshot = loadLocked()
            guard !loadFailed, !snapshot.requiresAccountConfirmation,
                snapshot.confirmedAccountRecordName != nil
            else {
                throw CloudKitFamilyPersistenceError.accountBindingMismatch
            }

            var recoveries: [CloudKitStagedRemoteRootRemovalRecovery] = []
            for entry in snapshot.inbox where isInboxEntryAuthorized(entry, in: snapshot) {
                guard entry.operation == .save,
                    let record = entry.record,
                    record.kind == .profileDeletion,
                    record.isDeleted,
                    entry.terminalEvidence == .rootRecordDeletion
                        || entry.terminalEvidence == nil
                else { continue }
                guard
                    isPrivacyMinimalTerminalRemoval(
                        entry,
                        profileID: record.profileID
                    ),
                    let binding = snapshot.bindings.first(where: {
                        $0.profileID == record.profileID
                    }),
                    isAuthorized(binding, in: snapshot),
                    let rootRecordID = binding.rootRecordID,
                    entry.zoneName == rootRecordID.zoneID.zoneName,
                    entry.ownerName == rootRecordID.zoneID.ownerName
                else {
                    throw CloudKitFamilyPersistenceError.bindingConflict
                }
                switch (entry.scope, binding.state) {
                case (.privateDatabase, .privateOwner),
                    (.sharedDatabase, .sharedParticipant):
                    guard entry.terminalEvidence == .rootRecordDeletion else {
                        // Evidence-less active payload-zone tombstones may be
                        // ordinary versioned records from an older writer.
                        // Never reinterpret them as a root deletion.
                        continue
                    }
                    recoveries.append(
                        CloudKitStagedRemoteRootRemovalRecovery(
                            record: record,
                            recordID: rootRecordID,
                            scope: entry.scope,
                            binding: binding,
                            receivedAt: entry.receivedAt,
                            terminalEvidence: entry.terminalEvidence
                        )
                    )
                case (.privateDatabase, .ownerDeleted),
                    (.sharedDatabase, .revoked),
                    (.sharedDatabase, .participantLeft):
                    if entry.terminalEvidence == nil {
                        // Pre-evidence schema-v2 terminal receipts cannot prove
                        // whether only the root or the entire zone was deleted.
                        // Recover conservatively through the idempotent remote
                        // removal before allowing replay.
                        recoveries.append(
                            CloudKitStagedRemoteRootRemovalRecovery(
                                record: record,
                                recordID: rootRecordID,
                                scope: entry.scope,
                                binding: binding,
                                receivedAt: entry.receivedAt,
                                terminalEvidence: nil
                            )
                        )
                    } else {
                        // The explicit atomic terminal transition already
                        // succeeded. Keep its receipt for ordinary replay.
                        continue
                    }
                default:
                    throw CloudKitFamilyPersistenceError.bindingConflict
                }
            }
            guard
                Set(recoveries.map { $0.record.profileID }).count
                    == recoveries.count
            else {
                throw CloudKitFamilyPersistenceError.corruptMetadata
            }
            return recoveries.sorted {
                $0.record.profileID.description
                    < $1.record.profileID.description
            }
        }
    }

    func pendingRemoteZoneRemovalRecoveries() throws
        -> [CloudKitStagedRemoteZoneRemovalRecovery]
    {
        try withLock {
            let snapshot = loadLocked()
            guard !loadFailed, !snapshot.requiresAccountConfirmation,
                snapshot.confirmedAccountRecordName != nil
            else {
                throw CloudKitFamilyPersistenceError.accountBindingMismatch
            }
            var recoveries: [CloudKitStagedRemoteZoneRemovalRecovery] = []
            for entry in snapshot.inbox where isInboxEntryAuthorized(entry, in: snapshot) {
                guard entry.operation == .save,
                    entry.terminalEvidence == .zoneDeletion
                else { continue }
                guard let record = entry.record,
                    isPrivacyMinimalTerminalRemoval(
                        entry,
                        profileID: record.profileID
                    ),
                    let binding = snapshot.bindings.first(where: {
                        $0.profileID == record.profileID
                    }),
                    isAuthorized(binding, in: snapshot),
                    let rootRecordID = binding.rootRecordID,
                    entry.zoneName == rootRecordID.zoneID.zoneName,
                    entry.ownerName == rootRecordID.zoneID.ownerName
                else {
                    throw CloudKitFamilyPersistenceError.bindingConflict
                }
                switch (entry.scope, binding.state) {
                case (.privateDatabase, .privateOwner),
                    (.sharedDatabase, .sharedParticipant):
                    recoveries.append(
                        CloudKitStagedRemoteZoneRemovalRecovery(
                            record: record,
                            recordID: rootRecordID,
                            scope: entry.scope,
                            binding: binding,
                            receivedAt: entry.receivedAt
                        )
                    )
                case (.privateDatabase, .ownerDeleted),
                    (.sharedDatabase, .revoked),
                    (.sharedDatabase, .participantLeft):
                    continue
                default:
                    throw CloudKitFamilyPersistenceError.bindingConflict
                }
            }
            guard
                Set(recoveries.map { $0.record.profileID }).count
                    == recoveries.count
            else {
                throw CloudKitFamilyPersistenceError.corruptMetadata
            }
            return recoveries.sorted {
                $0.record.profileID.description
                    < $1.record.profileID.description
            }
        }
    }

    func acknowledgeInbox(receiptIDs: Set<UUID>) throws {
        guard !receiptIDs.isEmpty else { return }
        try withLock {
            var snapshot = loadLocked()
            let acknowledgedEntries = snapshot.inbox.filter {
                receiptIDs.contains($0.receiptID)
            }
            var markers = snapshot.acknowledgedTerminalRemovals ?? []
            for entry in acknowledgedEntries {
                guard let record = entry.record,
                    isPrivacyMinimalTerminalRemoval(
                        entry,
                        profileID: record.profileID
                    )
                else { continue }
                let marker = CloudKitAcknowledgedTerminalRemoval(
                    profileID: record.profileID,
                    logicalRevision: record.logicalRevision
                )
                markers.removeAll { $0.profileID == marker.profileID }
                markers.append(marker)
            }
            snapshot.acknowledgedTerminalRemovals = markers.sorted {
                $0.profileID.description < $1.profileID.description
            }
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
        // Bindings are account-scoped deletion provenance. Preserve them
        // byte-for-byte so a different signed-in account cannot turn a former
        // owner/participant tombstone into a fresh private-zone operation.
        snapshot.systemFields.removeAll()
        // Transport-owned bytes are scoped to the CloudKit account that
        // fetched them. Never replay an old account's unacknowledged inbox or
        // let its quarantine locks block a newly confirmed account. Local app
        // repositories are deliberately untouched.
        let bindingsByProfileID = Dictionary(
            uniqueKeysWithValues: snapshot.bindings.map {
                ($0.profileID, $0)
            }
        )
        snapshot.inbox.removeAll { entry in
            guard let profileID = entry.record?.profileID,
                let binding = bindingsByProfileID[profileID],
                isPrivacyMinimalTerminalRemoval(
                    entry,
                    profileID: profileID
                )
            else { return true }
            let isLegacyTerminalReceipt =
                entry.terminalEvidence == nil
                && (binding.state == .ownerDeleted
                    || binding.state == .revoked
                    || binding.state == .participantLeft)
            return entry.terminalEvidence == nil && !isLegacyTerminalReceipt
        }
        snapshot.quarantined.removeAll()
        snapshot.protectedRecordKeys.removeAll()
        // Terminal acknowledgements are keyed by Profile and their immutable
        // binding carries account provenance. Preserve them dormant across a
        // switch so returning to the origin account cannot repeat erasure.
    }

    private func isInboxEntryAuthorized(
        _ entry: CloudKitFamilyInboxEntry,
        in snapshot: CloudKitFamilyMetadataSnapshot
    ) -> Bool {
        let profileID = entry.record?.profileID ?? entry.deletionKey?.profileID
        guard let profileID,
            let binding = snapshot.bindings.first(where: {
                $0.profileID == profileID
            })
        else { return false }
        return isAuthorized(binding, in: snapshot)
    }

    private func appendInboxEntry(
        record: FamilySyncRecord,
        recordID: CKRecord.ID,
        scope: CloudKitFamilyDatabaseScope,
        receivedAt: Date,
        terminalEvidence: CloudKitFamilyTerminalEvidence? = nil,
        snapshot: inout CloudKitFamilyMetadataSnapshot
    ) -> (receiptID: UUID, didMutate: Bool) {
        if let existing = snapshot.inbox.first(where: {
            $0.operation == .save && $0.record == record
                && $0.scope == scope
                && $0.zoneName == recordID.zoneID.zoneName
                && $0.ownerName == recordID.zoneID.ownerName
                && $0.terminalEvidence == terminalEvidence
        }) {
            let cleared = clearQuarantine(
                recordID: recordID,
                scope: scope,
                snapshot: &snapshot
            )
            return (existing.receiptID, cleared)
        }
        let entry = CloudKitFamilyInboxEntry(
            receiptID: UUID(),
            scope: scope,
            zoneName: recordID.zoneID.zoneName,
            ownerName: recordID.zoneID.ownerName,
            operation: .save,
            record: record,
            deletionKey: nil,
            receivedAt: receivedAt,
            terminalEvidence: terminalEvidence
        )
        snapshot.inbox.append(entry)
        _ = clearQuarantine(
            recordID: recordID,
            scope: scope,
            snapshot: &snapshot
        )
        return (entry.receiptID, true)
    }

    private func isAuthorized(
        _ binding: ProfileCloudBinding,
        in snapshot: CloudKitFamilyMetadataSnapshot
    ) -> Bool {
        guard !loadFailed, !snapshot.requiresAccountConfirmation,
            let confirmed = snapshot.confirmedAccountRecordName,
            let origin = binding.originAccountRecordName
        else { return false }
        return confirmed == origin
    }

    private func canReplace(
        _ existing: ProfileCloudBinding,
        with candidate: ProfileCloudBinding
    ) -> Bool {
        guard existing.profileID == candidate.profileID,
            existing.state == candidate.state,
            existing.state == .privateOwner
                || existing.state == .sharedParticipant,
            existing.zoneName == candidate.zoneName,
            existing.ownerName == candidate.ownerName
        else { return false }
        guard let existingRoot = existing.rootRecordName else { return true }
        return candidate.rootRecordName == existingRoot
    }

    private func isAcknowledgedTerminalRemoval(
        _ record: FamilySyncRecord,
        in snapshot: CloudKitFamilyMetadataSnapshot
    ) -> Bool {
        let marker = CloudKitAcknowledgedTerminalRemoval(
            profileID: record.profileID,
            logicalRevision: record.logicalRevision
        )
        return (snapshot.acknowledgedTerminalRemovals ?? []).contains(marker)
    }

    private func isValidMetadataSnapshot(
        _ snapshot: CloudKitFamilyMetadataSnapshot
    ) -> Bool {
        func isNonEmpty(_ value: String?) -> Bool {
            guard let value else { return false }
            return !value.trimmingCharacters(
                in: .whitespacesAndNewlines
            ).isEmpty
        }

        if let confirmed = snapshot.confirmedAccountRecordName,
            !isNonEmpty(confirmed)
        {
            return false
        }
        if !snapshot.requiresAccountConfirmation,
            !isNonEmpty(snapshot.confirmedAccountRecordName)
        {
            return false
        }

        var profileIDs = Set<ProfileID>()
        var zones = Set<String>()
        for binding in snapshot.bindings {
            guard profileIDs.insert(binding.profileID).inserted else {
                return false
            }
            switch binding.state {
            case .unbound:
                guard binding.zoneName == nil,
                    binding.ownerName == nil,
                    binding.rootRecordName == nil,
                    binding.originAccountRecordName == nil,
                    binding.originErasureRoute == nil
                        || binding.originErasureRoute == .unresolved
                else { return false }
            case .privateOwner, .ownerDeleted:
                guard isNonEmpty(binding.zoneName),
                    isNonEmpty(binding.ownerName),
                    isNonEmpty(binding.rootRecordName),
                    isNonEmpty(binding.originAccountRecordName),
                    binding.originErasureRoute == .owner
                else { return false }
            case .sharedParticipant, .revoked, .participantLeft:
                guard isNonEmpty(binding.zoneName),
                    isNonEmpty(binding.ownerName),
                    isNonEmpty(binding.rootRecordName),
                    isNonEmpty(binding.originAccountRecordName),
                    binding.originErasureRoute == .participant
                else { return false }
            }
            if let zoneName = binding.zoneName,
                let ownerName = binding.ownerName
            {
                guard zones.insert("\(ownerName)|\(zoneName)").inserted else {
                    return false
                }
            }
        }

        let receiptIDs = snapshot.inbox.map(\.receiptID)
        guard Set(receiptIDs).count == receiptIDs.count else { return false }

        let bindingsByProfileID = Dictionary(
            uniqueKeysWithValues: snapshot.bindings.map {
                ($0.profileID, $0)
            }
        )
        for entry in snapshot.inbox {
            guard let evidence = entry.terminalEvidence else { continue }
            guard entry.operation == .save,
                let record = entry.record,
                let binding = bindingsByProfileID[record.profileID],
                isPrivacyMinimalTerminalRemoval(
                    entry,
                    profileID: record.profileID
                )
            else { return false }
            switch evidence {
            case .ownerDeletionLedger:
                guard entry.scope == .privateDatabase,
                    entry.zoneName
                        == CloudKitFamilyDeletionLedgerCodec.controlZoneID.zoneName,
                    entry.ownerName
                        == CloudKitFamilyDeletionLedgerCodec.controlZoneID.ownerName,
                    binding.erasureRoute == .owner,
                    binding.state == .privateOwner
                        || binding.state == .ownerDeleted
                else { return false }
            case .rootRecordDeletion, .zoneDeletion:
                guard entry.zoneName == binding.zoneName,
                    entry.ownerName == binding.ownerName
                else { return false }
                switch (entry.scope, binding.state) {
                case (.privateDatabase, .privateOwner),
                    (.privateDatabase, .ownerDeleted),
                    (.sharedDatabase, .sharedParticipant),
                    (.sharedDatabase, .revoked),
                    (.sharedDatabase, .participantLeft):
                    break
                default:
                    return false
                }
            }
        }

        var markerProfileIDs = Set<ProfileID>()
        for marker in snapshot.acknowledgedTerminalRemovals ?? [] {
            guard markerProfileIDs.insert(marker.profileID).inserted,
                let binding = snapshot.bindings.first(where: {
                    $0.profileID == marker.profileID
                }),
                binding.state == .ownerDeleted
                    || binding.state == .revoked
                    || binding.state == .participantLeft
            else { return false }
        }

        var ambiguousMarkerIDs = Set<UUID>()
        var ambiguousEvidenceKeys = Set<String>()
        var provisionalBindingProfiles = Set<ProfileID>()
        for marker in snapshot.ambiguousRemoteRemovals ?? [] {
            let evidenceKey =
                "\(marker.profileID)|\(marker.ownerName)|"
                + "\(marker.zoneName)|\(marker.evidence.rawValue)"
            guard ambiguousMarkerIDs.insert(marker.id).inserted,
                ambiguousEvidenceKeys.insert(evidenceKey).inserted,
                isNonEmpty(marker.zoneName),
                isNonEmpty(marker.ownerName),
                isNonEmpty(marker.rootRecordName),
                isNonEmpty(marker.originAccountRecordName),
                let binding = bindingsByProfileID[marker.profileID],
                binding.zoneID == marker.zoneID,
                binding.rootRecordName == marker.rootRecordName,
                binding.originAccountRecordName
                    == marker.originAccountRecordName
            else { return false }
            switch marker.evidence {
            case .ownerDeletionLedger:
                guard marker.scope == .privateDatabase,
                    binding.state == .privateOwner,
                    binding.erasureRoute == .owner
                else { return false }
                if marker.provisionalBindingCreated,
                    !provisionalBindingProfiles.insert(marker.profileID).inserted
                {
                    return false
                }
            case .rootRecordDeletion, .zoneDeletion:
                guard !marker.provisionalBindingCreated else { return false }
                switch (marker.scope, binding.state) {
                case (.privateDatabase, .privateOwner),
                    (.sharedDatabase, .sharedParticipant):
                    break
                default:
                    return false
                }
            }
        }
        return true
    }

    private func loadLocked() -> CloudKitFamilyMetadataSnapshot {
        if let cached { return cached }
        guard FileManager.default.fileExists(atPath: snapshotURL.path) else {
            let empty = CloudKitFamilyMetadataSnapshot()
            cached = empty
            return empty
        }
        guard let data = try? Data(contentsOf: snapshotURL),
            var decoded = try? JSONDecoder().decode(
                CloudKitFamilyMetadataSnapshot.self,
                from: data
            ),
            (1...CloudKitFamilyMetadataSnapshot.currentSchemaVersion).contains(
                decoded.schemaVersion
            )
        else {
            // Preserve unreadable routing/account/inbox bytes and latch the
            // failure. Reconfirming must never convert a formerly shared
            // profile into a fresh private zone after metadata corruption.
            loadFailed = true
            let empty = CloudKitFamilyMetadataSnapshot()
            cached = empty
            return empty
        }
        let requiresMigration = decoded.schemaVersion == 1
        if requiresMigration {
            decoded.schemaVersion = CloudKitFamilyMetadataSnapshot.currentSchemaVersion
            decoded.bindings = decoded.bindings.map { binding in
                binding.assigningOrigin(
                    accountRecordName: binding.state == .unbound
                        ? nil
                        : decoded.confirmedAccountRecordName
                )
            }
        }
        guard isValidMetadataSnapshot(decoded) else {
            // Structurally ambiguous routing metadata is as unsafe as
            // unreadable JSON. Keep the original bytes untouched and latch a
            // fail-closed account gate rather than guessing which zone wins.
            loadFailed = true
            let empty = CloudKitFamilyMetadataSnapshot()
            cached = empty
            return empty
        }
        if requiresMigration {
            do {
                try persistLocked(decoded)
            } catch {
                // Do not expose an in-memory provenance upgrade that did not
                // become durable. The original v1 bytes remain untouched by
                // the atomic write and the account gate fails closed.
                loadFailed = true
                let empty = CloudKitFamilyMetadataSnapshot()
                cached = empty
                return empty
            }
        } else {
            cached = decoded
        }
        return decoded
    }

    private func persistLocked(_ snapshot: CloudKitFamilyMetadataSnapshot) throws {
        guard !loadFailed else {
            throw CloudKitFamilyPersistenceError.corruptMetadata
        }
        guard isValidMetadataSnapshot(snapshot) else {
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
    case accountBindingMismatch
    case bindingConflict
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
