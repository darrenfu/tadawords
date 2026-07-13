import Foundation
import TadaWordsContent
import TadaWordsDomain

enum ContentTestFixture {
    static let profileID = ProfileID(
        rawValue: UUID(uuidString: "61000000-0000-0000-0000-000000000001")!
    )
    static let secondProfileID = ProfileID(
        rawValue: UUID(uuidString: "61000000-0000-0000-0000-000000000002")!
    )
    static let day = Date(timeIntervalSince1970: 2_000_000_000)
    static let utc = TimeZone(secondsFromGMT: 0)!

    static func wordID(_ number: Int) -> WordPromptID {
        WordPromptID(rawValue: uuid(prefix: "62", number: number))
    }

    static func entryID(_ number: Int) -> WordPoolEntryID {
        WordPoolEntryID(rawValue: uuid(prefix: "63", number: number))
    }

    static func prompt(
        _ text: String,
        number: Int,
        mode: LearningMode = .read,
        audioCue: WordAudioCue = .isolated
    ) throws -> WordPrompt {
        try WordPrompt(
            id: wordID(number),
            learningMode: mode,
            text: text,
            audioCue: audioCue
        )
    }

    static func entry(
        _ text: String,
        number: Int,
        profileID: ProfileID = profileID,
        mode: LearningMode = .read,
        addedAt: Date,
        lastQueuedAt: Date? = nil,
        isActive: Bool = true,
        position: Int = 0,
        audioCue: WordAudioCue = .isolated
    ) throws -> WordPoolEntry {
        WordPoolEntry(
            id: entryID(number),
            profileID: profileID,
            prompt: try prompt(
                text,
                number: number,
                mode: mode,
                audioCue: audioCue
            ),
            addedAt: addedAt,
            source: .guardianManual,
            isActive: isActive,
            lastQueuedAt: lastQueuedAt,
            positionInLastBatch: position
        )
    }

    private static func uuid(prefix: String, number: Int) -> UUID {
        let suffix = String(format: "%012X", number)
        return UUID(
            uuidString: "\(prefix)000000-0000-0000-0000-\(suffix)"
        )!
    }
}
