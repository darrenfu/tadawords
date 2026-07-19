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
    private let deviceID: String

    public init(deviceID: String = "in-memory-word-pool") {
        self.deviceID = deviceID
    }

    public func upsert(_ drafts: [WordPoolEntryDraft]) async throws
        -> [WordPoolUpsertOutcome]
    {
        try storage.upsert(drafts, deviceID: deviceID)
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
        try storage.setActive(
            isActive,
            entryID: entryID,
            deviceID: deviceID
        )
    }

    public func setActive(
        _ isActive: Bool,
        entryIDs: [WordPoolEntryID]
    ) async throws -> [WordPoolEntry] {
        try storage.setActive(
            isActive,
            entryIDs: entryIDs,
            deviceID: deviceID
        )
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
    private var entryIDByLegacyID: [WordPoolEntryID: WordPoolEntryID]

    init() {
        entriesByID = [:]
        entryIDByIdentity = [:]
        entryIDByLegacyID = [:]
    }

    init(entries: [WordPoolEntry]) throws {
        try Self.validateNoDuplicates(entries)

        var entriesByID: [WordPoolEntryID: WordPoolEntry] = [:]
        var entryIDByIdentity: [WordPoolIdentity: WordPoolEntryID] = [:]
        var entryIDByLegacyID: [WordPoolEntryID: WordPoolEntryID] = [:]

        for sourceEntry in entries {
            let entry = try WordPoolStableIdentity.canonicalized(sourceEntry)
            try Self.index(
                entry,
                entriesByID: &entriesByID,
                entryIDByIdentity: &entryIDByIdentity,
                entryIDByLegacyID: &entryIDByLegacyID
            )
        }

        self.entriesByID = entriesByID
        self.entryIDByIdentity = entryIDByIdentity
        self.entryIDByLegacyID = entryIDByLegacyID
    }

    /// V1 allowed random IDs, so independently created copies of one business
    /// word could coexist after an interrupted/manual merge. Migration folds
    /// those copies into one canonical record and retains every old ID as an
    /// alias. Duplicate IDs that point to different records remain corruption.
    init(migratingLegacyEntries entries: [WordPoolEntry]) throws {
        var sourceEntryByID: [WordPoolEntryID: WordPoolEntry] = [:]
        for entry in entries {
            if let existing = sourceEntryByID[entry.id], existing != entry {
                throw WordPoolStorageValidationError.duplicateEntryID(entry.id)
            }
            sourceEntryByID[entry.id] = entry
        }

        var mergedByIdentity: [WordPoolIdentity: WordPoolEntry] = [:]
        for sourceEntry in sourceEntryByID.values.sorted(by: Self.stableEntryOrder) {
            let canonical = try WordPoolStableIdentity.canonicalized(sourceEntry)
            if let existing = mergedByIdentity[canonical.poolIdentity] {
                mergedByIdentity[canonical.poolIdentity] = try Self.mergingLegacy(
                    existing,
                    canonical
                )
            } else {
                mergedByIdentity[canonical.poolIdentity] = canonical
            }
        }

        try self.init(entries: Array(mergedByIdentity.values))
    }

    var allEntriesInStableOrder: [WordPoolEntry] {
        entriesByID.values.sorted(by: Self.stableEntryOrder)
    }

    mutating func upsert(
        _ drafts: [WordPoolEntryDraft],
        deviceID: String
    ) throws -> [WordPoolUpsertOutcome] {
        try drafts.map { draft in
            let identity = WordPoolIdentity(
                profileID: draft.profileID,
                prompt: draft.prompt
            )

            if let existingID = entryIDByIdentity[identity],
                let existingEntry = entriesByID[existingID]
            {
                let candidate = existingEntry.requeued(
                    at: draft.addedAt,
                    positionInBatch: draft.positionInBatch
                )
                let requeuedEntry =
                    candidate == existingEntry
                    ? existingEntry
                    : candidate.replacingLogicalRevision(
                        .next(
                            after: [existingEntry.logicalRevision],
                            deviceID: deviceID
                        )
                    )
                entriesByID[existingID] = requeuedEntry
                return existingEntry.isActive
                    ? .alreadyActive(requeuedEntry)
                    : .reactivated(requeuedEntry)
            }

            let canonicalPromptID = WordPoolStableIdentity.promptID(
                profileID: draft.profileID,
                learningMode: draft.prompt.learningMode,
                normalizedText: draft.prompt.normalizedText
            )
            let canonicalPrompt = try WordPrompt(
                id: canonicalPromptID,
                learningMode: draft.prompt.learningMode,
                text: draft.prompt.displayText,
                audioCue: draft.prompt.audioCue
            )
            let entry = WordPoolEntry(
                id: WordPoolStableIdentity.entryID(
                    profileID: draft.profileID,
                    learningMode: draft.prompt.learningMode,
                    normalizedText: draft.prompt.normalizedText
                ),
                profileID: draft.profileID,
                prompt: canonicalPrompt,
                addedAt: draft.addedAt,
                source: draft.source,
                positionInLastBatch: draft.positionInBatch,
                logicalRevision: .next(after: [], deviceID: deviceID)
            )
            entriesByID[entry.id] = entry
            entryIDByIdentity[identity] = entry.id
            return .inserted(entry)
        }
    }

    /// Applies an already conflict-resolved sync record while preserving its
    /// stable identifiers. The caller owns revision ordering.
    @discardableResult
    mutating func mergeSynced(
        _ entry: WordPoolEntry,
        logicalRevision: FamilySyncLogicalRevision
    ) throws -> Bool {
        let canonical = try WordPoolStableIdentity.canonicalized(entry)
            .replacingLogicalRevision(logicalRevision)
        if let existingByID = entriesByID[canonical.id] {
            guard existingByID.poolIdentity == canonical.poolIdentity else {
                throw WordPoolStorageValidationError.duplicateEntryID(canonical.id)
            }
            let incomingWithAliases = canonical.replacingAliases(
                legacyEntryIDs: existingByID.legacyEntryIDs
                    + canonical.legacyEntryIDs,
                legacyPromptIDs: existingByID.legacyPromptIDs
                    + canonical.legacyPromptIDs
            )
            let converged = try Self.mergingLegacy(
                existingByID,
                incomingWithAliases
            )
            guard existingByID != converged else { return false }
            try replace(existingByID, with: converged)
            return true
        }
        if let existingID = entryIDByIdentity[canonical.poolIdentity],
            existingID != canonical.id
        {
            throw WordPoolStorageValidationError.duplicatePoolIdentity(
                canonical.poolIdentity
            )
        }
        try Self.index(
            canonical,
            entriesByID: &entriesByID,
            entryIDByIdentity: &entryIDByIdentity,
            entryIDByLegacyID: &entryIDByLegacyID
        )
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
        entryID: WordPoolEntryID,
        deviceID: String
    ) throws -> WordPoolEntry {
        let canonicalID = canonicalEntryID(for: entryID)
        guard let canonicalID, let existingEntry = entriesByID[canonicalID] else {
            throw WordPoolRepositoryError.entryNotFound(entryID)
        }
        guard existingEntry.isActive != isActive else { return existingEntry }
        let updatedEntry = existingEntry.settingActive(isActive)
            .replacingLogicalRevision(
                .next(
                    after: [existingEntry.logicalRevision],
                    deviceID: deviceID
                )
            )
        entriesByID[canonicalID] = updatedEntry
        return updatedEntry
    }

    mutating func setActive(
        _ isActive: Bool,
        entryIDs: [WordPoolEntryID],
        deviceID: String
    ) throws -> [WordPoolEntry] {
        let uniqueRequestedIDs = Array(Set(entryIDs))
        var canonicalIDs: [WordPoolEntryID] = []
        for entryID in uniqueRequestedIDs {
            guard let canonicalID = canonicalEntryID(for: entryID) else {
                throw WordPoolRepositoryError.entryNotFound(entryID)
            }
            canonicalIDs.append(canonicalID)
        }
        return Array(Set(canonicalIDs)).map { entryID in
            let existingEntry = entriesByID[entryID]!
            guard existingEntry.isActive != isActive else {
                return existingEntry
            }
            let updatedEntry = existingEntry.settingActive(isActive)
                .replacingLogicalRevision(
                    .next(
                        after: [existingEntry.logicalRevision],
                        deviceID: deviceID
                    )
                )
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
            for alias in removed.legacyEntryIDs {
                entryIDByLegacyID.removeValue(forKey: alias)
            }
        }
        return true
    }

    func profileID(forEntryID entryID: WordPoolEntryID) -> ProfileID? {
        guard let canonicalID = canonicalEntryID(for: entryID) else {
            return nil
        }
        return entriesByID[canonicalID]?.profileID
    }

    private func canonicalEntryID(
        for entryID: WordPoolEntryID
    ) -> WordPoolEntryID? {
        if entriesByID[entryID] != nil { return entryID }
        return entryIDByLegacyID[entryID]
    }

    private mutating func replace(
        _ existing: WordPoolEntry,
        with replacement: WordPoolEntry
    ) throws {
        entriesByID.removeValue(forKey: existing.id)
        entryIDByIdentity.removeValue(forKey: existing.poolIdentity)
        for alias in existing.legacyEntryIDs {
            entryIDByLegacyID.removeValue(forKey: alias)
        }
        try Self.index(
            replacement,
            entriesByID: &entriesByID,
            entryIDByIdentity: &entryIDByIdentity,
            entryIDByLegacyID: &entryIDByLegacyID
        )
    }

    private static func validateNoDuplicates(
        _ entries: [WordPoolEntry]
    ) throws {
        var entryIDs: Set<WordPoolEntryID> = []
        var identities: Set<WordPoolIdentity> = []
        for entry in entries {
            guard entryIDs.insert(entry.id).inserted else {
                throw WordPoolStorageValidationError.duplicateEntryID(entry.id)
            }
            guard identities.insert(entry.poolIdentity).inserted else {
                throw WordPoolStorageValidationError.duplicatePoolIdentity(
                    entry.poolIdentity
                )
            }
        }
    }

    private static func index(
        _ entry: WordPoolEntry,
        entriesByID: inout [WordPoolEntryID: WordPoolEntry],
        entryIDByIdentity: inout [WordPoolIdentity: WordPoolEntryID],
        entryIDByLegacyID: inout [WordPoolEntryID: WordPoolEntryID]
    ) throws {
        guard entriesByID[entry.id] == nil else {
            throw WordPoolStorageValidationError.duplicateEntryID(entry.id)
        }
        guard entryIDByIdentity[entry.poolIdentity] == nil else {
            throw WordPoolStorageValidationError.duplicatePoolIdentity(
                entry.poolIdentity
            )
        }
        for alias in entry.legacyEntryIDs {
            guard entriesByID[alias] == nil,
                entryIDByLegacyID[alias] == nil
            else {
                throw WordPoolStorageValidationError.duplicateEntryID(alias)
            }
        }
        entriesByID[entry.id] = entry
        entryIDByIdentity[entry.poolIdentity] = entry.id
        for alias in entry.legacyEntryIDs {
            entryIDByLegacyID[alias] = entry.id
        }
    }

    private static func mergingLegacy(
        _ left: WordPoolEntry,
        _ right: WordPoolEntry
    ) throws -> WordPoolEntry {
        precondition(left.poolIdentity == right.poolIdentity)
        let winner: WordPoolEntry
        if left.logicalRevision != right.logicalRevision {
            winner = left.logicalRevision > right.logicalRevision ? left : right
        } else {
            winner = legacyQueueWinner(left, right)
        }
        let provenance = legacyProvenanceWinner(left, right)
        let aliases = left.legacyEntryIDs + right.legacyEntryIDs
        let promptAliases = left.legacyPromptIDs + right.legacyPromptIDs

        return WordPoolEntry(
            id: winner.id,
            profileID: winner.profileID,
            prompt: winner.prompt,
            addedAt: min(left.addedAt, right.addedAt),
            source: provenance.source,
            isActive: winner.isActive,
            lastQueuedAt: winner.lastQueuedAt,
            positionInLastBatch: winner.positionInLastBatch,
            legacyEntryIDs: aliases,
            legacyPromptIDs: promptAliases,
            logicalRevision: max(
                left.logicalRevision,
                right.logicalRevision
            )
        )
    }

    private static func legacyQueueWinner(
        _ left: WordPoolEntry,
        _ right: WordPoolEntry
    ) -> WordPoolEntry {
        if left.lastQueuedAt != right.lastQueuedAt {
            return left.lastQueuedAt > right.lastQueuedAt ? left : right
        }
        if left.addedAt != right.addedAt {
            return left.addedAt > right.addedAt ? left : right
        }
        if left.prompt.displayText != right.prompt.displayText {
            return left.prompt.displayText < right.prompt.displayText
                ? left : right
        }
        let leftAlias = left.legacyEntryIDs.first?.description ?? left.id.description
        let rightAlias = right.legacyEntryIDs.first?.description ?? right.id.description
        return leftAlias < rightAlias ? left : right
    }

    private static func legacyProvenanceWinner(
        _ left: WordPoolEntry,
        _ right: WordPoolEntry
    ) -> WordPoolEntry {
        if left.addedAt != right.addedAt {
            return left.addedAt < right.addedAt ? left : right
        }
        return left.source.rawValue < right.source.rawValue ? left : right
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
