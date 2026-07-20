import Foundation
import TadaWordsContent
import TadaWordsDomain
import XCTest

@testable import TadaWordsGuardianFeatures

@MainActor
final class FamilySyncGuardianReceiptRefreshHarnessTests: XCTestCase {
    func testCommittedReceiptRefreshesProfileWordsSettingsProgressAndRewards()
        async throws
    {
        let fixture = try await GuardianReceiptRefreshFixture.make(
            includeSecondProfile: true
        )
        await fixture.model.refreshAfterExternalSyncAndWait()
        let remoteProfile = KidProfile(
            id: fixture.first.id,
            displayName: "Mia Remote",
            avatar: .cartoonAnimal(assetID: "fox"),
            selectedWorld: .buildItBay,
            starterWorld: fixture.first.starterWorld,
            guardianUnlockedWorlds: [.buildItBay],
            schoolGrade: .kindergarten,
            ageYears: 5,
            createdAt: fixture.first.createdAt,
            updatedAt: fixture.now
        )
        try await fixture.profiles.save(remoteProfile)
        let outcomes = try await fixture.words.upsert([
            WordPoolEntryDraft(
                profileID: fixture.first.id,
                prompt: try WordPrompt(learningMode: .read, text: "dog"),
                addedAt: fixture.now,
                source: .guardianManual,
                positionInBatch: 0
            )
        ])
        let dog = try XCTUnwrap(outcomes.first?.entry)
        let remoteSettings = ProfilePracticeSettings(
            profileID: fixture.first.id,
            read: LearningRouteSettings(
                newWordLimit: 3,
                reviewWordLimit: 2,
                contentOrder: .reviewThenNew,
                emergencyAfterSeconds: 240
            )
        )
        try await fixture.settings.save(remoteSettings)
        try await fixture.learning.append(
            AttemptEvent(
                profileID: fixture.first.id,
                wordPromptID: dog.prompt.id,
                learningMode: .read,
                evidence: .firstIndependentAttempt,
                outcome: .correct,
                occurredAt: fixture.now
            )
        )
        try await fixture.grantReward(in: .buildItBay)

        await fixture.model.refreshAfterExternalSyncAndWait()

        let snapshot = try XCTUnwrap(fixture.model.snapshot)
        XCTAssertEqual(snapshot.profile, remoteProfile)
        XCTAssertEqual(snapshot.readPool.map(\.normalizedText), ["dog"])
        XCTAssertEqual(snapshot.practiceSettings, remoteSettings)
        XCTAssertEqual(snapshot.practiceFrequencyByWordID[dog.prompt.id], 1)
        XCTAssertEqual(
            snapshot.collections[.buildItBay]?.collectedCount,
            1
        )
    }

    func testRemoteDeletionOfVisibleProfileMovesParentToProfiles()
        async throws
    {
        let fixture = try await GuardianReceiptRefreshFixture.make(
            includeSecondProfile: true
        )
        await fixture.model.refreshAfterExternalSyncAndWait()
        try await fixture.profiles.delete(id: fixture.first.id)

        await fixture.model.refreshAfterExternalSyncAndWait()

        XCTAssertEqual(fixture.model.snapshot?.profile.id, fixture.second?.id)
        XCTAssertEqual(
            fixture.model.familySnapshot?.profiles.map(\.id),
            fixture.second.map { [$0.id] }
        )
        guard case .profiles = fixture.model.destination else {
            return XCTFail("A remotely removed visible Kid should return Parents to Kids")
        }
    }

    func testRemoteDeletionOfFinalProfileShowsRecoverableCreationPage()
        async throws
    {
        let fixture = try await GuardianReceiptRefreshFixture.make(
            includeSecondProfile: false
        )
        await fixture.model.refreshAfterExternalSyncAndWait()
        try await fixture.profiles.delete(id: fixture.first.id)

        await fixture.model.refreshAfterExternalSyncAndWait()

        XCTAssertNil(fixture.model.snapshot)
        XCTAssertEqual(fixture.model.familySnapshot?.profiles, [])
        XCTAssertNil(fixture.model.familySnapshot?.selectedProfileID)
        guard case .profileEditor(let profile) = fixture.model.destination else {
            return XCTFail("Deleting the final shared Kid needs a recoverable create page")
        }
        XCTAssertNil(profile)

        XCTAssertTrue(
            fixture.model.returnFromProfileEditor(),
            "Back must tell GuardianRootView to invoke onExit for an empty family"
        )
        XCTAssertEqual(fixture.model.transitionKey, "parent-gate")

        fixture.model.showProfiles()
        XCTAssertTrue(
            fixture.model.returnFromProfiles(),
            "The empty Kids page must also exit instead of opening a blank dashboard"
        )
        XCTAssertEqual(fixture.model.transitionKey, "parent-gate")
    }
}

@MainActor
private struct GuardianReceiptRefreshFixture {
    let now = Date(timeIntervalSince1970: 2_177_000_000)
    let first: KidProfile
    let second: KidProfile?
    let profiles: InMemoryKidProfileRepository
    let words: InMemoryWordPoolRepository
    let settings: InMemoryPracticeSettingsRepository
    let learning: InMemoryLearningRecordRepository
    let daily: InMemoryDailyQuestRepository
    let coordinator: DailyQuestCoordinator
    let store: RepositoryGuardianFamilyStore
    let model: GuardianDashboardViewModel

    static func make(
        includeSecondProfile: Bool
    ) async throws -> Self {
        let now = Date(timeIntervalSince1970: 2_177_000_000)
        let first = KidProfile(
            displayName: "Mia",
            avatar: .cartoonAnimal(assetID: "hare"),
            selectedWorld: .moonpetalKingdom,
            createdAt: now.addingTimeInterval(-200)
        )
        let second =
            includeSecondProfile
            ? KidProfile(
                displayName: "Leo",
                avatar: .cartoonAnimal(assetID: "fox"),
                selectedWorld: .pawsAndPines,
                createdAt: now.addingTimeInterval(-100)
            )
            : nil
        let profiles = InMemoryKidProfileRepository()
        try await profiles.save(first)
        if let second { try await profiles.save(second) }
        let words = InMemoryWordPoolRepository(deviceID: "guardian-receipt")
        let settings = InMemoryPracticeSettingsRepository()
        let learning = InMemoryLearningRecordRepository()
        let daily = InMemoryDailyQuestRepository()
        let coordinator = DailyQuestCoordinator(
            repository: daily,
            timeZone: .gmt
        )
        let initialProfiles = [first] + [second].compactMap { $0 }
        let store = RepositoryGuardianFamilyStore(
            profiles: initialProfiles,
            selectedProfileID: first.id,
            profileRepository: profiles,
            wordPoolRepository: words,
            practiceSettingsRepository: settings,
            learningRecordRepository: learning,
            dailyQuestRepository: daily,
            clock: GuardianReceiptClock(now: now),
            timeZone: .gmt
        )
        let model = GuardianDashboardViewModel(
            store: store,
            audioPromptService: GuardianReceiptSilentAudioPromptService()
        )
        return Self(
            first: first,
            second: second,
            profiles: profiles,
            words: words,
            settings: settings,
            learning: learning,
            daily: daily,
            coordinator: coordinator,
            store: store,
            model: model
        )
    }

    func grantReward(in world: WorldTheme) async throws {
        let plan = QuestPlan(
            profileID: first.id,
            configuration: .defaultWrite,
            reviewWordIDs: [],
            newWordIDs: [WordPromptID()],
            createdAt: now
        )
        let state = try await coordinator.loadOrCreateToday(
            candidate: plan,
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

private struct GuardianReceiptClock: AppClock {
    let now: Date
}

private struct GuardianReceiptSilentAudioPromptService: AudioPromptService {
    func play(_ prompt: WordPrompt, for profileID: ProfileID) async throws {
        _ = prompt
        _ = profileID
    }
}
