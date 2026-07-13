import Foundation
import TadaWordsDomain

struct WordProgressKey: Hashable, Sendable {
    let profileID: ProfileID
    let wordPromptID: WordPromptID
    let learningMode: LearningMode

    init(_ progress: WordProgress) {
        profileID = progress.profileID
        wordPromptID = progress.wordPromptID
        learningMode = progress.learningMode
    }

    init(
        profileID: ProfileID,
        wordPromptID: WordPromptID,
        learningMode: LearningMode
    ) {
        self.profileID = profileID
        self.wordPromptID = wordPromptID
        self.learningMode = learningMode
    }
}

struct ProfileWordKey: Hashable, Sendable {
    let profileID: ProfileID
    let wordPromptID: WordPromptID
}

enum LearningRecordStorageValidationError: Error, Equatable, Sendable {
    case duplicateAttemptID(AttemptID)
    case duplicateCorrectionID(AttemptCorrectionID)
    case duplicateProgressKey(WordProgressKey)
    case conflictingProgressMode(
        profileWordKey: ProfileWordKey,
        firstMode: LearningMode,
        secondMode: LearningMode
    )

    var publicIssue: LearningRecordSnapshotValidationIssue {
        switch self {
        case .duplicateAttemptID(let attemptID):
            .duplicateAttemptID(attemptID)
        case .duplicateCorrectionID(let correctionID):
            .duplicateCorrectionID(correctionID)
        case .duplicateProgressKey(let key):
            .duplicateProgressKey(
                profileID: key.profileID,
                wordPromptID: key.wordPromptID,
                learningMode: key.learningMode
            )
        case .conflictingProgressMode(let key, let firstMode, let secondMode):
            .conflictingProgressMode(
                profileID: key.profileID,
                wordPromptID: key.wordPromptID,
                firstMode: firstMode,
                secondMode: secondMode
            )
        }
    }
}

struct LearningRecordStorage: Sendable {
    private var attemptsByID: [AttemptID: AttemptEvent] = [:]
    private var correctionsByID: [AttemptCorrectionID: AttemptCorrectionEvent] = [:]
    private var progressByKey: [WordProgressKey: WordProgress] = [:]
    private var progressModeByProfileWord: [ProfileWordKey: LearningMode] = [:]

    init() {}

    init(snapshot: LearningRecordSnapshot) throws {
        for attempt in snapshot.attempts {
            guard attemptsByID[attempt.id] == nil else {
                throw LearningRecordStorageValidationError.duplicateAttemptID(
                    attempt.id
                )
            }
            attemptsByID[attempt.id] = attempt
        }

        for correction in snapshot.corrections {
            guard correctionsByID[correction.id] == nil else {
                throw LearningRecordStorageValidationError.duplicateCorrectionID(
                    correction.id
                )
            }
            correctionsByID[correction.id] = correction
        }

        for progress in snapshot.progress {
            let key = WordProgressKey(progress)
            let profileWordKey = ProfileWordKey(
                profileID: progress.profileID,
                wordPromptID: progress.wordPromptID
            )
            guard progressByKey[key] == nil else {
                throw LearningRecordStorageValidationError.duplicateProgressKey(
                    key
                )
            }
            if let existingMode = progressModeByProfileWord[profileWordKey],
                existingMode != progress.learningMode
            {
                throw LearningRecordStorageValidationError.conflictingProgressMode(
                    profileWordKey: profileWordKey,
                    firstMode: existingMode,
                    secondMode: progress.learningMode
                )
            }
            progressByKey[key] = progress
            progressModeByProfileWord[profileWordKey] = progress.learningMode
        }
    }

    var snapshot: LearningRecordSnapshot {
        LearningRecordSnapshot(
            attempts: attemptsByID.values.sorted(by: Self.attemptOrder),
            corrections: correctionsByID.values.sorted(
                by: Self.correctionOrder
            ),
            progress: progressByKey.values.sorted(by: Self.progressOrder)
        )
    }

    mutating func append(_ event: AttemptEvent) throws -> Bool {
        guard let existingEvent = attemptsByID[event.id] else {
            attemptsByID[event.id] = event
            return true
        }
        guard existingEvent == event else {
            throw LearningRecordRepositoryError.conflictingAttemptID(event.id)
        }
        return false
    }

    mutating func append(
        _ correction: AttemptCorrectionEvent
    ) throws -> Bool {
        guard let existingCorrection = correctionsByID[correction.id] else {
            correctionsByID[correction.id] = correction
            return true
        }
        guard existingCorrection == correction else {
            throw LearningRecordRepositoryError.conflictingCorrectionID(
                correction.id
            )
        }
        return false
    }

    func attempts(
        for profileID: ProfileID,
        wordPromptID: WordPromptID?
    ) -> [AttemptEvent] {
        attemptsByID.values
            .filter { attempt in
                guard attempt.profileID == profileID else { return false }
                guard let wordPromptID else { return true }
                return attempt.wordPromptID == wordPromptID
            }
            .sorted(by: Self.attemptOrder)
    }

    func corrections(
        for attemptID: AttemptID
    ) -> [AttemptCorrectionEvent] {
        correctionsByID.values
            .filter { $0.originalAttemptID == attemptID }
            .sorted(by: Self.correctionOrder)
    }

    func progress(
        for profileID: ProfileID,
        wordPromptID: WordPromptID
    ) -> WordProgress? {
        let profileWordKey = ProfileWordKey(
            profileID: profileID,
            wordPromptID: wordPromptID
        )
        guard let learningMode = progressModeByProfileWord[profileWordKey] else {
            return nil
        }
        return progressByKey[
            WordProgressKey(
                profileID: profileID,
                wordPromptID: wordPromptID,
                learningMode: learningMode
            )
        ]
    }

    func progress(
        for profileID: ProfileID,
        wordPromptID: WordPromptID,
        learningMode: LearningMode
    ) -> WordProgress? {
        progressByKey[
            WordProgressKey(
                profileID: profileID,
                wordPromptID: wordPromptID,
                learningMode: learningMode
            )
        ]
    }

    func allProgress(for profileID: ProfileID) -> [WordProgress] {
        progressByKey.values
            .filter { $0.profileID == profileID }
            .sorted(by: Self.progressOrder)
    }

    mutating func save(_ progress: WordProgress) throws -> Bool {
        let key = WordProgressKey(progress)
        let profileWordKey = ProfileWordKey(
            profileID: progress.profileID,
            wordPromptID: progress.wordPromptID
        )
        if let existingMode = progressModeByProfileWord[profileWordKey],
            existingMode != progress.learningMode
        {
            throw LearningRecordRepositoryError.conflictingProgressMode(
                profileID: progress.profileID,
                wordPromptID: progress.wordPromptID,
                existingMode: existingMode,
                incomingMode: progress.learningMode
            )
        }
        guard progressByKey[key] != progress else { return false }
        progressByKey[key] = progress
        progressModeByProfileWord[profileWordKey] = progress.learningMode
        return true
    }

    @discardableResult
    mutating func deleteLearningRecords(
        for profileID: ProfileID
    ) throws -> Bool {
        let current = snapshot
        let retainedAttempts = current.attempts.filter {
            $0.profileID != profileID
        }
        let retainedAttemptIDs = Set(retainedAttempts.map(\.id))
        let retainedCorrections = current.corrections.filter {
            retainedAttemptIDs.contains($0.originalAttemptID)
        }
        let retainedProgress = current.progress.filter {
            $0.profileID != profileID
        }
        guard
            retainedAttempts.count != current.attempts.count
                || retainedProgress.count != current.progress.count
        else { return false }
        self = try LearningRecordStorage(
            snapshot: LearningRecordSnapshot(
                attempts: retainedAttempts,
                corrections: retainedCorrections,
                progress: retainedProgress
            )
        )
        return true
    }

    private static func attemptOrder(
        _ left: AttemptEvent,
        _ right: AttemptEvent
    ) -> Bool {
        if left.occurredAt != right.occurredAt {
            return left.occurredAt < right.occurredAt
        }
        return left.id.rawValue.uuidString < right.id.rawValue.uuidString
    }

    private static func correctionOrder(
        _ left: AttemptCorrectionEvent,
        _ right: AttemptCorrectionEvent
    ) -> Bool {
        if left.correctedAt != right.correctedAt {
            return left.correctedAt < right.correctedAt
        }
        return left.id.rawValue.uuidString < right.id.rawValue.uuidString
    }

    private static func progressOrder(
        _ left: WordProgress,
        _ right: WordProgress
    ) -> Bool {
        if left.profileID != right.profileID {
            return left.profileID.rawValue.uuidString
                < right.profileID.rawValue.uuidString
        }
        if left.wordPromptID != right.wordPromptID {
            return left.wordPromptID.rawValue.uuidString
                < right.wordPromptID.rawValue.uuidString
        }
        return left.learningMode.rawValue < right.learningMode.rawValue
    }
}
