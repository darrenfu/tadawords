import Foundation
import TadaWordsDomain

public struct FamilySyncManifestEntry: Codable, Equatable, Sendable {
    public let key: FamilySyncChangeKey
    public let kind: FamilySyncRecordKind
    public let schemaVersion: Int
    public let minimumReadableVersion: Int
    public let revision: FamilySyncLogicalRevision
    public let payloadChecksum: String
    public let payloadSize: Int
    public let isDeleted: Bool

    public init(record: FamilySyncRecord) {
        key = FamilySyncChangeKey(
            profileID: record.profileID,
            recordName: record.recordName
        )
        kind = record.kind
        schemaVersion = record.schemaVersion
        minimumReadableVersion = record.minimumReadableVersion
        revision = record.logicalRevision
        payloadChecksum = record.payloadChecksum
        payloadSize = record.payloadSize
        isDeleted = record.isDeleted
    }

    public init(
        key: FamilySyncChangeKey,
        kind: FamilySyncRecordKind,
        schemaVersion: Int,
        minimumReadableVersion: Int,
        revision: FamilySyncLogicalRevision,
        payloadChecksum: String,
        payloadSize: Int,
        isDeleted: Bool
    ) {
        self.key = key
        self.kind = kind
        self.schemaVersion = schemaVersion
        self.minimumReadableVersion = minimumReadableVersion
        self.revision = revision
        self.payloadChecksum = payloadChecksum
        self.payloadSize = payloadSize
        self.isDeleted = isDeleted
    }

    fileprivate func hasSameContent(as record: FamilySyncRecord) -> Bool {
        kind == record.kind
            && schemaVersion == record.schemaVersion
            && minimumReadableVersion == record.minimumReadableVersion
            && payloadChecksum == record.payloadChecksum
            && payloadSize == record.payloadSize
            && isDeleted == record.isDeleted
    }

    fileprivate func hasSameServerValue(as other: Self) -> Bool {
        kind == other.kind
            && schemaVersion == other.schemaVersion
            && minimumReadableVersion == other.minimumReadableVersion
            && revision == other.revision
            && payloadChecksum == other.payloadChecksum
            && payloadSize == other.payloadSize
            && isDeleted == other.isDeleted
    }
}

public struct FamilySyncOutboxEntry: Codable, Equatable, Sendable {
    public enum Operation: String, Codable, Equatable, Sendable {
        case save
        case delete

        fileprivate var operationKind: FamilySyncChangeOperationKind {
            switch self {
            case .save:
                .save
            case .delete:
                .delete
            }
        }
    }

    public let key: FamilySyncChangeKey
    public let operation: Operation
    public let revision: FamilySyncLogicalRevision
    public let firstQueuedAt: Date
    public let lastQueuedAt: Date
    public let retryCount: Int
    public let nextRetryAt: Date?
    public let lastAttemptAt: Date?
    public let errorCategory: FamilySyncPrivacySafeErrorCategory?

    public init(
        key: FamilySyncChangeKey,
        operation: Operation,
        revision: FamilySyncLogicalRevision,
        firstQueuedAt: Date,
        lastQueuedAt: Date,
        retryCount: Int = 0,
        nextRetryAt: Date? = nil,
        lastAttemptAt: Date? = nil,
        errorCategory: FamilySyncPrivacySafeErrorCategory? = nil
    ) {
        self.key = key
        self.operation = operation
        self.revision = revision
        self.firstQueuedAt = firstQueuedAt
        self.lastQueuedAt = lastQueuedAt
        self.retryCount = max(0, retryCount)
        self.nextRetryAt = nextRetryAt
        self.lastAttemptAt = lastAttemptAt
        self.errorCategory = errorCategory
    }
}

/// Narrow outbox metadata needed to resume one Profile erasure. It deliberately
/// excludes payloads and every unrelated journal entry.
public struct ProfileDeletionPendingDeliveryEvidence: Equatable, Sendable {
    public let acknowledgement: FamilySyncChangeAcknowledgement
    public let firstQueuedAt: Date
    public let lastQueuedAt: Date
    public let retryCount: Int
    public let nextRetryAt: Date?
    public let lastAttemptAt: Date?
    public let errorCategory: FamilySyncPrivacySafeErrorCategory?

    public init(
        acknowledgement: FamilySyncChangeAcknowledgement,
        firstQueuedAt: Date,
        lastQueuedAt: Date,
        retryCount: Int,
        nextRetryAt: Date?,
        lastAttemptAt: Date?,
        errorCategory: FamilySyncPrivacySafeErrorCategory?
    ) {
        self.acknowledgement = acknowledgement
        self.firstQueuedAt = firstQueuedAt
        self.lastQueuedAt = lastQueuedAt
        self.retryCount = max(0, retryCount)
        self.nextRetryAt = nextRetryAt
        self.lastAttemptAt = lastAttemptAt
        self.errorCategory = errorCategory
    }
}

public enum ProfileDeletionDeliveryEvidence: Equatable, Sendable {
    case notQueued
    case pending(ProfileDeletionPendingDeliveryEvidence)
    case acknowledged(FamilySyncChangeAcknowledgement)
}

public enum FamilySyncDurableCondition: String, Codable, Sendable {
    case idle
    case waitingForConnection
    case iCloudUnavailable
    case needsAttention
}

public struct FamilySyncDurableStatus: Codable, Equatable, Sendable {
    public let pendingCount: Int
    public let lastAttemptAt: Date?
    public let lastSuccessAt: Date?
    public let errorCategory: FamilySyncPrivacySafeErrorCategory?
    public let condition: FamilySyncDurableCondition
    public let retryCount: Int
    public let nextRetryAt: Date?

    public init(
        pendingCount: Int,
        lastAttemptAt: Date?,
        lastSuccessAt: Date?,
        errorCategory: FamilySyncPrivacySafeErrorCategory?,
        condition: FamilySyncDurableCondition = .idle,
        retryCount: Int = 0,
        nextRetryAt: Date? = nil
    ) {
        self.pendingCount = max(0, pendingCount)
        self.lastAttemptAt = lastAttemptAt
        self.lastSuccessAt = lastSuccessAt
        self.errorCategory = errorCategory
        self.condition = condition
        self.retryCount = max(0, retryCount)
        self.nextRetryAt = nextRetryAt
    }

    public static let empty = Self(
        pendingCount: 0,
        lastAttemptAt: nil,
        lastSuccessAt: nil,
        errorCategory: nil,
        condition: .idle
    )

    private enum CodingKeys: String, CodingKey {
        case pendingCount
        case lastAttemptAt
        case lastSuccessAt
        case errorCategory
        case condition
        case retryCount
        case nextRetryAt
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let pendingCount = try container.decode(Int.self, forKey: .pendingCount)
        let errorCategory = try container.decodeIfPresent(
            FamilySyncPrivacySafeErrorCategory.self,
            forKey: .errorCategory
        )
        self.init(
            pendingCount: pendingCount,
            lastAttemptAt: try container.decodeIfPresent(
                Date.self,
                forKey: .lastAttemptAt
            ),
            lastSuccessAt: try container.decodeIfPresent(
                Date.self,
                forKey: .lastSuccessAt
            ),
            errorCategory: errorCategory,
            condition: try container.decodeIfPresent(
                FamilySyncDurableCondition.self,
                forKey: .condition
            )
                ?? Self.legacyCondition(
                    pendingCount: pendingCount,
                    errorCategory: errorCategory
                ),
            retryCount: try container.decodeIfPresent(
                Int.self,
                forKey: .retryCount
            ) ?? 0,
            nextRetryAt: try container.decodeIfPresent(
                Date.self,
                forKey: .nextRetryAt
            )
        )
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(pendingCount, forKey: .pendingCount)
        try container.encodeIfPresent(lastAttemptAt, forKey: .lastAttemptAt)
        try container.encodeIfPresent(lastSuccessAt, forKey: .lastSuccessAt)
        try container.encodeIfPresent(errorCategory, forKey: .errorCategory)
        try container.encode(condition, forKey: .condition)
        try container.encode(retryCount, forKey: .retryCount)
        try container.encodeIfPresent(nextRetryAt, forKey: .nextRetryAt)
    }

    static func condition(
        for category: FamilySyncPrivacySafeErrorCategory?
    ) -> FamilySyncDurableCondition {
        switch category {
        case .account:
            .iCloudUnavailable
        case .connectivity, .rateLimited, .server:
            .waitingForConnection
        case .compatibility, .corruptState, .conflict, .unknown:
            .needsAttention
        case nil:
            .idle
        }
    }

    private static func legacyCondition(
        pendingCount: Int,
        errorCategory: FamilySyncPrivacySafeErrorCategory?
    ) -> FamilySyncDurableCondition {
        let mapped = condition(for: errorCategory)
        if mapped == .idle, pendingCount > 0 { return .waitingForConnection }
        return mapped
    }
}

public struct FamilySyncJournalSnapshot: Codable, Equatable, Sendable {
    public static let currentSchemaVersion = 1

    public let schemaVersion: Int
    public let localManifest: [FamilySyncManifestEntry]
    public let acknowledgedManifest: [FamilySyncManifestEntry]
    public let outbox: [FamilySyncOutboxEntry]
    public let status: FamilySyncDurableStatus

    public init(
        schemaVersion: Int = Self.currentSchemaVersion,
        localManifest: [FamilySyncManifestEntry] = [],
        acknowledgedManifest: [FamilySyncManifestEntry] = [],
        outbox: [FamilySyncOutboxEntry] = [],
        status: FamilySyncDurableStatus = .empty
    ) {
        self.schemaVersion = schemaVersion
        self.localManifest = localManifest
        self.acknowledgedManifest = acknowledgedManifest
        self.outbox = outbox
        self.status = status
    }
}

public enum FamilySyncJournalError: Error, Equatable, Sendable {
    case readFailed(snapshotURL: URL, details: String)
    case invalidJSON(snapshotURL: URL, details: String)
    case unsupportedSchemaVersion(snapshotURL: URL, found: Int, supported: Int)
    case duplicateManifestKey(FamilySyncChangeKey)
    case duplicateOutboxKey(FamilySyncChangeKey)
    case inconsistentProfileDeletionEvidence
    case writeFailed(snapshotURL: URL, details: String)
}

public protocol FamilySyncJournalRepository: Sendable {
    func reconcileLocalRecords(
        _ records: [FamilySyncRecord],
        deviceID: String,
        now: Date
    ) async throws -> [FamilySyncRecord]

    func pendingChanges(
        using records: [FamilySyncRecord],
        now: Date
    ) async throws -> [FamilySyncPendingOperation]

    func recordAttempt(
        keys: Set<FamilySyncChangeKey>,
        at date: Date
    ) async throws

    func recordTransportResult(
        acknowledged: Set<FamilySyncChangeAcknowledgement>,
        failures: [FamilySyncTransportFailure],
        at date: Date
    ) async throws

    func recordAppliedRemote(
        records: [FamilySyncRecord],
        deletions: [FamilySyncRemoteDeletion],
        at date: Date
    ) async throws

    func invalidateAcknowledgementsForAccountChange(at date: Date) async throws

    /// Removes cached, nonterminal records that were only discovered during an
    /// unfinished first-run flow. The caller must hold a durable disabled-sync
    /// fence. Canonical Profile-deletion evidence is always retained so an
    /// account change cannot weaken a privacy boundary.
    func discardUnadoptedProfileState() async throws

    /// Returns every Profile identity referenced by nonterminal cached state.
    /// Callers must snapshot this set before discarding the journal so they
    /// can erase canonical child data even when no Profile row exists.
    func unadoptedProfileIDs() async throws -> Set<ProfileID>

    func hasUnadoptedProfileState() async throws -> Bool

    func recordParentVisibleCondition(
        _ condition: FamilySyncDurableCondition,
        errorCategory: FamilySyncPrivacySafeErrorCategory?,
        at date: Date
    ) async throws

    func durableStatus() async throws -> FamilySyncDurableStatus

    func profileDeletionDeliveryEvidence(
        for profileID: ProfileID
    ) async throws -> ProfileDeletionDeliveryEvidence

    func requeueProfileDeletion(
        for profileID: ProfileID,
        errorCategory: FamilySyncPrivacySafeErrorCategory,
        at date: Date
    ) async throws
}

/// Test/demo fallback only. Production composition always injects the durable
/// JSON repository below.
public actor VolatileFamilySyncJournalRepository: FamilySyncJournalRepository {
    private var records: [FamilySyncChangeKey: FamilySyncRecord] = [:]
    private var acknowledged: [FamilySyncChangeKey: FamilySyncLogicalRevision] = [:]
    private var pending: Set<FamilySyncChangeKey> = []
    private var lastAttemptAt: Date?
    private var lastSuccessAt: Date?
    private var errorCategory: FamilySyncPrivacySafeErrorCategory?
    private var condition = FamilySyncDurableCondition.idle

    public init() {}

    public func reconcileLocalRecords(
        _ candidates: [FamilySyncRecord],
        deviceID: String,
        now: Date
    ) -> [FamilySyncRecord] {
        _ = now
        var versioned: [FamilySyncRecord] = []
        for candidate in candidates {
            let key = FamilySyncChangeKey(
                profileID: candidate.profileID,
                recordName: candidate.recordName
            )
            let existing = records[key]
            let unchanged =
                existing?.payloadChecksum == candidate.payloadChecksum
                && existing?.isDeleted == candidate.isDeleted
            let revision =
                unchanged
                ? existing!.logicalRevision
                : .next(
                    after: [existing?.logicalRevision].compactMap { $0 },
                    deviceID: deviceID
                )
            let record = candidate.assigning(revision: revision)
            records[key] = record
            if acknowledged[key] == revision {
                pending.remove(key)
            } else {
                pending.insert(key)
            }
            versioned.append(record)
        }
        return versioned
    }

    public func pendingChanges(
        using records: [FamilySyncRecord],
        now: Date
    ) -> [FamilySyncPendingOperation] {
        _ = now
        let byKey = Dictionary(
            uniqueKeysWithValues: records.map {
                (
                    FamilySyncChangeKey(
                        profileID: $0.profileID,
                        recordName: $0.recordName
                    ),
                    $0
                )
            }
        )
        return pending.compactMap { key in
            byKey[key].map(FamilySyncPendingOperation.save)
        }
    }

    public func recordAttempt(
        keys: Set<FamilySyncChangeKey>,
        at date: Date
    ) {
        _ = keys
        lastAttemptAt = date
    }

    public func recordTransportResult(
        acknowledged acknowledgements: Set<FamilySyncChangeAcknowledgement>,
        failures: [FamilySyncTransportFailure],
        at date: Date
    ) {
        for acknowledgement in acknowledgements {
            guard
                records[acknowledgement.key]?.logicalRevision
                    == acknowledgement.revision
            else { continue }
            acknowledged[acknowledgement.key] = acknowledgement.revision
            pending.remove(acknowledgement.key)
        }
        errorCategory = failures.first?.category
        condition = FamilySyncDurableStatus.condition(for: errorCategory)
        if pending.isEmpty, failures.isEmpty { lastSuccessAt = date }
    }

    public func recordAppliedRemote(
        records incoming: [FamilySyncRecord],
        deletions: [FamilySyncRemoteDeletion],
        at date: Date
    ) {
        _ = date
        let terminalProfileIDs = Set(
            records.values.compactMap { record in
                Self.isCanonicalProfileDeletion(record)
                    ? record.profileID
                    : nil
            }
        ).union(
            incoming.compactMap { record in
                Self.isCanonicalProfileDeletion(record)
                    ? record.profileID
                    : nil
            }
        )

        for record in incoming {
            guard
                !terminalProfileIDs.contains(record.profileID)
                    || Self.isCanonicalProfileDeletion(record)
            else { continue }
            let key = FamilySyncChangeKey(
                profileID: record.profileID,
                recordName: record.recordName
            )
            records[key] = record
            acknowledged[key] = record.logicalRevision
            pending.remove(key)
        }

        for profileID in terminalProfileIDs {
            let deletionKey = Self.profileDeletionKey(for: profileID)
            records = records.filter {
                $0.key.profileID != profileID || $0.key == deletionKey
            }
            acknowledged = acknowledged.filter {
                $0.key.profileID != profileID || $0.key == deletionKey
            }
            pending = pending.filter {
                $0.profileID != profileID || $0 == deletionKey
            }
        }

        for deletion in deletions {
            guard !terminalProfileIDs.contains(deletion.key.profileID) else {
                continue
            }
            records.removeValue(forKey: deletion.key)
            acknowledged.removeValue(forKey: deletion.key)
            pending.remove(deletion.key)
        }
    }

    public func invalidateAcknowledgementsForAccountChange(at date: Date) {
        let completedDeletionKeys = Set<FamilySyncChangeKey>(
            records.compactMap { element in
                let (key, record) = element
                guard record.kind == .profileDeletion, record.isDeleted,
                    acknowledged[key] == record.logicalRevision,
                    !pending.contains(key)
                else { return nil }
                return key
            }
        )
        pending.formUnion(Set(records.keys).subtracting(completedDeletionKeys))
        acknowledged = acknowledged.filter { completedDeletionKeys.contains($0.key) }
        lastSuccessAt = nil
        errorCategory = .account
        condition = .iCloudUnavailable
    }

    public func discardUnadoptedProfileState() {
        let retainedRecords = records.filter {
            Self.isCanonicalProfileDeletion($0.value)
        }
        acknowledged = acknowledged.filter { key, revision in
            retainedRecords[key]?.logicalRevision == revision
        }
        pending = pending.filter { retainedRecords[$0] != nil }
        records = retainedRecords
        guard pending.isEmpty else { return }
        lastAttemptAt = nil
        lastSuccessAt = nil
        errorCategory = nil
        condition = .idle
    }

    public func unadoptedProfileIDs() async throws -> Set<ProfileID> {
        var profileIDs = Set(
            records.compactMap { _, record in
                Self.isCanonicalProfileDeletion(record)
                    ? nil
                    : record.profileID
            }
        )
        profileIDs.formUnion(
            acknowledged.compactMap { key, revision in
                guard
                    let record = records[key],
                    Self.isCanonicalProfileDeletion(record),
                    record.logicalRevision == revision
                else { return key.profileID }
                return nil
            }
        )
        profileIDs.formUnion(
            pending.compactMap { key in
                guard
                    let record = records[key],
                    Self.isCanonicalProfileDeletion(record)
                else { return key.profileID }
                return nil
            }
        )
        return profileIDs
    }

    public func hasUnadoptedProfileState() -> Bool {
        let terminalRecordKeys = Set(
            records.compactMap { key, record in
                Self.isCanonicalProfileDeletion(record) ? key : nil
            }
        )
        let acknowledgedIsTerminal = acknowledged.allSatisfy { key, revision in
            guard let record = records[key] else { return false }
            return terminalRecordKeys.contains(key)
                && record.logicalRevision == revision
        }
        return records.keys.contains { !terminalRecordKeys.contains($0) }
            || !acknowledgedIsTerminal
            || pending.contains { !terminalRecordKeys.contains($0) }
    }

    public func recordParentVisibleCondition(
        _ condition: FamilySyncDurableCondition,
        errorCategory: FamilySyncPrivacySafeErrorCategory?,
        at date: Date
    ) {
        self.condition = condition
        self.errorCategory = errorCategory
        lastAttemptAt = date
    }

    public func durableStatus() -> FamilySyncDurableStatus {
        FamilySyncDurableStatus(
            pendingCount: pending.count,
            lastAttemptAt: lastAttemptAt,
            lastSuccessAt: lastSuccessAt,
            errorCategory: errorCategory,
            condition: condition
        )
    }

    public func profileDeletionDeliveryEvidence(
        for profileID: ProfileID
    ) throws -> ProfileDeletionDeliveryEvidence {
        let key = Self.profileDeletionKey(for: profileID)
        guard let record = records[key], record.kind == .profileDeletion,
            record.isDeleted
        else {
            return .notQueued
        }
        let acknowledgement = FamilySyncChangeAcknowledgement(
            key: key,
            revision: record.logicalRevision,
            operation: .save
        )
        if pending.contains(key) {
            return .pending(
                ProfileDeletionPendingDeliveryEvidence(
                    acknowledgement: acknowledgement,
                    firstQueuedAt: record.updatedAt,
                    lastQueuedAt: record.updatedAt,
                    retryCount: 0,
                    nextRetryAt: nil,
                    lastAttemptAt: lastAttemptAt,
                    errorCategory: errorCategory
                )
            )
        }
        if acknowledged[key] == record.logicalRevision {
            return .acknowledged(acknowledgement)
        }
        return .notQueued
    }

    public func requeueProfileDeletion(
        for profileID: ProfileID,
        errorCategory: FamilySyncPrivacySafeErrorCategory,
        at date: Date
    ) throws {
        let key = Self.profileDeletionKey(for: profileID)
        guard let record = records[key], record.kind == .profileDeletion,
            record.isDeleted
        else {
            throw FamilySyncJournalError.inconsistentProfileDeletionEvidence
        }
        acknowledged.removeValue(forKey: key)
        pending.insert(key)
        lastAttemptAt = date
        self.errorCategory = errorCategory
        condition = .needsAttention
    }

    private static func profileDeletionKey(
        for profileID: ProfileID
    ) -> FamilySyncChangeKey {
        FamilySyncChangeKey(
            profileID: profileID,
            recordName: "profile-\(profileID)"
        )
    }

    private static func isCanonicalProfileDeletion(
        _ record: FamilySyncRecord
    ) -> Bool {
        record.kind == .profileDeletion
            && record.isDeleted
            && FamilySyncChangeKey(
                profileID: record.profileID,
                recordName: record.recordName
            ) == profileDeletionKey(for: record.profileID)
    }
}

public actor LocalJSONFamilySyncJournalRepository: FamilySyncJournalRepository {
    public nonisolated let snapshotURL: URL

    private let fileManager: FileManager
    private var snapshot: FamilySyncJournalSnapshot?

    public init(snapshotURL: URL, fileManager: FileManager = .default) {
        self.snapshotURL = snapshotURL
        self.fileManager = fileManager
    }

    public func reconcileLocalRecords(
        _ records: [FamilySyncRecord],
        deviceID: String,
        now: Date
    ) throws -> [FamilySyncRecord] {
        let current = try loadedSnapshot()
        var local = try dictionary(current.localManifest, duplicate: .manifest)
        let acknowledged = try dictionary(
            current.acknowledgedManifest,
            duplicate: .manifest
        )
        var outbox = try dictionary(current.outbox, duplicate: .outbox)
        var versioned: [FamilySyncRecord] = []
        let rawKeys = Set(
            records.map {
                FamilySyncChangeKey(profileID: $0.profileID, recordName: $0.recordName)
            }
        )

        for record in records {
            try record.validateCompatibility()
            let key = FamilySyncChangeKey(
                profileID: record.profileID,
                recordName: record.recordName
            )
            let previous = local[key]
            let revision: FamilySyncLogicalRevision
            if let previous, previous.hasSameContent(as: record) {
                revision = previous.revision
            } else {
                revision = .next(
                    after: [previous?.revision, acknowledged[key]?.revision].compactMap { $0 },
                    deviceID: deviceID
                )
            }
            let candidate = record.assigning(revision: revision)
            let manifest = FamilySyncManifestEntry(record: candidate)
            local[key] = manifest
            versioned.append(candidate)
            if acknowledged[key]?.hasSameServerValue(as: manifest) != true {
                outbox[key] = queuedEntry(
                    key: key,
                    operation: .save,
                    revision: revision,
                    existing: outbox[key],
                    now: now
                )
            } else {
                outbox.removeValue(forKey: key)
            }
        }

        for key in Set(local.keys).subtracting(rawKeys) {
            guard let previous = local[key], !previous.isDeleted else { continue }
            let revision = FamilySyncLogicalRevision.next(
                after: [previous.revision, acknowledged[key]?.revision].compactMap { $0 },
                deviceID: deviceID
            )
            local[key] = FamilySyncManifestEntry(
                key: key,
                kind: previous.kind,
                schemaVersion: FamilySyncRecord.currentSchemaVersion,
                minimumReadableVersion: FamilySyncRecord.minimumReadableSchemaVersion,
                revision: revision,
                payloadChecksum: "",
                payloadSize: 0,
                isDeleted: true
            )
            outbox[key] = queuedEntry(
                key: key,
                operation: .delete,
                revision: revision,
                existing: outbox[key],
                now: now
            )
        }

        try persist(
            snapshot(
                local: local,
                acknowledged: acknowledged,
                outbox: outbox,
                previousStatus: current.status
            )
        )
        return versioned.sorted { lhs, rhs in
            if lhs.profileID != rhs.profileID {
                return lhs.profileID.description < rhs.profileID.description
            }
            return lhs.recordName < rhs.recordName
        }
    }

    public func pendingChanges(
        using records: [FamilySyncRecord],
        now: Date
    ) throws -> [FamilySyncPendingOperation] {
        let current = try loadedSnapshot()
        let recordByKey = Dictionary(
            uniqueKeysWithValues: records.map {
                (
                    FamilySyncChangeKey(
                        profileID: $0.profileID,
                        recordName: $0.recordName
                    ),
                    $0
                )
            }
        )
        return current.outbox
            .filter { $0.nextRetryAt.map { $0 <= now } ?? true }
            .sorted(by: Self.outboxOrder)
            .compactMap { entry in
                switch entry.operation {
                case .save:
                    guard let record = recordByKey[entry.key],
                        record.logicalRevision == entry.revision
                    else { return nil }
                    return .save(record)
                case .delete:
                    return .delete(key: entry.key, revision: entry.revision)
                }
            }
    }

    public func recordAttempt(
        keys: Set<FamilySyncChangeKey>,
        at date: Date
    ) throws {
        let current = try loadedSnapshot()
        var outbox = try dictionary(current.outbox, duplicate: .outbox)
        for key in keys {
            guard let entry = outbox[key] else { continue }
            outbox[key] = FamilySyncOutboxEntry(
                key: entry.key,
                operation: entry.operation,
                revision: entry.revision,
                firstQueuedAt: entry.firstQueuedAt,
                lastQueuedAt: entry.lastQueuedAt,
                retryCount: entry.retryCount,
                nextRetryAt: entry.nextRetryAt,
                lastAttemptAt: date,
                errorCategory: entry.errorCategory
            )
        }
        try persist(
            snapshot(
                local: try dictionary(current.localManifest, duplicate: .manifest),
                acknowledged: try dictionary(
                    current.acknowledgedManifest,
                    duplicate: .manifest
                ),
                outbox: outbox,
                previousStatus: FamilySyncDurableStatus(
                    pendingCount: outbox.count,
                    lastAttemptAt: date,
                    lastSuccessAt: current.status.lastSuccessAt,
                    errorCategory: current.status.errorCategory,
                    condition: current.status.condition
                )
            )
        )
    }

    public func recordTransportResult(
        acknowledged acknowledgements: Set<FamilySyncChangeAcknowledgement>,
        failures: [FamilySyncTransportFailure],
        at date: Date
    ) throws {
        let current = try loadedSnapshot()
        let local = try dictionary(current.localManifest, duplicate: .manifest)
        var acknowledged = try dictionary(
            current.acknowledgedManifest,
            duplicate: .manifest
        )
        var outbox = try dictionary(current.outbox, duplicate: .outbox)

        for acknowledgement in acknowledgements {
            let key = acknowledgement.key
            guard let entry = outbox[key],
                entry.revision == acknowledgement.revision,
                entry.operation.operationKind == acknowledgement.operation
            else { continue }
            if let manifest = local[key], manifest.revision == acknowledgement.revision {
                acknowledged[key] = manifest
            }
            outbox.removeValue(forKey: key)
        }

        for failure in failures {
            let targets: [FamilySyncChangeKey]
            if let key = failure.key {
                targets = [key]
            } else {
                targets = Array(outbox.keys)
            }
            for key in targets {
                guard let entry = outbox[key] else { continue }
                let retryCount = entry.retryCount + 1
                let delay = max(
                    failure.retryAfter ?? 0,
                    Self.retryDelay(for: key, retryCount: retryCount)
                )
                outbox[key] = FamilySyncOutboxEntry(
                    key: entry.key,
                    operation: entry.operation,
                    revision: entry.revision,
                    firstQueuedAt: entry.firstQueuedAt,
                    lastQueuedAt: entry.lastQueuedAt,
                    retryCount: retryCount,
                    nextRetryAt: date.addingTimeInterval(delay),
                    lastAttemptAt: date,
                    errorCategory: failure.category
                )
            }
        }

        let errorCategory = failures.first?.category
        let previousStatus = FamilySyncDurableStatus(
            pendingCount: outbox.count,
            lastAttemptAt: date,
            lastSuccessAt: outbox.isEmpty && failures.isEmpty
                ? date
                : current.status.lastSuccessAt,
            errorCategory: errorCategory,
            condition: FamilySyncDurableStatus.condition(for: errorCategory)
        )
        try persist(
            snapshot(
                local: local,
                acknowledged: acknowledged,
                outbox: outbox,
                previousStatus: previousStatus
            )
        )
    }

    public func recordAppliedRemote(
        records: [FamilySyncRecord],
        deletions: [FamilySyncRemoteDeletion],
        at date: Date
    ) throws {
        let current = try loadedSnapshot()
        var local = try dictionary(current.localManifest, duplicate: .manifest)
        var acknowledged = try dictionary(
            current.acknowledgedManifest,
            duplicate: .manifest
        )
        var outbox = try dictionary(current.outbox, duplicate: .outbox)

        let terminalProfileIDs = Set(
            local.values.compactMap { manifest in
                Self.isCanonicalProfileDeletion(manifest)
                    ? manifest.key.profileID
                    : nil
            }
        ).union(
            records.compactMap { record in
                Self.isCanonicalProfileDeletion(record)
                    ? record.profileID
                    : nil
            }
        )

        for record in records {
            let manifest = FamilySyncManifestEntry(record: record)
            let key = manifest.key
            guard
                !terminalProfileIDs.contains(key.profileID)
                    || Self.isCanonicalProfileDeletion(manifest)
            else { continue }
            acknowledged[key] = manifest
            if Self.isCanonicalProfileDeletion(manifest)
                || (local[key].map { $0.revision <= manifest.revision } ?? true)
            {
                local[key] = manifest
                outbox.removeValue(forKey: key)
            }
        }

        // A versioned Profile tombstone is a terminal barrier. Once accepted,
        // no child manifest or pending operation for that Profile is useful,
        // and retaining one can both leak erased identifiers and create an
        // impossible retry loop against a deleted CloudKit hierarchy.
        for profileID in terminalProfileIDs {
            let deletionKey = Self.profileDeletionKey(for: profileID)
            local = local.filter {
                $0.key.profileID != profileID || $0.key == deletionKey
            }
            acknowledged = acknowledged.filter {
                $0.key.profileID != profileID || $0.key == deletionKey
            }
            outbox = outbox.filter {
                $0.key.profileID != profileID || $0.key == deletionKey
            }
        }

        for deletion in deletions {
            guard !terminalProfileIDs.contains(deletion.key.profileID) else {
                continue
            }
            acknowledged.removeValue(forKey: deletion.key)
            guard let existing = local[deletion.key] else { continue }
            // A CKSyncEngine fetch deletion has no logical revision. It can be
            // stale, so it never wins over durable local state. Semantic
            // deletions arrive as versioned tombstone envelopes; an unversioned
            // physical deletion merely causes the local value to be re-sent.
            if !existing.isDeleted {
                outbox[deletion.key] = queuedEntry(
                    key: deletion.key,
                    operation: .save,
                    revision: existing.revision,
                    existing: outbox[deletion.key],
                    now: date
                )
            }
        }

        try persist(
            snapshot(
                local: local,
                acknowledged: acknowledged,
                outbox: outbox,
                previousStatus: FamilySyncDurableStatus(
                    pendingCount: outbox.count,
                    lastAttemptAt: current.status.lastAttemptAt,
                    lastSuccessAt: outbox.isEmpty ? date : current.status.lastSuccessAt,
                    errorCategory: current.status.errorCategory,
                    condition: current.status.condition
                )
            )
        )
    }

    public func invalidateAcknowledgementsForAccountChange(at date: Date) throws {
        let current = try loadedSnapshot()
        let local = try dictionary(current.localManifest, duplicate: .manifest)
        let currentAcknowledged = try dictionary(
            current.acknowledgedManifest,
            duplicate: .manifest
        )
        var outbox = try dictionary(current.outbox, duplicate: .outbox)
        var retainedAcknowledgements: [FamilySyncChangeKey: FamilySyncManifestEntry] = [:]
        for manifest in local.values {
            let isCompletedProfileDeletion =
                manifest.kind == .profileDeletion
                && manifest.isDeleted
                && outbox[manifest.key] == nil
                && currentAcknowledged[manifest.key]?.hasSameServerValue(as: manifest)
                    == true
            if isCompletedProfileDeletion {
                retainedAcknowledgements[manifest.key] = currentAcknowledged[manifest.key]
                continue
            }
            let queued = queuedEntry(
                key: manifest.key,
                operation: manifest.kind == .profileDeletion
                    ? .save
                    : (manifest.isDeleted ? .delete : .save),
                revision: manifest.revision,
                existing: outbox[manifest.key],
                now: date
            )
            outbox[manifest.key] = FamilySyncOutboxEntry(
                key: queued.key,
                operation: queued.operation,
                revision: queued.revision,
                firstQueuedAt: queued.firstQueuedAt,
                lastQueuedAt: queued.lastQueuedAt,
                retryCount: queued.retryCount,
                nextRetryAt: queued.nextRetryAt,
                lastAttemptAt: date,
                errorCategory: .account
            )
        }
        try persist(
            snapshot(
                local: local,
                acknowledged: retainedAcknowledgements,
                outbox: outbox,
                previousStatus: FamilySyncDurableStatus(
                    pendingCount: outbox.count,
                    lastAttemptAt: current.status.lastAttemptAt,
                    lastSuccessAt: nil,
                    errorCategory: .account,
                    condition: .iCloudUnavailable
                )
            )
        )
    }

    public func discardUnadoptedProfileState() throws {
        let current = try loadedSnapshot()
        let local = try dictionary(current.localManifest, duplicate: .manifest)
        let acknowledged = try dictionary(
            current.acknowledgedManifest,
            duplicate: .manifest
        )
        let outbox = try dictionary(current.outbox, duplicate: .outbox)
        let retainedLocal = local.filter {
            Self.isCanonicalProfileDeletion($0.value)
        }
        let retainedAcknowledged = acknowledged.filter { key, manifest in
            guard let localManifest = retainedLocal[key] else { return false }
            return Self.isCanonicalProfileDeletion(manifest)
                && manifest.hasSameServerValue(as: localManifest)
        }
        let retainedOutbox = outbox.filter { key, entry in
            guard let manifest = retainedLocal[key] else { return false }
            return entry.operation == .save
                && entry.revision == manifest.revision
        }
        let retainedStatus =
            retainedOutbox.isEmpty ? FamilySyncDurableStatus.empty : current.status
        try persist(
            snapshot(
                local: retainedLocal,
                acknowledged: retainedAcknowledged,
                outbox: retainedOutbox,
                previousStatus: retainedStatus
            )
        )
    }

    public func unadoptedProfileIDs() async throws -> Set<ProfileID> {
        let current = try loadedSnapshot()
        let local = try dictionary(current.localManifest, duplicate: .manifest)
        let acknowledged = try dictionary(
            current.acknowledgedManifest,
            duplicate: .manifest
        )
        let outbox = try dictionary(current.outbox, duplicate: .outbox)
        var profileIDs = Set(
            local.values.compactMap { manifest in
                Self.isCanonicalProfileDeletion(manifest)
                    ? nil
                    : manifest.key.profileID
            }
        )
        profileIDs.formUnion(
            acknowledged.compactMap { key, manifest in
                guard
                    Self.isCanonicalProfileDeletion(manifest),
                    let localManifest = local[key],
                    Self.isCanonicalProfileDeletion(localManifest),
                    manifest.hasSameServerValue(as: localManifest)
                else { return manifest.key.profileID }
                return nil
            }
        )
        profileIDs.formUnion(
            outbox.compactMap { key, entry in
                guard let manifest = local[key] else {
                    return key.profileID
                }
                let isTerminal =
                    Self.isCanonicalProfileDeletion(manifest)
                    && entry.operation == .save
                    && entry.revision == manifest.revision
                return isTerminal ? nil : key.profileID
            }
        )
        return profileIDs
    }

    public func hasUnadoptedProfileState() throws -> Bool {
        let current = try loadedSnapshot()
        let local = try dictionary(current.localManifest, duplicate: .manifest)
        let acknowledged = try dictionary(
            current.acknowledgedManifest,
            duplicate: .manifest
        )
        let outbox = try dictionary(current.outbox, duplicate: .outbox)
        let hasLocalState = local.values.contains {
            !Self.isCanonicalProfileDeletion($0)
        }
        let hasAcknowledgedState = acknowledged.contains { key, manifest in
            guard
                Self.isCanonicalProfileDeletion(manifest),
                let localManifest = local[key],
                Self.isCanonicalProfileDeletion(localManifest)
            else { return true }
            return !manifest.hasSameServerValue(as: localManifest)
        }
        let hasOutboxState = outbox.contains { key, entry in
            guard let manifest = local[key] else { return true }
            return !Self.isCanonicalProfileDeletion(manifest)
                || entry.operation != .save
                || entry.revision != manifest.revision
        }
        return hasLocalState || hasAcknowledgedState || hasOutboxState
    }

    public func recordParentVisibleCondition(
        _ condition: FamilySyncDurableCondition,
        errorCategory: FamilySyncPrivacySafeErrorCategory?,
        at date: Date
    ) throws {
        let current = try loadedSnapshot()
        try persist(
            snapshot(
                local: try dictionary(current.localManifest, duplicate: .manifest),
                acknowledged: try dictionary(
                    current.acknowledgedManifest,
                    duplicate: .manifest
                ),
                outbox: try dictionary(current.outbox, duplicate: .outbox),
                previousStatus: FamilySyncDurableStatus(
                    pendingCount: current.outbox.count,
                    lastAttemptAt: date,
                    lastSuccessAt: current.status.lastSuccessAt,
                    errorCategory: errorCategory,
                    condition: condition
                )
            )
        )
    }

    public func durableStatus() throws -> FamilySyncDurableStatus {
        try loadedSnapshot().status
    }

    public func profileDeletionDeliveryEvidence(
        for profileID: ProfileID
    ) throws -> ProfileDeletionDeliveryEvidence {
        let current = try loadedSnapshot()
        let local = try dictionary(current.localManifest, duplicate: .manifest)
        let acknowledged = try dictionary(
            current.acknowledgedManifest,
            duplicate: .manifest
        )
        let outbox = try dictionary(current.outbox, duplicate: .outbox)
        let key = Self.profileDeletionKey(for: profileID)
        guard let manifest = local[key], manifest.kind == .profileDeletion,
            manifest.isDeleted
        else {
            return .notQueued
        }
        let acknowledgement = FamilySyncChangeAcknowledgement(
            key: key,
            revision: manifest.revision,
            operation: .save
        )
        if let entry = outbox[key] {
            guard entry.operation == .save, entry.revision == manifest.revision else {
                throw FamilySyncJournalError.inconsistentProfileDeletionEvidence
            }
            return .pending(
                ProfileDeletionPendingDeliveryEvidence(
                    acknowledgement: acknowledgement,
                    firstQueuedAt: entry.firstQueuedAt,
                    lastQueuedAt: entry.lastQueuedAt,
                    retryCount: entry.retryCount,
                    nextRetryAt: entry.nextRetryAt,
                    lastAttemptAt: entry.lastAttemptAt,
                    errorCategory: entry.errorCategory
                )
            )
        }
        if acknowledged[key]?.hasSameServerValue(as: manifest) == true {
            return .acknowledged(acknowledgement)
        }
        return .notQueued
    }

    public func requeueProfileDeletion(
        for profileID: ProfileID,
        errorCategory: FamilySyncPrivacySafeErrorCategory,
        at date: Date
    ) throws {
        let current = try loadedSnapshot()
        let local = try dictionary(current.localManifest, duplicate: .manifest)
        var acknowledged = try dictionary(
            current.acknowledgedManifest,
            duplicate: .manifest
        )
        var outbox = try dictionary(current.outbox, duplicate: .outbox)
        let key = Self.profileDeletionKey(for: profileID)
        guard let manifest = local[key], manifest.kind == .profileDeletion,
            manifest.isDeleted
        else {
            throw FamilySyncJournalError.inconsistentProfileDeletionEvidence
        }
        let queued = queuedEntry(
            key: key,
            operation: .save,
            revision: manifest.revision,
            existing: outbox[key],
            now: date
        )
        outbox[key] = FamilySyncOutboxEntry(
            key: queued.key,
            operation: queued.operation,
            revision: queued.revision,
            firstQueuedAt: queued.firstQueuedAt,
            lastQueuedAt: queued.lastQueuedAt,
            retryCount: queued.retryCount,
            nextRetryAt: nil,
            lastAttemptAt: date,
            errorCategory: errorCategory
        )
        acknowledged.removeValue(forKey: key)
        try persist(
            snapshot(
                local: local,
                acknowledged: acknowledged,
                outbox: outbox,
                previousStatus: FamilySyncDurableStatus(
                    pendingCount: outbox.count,
                    lastAttemptAt: date,
                    lastSuccessAt: current.status.lastSuccessAt,
                    errorCategory: errorCategory,
                    condition: .needsAttention
                )
            )
        )
    }

    public func reloadFromDisk() {
        snapshot = nil
    }

    private func queuedEntry(
        key: FamilySyncChangeKey,
        operation: FamilySyncOutboxEntry.Operation,
        revision: FamilySyncLogicalRevision,
        existing: FamilySyncOutboxEntry?,
        now: Date
    ) -> FamilySyncOutboxEntry {
        if let existing, existing.operation == operation, existing.revision == revision {
            return existing
        }
        return FamilySyncOutboxEntry(
            key: key,
            operation: operation,
            revision: revision,
            firstQueuedAt: existing?.firstQueuedAt ?? now,
            lastQueuedAt: now
        )
    }

    private func loadedSnapshot() throws -> FamilySyncJournalSnapshot {
        if let snapshot { return snapshot }
        let data: Data?
        do {
            data = try snapshotFile.readIfPresent()
        } catch {
            throw FamilySyncJournalError.readFailed(
                snapshotURL: snapshotURL,
                details: String(describing: error)
            )
        }
        guard let data else {
            let empty = FamilySyncJournalSnapshot()
            snapshot = empty
            return empty
        }
        let decoded: FamilySyncJournalSnapshot
        do {
            decoded = try InspectableSnapshotJSONCodec.makeDecoder().decode(
                FamilySyncJournalSnapshot.self,
                from: data
            )
        } catch {
            throw FamilySyncJournalError.invalidJSON(
                snapshotURL: snapshotURL,
                details: String(describing: error)
            )
        }
        guard decoded.schemaVersion == FamilySyncJournalSnapshot.currentSchemaVersion else {
            throw FamilySyncJournalError.unsupportedSchemaVersion(
                snapshotURL: snapshotURL,
                found: decoded.schemaVersion,
                supported: FamilySyncJournalSnapshot.currentSchemaVersion
            )
        }
        _ = try dictionary(decoded.localManifest, duplicate: .manifest)
        _ = try dictionary(decoded.acknowledgedManifest, duplicate: .manifest)
        _ = try dictionary(decoded.outbox, duplicate: .outbox)
        snapshot = decoded
        return decoded
    }

    private func persist(_ candidate: FamilySyncJournalSnapshot) throws {
        do {
            try snapshotFile.write(
                InspectableSnapshotJSONCodec.makeEncoder().encode(candidate)
            )
        } catch let error as FamilySyncJournalError {
            throw error
        } catch {
            throw FamilySyncJournalError.writeFailed(
                snapshotURL: snapshotURL,
                details: String(describing: error)
            )
        }
        snapshot = candidate
    }

    private enum DuplicateKind {
        case manifest
        case outbox
    }

    private func dictionary(
        _ entries: [FamilySyncManifestEntry],
        duplicate: DuplicateKind
    ) throws -> [FamilySyncChangeKey: FamilySyncManifestEntry] {
        var result: [FamilySyncChangeKey: FamilySyncManifestEntry] = [:]
        for entry in entries {
            if result.updateValue(entry, forKey: entry.key) != nil {
                _ = duplicate
                throw FamilySyncJournalError.duplicateManifestKey(entry.key)
            }
        }
        return result
    }

    private func dictionary(
        _ entries: [FamilySyncOutboxEntry],
        duplicate: DuplicateKind
    ) throws -> [FamilySyncChangeKey: FamilySyncOutboxEntry] {
        var result: [FamilySyncChangeKey: FamilySyncOutboxEntry] = [:]
        for entry in entries {
            if result.updateValue(entry, forKey: entry.key) != nil {
                _ = duplicate
                throw FamilySyncJournalError.duplicateOutboxKey(entry.key)
            }
        }
        return result
    }

    private func snapshot(
        local: [FamilySyncChangeKey: FamilySyncManifestEntry],
        acknowledged: [FamilySyncChangeKey: FamilySyncManifestEntry],
        outbox: [FamilySyncChangeKey: FamilySyncOutboxEntry],
        previousStatus: FamilySyncDurableStatus
    ) -> FamilySyncJournalSnapshot {
        let retryCount = outbox.values.map(\.retryCount).max() ?? 0
        let nextRetryAt = outbox.values.compactMap(\.nextRetryAt).min()
        return FamilySyncJournalSnapshot(
            localManifest: local.values.sorted(by: Self.manifestOrder),
            acknowledgedManifest: acknowledged.values.sorted(by: Self.manifestOrder),
            outbox: outbox.values.sorted(by: Self.outboxOrder),
            status: FamilySyncDurableStatus(
                pendingCount: outbox.count,
                lastAttemptAt: previousStatus.lastAttemptAt,
                lastSuccessAt: previousStatus.lastSuccessAt,
                errorCategory: previousStatus.errorCategory,
                condition: previousStatus.condition,
                retryCount: retryCount,
                nextRetryAt: nextRetryAt
            )
        )
    }

    private static func manifestOrder(
        _ lhs: FamilySyncManifestEntry,
        _ rhs: FamilySyncManifestEntry
    ) -> Bool {
        keyOrder(lhs.key, rhs.key)
    }

    private static func outboxOrder(
        _ lhs: FamilySyncOutboxEntry,
        _ rhs: FamilySyncOutboxEntry
    ) -> Bool {
        keyOrder(lhs.key, rhs.key)
    }

    private static func keyOrder(
        _ lhs: FamilySyncChangeKey,
        _ rhs: FamilySyncChangeKey
    ) -> Bool {
        if lhs.profileID != rhs.profileID {
            return lhs.profileID.description < rhs.profileID.description
        }
        return lhs.recordName < rhs.recordName
    }

    private static func retryDelay(
        for key: FamilySyncChangeKey,
        retryCount: Int
    ) -> TimeInterval {
        let exponent = min(8, max(0, retryCount - 1))
        let base = min(3_600.0, 5.0 * pow(2.0, Double(exponent)))
        let scalar = key.recordName.unicodeScalars.reduce(UInt64(1_469_598_103_934_665_603)) {
            ($0 ^ UInt64($1.value)) &* 1_099_511_628_211
        }
        let jitter = 0.8 + (Double(scalar % 401) / 1_000.0)
        return min(3_600.0, base * jitter)
    }

    private static func profileDeletionKey(
        for profileID: ProfileID
    ) -> FamilySyncChangeKey {
        FamilySyncChangeKey(
            profileID: profileID,
            recordName: "profile-\(profileID)"
        )
    }

    private static func isCanonicalProfileDeletion(
        _ manifest: FamilySyncManifestEntry
    ) -> Bool {
        manifest.kind == .profileDeletion
            && manifest.isDeleted
            && manifest.key == profileDeletionKey(for: manifest.key.profileID)
    }

    private static func isCanonicalProfileDeletion(
        _ record: FamilySyncRecord
    ) -> Bool {
        isCanonicalProfileDeletion(FamilySyncManifestEntry(record: record))
    }

    private var snapshotFile: AtomicSnapshotFile {
        AtomicSnapshotFile(snapshotURL: snapshotURL, fileManager: fileManager)
    }
}
