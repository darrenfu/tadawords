import Foundation
import TadaWordsDomain

/// Exact remote bytes kept only while a Profile-scoped multi-repository apply
/// is unfinished. Bootstrap can deterministically resume this transaction
/// before exposing the Profile to SwiftUI.
public struct FamilySyncPendingApplyTransaction: Codable, Equatable, Sendable {
    public let id: UUID
    public let profileID: ProfileID
    public let batchID: String
    public let records: [FamilySyncRecord]
    public let startedAt: Date

    public init(
        id: UUID = UUID(),
        profileID: ProfileID,
        records: [FamilySyncRecord],
        startedAt: Date
    ) throws {
        guard !records.isEmpty,
            records.allSatisfy({ $0.profileID == profileID })
        else {
            throw FamilySyncApplyTransactionError.profileMismatch(profileID)
        }
        self.id = id
        self.profileID = profileID
        batchID = Self.batchID(for: records)
        self.records = records.sorted(by: Self.recordOrder)
        self.startedAt = startedAt
    }

    static func batchID(for records: [FamilySyncRecord]) -> String {
        var bytes = Data()
        for record in records.sorted(by: recordOrder) {
            bytes.append(contentsOf: record.profileID.description.utf8)
            bytes.append(0)
            bytes.append(contentsOf: record.recordName.utf8)
            bytes.append(0)
            bytes.append(contentsOf: record.kind.rawValue.utf8)
            bytes.append(0)
            bytes.append(contentsOf: record.payloadChecksum.utf8)
            bytes.append(0)
            bytes.append(contentsOf: String(record.logicalRevision.counter).utf8)
            bytes.append(0)
            bytes.append(contentsOf: record.logicalRevision.deviceID.utf8)
            bytes.append(record.isDeleted ? 1 : 0)
        }
        return FamilySyncRecord.checksum(for: bytes)
    }

    private static func recordOrder(
        _ lhs: FamilySyncRecord,
        _ rhs: FamilySyncRecord
    ) -> Bool {
        if lhs.recordName != rhs.recordName {
            return lhs.recordName < rhs.recordName
        }
        if lhs.kind != rhs.kind {
            return lhs.kind.rawValue < rhs.kind.rawValue
        }
        return lhs.payloadChecksum < rhs.payloadChecksum
    }
}

/// Privacy-minimal durable evidence exposed after the payload transaction has
/// committed. It deliberately contains no child name, word, photo, or answer.
public struct FamilySyncCommittedApplyReceipt: Codable, Equatable, Sendable {
    public let transactionID: UUID
    public let profileID: ProfileID
    public let batchID: String
    public let recordCount: Int
    public let affectedKinds: [FamilySyncRecordKind]
    public let deletedProfile: Bool
    public let committedAt: Date

    init(
        transaction: FamilySyncPendingApplyTransaction,
        committedAt: Date
    ) {
        transactionID = transaction.id
        profileID = transaction.profileID
        batchID = transaction.batchID
        recordCount = transaction.records.count
        affectedKinds = Array(Set(transaction.records.map(\.kind))).sorted {
            $0.rawValue < $1.rawValue
        }
        deletedProfile = transaction.records.contains {
            $0.kind == .profileDeletion && $0.isDeleted
        }
        self.committedAt = committedAt
    }
}

public enum FamilySyncApplyTransactionStart: Equatable, Sendable {
    case pending(FamilySyncPendingApplyTransaction)
    case alreadyCommitted(FamilySyncCommittedApplyReceipt)
}

public protocol FamilySyncApplyTransactionRepository: Sendable {
    func begin(
        profileID: ProfileID,
        records: [FamilySyncRecord],
        at date: Date
    ) async throws -> FamilySyncApplyTransactionStart

    func pendingTransactions() async throws
        -> [FamilySyncPendingApplyTransaction]

    func markCommitted(
        transactionID: UUID,
        at date: Date
    ) async throws -> FamilySyncCommittedApplyReceipt

    func lastCommittedReceipt(
        for profileID: ProfileID
    ) async throws -> FamilySyncCommittedApplyReceipt?

    /// Privacy-safe token for deciding whether a background fetch committed
    /// any new repository data. It changes only after a receipt is durable.
    func committedReceiptToken() async throws -> String

    func committedReceipts() async -> AsyncStream<FamilySyncCommittedApplyReceipt>
}

public struct FamilySyncApplyTransactionSnapshot: Codable, Equatable, Sendable {
    public static let currentSchemaVersion = 1

    public let schemaVersion: Int
    public let pending: [FamilySyncPendingApplyTransaction]
    public let lastCommitted: [FamilySyncCommittedApplyReceipt]

    public init(
        schemaVersion: Int = Self.currentSchemaVersion,
        pending: [FamilySyncPendingApplyTransaction] = [],
        lastCommitted: [FamilySyncCommittedApplyReceipt] = []
    ) {
        self.schemaVersion = schemaVersion
        self.pending = pending
        self.lastCommitted = lastCommitted
    }
}

public enum FamilySyncApplyTransactionError: Error, Equatable, Sendable {
    case profileMismatch(ProfileID)
    case emptyBatch
    case pendingBatchConflict(ProfileID)
    case transactionNotFound(UUID)
    case duplicatePendingProfile(ProfileID)
    case duplicateCommittedProfile(ProfileID)
    case corruptSnapshot
    case unsupportedSchemaVersion(Int)
    case readFailed
    case writeFailed
}

public actor LocalJSONFamilySyncApplyTransactionRepository:
    FamilySyncApplyTransactionRepository
{
    public nonisolated let snapshotURL: URL

    private let fileManager: FileManager
    private var snapshot: FamilySyncApplyTransactionSnapshot?
    private var loadFailure: FamilySyncApplyTransactionError?
    private var receiptContinuations:
        [UUID: AsyncStream<FamilySyncCommittedApplyReceipt>.Continuation] = [:]

    public init(
        snapshotURL: URL,
        fileManager: FileManager = .default
    ) {
        self.snapshotURL = snapshotURL
        self.fileManager = fileManager
    }

    public func begin(
        profileID: ProfileID,
        records: [FamilySyncRecord],
        at date: Date
    ) async throws -> FamilySyncApplyTransactionStart {
        guard !records.isEmpty else {
            throw FamilySyncApplyTransactionError.emptyBatch
        }
        let transaction = try FamilySyncPendingApplyTransaction(
            profileID: profileID,
            records: records,
            startedAt: date
        )
        var current = try loadedSnapshot()

        if let committed = current.lastCommitted.first(where: {
            $0.profileID == profileID && $0.batchID == transaction.batchID
        }) {
            return .alreadyCommitted(committed)
        }
        if let pending = current.pending.first(where: {
            $0.profileID == profileID
        }) {
            guard pending.batchID == transaction.batchID else {
                throw FamilySyncApplyTransactionError.pendingBatchConflict(
                    profileID
                )
            }
            return .pending(pending)
        }

        current = FamilySyncApplyTransactionSnapshot(
            pending: (current.pending + [transaction]).sorted(
                by: Self.pendingOrder
            ),
            lastCommitted: current.lastCommitted
        )
        try persist(current)
        snapshot = current
        return .pending(transaction)
    }

    public func pendingTransactions() async throws
        -> [FamilySyncPendingApplyTransaction]
    {
        try loadedSnapshot().pending.sorted(by: Self.pendingOrder)
    }

    public func markCommitted(
        transactionID: UUID,
        at date: Date
    ) async throws -> FamilySyncCommittedApplyReceipt {
        var current = try loadedSnapshot()
        guard
            let index = current.pending.firstIndex(where: {
                $0.id == transactionID
            })
        else {
            if let receipt = current.lastCommitted.first(where: {
                $0.transactionID == transactionID
            }) {
                return receipt
            }
            throw FamilySyncApplyTransactionError.transactionNotFound(
                transactionID
            )
        }

        let transaction = current.pending[index]
        let receipt = FamilySyncCommittedApplyReceipt(
            transaction: transaction,
            committedAt: date
        )
        var pending = current.pending
        pending.remove(at: index)
        var committed = current.lastCommitted.filter {
            $0.profileID != transaction.profileID
        }
        committed.append(receipt)
        committed.sort(by: Self.receiptOrder)
        current = FamilySyncApplyTransactionSnapshot(
            pending: pending,
            lastCommitted: committed
        )
        try persist(current)
        snapshot = current
        for continuation in receiptContinuations.values {
            continuation.yield(receipt)
        }
        return receipt
    }

    public func lastCommittedReceipt(
        for profileID: ProfileID
    ) async throws -> FamilySyncCommittedApplyReceipt? {
        try loadedSnapshot().lastCommitted.first {
            $0.profileID == profileID
        }
    }

    public func committedReceiptToken() async throws -> String {
        let receipts = try loadedSnapshot().lastCommitted.sorted(
            by: Self.receiptOrder
        )
        let bytes: Data
        do {
            bytes = try InspectableSnapshotJSONCodec.makeEncoder().encode(
                receipts
            )
        } catch {
            throw FamilySyncApplyTransactionError.writeFailed
        }
        return FamilySyncRecord.checksum(for: bytes)
    }

    public func committedReceipts() async
        -> AsyncStream<FamilySyncCommittedApplyReceipt>
    {
        let id = UUID()
        let durableReceipts =
            (try? loadedSnapshot().lastCommitted.sorted(
                by: Self.receiptOrder
            )) ?? []
        return AsyncStream { continuation in
            receiptContinuations[id] = continuation
            for receipt in durableReceipts {
                continuation.yield(receipt)
            }
            continuation.onTermination = { [weak self] _ in
                Task { await self?.removeContinuation(id) }
            }
        }
    }

    public func reloadFromDisk() throws {
        snapshot = nil
        loadFailure = nil
        _ = try loadedSnapshot()
    }

    private func removeContinuation(_ id: UUID) {
        receiptContinuations.removeValue(forKey: id)
    }

    private func loadedSnapshot() throws -> FamilySyncApplyTransactionSnapshot {
        if let loadFailure { throw loadFailure }
        if let snapshot { return snapshot }
        do {
            guard let data = try snapshotFile.readIfPresent() else {
                let empty = FamilySyncApplyTransactionSnapshot()
                snapshot = empty
                return empty
            }
            let decoded: FamilySyncApplyTransactionSnapshot
            do {
                decoded = try InspectableSnapshotJSONCodec.makeDecoder().decode(
                    FamilySyncApplyTransactionSnapshot.self,
                    from: data
                )
            } catch {
                throw FamilySyncApplyTransactionError.corruptSnapshot
            }
            guard
                decoded.schemaVersion
                    == FamilySyncApplyTransactionSnapshot.currentSchemaVersion
            else {
                throw FamilySyncApplyTransactionError.unsupportedSchemaVersion(
                    decoded.schemaVersion
                )
            }
            try validate(decoded)
            snapshot = decoded
            return decoded
        } catch let error as FamilySyncApplyTransactionError {
            loadFailure = error
            throw error
        } catch {
            loadFailure = .readFailed
            throw FamilySyncApplyTransactionError.readFailed
        }
    }

    private func validate(
        _ snapshot: FamilySyncApplyTransactionSnapshot
    ) throws {
        var pendingProfiles: Set<ProfileID> = []
        for transaction in snapshot.pending {
            guard pendingProfiles.insert(transaction.profileID).inserted else {
                throw FamilySyncApplyTransactionError.duplicatePendingProfile(
                    transaction.profileID
                )
            }
            guard
                transaction.records.allSatisfy({
                    $0.profileID == transaction.profileID
                }),
                transaction.batchID
                    == FamilySyncPendingApplyTransaction.batchID(
                        for: transaction.records
                    )
            else {
                throw FamilySyncApplyTransactionError.corruptSnapshot
            }
        }
        var committedProfiles: Set<ProfileID> = []
        for receipt in snapshot.lastCommitted {
            guard committedProfiles.insert(receipt.profileID).inserted else {
                throw FamilySyncApplyTransactionError.duplicateCommittedProfile(
                    receipt.profileID
                )
            }
        }
    }

    private func persist(
        _ snapshot: FamilySyncApplyTransactionSnapshot
    ) throws {
        let data: Data
        do {
            data = try InspectableSnapshotJSONCodec.makeEncoder().encode(snapshot)
        } catch {
            throw FamilySyncApplyTransactionError.writeFailed
        }
        do {
            try snapshotFile.write(data)
        } catch {
            throw FamilySyncApplyTransactionError.writeFailed
        }
    }

    private var snapshotFile: AtomicSnapshotFile {
        AtomicSnapshotFile(
            snapshotURL: snapshotURL,
            fileManager: fileManager
        )
    }

    private static func pendingOrder(
        _ lhs: FamilySyncPendingApplyTransaction,
        _ rhs: FamilySyncPendingApplyTransaction
    ) -> Bool {
        lhs.profileID.description < rhs.profileID.description
    }

    private static func receiptOrder(
        _ lhs: FamilySyncCommittedApplyReceipt,
        _ rhs: FamilySyncCommittedApplyReceipt
    ) -> Bool {
        lhs.profileID.description < rhs.profileID.description
    }
}
