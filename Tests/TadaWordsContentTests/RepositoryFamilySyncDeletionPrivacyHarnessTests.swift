import Foundation
import TadaWordsDomain
import XCTest

@testable import TadaWordsContent

final class RepositoryFamilySyncDeletionPrivacyHarnessTests: XCTestCase {
    func testDeletionClearsSessionAndVoiceprintBeforeTombstoneCommit()
        async throws
    {
        let fixture = try DeletionPrivacyFixture()
        defer { fixture.remove() }
        try await fixture.profiles.save(fixture.profile)
        try await fixture.session.saveLastSelectedProfileID(fixture.profile.id)
        try await fixture.voiceprints.save(fixture.voiceprint)
        let tombstone = ProfileDeletionTombstone(
            profileID: fixture.profile.id,
            deletedAt: fixture.now
        )
        let record = FamilySyncRecord(
            recordName: "profile-\(fixture.profile.id)",
            profileID: fixture.profile.id,
            kind: .profileDeletion,
            payload: try InspectableSnapshotJSONCodec.makeEncoder().encode(
                tombstone
            ),
            updatedAt: fixture.now,
            deviceID: "owner-device",
            isDeleted: true,
            logicalRevision: FamilySyncLogicalRevision(
                counter: 8,
                deviceID: "owner-device"
            )
        )
        let store = RepositoryFamilySyncRecordStore(
            profileRepository: fixture.profiles,
            wordPoolRepository: fixture.words,
            practiceSettingsRepository: fixture.settings,
            learningRepository: fixture.learning,
            dailyQuestRepository: fixture.daily,
            tombstoneRepository: fixture.tombstones,
            childSessionRepository: fixture.session,
            voiceprintRepository: fixture.voiceprints,
            deviceID: "participant-device"
        )

        try await store.validate([record], for: fixture.profile.id)
        try await store.apply([record], for: fixture.profile.id)

        let selectedProfileID = try await fixture.session
            .lastSelectedProfileID()
        let retainedVoiceprint = try await fixture.voiceprints.template(
            for: fixture.profile.id
        )
        let retainedProfile = try await fixture.profiles.profile(
            id: fixture.profile.id
        )
        let pending = try await fixture.tombstones.pendingTombstones()
        let events = fixture.log.snapshot()

        XCTAssertNil(selectedProfileID)
        XCTAssertNil(retainedVoiceprint)
        XCTAssertNil(retainedProfile)
        XCTAssertTrue(pending.isEmpty)
        let savedIndex = try XCTUnwrap(events.firstIndex(of: .tombstoneSaved))
        let sessionIndex = try XCTUnwrap(events.firstIndex(of: .sessionCleared))
        let voiceprintIndex = try XCTUnwrap(
            events.firstIndex(of: .voiceprintDeleted)
        )
        let committedIndex = try XCTUnwrap(
            events.firstIndex(of: .tombstoneCommitted)
        )
        XCTAssertLessThan(savedIndex, sessionIndex)
        XCTAssertLessThan(savedIndex, voiceprintIndex)
        XCTAssertLessThan(sessionIndex, committedIndex)
        XCTAssertLessThan(voiceprintIndex, committedIndex)
    }
}

private struct DeletionPrivacyFixture {
    let directory: URL
    let now = Date(timeIntervalSince1970: 2_175_000_000)
    let profile: KidProfile
    let profiles = InMemoryKidProfileRepository()
    let words: LocalJSONWordPoolRepository
    let settings: LocalJSONPracticeSettingsRepository
    let learning: LocalJSONLearningRecordRepository
    let daily: LocalJSONDailyQuestRepository
    let log = DeletionPrivacyEventLog()
    let tombstones: TrackingDeletionTombstoneRepository
    let session: TrackingChildSessionRepository
    let voiceprints: TrackingDeviceVoiceprintRepository
    let voiceprint: DeviceVoiceprintTemplate

    init() throws {
        directory = FileManager.default.temporaryDirectory.appendingPathComponent(
            "TadaDeletionPrivacy-\(UUID().uuidString)",
            isDirectory: true
        )
        try FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true
        )
        profile = KidProfile(
            displayName: "Mia",
            avatar: .cartoonAnimal(assetID: "hare"),
            selectedWorld: .moonpetalKingdom,
            createdAt: now
        )
        words = LocalJSONWordPoolRepository(
            snapshotURL: directory.appendingPathComponent("words.json")
        )
        settings = LocalJSONPracticeSettingsRepository(
            snapshotURL: directory.appendingPathComponent("settings.json")
        )
        learning = LocalJSONLearningRecordRepository(
            snapshotURL: directory.appendingPathComponent("learning.json")
        )
        daily = LocalJSONDailyQuestRepository(
            snapshotURL: directory.appendingPathComponent("daily.json")
        )
        tombstones = TrackingDeletionTombstoneRepository(log: log)
        session = TrackingChildSessionRepository(log: log)
        voiceprints = TrackingDeviceVoiceprintRepository(log: log)
        voiceprint = DeviceVoiceprintTemplate(
            profileID: profile.id,
            embedding: try VoiceprintEmbedding(
                modelIdentifier: "test-voice-v1",
                vector: [1, 0]
            ),
            acceptedSegmentCount: 3,
            acceptedSpeechDuration: ElapsedTime(seconds: 12),
            enrolledAt: now
        )
    }

    func remove() {
        try? FileManager.default.removeItem(at: directory)
    }
}

private enum DeletionPrivacyEvent: Equatable {
    case tombstoneSaved
    case sessionCleared
    case voiceprintDeleted
    case tombstoneCommitted
}

private final class DeletionPrivacyEventLog: @unchecked Sendable {
    private let lock = NSLock()
    private var events: [DeletionPrivacyEvent] = []

    func append(_ event: DeletionPrivacyEvent) {
        lock.lock()
        events.append(event)
        lock.unlock()
    }

    func snapshot() -> [DeletionPrivacyEvent] {
        lock.lock()
        defer { lock.unlock() }
        return events
    }
}

private actor TrackingDeletionTombstoneRepository:
    ProfileDeletionTombstoneRepository
{
    private let log: DeletionPrivacyEventLog
    private var tombstoneByProfile: [ProfileID: ProfileDeletionTombstone] = [:]
    private var pending: Set<ProfileID> = []

    init(log: DeletionPrivacyEventLog) {
        self.log = log
    }

    func tombstones() async throws -> [ProfileDeletionTombstone] {
        Array(tombstoneByProfile.values)
    }

    func pendingTombstones() async throws -> [ProfileDeletionTombstone] {
        tombstoneByProfile.values.filter { pending.contains($0.profileID) }
    }

    func tombstone(
        for profileID: ProfileID
    ) async throws -> ProfileDeletionTombstone? {
        tombstoneByProfile[profileID]
    }

    func save(_ tombstone: ProfileDeletionTombstone) async throws {
        tombstoneByProfile[tombstone.profileID] = tombstone
        pending.insert(tombstone.profileID)
        log.append(.tombstoneSaved)
    }

    func markCommitted(for profileID: ProfileID) async throws {
        log.append(.tombstoneCommitted)
        pending.remove(profileID)
    }

    func delete(for profileID: ProfileID) async throws {
        tombstoneByProfile.removeValue(forKey: profileID)
        pending.remove(profileID)
    }
}

private actor TrackingChildSessionRepository: ChildSessionRepository {
    private let log: DeletionPrivacyEventLog
    private var selectedProfileID: ProfileID?

    init(log: DeletionPrivacyEventLog) {
        self.log = log
    }

    func lastSelectedProfileID() async throws -> ProfileID? {
        selectedProfileID
    }

    func saveLastSelectedProfileID(_ profileID: ProfileID) async throws {
        selectedProfileID = profileID
    }

    func clearLastSelectedProfileID() async throws {
        selectedProfileID = nil
        log.append(.sessionCleared)
    }
}

private actor TrackingDeviceVoiceprintRepository: DeviceVoiceprintRepository {
    private let log: DeletionPrivacyEventLog
    private var templates: [ProfileID: DeviceVoiceprintTemplate] = [:]

    init(log: DeletionPrivacyEventLog) {
        self.log = log
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
        templates.removeValue(forKey: profileID)
        log.append(.voiceprintDeleted)
    }
}
