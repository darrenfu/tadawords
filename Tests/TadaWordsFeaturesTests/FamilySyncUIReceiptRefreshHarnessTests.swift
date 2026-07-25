import Foundation
import TadaWordsContent
import TadaWordsDomain
import XCTest

@testable import TadaWordsFeatures

@MainActor
final class FamilySyncUIReceiptRefreshHarnessTests: XCTestCase {
    func testRecoveryRequiredKeepsLastCommittedChildGenerationVisible()
        async throws
    {
        let now = Date(timeIntervalSince1970: 2_176_050_000)
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
        try await profiles.save(remoteProfile)
        let gate = ProfileScopedMutationGate()
        let transactionID = UUID()
        await gate.requireRecovery(
            oldProfile.id,
            transactionID: transactionID
        )
        let model = TadaWordsAppModel(
            profiles: [oldProfile],
            profileRepository: profiles,
            profileMutationGate: gate
        )
        await model.selectProfileAndWait(oldProfile)

        await model.refreshAfterExternalSyncAndWait()

        XCTAssertEqual(model.selectedProfile, oldProfile)
        XCTAssertEqual(model.profiles, [oldProfile])

        await gate.clearRecovery(
            oldProfile.id,
            transactionID: transactionID
        )
        await model.refreshAfterExternalSyncAndWait()

        XCTAssertEqual(model.selectedProfile, remoteProfile)
        XCTAssertEqual(model.profiles, [remoteProfile])
    }

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
                    emergencyAfterSeconds: 225,
                    incorrectAttemptLimit: 4
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
        XCTAssertEqual(session.incorrectAttemptLimit, 4)
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
        try await fixture.settings.save(
            ProfilePracticeSettings(
                profileID: fixture.profile.id,
                read: LearningRouteSettings(
                    newWordLimit: 5,
                    reviewWordLimit: 5,
                    contentOrder: .newThenReview,
                    emergencyAfterSeconds: 180,
                    incorrectAttemptLimit: 5
                )
            )
        )

        await fixture.model.refreshAfterExternalSyncAndWait()

        let after = try childQuestSession(from: fixture.model.destination)
        XCTAssertEqual(after.id, before.id)
        XCTAssertEqual(after.currentItem, before.currentItem)
        XCTAssertEqual(after.prompt.id, before.prompt.id)
        XCTAssertTrue(after.timer === timer)
        XCTAssertTrue(after.timer.isRunning)
        XCTAssertEqual(after.incorrectAttemptLimit, before.incorrectAttemptLimit)
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

    func testOlderReceiptRefreshCannotRepublishProfileAfterNewerDeletion()
        async throws
    {
        let profile = KidProfile(
            displayName: "Mia",
            avatar: .cartoonAnimal(assetID: "hare"),
            selectedWorld: .moonpetalKingdom,
            createdAt: Date(timeIntervalSince1970: 2_176_100_000)
        )
        let profiles = InvertedReceiptKidProfileRepository(profiles: [profile])
        let session = InMemoryChildSessionRepository()
        let model = TadaWordsAppModel(
            profiles: [profile],
            childSessionRepository: session,
            profileRepository: profiles
        )
        await model.selectProfileAndWait(profile)

        let olderRefresh = Task {
            await model.refreshAfterExternalSyncAndWait()
        }
        await profiles.waitForStartedRequestCount(1)
        await profiles.replaceProfiles([])

        let deletionRefresh = Task {
            await model.refreshAfterExternalSyncAndWait()
        }
        await profiles.waitForStartedRequestCount(2)
        await profiles.resumeRequest(1)
        await deletionRefresh.value

        XCTAssertTrue(model.profiles.isEmpty)
        XCTAssertNil(model.selectedProfile)
        guard case .profileChooser = model.destination else {
            return XCTFail("The newer deletion receipt must win")
        }

        await profiles.resumeRequest(0)
        await olderRefresh.value

        XCTAssertTrue(model.profiles.isEmpty)
        XCTAssertNil(model.selectedProfile)
        guard case .profileChooser = model.destination else {
            return XCTFail("A late older receipt must not resurrect the Kid")
        }
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

private actor InvertedReceiptKidProfileRepository: KidProfileRepository {
    private var storedProfiles: [KidProfile]
    private var startedRequestCount = 0
    private var continuations: [Int: CheckedContinuation<Void, Never>] = [:]

    init(profiles: [KidProfile]) {
        storedProfiles = profiles
    }

    func profiles() async throws -> [KidProfile] {
        let request = startedRequestCount
        startedRequestCount += 1
        let capturedProfiles = storedProfiles
        await withCheckedContinuation { continuation in
            continuations[request] = continuation
        }
        return capturedProfiles
    }

    func profile(id: ProfileID) async throws -> KidProfile? {
        storedProfiles.first(where: { $0.id == id })
    }

    func save(_ profile: KidProfile) async throws {
        storedProfiles.removeAll(where: { $0.id == profile.id })
        storedProfiles.append(profile)
    }

    func delete(id: ProfileID) async throws {
        storedProfiles.removeAll(where: { $0.id == id })
    }

    func replaceProfiles(_ profiles: [KidProfile]) {
        storedProfiles = profiles
    }

    func waitForStartedRequestCount(_ expectedCount: Int) async {
        while startedRequestCount < expectedCount {
            await Task.yield()
        }
    }

    func resumeRequest(_ request: Int) {
        continuations.removeValue(forKey: request)?.resume()
    }
}
