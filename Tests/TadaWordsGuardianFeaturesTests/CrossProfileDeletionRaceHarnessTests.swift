import Foundation
import TadaWordsDomain
import XCTest

@testable import TadaWordsContent
@testable import TadaWordsGuardianFeatures

final class CrossProfileDeletionRaceHarnessTests: XCTestCase {
    func testLocalAndRemoteDeletesConvergeToEmptyFamilyWithoutStaleDashboard()
        async throws
    {
        let fixture = try await CrossProfileDeletionRaceFixture()
        defer { fixture.remove() }

        let localDelete = Task {
            try await fixture.guardianStore.deleteProfile(
                id: fixture.localProfile.id
            )
        }
        let remoteDelete = Task {
            try await fixture.syncStore.apply(
                [fixture.remoteDeletionRecord()],
                for: fixture.remoteProfile.id
            )
        }

        let localResult = try await localDelete.value
        try await remoteDelete.value

        let profiles = try await fixture.profiles.profiles()
        let tombstones = try await fixture.tombstones.tombstones()
        let pendingTombstones = try await fixture.tombstones
            .pendingTombstones()
        let selectedProfileID = try await fixture.session
            .lastSelectedProfileID()
        let currentFamily = try await fixture.guardianStore.familySnapshot()

        XCTAssertEqual(profiles, [])
        XCTAssertEqual(
            Set(tombstones.map(\.profileID)),
            Set([fixture.localProfile.id, fixture.remoteProfile.id])
        )
        XCTAssertEqual(pendingTombstones, [])
        XCTAssertNil(selectedProfileID)
        XCTAssertEqual(localResult.family.profiles, [])
        XCTAssertNil(localResult.family.selectedProfileID)
        XCTAssertNil(localResult.dashboard)
        XCTAssertEqual(currentFamily.profiles, [])
        XCTAssertNil(currentFamily.selectedProfileID)

        let observedInterleaving = await fixture.profiles
            .observedRequiredInterleaving
        XCTAssertTrue(observedInterleaving)

        for profile in [fixture.localProfile, fixture.remoteProfile] {
            do {
                try await fixture.profiles.save(profile)
                XCTFail("A late Profile write resurrected \(profile.id)")
            } catch let error as ProfileScopedMutationGateError {
                XCTAssertEqual(error, .terminalProfile(profile.id))
            }

            do {
                try await fixture.settings.save(
                    .defaults(for: profile.id)
                )
                XCTFail("Late settings entered deleted Profile \(profile.id)")
            } catch let error as ProfileScopedMutationGateError {
                XCTAssertEqual(error, .terminalProfile(profile.id))
            }
        }

        let profilesAfterRejectedWrites = try await fixture.profiles.profiles()
        XCTAssertEqual(profilesAfterRejectedWrites, [])
        for profile in [fixture.localProfile, fixture.remoteProfile] {
            let retainedSettings = try await fixture.settings.settings(
                for: profile.id
            )
            XCTAssertNil(retainedSettings)
        }
    }
}

private struct CrossProfileDeletionRaceFixture {
    let directory: URL
    let now = Date(timeIntervalSince1970: 2_185_000_000)
    let localProfile: KidProfile
    let remoteProfile: KidProfile
    let mutationGate = ProfileScopedMutationGate()
    let profiles: CrossProfileDeleteInterleavingProfileRepository
    let words: LocalJSONWordPoolRepository
    let settings: LocalJSONPracticeSettingsRepository
    let learning: LocalJSONLearningRecordRepository
    let daily: LocalJSONDailyQuestRepository
    let tombstones: LocalJSONProfileDeletionTombstoneRepository
    let session: LocalJSONChildSessionRepository
    let guardianStore: RepositoryGuardianFamilyStore
    let syncStore: RepositoryFamilySyncRecordStore

    init() async throws {
        directory = FileManager.default.temporaryDirectory.appendingPathComponent(
            "TadaCrossProfileDeleteRace-\(UUID().uuidString)",
            isDirectory: true
        )
        try FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true
        )

        localProfile = KidProfile(
            displayName: "Mia",
            avatar: .cartoonAnimal(assetID: "hare"),
            selectedWorld: .moonpetalKingdom,
            createdAt: now.addingTimeInterval(-120)
        )
        remoteProfile = KidProfile(
            displayName: "Leo",
            avatar: .cartoonAnimal(assetID: "fox"),
            selectedWorld: .pawsAndPines,
            createdAt: now.addingTimeInterval(-60)
        )

        let baseProfiles = LocalJSONKidProfileRepository(
            snapshotURL: directory.appendingPathComponent("profiles.json"),
            mutationGate: mutationGate
        )
        profiles = CrossProfileDeleteInterleavingProfileRepository(
            base: baseProfiles,
            localProfileID: localProfile.id,
            remoteProfileID: remoteProfile.id
        )
        words = LocalJSONWordPoolRepository(
            snapshotURL: directory.appendingPathComponent("words.json"),
            mutationGate: mutationGate
        )
        settings = LocalJSONPracticeSettingsRepository(
            snapshotURL: directory.appendingPathComponent("settings.json"),
            mutationGate: mutationGate
        )
        learning = LocalJSONLearningRecordRepository(
            snapshotURL: directory.appendingPathComponent("learning.json"),
            mutationGate: mutationGate
        )
        daily = LocalJSONDailyQuestRepository(
            snapshotURL: directory.appendingPathComponent("daily.json"),
            mutationGate: mutationGate
        )
        tombstones = LocalJSONProfileDeletionTombstoneRepository(
            snapshotURL: directory.appendingPathComponent("deletions.json"),
            mutationGate: mutationGate
        )
        session = LocalJSONChildSessionRepository(
            snapshotURL: directory.appendingPathComponent("session.json")
        )

        try await profiles.save(localProfile)
        try await profiles.save(remoteProfile)
        try await session.saveLastSelectedProfileID(localProfile.id)

        guardianStore = RepositoryGuardianFamilyStore(
            profiles: [localProfile, remoteProfile],
            selectedProfileID: localProfile.id,
            profileRepository: profiles,
            wordPoolRepository: words,
            practiceSettingsRepository: settings,
            learningRecordRepository: learning,
            dailyQuestRepository: daily,
            tombstoneRepository: tombstones,
            childSessionRepository: session,
            mutationGate: mutationGate,
            clock: CrossProfileDeleteFixedClock(now: now),
            timeZone: .gmt
        )
        syncStore = RepositoryFamilySyncRecordStore(
            profileRepository: profiles,
            wordPoolRepository: words,
            practiceSettingsRepository: settings,
            learningRepository: learning,
            dailyQuestRepository: daily,
            tombstoneRepository: tombstones,
            childSessionRepository: session,
            mutationGate: mutationGate,
            deviceID: "remote-delete-test-device",
            clock: CrossProfileDeleteFixedClock(now: now)
        )
    }

    func remoteDeletionRecord() throws -> FamilySyncRecord {
        let tombstone = ProfileDeletionTombstone(
            profileID: remoteProfile.id,
            deletedAt: now.addingTimeInterval(1)
        )
        return FamilySyncRecord(
            recordName: "profile-\(remoteProfile.id)",
            profileID: remoteProfile.id,
            kind: .profileDeletion,
            payload: try InspectableSnapshotJSONCodec.makeEncoder().encode(
                tombstone
            ),
            updatedAt: tombstone.deletedAt,
            deviceID: "owner-device",
            isDeleted: true,
            logicalRevision: FamilySyncLogicalRevision(
                counter: 12,
                deviceID: "owner-device"
            )
        )
    }

    func remove() {
        try? FileManager.default.removeItem(at: directory)
    }
}

/// Forces one production-relevant ordering without sleeping or relying on the
/// cooperative executor: local A has been removed, remote B then removes its
/// identity, and only then may the Guardian transaction compute its result.
private actor CrossProfileDeleteInterleavingProfileRepository:
    KidProfileRepository
{
    private let base: LocalJSONKidProfileRepository
    private let localProfileID: ProfileID
    private let remoteProfileID: ProfileID
    private var didDeleteLocalProfile = false
    private var didDeleteRemoteProfile = false
    private var localDeleteWaiters: [CheckedContinuation<Void, Never>] = []
    private var remoteDeleteWaiters: [CheckedContinuation<Void, Never>] = []
    private(set) var observedRequiredInterleaving = false

    init(
        base: LocalJSONKidProfileRepository,
        localProfileID: ProfileID,
        remoteProfileID: ProfileID
    ) {
        self.base = base
        self.localProfileID = localProfileID
        self.remoteProfileID = remoteProfileID
    }

    func profiles() async throws -> [KidProfile] {
        try await base.profiles()
    }

    func profile(id: ProfileID) async throws -> KidProfile? {
        try await base.profile(id: id)
    }

    func save(_ profile: KidProfile) async throws {
        try await base.save(profile)
    }

    func delete(id: ProfileID) async throws {
        if id == remoteProfileID {
            await waitUntilLocalProfileWasDeleted()
            try await base.delete(id: id)
            didDeleteRemoteProfile = true
            observedRequiredInterleaving = didDeleteLocalProfile
            let waiters = remoteDeleteWaiters
            remoteDeleteWaiters.removeAll()
            for waiter in waiters { waiter.resume() }
            return
        }

        try await base.delete(id: id)
        guard id == localProfileID else { return }
        didDeleteLocalProfile = true
        let waiters = localDeleteWaiters
        localDeleteWaiters.removeAll()
        for waiter in waiters { waiter.resume() }
        await waitUntilRemoteProfileWasDeleted()
    }

    private func waitUntilLocalProfileWasDeleted() async {
        guard !didDeleteLocalProfile else { return }
        await withCheckedContinuation { continuation in
            localDeleteWaiters.append(continuation)
        }
    }

    private func waitUntilRemoteProfileWasDeleted() async {
        guard !didDeleteRemoteProfile else { return }
        await withCheckedContinuation { continuation in
            remoteDeleteWaiters.append(continuation)
        }
    }
}

private struct CrossProfileDeleteFixedClock: AppClock {
    let now: Date
}
