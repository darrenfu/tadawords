import Foundation
import TadaWordsContent
import TadaWordsDomain
import XCTest

@testable import TadaWordsGuardianFeatures

@MainActor
final class FamilySyncGuardianReceiptRefreshHarnessTests: XCTestCase {
    func testRecoveryRequiredKeepsLastCommittedParentGenerationVisible()
        async throws
    {
        let now = Date(timeIntervalSince1970: 2_177_050_000)
        let oldProfile = KidProfile(
            displayName: "Committed Old",
            avatar: .cartoonAnimal(assetID: "hare"),
            selectedWorld: .moonpetalKingdom,
            createdAt: now.addingTimeInterval(-100)
        )
        let remoteProfile = KidProfile(
            id: oldProfile.id,
            displayName: "Remote Complete",
            avatar: .cartoonAnimal(assetID: "fox"),
            selectedWorld: .pawsAndPines,
            starterWorld: oldProfile.starterWorld,
            createdAt: oldProfile.createdAt,
            updatedAt: now
        )
        let profiles = InMemoryKidProfileRepository()
        try await profiles.save(oldProfile)
        let gate = ProfileScopedMutationGate()
        let store = RepositoryGuardianFamilyStore(
            profiles: [oldProfile],
            selectedProfileID: oldProfile.id,
            profileRepository: profiles,
            wordPoolRepository: InMemoryWordPoolRepository(),
            practiceSettingsRepository: InMemoryPracticeSettingsRepository(),
            dailyQuestRepository: InMemoryDailyQuestRepository(),
            mutationGate: gate,
            clock: GuardianReceiptClock(now: now),
            timeZone: .gmt
        )
        let model = GuardianDashboardViewModel(
            store: store,
            audioPromptService: GuardianReceiptSilentAudioPromptService()
        )
        await model.refreshAfterExternalSyncAndWait()
        XCTAssertEqual(model.snapshot?.profile, oldProfile)

        try await profiles.save(remoteProfile)
        let transactionID = UUID()
        await gate.requireRecovery(
            oldProfile.id,
            transactionID: transactionID
        )
        await model.refreshAfterExternalSyncAndWait()

        XCTAssertEqual(model.snapshot?.profile, oldProfile)

        await gate.clearRecovery(
            oldProfile.id,
            transactionID: transactionID
        )
        await model.refreshAfterExternalSyncAndWait()

        XCTAssertEqual(model.snapshot?.profile, remoteProfile)
    }

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

    func testOlderReceiptRefreshCannotRepublishDeletedKidAfterNewerRefresh()
        async throws
    {
        let now = Date(timeIntervalSince1970: 2_177_100_000)
        let profile = KidProfile(
            displayName: "Mia",
            avatar: .cartoonAnimal(assetID: "hare"),
            selectedWorld: .moonpetalKingdom,
            createdAt: now
        )
        let profiles = DelayedGuardianProfileLookupRepository(profile: profile)
        let store = RepositoryGuardianFamilyStore(
            profiles: [profile],
            selectedProfileID: profile.id,
            profileRepository: profiles,
            wordPoolRepository: InMemoryWordPoolRepository(
                deviceID: "guardian-inverted-receipt"
            ),
            practiceSettingsRepository: InMemoryPracticeSettingsRepository(),
            dailyQuestRepository: InMemoryDailyQuestRepository(),
            clock: GuardianReceiptClock(now: now),
            timeZone: .gmt
        )
        let model = GuardianDashboardViewModel(
            store: store,
            audioPromptService: GuardianReceiptSilentAudioPromptService()
        )
        await model.refreshAfterExternalSyncAndWait()
        XCTAssertEqual(model.snapshot?.profile.id, profile.id)

        await profiles.delayNextProfileLookup()
        let olderRefresh = Task {
            await model.refreshAfterExternalSyncAndWait()
        }
        await profiles.waitForDelayedLookup()
        await profiles.removeProfile()

        let deletionRefresh = Task {
            await model.refreshAfterExternalSyncAndWait()
        }
        await deletionRefresh.value

        XCTAssertNil(model.snapshot)
        XCTAssertEqual(model.familySnapshot?.profiles, [])
        guard case .profileEditor(nil) = model.destination else {
            return XCTFail("The newer deletion receipt must show Add Kid")
        }

        await profiles.resumeDelayedLookup()
        await olderRefresh.value

        XCTAssertNil(model.snapshot)
        XCTAssertEqual(model.familySnapshot?.profiles, [])
        guard case .profileEditor(nil) = model.destination else {
            return XCTFail("A late older receipt must not restore the deleted Kid")
        }
    }

    func testCancelledOlderReceiptCannotRestoreStaleStoreSelection()
        async throws
    {
        let now = Date(timeIntervalSince1970: 2_177_200_000)
        let first = KidProfile(
            displayName: "Mia",
            avatar: .cartoonAnimal(assetID: "hare"),
            selectedWorld: .moonpetalKingdom,
            createdAt: now
        )
        let second = KidProfile(
            displayName: "Leo",
            avatar: .cartoonAnimal(assetID: "fox"),
            selectedWorld: .pawsAndPines,
            createdAt: now.addingTimeInterval(1)
        )
        let latest = KidProfile(
            displayName: "Ava",
            avatar: .cartoonAnimal(assetID: "owl"),
            selectedWorld: .frostlightWorld,
            createdAt: now.addingTimeInterval(2)
        )
        let profiles = InvertedGuardianSelectionRepository(
            profiles: [first, second, latest]
        )
        let store = RepositoryGuardianFamilyStore(
            profiles: [first, second, latest],
            selectedProfileID: first.id,
            profileRepository: profiles,
            wordPoolRepository: InMemoryWordPoolRepository(
                deviceID: "guardian-selection-fence"
            ),
            practiceSettingsRepository: InMemoryPracticeSettingsRepository(),
            dailyQuestRepository: InMemoryDailyQuestRepository(),
            clock: GuardianReceiptClock(now: now),
            timeZone: .gmt
        )
        let model = GuardianDashboardViewModel(
            store: store,
            audioPromptService: GuardianReceiptSilentAudioPromptService()
        )
        await model.refreshAfterExternalSyncAndWait()
        XCTAssertEqual(model.snapshot?.profile.id, first.id)

        await profiles.replaceProfiles([second, latest])
        await profiles.delayNextLookup(for: second.id)
        let olderRefresh = Task {
            await model.refreshAfterExternalSyncAndWait()
        }
        await profiles.waitForDelayedLookup()

        // GuardianRootView cancels the prior receipt task before starting the
        // new one. The Profile repository deliberately ignores cancellation
        // until its suspended lookup is released.
        olderRefresh.cancel()
        _ = try await store.selectProfile(id: latest.id)
        await model.refreshAfterExternalSyncAndWait()
        XCTAssertEqual(model.snapshot?.profile.id, latest.id)

        await profiles.resumeDelayedLookup()
        await olderRefresh.value

        XCTAssertEqual(model.snapshot?.profile.id, latest.id)
        let storedFamily = try await store.familySnapshot()
        XCTAssertEqual(storedFamily.selectedProfileID, latest.id)
        let storedDashboard = try await store.dashboardSnapshot()
        XCTAssertEqual(storedDashboard.profile.id, latest.id)
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

private actor DelayedGuardianProfileLookupRepository: KidProfileRepository {
    private var profile: KidProfile?
    private var shouldDelayNextLookup = false
    private var delayedLookupStarted = false
    private var delayedLookupContinuation: CheckedContinuation<Void, Never>?

    init(profile: KidProfile) {
        self.profile = profile
    }

    func profiles() async throws -> [KidProfile] {
        profile.map { [$0] } ?? []
    }

    func profile(id: ProfileID) async throws -> KidProfile? {
        let captured = profile?.id == id ? profile : nil
        guard shouldDelayNextLookup else { return captured }
        shouldDelayNextLookup = false
        delayedLookupStarted = true
        await withCheckedContinuation { continuation in
            delayedLookupContinuation = continuation
        }
        return captured
    }

    func save(_ profile: KidProfile) async throws {
        self.profile = profile
    }

    func delete(id: ProfileID) async throws {
        guard profile?.id == id else { return }
        profile = nil
    }

    func delayNextProfileLookup() {
        shouldDelayNextLookup = true
        delayedLookupStarted = false
    }

    func waitForDelayedLookup() async {
        while !delayedLookupStarted {
            await Task.yield()
        }
    }

    func removeProfile() {
        profile = nil
    }

    func resumeDelayedLookup() {
        delayedLookupContinuation?.resume()
        delayedLookupContinuation = nil
    }
}

private actor InvertedGuardianSelectionRepository: KidProfileRepository {
    private var orderedProfiles: [KidProfile]
    private var delayedProfileID: ProfileID?
    private var delayedLookupStarted = false
    private var delayedLookupContinuation: CheckedContinuation<Void, Never>?

    init(profiles: [KidProfile]) {
        orderedProfiles = profiles
    }

    func profiles() async throws -> [KidProfile] {
        orderedProfiles
    }

    func profile(id: ProfileID) async throws -> KidProfile? {
        let captured = orderedProfiles.first { $0.id == id }
        guard delayedProfileID == id else { return captured }
        delayedProfileID = nil
        delayedLookupStarted = true
        await withCheckedContinuation { continuation in
            delayedLookupContinuation = continuation
        }
        return captured
    }

    func save(_ profile: KidProfile) async throws {
        orderedProfiles.removeAll { $0.id == profile.id }
        orderedProfiles.append(profile)
    }

    func delete(id: ProfileID) async throws {
        orderedProfiles.removeAll { $0.id == id }
    }

    func replaceProfiles(_ profiles: [KidProfile]) {
        orderedProfiles = profiles
    }

    func delayNextLookup(for profileID: ProfileID) {
        delayedProfileID = profileID
        delayedLookupStarted = false
    }

    func waitForDelayedLookup() async {
        while !delayedLookupStarted {
            await Task.yield()
        }
    }

    func resumeDelayedLookup() {
        delayedLookupContinuation?.resume()
        delayedLookupContinuation = nil
    }
}
