import CryptoKit
import Foundation
import TadaWordsDomain

/// Stable, device-independent identifiers for a word's business identity.
///
/// A guardian can add the same word independently on two offline devices. The
/// profile, learning mode, and normalized English word are the identity; local
/// insertion order and random UUIDs are not. Namespaced SHA-256 identifiers
/// make those independent inserts address the same sync record without a
/// server round trip.
public enum WordPoolStableIdentity {
    private static let entryNamespace = "com.pawgoo.tadawords.word-pool-entry.v1"
    private static let promptNamespace = "com.pawgoo.tadawords.word-prompt.v1"

    public static func entryID(
        profileID: ProfileID,
        learningMode: LearningMode,
        normalizedText: String
    ) -> WordPoolEntryID {
        WordPoolEntryID(
            rawValue: deterministicUUID(
                namespace: entryNamespace,
                profileID: profileID,
                learningMode: learningMode,
                normalizedText: normalizedText
            )
        )
    }

    public static func promptID(
        profileID: ProfileID,
        learningMode: LearningMode,
        normalizedText: String
    ) -> WordPromptID {
        WordPromptID(
            rawValue: deterministicUUID(
                namespace: promptNamespace,
                profileID: profileID,
                learningMode: learningMode,
                normalizedText: normalizedText
            )
        )
    }

    static func canonicalized(_ entry: WordPoolEntry) throws -> WordPoolEntry {
        let canonicalEntryID = entryID(
            profileID: entry.profileID,
            learningMode: entry.learningMode,
            normalizedText: entry.normalizedText
        )
        let canonicalPromptID = promptID(
            profileID: entry.profileID,
            learningMode: entry.learningMode,
            normalizedText: entry.normalizedText
        )

        let legacyEntryIDs = normalizedAliases(
            entry.legacyEntryIDs + [entry.id],
            excluding: canonicalEntryID
        )
        let legacyPromptIDs = normalizedAliases(
            entry.legacyPromptIDs + [entry.prompt.id],
            excluding: canonicalPromptID
        )
        let prompt = try WordPrompt(
            id: canonicalPromptID,
            learningMode: entry.learningMode,
            text: entry.prompt.displayText,
            audioCue: entry.prompt.audioCue
        )

        return WordPoolEntry(
            id: canonicalEntryID,
            profileID: entry.profileID,
            prompt: prompt,
            addedAt: entry.addedAt,
            source: entry.source,
            isActive: entry.isActive,
            lastQueuedAt: entry.lastQueuedAt,
            positionInLastBatch: entry.positionInLastBatch,
            legacyEntryIDs: legacyEntryIDs,
            legacyPromptIDs: legacyPromptIDs,
            logicalRevision: entry.logicalRevision
        )
    }

    static func normalizedAliases<ID: RawRepresentable & Hashable>(
        _ aliases: [ID],
        excluding canonicalID: ID
    ) -> [ID] where ID.RawValue == UUID {
        Array(Set(aliases).subtracting([canonicalID])).sorted {
            $0.rawValue.uuidString < $1.rawValue.uuidString
        }
    }

    private static func deterministicUUID(
        namespace: String,
        profileID: ProfileID,
        learningMode: LearningMode,
        normalizedText: String
    ) -> UUID {
        let name = [
            namespace,
            profileID.rawValue.uuidString.lowercased(),
            learningMode.rawValue,
            normalizedText,
        ].joined(separator: "\u{001F}")
        var bytes = Array(SHA256.hash(data: Data(name.utf8)).prefix(16))

        // RFC 4122 variant with the version-5 nibble communicates that this is
        // a name-derived identifier. SHA-256 is used for the actual digest.
        bytes[6] = (bytes[6] & 0x0F) | 0x50
        bytes[8] = (bytes[8] & 0x3F) | 0x80

        let hex = bytes.map { String(format: "%02x", $0) }.joined()
        let uuidString =
            "\(hex.prefix(8))-"
            + "\(hex.dropFirst(8).prefix(4))-"
            + "\(hex.dropFirst(12).prefix(4))-"
            + "\(hex.dropFirst(16).prefix(4))-"
            + "\(hex.dropFirst(20).prefix(12))"
        return UUID(uuidString: uuidString)!
    }
}
