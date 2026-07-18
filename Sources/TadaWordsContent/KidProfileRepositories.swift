import Foundation
import TadaWordsDomain

public enum KidProfileRepositoryError: Error, Equatable, Sendable {
    case conflictingCreatedAt(
        profileID: ProfileID,
        existing: Date,
        incoming: Date
    )
}

public actor InMemoryKidProfileRepository: KidProfileRepository {
    private var storage: KidProfileStorage

    public init() {
        storage = KidProfileStorage()
    }

    public func profiles() async throws -> [KidProfile] {
        storage.profilesInStableOrder
    }

    public func profile(id: ProfileID) async throws -> KidProfile? {
        storage.profile(id: id)
    }

    public func save(_ profile: KidProfile) async throws {
        try storage.save(profile)
    }

    public func delete(id: ProfileID) async throws {
        storage.delete(id: id)
    }
}

public struct KidProfileSnapshot: Codable, Equatable, Sendable {
    public static let currentSchemaVersion = 1

    public let schemaVersion: Int
    public let profiles: [KidProfile]

    public init(
        schemaVersion: Int = Self.currentSchemaVersion,
        profiles: [KidProfile]
    ) {
        self.schemaVersion = schemaVersion
        self.profiles = profiles
    }
}

public enum KidProfileSnapshotValidationIssue: Equatable, Sendable {
    case duplicateProfileID(ProfileID)
}

public enum LocalKidProfileRepositoryError: Error, Equatable, Sendable {
    case readFailed(snapshotURL: URL, details: String)
    case invalidJSON(snapshotURL: URL, details: String)
    case unsupportedSchemaVersion(
        snapshotURL: URL,
        found: Int,
        supported: Int
    )
    case invalidSnapshot(
        snapshotURL: URL,
        issue: KidProfileSnapshotValidationIssue
    )
    case writeFailed(snapshotURL: URL, details: String)
}

/// Durable local profile source of truth. A single actor instance should be
/// shared by all composition roots that target the same snapshot URL.
public actor LocalJSONKidProfileRepository: KidProfileRepository {
    public nonisolated let snapshotURL: URL

    private let fileManager: FileManager
    private let mutationGate: ProfileScopedMutationGate?
    private var storage: KidProfileStorage?
    private var loadFailure: LocalKidProfileRepositoryError?

    public init(
        snapshotURL: URL,
        fileManager: FileManager = .default,
        mutationGate: ProfileScopedMutationGate? = nil
    ) {
        self.snapshotURL = snapshotURL
        self.fileManager = fileManager
        self.mutationGate = mutationGate
    }

    public func profiles() async throws -> [KidProfile] {
        try loadedStorage().profilesInStableOrder
    }

    public func profile(id: ProfileID) async throws -> KidProfile? {
        try loadedStorage().profile(id: id)
    }

    public func save(_ profile: KidProfile) async throws {
        try await withMutationLease(for: profile.id) {
            var candidate = try loadedStorage()
            guard try candidate.save(profile) else { return }
            try persist(candidate)
            storage = candidate
        }
    }

    public func delete(id: ProfileID) async throws {
        try await withMutationLease(for: id) {
            var candidate = try loadedStorage()
            guard candidate.delete(id: id) else { return }
            try persist(candidate)
            storage = candidate
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

    /// Retries loading only after a caller explicitly repairs or restores the
    /// snapshot. A failing file is never deleted or rewritten here.
    public func reloadFromDisk() throws {
        storage = nil
        loadFailure = nil
        _ = try loadedStorage()
    }

    private func loadedStorage() throws -> KidProfileStorage {
        if let loadFailure {
            throw loadFailure
        }
        if let storage {
            return storage
        }

        do {
            let loadedStorage = try readStorage()
            storage = loadedStorage
            return loadedStorage
        } catch let error as LocalKidProfileRepositoryError {
            loadFailure = error
            throw error
        } catch {
            let wrappedError = LocalKidProfileRepositoryError.readFailed(
                snapshotURL: snapshotURL,
                details: String(describing: error)
            )
            loadFailure = wrappedError
            throw wrappedError
        }
    }

    private func readStorage() throws -> KidProfileStorage {
        let data: Data?
        do {
            data = try snapshotFile.readIfPresent()
        } catch {
            throw LocalKidProfileRepositoryError.readFailed(
                snapshotURL: snapshotURL,
                details: String(describing: error)
            )
        }
        guard let data else { return KidProfileStorage() }

        let snapshot: KidProfileSnapshot
        do {
            snapshot = try InspectableSnapshotJSONCodec.makeDecoder().decode(
                KidProfileSnapshot.self,
                from: data
            )
        } catch {
            throw LocalKidProfileRepositoryError.invalidJSON(
                snapshotURL: snapshotURL,
                details: String(describing: error)
            )
        }

        guard snapshot.schemaVersion == KidProfileSnapshot.currentSchemaVersion else {
            throw LocalKidProfileRepositoryError.unsupportedSchemaVersion(
                snapshotURL: snapshotURL,
                found: snapshot.schemaVersion,
                supported: KidProfileSnapshot.currentSchemaVersion
            )
        }

        do {
            return try KidProfileStorage(profiles: snapshot.profiles)
        } catch let error as KidProfileStorageValidationError {
            throw LocalKidProfileRepositoryError.invalidSnapshot(
                snapshotURL: snapshotURL,
                issue: Self.publicValidationIssue(for: error)
            )
        }
    }

    private func persist(_ storage: KidProfileStorage) throws {
        let snapshot = KidProfileSnapshot(
            profiles: storage.profilesInStableOrder
        )
        let data: Data
        do {
            data = try InspectableSnapshotJSONCodec.makeEncoder().encode(
                snapshot
            )
        } catch {
            throw LocalKidProfileRepositoryError.writeFailed(
                snapshotURL: snapshotURL,
                details: "Could not encode snapshot: \(error)"
            )
        }

        do {
            try snapshotFile.write(data)
        } catch {
            throw LocalKidProfileRepositoryError.writeFailed(
                snapshotURL: snapshotURL,
                details: String(describing: error)
            )
        }
    }

    private var snapshotFile: AtomicSnapshotFile {
        AtomicSnapshotFile(
            snapshotURL: snapshotURL,
            fileManager: fileManager
        )
    }

    private static func publicValidationIssue(
        for error: KidProfileStorageValidationError
    ) -> KidProfileSnapshotValidationIssue {
        switch error {
        case .duplicateProfileID(let profileID):
            .duplicateProfileID(profileID)
        }
    }
}
