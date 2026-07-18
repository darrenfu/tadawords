import Foundation
import TadaWordsDomain

public struct WordPoolEntryID: RawRepresentable, Codable, Hashable, Sendable,
    CustomStringConvertible
{
    public let rawValue: UUID

    public init(rawValue: UUID = UUID()) {
        self.rawValue = rawValue
    }

    public var description: String { rawValue.uuidString }
}

public enum WordPoolEntrySource: String, Codable, CaseIterable, Hashable,
    Sendable
{
    case guardianManual
    case gradeRecommendation
}

/// One stable membership record in a profile's Read or Write pool.
///
/// Re-entering a word refreshes `lastQueuedAt` but retains `id`, the prompt ID,
/// original `addedAt`, and source provenance.
public struct WordPoolEntry: Codable, Hashable, Sendable {
    public static let legacyLogicalRevision = FamilySyncLogicalRevision(
        counter: 0,
        deviceID: "legacy-word-pool"
    )

    public let id: WordPoolEntryID
    public let profileID: ProfileID
    public let prompt: WordPrompt
    public let addedAt: Date
    public let source: WordPoolEntrySource
    public let isActive: Bool
    public let lastQueuedAt: Date
    public let positionInLastBatch: Int
    /// Random IDs written before stable business identity shipped. Keeping
    /// aliases lets learning history and queued UI actions resolve old IDs
    /// after the local snapshot migrates.
    public let legacyEntryIDs: [WordPoolEntryID]
    public let legacyPromptIDs: [WordPromptID]
    /// Durable conflict authority for mutable membership state. Wall-clock
    /// queue dates remain presentation/order inputs and never override this
    /// revision during sync.
    public let logicalRevision: FamilySyncLogicalRevision

    public init(
        id: WordPoolEntryID = WordPoolEntryID(),
        profileID: ProfileID,
        prompt: WordPrompt,
        addedAt: Date,
        source: WordPoolEntrySource,
        isActive: Bool = true,
        lastQueuedAt: Date? = nil,
        positionInLastBatch: Int = 0,
        legacyEntryIDs: [WordPoolEntryID] = [],
        legacyPromptIDs: [WordPromptID] = [],
        logicalRevision: FamilySyncLogicalRevision = Self.legacyLogicalRevision
    ) {
        self.id = id
        self.profileID = profileID
        self.prompt = prompt
        self.addedAt = addedAt
        self.source = source
        self.isActive = isActive
        self.lastQueuedAt = max(addedAt, lastQueuedAt ?? addedAt)
        self.positionInLastBatch = max(0, positionInLastBatch)
        self.legacyEntryIDs = Self.normalizedAliases(
            legacyEntryIDs,
            excluding: id
        )
        self.legacyPromptIDs = Self.normalizedAliases(
            legacyPromptIDs,
            excluding: prompt.id
        )
        self.logicalRevision = logicalRevision
    }

    public var learningMode: LearningMode { prompt.learningMode }
    public var normalizedText: String { prompt.normalizedText }

    public var poolIdentity: WordPoolIdentity {
        WordPoolIdentity(
            profileID: profileID,
            prompt: prompt
        )
    }

    public func resolves(entryID candidate: WordPoolEntryID) -> Bool {
        candidate == id || legacyEntryIDs.contains(candidate)
    }

    public func resolves(promptID candidate: WordPromptID) -> Bool {
        candidate == prompt.id || legacyPromptIDs.contains(candidate)
    }

    private enum CodingKeys: String, CodingKey {
        case id
        case profileID
        case prompt
        case addedAt
        case source
        case isActive
        case lastQueuedAt
        case positionInLastBatch
        case legacyEntryIDs
        case legacyPromptIDs
        case logicalRevision
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            id: try container.decode(WordPoolEntryID.self, forKey: .id),
            profileID: try container.decode(ProfileID.self, forKey: .profileID),
            prompt: try container.decode(WordPrompt.self, forKey: .prompt),
            addedAt: try container.decode(Date.self, forKey: .addedAt),
            source: try container.decode(WordPoolEntrySource.self, forKey: .source),
            isActive: try container.decode(Bool.self, forKey: .isActive),
            lastQueuedAt: try container.decode(Date.self, forKey: .lastQueuedAt),
            positionInLastBatch: try container.decode(
                Int.self,
                forKey: .positionInLastBatch
            ),
            legacyEntryIDs: try container.decodeIfPresent(
                [WordPoolEntryID].self,
                forKey: .legacyEntryIDs
            ) ?? [],
            legacyPromptIDs: try container.decodeIfPresent(
                [WordPromptID].self,
                forKey: .legacyPromptIDs
            ) ?? [],
            logicalRevision: try container.decodeIfPresent(
                FamilySyncLogicalRevision.self,
                forKey: .logicalRevision
            ) ?? Self.legacyLogicalRevision
        )
    }

    func requeued(at date: Date, positionInBatch: Int) -> WordPoolEntry {
        let shouldRefreshQueue = date >= lastQueuedAt
        return WordPoolEntry(
            id: id,
            profileID: profileID,
            prompt: prompt,
            addedAt: addedAt,
            source: source,
            isActive: true,
            lastQueuedAt: shouldRefreshQueue ? date : lastQueuedAt,
            positionInLastBatch: shouldRefreshQueue
                ? positionInBatch
                : positionInLastBatch,
            legacyEntryIDs: legacyEntryIDs,
            legacyPromptIDs: legacyPromptIDs,
            logicalRevision: logicalRevision
        )
    }

    func settingActive(_ isActive: Bool) -> WordPoolEntry {
        WordPoolEntry(
            id: id,
            profileID: profileID,
            prompt: prompt,
            addedAt: addedAt,
            source: source,
            isActive: isActive,
            lastQueuedAt: lastQueuedAt,
            positionInLastBatch: positionInLastBatch,
            legacyEntryIDs: legacyEntryIDs,
            legacyPromptIDs: legacyPromptIDs,
            logicalRevision: logicalRevision
        )
    }

    func replacingAliases(
        legacyEntryIDs: [WordPoolEntryID],
        legacyPromptIDs: [WordPromptID]
    ) -> WordPoolEntry {
        WordPoolEntry(
            id: id,
            profileID: profileID,
            prompt: prompt,
            addedAt: addedAt,
            source: source,
            isActive: isActive,
            lastQueuedAt: lastQueuedAt,
            positionInLastBatch: positionInLastBatch,
            legacyEntryIDs: legacyEntryIDs,
            legacyPromptIDs: legacyPromptIDs,
            logicalRevision: logicalRevision
        )
    }

    func replacingLogicalRevision(
        _ revision: FamilySyncLogicalRevision
    ) -> WordPoolEntry {
        WordPoolEntry(
            id: id,
            profileID: profileID,
            prompt: prompt,
            addedAt: addedAt,
            source: source,
            isActive: isActive,
            lastQueuedAt: lastQueuedAt,
            positionInLastBatch: positionInLastBatch,
            legacyEntryIDs: legacyEntryIDs,
            legacyPromptIDs: legacyPromptIDs,
            logicalRevision: revision
        )
    }

    private static func normalizedAliases<ID: RawRepresentable & Hashable>(
        _ aliases: [ID],
        excluding canonicalID: ID
    ) -> [ID] where ID.RawValue == UUID {
        Array(Set(aliases).subtracting([canonicalID])).sorted {
            $0.rawValue.uuidString < $1.rawValue.uuidString
        }
    }
}

public struct WordPoolIdentity: Hashable, Sendable {
    public let profileID: ProfileID
    public let learningMode: LearningMode
    public let normalizedText: String

    public init(
        profileID: ProfileID,
        prompt: WordPrompt
    ) {
        self.profileID = profileID
        self.learningMode = prompt.learningMode
        self.normalizedText = prompt.normalizedText
    }
}
