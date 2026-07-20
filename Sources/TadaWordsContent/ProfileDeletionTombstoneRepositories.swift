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
    func erasureLifecycles() async throws -> [ProfileErasureLifecycle]
    func erasureLifecycle(for profileID: ProfileID) async throws -> ProfileErasureLifecycle?
    func save(_ tombstone: ProfileDeletionTombstone) async throws
    func markCommitted(for profileID: ProfileID) async throws
    func recordErasureEvent(
        _ event: ProfileErasureLifecycleEvent,
        for profileID: ProfileID
    ) async throws
    func delete(for profileID: ProfileID) async throws
}

public enum ProfileErasureLifecycleEvent: Equatable, Sendable {
    case attemptStarted(route: ProfileErasureRoute, at: Date)
    case routeResolved(route: ProfileErasureRoute, at: Date)
    case retryScheduled(
        route: ProfileErasureRoute,
        retryCount: Int,
        nextRetryAt: Date?,
        category: FamilySyncPrivacySafeErrorCategory,
        at: Date
    )
    case needsAttention(
        route: ProfileErasureRoute,
        category: FamilySyncPrivacySafeErrorCategory,
        at: Date
    )
    case completed(route: ProfileErasureRoute, at: Date)
}

public enum ProfileErasureLifecycleRepositoryError: Error, Equatable {
    case missingLifecycle(ProfileID)
    case unresolvedCompletion(ProfileID)
    case routeConflict(
        profileID: ProfileID,
        existing: ProfileErasureRoute,
        requested: ProfileErasureRoute
    )
    case unsupportedLifecycleStorage
}

extension ProfileDeletionTombstoneRepository {
    public func erasureLifecycles() async throws -> [ProfileErasureLifecycle] {
        throw ProfileErasureLifecycleRepositoryError.unsupportedLifecycleStorage
    }

    public func erasureLifecycle(
        for profileID: ProfileID
    ) async throws -> ProfileErasureLifecycle? {
        throw ProfileErasureLifecycleRepositoryError.unsupportedLifecycleStorage
    }

    public func recordErasureEvent(
        _ event: ProfileErasureLifecycleEvent,
        for profileID: ProfileID
    ) async throws {
        _ = event
        throw ProfileErasureLifecycleRepositoryError.unsupportedLifecycleStorage
    }
}

public actor InMemoryProfileDeletionTombstoneRepository:
    ProfileDeletionTombstoneRepository
{
    private struct Entry: Sendable {
        var tombstone: ProfileDeletionTombstone
        var isLocalPurgeCommitted: Bool
        var lifecycle: ProfileErasureLifecycle
    }

    private var values: [ProfileID: Entry]

    public init(tombstones: [ProfileDeletionTombstone] = []) {
        values = Dictionary(
            uniqueKeysWithValues: tombstones.map { tombstone in
                (
                    tombstone.profileID,
                    Entry(
                        tombstone: tombstone,
                        isLocalPurgeCommitted: true,
                        lifecycle: ProfileErasureLifecycle(
                            profileID: tombstone.profileID,
                            route: .unresolved,
                            state: .requested,
                            requestedAt: tombstone.deletedAt
                        )
                    )
                )
            }
        )
    }

    public func tombstones() async throws -> [ProfileDeletionTombstone] {
        values.values.map(\.tombstone).sorted {
            $0.profileID.description < $1.profileID.description
        }
    }

    public func pendingTombstones() async throws -> [ProfileDeletionTombstone] {
        values.values
            .filter { !$0.isLocalPurgeCommitted }
            .map(\.tombstone)
    }

    public func tombstone(
        for profileID: ProfileID
    ) async throws -> ProfileDeletionTombstone? {
        values[profileID]?.tombstone
    }

    public func erasureLifecycles() async throws -> [ProfileErasureLifecycle] {
        values.values.map(\.lifecycle).sorted {
            $0.profileID.description < $1.profileID.description
        }
    }

    public func erasureLifecycle(
        for profileID: ProfileID
    ) async throws -> ProfileErasureLifecycle? {
        values[profileID]?.lifecycle
    }

    public func save(_ tombstone: ProfileDeletionTombstone) async throws {
        if let entry = values[tombstone.profileID] {
            guard entry.tombstone.deletedAt < tombstone.deletedAt else { return }
            values[tombstone.profileID] = Entry(
                tombstone: tombstone,
                isLocalPurgeCommitted: false,
                lifecycle: entry.lifecycle
            )
            return
        }
        values[tombstone.profileID] = Entry(
            tombstone: tombstone,
            isLocalPurgeCommitted: false,
            lifecycle: ProfileErasureLifecycle(
                profileID: tombstone.profileID,
                requestedAt: tombstone.deletedAt
            )
        )
    }

    public func markCommitted(for profileID: ProfileID) async throws {
        guard var entry = values[profileID] else { return }
        entry.isLocalPurgeCommitted = true
        values[profileID] = entry
    }

    public func recordErasureEvent(
        _ event: ProfileErasureLifecycleEvent,
        for profileID: ProfileID
    ) async throws {
        guard var entry = values[profileID] else {
            throw ProfileErasureLifecycleRepositoryError.missingLifecycle(profileID)
        }
        entry.lifecycle = try applying(
            event,
            to: entry.lifecycle,
            profileID: profileID
        )
        values[profileID] = entry
    }

    public func delete(for profileID: ProfileID) async throws {
        values.removeValue(forKey: profileID)
    }
}

public actor LocalJSONProfileDeletionTombstoneRepository:
    ProfileDeletionTombstoneRepository
{
    public nonisolated static let currentSchemaVersion = 2

    private struct Snapshot: Codable {
        struct Entry: Codable {
            let tombstone: ProfileDeletionTombstone
            let isLocalPurgeCommitted: Bool
            let lifecycle: ProfileErasureLifecycle
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

    private struct SnapshotEnvelope: Decodable {
        let schemaVersion: Int
    }

    private struct LegacySnapshot: Decodable {
        struct Entry: Decodable {
            let tombstone: ProfileDeletionTombstone
            let isCommitted: Bool
        }

        let schemaVersion: Int
        let entries: [Entry]
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
            .filter { !$0.isLocalPurgeCommitted }
            .map(\.tombstone)
            .sorted { $0.profileID.description < $1.profileID.description }
    }

    public func tombstone(
        for profileID: ProfileID
    ) async throws -> ProfileDeletionTombstone? {
        try loadedValues()[profileID]?.tombstone
    }

    public func erasureLifecycles() async throws -> [ProfileErasureLifecycle] {
        try loadedValues().values.map(\.lifecycle).sorted {
            $0.profileID.description < $1.profileID.description
        }
    }

    public func erasureLifecycle(
        for profileID: ProfileID
    ) async throws -> ProfileErasureLifecycle? {
        try loadedValues()[profileID]?.lifecycle
    }

    public func save(_ tombstone: ProfileDeletionTombstone) async throws {
        try await withMutationLease(
            for: tombstone.profileID,
            sealAfterSuccess: true
        ) {
            var candidate = try loadedValues()
            guard
                candidate[tombstone.profileID]?.tombstone.deletedAt ?? .distantPast
                    < tombstone.deletedAt
            else { return }
            let lifecycle =
                candidate[tombstone.profileID]?.lifecycle
                ?? ProfileErasureLifecycle(
                    profileID: tombstone.profileID,
                    requestedAt: tombstone.deletedAt
                )
            candidate[tombstone.profileID] = Snapshot.Entry(
                tombstone: tombstone,
                isLocalPurgeCommitted: false,
                lifecycle: lifecycle
            )
            try persist(candidate)
            values = candidate
        }
    }

    public func markCommitted(for profileID: ProfileID) async throws {
        try await withMutationLease(for: profileID) {
            var candidate = try loadedValues()
            guard let entry = candidate[profileID], !entry.isLocalPurgeCommitted else {
                return
            }
            candidate[profileID] = Snapshot.Entry(
                tombstone: entry.tombstone,
                isLocalPurgeCommitted: true,
                lifecycle: entry.lifecycle
            )
            try persist(candidate)
            values = candidate
        }
    }

    public func recordErasureEvent(
        _ event: ProfileErasureLifecycleEvent,
        for profileID: ProfileID
    ) async throws {
        try await withMutationLease(for: profileID) {
            var candidate = try loadedValues()
            guard let entry = candidate[profileID] else {
                throw ProfileErasureLifecycleRepositoryError.missingLifecycle(profileID)
            }
            let lifecycle = try applying(
                event,
                to: entry.lifecycle,
                profileID: profileID
            )
            guard lifecycle != entry.lifecycle else { return }
            candidate[profileID] = Snapshot.Entry(
                tombstone: entry.tombstone,
                isLocalPurgeCommitted: entry.isLocalPurgeCommitted,
                lifecycle: lifecycle
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
        sealAfterSuccess: Bool = false,
        _ operation: () throws -> Void
    ) async throws {
        guard let mutationGate,
            ProfileScopedMutationLeaseContext.profileID != profileID
        else {
            try operation()
            if sealAfterSuccess {
                await mutationGate?.seal(profileID)
            }
            return
        }
        try await mutationGate.acquire(
            profileID,
            allowingTerminal: true
        )
        do {
            try operation()
            if sealAfterSuccess {
                await mutationGate.seal(profileID)
            }
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
        let decoder = InspectableSnapshotJSONCodec.makeDecoder()
        let envelope = try decoder.decode(SnapshotEnvelope.self, from: data)
        let loaded: [ProfileID: Snapshot.Entry]
        switch envelope.schemaVersion {
        case Snapshot.currentSchemaVersion:
            let snapshot = try decoder.decode(Snapshot.self, from: data)
            loaded = try validatedEntries(snapshot.entries)
        case 1:
            let legacy = try decoder.decode(LegacySnapshot.self, from: data)
            loaded = try validatedEntries(
                legacy.entries.map { entry in
                    Snapshot.Entry(
                        tombstone: entry.tombstone,
                        isLocalPurgeCommitted: entry.isCommitted,
                        lifecycle: ProfileErasureLifecycle(
                            profileID: entry.tombstone.profileID,
                            requestedAt: entry.tombstone.deletedAt
                        )
                    )
                }
            )
            try persist(loaded)
        default:
            throw CocoaError(.coderReadCorrupt)
        }
        values = loaded
        return loaded
    }

    private func validatedEntries(
        _ entries: [Snapshot.Entry]
    ) throws -> [ProfileID: Snapshot.Entry] {
        let profileIDs = entries.map { $0.tombstone.profileID }
        guard
            Set(profileIDs).count == profileIDs.count,
            entries.allSatisfy({ entry in
                entry.lifecycle.profileID == entry.tombstone.profileID
                    && entry.lifecycle.attemptCount >= 0
                    && entry.lifecycle.retryCount >= 0
            })
        else {
            throw CocoaError(.coderReadCorrupt)
        }
        return Dictionary(uniqueKeysWithValues: zip(profileIDs, entries))
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

private func applying(
    _ event: ProfileErasureLifecycleEvent,
    to lifecycle: ProfileErasureLifecycle,
    profileID: ProfileID
) throws -> ProfileErasureLifecycle {
    guard lifecycle.state != .complete else { return lifecycle }

    let requestedRoute: ProfileErasureRoute
    switch event {
    case .attemptStarted(let route, _),
        .routeResolved(let route, _),
        .retryScheduled(let route, _, _, _, _),
        .needsAttention(let route, _, _),
        .completed(let route, _):
        requestedRoute = route
    }
    let route = try mergedRoute(
        existing: lifecycle.route,
        requested: requestedRoute,
        profileID: profileID
    )

    switch event {
    case .attemptStarted(_, let at):
        return ProfileErasureLifecycle(
            profileID: profileID,
            route: route,
            state: .deleting,
            requestedAt: lifecycle.requestedAt,
            attemptCount: safeIncrement(lifecycle.attemptCount),
            retryCount: lifecycle.retryCount,
            lastAttemptAt: latest(lifecycle.lastAttemptAt, at),
            nextRetryAt: nil,
            lastSuccessAt: lifecycle.lastSuccessAt,
            errorCategory: nil
        )
    case .routeResolved:
        return ProfileErasureLifecycle(
            profileID: profileID,
            route: route,
            state: lifecycle.state,
            requestedAt: lifecycle.requestedAt,
            attemptCount: lifecycle.attemptCount,
            retryCount: lifecycle.retryCount,
            lastAttemptAt: lifecycle.lastAttemptAt,
            nextRetryAt: lifecycle.nextRetryAt,
            lastSuccessAt: lifecycle.lastSuccessAt,
            errorCategory: lifecycle.errorCategory
        )
    case .retryScheduled(_, let retryCount, let nextRetryAt, let category, let at):
        return ProfileErasureLifecycle(
            profileID: profileID,
            route: route,
            state: .waitingForConnection,
            requestedAt: lifecycle.requestedAt,
            attemptCount: lifecycle.attemptCount,
            retryCount: max(lifecycle.retryCount, max(0, retryCount)),
            lastAttemptAt: latest(lifecycle.lastAttemptAt, at),
            nextRetryAt: latest(lifecycle.nextRetryAt, nextRetryAt),
            lastSuccessAt: lifecycle.lastSuccessAt,
            errorCategory: category
        )
    case .needsAttention(_, let category, let at):
        return ProfileErasureLifecycle(
            profileID: profileID,
            route: route,
            state: .needsAttention,
            requestedAt: lifecycle.requestedAt,
            attemptCount: lifecycle.attemptCount,
            retryCount: lifecycle.retryCount,
            lastAttemptAt: latest(lifecycle.lastAttemptAt, at),
            nextRetryAt: nil,
            lastSuccessAt: lifecycle.lastSuccessAt,
            errorCategory: category
        )
    case .completed(_, let at):
        guard route != .unresolved else {
            throw ProfileErasureLifecycleRepositoryError.unresolvedCompletion(profileID)
        }
        return ProfileErasureLifecycle(
            profileID: profileID,
            route: route,
            state: .complete,
            requestedAt: lifecycle.requestedAt,
            attemptCount: lifecycle.attemptCount,
            retryCount: lifecycle.retryCount,
            lastAttemptAt: lifecycle.lastAttemptAt,
            nextRetryAt: nil,
            lastSuccessAt: latest(lifecycle.lastSuccessAt, at),
            errorCategory: nil
        )
    }
}

private func mergedRoute(
    existing: ProfileErasureRoute,
    requested: ProfileErasureRoute,
    profileID: ProfileID
) throws -> ProfileErasureRoute {
    if requested == .unresolved { return existing }
    if existing == .unresolved || existing == requested { return requested }
    throw ProfileErasureLifecycleRepositoryError.routeConflict(
        profileID: profileID,
        existing: existing,
        requested: requested
    )
}

private func latest(_ lhs: Date?, _ rhs: Date?) -> Date? {
    switch (lhs, rhs) {
    case (.none, .none): return nil
    case (.some(let value), .none), (.none, .some(let value)): return value
    case (.some(let lhs), .some(let rhs)): return max(lhs, rhs)
    }
}

private func safeIncrement(_ value: Int) -> Int {
    value == Int.max ? value : value + 1
}
