import Foundation
import TadaWordsDomain

public actor InMemoryChildSessionRepository: ChildSessionRepository {
    private var storedProfileID: ProfileID?

    public init(lastSelectedProfileID: ProfileID? = nil) {
        storedProfileID = lastSelectedProfileID
    }

    public func lastSelectedProfileID() async throws -> ProfileID? {
        storedProfileID
    }

    public func saveLastSelectedProfileID(_ profileID: ProfileID) async throws {
        storedProfileID = profileID
    }

    public func clearLastSelectedProfileID() async throws {
        storedProfileID = nil
    }
}

public struct ChildSessionSnapshot: Codable, Equatable, Sendable {
    public static let currentSchemaVersion = 1

    public let schemaVersion: Int
    public let lastSelectedProfileID: ProfileID?

    public init(
        schemaVersion: Int = Self.currentSchemaVersion,
        lastSelectedProfileID: ProfileID?
    ) {
        self.schemaVersion = schemaVersion
        self.lastSelectedProfileID = lastSelectedProfileID
    }
}

public enum LocalChildSessionRepositoryError: Error, Equatable, Sendable {
    case readFailed(snapshotURL: URL, details: String)
    case invalidJSON(snapshotURL: URL, details: String)
    case unsupportedSchemaVersion(
        snapshotURL: URL,
        found: Int,
        supported: Int
    )
    case writeFailed(snapshotURL: URL, details: String)
}

/// Stores only the child area's launch preference. Profile data remains in the
/// profile repository and is always revalidated by the composition root.
public actor LocalJSONChildSessionRepository: ChildSessionRepository {
    public nonisolated let snapshotURL: URL

    private let fileManager: FileManager
    private var snapshot: ChildSessionSnapshot?
    private var loadFailure: LocalChildSessionRepositoryError?

    public init(
        snapshotURL: URL,
        fileManager: FileManager = .default
    ) {
        self.snapshotURL = snapshotURL
        self.fileManager = fileManager
    }

    public func lastSelectedProfileID() async throws -> ProfileID? {
        try loadedSnapshot().lastSelectedProfileID
    }

    public func saveLastSelectedProfileID(_ profileID: ProfileID) async throws {
        do {
            if try loadedSnapshot().lastSelectedProfileID == profileID {
                return
            }
        } catch let error as LocalChildSessionRepositoryError {
            if case .unsupportedSchemaVersion = error { throw error }
        }
        // A malformed preference must not become a permanent latch. The next
        // explicit player selection is authoritative and atomically repairs it.
        try persist(ChildSessionSnapshot(lastSelectedProfileID: profileID))
    }

    public func clearLastSelectedProfileID() async throws {
        do {
            if try loadedSnapshot().lastSelectedProfileID == nil {
                return
            }
        } catch let error as LocalChildSessionRepositoryError {
            if case .unsupportedSchemaVersion = error { throw error }
        }
        try persist(ChildSessionSnapshot(lastSelectedProfileID: nil))
    }

    public func reloadFromDisk() throws {
        snapshot = nil
        loadFailure = nil
        _ = try loadedSnapshot()
    }

    private func loadedSnapshot() throws -> ChildSessionSnapshot {
        if let loadFailure {
            throw loadFailure
        }
        if let snapshot {
            return snapshot
        }
        do {
            let loaded = try readSnapshot()
            snapshot = loaded
            return loaded
        } catch let error as LocalChildSessionRepositoryError {
            loadFailure = error
            throw error
        } catch {
            let wrapped = LocalChildSessionRepositoryError.readFailed(
                snapshotURL: snapshotURL,
                details: String(describing: error)
            )
            loadFailure = wrapped
            throw wrapped
        }
    }

    private func readSnapshot() throws -> ChildSessionSnapshot {
        let data: Data?
        do {
            data = try snapshotFile.readIfPresent()
        } catch {
            throw LocalChildSessionRepositoryError.readFailed(
                snapshotURL: snapshotURL,
                details: String(describing: error)
            )
        }
        guard let data else {
            return ChildSessionSnapshot(lastSelectedProfileID: nil)
        }
        let decoded: ChildSessionSnapshot
        do {
            decoded = try InspectableSnapshotJSONCodec.makeDecoder().decode(
                ChildSessionSnapshot.self,
                from: data
            )
        } catch {
            throw LocalChildSessionRepositoryError.invalidJSON(
                snapshotURL: snapshotURL,
                details: String(describing: error)
            )
        }
        guard decoded.schemaVersion == ChildSessionSnapshot.currentSchemaVersion else {
            throw LocalChildSessionRepositoryError.unsupportedSchemaVersion(
                snapshotURL: snapshotURL,
                found: decoded.schemaVersion,
                supported: ChildSessionSnapshot.currentSchemaVersion
            )
        }
        return decoded
    }

    private func persist(_ candidate: ChildSessionSnapshot) throws {
        let data: Data
        do {
            data = try InspectableSnapshotJSONCodec.makeEncoder().encode(candidate)
        } catch {
            throw LocalChildSessionRepositoryError.writeFailed(
                snapshotURL: snapshotURL,
                details: "Could not encode snapshot: \(error)"
            )
        }
        do {
            try snapshotFile.write(data)
        } catch {
            throw LocalChildSessionRepositoryError.writeFailed(
                snapshotURL: snapshotURL,
                details: String(describing: error)
            )
        }
        snapshot = candidate
        loadFailure = nil
    }

    private var snapshotFile: AtomicSnapshotFile {
        AtomicSnapshotFile(
            snapshotURL: snapshotURL,
            fileManager: fileManager
        )
    }
}
