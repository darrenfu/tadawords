import Foundation
import TadaWordsContent
import TadaWordsDomain
import XCTest

@testable import TadaWordsGuardianFeatures

final class RepositoryGuardianFamilyStoreTests: XCTestCase {
    func testCreatePersistsAndSelectsNewProfile() async throws {
        let fixture = try await makeFixture()

        let dashboard = try await fixture.store.createProfile(
            from: GuardianProfileDraft(
                displayName: "  Leo  ",
                avatarAssetID: "bear",
                selectedWorld: .buildItBay
            )
        )
        let family = try await fixture.store.familySnapshot()

        XCTAssertEqual(family.profiles.count, 2)
        XCTAssertEqual(family.selectedProfileID, dashboard.profile.id)
        XCTAssertEqual(dashboard.profile.displayName, "Leo")
        XCTAssertEqual(
            dashboard.profile.avatar,
            .cartoonAnimal(assetID: "bear")
        )
        XCTAssertEqual(dashboard.profile.selectedWorld, .buildItBay)
        XCTAssertTrue(dashboard.readPool.isEmpty)
        XCTAssertTrue(dashboard.writePool.isEmpty)
        XCTAssertEqual(
            dashboard.practiceSettings,
            .defaults(for: dashboard.profile.id)
        )
        let persistedProfile = try await fixture.profileRepository.profile(
            id: dashboard.profile.id
        )
        XCTAssertEqual(persistedProfile, dashboard.profile)
    }

    func testSwitchingProfilesKeepsPoolsAndSettingsStrictlyIsolated() async throws {
        let fixture = try await makeFixture()
        let second = try await fixture.store.createProfile(
            from: GuardianProfileDraft(
                displayName: "Leo",
                avatarAssetID: "fox",
                selectedWorld: .pawsAndPines
            )
        ).profile
        _ = try await fixture.store.importWords(
            GuardianWordImportRequest(rawText: "cat", learningMode: .read)
        )
        let secondSettings = ProfilePracticeSettings(
            profileID: second.id,
            read: LearningRouteSettings(
                newWordLimit: 7,
                reviewWordLimit: 2,
                contentOrder: .reviewThenNew,
                emergencyAfterSeconds: 180
            )
        )
        _ = try await fixture.store.updatePracticeSettings(secondSettings)

        let firstDashboard = try await fixture.store.selectProfile(
            id: fixture.firstProfile.id
        )
        XCTAssertTrue(firstDashboard.readPool.isEmpty)
        XCTAssertTrue(firstDashboard.writePool.isEmpty)
        XCTAssertEqual(
            firstDashboard.practiceSettings,
            .defaults(for: fixture.firstProfile.id)
        )
        _ = try await fixture.store.importWords(
            GuardianWordImportRequest(rawText: "dog", learningMode: .write)
        )

        let restoredSecond = try await fixture.store.selectProfile(id: second.id)
        XCTAssertEqual(restoredSecond.readPool.map(\.normalizedText), ["cat"])
        XCTAssertTrue(restoredSecond.writePool.isEmpty)
        XCTAssertEqual(restoredSecond.practiceSettings, secondSettings)

        let restoredFirst = try await fixture.store.selectProfile(
            id: fixture.firstProfile.id
        )
        XCTAssertTrue(restoredFirst.readPool.isEmpty)
        XCTAssertEqual(restoredFirst.writePool.map(\.normalizedText), ["dog"])
    }

    func testEditPreservesIdentityCreationDateAndVoiceprint() async throws {
        let fixture = try await makeFixture(
            voiceprintStatus: .enrolled(
                modelVersion: "voice-v1",
                enrolledAt: testDate.addingTimeInterval(-50)
            )
        )

        let updated = try await fixture.store.updateProfile(
            id: fixture.firstProfile.id,
            from: GuardianProfileDraft(
                displayName: "Ava",
                avatarAssetID: "owl",
                selectedWorld: .moonpetalKingdom
            )
        ).profile

        XCTAssertEqual(updated.id, fixture.firstProfile.id)
        XCTAssertEqual(updated.createdAt, fixture.firstProfile.createdAt)
        XCTAssertEqual(updated.voiceprintStatus, fixture.firstProfile.voiceprintStatus)
        XCTAssertEqual(updated.displayName, "Ava")
        XCTAssertEqual(updated.avatar, .cartoonAnimal(assetID: "owl"))
    }

    func testInvalidDraftsDoNotCreateProfiles() async throws {
        let fixture = try await makeFixture()

        await assertThrowsErrorAsync {
            _ = try await fixture.store.createProfile(
                from: GuardianProfileDraft(
                    displayName: "   ",
                    avatarAssetID: "hare",
                    selectedWorld: .moonpetalKingdom
                )
            )
        } verify: { error in
            XCTAssertEqual(error as? GuardianFamilyStoreError, .emptyDisplayName)
        }
        await assertThrowsErrorAsync {
            _ = try await fixture.store.createProfile(
                from: GuardianProfileDraft(
                    displayName: "Nora",
                    avatarAssetID: "not-built-in",
                    selectedWorld: .pawsAndPines
                )
            )
        } verify: { error in
            XCTAssertEqual(
                error as? GuardianFamilyStoreError,
                .unsupportedAvatar("not-built-in")
            )
        }

        let persistedProfiles = try await fixture.profileRepository.profiles()
        XCTAssertEqual(persistedProfiles, [fixture.firstProfile])
    }

    func testDependentStorageFailureCannotPartiallyCreateOrEditProfile() async throws {
        let profileRepository = InMemoryKidProfileRepository()
        let firstProfile = KidProfile(
            displayName: "Mia",
            avatar: .cartoonAnimal(assetID: "hare"),
            selectedWorld: .moonpetalKingdom,
            createdAt: testDate.addingTimeInterval(-100)
        )
        try await profileRepository.save(firstProfile)
        let store = RepositoryGuardianFamilyStore(
            profiles: [firstProfile],
            profileRepository: profileRepository,
            wordPoolRepository: InMemoryWordPoolRepository(),
            practiceSettingsRepository: FailingFamilyPracticeSettingsRepository(),
            clock: FamilyFixedClock(now: testDate)
        )

        await assertThrowsErrorAsync {
            _ = try await store.createProfile(
                from: GuardianProfileDraft(
                    displayName: "Leo",
                    avatarAssetID: "fox",
                    selectedWorld: .buildItBay
                )
            )
        } verify: { _ in
        }
        await assertThrowsErrorAsync {
            _ = try await store.updateProfile(
                id: firstProfile.id,
                from: GuardianProfileDraft(
                    displayName: "Changed",
                    avatarAssetID: "owl",
                    selectedWorld: .pawsAndPines
                )
            )
        } verify: { _ in
        }

        let persistedProfiles = try await profileRepository.profiles()
        XCTAssertEqual(persistedProfiles, [firstProfile])
    }

    func testQuestCalendarUsesDailyRepositoryAndIsProfileIsolated()
        async throws
    {
        let profileRepository = InMemoryKidProfileRepository()
        let firstProfile = KidProfile(
            displayName: "Mia",
            avatar: .cartoonAnimal(assetID: "hare"),
            selectedWorld: .moonpetalKingdom,
            createdAt: testDate.addingTimeInterval(-100)
        )
        let secondProfile = KidProfile(
            displayName: "Leo",
            avatar: .cartoonAnimal(assetID: "fox"),
            selectedWorld: .buildItBay,
            createdAt: testDate.addingTimeInterval(-50)
        )
        try await profileRepository.save(firstProfile)
        try await profileRepository.save(secondProfile)

        let dailyRepository = InMemoryDailyQuestRepository()
        let coordinator = DailyQuestCoordinator(
            repository: dailyRepository,
            timeZone: .gmt
        )
        let questPlan = QuestPlan(
            profileID: firstProfile.id,
            configuration: QuestConfiguration(
                learningMode: .read,
                newWordLimit: 1,
                reviewWordLimit: 0,
                attentionBudget: 1,
                contentOrder: .newThenReview
            ),
            reviewWordIDs: [],
            newWordIDs: [WordPromptID()],
            createdAt: testDate
        )
        let state = try await coordinator.loadOrCreateToday(
            candidate: questPlan,
            on: testDate
        )
        _ = try await coordinator.complete(
            try XCTUnwrap(coordinator.todayLaunch(from: state)),
            score: QuestScore(
                points: 40,
                firstIndependentCorrectCount: 1,
                firstIndependentAttemptCount: 1,
                stars: QuestStars(earned: [.completion]),
                personalPaceAssessment: .unavailable
            ),
            world: firstProfile.selectedWorld,
            completedAt: testDate
        )

        let store = RepositoryGuardianFamilyStore(
            profiles: [firstProfile, secondProfile],
            profileRepository: profileRepository,
            wordPoolRepository: InMemoryWordPoolRepository(),
            practiceSettingsRepository: InMemoryPracticeSettingsRepository(),
            dailyQuestRepository: dailyRepository,
            clock: FamilyFixedClock(now: testDate),
            timeZone: .gmt
        )

        let firstDashboard = try await store.dashboardSnapshot()
        XCTAssertEqual(firstDashboard.questCalendar.profileID, firstProfile.id)
        XCTAssertEqual(
            firstDashboard.questCalendar.completionCountByDay.values.reduce(0, +),
            1
        )

        let secondDashboard = try await store.selectProfile(id: secondProfile.id)
        XCTAssertEqual(secondDashboard.questCalendar.profileID, secondProfile.id)
        XCTAssertTrue(secondDashboard.questCalendar.completionCountByDay.isEmpty)
    }

    private let testDate = Date(timeIntervalSince1970: 2_000_000_000)

    private func makeFixture(
        voiceprintStatus: VoiceprintEnrollmentStatus = .notEnrolled
    ) async throws -> Fixture {
        let profileRepository = InMemoryKidProfileRepository()
        let firstProfile = KidProfile(
            displayName: "Mia",
            avatar: .cartoonAnimal(assetID: "hare"),
            selectedWorld: .moonpetalKingdom,
            voiceprintStatus: voiceprintStatus,
            createdAt: testDate.addingTimeInterval(-100)
        )
        try await profileRepository.save(firstProfile)
        let store = RepositoryGuardianFamilyStore(
            profiles: [firstProfile],
            profileRepository: profileRepository,
            wordPoolRepository: InMemoryWordPoolRepository(),
            practiceSettingsRepository: InMemoryPracticeSettingsRepository(),
            clock: FamilyFixedClock(now: testDate)
        )
        return Fixture(
            store: store,
            profileRepository: profileRepository,
            firstProfile: firstProfile
        )
    }
}

private struct Fixture {
    let store: RepositoryGuardianFamilyStore
    let profileRepository: InMemoryKidProfileRepository
    let firstProfile: KidProfile
}

private struct FamilyFixedClock: AppClock {
    let now: Date
}

private actor FailingFamilyPracticeSettingsRepository: PracticeSettingsRepository {
    func settings(for profileID: ProfileID) async throws -> ProfilePracticeSettings? {
        _ = profileID
        throw FamilyStoreTestFailure.unavailable
    }

    func save(_ settings: ProfilePracticeSettings) async throws {
        _ = settings
        throw FamilyStoreTestFailure.unavailable
    }

    func delete(for profileID: ProfileID) async throws {
        _ = profileID
        throw FamilyStoreTestFailure.unavailable
    }
}

private enum FamilyStoreTestFailure: Error {
    case unavailable
}

private func assertThrowsErrorAsync(
    _ expression: () async throws -> Void,
    verify: (any Error) -> Void,
    file: StaticString = #filePath,
    line: UInt = #line
) async {
    do {
        try await expression()
        XCTFail("Expected an error", file: file, line: line)
    } catch {
        verify(error)
    }
}
