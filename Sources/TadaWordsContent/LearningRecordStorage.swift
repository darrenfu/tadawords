import Foundation
import TadaWordsDomain
import TadaWordsLearning

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

struct WordPromptAliasKey: Hashable, Sendable {
    let profileID: ProfileID
    let learningMode: LearningMode
    let legacyPromptID: WordPromptID

    init(_ alias: WordPromptAlias) {
        profileID = alias.profileID
        learningMode = alias.learningMode
        legacyPromptID = alias.legacyPromptID
    }

    init(
        profileID: ProfileID,
        learningMode: LearningMode,
        legacyPromptID: WordPromptID
    ) {
        self.profileID = profileID
        self.learningMode = learningMode
        self.legacyPromptID = legacyPromptID
    }
}

enum LearningRecordStorageValidationError: Error, Equatable, Sendable {
    case duplicateAttemptID(AttemptID)
    case duplicateCorrectionID(AttemptCorrectionID)
    case conflictingCorrectionRoute(AttemptID)
    case conflictingPromptAlias(WordPromptAliasKey)
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
        case .conflictingCorrectionRoute(let attemptID):
            .conflictingCorrectionRoute(attemptID)
        case .conflictingPromptAlias(let key):
            .conflictingPromptAlias(
                profileID: key.profileID,
                learningMode: key.learningMode,
                legacyPromptID: key.legacyPromptID
            )
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
    private var correctionProfileIDByAttemptID: [AttemptID: ProfileID] = [:]
    private var correctionSourceRecordByID: [AttemptCorrectionID: FamilySyncRecord] = [:]
    private var canonicalPromptIDByAlias: [WordPromptAliasKey: WordPromptID] = [:]
    private var progressByKey: [WordProgressKey: WordProgress] = [:]
    private var progressModeByProfileWord: [ProfileWordKey: LearningMode] = [:]

    init() {}

    init(
        snapshot: LearningRecordSnapshot,
        includeStoredProgress: Bool = true
    ) throws {
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

        for route in snapshot.correctionRoutes {
            guard let correction = correctionsByID[route.correctionID],
                correction.originalAttemptID == route.originalAttemptID
            else {
                throw
                    LearningRecordStorageValidationError
                    .conflictingCorrectionRoute(route.originalAttemptID)
            }
            if let existing = correctionProfileIDByAttemptID[
                route.originalAttemptID
            ], existing != route.profileID {
                throw
                    LearningRecordStorageValidationError
                    .conflictingCorrectionRoute(route.originalAttemptID)
            }
            if let attempt = attemptsByID[route.originalAttemptID],
                attempt.profileID != route.profileID
            {
                throw
                    LearningRecordStorageValidationError
                    .conflictingCorrectionRoute(route.originalAttemptID)
            }
            correctionProfileIDByAttemptID[route.originalAttemptID] =
                route.profileID
            if let sourceRecord = route.sourceRecord {
                correctionSourceRecordByID[route.correctionID] = sourceRecord
            }
        }

        // Version 1/2 snapshots did not persist explicit routes. Any
        // correction whose attempt is present can be migrated losslessly.
        for correction in correctionsByID.values {
            if let attempt = attemptsByID[correction.originalAttemptID] {
                correctionProfileIDByAttemptID[correction.originalAttemptID] =
                    attempt.profileID
            }
        }

        for alias in snapshot.promptAliases {
            guard alias.legacyPromptID != alias.canonicalPromptID else {
                continue
            }
            let key = WordPromptAliasKey(alias)
            if let existing = canonicalPromptIDByAlias[key],
                existing != alias.canonicalPromptID
            {
                throw
                    LearningRecordStorageValidationError
                    .conflictingPromptAlias(key)
            }
            canonicalPromptIDByAlias[key] = alias.canonicalPromptID
        }

        if includeStoredProgress {
            for progress in snapshot.progress {
                let key = WordProgressKey(progress)
                guard progressByKey[key] == nil else {
                    throw
                        LearningRecordStorageValidationError
                        .duplicateProgressKey(key)
                }
                try insert(progress)
            }
        }
    }

    var snapshot: LearningRecordSnapshot {
        LearningRecordSnapshot(
            attempts: attemptsByID.values.sorted(by: Self.attemptOrder),
            corrections: correctionsByID.values.sorted(
                by: Self.correctionOrder
            ),
            correctionRoutes: canonicalCorrectionRoutes,
            promptAliases: canonicalPromptAliases,
            progress: progressByKey.values.sorted(by: Self.progressOrder)
        )
    }

    var canonicalAttempts: [AttemptEvent] {
        attemptsByID.values.sorted(by: Self.attemptOrder)
    }

    var canonicalCorrections: [AttemptCorrectionEvent] {
        correctionsByID.values.sorted(by: Self.correctionOrder)
    }

    var canonicalCorrectionRoutes: [AttemptCorrectionRoute] {
        correctionsByID.values.compactMap { correction in
            guard
                let profileID = correctionProfileIDByAttemptID[
                    correction.originalAttemptID
                ]
            else { return nil }
            return AttemptCorrectionRoute(
                correctionID: correction.id,
                originalAttemptID: correction.originalAttemptID,
                profileID: profileID,
                sourceRecord: correctionSourceRecordByID[correction.id]
            )
        }.sorted {
            $0.correctionID.rawValue.uuidString
                < $1.correctionID.rawValue.uuidString
        }
    }

    var canonicalPromptAliases: [WordPromptAlias] {
        canonicalPromptIDByAlias.map { key, canonicalPromptID in
            WordPromptAlias(
                profileID: key.profileID,
                learningMode: key.learningMode,
                legacyPromptID: key.legacyPromptID,
                canonicalPromptID: canonicalPromptID
            )
        }.sorted(by: Self.promptAliasOrder)
    }

    mutating func registerPromptAliases(
        _ aliases: [WordPromptAlias]
    ) throws -> Bool {
        var didChange = false
        for alias in aliases where alias.legacyPromptID != alias.canonicalPromptID {
            let key = WordPromptAliasKey(alias)
            if let existing = canonicalPromptIDByAlias[key] {
                guard existing == alias.canonicalPromptID else {
                    throw LearningRecordRepositoryError.conflictingPromptAlias(
                        profileID: alias.profileID,
                        learningMode: alias.learningMode,
                        legacyPromptID: alias.legacyPromptID
                    )
                }
                continue
            }
            canonicalPromptIDByAlias[key] = alias.canonicalPromptID
            didChange = true
        }
        return didChange
    }

    mutating func append(_ event: AttemptEvent) throws -> Bool {
        if let correctionProfileID = correctionProfileIDByAttemptID[event.id],
            correctionProfileID != event.profileID
        {
            throw LearningRecordRepositoryError.conflictingAttemptRoute(
                event.id
            )
        }
        guard let existingEvent = attemptsByID[event.id] else {
            attemptsByID[event.id] = event
            if correctionsByID.values.contains(where: {
                $0.originalAttemptID == event.id
            }) {
                correctionProfileIDByAttemptID[event.id] = event.profileID
            }
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

    mutating func append(
        _ correction: AttemptCorrectionEvent,
        routedTo profileID: ProfileID,
        sourceRecord: FamilySyncRecord?
    ) throws -> Bool {
        if let attempt = attemptsByID[correction.originalAttemptID],
            attempt.profileID != profileID
        {
            throw LearningRecordRepositoryError.conflictingAttemptRoute(
                correction.originalAttemptID
            )
        }
        if let existingRoute = correctionProfileIDByAttemptID[
            correction.originalAttemptID
        ], existingRoute != profileID {
            throw LearningRecordRepositoryError.conflictingAttemptRoute(
                correction.originalAttemptID
            )
        }
        var didChange = try append(correction)
        if correctionProfileIDByAttemptID[correction.originalAttemptID] == nil {
            didChange = true
        }
        correctionProfileIDByAttemptID[correction.originalAttemptID] = profileID
        if let sourceRecord {
            if let existing = correctionSourceRecordByID[correction.id],
                existing != sourceRecord
            {
                throw LearningRecordRepositoryError.conflictingCorrectionID(
                    correction.id
                )
            }
            if correctionSourceRecordByID[correction.id] == nil {
                didChange = true
            }
            correctionSourceRecordByID[correction.id] = sourceRecord
        }
        return didChange
    }

    func correctionRoute(for attemptID: AttemptID) -> ProfileID? {
        correctionProfileIDByAttemptID[attemptID]
    }

    func sourceRecord(
        for correctionID: AttemptCorrectionID
    ) -> FamilySyncRecord? {
        correctionSourceRecordByID[correctionID]
    }

    /// Rebuilds the one projection touched by a newly appended fact. The
    /// caller applies this to a value-semantic candidate before its atomic
    /// snapshot write, so facts and their read model can never be committed
    /// separately.
    mutating func rebuildProgress(affectedBy event: AttemptEvent) throws {
        try rebuildProgress(
            for: WordProgressKey(
                profileID: event.profileID,
                wordPromptID: canonicalPromptID(
                    profileID: event.profileID,
                    learningMode: event.learningMode,
                    promptID: event.wordPromptID
                ),
                learningMode: event.learningMode
            )
        )
    }

    /// A correction may arrive before its immutable attempt. In that case it
    /// remains a canonical orphan fact and the later attempt append performs
    /// the rebuild. This keeps arrival order irrelevant without guessing a
    /// profile or word identity that the correction does not carry.
    mutating func rebuildProgress(
        affectedBy correction: AttemptCorrectionEvent
    ) throws {
        guard let original = attemptsByID[correction.originalAttemptID] else {
            return
        }
        try rebuildProgress(affectedBy: original)
    }

    /// Reconstructs every rebuildable projection from immutable facts. Used
    /// for snapshot migration and projection-algorithm upgrades.
    mutating func rebuildAllProgress() throws {
        progressByKey.removeAll(keepingCapacity: true)
        progressModeByProfileWord.removeAll(keepingCapacity: true)

        let keys = Set(
            attemptsByID.values.map {
                WordProgressKey(
                    profileID: $0.profileID,
                    wordPromptID: canonicalPromptID(
                        profileID: $0.profileID,
                        learningMode: $0.learningMode,
                        promptID: $0.wordPromptID
                    ),
                    learningMode: $0.learningMode
                )
            }
        ).sorted(by: Self.progressKeyOrder)

        for key in keys {
            try rebuildProgress(for: key)
        }
    }

    func attempts(
        for profileID: ProfileID,
        wordPromptID: WordPromptID?
    ) -> [AttemptEvent] {
        attemptsByID.values
            .filter { attempt in
                guard attempt.profileID == profileID else { return false }
                guard let wordPromptID else { return true }
                let canonicalQuery = canonicalPromptID(
                    profileID: profileID,
                    learningMode: attempt.learningMode,
                    promptID: wordPromptID
                )
                return canonicalPromptID(
                    profileID: attempt.profileID,
                    learningMode: attempt.learningMode,
                    promptID: attempt.wordPromptID
                ) == canonicalQuery
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

    func corrections(
        routedTo profileID: ProfileID
    ) -> [AttemptCorrectionEvent] {
        correctionsByID.values
            .filter {
                correctionProfileIDByAttemptID[$0.originalAttemptID]
                    == profileID
            }
            .sorted(by: Self.correctionOrder)
    }

    func progress(
        for profileID: ProfileID,
        wordPromptID: WordPromptID
    ) -> WordProgress? {
        let candidateIDs = Set(
            LearningMode.allCases.map {
                canonicalPromptID(
                    profileID: profileID,
                    learningMode: $0,
                    promptID: wordPromptID
                )
            }
        )
        let matches = progressByKey.values.filter {
            $0.profileID == profileID
                && candidateIDs.contains($0.wordPromptID)
        }
        guard matches.count <= 1 else { return nil }
        return matches.first
    }

    func progress(
        for profileID: ProfileID,
        wordPromptID: WordPromptID,
        learningMode: LearningMode
    ) -> WordProgress? {
        let canonicalID = canonicalPromptID(
            profileID: profileID,
            learningMode: learningMode,
            promptID: wordPromptID
        )
        return progressByKey[
            WordProgressKey(
                profileID: profileID,
                wordPromptID: canonicalID,
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

    private mutating func rebuildProgress(
        for key: WordProgressKey
    ) throws {
        let attempts = attemptsByID.values.filter {
            $0.profileID == key.profileID
                && canonicalPromptID(
                    profileID: $0.profileID,
                    learningMode: $0.learningMode,
                    promptID: $0.wordPromptID
                ) == key.wordPromptID
                && $0.learningMode == key.learningMode
        }
        guard !attempts.isEmpty else {
            progressByKey.removeValue(forKey: key)
            let profileWordKey = ProfileWordKey(
                profileID: key.profileID,
                wordPromptID: key.wordPromptID
            )
            if progressModeByProfileWord[profileWordKey] == key.learningMode {
                progressModeByProfileWord.removeValue(forKey: profileWordKey)
            }
            return
        }

        let projectionAttempts = attempts.map {
            projectedAttempt($0, canonicalPromptID: key.wordPromptID)
        }
        let rebuilt = try WordProgressReducer().rebuild(
            profileID: key.profileID,
            wordPromptID: key.wordPromptID,
            learningMode: key.learningMode,
            from: projectionAttempts,
            corrections: Array(correctionsByID.values)
        )
        try insert(rebuilt)
    }

    private mutating func insert(_ progress: WordProgress) throws {
        let key = WordProgressKey(progress)
        let profileWordKey = ProfileWordKey(
            profileID: progress.profileID,
            wordPromptID: progress.wordPromptID
        )
        if let existingMode = progressModeByProfileWord[profileWordKey],
            existingMode != progress.learningMode
        {
            throw LearningRecordStorageValidationError.conflictingProgressMode(
                profileWordKey: profileWordKey,
                firstMode: existingMode,
                secondMode: progress.learningMode
            )
        }
        if progressByKey[key] != nil {
            progressByKey[key] = progress
            return
        }
        progressByKey[key] = progress
        progressModeByProfileWord[profileWordKey] = progress.learningMode
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
            if retainedAttemptIDs.contains($0.originalAttemptID) {
                return true
            }
            return correctionProfileIDByAttemptID[$0.originalAttemptID]
                != profileID
        }
        let retainedCorrectionAttemptIDs = Set(
            retainedCorrections.map(\.originalAttemptID)
        )
        let retainedRoutes = current.correctionRoutes.filter {
            retainedCorrectionAttemptIDs.contains($0.originalAttemptID)
                && $0.profileID != profileID
        }
        let retainedProgress = current.progress.filter {
            $0.profileID != profileID
        }
        let retainedPromptAliases = current.promptAliases.filter {
            $0.profileID != profileID
        }
        guard
            retainedAttempts.count != current.attempts.count
                || retainedCorrections.count != current.corrections.count
                || retainedRoutes.count != current.correctionRoutes.count
                || retainedPromptAliases.count != current.promptAliases.count
                || retainedProgress.count != current.progress.count
        else { return false }
        self = try LearningRecordStorage(
            snapshot: LearningRecordSnapshot(
                attempts: retainedAttempts,
                corrections: retainedCorrections,
                correctionRoutes: retainedRoutes,
                promptAliases: retainedPromptAliases,
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

    private static func progressKeyOrder(
        _ left: WordProgressKey,
        _ right: WordProgressKey
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

    private func canonicalPromptID(
        profileID: ProfileID,
        learningMode: LearningMode,
        promptID: WordPromptID
    ) -> WordPromptID {
        canonicalPromptIDByAlias[
            WordPromptAliasKey(
                profileID: profileID,
                learningMode: learningMode,
                legacyPromptID: promptID
            )
        ] ?? promptID
    }

    private func projectedAttempt(
        _ attempt: AttemptEvent,
        canonicalPromptID: WordPromptID
    ) -> AttemptEvent {
        guard attempt.wordPromptID != canonicalPromptID else { return attempt }
        return AttemptEvent(
            id: attempt.id,
            questID: attempt.questID,
            profileID: attempt.profileID,
            wordPromptID: canonicalPromptID,
            learningMode: attempt.learningMode,
            evidence: attempt.evidence,
            outcome: attempt.outcome,
            timing: attempt.timing,
            occurredAt: attempt.occurredAt,
            replayCount: attempt.replayCount,
            recognitionConfidence: attempt.recognitionConfidence,
            paceContext: attempt.paceContext
        )
    }

    private static func promptAliasOrder(
        _ left: WordPromptAlias,
        _ right: WordPromptAlias
    ) -> Bool {
        if left.profileID != right.profileID {
            return left.profileID.description < right.profileID.description
        }
        if left.learningMode != right.learningMode {
            return left.learningMode.rawValue < right.learningMode.rawValue
        }
        return left.legacyPromptID.description < right.legacyPromptID.description
    }
}
