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

    func recordParentVisibleCondition(
        _ condition: FamilySyncDurableCondition,
        errorCategory: FamilySyncPrivacySafeErrorCategory?,
        at date: Date
    ) async throws

    func durableStatus() async throws -> FamilySyncDurableStatus
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
        for record in incoming {
            let key = FamilySyncChangeKey(
                profileID: record.profileID,
                recordName: record.recordName
            )
            records[key] = record
            acknowledged[key] = record.logicalRevision
            pending.remove(key)
        }
        for deletion in deletions {
            records.removeValue(forKey: deletion.key)
            acknowledged.removeValue(forKey: deletion.key)
            pending.remove(deletion.key)
        }
    }

    public func invalidateAcknowledgementsForAccountChange(at date: Date) {
        _ = date
        pending.formUnion(records.keys)
        acknowledged.removeAll()
        lastSuccessAt = nil
        errorCategory = .account
        condition = .iCloudUnavailable
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

        for record in records {
            let manifest = FamilySyncManifestEntry(record: record)
            let key = manifest.key
            acknowledged[key] = manifest
            if local[key].map({ $0.revision <= manifest.revision }) ?? true {
                local[key] = manifest
                outbox.removeValue(forKey: key)
            }
        }
        for deletion in deletions {
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
        var outbox = try dictionary(current.outbox, duplicate: .outbox)
        for manifest in local.values {
            outbox[manifest.key] = queuedEntry(
                key: manifest.key,
                operation: manifest.kind == .profileDeletion
                    ? .save
                    : (manifest.isDeleted ? .delete : .save),
                revision: manifest.revision,
                existing: outbox[manifest.key],
                now: date
            )
        }
        try persist(
            snapshot(
                local: local,
                acknowledged: [:],
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

    private var snapshotFile: AtomicSnapshotFile {
        AtomicSnapshotFile(snapshotURL: snapshotURL, fileManager: fileManager)
    }
}
