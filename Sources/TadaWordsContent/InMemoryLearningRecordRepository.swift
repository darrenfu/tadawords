import TadaWordsDomain

/// Process-local adapter that deliberately shares all mutation, ordering, and
/// conflict semantics with `LocalJSONLearningRecordRepository`.
public actor InMemoryLearningRecordRepository: ProfileLearningRecordRepository,
    RoutedAttemptCorrectionRepository, WordPromptAliasRegistering
{
    private var storage = LearningRecordStorage()

    public init() {}

    public func append(_ event: AttemptEvent) async throws {
        var candidate = storage
        guard try candidate.append(event) else { return }
        try candidate.rebuildProgress(affectedBy: event)
        storage = candidate
    }

    public func append(_ correction: AttemptCorrectionEvent) async throws {
        var candidate = storage
        let didAppend: Bool
        if let profileID = candidate.canonicalAttempts.first(where: {
            $0.id == correction.originalAttemptID
        })?.profileID {
            didAppend = try candidate.append(
                correction,
                routedTo: profileID,
                sourceRecord: nil
            )
        } else {
            didAppend = try candidate.append(correction)
        }
        guard didAppend else { return }
        try candidate.rebuildProgress(affectedBy: correction)
        storage = candidate
    }

    public func registerPromptAliases(
        _ aliases: [WordPromptAlias]
    ) async throws {
        var candidate = storage
        guard try candidate.registerPromptAliases(aliases) else { return }
        try candidate.rebuildAllProgress()
        storage = candidate
    }

    public func append(
        _ correction: AttemptCorrectionEvent,
        routedTo profileID: ProfileID,
        sourceRecord: FamilySyncRecord?
    ) async throws {
        var candidate = storage
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
        storage = candidate
    }

    public func correctionRoute(
        for attemptID: AttemptID
    ) async throws -> ProfileID? {
        storage.correctionRoute(for: attemptID)
    }

    public func corrections(
        routedTo profileID: ProfileID
    ) async throws -> [AttemptCorrectionEvent] {
        storage.corrections(routedTo: profileID)
    }

    public func sourceRecord(
        for correctionID: AttemptCorrectionID
    ) async throws -> FamilySyncRecord? {
        storage.sourceRecord(for: correctionID)
    }

    public func attempts(
        for profileID: ProfileID,
        wordPromptID: WordPromptID?
    ) async throws -> [AttemptEvent] {
        storage.attempts(
            for: profileID,
            wordPromptID: wordPromptID
        )
    }

    public func corrections(
        for attemptID: AttemptID
    ) async throws -> [AttemptCorrectionEvent] {
        storage.corrections(for: attemptID)
    }

    public func progress(
        for profileID: ProfileID,
        wordPromptID: WordPromptID
    ) async throws -> WordProgress? {
        storage.progress(
            for: profileID,
            wordPromptID: wordPromptID
        )
    }

    public func progress(
        for profileID: ProfileID,
        wordPromptID: WordPromptID,
        learningMode: LearningMode
    ) async throws -> WordProgress? {
        storage.progress(
            for: profileID,
            wordPromptID: wordPromptID,
            learningMode: learningMode
        )
    }

    public func save(_ progress: WordProgress) async throws {
        _ = try storage.save(progress)
    }

    public func allProgress(
        for profileID: ProfileID
    ) async throws -> [WordProgress] {
        storage.allProgress(for: profileID)
    }

    public func deleteLearningRecords(for profileID: ProfileID) async throws {
        _ = try storage.deleteLearningRecords(for: profileID)
    }
}
