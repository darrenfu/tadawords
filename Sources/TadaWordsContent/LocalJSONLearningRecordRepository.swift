import CryptoKit
import Foundation
import TadaWordsDomain

public struct LearningRecordSnapshot: Codable, Equatable, Sendable {
    public static let currentSchemaVersion = 4
    public static let currentProjectionAlgorithmVersion = 2

    public let schemaVersion: Int
    public let projectionAlgorithmVersion: Int
    public let canonicalFactsChecksum: String
    public let attempts: [AttemptEvent]
    public let corrections: [AttemptCorrectionEvent]
    /// Durable routing for a correction whose immutable attempt has not
    /// arrived yet. `AttemptCorrectionEvent` predates family sync and does not
    /// carry a profile ID, so dropping this route would let a later attempt
    /// with the same UUID attach the correction to another child.
    public let correctionRoutes: [AttemptCorrectionRoute]
    /// Durable resolver from pre-business-key prompt UUIDs to the canonical
    /// Profile x mode x normalized-word prompt ID carried by WordPool entries.
    /// Attempt facts remain byte-for-byte immutable.
    public let promptAliases: [WordPromptAlias]
    public let progress: [WordProgress]

    public init(
        schemaVersion: Int = Self.currentSchemaVersion,
        projectionAlgorithmVersion: Int? = nil,
        canonicalFactsChecksum: String = "",
        attempts: [AttemptEvent],
        corrections: [AttemptCorrectionEvent],
        correctionRoutes: [AttemptCorrectionRoute] = [],
        promptAliases: [WordPromptAlias] = [],
        progress: [WordProgress]
    ) {
        self.schemaVersion = schemaVersion
        self.projectionAlgorithmVersion =
            projectionAlgorithmVersion
            ?? (schemaVersion == Self.currentSchemaVersion
                ? Self.currentProjectionAlgorithmVersion
                : 0)
        self.canonicalFactsChecksum = canonicalFactsChecksum
        self.attempts = attempts
        self.corrections = corrections
        self.correctionRoutes = correctionRoutes
        self.promptAliases = promptAliases
        self.progress = progress
    }

    private enum CodingKeys: String, CodingKey {
        case schemaVersion
        case projectionAlgorithmVersion
        case canonicalFactsChecksum
        case attempts
        case corrections
        case correctionRoutes
        case promptAliases
        case progress
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let schemaVersion = try container.decode(
            Int.self,
            forKey: .schemaVersion
        )
        self.init(
            schemaVersion: schemaVersion,
            projectionAlgorithmVersion: try container.decodeIfPresent(
                Int.self,
                forKey: .projectionAlgorithmVersion
            ),
            canonicalFactsChecksum: try container.decodeIfPresent(
                String.self,
                forKey: .canonicalFactsChecksum
            ) ?? "",
            attempts: try container.decode(
                [AttemptEvent].self,
                forKey: .attempts
            ),
            corrections: try container.decode(
                [AttemptCorrectionEvent].self,
                forKey: .corrections
            ),
            correctionRoutes: try container.decodeIfPresent(
                [AttemptCorrectionRoute].self,
                forKey: .correctionRoutes
            ) ?? [],
            promptAliases: try container.decodeIfPresent(
                [WordPromptAlias].self,
                forKey: .promptAliases
            ) ?? [],
            progress: try container.decode(
                [WordProgress].self,
                forKey: .progress
            )
        )
    }
}

public struct WordPromptAlias: Codable, Equatable, Hashable, Sendable {
    public let profileID: ProfileID
    public let learningMode: LearningMode
    public let legacyPromptID: WordPromptID
    public let canonicalPromptID: WordPromptID

    public init(
        profileID: ProfileID,
        learningMode: LearningMode,
        legacyPromptID: WordPromptID,
        canonicalPromptID: WordPromptID
    ) {
        self.profileID = profileID
        self.learningMode = learningMode
        self.legacyPromptID = legacyPromptID
        self.canonicalPromptID = canonicalPromptID
    }
}

public protocol WordPromptAliasRegistering: Sendable {
    func registerPromptAliases(_ aliases: [WordPromptAlias]) async throws
}

public struct AttemptCorrectionRoute: Codable, Equatable, Hashable, Sendable {
    public let correctionID: AttemptCorrectionID
    public let originalAttemptID: AttemptID
    public let profileID: ProfileID
    public let sourceRecord: FamilySyncRecord?

    public init(
        correctionID: AttemptCorrectionID,
        originalAttemptID: AttemptID,
        profileID: ProfileID,
        sourceRecord: FamilySyncRecord? = nil
    ) {
        self.correctionID = correctionID
        self.originalAttemptID = originalAttemptID
        self.profileID = profileID
        self.sourceRecord = sourceRecord
    }
}

/// Sync-only extension that preserves the envelope's profile route while an
/// immutable correction waits for its attempt. Normal app code can continue
/// using `ProfileLearningRecordRepository` unchanged.
public protocol RoutedAttemptCorrectionRepository: Sendable {
    func append(
        _ correction: AttemptCorrectionEvent,
        routedTo profileID: ProfileID,
        sourceRecord: FamilySyncRecord?
    ) async throws

    func correctionRoute(
        for attemptID: AttemptID
    ) async throws -> ProfileID?

    func corrections(
        routedTo profileID: ProfileID
    ) async throws -> [AttemptCorrectionEvent]

    func sourceRecord(
        for correctionID: AttemptCorrectionID
    ) async throws -> FamilySyncRecord?
}

public enum LearningRecordSnapshotValidationIssue: Equatable, Sendable {
    case duplicateAttemptID(AttemptID)
    case duplicateCorrectionID(AttemptCorrectionID)
    case conflictingCorrectionRoute(AttemptID)
    case conflictingPromptAlias(
        profileID: ProfileID,
        learningMode: LearningMode,
        legacyPromptID: WordPromptID
    )
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
    case conflictingAttemptRoute(AttemptID)
    case missingCorrectionRoute(AttemptID)
    case conflictingPromptAlias(
        profileID: ProfileID,
        learningMode: LearningMode,
        legacyPromptID: WordPromptID
    )
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
public actor LocalJSONLearningRecordRepository: ProfileLearningRecordRepository,
    RoutedAttemptCorrectionRepository, WordPromptAliasRegistering
{
    public nonisolated let snapshotURL: URL

    private let fileManager: FileManager
    private let mutationGate: ProfileScopedMutationGate?
    private var storage: LearningRecordStorage?
    private var loadFailure: LocalLearningRecordRepositoryError?

    public init(
        snapshotURL: URL,
        fileManager: FileManager = .default,
        mutationGate: ProfileScopedMutationGate? = nil
    ) {
        self.snapshotURL = snapshotURL
        self.fileManager = fileManager
        self.mutationGate = mutationGate
    }

    public func append(_ event: AttemptEvent) async throws {
        try await withMutationLease(for: event.profileID) {
            var candidate = try loadedStorage()
            guard try candidate.append(event) else { return }
            try candidate.rebuildProgress(affectedBy: event)
            try persist(candidate)
            storage = candidate
        }
    }

    public func append(_ correction: AttemptCorrectionEvent) async throws {
        let profileID =
            try loadedStorage().canonicalAttempts.first {
                $0.id == correction.originalAttemptID
            }?.profileID ?? ProfileScopedMutationLeaseContext.profileID
        guard profileID != nil || mutationGate == nil else {
            // Production repositories share a terminal Profile fence. Without
            // an immutable attempt, explicit sync route, or inherited Profile
            // transaction there is no safe lease to acquire: the attempt may
            // have just been erased. Legacy/in-memory repositories without a
            // gate retain correction-before-attempt compatibility.
            throw LearningRecordRepositoryError.missingCorrectionRoute(
                correction.originalAttemptID
            )
        }
        try await withOptionalMutationLease(for: profileID) {
            var candidate = try loadedStorage()
            let didAppend: Bool
            if let profileID {
                // The local API predates explicit sync routing, but once the
                // immutable attempt is present its Profile is authoritative.
                // Persist that route now so correction-before-attempt and
                // attempt-before-correction converge to identical bytes.
                didAppend = try candidate.append(
                    correction,
                    routedTo: profileID,
                    sourceRecord: nil
                )
            } else {
                // A truly orphaned local correction has no safe Profile to
                // guess. The later immutable attempt fills the route.
                didAppend = try candidate.append(correction)
            }
            guard didAppend else { return }
            try candidate.rebuildProgress(affectedBy: correction)
            try persist(candidate)
            storage = candidate
        }
    }

    public func registerPromptAliases(
        _ aliases: [WordPromptAlias]
    ) async throws {
        guard !aliases.isEmpty else { return }
        let profileIDs = Set(aliases.map(\.profileID))
        try await withMutationLeases(for: profileIDs) {
            var candidate = try loadedStorage()
            guard try candidate.registerPromptAliases(aliases) else { return }
            try candidate.rebuildAllProgress()
            try persist(candidate)
            storage = candidate
        }
    }

    public func append(
        _ correction: AttemptCorrectionEvent,
        routedTo profileID: ProfileID,
        sourceRecord: FamilySyncRecord?
    ) async throws {
        try await withMutationLease(for: profileID) {
            var candidate = try loadedStorage()
            guard
                try candidate.append(
                    correction,
                    routedTo: profileID,
                    sourceRecord: sourceRecord
                )
            else {
                return
            }
            try candidate.rebuildProgress(affectedBy: correction)
            try persist(candidate)
            storage = candidate
        }
    }

    public func correctionRoute(
        for attemptID: AttemptID
    ) async throws -> ProfileID? {
        try await withAllProfilesCommittedRead(mutationGate) {
            try loadedStorage().correctionRoute(for: attemptID)
        }
    }

    public func corrections(
        routedTo profileID: ProfileID
    ) async throws -> [AttemptCorrectionEvent] {
        try await withProfileScopedMutationLease(
            mutationGate,
            for: profileID,
            allowingTerminal: true
        ) {
            try loadedStorage().corrections(routedTo: profileID)
        }
    }

    public func sourceRecord(
        for correctionID: AttemptCorrectionID
    ) async throws -> FamilySyncRecord? {
        try await withAllProfilesCommittedRead(mutationGate) {
            try loadedStorage().sourceRecord(for: correctionID)
        }
    }

    public func attempts(
        for profileID: ProfileID,
        wordPromptID: WordPromptID?
    ) async throws -> [AttemptEvent] {
        try await withProfileScopedMutationLease(
            mutationGate,
            for: profileID,
            allowingTerminal: true
        ) {
            try loadedStorage().attempts(
                for: profileID,
                wordPromptID: wordPromptID
            )
        }
    }

    public func corrections(
        for attemptID: AttemptID
    ) async throws -> [AttemptCorrectionEvent] {
        try await withAllProfilesCommittedRead(mutationGate) {
            try loadedStorage().corrections(for: attemptID)
        }
    }

    public func progress(
        for profileID: ProfileID,
        wordPromptID: WordPromptID
    ) async throws -> WordProgress? {
        try await withProfileScopedMutationLease(
            mutationGate,
            for: profileID,
            allowingTerminal: true
        ) {
            try loadedStorage().progress(
                for: profileID,
                wordPromptID: wordPromptID
            )
        }
    }

    /// Mode-explicit convenience for composition code that already owns a
    /// `LearningMode`; the Domain protocol remains supported unchanged.
    public func progress(
        for profileID: ProfileID,
        wordPromptID: WordPromptID,
        learningMode: LearningMode
    ) async throws -> WordProgress? {
        try await withProfileScopedMutationLease(
            mutationGate,
            for: profileID,
            allowingTerminal: true
        ) {
            try loadedStorage().progress(
                for: profileID,
                wordPromptID: wordPromptID,
                learningMode: learningMode
            )
        }
    }

    public func save(_ progress: WordProgress) async throws {
        try await withMutationLease(for: progress.profileID) {
            var candidate = try loadedStorage()
            guard try candidate.save(progress) else { return }
            try persist(candidate)
            storage = candidate
        }
    }

    public func allProgress(
        for profileID: ProfileID
    ) async throws -> [WordProgress] {
        try await withProfileScopedMutationLease(
            mutationGate,
            for: profileID,
            allowingTerminal: true
        ) {
            try loadedStorage().allProgress(for: profileID)
        }
    }

    public func deleteLearningRecords(for profileID: ProfileID) async throws {
        try await withMutationLease(for: profileID) {
            var candidate = try loadedStorage()
            guard try candidate.deleteLearningRecords(for: profileID) else { return }
            try persist(candidate)
            storage = candidate
        }
    }

    private func withMutationLease(
        for profileID: ProfileID,
        _ operation: () throws -> Void
    ) async throws {
        try await withOptionalMutationLease(for: profileID, operation)
    }

    private func withMutationLeases(
        for profileIDs: Set<ProfileID>,
        _ operation: () throws -> Void
    ) async throws {
        guard let mutationGate else {
            try operation()
            return
        }
        let ids =
            profileIDs
            .filter {
                !ProfileScopedMutationLeaseContext.holdsAllProfiles
                    && ProfileScopedMutationLeaseContext.profileID != $0
            }
            .sorted { $0.description < $1.description }
        var acquiredIDs: [ProfileID] = []
        do {
            for id in ids {
                try await mutationGate.acquire(id)
                acquiredIDs.append(id)
            }
            try operation()
            for id in acquiredIDs.reversed() { await mutationGate.release(id) }
        } catch {
            for id in acquiredIDs.reversed() { await mutationGate.release(id) }
            throw error
        }
    }

    private func withOptionalMutationLease(
        for profileID: ProfileID?,
        _ operation: () throws -> Void
    ) async throws {
        guard let profileID, let mutationGate,
            !ProfileScopedMutationLeaseContext.holdsAllProfiles,
            ProfileScopedMutationLeaseContext.profileID != profileID
        else {
            try operation()
            return
        }
        try await mutationGate.acquire(profileID)
        do {
            try operation()
            await mutationGate.release(profileID)
        } catch {
            await mutationGate.release(profileID)
            throw error
        }
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

        guard
            (1...LearningRecordSnapshot.currentSchemaVersion).contains(
                snapshot.schemaVersion
            )
        else {
            throw LocalLearningRecordRepositoryError.unsupportedSchemaVersion(
                snapshotURL: snapshotURL,
                found: snapshot.schemaVersion,
                supported: LearningRecordSnapshot.currentSchemaVersion
            )
        }

        do {
            let canonicalFactsChecksum = try Self.canonicalFactsChecksum(
                attempts: snapshot.attempts,
                corrections: snapshot.corrections,
                correctionRoutes: snapshot.correctionRoutes,
                promptAliases: snapshot.promptAliases
            )
            var rebuilt = try LearningRecordStorage(
                snapshot: snapshot,
                includeStoredProgress: false
            )
            try rebuilt.rebuildAllProgress()
            let requiresProjectionRebuild =
                snapshot.schemaVersion < LearningRecordSnapshot.currentSchemaVersion
                || snapshot.projectionAlgorithmVersion
                    != LearningRecordSnapshot.currentProjectionAlgorithmVersion
                || snapshot.canonicalFactsChecksum != canonicalFactsChecksum
                || snapshot.progress != rebuilt.snapshot.progress

            if requiresProjectionRebuild {
                try persist(rebuilt)
            }
            return rebuilt
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
            let checksum = try Self.canonicalFactsChecksum(
                attempts: storage.canonicalAttempts,
                corrections: storage.canonicalCorrections,
                correctionRoutes: storage.canonicalCorrectionRoutes,
                promptAliases: storage.canonicalPromptAliases
            )
            data = try InspectableSnapshotJSONCodec.makeEncoder().encode(
                LearningRecordSnapshot(
                    projectionAlgorithmVersion:
                        LearningRecordSnapshot.currentProjectionAlgorithmVersion,
                    canonicalFactsChecksum: checksum,
                    attempts: storage.canonicalAttempts,
                    corrections: storage.canonicalCorrections,
                    correctionRoutes: storage.canonicalCorrectionRoutes,
                    promptAliases: storage.canonicalPromptAliases,
                    progress: storage.snapshot.progress
                )
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

    private static func canonicalFactsChecksum(
        attempts: [AttemptEvent],
        corrections: [AttemptCorrectionEvent],
        correctionRoutes: [AttemptCorrectionRoute],
        promptAliases: [WordPromptAlias]
    ) throws -> String {
        let facts = CanonicalLearningFacts(
            attempts: attempts.sorted(by: attemptOrder),
            corrections: corrections.sorted(by: correctionOrder),
            correctionRoutes: correctionRoutes.sorted(by: correctionRouteOrder),
            promptAliases: promptAliases.sorted(by: promptAliasOrder)
        )
        let data = try InspectableSnapshotJSONCodec.makeEncoder().encode(facts)
        return SHA256.hash(data: data)
            .map { String(format: "%02x", $0) }
            .joined()
    }

    private static func attemptOrder(
        _ left: AttemptEvent,
        _ right: AttemptEvent
    ) -> Bool {
        if left.occurredAt != right.occurredAt {
            return left.occurredAt < right.occurredAt
        }
        return left.id.rawValue.uuidString < right.id.rawValue.uuidString
    }

    private static func correctionOrder(
        _ left: AttemptCorrectionEvent,
        _ right: AttemptCorrectionEvent
    ) -> Bool {
        if left.correctedAt != right.correctedAt {
            return left.correctedAt < right.correctedAt
        }
        return left.id.rawValue.uuidString < right.id.rawValue.uuidString
    }

    private static func correctionRouteOrder(
        _ left: AttemptCorrectionRoute,
        _ right: AttemptCorrectionRoute
    ) -> Bool {
        left.correctionID.rawValue.uuidString
            < right.correctionID.rawValue.uuidString
    }

    private static func promptAliasOrder(
        _ left: WordPromptAlias,
        _ right: WordPromptAlias
    ) -> Bool {
        if left.profileID != right.profileID {
            return left.profileID.description < right.profileID.description
        }
        if left.learningMode != right.learningMode {
            return left.learningMode.rawValue < right.learningMode.rawValue
        }
        return left.legacyPromptID.description < right.legacyPromptID.description
    }

    private struct CanonicalLearningFacts: Encodable {
        let attempts: [AttemptEvent]
        let corrections: [AttemptCorrectionEvent]
        let correctionRoutes: [AttemptCorrectionRoute]
        let promptAliases: [WordPromptAlias]
    }
}
