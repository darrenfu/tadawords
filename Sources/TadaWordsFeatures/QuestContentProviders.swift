import Foundation
import TadaWordsContent
import TadaWordsDomain
import TadaWordsLearning

protocol QuestContentProviding: Sendable {
    /// This is configuration readiness only. Pool emptiness and storage health
    /// are discovered by `prepareQuest`, at the explicit loading boundary.
    func availability(for mode: LearningMode, profile: KidProfile) -> QuestAvailability

    /// Prepares one stable, presentation-ordered daily quest for a child.
    func prepareQuest(
        for mode: LearningMode,
        profile: KidProfile
    ) async throws -> PreparedQuest

    /// Rehydrates a persisted Daily Quest plan without running New-word
    /// selection again. Inactive pool entries remain available for the rest of
    /// the day so a guardian edit cannot silently replace today's plan.
    func prompts(
        for plan: QuestPlan,
        profile: KidProfile
    ) async throws -> [WordPrompt]

    /// Selects a reward-free freestyle batch. Implementations should prefer
    /// active pool words outside the canonical Today plan, then gracefully
    /// fall back to a replay when the pool has no alternative words.
    func prepareFreestyleQuest(
        for mode: LearningMode,
        profile: KidProfile,
        excluding wordIDs: Set<WordPromptID>
    ) async throws -> PreparedQuest
}

extension QuestContentProviding {
    func prepareFreestyleQuest(
        for mode: LearningMode,
        profile: KidProfile,
        excluding wordIDs: Set<WordPromptID>
    ) async throws -> PreparedQuest {
        let prepared = try await prepareQuest(for: mode, profile: profile)
        let alternatives = prepared.orderedPrompts.filter {
            !wordIDs.contains($0.id)
        }
        return prepared.asFreestyle(
            prompts: alternatives.isEmpty ? prepared.orderedPrompts : alternatives
        )
    }
}

struct PreparedQuest: Equatable, Sendable {
    let plan: QuestPlan
    let orderedPrompts: [WordPrompt]
    let emergencyAfter: TimeInterval
    let deviceClass: DeviceClass
    let personalPaceBands: [PersonalPaceBand]
    let interfacePreferences: PracticeInterfacePreferences

    init(
        plan: QuestPlan,
        orderedPrompts: [WordPrompt],
        emergencyAfter: TimeInterval,
        deviceClass: DeviceClass = .tablet,
        personalPaceBands: [PersonalPaceBand] = [],
        interfacePreferences: PracticeInterfacePreferences = .default
    ) {
        self.plan = plan
        self.orderedPrompts = orderedPrompts
        self.emergencyAfter = emergencyAfter
        self.deviceClass = deviceClass
        self.personalPaceBands = personalPaceBands
        self.interfacePreferences = interfacePreferences
    }

    func asFreestyle(prompts: [WordPrompt]) -> PreparedQuest {
        let uniquePrompts = prompts.reduce(into: [WordPrompt]()) { result, prompt in
            guard !result.contains(where: { $0.id == prompt.id }) else { return }
            result.append(prompt)
        }
        let freestylePlan = QuestPlan(
            profileID: plan.profileID,
            configuration: plan.configuration,
            reviewWordIDs: uniquePrompts.map(\.id),
            newWordIDs: [],
            createdAt: plan.createdAt
        )
        return PreparedQuest(
            plan: freestylePlan,
            orderedPrompts: uniquePrompts,
            emergencyAfter: emergencyAfter,
            deviceClass: deviceClass,
            personalPaceBands: personalPaceBands,
            interfacePreferences: interfacePreferences
        )
    }
}

enum QuestContentError: Error, Equatable, Sendable {
    case emptyPool
    case noReviewDue
    case inconsistentContent
}

/// Production-safe default. Missing repositories block practice rather than
/// fabricating prompts, progress, or rewards.
struct UnavailableQuestContentProvider: QuestContentProviding {
    func availability(for mode: LearningMode, profile: KidProfile) -> QuestAvailability {
        _ = mode
        _ = profile
        return .blocked(.storageUnavailable)
    }

    func prepareQuest(
        for mode: LearningMode,
        profile: KidProfile
    ) async throws -> PreparedQuest {
        _ = mode
        _ = profile
        throw QuestContentError.emptyPool
    }

    func prompts(
        for plan: QuestPlan,
        profile: KidProfile
    ) async throws -> [WordPrompt] {
        _ = plan
        _ = profile
        throw QuestContentError.emptyPool
    }
}

/// Composes the persistent pool and progress boundaries with the existing
/// daily selector and planner. New words are shown before due review words;
/// protected review work still owns capacity according to `QuestPlanner`.
struct RepositoryBackedQuestContentProvider: QuestContentProviding {
    private let wordPoolRepository: any WordPoolRepository
    private let wordProgressRepository: any WordProgressRepository
    private let practiceSettingsRepository: any PracticeSettingsRepository
    private let attemptEventRepository: (any AttemptEventRepository)?
    private let deviceClass: DeviceClass
    private let clock: any AppClock
    private let dailyProvider: DailyQuestContentProvider
    private let planner: QuestPlanner
    private let reviewRanker: ReviewPriorityRanker
    private let gradeWordRecommender: (any GradeWordRecommending)?
    private let teacherAudioPreparer: (any TeacherWordAudioPreparing)?

    init(
        wordPoolRepository: any WordPoolRepository,
        wordProgressRepository: any WordProgressRepository,
        practiceSettingsRepository: any PracticeSettingsRepository,
        attemptEventRepository: (any AttemptEventRepository)? = nil,
        gradeWordRecommender: (any GradeWordRecommending)? = nil,
        teacherAudioPreparer: (any TeacherWordAudioPreparing)? = nil,
        deviceClass: DeviceClass = .tablet,
        clock: any AppClock,
        timeZone: TimeZone
    ) {
        self.wordPoolRepository = wordPoolRepository
        self.wordProgressRepository = wordProgressRepository
        self.practiceSettingsRepository = practiceSettingsRepository
        self.attemptEventRepository = attemptEventRepository
        self.gradeWordRecommender = gradeWordRecommender
        self.teacherAudioPreparer = teacherAudioPreparer
        self.deviceClass = deviceClass
        self.clock = clock
        self.dailyProvider = DailyQuestContentProvider(
            repository: wordPoolRepository,
            timeZone: timeZone
        )
        self.planner = QuestPlanner()
        self.reviewRanker = ReviewPriorityRanker()
    }

    func availability(for mode: LearningMode, profile: KidProfile) -> QuestAvailability {
        _ = mode
        _ = profile
        return .available
    }

    func prepareQuest(
        for mode: LearningMode,
        profile: KidProfile
    ) async throws -> PreparedQuest {
        let storedSettings = try await practiceSettingsRepository.settings(
            for: profile.id
        )
        let settings = storedSettings ?? .defaults(for: profile.id)
        guard settings.profileID == profile.id else {
            throw QuestContentError.inconsistentContent
        }
        let modeConfiguration = settings.configuration(for: mode)
        let configuration = modeConfiguration.questConfiguration
        let now = clock.now
        try await gradeWordRecommender?.refillIfNeeded(
            profile: profile,
            learningMode: mode,
            settings: settings
        )
        let entries = try await activeEntries(for: profile.id, mode: mode)
        guard !entries.isEmpty else {
            throw QuestContentError.emptyPool
        }

        let progressByWordID = try await loadProgress(
            for: entries,
            profileID: profile.id,
            mode: mode
        )
        let previouslyStartedWordIDs = Set(
            progressByWordID.values
                .filter(\.hasIndependentStart)
                .map(\.wordPromptID)
        )
        let rankedDueReviewWordIDs = rankedDueReviewWordIDs(
            entries: entries,
            progressByWordID: progressByWordID,
            asOf: now
        )
        let selectedDueReviewWordIDs = Array(
            rankedDueReviewWordIDs.prefix(configuration.reviewWordLimit)
        )
        let deferredDueReviewWordIDs = Array(
            rankedDueReviewWordIDs.dropFirst(selectedDueReviewWordIDs.count)
        )
        let supplementalReviewWordIDs = rankedSupplementalReviewWordIDs(
            entries: entries,
            progressByWordID: progressByWordID,
            asOf: now
        )
        let planningInput = try await dailyProvider.planningInput(
            for: DailyQuestContentRequest(
                profileID: profile.id,
                configuration: configuration,
                date: now,
                previouslyStartedWordIDs: previouslyStartedWordIDs,
                dueReviewWordIDs: selectedDueReviewWordIDs,
                supplementalReviewWordIDs: supplementalReviewWordIDs
            )
        )
        let plannedQuest = planner.makePlan(
            profileID: profile.id,
            configuration: configuration,
            input: planningInput,
            createdAt: now
        )
        let plan = QuestPlan(
            id: plannedQuest.id,
            profileID: plannedQuest.profileID,
            configuration: plannedQuest.configuration,
            reviewWordIDs: plannedQuest.reviewWordIDs,
            newWordIDs: plannedQuest.newWordIDs,
            deferredReviewWordIDs: deferredDueReviewWordIDs
                + plannedQuest.deferredReviewWordIDs,
            createdAt: plannedQuest.createdAt
        )
        let prompts = try await prompts(for: plan, profile: profile)
        let personalPaceBands = try await loadPersonalPaceBands(
            profileID: profile.id,
            mode: mode
        )

        guard !prompts.isEmpty else {
            throw QuestContentError.noReviewDue
        }
        return PreparedQuest(
            plan: plan,
            orderedPrompts: prompts,
            emergencyAfter: TimeInterval(
                modeConfiguration.emergencyAfterSeconds
            ),
            deviceClass: deviceClass,
            personalPaceBands: personalPaceBands,
            interfacePreferences: settings.interface
        )
    }

    func prompts(
        for plan: QuestPlan,
        profile: KidProfile
    ) async throws -> [WordPrompt] {
        guard plan.profileID == profile.id else {
            throw QuestContentError.inconsistentContent
        }
        let mode = plan.configuration.learningMode
        let entries = try await wordPoolRepository.entries(
            for: profile.id,
            learningMode: mode,
            includingInactive: true
        )
        let promptsByID = try promptLookup(from: entries)
        return try plan.orderedItems.map { item in
            guard let prompt = promptsByID[item.wordPromptID],
                prompt.learningMode == mode
            else {
                throw QuestContentError.inconsistentContent
            }
            return prompt
        }
    }

    func prepareFreestyleQuest(
        for mode: LearningMode,
        profile: KidProfile,
        excluding wordIDs: Set<WordPromptID>
    ) async throws -> PreparedQuest {
        let storedSettings = try await practiceSettingsRepository.settings(
            for: profile.id
        )
        let settings = storedSettings ?? .defaults(for: profile.id)
        guard settings.profileID == profile.id else {
            throw QuestContentError.inconsistentContent
        }
        let modeConfiguration = settings.configuration(for: mode)
        try await gradeWordRecommender?.refillIfNeeded(
            profile: profile,
            learningMode: mode,
            settings: settings
        )
        let entries = try await activeEntries(for: profile.id, mode: mode)
        guard !entries.isEmpty else { throw QuestContentError.emptyPool }
        let batchSize = max(
            1,
            modeConfiguration.questConfiguration.attentionBudget
        )
        let alternatives = entries.filter { !wordIDs.contains($0.prompt.id) }
        let selectedEntries = Array(
            (alternatives.isEmpty ? entries : alternatives).prefix(batchSize)
        )
        let selected = selectedEntries.map(\.prompt)
        guard !selected.isEmpty else { throw QuestContentError.emptyPool }
        let plan = QuestPlan(
            profileID: profile.id,
            configuration: modeConfiguration.questConfiguration,
            reviewWordIDs: selected.map(\.id),
            newWordIDs: [],
            createdAt: clock.now
        )
        return PreparedQuest(
            plan: plan,
            orderedPrompts: selected,
            emergencyAfter: TimeInterval(
                modeConfiguration.emergencyAfterSeconds
            ),
            deviceClass: deviceClass,
            personalPaceBands: try await loadPersonalPaceBands(
                profileID: profile.id,
                mode: mode
            ),
            interfacePreferences: settings.interface
        )
    }

    private func activeEntries(
        for profileID: ProfileID,
        mode: LearningMode
    ) async throws -> [WordPoolEntry] {
        try await wordPoolRepository.entries(
            for: profileID,
            learningMode: mode,
            includingInactive: false
        )
    }

    private func loadPersonalPaceBands(
        profileID: ProfileID,
        mode: LearningMode
    ) async throws -> [PersonalPaceBand] {
        guard let attemptEventRepository else { return [] }
        let attempts = try await attemptEventRepository.attempts(
            for: profileID,
            wordPromptID: nil
        ).filter { attempt in
            attempt.learningMode == mode
                && attempt.evidence.countsTowardAccuracy
                && attempt.paceContext?.learningMode == mode
        }

        var corrections: [AttemptCorrectionEvent] = []
        for attempt in attempts {
            corrections.append(
                contentsOf: try await attemptEventRepository.corrections(
                    for: attempt.id
                )
            )
        }

        let measurements = EffectiveAttemptResolver().resolve(
            attempts,
            corrections: corrections
        ).compactMap { attempt -> PaceMeasurement? in
            guard attempt.outcome.isCorrect,
                let context = attempt.original.paceContext
            else {
                return nil
            }
            return AttemptPaceMeasurementExtractor().measurement(
                from: attempt.original,
                context: context
            )
        }
        return PersonalPaceBaselineBuilder().bands(from: measurements)
    }

    private func loadProgress(
        for entries: [WordPoolEntry],
        profileID: ProfileID,
        mode: LearningMode
    ) async throws -> [WordPromptID: WordProgress] {
        var progressByWordID: [WordPromptID: WordProgress] = [:]
        for entry in entries {
            guard
                let progress = try await wordProgressRepository.progress(
                    for: profileID,
                    wordPromptID: entry.prompt.id
                )
            else {
                continue
            }
            guard progress.profileID == profileID else {
                throw QuestContentError.inconsistentContent
            }
            guard progress.wordPromptID == entry.prompt.id else {
                throw QuestContentError.inconsistentContent
            }
            guard progress.learningMode == mode else {
                throw QuestContentError.inconsistentContent
            }
            progressByWordID[entry.prompt.id] = progress
        }
        return progressByWordID
    }

    private func rankedDueReviewWordIDs(
        entries: [WordPoolEntry],
        progressByWordID: [WordPromptID: WordProgress],
        asOf now: Date
    ) -> [WordPromptID] {
        let paceBaseline = secondsPerCharacterBaseline(
            entries: entries,
            progressByWordID: progressByWordID
        )
        let candidates = entries.compactMap { entry -> ReviewPriorityCandidate? in
            guard let progress = progressByWordID[entry.prompt.id] else {
                return nil
            }
            guard let nextReviewAt = progress.memoryState.nextReviewAt else {
                return nil
            }
            guard nextReviewAt <= now else {
                return nil
            }

            return ReviewPriorityCandidate(
                wordPromptID: entry.prompt.id,
                nextReviewAt: nextReviewAt,
                predictedRecall: progress.memoryState.predictedRecall(at: now),
                lapseCount: progress.memoryState.lapseCount,
                independentIncorrectRate: 1 - (progress.firstIndependentAccuracy ?? 1),
                paceRatio: paceRatio(
                    for: progress,
                    wordLength: entry.prompt.normalizedText.count,
                    baseline: paceBaseline
                ),
                replayCount: progress.totalReplayCount,
                helpCount: progress.helpedAttemptCount,
                uncertainCount: progress.uncertainAttemptCount,
                guardianRequeuedAt: guardianRequeueDate(
                    entry: entry,
                    progress: progress
                )
            )
        }
        return reviewRanker.ranked(candidates, asOf: now).map(\.wordPromptID)
    }

    /// A not-yet-due word can still fill an otherwise unused Review slot when
    /// immutable evidence shows a lapse, Help, replay, uncertainty, or a pace
    /// meaningfully above this child's own route baseline. Due work always
    /// remains protected by `QuestPlanner`.
    private func rankedSupplementalReviewWordIDs(
        entries: [WordPoolEntry],
        progressByWordID: [WordPromptID: WordProgress],
        asOf now: Date
    ) -> [WordPromptID] {
        let paceBaseline = secondsPerCharacterBaseline(
            entries: entries,
            progressByWordID: progressByWordID
        )
        let candidates = entries.compactMap { entry -> ReviewPriorityCandidate? in
            guard let progress = progressByWordID[entry.prompt.id] else {
                return nil
            }
            let nextReviewAt = progress.memoryState.nextReviewAt ?? .distantFuture
            guard nextReviewAt > now else { return nil }
            let paceRatio = paceRatio(
                for: progress,
                wordLength: entry.prompt.normalizedText.count,
                baseline: paceBaseline
            )
            let incorrectRate = 1 - (progress.firstIndependentAccuracy ?? 1)
            let hasWeakSignal =
                progress.memoryState.lapseCount > 0
                || incorrectRate > 0
                || progress.totalReplayCount > 0
                || progress.helpedAttemptCount > 0
                || progress.uncertainAttemptCount > 0
                || (paceRatio ?? 1) > 1.25
                || guardianRequeueDate(entry: entry, progress: progress) != nil
            guard hasWeakSignal else { return nil }

            return ReviewPriorityCandidate(
                wordPromptID: entry.prompt.id,
                nextReviewAt: nextReviewAt,
                predictedRecall: progress.memoryState.predictedRecall(at: now),
                lapseCount: progress.memoryState.lapseCount,
                independentIncorrectRate: incorrectRate,
                paceRatio: paceRatio,
                replayCount: progress.totalReplayCount,
                helpCount: progress.helpedAttemptCount,
                uncertainCount: progress.uncertainAttemptCount,
                guardianRequeuedAt: guardianRequeueDate(
                    entry: entry,
                    progress: progress
                )
            )
        }
        return reviewRanker.ranked(candidates, asOf: now).map(\.wordPromptID)
    }

    private func guardianRequeueDate(
        entry: WordPoolEntry,
        progress: WordProgress
    ) -> Date? {
        guard let lastEncounterAt = progress.lastEncounterAt,
            entry.lastQueuedAt > lastEncounterAt
        else {
            return nil
        }
        return entry.lastQueuedAt
    }

    /// Uses the child's own route history as the pace baseline. Normalizing by
    /// word length keeps long write prompts from looking weak solely because
    /// they contain more strokes.
    private func secondsPerCharacterBaseline(
        entries: [WordPoolEntry],
        progressByWordID: [WordPromptID: WordProgress]
    ) -> Double? {
        let measurements = entries.compactMap { entry -> Double? in
            guard
                let meanTime = progressByWordID[entry.prompt.id]?
                    .firstIndependentMeanResponseTime,
                meanTime.seconds > 0
            else {
                return nil
            }
            return meanTime.seconds / Double(max(1, entry.prompt.normalizedText.count))
        }.sorted()
        guard !measurements.isEmpty else { return nil }
        let midpoint = measurements.count / 2
        if measurements.count.isMultiple(of: 2) {
            return (measurements[midpoint - 1] + measurements[midpoint]) / 2
        }
        return measurements[midpoint]
    }

    private func paceRatio(
        for progress: WordProgress,
        wordLength: Int,
        baseline: Double?
    ) -> Double? {
        guard
            let meanTime = progress.firstIndependentMeanResponseTime,
            let baseline,
            baseline > 0
        else {
            return nil
        }
        let secondsPerCharacter = meanTime.seconds / Double(max(1, wordLength))
        return secondsPerCharacter / baseline
    }

    private func promptLookup(
        from entries: [WordPoolEntry]
    ) throws -> [WordPromptID: WordPrompt] {
        var promptsByID: [WordPromptID: WordPrompt] = [:]
        for entry in entries {
            guard promptsByID.updateValue(entry.prompt, forKey: entry.prompt.id) == nil else {
                throw QuestContentError.inconsistentContent
            }
        }
        return promptsByID
    }
}

/// Deterministic in-memory fixture used only by Preview and Debug composition.
actor DemoQuestContentProvider: QuestContentProviding {
    private let wordPoolRepository: InMemoryWordPoolRepository
    private let practiceSettingsRepository: InMemoryPracticeSettingsRepository
    private let repositoryProvider: RepositoryBackedQuestContentProvider
    private let clock: any AppClock
    private var seededProfileIDs: Set<ProfileID> = []

    init(
        wordPoolRepository: InMemoryWordPoolRepository,
        wordProgressRepository: any WordProgressRepository,
        practiceSettingsRepository: InMemoryPracticeSettingsRepository,
        attemptEventRepository: (any AttemptEventRepository)? = nil,
        deviceClass: DeviceClass = .tablet,
        clock: any AppClock,
        timeZone: TimeZone
    ) {
        self.wordPoolRepository = wordPoolRepository
        self.practiceSettingsRepository = practiceSettingsRepository
        self.repositoryProvider = RepositoryBackedQuestContentProvider(
            wordPoolRepository: wordPoolRepository,
            wordProgressRepository: wordProgressRepository,
            practiceSettingsRepository: practiceSettingsRepository,
            attemptEventRepository: attemptEventRepository,
            deviceClass: deviceClass,
            clock: clock,
            timeZone: timeZone
        )
        self.clock = clock
    }

    nonisolated func availability(
        for mode: LearningMode,
        profile: KidProfile
    ) -> QuestAvailability {
        _ = mode
        _ = profile
        return .available
    }

    func prepareQuest(
        for mode: LearningMode,
        profile: KidProfile
    ) async throws -> PreparedQuest {
        try await seedIfNeeded(for: profile.id)
        return try await repositoryProvider.prepareQuest(for: mode, profile: profile)
    }

    func prompts(
        for plan: QuestPlan,
        profile: KidProfile
    ) async throws -> [WordPrompt] {
        try await seedIfNeeded(for: profile.id)
        return try await repositoryProvider.prompts(for: plan, profile: profile)
    }

    private func seedIfNeeded(for profileID: ProfileID) async throws {
        guard !seededProfileIDs.contains(profileID) else { return }

        if try await practiceSettingsRepository.settings(for: profileID) == nil {
            try await practiceSettingsRepository.save(
                .defaults(for: profileID)
            )
        }

        let readPrompts = try Self.makePrompts(
            mode: .read,
            words: ["the", "look", "see", "come", "here"],
            identifierPrefix: "71000000"
        )
        let writePrompts = try Self.makePrompts(
            mode: .write,
            words: ["look", "play", "jump"],
            identifierPrefix: "72000000"
        )
        _ = try await wordPoolRepository.upsert(
            Self.drafts(
                prompts: readPrompts + writePrompts,
                profileID: profileID,
                addedAt: clock.now
            )
        )
        seededProfileIDs.insert(profileID)
    }

    private static func drafts(
        prompts: [WordPrompt],
        profileID: ProfileID,
        addedAt: Date
    ) -> [WordPoolEntryDraft] {
        prompts.enumerated().map { index, prompt in
            WordPoolEntryDraft(
                profileID: profileID,
                prompt: prompt,
                addedAt: addedAt,
                source: .guardianManual,
                positionInBatch: index
            )
        }
    }

    private static func makePrompts(
        mode: LearningMode,
        words: [String],
        identifierPrefix: String
    ) throws -> [WordPrompt] {
        try words.enumerated().map { index, word in
            guard
                let identifier = UUID(
                    uuidString:
                        "\(identifierPrefix)-0000-0000-0000-\(String(format: "%012X", index + 1))"
                )
            else {
                throw QuestContentError.inconsistentContent
            }
            return try WordPrompt(
                id: WordPromptID(rawValue: identifier),
                learningMode: mode,
                text: word
            )
        }
    }
}

extension WordProgress {
    fileprivate var hasIndependentStart: Bool {
        firstIndependentAttemptCount > 0
            || memoryState.lastIndependentAttemptAt != nil
            || lastEncounterAt != nil
    }
}

struct SilentAudioPromptService: AudioPromptService {
    func play(_ prompt: WordPrompt, for profileID: ProfileID) async throws {
        _ = prompt
        _ = profileID
        // Preview owns no platform audio framework. The iOS app injects one.
    }
}
