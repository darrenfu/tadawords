import Foundation
import TadaWordsContent
import TadaWordsDomain
import TadaWordsLearning

/// Production Guardian word-store adapter for exactly one child profile.
///
/// This type never seeds content. Guardian attention is derived only from the
/// selected profile's persisted pool, attempts, and progress snapshots.
public actor RepositoryGuardianWordStore: GuardianWordStore {
    private let profile: KidProfile
    private let wordPoolRepository: any WordPoolRepository
    private let practiceSettingsRepository: any PracticeSettingsRepository
    private let learningRecordRepository: (any AttemptEventRepository & WordProgressRepository)?
    private let dailyQuestRepository: any DailyQuestRepository
    private let importer: ManualWordPoolImporter
    private let clock: any AppClock
    private let timeZone: TimeZone
    private let attentionEvaluator = GuardianAttentionEvaluator()

    public init(
        profile: KidProfile,
        wordPoolRepository: any WordPoolRepository,
        practiceSettingsRepository: any PracticeSettingsRepository,
        learningRecordRepository:
            (any AttemptEventRepository & WordProgressRepository)? = nil,
        dailyQuestRepository: any DailyQuestRepository = InMemoryDailyQuestRepository(),
        clock: any AppClock,
        timeZone: TimeZone = .current
    ) {
        self.profile = profile
        self.wordPoolRepository = wordPoolRepository
        self.practiceSettingsRepository = practiceSettingsRepository
        self.learningRecordRepository = learningRecordRepository
        self.dailyQuestRepository = dailyQuestRepository
        self.importer = ManualWordPoolImporter(repository: wordPoolRepository)
        self.clock = clock
        self.timeZone = timeZone
    }

    public func dashboardSnapshot() async throws -> GuardianDashboardSnapshot {
        try await makeSnapshot()
    }

    public func importWords(
        _ request: GuardianWordImportRequest
    ) async throws -> GuardianWordImportReport {
        let result = try await importer.importBatch(
            request.rawText,
            profileID: profile.id,
            learningMode: request.learningMode,
            addedAt: clock.now,
            audioCuesByNormalizedWord: request.spokenContextsByNormalizedWord
                .mapValues { WordAudioCue.contextual($0) }
        )
        return GuardianWordImportReportMapper.report(
            from: result,
            learningMode: request.learningMode
        )
    }

    public func deactivateWord(
        id: WordPromptID,
        learningMode: LearningMode
    ) async throws -> GuardianDashboardSnapshot {
        let currentSnapshot = try await makeSnapshot()
        let activeEntries = try await wordPoolRepository.entries(
            for: profile.id,
            learningMode: learningMode,
            includingInactive: false
        )
        guard let entry = activeEntries.first(where: { $0.prompt.id == id }) else {
            throw GuardianWordStoreError.wordNotFound(id)
        }
        _ = try await wordPoolRepository.setActive(false, entryID: entry.id)
        return GuardianDashboardSnapshot(
            profile: currentSnapshot.profile,
            readPool: currentSnapshot.readPool.filter { prompt in
                learningMode != .read || prompt.id != id
            },
            writePool: currentSnapshot.writePool.filter { prompt in
                learningMode != .write || prompt.id != id
            },
            needsAttention: currentSnapshot.needsAttention.filter {
                $0.prompt.id != id
            },
            practiceSettings: currentSnapshot.practiceSettings,
            questCalendar: currentSnapshot.questCalendar,
            today: currentSnapshot.today,
            todaySummary: currentSnapshot.todaySummary,
            worldProgression: currentSnapshot.worldProgression,
            collections: currentSnapshot.collections
        )
    }

    public func updatePracticeSettings(
        _ settings: ProfilePracticeSettings
    ) async throws -> GuardianDashboardSnapshot {
        try validateProfileID(settings.profileID)
        let currentSnapshot = try await makeSnapshot()
        try await practiceSettingsRepository.save(settings)
        return GuardianDashboardSnapshot(
            profile: currentSnapshot.profile,
            readPool: currentSnapshot.readPool,
            writePool: currentSnapshot.writePool,
            needsAttention: currentSnapshot.needsAttention,
            practiceSettings: settings,
            questCalendar: currentSnapshot.questCalendar,
            today: currentSnapshot.today,
            todaySummary: currentSnapshot.todaySummary,
            worldProgression: currentSnapshot.worldProgression,
            collections: currentSnapshot.collections
        )
    }

    public func report(
        for period: GuardianReportPeriod
    ) async throws -> GuardianLearningReport {
        guard let learningRecordRepository else {
            throw GuardianFamilyStoreError.learningHistoryUnavailable
        }
        async let readEntries = wordPoolRepository.entries(
            for: profile.id,
            learningMode: .read,
            includingInactive: true
        )
        async let writeEntries = wordPoolRepository.entries(
            for: profile.id,
            learningMode: .write,
            includingInactive: true
        )
        async let attempts = learningRecordRepository.attempts(
            for: profile.id,
            wordPromptID: nil
        )
        async let completions = allCompletions()
        let (read, write, loadedAttempts, loadedCompletions) = try await (
            readEntries,
            writeEntries,
            attempts,
            completions
        )
        let corrections = try await allCorrections(
            for: loadedAttempts,
            repository: learningRecordRepository
        )
        return GuardianReportBuilder().makeReport(
            profile: profile,
            period: period,
            now: clock.now,
            prompts: (read + write).map(\.prompt),
            attempts: loadedAttempts,
            corrections: corrections,
            completions: loadedCompletions
        )
    }

    public func correctAttempt(
        id: AttemptID,
        to outcome: AttemptOutcome
    ) async throws -> GuardianLearningReport {
        guard outcome == .correct || outcome == .incorrect,
            let learningRecordRepository
        else {
            throw GuardianFamilyStoreError.learningHistoryUnavailable
        }
        let allAttempts = try await learningRecordRepository.attempts(
            for: profile.id,
            wordPromptID: nil
        )
        guard let original = allAttempts.first(where: { $0.id == id }) else {
            throw GuardianFamilyStoreError.learningHistoryUnavailable
        }
        let correction = AttemptCorrectionEvent(
            originalAttemptID: id,
            correctedOutcome: outcome,
            reason: .guardianOverride,
            correctedAt: clock.now
        )
        try await learningRecordRepository.append(correction)
        let promptAttempts = allAttempts.filter {
            $0.wordPromptID == original.wordPromptID
        }
        let corrections = try await allCorrections(
            for: promptAttempts,
            repository: learningRecordRepository
        )
        let rebuilt = try WordProgressReducer().rebuild(
            profileID: profile.id,
            wordPromptID: original.wordPromptID,
            learningMode: original.learningMode,
            from: promptAttempts,
            corrections: corrections
        )
        try await learningRecordRepository.save(rebuilt)
        return try await report(for: .thirtyDays)
    }

    private func makeSnapshot() async throws -> GuardianDashboardSnapshot {
        async let readEntries = wordPoolRepository.entries(
            for: profile.id,
            learningMode: .read,
            includingInactive: false
        )
        async let writeEntries = wordPoolRepository.entries(
            for: profile.id,
            learningMode: .write,
            includingInactive: false
        )
        async let storedSettings = practiceSettingsRepository.settings(
            for: profile.id
        )
        let month = LocalMonth(date: clock.now, timeZone: timeZone)
        async let monthCompletions = dailyQuestRepository.completions(
            for: profile.id,
            in: month
        )

        let (readPoolEntries, writePoolEntries, fetchedSettings, completions) = try await (
            readEntries,
            writeEntries,
            storedSettings,
            monthCompletions
        )
        let settings =
            fetchedSettings
            ?? ProfilePracticeSettings.defaults(for: profile.id)
        try validateProfileID(settings.profileID)
        let activeEntries = readPoolEntries + writePoolEntries
        let learningEvidence = try await makeLearningEvidence(
            activeEntries: activeEntries
        )
        let allCompletions = try await allCompletions(fallback: completions)
        let rewardGrants = try await allRewardGrants()
        let today = LocalDay(date: clock.now, timeZone: timeZone)
        let catalog = ThemedRewardCatalog()
        let collections = Dictionary(
            uniqueKeysWithValues: WorldTheme.allCases.map { world in
                (
                    world,
                    RewardCollection(
                        profileID: profile.id,
                        world: world,
                        catalogItems: catalog.items(for: world),
                        rewardGrants: rewardGrants
                    )
                )
            }
        )

        return GuardianDashboardSnapshot(
            profile: profile,
            readPool: readPoolEntries.map(\.prompt),
            writePool: writePoolEntries.map(\.prompt),
            needsAttention: learningEvidence.attention,
            practiceSettings: settings,
            questCalendar: DailyQuestMonthSummary(
                profileID: profile.id,
                month: month,
                completions: completions
            ),
            today: today,
            todaySummary: makeTodaySummary(
                readEntries: readPoolEntries,
                writeEntries: writePoolEntries,
                progress: learningEvidence.progress,
                completions: allCompletions,
                today: today
            ),
            worldProgression: WorldProgression(
                profile: profile,
                completions: allCompletions
            ),
            collections: collections
        )
    }

    private func makeLearningEvidence(
        activeEntries: [WordPoolEntry]
    ) async throws -> (attention: [GuardianAttentionItem], progress: [WordProgress]) {
        guard let learningRecordRepository else { return ([], []) }
        let profileID = profile.id

        async let attempts = learningRecordRepository.attempts(
            for: profileID,
            wordPromptID: nil
        )
        let progress = try await withThrowingTaskGroup(
            of: WordProgress?.self,
            returning: [WordProgress].self
        ) { group in
            for entry in activeEntries {
                group.addTask {
                    try await learningRecordRepository.progress(
                        for: profileID,
                        wordPromptID: entry.prompt.id
                    )
                }
            }

            var collected: [WordProgress] = []
            for try await item in group {
                if let item { collected.append(item) }
            }
            return collected
        }

        let loadedAttempts = try await attempts
        let attention = attentionEvaluator.evaluate(
            activePrompts: activeEntries.map(\.prompt),
            progress: progress,
            attempts: loadedAttempts,
            profileID: profileID,
            now: clock.now
        )
        return (attention, progress)
    }

    private func makeTodaySummary(
        readEntries: [WordPoolEntry],
        writeEntries: [WordPoolEntry],
        progress: [WordProgress],
        completions: [DailyQuestCompletion],
        today: LocalDay
    ) -> GuardianTodaySummary {
        let todayCompletions = completions.filter { $0.localDay == today }
        func route(
            _ mode: LearningMode,
            entries: [WordPoolEntry]
        ) -> GuardianTodayRouteSummary {
            let completion = todayCompletions.first {
                $0.learningMode == mode && $0.runKind == .today
            }
            let dueCount = progress.filter {
                $0.learningMode == mode
                    && ($0.memoryState.nextReviewAt.map { $0 <= clock.now } ?? false)
            }.count
            let addedToday = entries.filter {
                LocalDay(date: $0.addedAt, timeZone: timeZone) == today
            }.count
            return GuardianTodayRouteSummary(
                learningMode: mode,
                newWordsAddedToday: addedToday,
                waitingPoolCount: entries.count,
                dueReviewCount: dueCount,
                completedToday: completion != nil,
                points: completion?.points,
                stars: completion?.stars
            )
        }
        return GuardianTodaySummary(
            profileID: profile.id,
            read: route(.read, entries: readEntries),
            write: route(.write, entries: writeEntries),
            completedQuestCount: todayCompletions.count,
            totalPoints: todayCompletions.map(\.points).reduce(0, +),
            totalStars: todayCompletions.map(\.stars.count).reduce(0, +),
            syncState: .thisDeviceOnly
        )
    }

    private func allCompletions(
        fallback: [DailyQuestCompletion] = []
    ) async throws -> [DailyQuestCompletion] {
        guard let history = dailyQuestRepository as? any DailyQuestHistoryRepository else {
            return fallback
        }
        return try await history.allCompletions(for: profile.id)
    }

    private func allRewardGrants() async throws -> [RewardGrant] {
        guard let history = dailyQuestRepository as? any DailyQuestHistoryRepository else {
            return []
        }
        return try await history.rewardGrants(for: profile.id)
    }

    private func allCorrections(
        for attempts: [AttemptEvent],
        repository: any AttemptEventRepository
    ) async throws -> [AttemptCorrectionEvent] {
        try await withThrowingTaskGroup(
            of: [AttemptCorrectionEvent].self,
            returning: [AttemptCorrectionEvent].self
        ) { group in
            for attempt in attempts {
                group.addTask {
                    try await repository.corrections(for: attempt.id)
                }
            }
            var result: [AttemptCorrectionEvent] = []
            for try await corrections in group {
                result.append(contentsOf: corrections)
            }
            return result
        }
    }

    private func validateProfileID(_ profileID: ProfileID) throws {
        guard profileID == profile.id else {
            throw GuardianWordStoreError.profileMismatch(
                expected: profile.id,
                received: profileID
            )
        }
    }
}

private enum GuardianWordImportReportMapper {
    static func report(
        from result: ManualWordPoolImportResult,
        learningMode: LearningMode
    ) -> GuardianWordImportReport {
        var duplicates = result.requeuedExisting.map(\.normalizedText)
        var rejected: [GuardianRejectedWord] = []

        for rejection in result.rejected {
            switch rejection.reason {
            case .duplicateInBatch(let normalizedText):
                duplicates.append(normalizedText)
            default:
                rejected.append(
                    GuardianRejectedWord(
                        sourceText: rejection.originalToken,
                        reason: message(for: rejection.reason)
                    )
                )
            }
        }

        return GuardianWordImportReport(
            learningMode: learningMode,
            accepted: result.inserted.map(\.normalizedText),
            duplicates: duplicates,
            rejected: rejected
        )
    }

    private static func message(
        for reason: ManualWordRejectionReason
    ) -> String {
        switch reason {
        case .emptyBatch:
            "Enter at least one word."
        case .duplicateInBatch:
            "This word appeared more than once in the batch."
        case .invalidPrompt(let error):
            message(for: error)
        case .unexpectedValidationFailure:
            "This word could not be added."
        }
    }

    private static func message(for error: WordPromptValidationError) -> String {
        switch error {
        case .emptyText:
            "Enter at least one word."
        case .tooLong(let maximumCharacterCount):
            "Use no more than \(maximumCharacterCount) characters."
        case .multipleWordsNotSupported:
            "Add one word per entry."
        case .unsupportedCharacters:
            "Use English letters, hyphens, or apostrophes only."
        case .contextRequired:
            "This word needs a spoken context before it can be added."
        case .contextMustContainTarget:
            "The spoken context must include the word."
        case .contextTooLong(let maximumCharacterCount):
            "Keep the spoken context under \(maximumCharacterCount) characters."
        }
    }
}
