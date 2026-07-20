import Foundation
import TadaWordsContent
import TadaWordsDomain
import TadaWordsGuardianFeatures
import XCTest

@testable import TadaWordsAppShell
@testable import TadaWordsFeatures

@MainActor
final class ApplicationCompositionTests: XCTestCase {
    func testFirstLaunchCreatesOneStableDefaultProfileAndDeterministicPaths() async throws {
        let applicationSupportDirectory = try makeTemporaryDirectory()
        defer { removeTemporaryDirectory(applicationSupportDirectory) }

        let environment = try await makeBootstrapper(
            applicationSupportDirectory: applicationSupportDirectory
        ).bootstrap()
        let family = try await environment.guardianStore.familySnapshot()

        XCTAssertEqual(environment.profiles, [Self.defaultProfile])
        XCTAssertEqual(family.selectedProfileID, Self.defaultProfile.id)
        XCTAssertEqual(
            environment.dataPaths.dataDirectory,
            applicationSupportDirectory.appendingPathComponent(
                "TadaWords",
                isDirectory: true
            )
        )
        XCTAssertEqual(
            environment.dataPaths.profilesSnapshot.lastPathComponent,
            "profiles.json"
        )
        XCTAssertEqual(
            environment.dataPaths.wordPoolSnapshot.lastPathComponent,
            "word-pool.json"
        )
        XCTAssertEqual(
            environment.dataPaths.learningRecordsSnapshot.lastPathComponent,
            "learning-records.json"
        )
        XCTAssertEqual(
            environment.dataPaths.practiceSettingsSnapshot.lastPathComponent,
            "practice-settings.json"
        )
        XCTAssertEqual(
            environment.dataPaths.dailyQuestsSnapshot.lastPathComponent,
            "daily-quests.json"
        )
        XCTAssertEqual(
            environment.dataPaths.childSessionSnapshot.lastPathComponent,
            "child-session.json"
        )
        XCTAssertEqual(
            environment.dailyQuestRepository.snapshotURL,
            environment.dataPaths.dailyQuestsSnapshot
        )

        let persistedProfiles = try await LocalJSONKidProfileRepository(
            snapshotURL: environment.dataPaths.profilesSnapshot
        ).profiles()
        XCTAssertEqual(persistedProfiles, [Self.defaultProfile])
        let persistedSettings = try await environment.practiceSettingsRepository.settings(
            for: Self.defaultProfile.id
        )
        XCTAssertEqual(
            persistedSettings,
            .defaults(for: Self.defaultProfile.id)
        )
    }

    func testRestartKeepsDefaultProfileIDWithoutDuplicatingOrRewriting() async throws {
        let applicationSupportDirectory = try makeTemporaryDirectory()
        defer { removeTemporaryDirectory(applicationSupportDirectory) }

        let firstEnvironment = try await makeBootstrapper(
            applicationSupportDirectory: applicationSupportDirectory
        ).bootstrap()
        let originalSnapshot = try Data(
            contentsOf: firstEnvironment.dataPaths.profilesSnapshot
        )
        let originalSettingsSnapshot = try Data(
            contentsOf: firstEnvironment.dataPaths.practiceSettingsSnapshot
        )

        let restartedEnvironment = try await makeBootstrapper(
            applicationSupportDirectory: applicationSupportDirectory
        ).bootstrap()
        let restartedSnapshot = try Data(
            contentsOf: restartedEnvironment.dataPaths.profilesSnapshot
        )
        let restartedSettingsSnapshot = try Data(
            contentsOf: restartedEnvironment.dataPaths.practiceSettingsSnapshot
        )

        XCTAssertEqual(restartedEnvironment.profiles.count, 1)
        XCTAssertEqual(
            restartedEnvironment.profiles.first?.id,
            Self.defaultProfile.id
        )
        XCTAssertEqual(restartedSnapshot, originalSnapshot)
        XCTAssertEqual(restartedSettingsSnapshot, originalSettingsSnapshot)
    }

    func testCommittedDeletionOfOnlyProfileRemainsEmptyAcrossColdRestart()
        async throws
    {
        let applicationSupportDirectory = try makeTemporaryDirectory()
        defer { removeTemporaryDirectory(applicationSupportDirectory) }
        let first = try await makeBootstrapper(
            applicationSupportDirectory: applicationSupportDirectory
        ).bootstrap()

        let deletion = try await first.guardianStore.deleteProfile(
            id: Self.defaultProfile.id
        )
        XCTAssertTrue(deletion.family.profiles.isEmpty)
        XCTAssertNil(deletion.family.selectedProfileID)
        XCTAssertNil(deletion.dashboard)

        let restarted = try await makeBootstrapper(
            applicationSupportDirectory: applicationSupportDirectory
        ).bootstrap()
        let restartedFamily = try await restarted.guardianStore.familySnapshot()
        let persistedProfiles = try await restarted.profileRepository.profiles()
        let persistedTombstone = try await restarted.tombstoneRepository.tombstone(
            for: Self.defaultProfile.id
        )
        let pending = try await restarted.tombstoneRepository.pendingTombstones()

        XCTAssertTrue(restarted.profiles.isEmpty)
        XCTAssertTrue(restartedFamily.profiles.isEmpty)
        XCTAssertNil(restartedFamily.selectedProfileID)
        XCTAssertTrue(persistedProfiles.isEmpty)
        XCTAssertEqual(persistedTombstone, deletion.tombstone)
        XCTAssertTrue(pending.isEmpty)
        XCTAssertNil(restarted.lastSelectedProfileID)
    }

    func testCrashReplayDeletingFinalProfileCannotSeedReplacementProfile()
        async throws
    {
        let applicationSupportDirectory = try makeTemporaryDirectory()
        defer { removeTemporaryDirectory(applicationSupportDirectory) }
        let first = try await makeBootstrapper(
            applicationSupportDirectory: applicationSupportDirectory
        ).bootstrap()
        let tombstone = ProfileDeletionTombstone(
            profileID: Self.defaultProfile.id,
            deletedAt: Self.testDate.addingTimeInterval(30)
        )
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .secondsSince1970
        let record = FamilySyncRecord(
            recordName: "profile-\(Self.defaultProfile.id)",
            profileID: Self.defaultProfile.id,
            kind: .profileDeletion,
            payload: try encoder.encode(tombstone),
            updatedAt: tombstone.deletedAt,
            deviceID: "remote-owner",
            isDeleted: true,
            logicalRevision: FamilySyncLogicalRevision(
                counter: 9,
                deviceID: "remote-owner"
            )
        )
        guard
            case .pending = try await first.familySyncApplyTransactionRepository
                .begin(
                    profileID: Self.defaultProfile.id,
                    records: [record],
                    at: Self.testDate
                )
        else {
            return XCTFail("The deletion replay fixture must remain pending")
        }

        let restarted = try await makeBootstrapper(
            applicationSupportDirectory: applicationSupportDirectory
        ).bootstrap()
        let family = try await restarted.guardianStore.familySnapshot()
        let persistedProfiles = try await restarted.profileRepository.profiles()
        let persistedTombstone = try await restarted.tombstoneRepository.tombstone(
            for: Self.defaultProfile.id
        )
        let pendingTransactions =
            try await restarted
            .familySyncApplyTransactionRepository.pendingTransactions()

        XCTAssertTrue(restarted.profiles.isEmpty)
        XCTAssertTrue(family.profiles.isEmpty)
        XCTAssertNil(family.selectedProfileID)
        XCTAssertTrue(persistedProfiles.isEmpty)
        XCTAssertEqual(persistedTombstone, tombstone)
        XCTAssertTrue(pendingTransactions.isEmpty)
    }

    func testExistingEmptyProfileSnapshotWithoutTombstoneDoesNotSeedDefault()
        async throws
    {
        let applicationSupportDirectory = try makeTemporaryDirectory()
        defer { removeTemporaryDirectory(applicationSupportDirectory) }
        let paths = ApplicationDataPaths(
            applicationSupportDirectory: applicationSupportDirectory
        )
        let profileRepository = LocalJSONKidProfileRepository(
            snapshotURL: paths.profilesSnapshot
        )
        try await profileRepository.save(Self.defaultProfile)
        try await profileRepository.delete(id: Self.defaultProfile.id)
        XCTAssertTrue(
            FileManager.default.fileExists(atPath: paths.profilesSnapshot.path)
        )

        let environment = try await makeBootstrapper(
            applicationSupportDirectory: applicationSupportDirectory
        ).bootstrap()
        let family = try await environment.guardianStore.familySnapshot()
        let persistedProfiles = try await environment.profileRepository.profiles()
        let tombstones = try await environment.tombstoneRepository.tombstones()

        XCTAssertTrue(environment.profiles.isEmpty)
        XCTAssertTrue(family.profiles.isEmpty)
        XCTAssertNil(family.selectedProfileID)
        XCTAssertTrue(persistedProfiles.isEmpty)
        XCTAssertTrue(tombstones.isEmpty)
        XCTAssertTrue(environment.requiresFirstRunOnboarding)
        XCTAssertEqual(environment.firstRunOnboardingPurpose, .fullSetup)
    }

    func testCreatedChildAndLastSelectionSurviveColdRestart() async throws {
        let applicationSupportDirectory = try makeTemporaryDirectory()
        defer { removeTemporaryDirectory(applicationSupportDirectory) }
        let firstEnvironment = try await makeBootstrapper(
            applicationSupportDirectory: applicationSupportDirectory
        ).bootstrap()
        let creator = RepositoryChildProfileCreator(
            profileRepository: firstEnvironment.profileRepository,
            practiceSettingsRepository: firstEnvironment.practiceSettingsRepository,
            clock: FixedAppClock(now: Self.testDate.addingTimeInterval(10))
        )
        let created = try await creator.createProfile(
            displayName: "Coco",
            ageYears: 4,
            existingProfiles: firstEnvironment.profiles
        )
        try await firstEnvironment.childSessionRepository
            .saveLastSelectedProfileID(created.id)

        let restarted = try await makeBootstrapper(
            applicationSupportDirectory: applicationSupportDirectory
        ).bootstrap()

        let restartedSettings = try await restarted.practiceSettingsRepository
            .settings(for: created.id)
        XCTAssertTrue(restarted.profiles.contains(created))
        XCTAssertEqual(restarted.lastSelectedProfileID, created.id)
        XCTAssertEqual(
            restartedSettings,
            .defaults(for: created.id)
        )
    }

    func testDeletedRememberedProfileFallsBackToChooserAndClearsStaleMarker()
        async throws
    {
        let applicationSupportDirectory = try makeTemporaryDirectory()
        defer { removeTemporaryDirectory(applicationSupportDirectory) }
        let firstEnvironment = try await makeBootstrapper(
            applicationSupportDirectory: applicationSupportDirectory
        ).bootstrap()
        let extra = KidProfile(
            displayName: "Coco",
            avatar: .cartoonAnimal(assetID: "fox"),
            selectedWorld: .pawsAndPines,
            createdAt: Self.testDate.addingTimeInterval(10)
        )
        try await firstEnvironment.profileRepository.save(extra)
        try await firstEnvironment.practiceSettingsRepository.save(
            .defaults(for: extra.id)
        )
        try await firstEnvironment.childSessionRepository
            .saveLastSelectedProfileID(extra.id)
        try await firstEnvironment.profileRepository.delete(id: extra.id)

        let restarted = try await makeBootstrapper(
            applicationSupportDirectory: applicationSupportDirectory
        ).bootstrap()

        let clearedProfileID = try await restarted.childSessionRepository
            .lastSelectedProfileID()
        XCTAssertNil(restarted.lastSelectedProfileID)
        XCTAssertNil(clearedProfileID)
        XCTAssertEqual(restarted.profiles, [Self.defaultProfile])
    }

    func testCorruptLaunchPreferenceFallsBackWithoutBlockingLearningData()
        async throws
    {
        let applicationSupportDirectory = try makeTemporaryDirectory()
        defer { removeTemporaryDirectory(applicationSupportDirectory) }
        let paths = ApplicationDataPaths(
            applicationSupportDirectory: applicationSupportDirectory
        )
        try FileManager.default.createDirectory(
            at: paths.dataDirectory,
            withIntermediateDirectories: true
        )
        try Data("not-json".utf8).write(to: paths.childSessionSnapshot)

        let environment = try await makeBootstrapper(
            applicationSupportDirectory: applicationSupportDirectory
        ).bootstrap()

        XCTAssertEqual(environment.profiles, [Self.defaultProfile])
        XCTAssertNil(environment.lastSelectedProfileID)
        XCTAssertEqual(
            try Data(contentsOf: paths.childSessionSnapshot),
            Data("not-json".utf8),
            "A non-core preference failure should fall back without destroying evidence."
        )

        try await environment.childSessionRepository
            .saveLastSelectedProfileID(Self.defaultProfile.id)
        let restarted = try await makeBootstrapper(
            applicationSupportDirectory: applicationSupportDirectory
        ).bootstrap()
        XCTAssertEqual(
            restarted.lastSelectedProfileID,
            Self.defaultProfile.id,
            "The next explicit child selection should atomically repair a bad preference."
        )
    }

    func testRestartPreservesCustomPracticeSettingsWithoutRewriting() async throws {
        let applicationSupportDirectory = try makeTemporaryDirectory()
        defer { removeTemporaryDirectory(applicationSupportDirectory) }
        let firstEnvironment = try await makeBootstrapper(
            applicationSupportDirectory: applicationSupportDirectory
        ).bootstrap()
        let customSettings = ProfilePracticeSettings(
            profileID: Self.defaultProfile.id,
            read: LearningRouteSettings(
                newWordLimit: 7,
                reviewWordLimit: 4,
                contentOrder: .reviewThenNew,
                emergencyAfterSeconds: 90
            )
        )
        try await firstEnvironment.practiceSettingsRepository.save(customSettings)
        let customSnapshot = try Data(
            contentsOf: firstEnvironment.dataPaths.practiceSettingsSnapshot
        )

        let restartedEnvironment = try await makeBootstrapper(
            applicationSupportDirectory: applicationSupportDirectory
        ).bootstrap()
        let restoredSettings =
            try await restartedEnvironment
            .practiceSettingsRepository.settings(for: Self.defaultProfile.id)

        XCTAssertEqual(restoredSettings, customSettings)
        XCTAssertEqual(
            try Data(
                contentsOf: restartedEnvironment.dataPaths.practiceSettingsSnapshot
            ),
            customSnapshot
        )
    }

    func testExistingProfilesAreLoadedWithoutSeedingOrRewriting() async throws {
        let applicationSupportDirectory = try makeTemporaryDirectory()
        defer { removeTemporaryDirectory(applicationSupportDirectory) }
        let paths = ApplicationDataPaths(
            applicationSupportDirectory: applicationSupportDirectory
        )
        let existingProfile = KidProfile(
            id: ProfileID(
                rawValue: try XCTUnwrap(
                    UUID(
                        uuidString: "BCA2F5A8-6C40-42F1-A2CD-A7F69873E095"
                    )
                )
            ),
            displayName: "Existing Kid",
            avatar: .cartoonAnimal(assetID: "fox"),
            selectedWorld: .pawsAndPines,
            createdAt: Self.testDate.addingTimeInterval(-100)
        )
        let repository = LocalJSONKidProfileRepository(
            snapshotURL: paths.profilesSnapshot
        )
        try await repository.save(existingProfile)
        let originalSnapshot = try Data(contentsOf: paths.profilesSnapshot)

        let environment = try await makeBootstrapper(
            applicationSupportDirectory: applicationSupportDirectory
        ).bootstrap()
        let family = try await environment.guardianStore.familySnapshot()

        XCTAssertEqual(environment.profiles, [existingProfile])
        XCTAssertEqual(family.selectedProfile, existingProfile)
        XCTAssertEqual(
            try Data(contentsOf: paths.profilesSnapshot),
            originalSnapshot
        )
    }

    func testGuardianImportIsImmediatelyVisibleThroughSharedChildWordRepository() async throws {
        let applicationSupportDirectory = try makeTemporaryDirectory()
        defer { removeTemporaryDirectory(applicationSupportDirectory) }

        let environment = try await makeBootstrapper(
            applicationSupportDirectory: applicationSupportDirectory
        ).bootstrap()
        let initiallyCachedEntries = try await environment.wordPoolRepository.entries(
            for: Self.defaultProfile.id,
            learningMode: .read,
            includingInactive: true
        )
        XCTAssertTrue(initiallyCachedEntries.isEmpty)

        let report = try await environment.guardianStore.importWords(
            GuardianWordImportRequest(
                rawText: "cat",
                learningMode: .read
            )
        )
        let childEntries = try await environment.wordPoolRepository.entries(
            for: Self.defaultProfile.id,
            learningMode: .read,
            includingInactive: true
        )

        XCTAssertEqual(report.accepted, ["cat"])
        XCTAssertEqual(childEntries.map(\.prompt.normalizedText), ["cat"])

        let restartedRepository = LocalJSONWordPoolRepository(
            snapshotURL: environment.dataPaths.wordPoolSnapshot
        )
        let persistedEntries = try await restartedRepository.entries(
            for: Self.defaultProfile.id,
            learningMode: .read,
            includingInactive: true
        )
        XCTAssertEqual(persistedEntries.map(\.prompt.normalizedText), ["cat"])
    }

    func testGuardianSettingsUpdateIsImmediatelyVisibleThroughSharedChildRepository()
        async throws
    {
        let applicationSupportDirectory = try makeTemporaryDirectory()
        defer { removeTemporaryDirectory(applicationSupportDirectory) }
        let environment = try await makeBootstrapper(
            applicationSupportDirectory: applicationSupportDirectory
        ).bootstrap()
        let initiallyCachedSettings =
            try await environment
            .practiceSettingsRepository.settings(for: Self.defaultProfile.id)
        XCTAssertEqual(
            initiallyCachedSettings,
            .defaults(for: Self.defaultProfile.id)
        )
        let customSettings = ProfilePracticeSettings(
            profileID: Self.defaultProfile.id,
            read: LearningRouteSettings(
                newWordLimit: 8,
                reviewWordLimit: 6,
                contentOrder: .reviewThenNew,
                emergencyAfterSeconds: 120
            )
        )

        let guardianSnapshot = try await environment.guardianStore
            .updatePracticeSettings(customSettings)
        let childSettings = try await environment.practiceSettingsRepository.settings(
            for: Self.defaultProfile.id
        )

        XCTAssertEqual(guardianSnapshot.practiceSettings, customSettings)
        XCTAssertEqual(childSettings, customSettings)

        let restartedRepository = LocalJSONPracticeSettingsRepository(
            snapshotURL: environment.dataPaths.practiceSettingsSnapshot
        )
        let persistedSettings = try await restartedRepository.settings(
            for: Self.defaultProfile.id
        )
        XCTAssertEqual(persistedSettings, customSettings)
    }

    func testSharedLearningRepositoryPreservesAttemptAndProgressAcrossRestart() async throws {
        let applicationSupportDirectory = try makeTemporaryDirectory()
        defer { removeTemporaryDirectory(applicationSupportDirectory) }
        let environment = try await makeBootstrapper(
            applicationSupportDirectory: applicationSupportDirectory
        ).bootstrap()
        let wordID = WordPromptID(
            rawValue: try XCTUnwrap(
                UUID(
                    uuidString: "3448D4E8-A1BC-4A52-92D7-2951D1875BA6"
                )
            )
        )
        let initialProgress = try await environment.learningRecordRepository.progress(
            for: Self.defaultProfile.id,
            wordPromptID: wordID
        )
        XCTAssertNil(initialProgress)
        let attempt = AttemptEvent(
            profileID: Self.defaultProfile.id,
            wordPromptID: wordID,
            learningMode: .read,
            evidence: .firstIndependentAttempt,
            outcome: .correct,
            occurredAt: Self.testDate
        )
        try await environment.learningRecordRepository.append(attempt)
        let derivedProgress = try await environment.learningRecordRepository.progress(
            for: Self.defaultProfile.id,
            wordPromptID: wordID
        )
        let eventDerivedProgress = try XCTUnwrap(derivedProgress)
        XCTAssertEqual(eventDerivedProgress.firstIndependentAttemptCount, 1)
        XCTAssertEqual(eventDerivedProgress.firstIndependentCorrectCount, 1)
        XCTAssertEqual(eventDerivedProgress.lastEncounterAt, Self.testDate)

        let restartedRepository = LocalJSONLearningRecordRepository(
            snapshotURL: environment.dataPaths.learningRecordsSnapshot
        )
        let persistedAttempts = try await restartedRepository.attempts(
            for: Self.defaultProfile.id,
            wordPromptID: wordID
        )
        let persistedProgress = try await restartedRepository.progress(
            for: Self.defaultProfile.id,
            wordPromptID: wordID
        )
        XCTAssertEqual(persistedAttempts, [attempt])
        XCTAssertEqual(persistedProgress, eventDerivedProgress)
    }

    func testCorruptProfileSnapshotFailsClosedWithoutOverwritingBytes() async throws {
        let applicationSupportDirectory = try makeTemporaryDirectory()
        defer { removeTemporaryDirectory(applicationSupportDirectory) }
        let paths = ApplicationDataPaths(
            applicationSupportDirectory: applicationSupportDirectory
        )
        try FileManager.default.createDirectory(
            at: paths.dataDirectory,
            withIntermediateDirectories: true
        )
        let corruptSnapshot = Data("{not-json".utf8)
        try corruptSnapshot.write(to: paths.profilesSnapshot)

        do {
            _ = try await makeBootstrapper(
                applicationSupportDirectory: applicationSupportDirectory
            ).bootstrap()
            XCTFail("Expected corrupt profile JSON to stop bootstrap.")
        } catch let error as ApplicationBootstrapError {
            XCTAssertEqual(
                error,
                .invalidSnapshotEnvelope(store: .profiles)
            )
        }

        XCTAssertEqual(
            try Data(contentsOf: paths.profilesSnapshot),
            corruptSnapshot
        )
        XCTAssertFalse(
            FileManager.default.fileExists(atPath: paths.wordPoolSnapshot.path)
        )
        XCTAssertFalse(
            FileManager.default.fileExists(
                atPath: paths.learningRecordsSnapshot.path
            )
        )
    }

    func testCorruptWordPoolSnapshotFailsClosedWithoutCreatingProfile() async throws {
        let applicationSupportDirectory = try makeTemporaryDirectory()
        defer { removeTemporaryDirectory(applicationSupportDirectory) }
        let paths = ApplicationDataPaths(
            applicationSupportDirectory: applicationSupportDirectory
        )
        try FileManager.default.createDirectory(
            at: paths.dataDirectory,
            withIntermediateDirectories: true
        )
        let corruptSnapshot = Data("{not-a-word-pool".utf8)
        try corruptSnapshot.write(to: paths.wordPoolSnapshot)

        do {
            _ = try await makeBootstrapper(
                applicationSupportDirectory: applicationSupportDirectory
            ).bootstrap()
            XCTFail("Expected corrupt word-pool JSON to stop bootstrap.")
        } catch let error as ApplicationBootstrapError {
            XCTAssertEqual(
                error,
                .invalidSnapshotEnvelope(store: .wordPool)
            )
        }

        XCTAssertEqual(
            try Data(contentsOf: paths.wordPoolSnapshot),
            corruptSnapshot
        )
        XCTAssertFalse(
            FileManager.default.fileExists(atPath: paths.profilesSnapshot.path)
        )
    }

    func testCorruptLearningSnapshotFailsClosedWithoutCreatingProfile() async throws {
        let applicationSupportDirectory = try makeTemporaryDirectory()
        defer { removeTemporaryDirectory(applicationSupportDirectory) }
        let paths = ApplicationDataPaths(
            applicationSupportDirectory: applicationSupportDirectory
        )
        try FileManager.default.createDirectory(
            at: paths.dataDirectory,
            withIntermediateDirectories: true
        )
        let corruptSnapshot = Data("{not-learning-records".utf8)
        try corruptSnapshot.write(to: paths.learningRecordsSnapshot)

        do {
            _ = try await makeBootstrapper(
                applicationSupportDirectory: applicationSupportDirectory
            ).bootstrap()
            XCTFail("Expected corrupt learning JSON to stop bootstrap.")
        } catch let error as ApplicationBootstrapError {
            XCTAssertEqual(
                error,
                .invalidSnapshotEnvelope(store: .learningRecords)
            )
        }

        XCTAssertEqual(
            try Data(contentsOf: paths.learningRecordsSnapshot),
            corruptSnapshot
        )
        XCTAssertFalse(
            FileManager.default.fileExists(atPath: paths.profilesSnapshot.path)
        )
    }

    func testCorruptPracticeSettingsFailsClosedWithoutCreatingProfile() async throws {
        let applicationSupportDirectory = try makeTemporaryDirectory()
        defer { removeTemporaryDirectory(applicationSupportDirectory) }
        let paths = ApplicationDataPaths(
            applicationSupportDirectory: applicationSupportDirectory
        )
        try FileManager.default.createDirectory(
            at: paths.dataDirectory,
            withIntermediateDirectories: true
        )
        let corruptSnapshot = Data("{not-practice-settings".utf8)
        try corruptSnapshot.write(to: paths.practiceSettingsSnapshot)

        do {
            _ = try await makeBootstrapper(
                applicationSupportDirectory: applicationSupportDirectory
            ).bootstrap()
            XCTFail("Expected corrupt practice settings to stop bootstrap.")
        } catch let error as ApplicationBootstrapError {
            XCTAssertEqual(
                error,
                .invalidSnapshotEnvelope(store: .practiceSettings)
            )
        }

        XCTAssertEqual(
            try Data(contentsOf: paths.practiceSettingsSnapshot),
            corruptSnapshot
        )
        XCTAssertFalse(
            FileManager.default.fileExists(atPath: paths.profilesSnapshot.path)
        )
    }

    func testCorruptDailyQuestSnapshotFailsClosedWithoutCreatingProfile()
        async throws
    {
        let applicationSupportDirectory = try makeTemporaryDirectory()
        defer { removeTemporaryDirectory(applicationSupportDirectory) }
        let paths = ApplicationDataPaths(
            applicationSupportDirectory: applicationSupportDirectory
        )
        try FileManager.default.createDirectory(
            at: paths.dataDirectory,
            withIntermediateDirectories: true
        )
        let corruptSnapshot = Data("{not-daily-quests".utf8)
        try corruptSnapshot.write(to: paths.dailyQuestsSnapshot)

        do {
            _ = try await makeBootstrapper(
                applicationSupportDirectory: applicationSupportDirectory
            ).bootstrap()
            XCTFail("Expected corrupt Daily Quest JSON to stop bootstrap.")
        } catch let error as ApplicationBootstrapError {
            XCTAssertEqual(
                error,
                .invalidSnapshotEnvelope(store: .dailyQuests)
            )
        }

        XCTAssertEqual(
            try Data(contentsOf: paths.dailyQuestsSnapshot),
            corruptSnapshot
        )
        XCTAssertFalse(
            FileManager.default.fileExists(atPath: paths.profilesSnapshot.path)
        )
    }

    func testMissingProfileSnapshotWithExistingDataFailsWithoutOrphaningData()
        async throws
    {
        let applicationSupportDirectory = try makeTemporaryDirectory()
        defer { removeTemporaryDirectory(applicationSupportDirectory) }
        let paths = ApplicationDataPaths(
            applicationSupportDirectory: applicationSupportDirectory
        )
        let wordRepository = LocalJSONWordPoolRepository(
            snapshotURL: paths.wordPoolSnapshot
        )
        let prompt = try WordPrompt(
            learningMode: .read,
            text: "cat"
        )
        _ = try await wordRepository.upsert([
            WordPoolEntryDraft(
                profileID: Self.defaultProfile.id,
                prompt: prompt,
                addedAt: Self.testDate,
                source: .guardianManual,
                positionInBatch: 0
            )
        ])
        let originalWordSnapshot = try Data(
            contentsOf: paths.wordPoolSnapshot
        )

        do {
            _ = try await makeBootstrapper(
                applicationSupportDirectory: applicationSupportDirectory
            ).bootstrap()
            XCTFail("Expected missing profile metadata to stop bootstrap.")
        } catch let error as ApplicationBootstrapError {
            XCTAssertEqual(
                error,
                .profileSnapshotMissingWithDependentData
            )
        }

        XCTAssertEqual(
            try Data(contentsOf: paths.wordPoolSnapshot),
            originalWordSnapshot
        )
        XCTAssertFalse(
            FileManager.default.fileExists(atPath: paths.profilesSnapshot.path)
        )
        XCTAssertFalse(
            FileManager.default.fileExists(
                atPath: paths.practiceSettingsSnapshot.path
            )
        )
    }

    func testCurrentFamilySyncSnapshotVersionsBootstrapSuccessfully() async throws {
        let applicationSupportDirectory = try makeTemporaryDirectory()
        defer { removeTemporaryDirectory(applicationSupportDirectory) }
        let paths = ApplicationDataPaths(
            applicationSupportDirectory: applicationSupportDirectory
        )
        try FileManager.default.createDirectory(
            at: paths.dataDirectory,
            withIntermediateDirectories: true
        )
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .secondsSince1970
        encoder.outputFormatting = [.sortedKeys]
        try encoder.encode(
            KidProfileSnapshot(profiles: [Self.defaultProfile])
        ).write(to: paths.profilesSnapshot)
        try encoder.encode(
            WordPoolSnapshot(entries: [])
        ).write(to: paths.wordPoolSnapshot)
        try encoder.encode(
            LearningRecordSnapshot(
                attempts: [],
                corrections: [],
                progress: []
            )
        ).write(to: paths.learningRecordsSnapshot)
        try encoder.encode(
            PracticeSettingsSnapshot(
                settings: [.defaults(for: Self.defaultProfile.id)]
            )
        ).write(to: paths.practiceSettingsSnapshot)
        try encoder.encode(
            DailyQuestSnapshot(
                plans: [],
                completions: [],
                rewardGrants: []
            )
        ).write(to: paths.dailyQuestsSnapshot)

        let environment = try await makeBootstrapper(
            applicationSupportDirectory: applicationSupportDirectory
        ).bootstrap()

        XCTAssertEqual(environment.profiles, [Self.defaultProfile])
        XCTAssertEqual(
            try schemaVersion(in: paths.wordPoolSnapshot),
            WordPoolSnapshot.currentSchemaVersion
        )
        XCTAssertEqual(
            try schemaVersion(in: paths.learningRecordsSnapshot),
            LearningRecordSnapshot.currentSchemaVersion
        )
        XCTAssertEqual(
            try schemaVersion(in: paths.dailyQuestsSnapshot),
            DailyQuestSnapshot.currentSchemaVersion
        )
    }

    func testNewerCoreSchemasFailBeforeAnyBootstrapWriteAcrossRetries()
        async throws
    {
        let candidates:
            [(
                store: ApplicationSnapshotStore,
                supported: Int,
                snapshotURL: (ApplicationDataPaths) -> URL
            )] = [
                (
                    .wordPool,
                    WordPoolSnapshot.currentSchemaVersion,
                    { $0.wordPoolSnapshot }
                ),
                (
                    .learningRecords,
                    LearningRecordSnapshot.currentSchemaVersion,
                    { $0.learningRecordsSnapshot }
                ),
                (
                    .dailyQuests,
                    DailyQuestSnapshot.currentSchemaVersion,
                    { $0.dailyQuestsSnapshot }
                ),
            ]

        for candidate in candidates {
            let applicationSupportDirectory = try makeTemporaryDirectory()
            defer { removeTemporaryDirectory(applicationSupportDirectory) }
            let paths = ApplicationDataPaths(
                applicationSupportDirectory: applicationSupportDirectory
            )
            try FileManager.default.createDirectory(
                at: paths.dataDirectory,
                withIntermediateDirectories: true
            )
            let futureVersion = candidate.supported + 1
            let original = Data(
                "{\"schemaVersion\":\(futureVersion)}".utf8
            )
            let futureSnapshotURL = candidate.snapshotURL(paths)
            try original.write(to: futureSnapshotURL)

            for _ in 0..<2 {
                do {
                    _ = try await makeBootstrapper(
                        applicationSupportDirectory: applicationSupportDirectory
                    ).bootstrap()
                    XCTFail("Expected a newer snapshot to require an app update.")
                } catch let error as ApplicationBootstrapError {
                    XCTAssertEqual(
                        error,
                        .requiresNewerApp(
                            store: candidate.store,
                            found: futureVersion,
                            supported: candidate.supported
                        )
                    )
                }
            }

            XCTAssertEqual(try Data(contentsOf: futureSnapshotURL), original)
            XCTAssertFalse(
                FileManager.default.fileExists(
                    atPath: paths.deviceIdentitySnapshot.path
                )
            )
            XCTAssertFalse(
                FileManager.default.fileExists(
                    atPath: paths.firstRunOnboardingSnapshot.path
                )
            )
            XCTAssertEqual(
                try FileManager.default.contentsOfDirectory(
                    at: paths.dataDirectory,
                    includingPropertiesForKeys: nil
                ).map(\.lastPathComponent),
                [futureSnapshotURL.lastPathComponent]
            )
        }
    }

    func testNewerSchemaFailureProvidesPrivacySafeUpdateGuidance() {
        let failure = ApplicationBootstrapFailure(
            error: ApplicationBootstrapError.requiresNewerApp(
                store: .wordPool,
                found: 3,
                supported: 2
            )
        )

        XCTAssertEqual(failure.title, "Update Tada Words")
        XCTAssertTrue(failure.message.contains("saved data is safe"))
        XCTAssertTrue(failure.message.contains("latest Tada Words build"))
        XCTAssertEqual(failure.debugDetails, "requires-newer-app:wordPool:3:2")
    }

    func testBundledPersistenceSchemaPolicyMatchesEveryReader() throws {
        let repositoryRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let policyURL = repositoryRoot.appendingPathComponent(
            "Apps/TadaWordsApp/PersistenceSchemaCompatibility.json"
        )
        guard
            let object = try JSONSerialization.jsonObject(
                with: Data(contentsOf: policyURL)
            ) as? [String: Any],
            let formatVersion = object["formatVersion"] as? Int,
            let rawStores = object["stores"] as? [String: Any]
        else {
            return XCTFail("Persistence compatibility policy is malformed.")
        }
        let stores = rawStores.compactMapValues { value in
            (value as? NSNumber)?.intValue
        }

        XCTAssertEqual(formatVersion, 1)
        XCTAssertEqual(
            stores,
            [
                "child-session.json": ChildSessionSnapshot.currentSchemaVersion,
                "daily-quests.json": DailyQuestSnapshot.currentSchemaVersion,
                "family-sync-apply-transactions.json":
                    FamilySyncApplyTransactionSnapshot.currentSchemaVersion,
                "family-sync-journal.json":
                    FamilySyncJournalSnapshot.currentSchemaVersion,
                "family-sync-preference.json":
                    FamilySyncPreferenceSnapshot.currentSchemaVersion,
                "first-run-onboarding.json":
                    FirstRunOnboardingState.currentSchemaVersion,
                "learning-records.json":
                    LearningRecordSnapshot.currentSchemaVersion,
                "practice-settings.json":
                    PracticeSettingsSnapshot.currentSchemaVersion,
                "profile-deletions.json":
                    LocalJSONProfileDeletionTombstoneRepository
                    .currentSchemaVersion,
                "profiles.json": KidProfileSnapshot.currentSchemaVersion,
                "word-pool.json": WordPoolSnapshot.currentSchemaVersion,
            ]
        )
    }

    func testConstructingProductionCompositionDoesNotRequestSpeechPermission() async throws {
        let applicationSupportDirectory = try makeTemporaryDirectory()
        defer { removeTemporaryDirectory(applicationSupportDirectory) }
        let recorder = AuthorizationRecorder()

        _ = TadaWordsApplicationView(
            applicationSupportDirectory: { applicationSupportDirectory },
            defaultProfile: Self.defaultProfile,
            audioPromptService: AudioStub(),
            speechRecognitionService: SpeechStub(),
            handwritingRecognitionService: HandwritingStub(),
            requestSpeechAuthorization: {
                await recorder.recordRequest()
                return false
            }
        )

        let requestCount = await recorder.requestCount
        XCTAssertEqual(requestCount, 0)
    }

    func testBootstrapReplaysPendingFamilySyncApplyBeforeEnvironmentExposure()
        async throws
    {
        let applicationSupportDirectory = try makeTemporaryDirectory()
        defer { removeTemporaryDirectory(applicationSupportDirectory) }
        let paths = ApplicationDataPaths(
            applicationSupportDirectory: applicationSupportDirectory
        )
        try FileManager.default.createDirectory(
            at: paths.dataDirectory,
            withIntermediateDirectories: true
        )
        let remoteProfile = KidProfile(
            id: ProfileID(),
            displayName: "Recovered Kid",
            avatar: .cartoonAnimal(assetID: "fox"),
            selectedWorld: .pawsAndPines,
            createdAt: Self.testDate.addingTimeInterval(-100),
            updatedAt: Self.testDate.addingTimeInterval(20)
        )
        let remoteSettings = ProfilePracticeSettings(
            profileID: remoteProfile.id,
            read: LearningRouteSettings(
                newWordLimit: 7,
                reviewWordLimit: 3,
                contentOrder: .reviewThenNew,
                emergencyAfterSeconds: 180
            )
        )
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .secondsSince1970
        let revision = FamilySyncLogicalRevision(
            counter: 6,
            deviceID: "remote-device"
        )
        let records = [
            FamilySyncRecord(
                recordName: "profile-\(remoteProfile.id)",
                profileID: remoteProfile.id,
                kind: .profile,
                payload: try encoder.encode(remoteProfile),
                updatedAt: remoteProfile.updatedAt,
                deviceID: revision.deviceID,
                logicalRevision: revision
            ),
            FamilySyncRecord(
                recordName: "practice-settings-\(remoteProfile.id)",
                profileID: remoteProfile.id,
                kind: .practiceSettings,
                payload: try encoder.encode(remoteSettings),
                updatedAt: remoteProfile.updatedAt,
                deviceID: revision.deviceID,
                logicalRevision: revision
            ),
        ]

        // Simulate a crash after the first repository write: Profile bytes are
        // already visible on disk, while the exact accepted multi-repository
        // batch remains pending and settings were never applied.
        let profileRepository = LocalJSONKidProfileRepository(
            snapshotURL: paths.profilesSnapshot
        )
        try await profileRepository.save(remoteProfile)
        let transactions = LocalJSONFamilySyncApplyTransactionRepository(
            snapshotURL: paths.familySyncApplyTransactionsSnapshot
        )
        let start = try await transactions.begin(
            profileID: remoteProfile.id,
            records: records,
            at: Self.testDate
        )
        guard case .pending(let pendingTransaction) = start else {
            return XCTFail("The crash fixture must begin as pending")
        }

        let environment = try await makeBootstrapper(
            applicationSupportDirectory: applicationSupportDirectory
        ).bootstrap()
        let recoveredSettings = try await environment.practiceSettingsRepository
            .settings(for: remoteProfile.id)
        let pendingAfterRecovery =
            try await environment
            .familySyncApplyTransactionRepository.pendingTransactions()
        let committed =
            try await environment
            .familySyncApplyTransactionRepository.lastCommittedReceipt(
                for: remoteProfile.id
            )

        XCTAssertEqual(environment.profiles, [remoteProfile])
        XCTAssertEqual(recoveredSettings, remoteSettings)
        XCTAssertTrue(pendingAfterRecovery.isEmpty)
        XCTAssertEqual(committed?.transactionID, pendingTransaction.id)
        XCTAssertEqual(committed?.recordCount, 2)
        XCTAssertEqual(
            committed?.affectedKinds,
            [.practiceSettings, .profile]
        )

        // Once committed, the crash file retains only privacy-minimal receipt
        // metadata. Child names and exact payload bytes are gone.
        let committedSnapshotBytes = try Data(
            contentsOf: paths.familySyncApplyTransactionsSnapshot
        )
        let committedSnapshotText = String(
            decoding: committedSnapshotBytes,
            as: UTF8.self
        )
        XCTAssertFalse(committedSnapshotText.contains(remoteProfile.displayName))
        XCTAssertFalse(committedSnapshotText.contains("newWordLimit"))

        let secondRestart = try await makeBootstrapper(
            applicationSupportDirectory: applicationSupportDirectory
        ).bootstrap()
        let secondSettings = try await secondRestart.practiceSettingsRepository
            .settings(for: remoteProfile.id)
        let secondPending =
            try await secondRestart
            .familySyncApplyTransactionRepository.pendingTransactions()
        let secondReceipt =
            try await secondRestart
            .familySyncApplyTransactionRepository.lastCommittedReceipt(
                for: remoteProfile.id
            )
        XCTAssertEqual(secondRestart.profiles, [remoteProfile])
        XCTAssertEqual(secondSettings, remoteSettings)
        XCTAssertTrue(secondPending.isEmpty)
        XCTAssertEqual(secondReceipt, committed)
    }

    func testBootstrapRecoversPendingProfileDeletionJournalWithoutResurrection()
        async throws
    {
        let applicationSupportDirectory = try makeTemporaryDirectory()
        defer { removeTemporaryDirectory(applicationSupportDirectory) }
        let suiteName = "BootstrapHandwritingRecoveryTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let handwritingStore = HandwritingPreferenceStore(
            userDefaults: defaults,
            keyPrefix: "selection"
        )
        let retainedProfileID = ProfileID()
        let first = try await makeBootstrapper(
            applicationSupportDirectory: applicationSupportDirectory,
            handwritingPreferenceRemover: handwritingStore
        ).bootstrap()
        let deletedID = Self.defaultProfile.id
        handwritingStore.save(
            HandwritingSelectionState(tool: .chalk),
            for: deletedID
        )
        handwritingStore.save(
            HandwritingSelectionState(tool: .brush),
            for: retainedProfileID
        )
        try await first.childSessionRepository.saveLastSelectedProfileID(deletedID)
        try await first.tombstoneRepository.save(
            ProfileDeletionTombstone(
                profileID: deletedID,
                deletedAt: Self.testDate.addingTimeInterval(10)
            )
        )

        let restarted = try await makeBootstrapper(
            applicationSupportDirectory: applicationSupportDirectory,
            handwritingPreferenceRemover: handwritingStore
        ).bootstrap()
        let profiles = try await restarted.profileRepository.profiles()
        let pending = try await restarted.tombstoneRepository.pendingTombstones()
        let erasureLifecycles = try await restarted.familySyncCoordinator
            .profileErasureLifecycles()
        let selected = try await restarted.childSessionRepository
            .lastSelectedProfileID()

        XCTAssertTrue(profiles.isEmpty)
        XCTAssertFalse(profiles.contains(where: { $0.id == deletedID }))
        XCTAssertTrue(pending.isEmpty)
        XCTAssertEqual(erasureLifecycles.count, 1)
        XCTAssertEqual(erasureLifecycles.first?.profileID, deletedID)
        XCTAssertEqual(erasureLifecycles.first?.state, .requested)
        XCTAssertEqual(erasureLifecycles.first?.route, .unresolved)
        XCTAssertNil(selected)
        XCTAssertEqual(
            handwritingStore.selection(for: deletedID),
            HandwritingSelectionState()
        )
        XCTAssertEqual(
            handwritingStore.selection(for: retainedProfileID),
            HandwritingSelectionState(tool: .brush)
        )
    }

    func testBootstrapConsumesLegacyHandwritingToolIntoProfileSettings()
        async throws
    {
        let applicationSupportDirectory = try makeTemporaryDirectory()
        defer { removeTemporaryDirectory(applicationSupportDirectory) }
        let suiteName = "BootstrapHandwritingMigrationTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let handwritingStore = HandwritingPreferenceStore(
            userDefaults: defaults,
            keyPrefix: "selection"
        )
        handwritingStore.save(
            HandwritingSelectionState(tool: .brush),
            for: Self.defaultProfile.id
        )

        let environment = try await makeBootstrapper(
            applicationSupportDirectory: applicationSupportDirectory,
            handwritingPreferenceRemover: handwritingStore
        ).bootstrap()
        let settings = try await environment.practiceSettingsRepository.settings(
            for: Self.defaultProfile.id
        )

        XCTAssertEqual(settings?.interface.selectedHandwritingTool, .brush)
        XCTAssertEqual(
            handwritingStore.selection(for: Self.defaultProfile.id),
            HandwritingSelectionState()
        )
    }

    func testBootstrapRepairsHandwritingResidueForCommittedProfileDeletion()
        async throws
    {
        let applicationSupportDirectory = try makeTemporaryDirectory()
        defer { removeTemporaryDirectory(applicationSupportDirectory) }
        let suiteName = "CommittedHandwritingRecoveryTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let handwritingStore = HandwritingPreferenceStore(
            userDefaults: defaults,
            keyPrefix: "selection"
        )
        let first = try await makeBootstrapper(
            applicationSupportDirectory: applicationSupportDirectory,
            handwritingPreferenceRemover: handwritingStore
        ).bootstrap()
        let deletedID = Self.defaultProfile.id
        handwritingStore.save(
            HandwritingSelectionState(tool: .pencil),
            for: deletedID
        )
        try await first.tombstoneRepository.save(
            ProfileDeletionTombstone(
                profileID: deletedID,
                deletedAt: Self.testDate.addingTimeInterval(10)
            )
        )
        try await first.tombstoneRepository.markCommitted(for: deletedID)

        _ = try await makeBootstrapper(
            applicationSupportDirectory: applicationSupportDirectory,
            handwritingPreferenceRemover: handwritingStore
        ).bootstrap()

        XCTAssertEqual(
            handwritingStore.selection(for: deletedID),
            HandwritingSelectionState()
        )
    }

    private func makeBootstrapper(
        applicationSupportDirectory: URL,
        handwritingPreferenceRemover: any HandwritingPreferenceRemoving =
            HandwritingPreferenceStore()
    ) -> ProductionApplicationBootstrapper {
        ProductionApplicationBootstrapper(
            applicationSupportDirectory: { applicationSupportDirectory },
            defaultProfile: Self.defaultProfile,
            clock: FixedAppClock(now: Self.testDate),
            timeZone: TimeZone(secondsFromGMT: 0) ?? .current,
            handwritingPreferenceRemover: handwritingPreferenceRemover
        )
    }

    private func makeTemporaryDirectory() throws -> URL {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true
        )
        return directory
    }

    private func schemaVersion(in url: URL) throws -> Int {
        guard
            let object = try JSONSerialization.jsonObject(
                with: Data(contentsOf: url)
            ) as? [String: Any],
            let version = object["schemaVersion"] as? Int
        else {
            throw CocoaError(.coderReadCorrupt)
        }
        return version
    }

    private func removeTemporaryDirectory(_ directory: URL) {
        try? FileManager.default.removeItem(at: directory)
    }

    private static let testDate = Date(timeIntervalSince1970: 1_735_689_600)

    private static let defaultProfile = KidProfile(
        id: defaultProfileID,
        displayName: "My Kid",
        avatar: .cartoonAnimal(assetID: "hare"),
        selectedWorld: .moonpetalKingdom,
        createdAt: testDate
    )

    private static let defaultProfileID: ProfileID = {
        guard
            let rawValue = UUID(
                uuidString: "3B20FEF0-7E43-4B70-8F89-D37AD55454A1"
            )
        else {
            preconditionFailure("The test profile ID is invalid.")
        }
        return ProfileID(rawValue: rawValue)
    }()
}

private actor AuthorizationRecorder {
    private(set) var requestCount = 0

    func recordRequest() {
        requestCount += 1
    }
}

private struct FixedAppClock: AppClock {
    let now: Date
}

private struct AudioStub: AudioPromptService {
    func play(_ prompt: WordPrompt, for profileID: ProfileID) async throws {
        _ = prompt
        _ = profileID
    }
}

private struct SpeechStub: SpeechRecognitionService {
    func recognize(
        _ request: SpeechRecognitionRequest
    ) async throws -> RecognitionResult {
        _ = request
        return RecognitionResult(
            decision: .technicalFailure(.serviceUnavailable)
        )
    }
}

private struct HandwritingStub: HandwritingRecognitionService {
    func recognize(
        sample: HandwritingSample,
        prompt: WordPrompt,
        for profileID: ProfileID
    ) async throws -> RecognitionResult {
        _ = sample
        _ = prompt
        _ = profileID
        return RecognitionResult(
            decision: .technicalFailure(.serviceUnavailable)
        )
    }
}
