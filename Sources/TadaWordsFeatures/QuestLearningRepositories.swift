import Foundation
import TadaWordsDomain

enum QuestStorageError: Error, Equatable, Sendable {
    case unavailable
}

struct UnavailableAttemptEventRepository: AttemptEventRepository {
    func append(_ event: AttemptEvent) async throws {
        _ = event
        throw QuestStorageError.unavailable
    }

    func append(_ correction: AttemptCorrectionEvent) async throws {
        _ = correction
        throw QuestStorageError.unavailable
    }

    func attempts(
        for profileID: ProfileID,
        wordPromptID: WordPromptID?
    ) async throws -> [AttemptEvent] {
        _ = profileID
        _ = wordPromptID
        throw QuestStorageError.unavailable
    }

    func corrections(for attemptID: AttemptID) async throws -> [AttemptCorrectionEvent] {
        _ = attemptID
        throw QuestStorageError.unavailable
    }
}

struct UnavailableWordProgressRepository: WordProgressRepository {
    func progress(
        for profileID: ProfileID,
        wordPromptID: WordPromptID
    ) async throws -> WordProgress? {
        _ = profileID
        _ = wordPromptID
        throw QuestStorageError.unavailable
    }

    func save(_ progress: WordProgress) async throws {
        _ = progress
        throw QuestStorageError.unavailable
    }
}

struct DemoAppClock: AppClock {
    let now: Date

    init(now: Date = Date(timeIntervalSince1970: 2_000_000_000)) {
        self.now = now
    }
}
