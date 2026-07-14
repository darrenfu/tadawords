import Foundation
import TadaWordsDomain

public struct WordPoolEntryDraft: Hashable, Sendable {
    public let profileID: ProfileID
    public let prompt: WordPrompt
    public let addedAt: Date
    public let source: WordPoolEntrySource
    public let positionInBatch: Int

    public init(
        profileID: ProfileID,
        prompt: WordPrompt,
        addedAt: Date,
        source: WordPoolEntrySource,
        positionInBatch: Int
    ) {
        self.profileID = profileID
        self.prompt = prompt
        self.addedAt = addedAt
        self.source = source
        self.positionInBatch = max(0, positionInBatch)
    }
}

public enum WordPoolUpsertOutcome: Hashable, Sendable {
    case inserted(WordPoolEntry)
    case reactivated(WordPoolEntry)
    case alreadyActive(WordPoolEntry)

    public var entry: WordPoolEntry {
        switch self {
        case .inserted(let entry), .reactivated(let entry),
            .alreadyActive(let entry):
            entry
        }
    }
}

public enum WordPoolRepositoryError: Error, Equatable, Sendable {
    case entryNotFound(WordPoolEntryID)
}

public protocol WordPoolRepository: Sendable {
    /// Atomically merges one guardian batch in its original order.
    func upsert(_ drafts: [WordPoolEntryDraft]) async throws
        -> [WordPoolUpsertOutcome]

    func entries(
        for profileID: ProfileID,
        learningMode: LearningMode,
        includingInactive: Bool
    ) async throws -> [WordPoolEntry]

    func setActive(
        _ isActive: Bool,
        entryID: WordPoolEntryID
    ) async throws -> WordPoolEntry

    /// Atomically updates a parent-confirmed set of pool memberships.
    func setActive(
        _ isActive: Bool,
        entryIDs: [WordPoolEntryID]
    ) async throws -> [WordPoolEntry]

    func deleteAll(for profileID: ProfileID) async throws
}

/// Preview/test repository with the same atomic de-duplication boundary a
/// persistent adapter must provide.
public actor InMemoryWordPoolRepository: WordPoolRepository {
    private var storage = WordPoolStorage()

    public init() {}

    public func upsert(_ drafts: [WordPoolEntryDraft]) async throws
        -> [WordPoolUpsertOutcome]
    {
        storage.upsert(drafts)
    }

    public func entries(
        for profileID: ProfileID,
        learningMode: LearningMode,
        includingInactive: Bool = false
    ) async throws -> [WordPoolEntry] {
        storage.entries(
            for: profileID,
            learningMode: learningMode,
            includingInactive: includingInactive
        )
    }

    public func setActive(
        _ isActive: Bool,
        entryID: WordPoolEntryID
    ) async throws -> WordPoolEntry {
        try storage.setActive(isActive, entryID: entryID)
    }

    public func setActive(
        _ isActive: Bool,
        entryIDs: [WordPoolEntryID]
    ) async throws -> [WordPoolEntry] {
        try storage.setActive(isActive, entryIDs: entryIDs)
    }

    public func deleteAll(for profileID: ProfileID) async throws {
        storage.deleteAll(for: profileID)
    }
}

enum WordPoolStorageValidationError: Error, Equatable, Sendable {
    case duplicateEntryID(WordPoolEntryID)
    case duplicatePoolIdentity(WordPoolIdentity)
}

/// Shared value-semantic storage keeps preview and persistent repositories on
/// exactly the same identity, ordering, and mutation rules.
struct WordPoolStorage: Sendable {
    private var entriesByID: [WordPoolEntryID: WordPoolEntry]
    private var entryIDByIdentity: [WordPoolIdentity: WordPoolEntryID]

    init() {
        entriesByID = [:]
        entryIDByIdentity = [:]
    }

    init(entries: [WordPoolEntry]) throws {
        var entriesByID: [WordPoolEntryID: WordPoolEntry] = [:]
        var entryIDByIdentity: [WordPoolIdentity: WordPoolEntryID] = [:]

        for entry in entries {
            guard entriesByID[entry.id] == nil else {
                throw WordPoolStorageValidationError.duplicateEntryID(entry.id)
            }
            guard entryIDByIdentity[entry.poolIdentity] == nil else {
                throw WordPoolStorageValidationError.duplicatePoolIdentity(
                    entry.poolIdentity
                )
            }
            entriesByID[entry.id] = entry
            entryIDByIdentity[entry.poolIdentity] = entry.id
        }

        self.entriesByID = entriesByID
        self.entryIDByIdentity = entryIDByIdentity
    }

    var allEntriesInStableOrder: [WordPoolEntry] {
        entriesByID.values.sorted(by: Self.stableEntryOrder)
    }

    mutating func upsert(
        _ drafts: [WordPoolEntryDraft]
    ) -> [WordPoolUpsertOutcome] {
        drafts.map { draft in
            let identity = WordPoolIdentity(
                profileID: draft.profileID,
                prompt: draft.prompt
            )

            if let existingID = entryIDByIdentity[identity],
                let existingEntry = entriesByID[existingID]
            {
                let requeuedEntry = existingEntry.requeued(
                    at: draft.addedAt,
                    positionInBatch: draft.positionInBatch
                )
                entriesByID[existingID] = requeuedEntry
                return existingEntry.isActive
                    ? .alreadyActive(requeuedEntry)
                    : .reactivated(requeuedEntry)
            }

            let entry = WordPoolEntry(
                profileID: draft.profileID,
                prompt: draft.prompt,
                addedAt: draft.addedAt,
                source: draft.source,
                positionInLastBatch: draft.positionInBatch
            )
            entriesByID[entry.id] = entry
            entryIDByIdentity[identity] = entry.id
            return .inserted(entry)
        }
    }

    /// Applies an already conflict-resolved sync record while preserving its
    /// stable identifiers. The caller owns revision ordering.
    @discardableResult
    mutating func mergeSynced(_ entry: WordPoolEntry) throws -> Bool {
        if let existingByID = entriesByID[entry.id] {
            guard existingByID.poolIdentity == entry.poolIdentity else {
                throw WordPoolStorageValidationError.duplicateEntryID(entry.id)
            }
            guard existingByID != entry else { return false }
            entriesByID[entry.id] = entry
            return true
        }
        if let existingID = entryIDByIdentity[entry.poolIdentity],
            existingID != entry.id
        {
            throw WordPoolStorageValidationError.duplicatePoolIdentity(
                entry.poolIdentity
            )
        }
        entriesByID[entry.id] = entry
        entryIDByIdentity[entry.poolIdentity] = entry.id
        return true
    }

    func entries(
        for profileID: ProfileID,
        learningMode: LearningMode,
        includingInactive: Bool
    ) -> [WordPoolEntry] {
        entriesByID.values
            .filter { entry in
                entry.profileID == profileID
                    && entry.learningMode == learningMode
                    && (includingInactive
                        || (entry.isActive && entry.source == .guardianManual))
            }
            .sorted(by: Self.stableEntryOrder)
    }

    mutating func setActive(
        _ isActive: Bool,
        entryID: WordPoolEntryID
    ) throws -> WordPoolEntry {
        guard let existingEntry = entriesByID[entryID] else {
            throw WordPoolRepositoryError.entryNotFound(entryID)
        }
        let updatedEntry = existingEntry.settingActive(isActive)
        entriesByID[entryID] = updatedEntry
        return updatedEntry
    }

    mutating func setActive(
        _ isActive: Bool,
        entryIDs: [WordPoolEntryID]
    ) throws -> [WordPoolEntry] {
        let uniqueIDs = Array(Set(entryIDs))
        for entryID in uniqueIDs where entriesByID[entryID] == nil {
            throw WordPoolRepositoryError.entryNotFound(entryID)
        }
        return uniqueIDs.map { entryID in
            let updatedEntry = entriesByID[entryID]!.settingActive(isActive)
            entriesByID[entryID] = updatedEntry
            return updatedEntry
        }
    }

    @discardableResult
    mutating func deleteAll(for profileID: ProfileID) -> Bool {
        let matchingIDs = entriesByID.values
            .filter { $0.profileID == profileID }
            .map(\.id)
        guard !matchingIDs.isEmpty else { return false }
        for id in matchingIDs {
            guard let removed = entriesByID.removeValue(forKey: id) else {
                continue
            }
            entryIDByIdentity.removeValue(forKey: removed.poolIdentity)
        }
        return true
    }

    private static func stableEntryOrder(
        _ left: WordPoolEntry,
        _ right: WordPoolEntry
    ) -> Bool {
        if left.lastQueuedAt != right.lastQueuedAt {
            return left.lastQueuedAt > right.lastQueuedAt
        }
        if left.positionInLastBatch != right.positionInLastBatch {
            return left.positionInLastBatch < right.positionInLastBatch
        }
        if left.normalizedText != right.normalizedText {
            return left.normalizedText < right.normalizedText
        }
        return left.id.rawValue.uuidString < right.id.rawValue.uuidString
    }
}
