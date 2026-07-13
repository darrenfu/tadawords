import Foundation

public protocol AttemptEventRepository: Sendable {
    func append(_ event: AttemptEvent) async throws
    func append(_ correction: AttemptCorrectionEvent) async throws

    func attempts(
        for profileID: ProfileID,
        wordPromptID: WordPromptID?
    ) async throws -> [AttemptEvent]

    func corrections(for attemptID: AttemptID) async throws -> [AttemptCorrectionEvent]
}

public protocol WordProgressRepository: Sendable {
    func progress(
        for profileID: ProfileID,
        wordPromptID: WordPromptID
    ) async throws -> WordProgress?

    func save(_ progress: WordProgress) async throws
}

public protocol ProfileLearningRecordRepository: AttemptEventRepository,
    WordProgressRepository
{
    func allProgress(for profileID: ProfileID) async throws -> [WordProgress]

    func deleteLearningRecords(for profileID: ProfileID) async throws
}

extension ProfileLearningRecordRepository {
    public func allProgress(for profileID: ProfileID) async throws -> [WordProgress] {
        _ = profileID
        return []
    }
}

public protocol AppClock: Sendable {
    var now: Date { get }
}

public struct SystemAppClock: AppClock {
    public init() {}

    public var now: Date { Date() }
}
