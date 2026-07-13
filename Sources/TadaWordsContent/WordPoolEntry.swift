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
    public let id: WordPoolEntryID
    public let profileID: ProfileID
    public let prompt: WordPrompt
    public let addedAt: Date
    public let source: WordPoolEntrySource
    public let isActive: Bool
    public let lastQueuedAt: Date
    public let positionInLastBatch: Int

    public init(
        id: WordPoolEntryID = WordPoolEntryID(),
        profileID: ProfileID,
        prompt: WordPrompt,
        addedAt: Date,
        source: WordPoolEntrySource,
        isActive: Bool = true,
        lastQueuedAt: Date? = nil,
        positionInLastBatch: Int = 0
    ) {
        self.id = id
        self.profileID = profileID
        self.prompt = prompt
        self.addedAt = addedAt
        self.source = source
        self.isActive = isActive
        self.lastQueuedAt = max(addedAt, lastQueuedAt ?? addedAt)
        self.positionInLastBatch = max(0, positionInLastBatch)
    }

    public var learningMode: LearningMode { prompt.learningMode }
    public var normalizedText: String { prompt.normalizedText }

    public var poolIdentity: WordPoolIdentity {
        WordPoolIdentity(
            profileID: profileID,
            prompt: prompt
        )
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
            )
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
                : positionInLastBatch
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
            positionInLastBatch: positionInLastBatch
        )
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
