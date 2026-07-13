import Foundation

public protocol FamilySyncPreferenceRepository: Sendable {
    func isEnabled() async throws -> Bool

    func setEnabled(_ isEnabled: Bool, updatedAt: Date) async throws
}

public actor InMemoryFamilySyncPreferenceRepository: FamilySyncPreferenceRepository {
    private var enabled: Bool

    public init(isEnabled: Bool = false) {
        enabled = isEnabled
    }

    public func isEnabled() async throws -> Bool {
        enabled
    }

    public func setEnabled(_ isEnabled: Bool, updatedAt: Date) async throws {
        _ = updatedAt
        enabled = isEnabled
    }
}

public struct FamilySyncPreferenceSnapshot: Codable, Equatable, Sendable {
    public static let currentSchemaVersion = 1
    public static let currentDisclosureVersion = 1

    public let schemaVersion: Int
    public let isEnabled: Bool
    public let disclosureVersion: Int?
    public let consentedAt: Date?
    public let updatedAt: Date?

    public init(
        schemaVersion: Int = Self.currentSchemaVersion,
        isEnabled: Bool,
        disclosureVersion: Int? = nil,
        consentedAt: Date? = nil,
        updatedAt: Date?
    ) {
        self.schemaVersion = schemaVersion
        self.isEnabled = isEnabled
        self.disclosureVersion = disclosureVersion
        self.consentedAt = consentedAt
        self.updatedAt = updatedAt
    }

    public var hasCurrentOptIn: Bool {
        isEnabled
            && disclosureVersion == Self.currentDisclosureVersion
            && consentedAt != nil
    }

    public static let disabled = FamilySyncPreferenceSnapshot(
        isEnabled: false,
        updatedAt: nil
    )
}

public enum LocalFamilySyncPreferenceRepositoryError: Error, Equatable, Sendable {
    case readFailed(snapshotURL: URL, details: String)
    case invalidJSON(snapshotURL: URL, details: String)
    case unsupportedSchemaVersion(
        snapshotURL: URL,
        found: Int,
        supported: Int
    )
    case writeFailed(snapshotURL: URL, details: String)
}

/// Stores a device-local privacy preference. A missing file is intentionally
/// interpreted as opt-out so fresh installs and migrations fail closed.
public actor LocalJSONFamilySyncPreferenceRepository: FamilySyncPreferenceRepository {
    public nonisolated let snapshotURL: URL

    private let fileManager: FileManager
    private var snapshot: FamilySyncPreferenceSnapshot?
    private var loadFailure: LocalFamilySyncPreferenceRepositoryError?

    public init(
        snapshotURL: URL,
        fileManager: FileManager = .default
    ) {
        self.snapshotURL = snapshotURL
        self.fileManager = fileManager
    }

    public func isEnabled() async throws -> Bool {
        try loadedSnapshot().hasCurrentOptIn
    }

    public func setEnabled(_ isEnabled: Bool, updatedAt: Date) async throws {
        if let current = try? loadedSnapshot() {
            if isEnabled, current.hasCurrentOptIn { return }
            if !isEnabled, !current.isEnabled { return }
        }
        try persist(
            FamilySyncPreferenceSnapshot(
                isEnabled: isEnabled,
                disclosureVersion:
                    isEnabled
                    ? FamilySyncPreferenceSnapshot.currentDisclosureVersion
                    : nil,
                consentedAt: isEnabled ? updatedAt : nil,
                updatedAt: updatedAt
            )
        )
    }

    public func reloadFromDisk() throws {
        snapshot = nil
        loadFailure = nil
        _ = try loadedSnapshot()
    }

    private func loadedSnapshot() throws -> FamilySyncPreferenceSnapshot {
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
        } catch let error as LocalFamilySyncPreferenceRepositoryError {
            loadFailure = error
            throw error
        } catch {
            let wrapped = LocalFamilySyncPreferenceRepositoryError.readFailed(
                snapshotURL: snapshotURL,
                details: String(describing: error)
            )
            loadFailure = wrapped
            throw wrapped
        }
    }

    private func readSnapshot() throws -> FamilySyncPreferenceSnapshot {
        let data: Data?
        do {
            data = try snapshotFile.readIfPresent()
        } catch {
            throw LocalFamilySyncPreferenceRepositoryError.readFailed(
                snapshotURL: snapshotURL,
                details: String(describing: error)
            )
        }
        guard let data else {
            return .disabled
        }
        let decoded: FamilySyncPreferenceSnapshot
        do {
            decoded = try InspectableSnapshotJSONCodec.makeDecoder().decode(
                FamilySyncPreferenceSnapshot.self,
                from: data
            )
        } catch {
            throw LocalFamilySyncPreferenceRepositoryError.invalidJSON(
                snapshotURL: snapshotURL,
                details: String(describing: error)
            )
        }
        guard decoded.schemaVersion == FamilySyncPreferenceSnapshot.currentSchemaVersion else {
            throw LocalFamilySyncPreferenceRepositoryError.unsupportedSchemaVersion(
                snapshotURL: snapshotURL,
                found: decoded.schemaVersion,
                supported: FamilySyncPreferenceSnapshot.currentSchemaVersion
            )
        }
        return decoded
    }

    private func persist(_ candidate: FamilySyncPreferenceSnapshot) throws {
        let data: Data
        do {
            data = try InspectableSnapshotJSONCodec.makeEncoder().encode(candidate)
        } catch {
            throw LocalFamilySyncPreferenceRepositoryError.writeFailed(
                snapshotURL: snapshotURL,
                details: "Could not encode snapshot: \(error)"
            )
        }
        do {
            try snapshotFile.write(data)
        } catch {
            throw LocalFamilySyncPreferenceRepositoryError.writeFailed(
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
