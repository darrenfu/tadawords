import Foundation
import TadaWordsContent
import TadaWordsDomain
import XCTest

@testable import TadaWordsAppShell

final class ProductionNotificationReconcilerTests: XCTestCase {
    func testRuntimeReconcileRefreshesCompletionAndSyncFailureWithoutPrompting()
        async throws
    {
        let profile = KidProfile(
            displayName: "Mia",
            avatar: .cartoonAnimal(assetID: "hare"),
            selectedWorld: .moonpetalKingdom,
            createdAt: now
        )
        let profiles = InMemoryKidProfileRepository()
        try await profiles.save(profile)
        let settings = InMemoryPracticeSettingsRepository()
        let words = InMemoryWordPoolRepository()
        let learning = InMemoryLearningRecordRepository()
        let prompt = try WordPrompt(learningMode: .read, text: "cat")
        let importOutcomes = try await words.upsert([
            WordPoolEntryDraft(
                profileID: profile.id,
                prompt: prompt,
                addedAt: now,
                source: .guardianManual,
                positionInBatch: 0
            )
        ])
        let canonicalPrompt = try XCTUnwrap(
            importOutcomes.first?.entry.prompt
        )
        try await learning.append(
            AttemptEvent(
                profileID: profile.id,
                wordPromptID: canonicalPrompt.id,
                learningMode: .read,
                evidence: .firstIndependentAttempt,
                outcome: .incorrect,
                occurredAt: now
            )
        )
        try await learning.save(
            WordProgress(
                profileID: profile.id,
                wordPromptID: canonicalPrompt.id,
                learningMode: .read,
                firstIndependentAttemptCount: 2,
                firstIndependentCorrectCount: 0,
                lastEncounterAt: now
            )
        )
        try await settings.save(
            ProfilePracticeSettings(
                profileID: profile.id,
                notifications: LearningNotificationPreferences(
                    questCompletionEnabled: true,
                    syncFailureEnabled: true,
                    weeklySummaryEnabled: true
                )
            )
        )
        let scheduler = NotificationSchedulerSpy()
        let reconciler = ProductionLearningNotificationReconciler(
            scheduler: scheduler,
            profileRepository: profiles,
            wordPoolRepository: words,
            practiceSettingsRepository: settings,
            learningRecordRepository: learning,
            dailyQuestRepository: NotificationDailyRepository(
                completedRunCount: 2
            ),
            familySyncCoordinator: NotificationSyncCoordinator(
                currentStatus: .failed(message: "safe", pendingCount: 1)
            ),
            clock: NotificationClock(now: now),
            timeZone: TimeZone(secondsFromGMT: 0) ?? .current
        )

        await reconciler.reconcileAll()

        let contexts = await scheduler.contexts()
        let requestCount = await scheduler.requestCount()
        XCTAssertEqual(contexts.count, 1)
        XCTAssertEqual(contexts.first?.completedQuestCountToday, 2)
        XCTAssertEqual(contexts.first?.hasPendingSyncFailure, true)
        XCTAssertEqual(contexts.first?.weeklyAttentionCount, 1)
        XCTAssertEqual(requestCount, 0)
    }

    private let now = Date(timeIntervalSince1970: 2_000_000_000)
}

private actor NotificationSchedulerSpy: LearningNotificationScheduling {
    private var savedContexts: [LearningNotificationContext] = []
    private var requests = 0

    func authorizationStatus() async -> LearningNotificationAuthorization {
        .authorized
    }

    func requestAuthorization() async -> LearningNotificationAuthorization {
        requests += 1
        return .authorized
    }

    func reconcile(
        preferences: LearningNotificationPreferences,
        context: LearningNotificationContext,
        calendar: Calendar
    ) async throws {
        _ = preferences
        _ = calendar
        savedContexts.append(context)
    }

    func removeNotifications(for profileID: ProfileID) async {
        _ = profileID
    }

    func contexts() -> [LearningNotificationContext] { savedContexts }
    func requestCount() -> Int { requests }
}

private actor NotificationDailyRepository: DailyQuestRepository {
    private let completedRunCount: Int

    init(completedRunCount: Int) {
        self.completedRunCount = completedRunCount
    }

    func state(for key: DailyQuestKey) async throws -> DailyQuestState {
        _ = key
        return DailyQuestState(plan: nil, todayCompletion: nil, rewardGrant: nil)
    }

    func createPlanIfAbsent(_ plan: DailyQuestPlan) async throws -> DailyQuestPlan {
        plan
    }

    func completions(
        for key: DailyQuestKey
    ) async throws -> [DailyQuestCompletion] {
        guard key.learningMode == .read else { return [] }
        return (0..<completedRunCount).map { index in
            DailyQuestCompletion(
                id: DailyQuestCompletionID(),
                dailyPlanID: QuestID(),
                runQuestID: QuestID(),
                profileID: key.profileID,
                learningMode: key.learningMode,
                localDay: key.localDay,
                runKind: index == 0 ? .today : .practiceAgain,
                points: 10,
                stars: QuestStars(),
                completedAt: Date(timeIntervalSince1970: 2_000_000_000)
            )
        }
    }

    func completions(
        for profileID: ProfileID,
        in month: LocalMonth
    ) async throws -> [DailyQuestCompletion] {
        _ = profileID
        _ = month
        return []
    }

    func recordCompletion(
        _ completion: DailyQuestCompletion,
        proposedRewardGrant: RewardGrant?
    ) async throws -> DailyQuestCompletionWriteResult {
        DailyQuestCompletionWriteResult(
            completion: completion,
            rewardGrant: proposedRewardGrant,
            insertedCompletion: true,
            grantedReward: proposedRewardGrant != nil
        )
    }
}

private actor NotificationSyncCoordinator: FamilySyncCoordinating {
    let currentStatus: FamilySyncStatus

    init(currentStatus: FamilySyncStatus) {
        self.currentStatus = currentStatus
    }

    func isEnabled() async -> Bool { true }
    func setEnabled(_ isEnabled: Bool) async throws -> FamilySyncStatus {
        _ = isEnabled
        return currentStatus
    }
    func synchronize() async -> FamilySyncStatus { currentStatus }
    func status() async -> FamilySyncStatus { currentStatus }

    func createShare(for profileID: ProfileID) async throws -> URL {
        _ = profileID
        return URL(string: "https://example.invalid")!
    }

    func acceptShare(at url: URL) async throws {
        _ = url
    }
}

private struct NotificationClock: AppClock {
    let now: Date
}
