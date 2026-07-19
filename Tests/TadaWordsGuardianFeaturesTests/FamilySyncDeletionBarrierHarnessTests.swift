import Foundation
import TadaWordsContent
import TadaWordsDomain
import XCTest

@testable import TadaWordsGuardianFeatures

final class FamilySyncDeletionBarrierHarnessTests: XCTestCase {
    func testDurableLocalTombstoneFailurePreventsEveryPayloadPurge()
        async throws
    {
        let now = Date(timeIntervalSince1970: 2_172_000_000)
        let deletedProfile = KidProfile(
            displayName: "Mia",
            avatar: .cartoonAnimal(assetID: "hare"),
            selectedWorld: .moonpetalKingdom,
            createdAt: now.addingTimeInterval(-200)
        )
        let fallbackProfile = KidProfile(
            displayName: "Leo",
            avatar: .cartoonAnimal(assetID: "fox"),
            selectedWorld: .buildItBay,
            createdAt: now.addingTimeInterval(-100)
        )
        let profiles = InMemoryKidProfileRepository()
        try await profiles.save(deletedProfile)
        try await profiles.save(fallbackProfile)
        let words = InMemoryWordPoolRepository(deviceID: "owner-device")
        let prompt = try WordPrompt(learningMode: .read, text: "dog")
        _ = try await words.upsert([
            WordPoolEntryDraft(
                profileID: deletedProfile.id,
                prompt: prompt,
                addedAt: now,
                source: .guardianManual,
                positionInBatch: 0
            )
        ])
        let settings = InMemoryPracticeSettingsRepository()
        try await settings.save(.defaults(for: deletedProfile.id))
        let learning = InMemoryLearningRecordRepository()
        try await learning.append(
            AttemptEvent(
                profileID: deletedProfile.id,
                wordPromptID: prompt.id,
                learningMode: .read,
                evidence: .firstIndependentAttempt,
                outcome: .correct,
                occurredAt: now
            )
        )
        let daily = InMemoryDailyQuestRepository()
        let tombstones = FailingDeletionTombstoneRepository()
        let store = RepositoryGuardianFamilyStore(
            profiles: [deletedProfile, fallbackProfile],
            selectedProfileID: deletedProfile.id,
            profileRepository: profiles,
            wordPoolRepository: words,
            practiceSettingsRepository: settings,
            learningRecordRepository: learning,
            dailyQuestRepository: daily,
            tombstoneRepository: tombstones,
            clock: DeletionBarrierClock(now: now)
        )

        do {
            _ = try await store.deleteProfile(id: deletedProfile.id)
            XCTFail("Deletion must stop when its durable local barrier cannot be written")
        } catch DeletionBarrierFailure.cannotPersistTombstone {
            // Expected: no payload repository may have been touched.
        }

        let retainedProfile = try await profiles.profile(id: deletedProfile.id)
        XCTAssertNotNil(
            retainedProfile,
            "No local purge may begin before the durable local tombstone commit"
        )
        let retainedWords = try await words.entries(
            for: deletedProfile.id,
            learningMode: .read,
            includingInactive: true
        )
        let retainedSettings = try await settings.settings(for: deletedProfile.id)
        let retainedAttempts = try await learning.attempts(
            for: deletedProfile.id,
            wordPromptID: nil
        )
        XCTAssertEqual(retainedWords.count, 1)
        XCTAssertNotNil(retainedSettings)
        XCTAssertEqual(retainedAttempts.count, 1)
    }

    func testSuccessfulLocalTombstoneAllowsImmediateLocalPrivacyPurge()
        async throws
    {
        let now = Date(timeIntervalSince1970: 2_172_000_100)
        let deletedProfile = KidProfile(
            displayName: "Mia",
            avatar: .cartoonAnimal(assetID: "hare"),
            selectedWorld: .moonpetalKingdom,
            createdAt: now.addingTimeInterval(-200)
        )
        let fallbackProfile = KidProfile(
            displayName: "Leo",
            avatar: .cartoonAnimal(assetID: "fox"),
            selectedWorld: .buildItBay,
            createdAt: now.addingTimeInterval(-100)
        )
        let profiles = InMemoryKidProfileRepository()
        try await profiles.save(deletedProfile)
        try await profiles.save(fallbackProfile)
        let words = InMemoryWordPoolRepository(deviceID: "owner-device")
        _ = try await words.upsert([
            WordPoolEntryDraft(
                profileID: deletedProfile.id,
                prompt: try WordPrompt(learningMode: .read, text: "dog"),
                addedAt: now,
                source: .guardianManual,
                positionInBatch: 0
            )
        ])
        let settings = InMemoryPracticeSettingsRepository()
        try await settings.save(.defaults(for: deletedProfile.id))
        let learning = InMemoryLearningRecordRepository()
        let tombstones = InMemoryProfileDeletionTombstoneRepository()
        let store = RepositoryGuardianFamilyStore(
            profiles: [deletedProfile, fallbackProfile],
            selectedProfileID: deletedProfile.id,
            profileRepository: profiles,
            wordPoolRepository: words,
            practiceSettingsRepository: settings,
            learningRecordRepository: learning,
            dailyQuestRepository: InMemoryDailyQuestRepository(),
            tombstoneRepository: tombstones,
            clock: DeletionBarrierClock(now: now)
        )

        let result = try await store.deleteProfile(id: deletedProfile.id)
        let persistedTombstone = try await tombstones.tombstone(
            for: deletedProfile.id
        )
        let pending = try await tombstones.pendingTombstones()
        let removedProfile = try await profiles.profile(id: deletedProfile.id)
        let removedWords = try await words.entries(
            for: deletedProfile.id,
            learningMode: .read,
            includingInactive: true
        )

        XCTAssertEqual(persistedTombstone, result.tombstone)
        XCTAssertTrue(pending.isEmpty)
        XCTAssertNil(removedProfile)
        XCTAssertTrue(removedWords.isEmpty)
    }
}

private struct DeletionBarrierClock: AppClock {
    let now: Date
}

private enum DeletionBarrierFailure: Error {
    case cannotPersistTombstone
}

private actor FailingDeletionTombstoneRepository:
    ProfileDeletionTombstoneRepository
{
    func tombstones() async throws -> [ProfileDeletionTombstone] { [] }

    func pendingTombstones() async throws -> [ProfileDeletionTombstone] { [] }

    func tombstone(
        for profileID: ProfileID
    ) async throws -> ProfileDeletionTombstone? {
        _ = profileID
        return nil
    }

    func save(_ tombstone: ProfileDeletionTombstone) async throws {
        _ = tombstone
        throw DeletionBarrierFailure.cannotPersistTombstone
    }

    func markCommitted(for profileID: ProfileID) async throws {
        _ = profileID
    }

    func delete(for profileID: ProfileID) async throws {
        _ = profileID
    }
}
