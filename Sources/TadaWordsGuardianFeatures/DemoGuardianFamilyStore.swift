import Foundation
import TadaWordsContent
import TadaWordsDomain

/// Interactive preview adapter. Production uses `RepositoryGuardianFamilyStore`
/// with the durable local JSON repositories.
public actor DemoGuardianFamilyStore: GuardianFamilyStore {
    private let profileRepository = InMemoryKidProfileRepository()
    private let wordPoolRepository = InMemoryWordPoolRepository()
    private let practiceSettingsRepository = InMemoryPracticeSettingsRepository()
    private let dailyQuestRepository = InMemoryDailyQuestRepository()
    private let learningRecordRepository = InMemoryLearningRecordRepository()
    private let clock: any AppClock
    private var store: RepositoryGuardianFamilyStore?

    public init(clock: any AppClock = SystemAppClock()) {
        self.clock = clock
    }

    public func familySnapshot() async throws -> GuardianFamilySnapshot {
        try await preparedStore().familySnapshot()
    }

    public func selectProfile(
        id: ProfileID
    ) async throws -> GuardianDashboardSnapshot {
        try await preparedStore().selectProfile(id: id)
    }

    public func createProfile(
        from draft: GuardianProfileDraft
    ) async throws -> GuardianDashboardSnapshot {
        try await preparedStore().createProfile(from: draft)
    }

    public func updateProfile(
        id: ProfileID,
        from draft: GuardianProfileDraft
    ) async throws -> GuardianDashboardSnapshot {
        try await preparedStore().updateProfile(id: id, from: draft)
    }

    public func dashboardSnapshot() async throws -> GuardianDashboardSnapshot {
        try await preparedStore().dashboardSnapshot()
    }

    public func importWords(
        _ request: GuardianWordImportRequest
    ) async throws -> GuardianWordImportReport {
        try await preparedStore().importWords(request)
    }

    public func updatePracticeSettings(
        _ settings: ProfilePracticeSettings
    ) async throws -> GuardianDashboardSnapshot {
        try await preparedStore().updatePracticeSettings(settings)
    }

    public func deactivateWord(
        id: WordPromptID,
        learningMode: LearningMode
    ) async throws -> GuardianDashboardSnapshot {
        try await preparedStore().deactivateWord(
            id: id,
            learningMode: learningMode
        )
    }

    public func setWordsActive(
        ids: [WordPromptID],
        learningMode: LearningMode,
        isActive: Bool
    ) async throws -> GuardianDashboardSnapshot {
        try await preparedStore().setWordsActive(
            ids: ids,
            learningMode: learningMode,
            isActive: isActive
        )
    }

    public func report(
        for period: GuardianReportPeriod
    ) async throws -> GuardianLearningReport {
        try await preparedStore().report(for: period)
    }

    public func correctAttempt(
        id: AttemptID,
        to outcome: AttemptOutcome
    ) async throws -> GuardianLearningReport {
        try await preparedStore().correctAttempt(id: id, to: outcome)
    }

    public func deleteProfile(
        id: ProfileID
    ) async throws -> GuardianProfileDeletionResult {
        try await preparedStore().deleteProfile(id: id)
    }

    public func updateVoiceprintStatus(
        profileID: ProfileID,
        status: VoiceprintEnrollmentStatus
    ) async throws -> GuardianDashboardSnapshot {
        try await preparedStore().updateVoiceprintStatus(
            profileID: profileID,
            status: status
        )
    }

    private func preparedStore() async throws -> RepositoryGuardianFamilyStore {
        if let store { return store }

        let profile = KidProfile(
            displayName: "Mia",
            avatar: .cartoonAnimal(assetID: "hare"),
            selectedWorld: .moonpetalKingdom,
            createdAt: Date(timeIntervalSince1970: 0)
        )
        try await profileRepository.save(profile)
        let newStore = RepositoryGuardianFamilyStore(
            profiles: [profile],
            profileRepository: profileRepository,
            wordPoolRepository: wordPoolRepository,
            practiceSettingsRepository: practiceSettingsRepository,
            learningRecordRepository: learningRecordRepository,
            dailyQuestRepository: dailyQuestRepository,
            clock: clock,
            timeZone: .current
        )
        _ = try await newStore.importWords(
            GuardianWordImportRequest(
                rawText: "the and is you can",
                learningMode: .read
            )
        )
        _ = try await newStore.importWords(
            GuardianWordImportRequest(
                rawText: "look play go",
                learningMode: .write
            )
        )
        store = newStore
        return newStore
    }
}
