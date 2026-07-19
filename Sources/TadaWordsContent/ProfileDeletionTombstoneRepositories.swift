import Foundation
import TadaWordsDomain

/// Removes device-local handwriting choices that belong to a deleted profile.
/// The concrete UserDefaults-backed implementation lives in Features, while
/// profile lifecycle coordinators depend only on this narrow cleanup contract.
public protocol HandwritingPreferenceRemoving: Sendable {
    func remove(for profileID: ProfileID)
}

/// One-way bridge for settings written by builds that kept the selected pen
/// in UserDefaults. Production bootstrap consumes the value into synchronized
/// Profile interface settings, then removes the device-local residue.
public protocol LegacyHandwritingPreferenceMigrating:
    HandwritingPreferenceRemoving
{
    func consumeLegacyTool(for profileID: ProfileID) -> HandwritingTool?
}

public protocol ProfileDeletionTombstoneRepository: Sendable {
    func tombstones() async throws -> [ProfileDeletionTombstone]
    func pendingTombstones() async throws -> [ProfileDeletionTombstone]
    func tombstone(for profileID: ProfileID) async throws -> ProfileDeletionTombstone?
    func save(_ tombstone: ProfileDeletionTombstone) async throws
    func markCommitted(for profileID: ProfileID) async throws
    func delete(for profileID: ProfileID) async throws
}

public actor InMemoryProfileDeletionTombstoneRepository:
    ProfileDeletionTombstoneRepository
{
    private var values: [ProfileID: ProfileDeletionTombstone]
    private var pending: Set<ProfileID>

    public init(tombstones: [ProfileDeletionTombstone] = []) {
        values = Dictionary(uniqueKeysWithValues: tombstones.map { ($0.profileID, $0) })
        pending = []
    }

    public func tombstones() async throws -> [ProfileDeletionTombstone] {
        values.values.sorted { $0.profileID.description < $1.profileID.description }
    }

    public func pendingTombstones() async throws -> [ProfileDeletionTombstone] {
        values.values.filter { pending.contains($0.profileID) }
    }

    public func tombstone(
        for profileID: ProfileID
    ) async throws -> ProfileDeletionTombstone? {
        values[profileID]
    }

    public func save(_ tombstone: ProfileDeletionTombstone) async throws {
        guard
            values[tombstone.profileID]?.deletedAt ?? .distantPast
                < tombstone.deletedAt
        else { return }
        values[tombstone.profileID] = tombstone
        pending.insert(tombstone.profileID)
    }

    public func markCommitted(for profileID: ProfileID) async throws {
        pending.remove(profileID)
    }

    public func delete(for profileID: ProfileID) async throws {
        values.removeValue(forKey: profileID)
        pending.remove(profileID)
    }
}

public actor LocalJSONProfileDeletionTombstoneRepository:
    ProfileDeletionTombstoneRepository
{
    public nonisolated static let currentSchemaVersion = 1

    private struct Snapshot: Codable {
        struct Entry: Codable {
            let tombstone: ProfileDeletionTombstone
            let isCommitted: Bool
        }

        static let currentSchemaVersion =
            LocalJSONProfileDeletionTombstoneRepository.currentSchemaVersion
        let schemaVersion: Int
        let entries: [Entry]

        init(entries: [Entry]) {
            schemaVersion = Self.currentSchemaVersion
            self.entries = entries
        }
    }

    public nonisolated let snapshotURL: URL
    private let fileManager: FileManager
    private let mutationGate: ProfileScopedMutationGate?
    private var values: [ProfileID: Snapshot.Entry]?

    public init(
        snapshotURL: URL,
        fileManager: FileManager = .default,
        mutationGate: ProfileScopedMutationGate? = nil
    ) {
        self.snapshotURL = snapshotURL
        self.fileManager = fileManager
        self.mutationGate = mutationGate
    }

    public func tombstones() async throws -> [ProfileDeletionTombstone] {
        try loadedValues().values.map(\.tombstone).sorted {
            $0.profileID.description < $1.profileID.description
        }
    }

    public func pendingTombstones() async throws -> [ProfileDeletionTombstone] {
        try loadedValues().values
            .filter { !$0.isCommitted }
            .map(\.tombstone)
            .sorted { $0.profileID.description < $1.profileID.description }
    }

    public func tombstone(
        for profileID: ProfileID
    ) async throws -> ProfileDeletionTombstone? {
        try loadedValues()[profileID]?.tombstone
    }

    public func save(_ tombstone: ProfileDeletionTombstone) async throws {
        try await withMutationLease(for: tombstone.profileID) {
            var candidate = try loadedValues()
            guard
                candidate[tombstone.profileID]?.tombstone.deletedAt ?? .distantPast
                    < tombstone.deletedAt
            else { return }
            candidate[tombstone.profileID] = Snapshot.Entry(
                tombstone: tombstone,
                isCommitted: false
            )
            try persist(candidate)
            values = candidate
        }
    }

    public func markCommitted(for profileID: ProfileID) async throws {
        try await withMutationLease(for: profileID) {
            var candidate = try loadedValues()
            guard let entry = candidate[profileID], !entry.isCommitted else { return }
            candidate[profileID] = Snapshot.Entry(
                tombstone: entry.tombstone,
                isCommitted: true
            )
            try persist(candidate)
            values = candidate
        }
    }

    public func delete(for profileID: ProfileID) async throws {
        try await withMutationLease(for: profileID) {
            var candidate = try loadedValues()
            guard candidate.removeValue(forKey: profileID) != nil else { return }
            try persist(candidate)
            values = candidate
        }
    }

    private func withMutationLease(
        for profileID: ProfileID,
        _ operation: () throws -> Void
    ) async throws {
        guard let mutationGate,
            ProfileScopedMutationLeaseContext.profileID != profileID
        else {
            try operation()
            return
        }
        await mutationGate.acquire(profileID)
        do {
            try operation()
            await mutationGate.release(profileID)
        } catch {
            await mutationGate.release(profileID)
            throw error
        }
    }

    private func loadedValues() throws -> [ProfileID: Snapshot.Entry] {
        if let values { return values }
        guard let data = try snapshotFile.readIfPresent() else {
            let empty: [ProfileID: Snapshot.Entry] = [:]
            values = empty
            return empty
        }
        let snapshot = try InspectableSnapshotJSONCodec.makeDecoder().decode(
            Snapshot.self,
            from: data
        )
        guard snapshot.schemaVersion == Snapshot.currentSchemaVersion else {
            throw CocoaError(.coderReadCorrupt)
        }
        let loaded = Dictionary(
            snapshot.entries.map { ($0.tombstone.profileID, $0) },
            uniquingKeysWith: { lhs, rhs in
                lhs.tombstone.deletedAt >= rhs.tombstone.deletedAt ? lhs : rhs
            }
        )
        values = loaded
        return loaded
    }

    private func persist(_ values: [ProfileID: Snapshot.Entry]) throws {
        let snapshot = Snapshot(
            entries: values.values.sorted {
                $0.tombstone.profileID.description
                    < $1.tombstone.profileID.description
            }
        )
        let data = try InspectableSnapshotJSONCodec.makeEncoder().encode(snapshot)
        try snapshotFile.write(data)
    }

    private var snapshotFile: AtomicSnapshotFile {
        AtomicSnapshotFile(snapshotURL: snapshotURL, fileManager: fileManager)
    }
}
