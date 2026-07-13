import TadaWordsDomain

/// Process-local adapter that deliberately shares all mutation, ordering, and
/// conflict semantics with `LocalJSONLearningRecordRepository`.
public actor InMemoryLearningRecordRepository: ProfileLearningRecordRepository {
    private var storage = LearningRecordStorage()

    public init() {}

    public func append(_ event: AttemptEvent) async throws {
        _ = try storage.append(event)
    }

    public func append(_ correction: AttemptCorrectionEvent) async throws {
        _ = try storage.append(correction)
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
