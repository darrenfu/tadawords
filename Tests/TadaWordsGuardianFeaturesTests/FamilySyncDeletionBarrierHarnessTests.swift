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

    func testVoiceprintFailureLeavesDeletionPendingAndSealsOrdinaryWrites()
        async throws
    {
        let fixture = try await makeVoiceprintDeletionFixture(
            failsVoiceprintDeletion: true
        )
        defer { fixture.remove() }

        do {
            _ = try await fixture.store.deleteProfile(
                id: fixture.deletedProfile.id
            )
            XCTFail("A failed voiceprint purge must not report deletion complete")
        } catch VoiceprintGuardianDeletionFailure.cannotDeleteVoiceprint {
            // Expected: the durable tombstone remains pending for recovery.
        }

        let retainedProfile = try await fixture.profiles.profile(
            id: fixture.deletedProfile.id
        )
        let retainedWords = try await fixture.words.entries(
            for: fixture.deletedProfile.id,
            learningMode: .read,
            includingInactive: true
        )
        let retainedSettings = try await fixture.settings.settings(
            for: fixture.deletedProfile.id
        )
        let retainedVoiceprint = try await fixture.voiceprints.template(
            for: fixture.deletedProfile.id
        )
        let pending = try await fixture.tombstones.pendingTombstones()
        let wasCommitted = await fixture.tombstones.wasCommitted(
            fixture.deletedProfile.id
        )

        XCTAssertNotNil(retainedProfile)
        XCTAssertEqual(retainedWords.count, 1)
        XCTAssertNotNil(retainedSettings)
        XCTAssertNotNil(retainedVoiceprint)
        XCTAssertEqual(pending.map(\.profileID), [fixture.deletedProfile.id])
        XCTAssertFalse(wasCommitted)
        XCTAssertFalse(
            fixture.log.snapshot().contains(.tombstoneCommitted),
            "A voiceprint failure must not advance the deletion to committed"
        )

        do {
            try await fixture.settings.save(
                .defaults(for: fixture.deletedProfile.id)
            )
            XCTFail("A durable deletion tombstone must seal later normal writes")
        } catch let error as ProfileScopedMutationGateError {
            XCTAssertEqual(
                error,
                .terminalProfile(fixture.deletedProfile.id)
            )
        }
    }

    func testVoiceprintIsDeletedBeforeTombstoneIsCommitted() async throws {
        let fixture = try await makeVoiceprintDeletionFixture(
            failsVoiceprintDeletion: false
        )
        defer { fixture.remove() }

        let result = try await fixture.store.deleteProfile(
            id: fixture.deletedProfile.id
        )

        let retainedVoiceprint = try await fixture.voiceprints.template(
            for: fixture.deletedProfile.id
        )
        let retainedProfile = try await fixture.profiles.profile(
            id: fixture.deletedProfile.id
        )
        let pending = try await fixture.tombstones.pendingTombstones()
        let wasCommitted = await fixture.tombstones.wasCommitted(
            fixture.deletedProfile.id
        )
        let events = fixture.log.snapshot()
        let savedIndex = try XCTUnwrap(events.firstIndex(of: .tombstoneSaved))
        let voiceprintIndex = try XCTUnwrap(
            events.firstIndex(of: .voiceprintDeleted)
        )
        let committedIndex = try XCTUnwrap(
            events.firstIndex(of: .tombstoneCommitted)
        )

        XCTAssertEqual(result.tombstone.profileID, fixture.deletedProfile.id)
        XCTAssertNil(retainedVoiceprint)
        XCTAssertNil(retainedProfile)
        XCTAssertTrue(pending.isEmpty)
        XCTAssertTrue(wasCommitted)
        XCTAssertLessThan(savedIndex, voiceprintIndex)
        XCTAssertLessThan(
            voiceprintIndex,
            committedIndex,
            "Sensitive voice data must be gone before deletion is committed"
        )
    }

    private func makeVoiceprintDeletionFixture(
        failsVoiceprintDeletion: Bool
    ) async throws -> VoiceprintGuardianDeletionFixture {
        let now = Date(timeIntervalSince1970: 2_172_000_200)
        let deletedProfile = KidProfile(
            displayName: "Mia",
            avatar: .cartoonAnimal(assetID: "hare"),
            selectedWorld: .moonpetalKingdom,
            voiceprintStatus: .enrolled(
                modelVersion: "voice-v1",
                enrolledAt: now.addingTimeInterval(-50)
            ),
            createdAt: now.addingTimeInterval(-200)
        )
        let fallbackProfile = KidProfile(
            displayName: "Leo",
            avatar: .cartoonAnimal(assetID: "fox"),
            selectedWorld: .buildItBay,
            createdAt: now.addingTimeInterval(-100)
        )
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(
            "TadaGuardianVoiceprintDeletion-\(UUID().uuidString)",
            isDirectory: true
        )
        try FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true
        )
        let gate = ProfileScopedMutationGate()
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
        let settings = LocalJSONPracticeSettingsRepository(
            snapshotURL: directory.appendingPathComponent("settings.json"),
            mutationGate: gate
        )
        try await settings.save(.defaults(for: deletedProfile.id))
        let log = VoiceprintGuardianDeletionEventLog()
        let tombstones = TrackingGuardianDeletionTombstoneRepository(log: log)
        let voiceprints = TrackingGuardianVoiceprintRepository(
            log: log,
            failsDeletion: failsVoiceprintDeletion
        )
        try await voiceprints.save(
            DeviceVoiceprintTemplate(
                profileID: deletedProfile.id,
                embedding: try VoiceprintEmbedding(
                    modelIdentifier: "voice-v1",
                    vector: [1, 0]
                ),
                acceptedSegmentCount: 3,
                acceptedSpeechDuration: ElapsedTime(seconds: 12),
                enrolledAt: now.addingTimeInterval(-50)
            )
        )
        let store = RepositoryGuardianFamilyStore(
            profiles: [deletedProfile, fallbackProfile],
            selectedProfileID: deletedProfile.id,
            profileRepository: profiles,
            wordPoolRepository: words,
            practiceSettingsRepository: settings,
            tombstoneRepository: tombstones,
            voiceprintRepository: voiceprints,
            mutationGate: gate,
            clock: DeletionBarrierClock(now: now)
        )
        return VoiceprintGuardianDeletionFixture(
            directory: directory,
            deletedProfile: deletedProfile,
            store: store,
            profiles: profiles,
            words: words,
            settings: settings,
            tombstones: tombstones,
            voiceprints: voiceprints,
            log: log
        )
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

private struct VoiceprintGuardianDeletionFixture {
    let directory: URL
    let deletedProfile: KidProfile
    let store: RepositoryGuardianFamilyStore
    let profiles: InMemoryKidProfileRepository
    let words: InMemoryWordPoolRepository
    let settings: LocalJSONPracticeSettingsRepository
    let tombstones: TrackingGuardianDeletionTombstoneRepository
    let voiceprints: TrackingGuardianVoiceprintRepository
    let log: VoiceprintGuardianDeletionEventLog

    func remove() {
        try? FileManager.default.removeItem(at: directory)
    }
}

private enum VoiceprintGuardianDeletionEvent: Equatable {
    case tombstoneSaved
    case voiceprintDeleteStarted
    case voiceprintDeleted
    case tombstoneCommitted
}

private final class VoiceprintGuardianDeletionEventLog: @unchecked Sendable {
    private let lock = NSLock()
    private var events: [VoiceprintGuardianDeletionEvent] = []

    func append(_ event: VoiceprintGuardianDeletionEvent) {
        lock.lock()
        events.append(event)
        lock.unlock()
    }

    func snapshot() -> [VoiceprintGuardianDeletionEvent] {
        lock.lock()
        defer { lock.unlock() }
        return events
    }
}

private actor TrackingGuardianDeletionTombstoneRepository:
    ProfileDeletionTombstoneRepository
{
    private let log: VoiceprintGuardianDeletionEventLog
    private var tombstoneByProfile: [ProfileID: ProfileDeletionTombstone] = [:]
    private var pendingProfileIDs = Set<ProfileID>()
    private var committedProfileIDs = Set<ProfileID>()

    init(log: VoiceprintGuardianDeletionEventLog) {
        self.log = log
    }

    func tombstones() async throws -> [ProfileDeletionTombstone] {
        Array(tombstoneByProfile.values)
    }

    func pendingTombstones() async throws -> [ProfileDeletionTombstone] {
        tombstoneByProfile.values.filter {
            pendingProfileIDs.contains($0.profileID)
        }
    }

    func tombstone(
        for profileID: ProfileID
    ) async throws -> ProfileDeletionTombstone? {
        tombstoneByProfile[profileID]
    }

    func save(_ tombstone: ProfileDeletionTombstone) async throws {
        tombstoneByProfile[tombstone.profileID] = tombstone
        pendingProfileIDs.insert(tombstone.profileID)
        log.append(.tombstoneSaved)
    }

    func markCommitted(for profileID: ProfileID) async throws {
        committedProfileIDs.insert(profileID)
        pendingProfileIDs.remove(profileID)
        log.append(.tombstoneCommitted)
    }

    func delete(for profileID: ProfileID) async throws {
        tombstoneByProfile.removeValue(forKey: profileID)
        pendingProfileIDs.remove(profileID)
        committedProfileIDs.remove(profileID)
    }

    func wasCommitted(_ profileID: ProfileID) -> Bool {
        committedProfileIDs.contains(profileID)
    }
}

private enum VoiceprintGuardianDeletionFailure: Error {
    case cannotDeleteVoiceprint
}

private actor TrackingGuardianVoiceprintRepository:
    DeviceVoiceprintRepository
{
    private let log: VoiceprintGuardianDeletionEventLog
    private let failsDeletion: Bool
    private var templates: [ProfileID: DeviceVoiceprintTemplate] = [:]

    init(
        log: VoiceprintGuardianDeletionEventLog,
        failsDeletion: Bool
    ) {
        self.log = log
        self.failsDeletion = failsDeletion
    }

    func template(
        for profileID: ProfileID
    ) async throws -> DeviceVoiceprintTemplate? {
        templates[profileID]
    }

    func save(_ template: DeviceVoiceprintTemplate) async throws {
        templates[template.profileID] = template
    }

    func delete(for profileID: ProfileID) async throws {
        log.append(.voiceprintDeleteStarted)
        guard !failsDeletion else {
            throw VoiceprintGuardianDeletionFailure.cannotDeleteVoiceprint
        }
        templates.removeValue(forKey: profileID)
        log.append(.voiceprintDeleted)
    }
}
