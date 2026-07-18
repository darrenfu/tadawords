import Foundation
import TadaWordsContent
import TadaWordsDomain
import XCTest

@testable import TadaWordsFeatures

@MainActor
final class FamilySyncUIReceiptRefreshHarnessTests: XCTestCase {
    func testCommittedReceiptRefreshesProfileRewardAndFutureWordSettingsProgress()
        async throws
    {
        let fixture = try await ChildReceiptRefreshFixture.make()
        let dog = try await fixture.addWord("dog")
        try await fixture.learning.save(
            WordProgress(
                profileID: fixture.profile.id,
                wordPromptID: dog.prompt.id,
                learningMode: .read,
                memoryState: MemoryState(
                    stabilityDays: 1,
                    difficulty: 0.4,
                    nextReviewAt: fixture.now.addingTimeInterval(-1),
                    lastIndependentAttemptAt: fixture.now.addingTimeInterval(-86_400),
                    consecutiveIndependentSuccesses: 1
                ),
                firstIndependentAttemptCount: 1,
                firstIndependentCorrectCount: 1,
                lastEncounterAt: fixture.now.addingTimeInterval(-86_400)
            )
        )
        try await fixture.settings.save(
            ProfilePracticeSettings(
                profileID: fixture.profile.id,
                read: LearningRouteSettings(
                    newWordLimit: 0,
                    reviewWordLimit: 1,
                    contentOrder: .reviewThenNew,
                    emergencyAfterSeconds: 225
                )
            )
        )
        let remoteProfile = KidProfile(
            id: fixture.profile.id,
            displayName: "Mia Remote",
            avatar: .cartoonAnimal(assetID: "fox"),
            selectedWorld: .buildItBay,
            starterWorld: fixture.profile.starterWorld,
            guardianUnlockedWorlds: [.buildItBay],
            schoolGrade: .kindergarten,
            ageYears: 5,
            createdAt: fixture.profile.createdAt,
            updatedAt: fixture.now
        )
        try await fixture.profiles.save(remoteProfile)
        try await fixture.grantReward(in: .buildItBay)

        await fixture.model.refreshAfterExternalSyncAndWait()

        XCTAssertEqual(fixture.model.selectedProfile, remoteProfile)
        XCTAssertEqual(
            fixture.model.rewardCollections[.buildItBay]?.collectedCount,
            1
        )
        await fixture.model.prepareQuestAndWait(.read)
        let session = try childQuestSession(from: fixture.model.destination)
        XCTAssertEqual(session.prompt.normalizedText, "dog")
        XCTAssertEqual(session.source, .review)
        XCTAssertEqual(session.timer.emergencyAfter, 225)
    }

    func testCommittedReceiptDoesNotRebuildOrInterruptActiveQuest()
        async throws
    {
        let fixture = try await ChildReceiptRefreshFixture.make()
        _ = try await fixture.addWord("cat")
        try await fixture.settings.save(.defaults(for: fixture.profile.id))
        await fixture.model.prepareQuestAndWait(.read)
        let before = try childQuestSession(from: fixture.model.destination)
        let timer = before.timer
        let remoteProfile = KidProfile(
            id: fixture.profile.id,
            displayName: "Mia Updated",
            avatar: fixture.profile.avatar,
            selectedWorld: .pawsAndPines,
            starterWorld: fixture.profile.starterWorld,
            schoolGrade: fixture.profile.schoolGrade,
            ageYears: fixture.profile.ageYears,
            createdAt: fixture.profile.createdAt,
            updatedAt: fixture.now
        )
        try await fixture.profiles.save(remoteProfile)
        _ = try await fixture.addWord("dog")

        await fixture.model.refreshAfterExternalSyncAndWait()

        let after = try childQuestSession(from: fixture.model.destination)
        XCTAssertEqual(after.id, before.id)
        XCTAssertEqual(after.currentItem, before.currentItem)
        XCTAssertEqual(after.prompt.id, before.prompt.id)
        XCTAssertTrue(after.timer === timer)
        XCTAssertTrue(after.timer.isRunning)
        XCTAssertEqual(fixture.model.selectedProfile, remoteProfile)
    }

    func testActiveProfileDeletionImmediatelyReturnsToChooserAndClearsSession()
        async throws
    {
        let fixture = try await ChildReceiptRefreshFixture.make()
        try await fixture.session.saveLastSelectedProfileID(fixture.profile.id)
        try await fixture.profiles.delete(id: fixture.profile.id)

        await fixture.model.refreshAfterExternalSyncAndWait()

        XCTAssertNil(fixture.model.selectedProfile)
        XCTAssertNil(fixture.model.lastPlayedProfileID)
        XCTAssertTrue(fixture.model.profiles.isEmpty)
        guard case .profileChooser = fixture.model.destination else {
            return XCTFail("A remotely deleted active Kid must return to the chooser")
        }
        let remembered = try await fixture.session.lastSelectedProfileID()
        XCTAssertNil(remembered)
    }
}

@MainActor
private struct ChildReceiptRefreshFixture {
    let now = Date(timeIntervalSince1970: 2_176_000_000)
    let profile: KidProfile
    let profiles: InMemoryKidProfileRepository
    let words: InMemoryWordPoolRepository
    let settings: InMemoryPracticeSettingsRepository
    let learning: InMemoryLearningRecordRepository
    let daily: InMemoryDailyQuestRepository
    let session: InMemoryChildSessionRepository
    let coordinator: DailyQuestCoordinator
    let model: TadaWordsAppModel

    static func make() async throws -> Self {
        let now = Date(timeIntervalSince1970: 2_176_000_000)
        let profile = KidProfile(
            displayName: "Mia",
            avatar: .cartoonAnimal(assetID: "hare"),
            selectedWorld: .moonpetalKingdom,
            createdAt: now.addingTimeInterval(-100)
        )
        let profiles = InMemoryKidProfileRepository()
        try await profiles.save(profile)
        let words = InMemoryWordPoolRepository(deviceID: "receipt-device")
        let settings = InMemoryPracticeSettingsRepository()
        let learning = InMemoryLearningRecordRepository()
        let daily = InMemoryDailyQuestRepository()
        let session = InMemoryChildSessionRepository()
        let coordinator = DailyQuestCoordinator(
            repository: daily,
            timeZone: .gmt
        )
        let clock = ReceiptRefreshClock(now: now)
        let model = TadaWordsAppModel(
            profiles: [profile],
            contentProvider: RepositoryBackedQuestContentProvider(
                wordPoolRepository: words,
                wordProgressRepository: learning,
                practiceSettingsRepository: settings,
                attemptEventRepository: learning,
                clock: clock,
                timeZone: .gmt
            ),
            practiceSettingsRepository: settings,
            attemptEventRepository: learning,
            wordProgressRepository: learning,
            dailyQuestCoordinator: coordinator,
            clock: clock,
            timeZone: .gmt,
            childSessionRepository: session,
            profileRepository: profiles
        )
        await model.selectProfileAndWait(profile)
        return Self(
            profile: profile,
            profiles: profiles,
            words: words,
            settings: settings,
            learning: learning,
            daily: daily,
            session: session,
            coordinator: coordinator,
            model: model
        )
    }

    func addWord(_ text: String) async throws -> WordPoolEntry {
        try await words.upsert([
            WordPoolEntryDraft(
                profileID: profile.id,
                prompt: try WordPrompt(learningMode: .read, text: text),
                addedAt: now,
                source: .guardianManual,
                positionInBatch: 0
            )
        ])[0].entry
    }

    func grantReward(in world: WorldTheme) async throws {
        let rewardPromptID = WordPromptID()
        let candidate = QuestPlan(
            profileID: profile.id,
            configuration: .defaultWrite,
            reviewWordIDs: [],
            newWordIDs: [rewardPromptID],
            createdAt: now
        )
        let state = try await coordinator.loadOrCreateToday(
            candidate: candidate,
            on: now
        )
        let launch = try XCTUnwrap(coordinator.todayLaunch(from: state))
        _ = try await coordinator.complete(
            launch,
            score: QuestScore(
                points: 100,
                firstIndependentCorrectCount: 1,
                firstIndependentAttemptCount: 1,
                stars: QuestStars(earned: [.completion, .accuracy]),
                personalPaceAssessment: .unavailable
            ),
            world: world,
            completedAt: now
        )
    }
}

private struct ReceiptRefreshClock: AppClock {
    let now: Date
}

@MainActor
private func childQuestSession(
    from destination: AppDestination
) throws -> QuestSession {
    guard case .quest(let session) = destination else {
        throw ReceiptRefreshTestFailure.expectedQuest
    }
    return session
}

private enum ReceiptRefreshTestFailure: Error {
    case expectedQuest
}
