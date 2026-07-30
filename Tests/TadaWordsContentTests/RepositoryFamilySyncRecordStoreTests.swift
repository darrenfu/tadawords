import Foundation
import TadaWordsDomain
import XCTest

@testable import TadaWordsContent

final class RepositoryFamilySyncRecordStoreTests: XCTestCase {
    func testPendingCreationIsExcludedFromEveryOutboundStoreEnumeration()
        async throws
    {
        let fixture = try Fixture()
        defer { fixture.remove() }
        try await fixture.profiles.save(fixture.profile)
        try await fixture.settings.save(.defaults(for: fixture.profile.id))
        let excludedProfileID = fixture.profile.id
        let store = fixture.makeStore(
            tombstones: fixture.tombstones,
            excludedProfileIDs: { [excludedProfileID] in [excludedProfileID] }
        )

        let profileIDs = try await store.profileIDsForSync()
        let records = try await store.records(for: fixture.profile.id)
        let exclusions = try await store.profileIDsExcludedFromSync()

        XCTAssertTrue(profileIDs.isEmpty)
        XCTAssertTrue(records.isEmpty)
        XCTAssertEqual(exclusions, [fixture.profile.id])
    }

    func testPracticeSettingsExportAsIndependentStableGroups() async throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        try await fixture.profiles.save(fixture.profile)
        try await fixture.settings.save(.defaults(for: fixture.profile.id))

        let records = try await fixture.makeStore(
            tombstones: fixture.tombstones
        ).records(for: fixture.profile.id)
        let settingsRecords = records.filter { $0.kind == .practiceSettings }

        XCTAssertEqual(
            Set(settingsRecords.map(\.recordName)),
            Set(
                PracticeSettingsSyncGroup.allCases.map {
                    $0.recordName(for: fixture.profile.id)
                })
        )
        XCTAssertEqual(settingsRecords.count, PracticeSettingsSyncGroup.allCases.count)
        XCTAssertEqual(
            Set(
                try settingsRecords.map {
                    try JSONDecoder.tada.decode(
                        PracticeSettingsSyncPayload.self,
                        from: $0.payload
                    ).group
                }),
            Set(PracticeSettingsSyncGroup.allCases)
        )
    }

    func testIndependentSettingsGroupsApplyInEitherOrder() async throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        try await fixture.profiles.save(fixture.profile)
        let baseline = ProfilePracticeSettings.defaults(for: fixture.profile.id)
        try await fixture.settings.save(baseline)
        let edited = ProfilePracticeSettings(
            profileID: fixture.profile.id,
            read: LearningRouteSettings(
                newWordLimit: 1,
                reviewWordLimit: 2,
                contentOrder: .reviewThenNew,
                emergencyAfterSeconds: 140
            ),
            audio: AudioPreferences(
                voiceEnabled: false,
                musicEnabled: false,
                soundEffectsEnabled: true,
                reducedSoundEnabled: true,
                calmEmergencyEnabled: false
            )
        )
        let records = try [PracticeSettingsSyncGroup.audio, .read].map { group in
            FamilySyncRecord(
                recordName: group.recordName(for: fixture.profile.id),
                profileID: fixture.profile.id,
                kind: .practiceSettings,
                payload: try JSONEncoder.tada.encode(
                    PracticeSettingsSyncPayload(settings: edited, group: group)
                ),
                updatedAt: fixture.now,
                deviceID: "remote"
            )
        }
        let store = fixture.makeStore(tombstones: fixture.tombstones)

        try await store.apply(records, for: fixture.profile.id)
        let forwardValue = try await fixture.settings.settings(
            for: fixture.profile.id
        )
        let forward = try XCTUnwrap(forwardValue)
        try await fixture.settings.save(baseline)
        try await store.apply(Array(records.reversed()), for: fixture.profile.id)
        let reverseValue = try await fixture.settings.settings(
            for: fixture.profile.id
        )
        let reverse = try XCTUnwrap(reverseValue)

        XCTAssertEqual(forward, reverse)
        XCTAssertEqual(forward.read, edited.read)
        XCTAssertEqual(forward.audio, edited.audio)
        XCTAssertEqual(forward.write, baseline.write)
        XCTAssertEqual(forward.notifications, baseline.notifications)
        XCTAssertEqual(forward.interface, baseline.interface)
    }

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
        let encodedObject = try XCTUnwrap(
            JSONSerialization.jsonObject(with: profileRecord.payload)
                as? [String: Any]
        )
        XCTAssertNil(encodedObject["voiceprintStatus"])
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

    func testLegacyProfilePayloadIgnoresRemoteVoiceprintSentinel() async throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let local = KidProfile(
            id: fixture.profile.id,
            displayName: fixture.profile.displayName,
            avatar: fixture.profile.avatar,
            selectedWorld: fixture.profile.selectedWorld,
            voiceprintStatus: .enrolled(
                modelVersion: "device-only-model",
                enrolledAt: fixture.now
            ),
            createdAt: fixture.profile.createdAt
        )
        try await fixture.profiles.save(local)
        let legacyRemote = KidProfile(
            id: local.id,
            displayName: "Remote name",
            avatar: local.avatar,
            selectedWorld: local.selectedWorld,
            voiceprintStatus: .needsRefresh,
            createdAt: local.createdAt,
            updatedAt: fixture.now.addingTimeInterval(10)
        )
        let record = FamilySyncRecord(
            recordName: "profile-\(local.id)",
            profileID: local.id,
            kind: .profile,
            payload: try JSONEncoder.tada.encode(legacyRemote),
            updatedAt: legacyRemote.updatedAt,
            deviceID: "legacy-device"
        )

        try await fixture.makeStore(tombstones: fixture.tombstones).apply(
            [record],
            for: local.id
        )

        let loaded = try await fixture.profiles.profile(id: local.id)
        let saved = try XCTUnwrap(loaded)
        XCTAssertEqual(saved.displayName, "Remote name")
        XCTAssertEqual(saved.voiceprintStatus, local.voiceprintStatus)
    }

    func testIncomingProfileWirePayloadCanonicalizesBeforePersistenceAndReexport()
        async throws
    {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let createdAt = fixture.now
        let treasure = TreasureAvatarSelection(
            rewardItemID: RewardItemID(rawValue: "earned-crown"),
            iconAssetID: "crown.fill"
        )
        let baseline = FamilySyncProfilePayload(
            profile: KidProfile(
                id: fixture.profile.id,
                displayName: "Baseline",
                avatar: fixture.profile.avatar,
                selectedWorld: fixture.profile.selectedWorld,
                selectedTreasureAvatar: treasure,
                createdAt: createdAt
            )
        )
        var object = try XCTUnwrap(
            JSONSerialization.jsonObject(
                with: JSONEncoder.tada.encode(baseline)
            ) as? [String: Any]
        )
        object["displayName"] = "   Remote Reader   "
        object["ageYears"] = 999
        object["updatedAt"] = createdAt.addingTimeInterval(-100).timeIntervalSince1970
        object["selectedCartoonIconAssetID"] = "must-be-cleared-by-treasure"
        let payload = try JSONSerialization.data(
            withJSONObject: object,
            options: [.sortedKeys]
        )
        let record = FamilySyncRecord(
            recordName: "profile-\(fixture.profile.id)",
            profileID: fixture.profile.id,
            kind: .profile,
            payload: payload,
            updatedAt: createdAt,
            deviceID: "remote-device"
        )
        let store = fixture.makeStore(tombstones: fixture.tombstones)

        try await store.apply([record], for: fixture.profile.id)

        let persistedValue = try await fixture.profiles.profile(
            id: fixture.profile.id
        )
        let persisted = try XCTUnwrap(persistedValue)
        XCTAssertEqual(persisted.displayName, "Remote Reader")
        XCTAssertEqual(persisted.ageYears, ProfileAgePolicy.durableAges.upperBound)
        XCTAssertEqual(persisted.updatedAt, createdAt)
        XCTAssertNil(persisted.selectedCartoonIconAssetID)
        XCTAssertEqual(persisted.selectedTreasureAvatar, treasure)

        let exportedRecords = try await store.records(for: fixture.profile.id)
        let exported = try XCTUnwrap(
            exportedRecords.first { $0.kind == .profile }
        )
        let canonical = try JSONDecoder.tada.decode(
            FamilySyncProfilePayload.self,
            from: exported.payload
        )
        XCTAssertEqual(canonical, FamilySyncProfilePayload(profile: persisted))
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

    func testCommittedDeletionCannotBeRemovedByDirectStaleProfileApply()
        async throws
    {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let deletion = ProfileDeletionTombstone(
            profileID: fixture.profile.id,
            deletedAt: fixture.now
        )
        try await fixture.tombstones.save(deletion)
        try await fixture.tombstones.markCommitted(for: fixture.profile.id)
        let staleProfile = KidProfile(
            id: fixture.profile.id,
            displayName: "Stale offline copy",
            avatar: fixture.profile.avatar,
            selectedWorld: fixture.profile.selectedWorld,
            createdAt: fixture.profile.createdAt,
            updatedAt: fixture.now.addingTimeInterval(10_000)
        )
        let staleRecord = FamilySyncRecord(
            recordName: "profile-\(staleProfile.id)",
            profileID: staleProfile.id,
            kind: .profile,
            payload: try JSONEncoder.tada.encode(staleProfile),
            updatedAt: staleProfile.updatedAt,
            deviceID: "stale-offline-device",
            logicalRevision: FamilySyncLogicalRevision(
                counter: 999,
                deviceID: "stale-offline-device"
            )
        )
        let store = fixture.makeStore(tombstones: fixture.tombstones)

        try await store.apply([staleRecord], for: fixture.profile.id)

        let retainedTombstone = try await fixture.tombstones.tombstone(
            for: fixture.profile.id
        )
        let resurrectedProfile = try await fixture.profiles.profile(
            id: fixture.profile.id
        )
        let exported = try await store.records(for: fixture.profile.id)
        XCTAssertEqual(retainedTombstone, deletion)
        XCTAssertNil(resurrectedProfile)
        XCTAssertEqual(exported.count, 1)
        XCTAssertEqual(exported.first?.kind, .profileDeletion)
        XCTAssertTrue(exported.first?.isDeleted == true)
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

    func testConditionalApplyCannotOverwriteLocalCommitWaitingAtSameProfileLease()
        async throws
    {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(
            "TadaSyncCAS-\(UUID().uuidString)",
            isDirectory: true
        )
        defer { try? FileManager.default.removeItem(at: directory) }
        try FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true
        )
        let gate = ProfileScopedMutationGate()
        let profiles = LocalJSONKidProfileRepository(
            snapshotURL: directory.appendingPathComponent("profiles.json"),
            mutationGate: gate
        )
        let words = LocalJSONWordPoolRepository(
            snapshotURL: directory.appendingPathComponent("words.json"),
            mutationGate: gate
        )
        let settings = LocalJSONPracticeSettingsRepository(
            snapshotURL: directory.appendingPathComponent("settings.json"),
            mutationGate: gate
        )
        let learning = LocalJSONLearningRecordRepository(
            snapshotURL: directory.appendingPathComponent("learning.json"),
            mutationGate: gate
        )
        let daily = LocalJSONDailyQuestRepository(
            snapshotURL: directory.appendingPathComponent("daily.json"),
            mutationGate: gate
        )
        let tombstones = LocalJSONProfileDeletionTombstoneRepository(
            snapshotURL: directory.appendingPathComponent("tombstones.json"),
            mutationGate: gate
        )
        let initial = KidProfile(
            displayName: "Before",
            avatar: .cartoonAnimal(assetID: "hare"),
            selectedWorld: .moonpetalKingdom,
            createdAt: Date(timeIntervalSince1970: 1)
        )
        try await profiles.save(initial)
        let store = RepositoryFamilySyncRecordStore(
            profileRepository: profiles,
            wordPoolRepository: words,
            practiceSettingsRepository: settings,
            learningRepository: learning,
            dailyQuestRepository: daily,
            tombstoneRepository: tombstones,
            mutationGate: gate,
            deviceID: "device-a"
        )
        let expected = FamilySyncRecordSetFingerprint(
            records: try await store.records(for: initial.id)
        )
        let remote = KidProfile(
            id: initial.id,
            displayName: "Remote",
            avatar: initial.avatar,
            selectedWorld: initial.selectedWorld,
            createdAt: initial.createdAt,
            updatedAt: Date(timeIntervalSince1970: 2)
        )
        let remoteRecord = FamilySyncRecord(
            recordName: "profile-\(initial.id)",
            profileID: initial.id,
            kind: .profile,
            payload: try JSONEncoder.tada.encode(remote),
            updatedAt: remote.updatedAt,
            deviceID: "cloud",
            logicalRevision: FamilySyncLogicalRevision(
                counter: 2,
                deviceID: "cloud"
            )
        )

        // A local writer owns the same profile lease after the coordinator's
        // expected snapshot was read. The remote apply must wait, then re-read
        // and reject rather than overwrite the committed local edit.
        try await gate.acquire(initial.id)
        let applyTask = Task {
            try await store.applyIfUnchanged(
                [remoteRecord],
                for: initial.id,
                expected: expected
            )
        }
        let local = KidProfile(
            id: initial.id,
            displayName: "Local wins",
            avatar: initial.avatar,
            selectedWorld: initial.selectedWorld,
            createdAt: initial.createdAt,
            updatedAt: Date(timeIntervalSince1970: 3)
        )
        try await ProfileScopedMutationLeaseContext.$profileID.withValue(initial.id) {
            try await profiles.save(local)
        }
        await gate.release(initial.id)

        let didApply = try await applyTask.value
        let persisted = try await profiles.profile(id: initial.id)
        XCTAssertFalse(didApply)
        XCTAssertEqual(persisted, local)
    }

    func testPublicApplyCommitsDurableTransactionReceipt() async throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        try await fixture.profiles.save(fixture.profile)
        let transactions = LocalJSONFamilySyncApplyTransactionRepository(
            snapshotURL: fixture.directory.appendingPathComponent(
                "apply-transactions.json"
            )
        )
        let remote = KidProfile(
            id: fixture.profile.id,
            displayName: "Mia Remote",
            avatar: fixture.profile.avatar,
            selectedWorld: fixture.profile.selectedWorld,
            createdAt: fixture.profile.createdAt,
            updatedAt: fixture.now
        )
        let record = FamilySyncRecord(
            recordName: "profile-\(remote.id)",
            profileID: remote.id,
            kind: .profile,
            payload: try JSONEncoder.tada.encode(remote),
            updatedAt: remote.updatedAt,
            deviceID: "remote-device",
            logicalRevision: FamilySyncLogicalRevision(
                counter: 4,
                deviceID: "remote-device"
            )
        )
        let store = fixture.makeStore(
            tombstones: fixture.tombstones,
            applyTransactionRepository: transactions
        )

        // The public entry point must not bypass the crash-safe transaction
        // path even though the production coordinator normally uses CAS apply.
        try await store.apply([record], for: remote.id)

        let pendingAfterCommit = try await transactions.pendingTransactions()
        let committedReceipt = try await transactions.lastCommittedReceipt(
            for: remote.id
        )
        let receipt = try XCTUnwrap(committedReceipt)
        let persistedProfile = try await fixture.profiles.profile(id: remote.id)
        XCTAssertTrue(pendingAfterCommit.isEmpty)
        XCTAssertEqual(receipt.recordCount, 1)
        XCTAssertEqual(receipt.affectedKinds, [.profile])
        XCTAssertFalse(receipt.deletedProfile)
        XCTAssertEqual(persistedProfile, remote)
    }

    func testFailedFirstRepositoryMutationKeepsExactPendingBatchForRestart()
        async throws
    {
        let fixture = try Fixture()
        defer { fixture.remove() }
        try await fixture.profiles.save(fixture.profile)
        let transactionURL = fixture.directory.appendingPathComponent(
            "interrupted-apply-transactions.json"
        )
        let transactions = LocalJSONFamilySyncApplyTransactionRepository(
            snapshotURL: transactionURL
        )
        let tombstones = PendingAssertingTombstoneRepository(
            transactions: transactions
        )
        let deletion = ProfileDeletionTombstone(
            profileID: fixture.profile.id,
            deletedAt: fixture.now
        )
        let record = FamilySyncRecord(
            recordName: "profile-\(fixture.profile.id)",
            profileID: fixture.profile.id,
            kind: .profileDeletion,
            payload: try JSONEncoder.tada.encode(deletion),
            updatedAt: deletion.deletedAt,
            deviceID: "remote-device",
            isDeleted: true,
            logicalRevision: FamilySyncLogicalRevision(
                counter: 9,
                deviceID: "remote-device"
            )
        )
        let store = fixture.makeStore(
            tombstones: tombstones,
            applyTransactionRepository: transactions
        )

        do {
            try await store.apply([record], for: fixture.profile.id)
            XCTFail("The injected first-mutation interruption must escape")
        } catch ApplyTransactionInterruption.firstMutation {
            // Simulates process death after durable begin but before local apply.
        }

        let observedPending =
            await tombstones
            .observedDurablePendingBeforeSave()
        let restarted = LocalJSONFamilySyncApplyTransactionRepository(
            snapshotURL: transactionURL
        )
        let pending = try await restarted.pendingTransactions()
        let committedReceipt = try await restarted.lastCommittedReceipt(
            for: fixture.profile.id
        )
        let retainedProfile = try await fixture.profiles.profile(
            id: fixture.profile.id
        )
        XCTAssertTrue(observedPending)
        XCTAssertEqual(pending.count, 1)
        XCTAssertEqual(pending.first?.profileID, fixture.profile.id)
        XCTAssertEqual(pending.first?.records, [record])
        XCTAssertNil(committedReceipt)
        XCTAssertEqual(
            retainedProfile,
            fixture.profile,
            "No payload mutation may occur before the durable transaction exists"
        )
    }

    func testCanonicalGenerationAuthoritativelyRemovesAbsentProfileAndReplays()
        async throws
    {
        let fixture = try Fixture()
        defer { fixture.remove() }
        try await fixture.profiles.save(fixture.profile)
        let extra = KidProfile(
            displayName: "Stale local child",
            avatar: fixture.profile.avatar,
            selectedWorld: fixture.profile.selectedWorld,
            createdAt: fixture.now.addingTimeInterval(-50)
        )
        try await fixture.profiles.save(extra)
        let canonicalProfile = KidProfile(
            id: fixture.profile.id,
            displayName: "Canonical child",
            avatar: fixture.profile.avatar,
            selectedWorld: fixture.profile.selectedWorld,
            createdAt: fixture.profile.createdAt,
            updatedAt: fixture.now
        )
        let record = FamilySyncRecord(
            recordName: "profile-\(canonicalProfile.id)",
            profileID: canonicalProfile.id,
            kind: .profile,
            payload: try JSONEncoder.tada.encode(
                FamilySyncProfilePayload(profile: canonicalProfile)
            ),
            updatedAt: fixture.now,
            deviceID: "canonical-ipad",
            logicalRevision: .init(
                counter: 20,
                deviceID: "canonical-ipad"
            )
        )
        let transactions = LocalJSONFamilySyncApplyTransactionRepository(
            snapshotURL: fixture.directory.appendingPathComponent(
                "canonical-apply-transactions.json"
            )
        )
        let store = fixture.makeStore(
            tombstones: fixture.tombstones,
            applyTransactionRepository: transactions
        )
        let snapshot = FamilySyncCanonicalGenerationSnapshot(
            generationID: "generation-1",
            previousGenerationID: nil,
            sourceInstallationID: "canonical-ipad",
            createdAt: fixture.now,
            records: [record]
        )

        try await store.replaceWithCanonicalSnapshot(snapshot)
        try await store.recoverPendingApplies()
        let persistedCanonical = try await fixture.profiles.profile(
            id: fixture.profile.id
        )
        let persistedExtra = try await fixture.profiles.profile(id: extra.id)
        let pending = try await transactions.pendingTransactions()
        let canonicalReceipt = try await transactions.lastCommittedReceipt(
            for: fixture.profile.id
        )
        let extraReceipt = try await transactions.lastCommittedReceipt(
            for: extra.id
        )

        XCTAssertEqual(persistedCanonical?.displayName, "Canonical child")
        XCTAssertNil(persistedExtra)
        XCTAssertTrue(pending.isEmpty)
        XCTAssertEqual(canonicalReceipt?.recordCount, 1)
        XCTAssertEqual(extraReceipt?.recordCount, 0)
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
        applyTransactionRepository:
            (any FamilySyncApplyTransactionRepository)? = nil,
        handwritingPreferenceRemover: (any HandwritingPreferenceRemoving)? = nil,
        excludedProfileIDs: @escaping @Sendable () async throws -> Set<ProfileID> = {
            []
        }
    ) -> RepositoryFamilySyncRecordStore {
        RepositoryFamilySyncRecordStore(
            profileRepository: profiles,
            wordPoolRepository: words,
            practiceSettingsRepository: settings,
            learningRepository: learning,
            dailyQuestRepository: daily,
            tombstoneRepository: tombstones,
            applyTransactionRepository: applyTransactionRepository,
            handwritingPreferenceRemover: handwritingPreferenceRemover,
            excludedProfileIDs: excludedProfileIDs,
            deviceID: "device-a",
            clock: FixedSyncStoreClock(now: now)
        )
    }

    func remove() {
        try? FileManager.default.removeItem(at: directory)
    }
}

private struct FixedSyncStoreClock: AppClock {
    let now: Date
}

private enum ApplyTransactionInterruption: Error {
    case firstMutation
}

private actor PendingAssertingTombstoneRepository:
    ProfileDeletionTombstoneRepository
{
    private let transactions: any FamilySyncApplyTransactionRepository
    private var observedPending = false

    init(transactions: any FamilySyncApplyTransactionRepository) {
        self.transactions = transactions
    }

    func tombstones() async throws -> [ProfileDeletionTombstone] { [] }

    func pendingTombstones() async throws -> [ProfileDeletionTombstone] { [] }

    func tombstone(for profileID: ProfileID) async throws
        -> ProfileDeletionTombstone?
    {
        _ = profileID
        return nil
    }

    func save(_ tombstone: ProfileDeletionTombstone) async throws {
        observedPending = try await transactions.pendingTransactions().contains {
            $0.profileID == tombstone.profileID
        }
        throw ApplyTransactionInterruption.firstMutation
    }

    func markCommitted(for profileID: ProfileID) async throws {
        _ = profileID
    }

    func delete(for profileID: ProfileID) async throws {
        _ = profileID
    }

    func observedDurablePendingBeforeSave() -> Bool {
        observedPending
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
