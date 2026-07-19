import Foundation
import TadaWordsDomain

public actor InMemoryPracticeSettingsRepository: PracticeSettingsRepository {
    private var storage = PracticeSettingsStorage()

    public init() {}

    public func settings(
        for profileID: ProfileID
    ) async throws -> ProfilePracticeSettings? {
        storage.settings(for: profileID)
    }

    public func save(_ settings: ProfilePracticeSettings) async throws {
        storage.save(settings)
    }

    public func delete(for profileID: ProfileID) async throws {
        storage.delete(for: profileID)
    }
}

public struct PracticeSettingsSnapshot: Codable, Equatable, Sendable {
    public static let currentSchemaVersion = 1

    public let schemaVersion: Int
    public let settings: [ProfilePracticeSettings]

    public init(
        schemaVersion: Int = Self.currentSchemaVersion,
        settings: [ProfilePracticeSettings]
    ) {
        self.schemaVersion = schemaVersion
        self.settings = settings
    }
}

public enum PracticeSettingsSnapshotValidationIssue: Equatable, Sendable {
    case duplicateProfileID(ProfileID)
}

public enum LocalPracticeSettingsRepositoryError: Error, Equatable, Sendable {
    case readFailed(snapshotURL: URL, details: String)
    case invalidJSON(snapshotURL: URL, details: String)
    case unsupportedSchemaVersion(
        snapshotURL: URL,
        found: Int,
        supported: Int
    )
    case invalidSnapshot(
        snapshotURL: URL,
        issue: PracticeSettingsSnapshotValidationIssue
    )
    case writeFailed(snapshotURL: URL, details: String)
}

/// Durable local practice settings. One actor instance should be shared for
/// each snapshot URL so writes remain serialized through a single owner.
public actor LocalJSONPracticeSettingsRepository: PracticeSettingsRepository {
    public nonisolated let snapshotURL: URL

    private let fileManager: FileManager
    private let mutationGate: ProfileScopedMutationGate?
    private var storage: PracticeSettingsStorage?
    private var loadFailure: LocalPracticeSettingsRepositoryError?

    public init(
        snapshotURL: URL,
        fileManager: FileManager = .default,
        mutationGate: ProfileScopedMutationGate? = nil
    ) {
        self.snapshotURL = snapshotURL
        self.fileManager = fileManager
        self.mutationGate = mutationGate
    }

    public func settings(
        for profileID: ProfileID
    ) async throws -> ProfilePracticeSettings? {
        try loadedStorage().settings(for: profileID)
    }

    public func save(_ settings: ProfilePracticeSettings) async throws {
        try await withMutationLease(for: settings.profileID) {
            var candidate = try loadedStorage()
            guard candidate.save(settings) else { return }
            try persist(candidate)
            storage = candidate
        }
    }

    public func delete(for profileID: ProfileID) async throws {
        try await withMutationLease(for: profileID) {
            var candidate = try loadedStorage()
            guard candidate.delete(for: profileID) else { return }
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

    /// Retries loading after a caller explicitly repairs or restores the
    /// snapshot. A failing file is never deleted or rewritten here.
    public func reloadFromDisk() throws {
        storage = nil
        loadFailure = nil
        _ = try loadedStorage()
    }

    private func loadedStorage() throws -> PracticeSettingsStorage {
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
        } catch let error as LocalPracticeSettingsRepositoryError {
            loadFailure = error
            throw error
        } catch {
            let wrappedError = LocalPracticeSettingsRepositoryError.readFailed(
                snapshotURL: snapshotURL,
                details: String(describing: error)
            )
            loadFailure = wrappedError
            throw wrappedError
        }
    }

    private func readStorage() throws -> PracticeSettingsStorage {
        let data: Data?
        do {
            data = try snapshotFile.readIfPresent()
        } catch {
            throw LocalPracticeSettingsRepositoryError.readFailed(
                snapshotURL: snapshotURL,
                details: String(describing: error)
            )
        }
        guard let data else { return PracticeSettingsStorage() }

        let snapshot: PracticeSettingsSnapshot
        do {
            snapshot = try InspectableSnapshotJSONCodec.makeDecoder().decode(
                PracticeSettingsSnapshot.self,
                from: data
            )
        } catch {
            throw LocalPracticeSettingsRepositoryError.invalidJSON(
                snapshotURL: snapshotURL,
                details: String(describing: error)
            )
        }

        guard snapshot.schemaVersion == PracticeSettingsSnapshot.currentSchemaVersion else {
            throw LocalPracticeSettingsRepositoryError.unsupportedSchemaVersion(
                snapshotURL: snapshotURL,
                found: snapshot.schemaVersion,
                supported: PracticeSettingsSnapshot.currentSchemaVersion
            )
        }

        do {
            return try PracticeSettingsStorage(settings: snapshot.settings)
        } catch let error as PracticeSettingsStorageValidationError {
            throw LocalPracticeSettingsRepositoryError.invalidSnapshot(
                snapshotURL: snapshotURL,
                issue: Self.publicValidationIssue(for: error)
            )
        }
    }

    private func persist(_ storage: PracticeSettingsStorage) throws {
        let snapshot = PracticeSettingsSnapshot(
            settings: storage.settingsInStableOrder
        )
        let data: Data
        do {
            data = try InspectableSnapshotJSONCodec.makeEncoder().encode(
                snapshot
            )
        } catch {
            throw LocalPracticeSettingsRepositoryError.writeFailed(
                snapshotURL: snapshotURL,
                details: "Could not encode snapshot: \(error)"
            )
        }

        do {
            try snapshotFile.write(data)
        } catch {
            throw LocalPracticeSettingsRepositoryError.writeFailed(
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
        for error: PracticeSettingsStorageValidationError
    ) -> PracticeSettingsSnapshotValidationIssue {
        switch error {
        case .duplicateProfileID(let profileID):
            .duplicateProfileID(profileID)
        }
    }
}
