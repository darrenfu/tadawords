import Foundation
import TadaWordsDomain

public struct WordPoolSnapshot: Codable, Equatable, Sendable {
    public static let currentSchemaVersion = 1

    public let schemaVersion: Int
    public let entries: [WordPoolEntry]

    public init(
        schemaVersion: Int = Self.currentSchemaVersion,
        entries: [WordPoolEntry]
    ) {
        self.schemaVersion = schemaVersion
        self.entries = entries
    }
}

public enum WordPoolSnapshotValidationIssue: Equatable, Sendable {
    case duplicateEntryID(WordPoolEntryID)
    case duplicatePoolIdentity(WordPoolIdentity)
}

public enum LocalWordPoolRepositoryError: Error, Equatable, Sendable {
    case readFailed(snapshotURL: URL, details: String)
    case invalidJSON(snapshotURL: URL, details: String)
    case unsupportedSchemaVersion(
        snapshotURL: URL,
        found: Int,
        supported: Int
    )
    case invalidSnapshot(
        snapshotURL: URL,
        issue: WordPoolSnapshotValidationIssue
    )
    case writeFailed(snapshotURL: URL, details: String)
}

/// Local, inspectable persistence for the small V1 guardian word pool.
///
/// Mutations are applied to a value-semantic candidate, atomically written to
/// disk, and only then committed to actor state. A corrupt or unsupported file
/// remains untouched and latches a typed load error until `reloadFromDisk()`.
public actor LocalJSONWordPoolRepository: WordPoolRepository {
    public nonisolated let snapshotURL: URL

    private let fileManager: FileManager
    private var storage: WordPoolStorage?
    private var loadFailure: LocalWordPoolRepositoryError?

    public init(
        snapshotURL: URL,
        fileManager: FileManager = .default
    ) {
        self.snapshotURL = snapshotURL
        self.fileManager = fileManager
    }

    public func upsert(_ drafts: [WordPoolEntryDraft]) async throws
        -> [WordPoolUpsertOutcome]
    {
        guard !drafts.isEmpty else { return [] }

        var candidate = try loadedStorage()
        let outcomes = candidate.upsert(drafts)
        try persist(candidate)
        storage = candidate
        return outcomes
    }

    public func entries(
        for profileID: ProfileID,
        learningMode: LearningMode,
        includingInactive: Bool = false
    ) async throws -> [WordPoolEntry] {
        try loadedStorage().entries(
            for: profileID,
            learningMode: learningMode,
            includingInactive: includingInactive
        )
    }

    public func setActive(
        _ isActive: Bool,
        entryID: WordPoolEntryID
    ) async throws -> WordPoolEntry {
        var candidate = try loadedStorage()
        let updatedEntry = try candidate.setActive(
            isActive,
            entryID: entryID
        )
        try persist(candidate)
        storage = candidate
        return updatedEntry
    }

    public func setActive(
        _ isActive: Bool,
        entryIDs: [WordPoolEntryID]
    ) async throws -> [WordPoolEntry] {
        guard !entryIDs.isEmpty else { return [] }
        var candidate = try loadedStorage()
        let updatedEntries = try candidate.setActive(
            isActive,
            entryIDs: entryIDs
        )
        try persist(candidate)
        storage = candidate
        return updatedEntries
    }

    public func mergeSynced(_ entry: WordPoolEntry) throws {
        var candidate = try loadedStorage()
        guard try candidate.mergeSynced(entry) else { return }
        try persist(candidate)
        storage = candidate
    }

    public func deleteAll(for profileID: ProfileID) async throws {
        var candidate = try loadedStorage()
        guard candidate.deleteAll(for: profileID) else { return }
        try persist(candidate)
        storage = candidate
    }

    /// Retries loading after a caller has explicitly repaired or restored the
    /// snapshot. This method never deletes or rewrites a failing file.
    public func reloadFromDisk() throws {
        storage = nil
        loadFailure = nil
        _ = try loadedStorage()
    }

    private func loadedStorage() throws -> WordPoolStorage {
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
        } catch let error as LocalWordPoolRepositoryError {
            loadFailure = error
            throw error
        } catch {
            let wrappedError = LocalWordPoolRepositoryError.readFailed(
                snapshotURL: snapshotURL,
                details: String(describing: error)
            )
            loadFailure = wrappedError
            throw wrappedError
        }
    }

    private func readStorage() throws -> WordPoolStorage {
        let data: Data?
        do {
            data = try snapshotFile.readIfPresent()
        } catch {
            throw LocalWordPoolRepositoryError.readFailed(
                snapshotURL: snapshotURL,
                details: String(describing: error)
            )
        }
        guard let data else { return WordPoolStorage() }

        let snapshot: WordPoolSnapshot
        do {
            snapshot = try InspectableSnapshotJSONCodec.makeDecoder().decode(
                WordPoolSnapshot.self,
                from: data
            )
        } catch {
            throw LocalWordPoolRepositoryError.invalidJSON(
                snapshotURL: snapshotURL,
                details: String(describing: error)
            )
        }

        guard snapshot.schemaVersion == WordPoolSnapshot.currentSchemaVersion else {
            throw LocalWordPoolRepositoryError.unsupportedSchemaVersion(
                snapshotURL: snapshotURL,
                found: snapshot.schemaVersion,
                supported: WordPoolSnapshot.currentSchemaVersion
            )
        }

        do {
            return try WordPoolStorage(entries: snapshot.entries)
        } catch let error as WordPoolStorageValidationError {
            throw LocalWordPoolRepositoryError.invalidSnapshot(
                snapshotURL: snapshotURL,
                issue: Self.publicValidationIssue(for: error)
            )
        }
    }

    private var snapshotFile: AtomicSnapshotFile {
        AtomicSnapshotFile(
            snapshotURL: snapshotURL,
            fileManager: fileManager
        )
    }

    private func persist(_ storage: WordPoolStorage) throws {
        let snapshot = WordPoolSnapshot(
            entries: storage.allEntriesInStableOrder
        )
        let data: Data
        do {
            data = try InspectableSnapshotJSONCodec.makeEncoder().encode(
                snapshot
            )
        } catch {
            throw LocalWordPoolRepositoryError.writeFailed(
                snapshotURL: snapshotURL,
                details: "Could not encode snapshot: \(error)"
            )
        }

        do {
            try snapshotFile.write(data)
        } catch {
            throw LocalWordPoolRepositoryError.writeFailed(
                snapshotURL: snapshotURL,
                details: String(describing: error)
            )
        }
    }

    private static func publicValidationIssue(
        for error: WordPoolStorageValidationError
    ) -> WordPoolSnapshotValidationIssue {
        switch error {
        case .duplicateEntryID(let entryID):
            .duplicateEntryID(entryID)
        case .duplicatePoolIdentity(let identity):
            .duplicatePoolIdentity(identity)
        }
    }
}
