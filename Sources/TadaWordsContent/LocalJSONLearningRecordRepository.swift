import Foundation
import TadaWordsDomain

public struct LearningRecordSnapshot: Codable, Equatable, Sendable {
    public static let currentSchemaVersion = 1

    public let schemaVersion: Int
    public let attempts: [AttemptEvent]
    public let corrections: [AttemptCorrectionEvent]
    public let progress: [WordProgress]

    public init(
        schemaVersion: Int = Self.currentSchemaVersion,
        attempts: [AttemptEvent],
        corrections: [AttemptCorrectionEvent],
        progress: [WordProgress]
    ) {
        self.schemaVersion = schemaVersion
        self.attempts = attempts
        self.corrections = corrections
        self.progress = progress
    }
}

public enum LearningRecordSnapshotValidationIssue: Equatable, Sendable {
    case duplicateAttemptID(AttemptID)
    case duplicateCorrectionID(AttemptCorrectionID)
    case duplicateProgressKey(
        profileID: ProfileID,
        wordPromptID: WordPromptID,
        learningMode: LearningMode
    )
    case conflictingProgressMode(
        profileID: ProfileID,
        wordPromptID: WordPromptID,
        firstMode: LearningMode,
        secondMode: LearningMode
    )
}

public enum LearningRecordRepositoryError: Error, Equatable, Sendable {
    case conflictingAttemptID(AttemptID)
    case conflictingCorrectionID(AttemptCorrectionID)
    case conflictingProgressMode(
        profileID: ProfileID,
        wordPromptID: WordPromptID,
        existingMode: LearningMode,
        incomingMode: LearningMode
    )
}

public enum LocalLearningRecordRepositoryError: Error, Equatable, Sendable {
    case readFailed(snapshotURL: URL, details: String)
    case invalidJSON(snapshotURL: URL, details: String)
    case unsupportedSchemaVersion(
        snapshotURL: URL,
        found: Int,
        supported: Int
    )
    case invalidSnapshot(
        snapshotURL: URL,
        issue: LearningRecordSnapshotValidationIssue
    )
    case writeFailed(snapshotURL: URL, details: String)
}

/// Durable local source of truth for immutable learning facts and rebuildable
/// progress snapshots. One actor instance should be shared for each file URL.
public actor LocalJSONLearningRecordRepository: ProfileLearningRecordRepository {
    public nonisolated let snapshotURL: URL

    private let fileManager: FileManager
    private var storage: LearningRecordStorage?
    private var loadFailure: LocalLearningRecordRepositoryError?

    public init(
        snapshotURL: URL,
        fileManager: FileManager = .default
    ) {
        self.snapshotURL = snapshotURL
        self.fileManager = fileManager
    }

    public func append(_ event: AttemptEvent) async throws {
        var candidate = try loadedStorage()
        guard try candidate.append(event) else { return }
        try persist(candidate)
        storage = candidate
    }

    public func append(_ correction: AttemptCorrectionEvent) async throws {
        var candidate = try loadedStorage()
        guard try candidate.append(correction) else { return }
        try persist(candidate)
        storage = candidate
    }

    public func attempts(
        for profileID: ProfileID,
        wordPromptID: WordPromptID?
    ) async throws -> [AttemptEvent] {
        try loadedStorage().attempts(
            for: profileID,
            wordPromptID: wordPromptID
        )
    }

    public func corrections(
        for attemptID: AttemptID
    ) async throws -> [AttemptCorrectionEvent] {
        try loadedStorage().corrections(for: attemptID)
    }

    public func progress(
        for profileID: ProfileID,
        wordPromptID: WordPromptID
    ) async throws -> WordProgress? {
        try loadedStorage().progress(
            for: profileID,
            wordPromptID: wordPromptID
        )
    }

    /// Mode-explicit convenience for composition code that already owns a
    /// `LearningMode`; the Domain protocol remains supported unchanged.
    public func progress(
        for profileID: ProfileID,
        wordPromptID: WordPromptID,
        learningMode: LearningMode
    ) async throws -> WordProgress? {
        try loadedStorage().progress(
            for: profileID,
            wordPromptID: wordPromptID,
            learningMode: learningMode
        )
    }

    public func save(_ progress: WordProgress) async throws {
        var candidate = try loadedStorage()
        guard try candidate.save(progress) else { return }
        try persist(candidate)
        storage = candidate
    }

    public func allProgress(
        for profileID: ProfileID
    ) async throws -> [WordProgress] {
        try loadedStorage().allProgress(for: profileID)
    }

    public func deleteLearningRecords(for profileID: ProfileID) async throws {
        var candidate = try loadedStorage()
        guard try candidate.deleteLearningRecords(for: profileID) else { return }
        try persist(candidate)
        storage = candidate
    }

    /// Retries loading only after a caller explicitly repairs or restores the
    /// snapshot. A failed file is never deleted or rewritten by this method.
    public func reloadFromDisk() throws {
        storage = nil
        loadFailure = nil
        _ = try loadedStorage()
    }

    private func loadedStorage() throws -> LearningRecordStorage {
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
        } catch let error as LocalLearningRecordRepositoryError {
            loadFailure = error
            throw error
        } catch {
            let wrappedError = LocalLearningRecordRepositoryError.readFailed(
                snapshotURL: snapshotURL,
                details: String(describing: error)
            )
            loadFailure = wrappedError
            throw wrappedError
        }
    }

    private func readStorage() throws -> LearningRecordStorage {
        let data: Data?
        do {
            data = try snapshotFile.readIfPresent()
        } catch {
            throw LocalLearningRecordRepositoryError.readFailed(
                snapshotURL: snapshotURL,
                details: String(describing: error)
            )
        }
        guard let data else { return LearningRecordStorage() }

        let snapshot: LearningRecordSnapshot
        do {
            snapshot = try InspectableSnapshotJSONCodec.makeDecoder().decode(
                LearningRecordSnapshot.self,
                from: data
            )
        } catch {
            throw LocalLearningRecordRepositoryError.invalidJSON(
                snapshotURL: snapshotURL,
                details: String(describing: error)
            )
        }

        guard snapshot.schemaVersion == LearningRecordSnapshot.currentSchemaVersion else {
            throw LocalLearningRecordRepositoryError.unsupportedSchemaVersion(
                snapshotURL: snapshotURL,
                found: snapshot.schemaVersion,
                supported: LearningRecordSnapshot.currentSchemaVersion
            )
        }

        do {
            return try LearningRecordStorage(snapshot: snapshot)
        } catch let error as LearningRecordStorageValidationError {
            throw LocalLearningRecordRepositoryError.invalidSnapshot(
                snapshotURL: snapshotURL,
                issue: error.publicIssue
            )
        }
    }

    private func persist(_ storage: LearningRecordStorage) throws {
        let data: Data
        do {
            data = try InspectableSnapshotJSONCodec.makeEncoder().encode(
                storage.snapshot
            )
        } catch {
            throw LocalLearningRecordRepositoryError.writeFailed(
                snapshotURL: snapshotURL,
                details: "Could not encode snapshot: \(error)"
            )
        }

        do {
            try snapshotFile.write(data)
        } catch {
            throw LocalLearningRecordRepositoryError.writeFailed(
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
}
