import Foundation
import TadaWordsContent
import TadaWordsDomain
import XCTest

final class RepositoryFamilySyncRecordStoreTests: XCTestCase {
    func testPracticeSettingsUseTheirOwnSnapshotRevision() async throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        try await fixture.profiles.save(fixture.profile)
        try await fixture.settings.save(.defaults(for: fixture.profile.id))
        _ = try await fixture.words.upsert([
            WordPoolEntryDraft(
                profileID: fixture.profile.id,
                prompt: try WordPrompt(learningMode: .read, text: "the"),
                addedAt: fixture.now,
                source: .guardianManual,
                positionInBatch: 0
            )
        ])
        let wordRevision = fixture.now.addingTimeInterval(-2_000)
        let settingsRevision = fixture.now.addingTimeInterval(-200)
        try FileManager.default.setAttributes(
            [.modificationDate: wordRevision],
            ofItemAtPath: fixture.words.snapshotURL.path
        )
        try FileManager.default.setAttributes(
            [.modificationDate: settingsRevision],
            ofItemAtPath: fixture.settings.snapshotURL.path
        )

        let records = try await fixture.makeStore(
            tombstones: fixture.tombstones
        ).records(for: fixture.profile.id)
        let settingsRecord = try XCTUnwrap(
            records.first { $0.kind == .practiceSettings }
        )

        XCTAssertEqual(settingsRecord.updatedAt, settingsRevision)
        XCTAssertNotEqual(settingsRecord.updatedAt, wordRevision)
    }

    func testProfileSyncScrubsAndNeverOverwritesDeviceVoiceprintStatus()
        async throws
    {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let enrolled = KidProfile(
            id: fixture.profile.id,
            displayName: fixture.profile.displayName,
            avatar: fixture.profile.avatar,
            selectedWorld: fixture.profile.selectedWorld,
            selectedCartoonIconAssetID: "fox",
            voiceprintStatus: .enrolled(
                modelVersion: "local-model",
                enrolledAt: fixture.now
            ),
            createdAt: fixture.profile.createdAt
        )
        try await fixture.profiles.save(enrolled)
        let store = fixture.makeStore(tombstones: fixture.tombstones)

        let records = try await store.records(for: enrolled.id)
        let profileRecord = try XCTUnwrap(records.first { $0.kind == .profile })
        let exported = try JSONDecoder.tada.decode(
            KidProfile.self,
            from: profileRecord.payload
        )
        XCTAssertEqual(exported.voiceprintStatus, .notEnrolled)
        XCTAssertEqual(exported.selectedCartoonIconAssetID, "fox")

        try await store.apply([profileRecord], for: enrolled.id)
        let loadedProfile = try await fixture.profiles.profile(id: enrolled.id)
        let saved = try XCTUnwrap(loadedProfile)
        XCTAssertEqual(saved.voiceprintStatus, enrolled.voiceprintStatus)
        XCTAssertEqual(saved.selectedCartoonIconAssetID, "fox")
    }

    func testCommittedDeletionSurvivesRestartAndExportsProfileTombstone()
        async throws
    {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let profile = fixture.profile
        try await fixture.profiles.save(profile)
        let deletion = ProfileDeletionTombstone(
            profileID: profile.id,
            deletedAt: fixture.now
        )
        try await fixture.tombstones.save(deletion)
        try await fixture.tombstones.markCommitted(for: profile.id)

        let restartedTombstones = LocalJSONProfileDeletionTombstoneRepository(
            snapshotURL: fixture.tombstoneURL
        )
        let store = fixture.makeStore(tombstones: restartedTombstones)
        let profileIDs = try await store.profileIDsForSync()
        let records = try await store.records(for: profile.id)

        XCTAssertEqual(profileIDs, [profile.id])
        XCTAssertEqual(records.count, 1)
        XCTAssertEqual(records.first?.recordName, "profile-\(profile.id)")
        XCTAssertEqual(records.first?.kind, .profileDeletion)
        XCTAssertEqual(records.first?.isDeleted, true)
        XCTAssertEqual(
            try JSONDecoder.tada.decode(
                ProfileDeletionTombstone.self,
                from: try XCTUnwrap(records.first?.payload)
            ),
            deletion
        )
    }

    func testApplyingDeletionPurgesDataAndCommitsCrashJournal() async throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let profile = fixture.profile
        try await fixture.profiles.save(profile)
        try await fixture.settings.save(.defaults(for: profile.id))
        let deletion = ProfileDeletionTombstone(
            profileID: profile.id,
            deletedAt: fixture.now
        )
        let payload = try JSONEncoder.tada.encode(deletion)
        let handwritingPreferenceRemover =
            RecordingSyncHandwritingPreferenceRemover()

        try await fixture.makeStore(
            tombstones: fixture.tombstones,
            handwritingPreferenceRemover: handwritingPreferenceRemover
        ).apply(
            [
                FamilySyncRecord(
                    recordName: "profile-\(profile.id)",
                    profileID: profile.id,
                    kind: .profileDeletion,
                    payload: payload,
                    updatedAt: fixture.now,
                    deviceID: "remote",
                    isDeleted: true
                )
            ],
            for: profile.id
        )

        let savedProfile = try await fixture.profiles.profile(id: profile.id)
        let savedSettings = try await fixture.settings.settings(for: profile.id)
        let savedTombstone = try await fixture.tombstones.tombstone(for: profile.id)
        let pending = try await fixture.tombstones.pendingTombstones()
        XCTAssertNil(savedProfile)
        XCTAssertNil(savedSettings)
        XCTAssertEqual(savedTombstone, deletion)
        XCTAssertTrue(pending.isEmpty)
        XCTAssertEqual(
            handwritingPreferenceRemover.removedProfileIDs,
            [profile.id]
        )
    }
}

private struct Fixture {
    let directory: URL
    let profiles: LocalJSONKidProfileRepository
    let words: LocalJSONWordPoolRepository
    let settings: LocalJSONPracticeSettingsRepository
    let learning: LocalJSONLearningRecordRepository
    let daily: LocalJSONDailyQuestRepository
    let tombstones: LocalJSONProfileDeletionTombstoneRepository
    let tombstoneURL: URL
    let now = Date(timeIntervalSince1970: 2_000_000_000)
    let profile: KidProfile

    init() throws {
        directory = FileManager.default.temporaryDirectory.appendingPathComponent(
            "TadaSync-\(UUID().uuidString)",
            isDirectory: true
        )
        try FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true
        )
        profiles = LocalJSONKidProfileRepository(
            snapshotURL: directory.appendingPathComponent("profiles.json")
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
        tombstoneURL = directory.appendingPathComponent("deletions.json")
        tombstones = LocalJSONProfileDeletionTombstoneRepository(
            snapshotURL: tombstoneURL
        )
        profile = KidProfile(
            displayName: "Mia",
            avatar: .cartoonAnimal(assetID: "hare"),
            selectedWorld: .moonpetalKingdom,
            createdAt: now.addingTimeInterval(-100)
        )
    }

    func makeStore(
        tombstones: any ProfileDeletionTombstoneRepository,
        handwritingPreferenceRemover: (any HandwritingPreferenceRemoving)? = nil
    ) -> RepositoryFamilySyncRecordStore {
        RepositoryFamilySyncRecordStore(
            profileRepository: profiles,
            wordPoolRepository: words,
            practiceSettingsRepository: settings,
            learningRepository: learning,
            dailyQuestRepository: daily,
            tombstoneRepository: tombstones,
            handwritingPreferenceRemover: handwritingPreferenceRemover,
            deviceID: "device-a"
        )
    }

    func remove() {
        try? FileManager.default.removeItem(at: directory)
    }
}

private final class RecordingSyncHandwritingPreferenceRemover:
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

extension JSONEncoder {
    fileprivate static var tada: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .secondsSince1970
        return encoder
    }
}

extension JSONDecoder {
    fileprivate static var tada: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .secondsSince1970
        return decoder
    }
}
