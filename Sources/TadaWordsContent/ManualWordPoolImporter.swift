import Foundation
import TadaWordsDomain

public struct ManualWordPoolImportResult: Sendable {
    public let inserted: [WordPoolEntry]
    public let requeuedExisting: [WordPoolEntry]
    public let rejected: [ManualWordRejection]

    public init(
        inserted: [WordPoolEntry],
        requeuedExisting: [WordPoolEntry],
        rejected: [ManualWordRejection]
    ) {
        self.inserted = inserted
        self.requeuedExisting = requeuedExisting
        self.rejected = rejected
    }
}

/// Coordinates parsing and the repository's atomic de-duplication operation.
public struct ManualWordPoolImporter: Sendable {
    private let repository: any WordPoolRepository
    private let parser: ManualWordBatchParser

    public init(
        repository: any WordPoolRepository,
        parser: ManualWordBatchParser = ManualWordBatchParser()
    ) {
        self.repository = repository
        self.parser = parser
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
        let outcomes = try await repository.upsert(drafts)

        var inserted: [WordPoolEntry] = []
        var requeuedExisting: [WordPoolEntry] = []
        for outcome in outcomes {
            switch outcome {
            case .inserted(let entry):
                inserted.append(entry)
            case .requeuedExisting(let entry):
                requeuedExisting.append(entry)
            }
        }

        return ManualWordPoolImportResult(
            inserted: inserted,
            requeuedExisting: requeuedExisting,
            rejected: parseResult.rejected
        )
    }
}
