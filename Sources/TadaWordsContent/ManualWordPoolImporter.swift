import Foundation
import TadaWordsDomain

public struct ManualWordPoolImportResult: Sendable {
    public let inserted: [WordPoolEntry]
    public let reactivated: [WordPoolEntry]
    public let alreadyActive: [WordPoolEntry]
    public let rejected: [ManualWordRejection]

    public init(
        inserted: [WordPoolEntry],
        reactivated: [WordPoolEntry],
        alreadyActive: [WordPoolEntry],
        rejected: [ManualWordRejection]
    ) {
        self.inserted = inserted
        self.reactivated = reactivated
        self.alreadyActive = alreadyActive
        self.rejected = rejected
    }
}

/// Coordinates parsing and the repository's atomic de-duplication operation.
public struct ManualWordPoolImporter: Sendable {
    private let repository: any WordPoolRepository
    private let parser: ManualWordBatchParser
    private let audioPreparer: (any TeacherWordAudioPreparing)?

    public init(
        repository: any WordPoolRepository,
        parser: ManualWordBatchParser = ManualWordBatchParser(),
        audioPreparer: (any TeacherWordAudioPreparing)? = nil
    ) {
        self.repository = repository
        self.parser = parser
        self.audioPreparer = audioPreparer
    }

    public func importBatch(
        _ input: String,
        profileID: ProfileID,
        learningMode: LearningMode,
        addedAt: Date,
        source: WordPoolEntrySource = .guardianManual,
        audioCuesByNormalizedWord: [String: WordAudioCue] = [:]
    ) async throws -> ManualWordPoolImportResult {
        let parseResult = parser.parse(
            input,
            learningMode: learningMode,
            audioCuesByNormalizedWord: audioCuesByNormalizedWord
        )
        let drafts = parseResult.accepted.map { parsedWord in
            WordPoolEntryDraft(
                profileID: profileID,
                prompt: parsedWord.prompt,
                addedAt: addedAt,
                source: source,
                positionInBatch: parsedWord.inputPosition
            )
        }
        // Membership may become active once its teacher audio is bundled,
        // atomically cached, or PawGoo explicitly confirms the word is outside
        // the Bella catalog and therefore eligible for on-device Apple speech.
        // Every other preparation failure leaves the pool unchanged.
        try await audioPreparer?.prepare(drafts.map(\.prompt))
        let outcomes = try await repository.upsert(drafts)

        var inserted: [WordPoolEntry] = []
        var reactivated: [WordPoolEntry] = []
        var alreadyActive: [WordPoolEntry] = []
        for outcome in outcomes {
            switch outcome {
            case .inserted(let entry):
                inserted.append(entry)
            case .reactivated(let entry):
                reactivated.append(entry)
            case .alreadyActive(let entry):
                alreadyActive.append(entry)
            }
        }

        return ManualWordPoolImportResult(
            inserted: inserted,
            reactivated: reactivated,
            alreadyActive: alreadyActive,
            rejected: parseResult.rejected
        )
    }
}
