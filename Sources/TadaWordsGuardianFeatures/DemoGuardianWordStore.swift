import Foundation
import TadaWordsContent
import TadaWordsDomain

/// Preview composition backed by the same Content importer and repository contracts
/// used by a persistent app adapter.
public actor DemoGuardianWordStore: GuardianWordStore {
    private let profile: KidProfile
    private let importer: ManualWordPoolImporter
    private let productionStore: RepositoryGuardianWordStore
    private var hasSeededPools = false

    public init(
        repository: any WordPoolRepository = InMemoryWordPoolRepository(),
        practiceSettingsRepository: any PracticeSettingsRepository =
            InMemoryPracticeSettingsRepository(),
        clock: any AppClock = SystemAppClock()
    ) {
        self.profile = KidProfile(
            displayName: "Mia",
            avatar: .cartoonAnimal(assetID: "hare"),
            selectedWorld: .moonpetalKingdom,
            createdAt: Date(timeIntervalSince1970: 0)
        )
        self.importer = ManualWordPoolImporter(repository: repository)
        let learningRepository = InMemoryLearningRecordRepository()
        self.productionStore = RepositoryGuardianWordStore(
            profile: profile,
            wordPoolRepository: repository,
            practiceSettingsRepository: practiceSettingsRepository,
            learningRecordRepository: learningRepository,
            clock: clock
        )
    }

    public func dashboardSnapshot() async throws -> GuardianDashboardSnapshot {
        try await seedPoolsIfNeeded()
        return try await productionStore.dashboardSnapshot()
    }

    public func importWords(
        _ request: GuardianWordImportRequest
    ) async throws -> GuardianWordImportReport {
        try await seedPoolsIfNeeded()
        return try await productionStore.importWords(request)
    }

    public func updatePracticeSettings(
        _ settings: ProfilePracticeSettings
    ) async throws -> GuardianDashboardSnapshot {
        try await seedPoolsIfNeeded()
        return try await productionStore.updatePracticeSettings(settings)
    }

    public func deactivateWord(
        id: WordPromptID,
        learningMode: LearningMode
    ) async throws -> GuardianDashboardSnapshot {
        try await seedPoolsIfNeeded()
        return try await productionStore.deactivateWord(
            id: id,
            learningMode: learningMode
        )
    }

    public func setWordsActive(
        ids: [WordPromptID],
        learningMode: LearningMode,
        isActive: Bool
    ) async throws -> GuardianDashboardSnapshot {
        try await seedPoolsIfNeeded()
        return try await productionStore.setWordsActive(
            ids: ids,
            learningMode: learningMode,
            isActive: isActive
        )
    }

    public func report(
        for period: GuardianReportPeriod
    ) async throws -> GuardianLearningReport {
        try await seedPoolsIfNeeded()
        return try await productionStore.report(for: period)
    }

    public func correctAttempt(
        id: AttemptID,
        to outcome: AttemptOutcome
    ) async throws -> GuardianLearningReport {
        try await seedPoolsIfNeeded()
        return try await productionStore.correctAttempt(id: id, to: outcome)
    }

    private func seedPoolsIfNeeded() async throws {
        guard !hasSeededPools else { return }
        let seedDate = profile.createdAt

        _ = try await importer.importBatch(
            "the and is you can",
            profileID: profile.id,
            learningMode: .read,
            addedAt: seedDate
        )
        _ = try await importer.importBatch(
            "look play go",
            profileID: profile.id,
            learningMode: .write,
            addedAt: seedDate
        )
        hasSeededPools = true
    }
}

enum GuardianBatchPreviewCounter {
    static func count(in source: String, learningMode: LearningMode) -> Int {
        let result = ManualWordBatchParser().parse(
            source,
            learningMode: learningMode
        )

        if result.accepted.isEmpty,
            result.rejected.count == 1,
            result.rejected.first?.reason == .emptyBatch
        {
            return 0
        }
        return result.accepted.count + result.rejected.count
    }
}
