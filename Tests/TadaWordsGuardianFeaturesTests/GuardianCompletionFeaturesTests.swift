import Foundation
import TadaWordsContent
import TadaWordsDomain
import XCTest

@testable import TadaWordsGuardianFeatures

final class GuardianCompletionFeaturesTests: XCTestCase {
    func testReportAppliesGuardianCorrectionRebuildsProgressAndExportsCSV()
        async throws
    {
        let fixture = try await makeFixture()
        let prompt = try await addWord(
            "cat",
            mode: .read,
            profile: fixture.firstProfile,
            repository: fixture.wordPoolRepository
        )
        let context = PaceContext(
            learningMode: .read,
            deviceClass: .tablet,
            inputMethod: .speech,
            wordLength: 3
        )
        let incorrect = AttemptEvent(
            id: AttemptID(rawValue: uuid(30)),
            profileID: fixture.firstProfile.id,
            wordPromptID: prompt.id,
            learningMode: .read,
            evidence: .firstIndependentAttempt,
            outcome: .incorrect,
            timing: AttemptTiming(speechOnsetLatency: ElapsedTime(seconds: 3)),
            occurredAt: now.addingTimeInterval(-100),
            paceContext: context
        )
        let correct = AttemptEvent(
            id: AttemptID(rawValue: uuid(31)),
            profileID: fixture.firstProfile.id,
            wordPromptID: prompt.id,
            learningMode: .read,
            evidence: .firstIndependentAttempt,
            outcome: .correct,
            timing: AttemptTiming(speechOnsetLatency: ElapsedTime(seconds: 2)),
            occurredAt: now.addingTimeInterval(-50),
            paceContext: context
        )
        try await fixture.learningRepository.append(incorrect)
        try await fixture.learningRepository.append(correct)

        let before = try await fixture.store.report(for: .sevenDays)
        XCTAssertEqual(before.words.first?.accuracy, 0.5)
        XCTAssertTrue(before.csv.contains("\"cat\",read,2,1,0.500,2.50"))

        _ = try await fixture.store.correctAttempt(id: incorrect.id, to: .correct)
        let after = try await fixture.store.report(for: .sevenDays)
        let progress = try await fixture.learningRepository.progress(
            for: fixture.firstProfile.id,
            wordPromptID: prompt.id
        )
        let corrections = try await fixture.learningRepository.corrections(
            for: incorrect.id
        )

        XCTAssertEqual(after.words.first?.accuracy, 1)
        XCTAssertEqual(progress?.firstIndependentCorrectCount, 2)
        XCTAssertEqual(progress?.firstIndependentAttemptCount, 2)
        XCTAssertEqual(corrections.count, 1)
    }

    func testDeleteProfileRemovesAllAssociatedLocalRepositories() async throws {
        let fixture = try await makeFixture(includesSecondProfile: true)
        let prompt = try await addWord(
            "dog",
            mode: .write,
            profile: fixture.firstProfile,
            repository: fixture.wordPoolRepository
        )
        try await fixture.settingsRepository.save(
            .defaults(for: fixture.firstProfile.id)
        )
        try await fixture.learningRepository.append(
            AttemptEvent(
                profileID: fixture.firstProfile.id,
                wordPromptID: prompt.id,
                learningMode: .write,
                evidence: .firstIndependentAttempt,
                outcome: .correct,
                occurredAt: now
            )
        )
        try await recordTodayQuest(
            profile: fixture.firstProfile,
            repository: fixture.dailyRepository
        )
        try await fixture.childSessionRepository.saveLastSelectedProfileID(
            fixture.firstProfile.id
        )

        let deletion = try await fixture.store.deleteProfile(
            id: fixture.firstProfile.id
        )
        let deletedProfile = try await fixture.profileRepository.profile(
            id: fixture.firstProfile.id
        )
        let deletedWords = try await fixture.wordPoolRepository.entries(
            for: fixture.firstProfile.id,
            learningMode: .write,
            includingInactive: true
        )
        let deletedSettings = try await fixture.settingsRepository.settings(
            for: fixture.firstProfile.id
        )
        let deletedAttempts = try await fixture.learningRepository.attempts(
            for: fixture.firstProfile.id,
            wordPromptID: nil
        )
        let deletedCompletions = try await fixture.dailyRepository.allCompletions(
            for: fixture.firstProfile.id
        )
        let deletedRewards = try await fixture.dailyRepository.rewardGrants(
            for: fixture.firstProfile.id
        )
        let selectedAfterDeletion = try await fixture.childSessionRepository
            .lastSelectedProfileID()

        XCTAssertNotEqual(deletion.dashboard.profile.id, fixture.firstProfile.id)
        XCTAssertEqual(deletion.tombstone.profileID, fixture.firstProfile.id)
        XCTAssertEqual(deletion.tombstone.deletedAt, now)
        XCTAssertNil(deletedProfile)
        XCTAssertTrue(deletedWords.isEmpty)
        XCTAssertNil(deletedSettings)
        XCTAssertTrue(deletedAttempts.isEmpty)
        XCTAssertTrue(deletedCompletions.isEmpty)
        XCTAssertTrue(deletedRewards.isEmpty)
        XCTAssertEqual(selectedAfterDeletion, deletion.dashboard.profile.id)
        XCTAssertEqual(
            fixture.handwritingPreferenceRemover.removedProfileIDs,
            [fixture.firstProfile.id]
        )
    }

    func testGuardianProfileEditPersistsGradeAgePhotoAndUpdatedAt() async throws {
        let fixture = try await makeFixture()
        let updated = try await fixture.store.updateProfile(
            id: fixture.firstProfile.id,
            from: GuardianProfileDraft(
                displayName: "Mia",
                avatar: .photo(assetID: "embedded-jpeg:AA==", source: .photoLibrary),
                selectedWorld: .pawsAndPines,
                schoolGrade: .kindergarten,
                ageYears: 5,
                guardianUnlockedWorlds: [.pawsAndPines]
            )
        ).profile

        XCTAssertEqual(updated.schoolGrade, .kindergarten)
        XCTAssertEqual(updated.ageYears, 5)
        XCTAssertEqual(updated.selectedWorld, .pawsAndPines)
        XCTAssertEqual(updated.guardianUnlockedWorlds, [.pawsAndPines])
        XCTAssertEqual(
            updated.avatar,
            .photo(assetID: "embedded-jpeg:AA==", source: .photoLibrary)
        )
        XCTAssertEqual(updated.updatedAt, now)
    }

    func testVoiceprintEnrollmentDoesNotChangeSyncMetadataRevision() async throws {
        let fixture = try await makeFixture()

        let updated = try await fixture.store.updateVoiceprintStatus(
            profileID: fixture.firstProfile.id,
            status: .enrolled(modelVersion: "device-model", enrolledAt: now)
        ).profile

        XCTAssertEqual(updated.updatedAt, fixture.firstProfile.updatedAt)
        XCTAssertEqual(
            updated.voiceprintStatus,
            .enrolled(modelVersion: "device-model", enrolledAt: now)
        )
    }

    private let now = Date(timeIntervalSince1970: 2_000_000_000)

    private struct Fixture {
        let store: RepositoryGuardianFamilyStore
        let firstProfile: KidProfile
        let profileRepository: InMemoryKidProfileRepository
        let wordPoolRepository: InMemoryWordPoolRepository
        let settingsRepository: InMemoryPracticeSettingsRepository
        let learningRepository: InMemoryLearningRecordRepository
        let dailyRepository: InMemoryDailyQuestRepository
        let childSessionRepository: InMemoryChildSessionRepository
        let handwritingPreferenceRemover: RecordingHandwritingPreferenceRemover
    }

    private func makeFixture(
        includesSecondProfile: Bool = false
    ) async throws -> Fixture {
        let profileRepository = InMemoryKidProfileRepository()
        let wordPoolRepository = InMemoryWordPoolRepository()
        let settingsRepository = InMemoryPracticeSettingsRepository()
        let learningRepository = InMemoryLearningRecordRepository()
        let dailyRepository = InMemoryDailyQuestRepository()
        let childSessionRepository = InMemoryChildSessionRepository()
        let handwritingPreferenceRemover = RecordingHandwritingPreferenceRemover()
        let first = KidProfile(
            id: ProfileID(rawValue: uuid(1)),
            displayName: "Mia",
            avatar: .cartoonAnimal(assetID: "hare"),
            selectedWorld: .moonpetalKingdom,
            createdAt: now.addingTimeInterval(-1_000)
        )
        try await profileRepository.save(first)
        var profiles = [first]
        if includesSecondProfile {
            let second = KidProfile(
                id: ProfileID(rawValue: uuid(2)),
                displayName: "Leo",
                avatar: .cartoonAnimal(assetID: "fox"),
                selectedWorld: .buildItBay,
                createdAt: now.addingTimeInterval(-500)
            )
            try await profileRepository.save(second)
            profiles.append(second)
        }
        return Fixture(
            store: RepositoryGuardianFamilyStore(
                profiles: profiles,
                profileRepository: profileRepository,
                wordPoolRepository: wordPoolRepository,
                practiceSettingsRepository: settingsRepository,
                learningRecordRepository: learningRepository,
                dailyQuestRepository: dailyRepository,
                childSessionRepository: childSessionRepository,
                handwritingPreferenceRemover: handwritingPreferenceRemover,
                clock: CompletionFixedClock(now: now),
                timeZone: TimeZone(secondsFromGMT: 0)!
            ),
            firstProfile: first,
            profileRepository: profileRepository,
            wordPoolRepository: wordPoolRepository,
            settingsRepository: settingsRepository,
            learningRepository: learningRepository,
            dailyRepository: dailyRepository,
            childSessionRepository: childSessionRepository,
            handwritingPreferenceRemover: handwritingPreferenceRemover
        )
    }

    private func addWord(
        _ text: String,
        mode: LearningMode,
        profile: KidProfile,
        repository: InMemoryWordPoolRepository
    ) async throws -> WordPrompt {
        let prompt = try WordPrompt(learningMode: mode, text: text)
        _ = try await repository.upsert([
            WordPoolEntryDraft(
                profileID: profile.id,
                prompt: prompt,
                addedAt: now,
                source: .guardianManual,
                positionInBatch: 0
            )
        ])
        return prompt
    }

    private func recordTodayQuest(
        profile: KidProfile,
        repository: InMemoryDailyQuestRepository
    ) async throws {
        let coordinator = DailyQuestCoordinator(
            repository: repository,
            timeZone: TimeZone(secondsFromGMT: 0)!
        )
        let state = try await coordinator.loadOrCreateToday(
            candidate: QuestPlan(
                profileID: profile.id,
                configuration: QuestConfiguration(
                    learningMode: .write,
                    newWordLimit: 1,
                    reviewWordLimit: 0,
                    attentionBudget: 1,
                    contentOrder: .newThenReview
                ),
                reviewWordIDs: [],
                newWordIDs: [WordPromptID()],
                createdAt: now
            ),
            on: now
        )
        _ = try await coordinator.complete(
            try XCTUnwrap(coordinator.todayLaunch(from: state)),
            score: QuestScore(
                points: 90,
                firstIndependentCorrectCount: 1,
                firstIndependentAttemptCount: 1,
                stars: QuestStars(earned: [.completion, .accuracy]),
                personalPaceAssessment: .unavailable
            ),
            world: profile.selectedWorld,
            completedAt: now
        )
    }

    private func uuid(_ number: Int) -> UUID {
        UUID(
            uuidString: String(
                format: "B5000000-0000-0000-0000-%012X",
                number
            )
        )!
    }
}

private final class RecordingHandwritingPreferenceRemover:
    HandwritingPreferenceRemoving, @unchecked Sendable
{
    private let lock = NSLock()
    private var profileIDs: [ProfileID] = []

    var removedProfileIDs: [ProfileID] {
        lock.withLock { profileIDs }
    }

    func remove(for profileID: ProfileID) {
        lock.withLock { profileIDs.append(profileID) }
    }
}

private struct CompletionFixedClock: AppClock {
    let now: Date
}
