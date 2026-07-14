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
        let progress = WordProgress(
            profileID: Self.defaultProfile.id,
            wordPromptID: wordID,
            learningMode: .read,
            firstIndependentAttemptCount: 1,
            firstIndependentCorrectCount: 1,
            lastEncounterAt: Self.testDate
        )

        try await environment.learningRecordRepository.append(attempt)
        try await environment.learningRecordRepository.save(progress)

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
        XCTAssertEqual(persistedProgress, progress)
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
        } catch let error as LocalKidProfileRepositoryError {
            guard case .invalidJSON(let snapshotURL, _) = error else {
                return XCTFail("Unexpected profile repository error: \(error)")
            }
            XCTAssertEqual(snapshotURL, paths.profilesSnapshot)
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
        } catch let error as LocalWordPoolRepositoryError {
            guard case .invalidJSON(let snapshotURL, _) = error else {
                return XCTFail("Unexpected word-pool repository error: \(error)")
            }
            XCTAssertEqual(snapshotURL, paths.wordPoolSnapshot)
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
        } catch let error as LocalLearningRecordRepositoryError {
            guard case .invalidJSON(let snapshotURL, _) = error else {
                return XCTFail("Unexpected learning repository error: \(error)")
            }
            XCTAssertEqual(snapshotURL, paths.learningRecordsSnapshot)
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
        } catch let error as LocalPracticeSettingsRepositoryError {
            guard case .invalidJSON(let snapshotURL, _) = error else {
                return XCTFail("Unexpected settings repository error: \(error)")
            }
            XCTAssertEqual(snapshotURL, paths.practiceSettingsSnapshot)
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
        } catch let error as LocalDailyQuestRepositoryError {
            guard case .invalidJSON(let snapshotURL, _) = error else {
                return XCTFail("Unexpected Daily Quest repository error: \(error)")
            }
            XCTAssertEqual(snapshotURL, paths.dailyQuestsSnapshot)
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
        let selected = try await restarted.childSessionRepository
            .lastSelectedProfileID()

        XCTAssertFalse(profiles.isEmpty)
        XCTAssertFalse(profiles.contains(where: { $0.id == deletedID }))
        XCTAssertTrue(pending.isEmpty)
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
        try await first.profileRepository.delete(id: deletedID)
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
