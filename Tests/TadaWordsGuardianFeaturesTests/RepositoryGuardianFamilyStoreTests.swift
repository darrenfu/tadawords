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
                selectedWorld: .buildItBay,
                schoolGrade: .kindergarten,
                ageYears: 5
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
        XCTAssertEqual(dashboard.profile.schoolGrade, .kindergarten)
        XCTAssertEqual(dashboard.profile.ageYears, 5)
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
                selectedWorld: .pawsAndPines,
                ageYears: 4
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

    func testPresetBothRemainsBoundToInitiatingProfileAfterSelectionChanges()
        async throws
    {
        let fixture = try await makeFixture()
        let secondProfile = try await fixture.store.createProfile(
            from: GuardianProfileDraft(
                displayName: "Leo",
                avatarAssetID: "fox",
                selectedWorld: .pawsAndPines,
                ageYears: 4
            )
        ).profile
        _ = try await fixture.store.selectProfile(id: fixture.firstProfile.id)
        let plan = PresetWordSelectionPlanner().plan(
            selectedWords: ["dog"],
            destination: .both,
            existingReadWords: [],
            existingWriteWords: []
        )

        let outcome = await GuardianPresetImportCoordinator().execute(
            profileID: fixture.firstProfile.id,
            plan: plan,
            submit: { profileID, request in
                let report = try? await fixture.store.importWords(
                    request,
                    for: profileID
                )
                if request.learningMode == .read {
                    _ = try? await fixture.store.selectProfile(id: secondProfile.id)
                }
                return report
            },
            rollback: { request in
                do {
                    try await fixture.store.setMembershipsActive(
                        ids: request.membershipIDs,
                        learningMode: request.learningMode,
                        isActive: false,
                        for: request.profileID
                    )
                    return true
                } catch {
                    return false
                }
            }
        )

        XCTAssertEqual(
            outcome,
            .success(
                GuardianPresetImportSummary(
                    addedMembershipCount: 2,
                    reactivatedMembershipCount: 0,
                    alreadyPresentMembershipCount: 0
                )
            )
        )
        let first = try await fixture.store.dashboardSnapshot(
            for: fixture.firstProfile.id
        )
        let second = try await fixture.store.dashboardSnapshot(for: secondProfile.id)
        let family = try await fixture.store.familySnapshot()
        XCTAssertEqual(first.readPool.map(\.normalizedText), ["dog"])
        XCTAssertEqual(first.writePool.map(\.normalizedText), ["dog"])
        XCTAssertTrue(second.readPool.isEmpty)
        XCTAssertTrue(second.writePool.isEmpty)
        XCTAssertEqual(family.selectedProfileID, secondProfile.id)
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
        XCTAssertNil(updated.ageYears)
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
                    avatarAssetID: "hare",
                    selectedWorld: .pawsAndPines
                )
            )
        } verify: { error in
            XCTAssertEqual(error as? GuardianFamilyStoreError, .invalidAge)
        }
        await assertThrowsErrorAsync {
            _ = try await fixture.store.createProfile(
                from: GuardianProfileDraft(
                    displayName: "Nora",
                    avatarAssetID: "not-built-in",
                    selectedWorld: .pawsAndPines,
                    ageYears: 4
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

    func testEditRejectsAgesOutsideTheThreeThroughEightProductRange() async throws {
        let fixture = try await makeFixture()

        for invalidAge in [2, 9, ProfileAgePolicy.durableAges.upperBound] {
            await assertThrowsErrorAsync {
                _ = try await fixture.store.updateProfile(
                    id: fixture.firstProfile.id,
                    from: GuardianProfileDraft(
                        displayName: "Mia",
                        avatarAssetID: "hare",
                        selectedWorld: .moonpetalKingdom,
                        ageYears: invalidAge
                    )
                )
            } verify: { error in
                XCTAssertEqual(
                    error as? GuardianFamilyStoreError,
                    .invalidAge
                )
            }
        }
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
                    selectedWorld: .buildItBay,
                    ageYears: 4
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

    func testDeletingOnlyProfileLeavesEmptyFamilyAndAllowsExplicitFirstProfile()
        async throws
    {
        let profile = KidProfile(
            displayName: "Mia",
            avatar: .cartoonAnimal(assetID: "hare"),
            selectedWorld: .moonpetalKingdom,
            voiceprintStatus: .enrolled(
                modelVersion: "voice-v1",
                enrolledAt: testDate.addingTimeInterval(-50)
            ),
            createdAt: testDate.addingTimeInterval(-100)
        )
        let profileRepository = InMemoryKidProfileRepository()
        try await profileRepository.save(profile)

        let wordPoolRepository = InMemoryWordPoolRepository()
        let prompt = try WordPrompt(learningMode: .read, text: "dog")
        _ = try await wordPoolRepository.upsert([
            WordPoolEntryDraft(
                profileID: profile.id,
                prompt: prompt,
                addedAt: testDate,
                source: .guardianManual,
                positionInBatch: 0
            )
        ])

        let practiceSettingsRepository = InMemoryPracticeSettingsRepository()
        try await practiceSettingsRepository.save(.defaults(for: profile.id))
        let learningRecordRepository = InMemoryLearningRecordRepository()
        try await learningRecordRepository.append(
            AttemptEvent(
                profileID: profile.id,
                wordPromptID: prompt.id,
                learningMode: .read,
                evidence: .firstIndependentAttempt,
                outcome: .correct,
                occurredAt: testDate
            )
        )
        let dailyQuestRepository = InMemoryDailyQuestRepository()
        let dailyQuestCoordinator = DailyQuestCoordinator(
            repository: dailyQuestRepository,
            timeZone: .gmt
        )
        let questPlan = QuestPlan(
            profileID: profile.id,
            configuration: QuestConfiguration(
                learningMode: .read,
                newWordLimit: 1,
                reviewWordLimit: 0,
                attentionBudget: 1,
                contentOrder: .newThenReview
            ),
            reviewWordIDs: [],
            newWordIDs: [prompt.id],
            createdAt: testDate
        )
        let questState = try await dailyQuestCoordinator.loadOrCreateToday(
            candidate: questPlan,
            on: testDate
        )
        _ = try await dailyQuestCoordinator.complete(
            try XCTUnwrap(dailyQuestCoordinator.todayLaunch(from: questState)),
            score: QuestScore(
                points: 40,
                firstIndependentCorrectCount: 1,
                firstIndependentAttemptCount: 1,
                stars: QuestStars(earned: [.completion]),
                personalPaceAssessment: .unavailable
            ),
            world: profile.selectedWorld,
            completedAt: testDate
        )

        let tombstoneRepository = InMemoryProfileDeletionTombstoneRepository()
        let childSessionRepository = InMemoryChildSessionRepository(
            lastSelectedProfileID: profile.id
        )
        let voiceprintRepository = FamilyStoreVoiceprintRepository()
        try await voiceprintRepository.save(
            DeviceVoiceprintTemplate(
                profileID: profile.id,
                embedding: try VoiceprintEmbedding(
                    modelIdentifier: "voice-v1",
                    vector: [1, 0]
                ),
                acceptedSegmentCount: 3,
                acceptedSpeechDuration: ElapsedTime(seconds: 12),
                enrolledAt: testDate.addingTimeInterval(-50)
            )
        )
        let store = RepositoryGuardianFamilyStore(
            profiles: [profile],
            selectedProfileID: profile.id,
            profileRepository: profileRepository,
            wordPoolRepository: wordPoolRepository,
            practiceSettingsRepository: practiceSettingsRepository,
            learningRecordRepository: learningRecordRepository,
            dailyQuestRepository: dailyQuestRepository,
            tombstoneRepository: tombstoneRepository,
            childSessionRepository: childSessionRepository,
            voiceprintRepository: voiceprintRepository,
            mutationGate: ProfileScopedMutationGate(),
            clock: FamilyFixedClock(now: testDate),
            timeZone: .gmt
        )

        let deletion = try await store.deleteProfile(id: profile.id)
        let family = try await store.familySnapshot()
        let deletedProfile = try await profileRepository.profile(id: profile.id)
        let deletedWords = try await wordPoolRepository.entries(
            for: profile.id,
            learningMode: .read,
            includingInactive: true
        )
        let deletedSettings = try await practiceSettingsRepository.settings(
            for: profile.id
        )
        let deletedAttempts = try await learningRecordRepository.attempts(
            for: profile.id,
            wordPromptID: nil
        )
        let deletedCompletions = try await dailyQuestRepository.allCompletions(
            for: profile.id
        )
        let lastSelectedProfileID =
            try await childSessionRepository
            .lastSelectedProfileID()
        let deletedVoiceprint = try await voiceprintRepository.template(
            for: profile.id
        )
        let persistedTombstone = try await tombstoneRepository.tombstone(
            for: profile.id
        )
        let pendingTombstones = try await tombstoneRepository.pendingTombstones()

        XCTAssertTrue(deletion.family.profiles.isEmpty)
        XCTAssertNil(deletion.family.selectedProfileID)
        XCTAssertNil(deletion.family.selectedProfile)
        XCTAssertNil(deletion.dashboard)
        XCTAssertEqual(family.profiles, [])
        XCTAssertNil(family.selectedProfileID)
        XCTAssertNil(deletedProfile)
        XCTAssertTrue(deletedWords.isEmpty)
        XCTAssertNil(deletedSettings)
        XCTAssertTrue(deletedAttempts.isEmpty)
        XCTAssertTrue(deletedCompletions.isEmpty)
        XCTAssertNil(lastSelectedProfileID)
        XCTAssertNil(deletedVoiceprint)
        XCTAssertEqual(persistedTombstone, deletion.tombstone)
        XCTAssertTrue(pendingTombstones.isEmpty)

        let firstNewDashboard = try await store.createProfile(
            from: GuardianProfileDraft(
                displayName: "Nora",
                avatarAssetID: "fox",
                selectedWorld: .pawsAndPines,
                ageYears: 4
            )
        )
        let rebuiltFamily = try await store.familySnapshot()

        XCTAssertNotEqual(firstNewDashboard.profile.id, profile.id)
        XCTAssertEqual(rebuiltFamily.profiles, [firstNewDashboard.profile])
        XCTAssertEqual(
            rebuiltFamily.selectedProfileID,
            firstNewDashboard.profile.id
        )
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

private actor FamilyStoreVoiceprintRepository: DeviceVoiceprintRepository {
    private var templates: [ProfileID: DeviceVoiceprintTemplate] = [:]

    func template(
        for profileID: ProfileID
    ) async throws -> DeviceVoiceprintTemplate? {
        templates[profileID]
    }

    func save(_ template: DeviceVoiceprintTemplate) async throws {
        templates[template.profileID] = template
    }

    func delete(for profileID: ProfileID) async throws {
        templates.removeValue(forKey: profileID)
    }
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
