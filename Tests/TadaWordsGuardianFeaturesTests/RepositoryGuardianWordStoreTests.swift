import Foundation
import TadaWordsContent
import TadaWordsDomain
import XCTest

@testable import TadaWordsGuardianFeatures

final class RepositoryGuardianWordStoreTests: XCTestCase {
    func testDependentReadFailureCannotPartiallyDeactivateWord() async throws {
        let wordRepository = InMemoryWordPoolRepository()
        let profile = makeProfile(number: 90, name: "Ava")
        let prompt = try WordPrompt(learningMode: .read, text: "cat")
        _ = try await wordRepository.upsert([
            WordPoolEntryDraft(
                profileID: profile.id,
                prompt: prompt,
                addedAt: testDate,
                source: .guardianManual,
                positionInBatch: 0
            )
        ])
        let store = RepositoryGuardianWordStore(
            profile: profile,
            wordPoolRepository: wordRepository,
            practiceSettingsRepository: FailingGuardianPracticeSettingsRepository(),
            clock: FixedGuardianClock(now: testDate)
        )

        do {
            _ = try await store.deactivateWord(
                id: prompt.id,
                learningMode: .read
            )
            XCTFail("Expected the dependent settings read to fail")
        } catch {
            // The repository mutation must not run after this preflight failure.
        }

        let activeEntries = try await wordRepository.entries(
            for: profile.id,
            learningMode: .read,
            includingInactive: false
        )
        XCTAssertEqual(activeEntries.map(\.prompt), [prompt])
    }

    func testEmptyProductionStoreNeverSeedsWordsOrAttention() async throws {
        let wordPoolRepository = InMemoryWordPoolRepository()
        let settingsRepository = InMemoryPracticeSettingsRepository()
        let profile = makeProfile(number: 1, name: "Ava")
        let store = RepositoryGuardianWordStore(
            profile: profile,
            wordPoolRepository: wordPoolRepository,
            practiceSettingsRepository: settingsRepository,
            clock: FixedGuardianClock(now: testDate)
        )

        let snapshot = try await store.dashboardSnapshot()

        XCTAssertEqual(snapshot.profile, profile)
        XCTAssertTrue(snapshot.readPool.isEmpty)
        XCTAssertTrue(snapshot.writePool.isEmpty)
        XCTAssertTrue(snapshot.needsAttention.isEmpty)
        XCTAssertEqual(
            snapshot.practiceSettings,
            .defaults(for: profile.id)
        )
        let storedSettings = try await settingsRepository.settings(
            for: profile.id
        )
        XCTAssertNil(storedSettings)
    }

    func testManualImportsAreVisibleThroughAnotherStoreSharingRepository()
        async throws
    {
        let repository = InMemoryWordPoolRepository()
        let profile = makeProfile(number: 1, name: "Ava")
        let firstStore = makeStore(profile: profile, repository: repository)
        _ = try await firstStore.importWords(
            GuardianWordImportRequest(
                rawText: "cat dog",
                learningMode: .read
            )
        )
        _ = try await firstStore.importWords(
            GuardianWordImportRequest(
                rawText: "jump",
                learningMode: .write
            )
        )

        let secondStore = makeStore(profile: profile, repository: repository)
        let snapshot = try await secondStore.dashboardSnapshot()
        let storedReadEntries = try await repository.entries(
            for: profile.id,
            learningMode: .read,
            includingInactive: true
        )

        XCTAssertEqual(
            snapshot.readPool.map(\.normalizedText),
            ["cat", "dog"]
        )
        XCTAssertEqual(snapshot.writePool.map(\.normalizedText), ["jump"])
        XCTAssertTrue(snapshot.needsAttention.isEmpty)
        XCTAssertEqual(Set(storedReadEntries.map(\.addedAt)), [testDate])
    }

    func testPersistentRepositorySurvivesStoreAndRepositoryRestart()
        async throws
    {
        let snapshotURL = try makeSnapshotURL()
        let profile = makeProfile(number: 1, name: "Ava")
        let firstRepository = LocalJSONWordPoolRepository(
            snapshotURL: snapshotURL
        )
        let firstStore = makeStore(
            profile: profile,
            repository: firstRepository
        )
        _ = try await firstStore.importWords(
            GuardianWordImportRequest(rawText: "cat", learningMode: .read)
        )
        _ = try await firstStore.importWords(
            GuardianWordImportRequest(rawText: "play", learningMode: .write)
        )

        let restartedRepository = LocalJSONWordPoolRepository(
            snapshotURL: snapshotURL
        )
        let restartedStore = makeStore(
            profile: profile,
            repository: restartedRepository
        )
        let snapshot = try await restartedStore.dashboardSnapshot()

        XCTAssertEqual(snapshot.readPool.map(\.normalizedText), ["cat"])
        XCTAssertEqual(snapshot.writePool.map(\.normalizedText), ["play"])
        XCTAssertTrue(snapshot.needsAttention.isEmpty)
    }

    func testSharedRepositoryRemainsStrictlyProfileIsolated() async throws {
        let repository = InMemoryWordPoolRepository()
        let firstProfile = makeProfile(number: 1, name: "Ava")
        let secondProfile = makeProfile(number: 2, name: "Leo")
        let firstStore = makeStore(
            profile: firstProfile,
            repository: repository
        )
        let secondStore = makeStore(
            profile: secondProfile,
            repository: repository
        )

        _ = try await firstStore.importWords(
            GuardianWordImportRequest(rawText: "cat", learningMode: .read)
        )
        let untouchedSecondSnapshot = try await secondStore.dashboardSnapshot()
        _ = try await secondStore.importWords(
            GuardianWordImportRequest(rawText: "cat", learningMode: .write)
        )
        let firstSnapshot = try await firstStore.dashboardSnapshot()
        let secondSnapshot = try await secondStore.dashboardSnapshot()

        XCTAssertEqual(untouchedSecondSnapshot.profile, secondProfile)
        XCTAssertTrue(untouchedSecondSnapshot.readPool.isEmpty)
        XCTAssertTrue(untouchedSecondSnapshot.writePool.isEmpty)
        XCTAssertEqual(firstSnapshot.profile, firstProfile)
        XCTAssertEqual(firstSnapshot.readPool.map(\.normalizedText), ["cat"])
        XCTAssertTrue(firstSnapshot.writePool.isEmpty)
        XCTAssertEqual(secondSnapshot.profile, secondProfile)
        XCTAssertTrue(secondSnapshot.readPool.isEmpty)
        XCTAssertEqual(secondSnapshot.writePool.map(\.normalizedText), ["cat"])
    }

    func testWordsAloneNeverCreateFabricatedAttentionWarnings() async throws {
        let repository = InMemoryWordPoolRepository()
        let store = makeStore(
            profile: makeProfile(number: 1, name: "Ava"),
            repository: repository
        )
        _ = try await store.importWords(
            GuardianWordImportRequest(
                rawText: "cat dog fox",
                learningMode: .read
            )
        )
        _ = try await store.importWords(
            GuardianWordImportRequest(
                rawText: "jump play",
                learningMode: .write
            )
        )

        let snapshot = try await store.dashboardSnapshot()

        XCTAssertFalse(snapshot.readPool.isEmpty)
        XCTAssertFalse(snapshot.writePool.isEmpty)
        XCTAssertTrue(snapshot.needsAttention.isEmpty)
    }

    func testProductionImportReportUsesRepositoryDeduplicationAndTypedRejections()
        async throws
    {
        let repository = InMemoryWordPoolRepository()
        let store = makeStore(
            profile: makeProfile(number: 1, name: "Ava"),
            repository: repository
        )
        _ = try await store.importWords(
            GuardianWordImportRequest(rawText: "cat", learningMode: .read)
        )

        let report = try await store.importWords(
            GuardianWordImportRequest(
                rawText: "CAT dog dog bad!",
                learningMode: .read
            )
        )

        XCTAssertEqual(report.accepted, ["dog"])
        XCTAssertEqual(report.duplicates, ["cat", "dog"])
        XCTAssertEqual(report.rejected.map(\.sourceText), ["bad!"])
    }

    func testPracticeSettingsPersistExactlyWithoutChangingPools()
        async throws
    {
        let wordPoolRepository = InMemoryWordPoolRepository()
        let settingsRepository = InMemoryPracticeSettingsRepository()
        let profile = makeProfile(number: 1, name: "Ava")
        let initialSettings = ProfilePracticeSettings(
            profileID: profile.id,
            read: makeRouteSettings(
                newWords: 2,
                reviewWords: 7,
                order: .reviewThenNew,
                emergencyAfterSeconds: 120
            ),
            write: makeRouteSettings(
                newWords: 1,
                reviewWords: 5,
                order: .newThenReview,
                emergencyAfterSeconds: 600
            )
        )
        try await settingsRepository.save(initialSettings)
        let store = RepositoryGuardianWordStore(
            profile: profile,
            wordPoolRepository: wordPoolRepository,
            practiceSettingsRepository: settingsRepository,
            clock: FixedGuardianClock(now: testDate)
        )
        _ = try await store.importWords(
            GuardianWordImportRequest(rawText: "cat", learningMode: .read)
        )

        let initial = try await store.dashboardSnapshot()
        let updatedSettings = ProfilePracticeSettings(
            profileID: profile.id,
            read: makeRouteSettings(
                newWords: 6,
                reviewWords: 4,
                order: .newThenReview,
                emergencyAfterSeconds: 300
            ),
            write: makeRouteSettings(
                newWords: 4,
                reviewWords: 8,
                order: .reviewThenNew,
                emergencyAfterSeconds: 900
            )
        )
        let updated = try await store.updatePracticeSettings(updatedSettings)
        let secondStore = makeStore(
            profile: profile,
            repository: wordPoolRepository,
            settingsRepository: settingsRepository
        )
        let sharedSnapshot = try await secondStore.dashboardSnapshot()

        XCTAssertEqual(initial.practiceSettings, initialSettings)
        XCTAssertEqual(updated.practiceSettings, updatedSettings)
        XCTAssertEqual(sharedSnapshot.practiceSettings, updatedSettings)
        XCTAssertEqual(updated.readPool, initial.readPool)
        XCTAssertEqual(updated.writePool, initial.writePool)
    }

    func testDemoSeedsExplicitlyButDoesNotFabricateAttention() async throws {
        let snapshot = try await DemoGuardianWordStore().dashboardSnapshot()

        XCTAssertEqual(snapshot.readPool.count, 5)
        XCTAssertEqual(snapshot.writePool.count, 3)
        XCTAssertTrue(snapshot.needsAttention.isEmpty)
        XCTAssertEqual(
            snapshot.practiceSettings,
            .defaults(for: snapshot.profile.id)
        )
    }

    func testUpdateRejectsAnotherProfilesSettingsWithoutPersistingThem()
        async throws
    {
        let profile = makeProfile(number: 1, name: "Ava")
        let otherProfile = makeProfile(number: 2, name: "Leo")
        let settingsRepository = InMemoryPracticeSettingsRepository()
        let store = makeStore(
            profile: profile,
            repository: InMemoryWordPoolRepository(),
            settingsRepository: settingsRepository
        )
        let mismatchedSettings = ProfilePracticeSettings.defaults(
            for: otherProfile.id
        )

        do {
            _ = try await store.updatePracticeSettings(mismatchedSettings)
            XCTFail("Expected a profile mismatch error")
        } catch let error as GuardianWordStoreError {
            XCTAssertEqual(
                error,
                .profileMismatch(
                    expected: profile.id,
                    received: otherProfile.id
                )
            )
        }

        let accidentallySaved = try await settingsRepository.settings(
            for: otherProfile.id
        )
        XCTAssertNil(accidentallySaved)
    }

    func testDashboardRejectsRepositorySettingsForAnotherProfile()
        async throws
    {
        let profile = makeProfile(number: 1, name: "Ava")
        let otherProfile = makeProfile(number: 2, name: "Leo")
        let store = makeStore(
            profile: profile,
            repository: InMemoryWordPoolRepository(),
            settingsRepository: MismatchedPracticeSettingsRepository(
                returnedSettings: .defaults(for: otherProfile.id)
            )
        )

        do {
            _ = try await store.dashboardSnapshot()
            XCTFail("Expected a profile mismatch error")
        } catch let error as GuardianWordStoreError {
            XCTAssertEqual(
                error,
                .profileMismatch(
                    expected: profile.id,
                    received: otherProfile.id
                )
            )
        }
    }

    func testPracticeSettingsSurviveRepositoryRestart() async throws {
        let profile = makeProfile(number: 1, name: "Ava")
        let snapshotURL = try makeSettingsSnapshotURL()
        let settings = ProfilePracticeSettings(
            profileID: profile.id,
            read: makeRouteSettings(
                newWords: 9,
                reviewWords: 4,
                order: .reviewThenNew,
                emergencyAfterSeconds: 180
            ),
            write: makeRouteSettings(
                newWords: 5,
                reviewWords: 7,
                order: .newThenReview,
                emergencyAfterSeconds: 720
            )
        )
        let firstSettingsRepository = LocalJSONPracticeSettingsRepository(
            snapshotURL: snapshotURL
        )
        let firstStore = makeStore(
            profile: profile,
            repository: InMemoryWordPoolRepository(),
            settingsRepository: firstSettingsRepository
        )
        _ = try await firstStore.updatePracticeSettings(settings)

        let restartedStore = makeStore(
            profile: profile,
            repository: InMemoryWordPoolRepository(),
            settingsRepository: LocalJSONPracticeSettingsRepository(
                snapshotURL: snapshotURL
            )
        )
        let restartedSnapshot = try await restartedStore.dashboardSnapshot()

        XCTAssertEqual(restartedSnapshot.practiceSettings, settings)
    }

    func testDeactivateRemovesWordFromPracticeButKeepsEntryAndLearningHistory()
        async throws
    {
        let wordRepository = InMemoryWordPoolRepository()
        let learningRepository = InMemoryLearningRecordRepository()
        let profile = makeProfile(number: 1, name: "Ava")
        let store = makeStore(
            profile: profile,
            repository: wordRepository,
            learningRepository: learningRepository
        )
        _ = try await store.importWords(
            GuardianWordImportRequest(rawText: "cat", learningMode: .read)
        )
        let snapshotBeforeDeactivation = try await store.dashboardSnapshot()
        let prompt = try XCTUnwrap(snapshotBeforeDeactivation.readPool.first)
        let attempt = AttemptEvent(
            profileID: profile.id,
            wordPromptID: prompt.id,
            learningMode: .read,
            evidence: .firstIndependentAttempt,
            outcome: .incorrect,
            occurredAt: testDate
        )
        let progress = WordProgress(
            profileID: profile.id,
            wordPromptID: prompt.id,
            learningMode: .read,
            firstIndependentAttemptCount: 1,
            firstIndependentCorrectCount: 0,
            lastEncounterAt: testDate
        )
        try await learningRepository.append(attempt)
        try await learningRepository.save(progress)

        let updated = try await store.deactivateWord(
            id: prompt.id,
            learningMode: .read
        )
        let allEntries = try await wordRepository.entries(
            for: profile.id,
            learningMode: .read,
            includingInactive: true
        )
        let savedAttempts = try await learningRepository.attempts(
            for: profile.id,
            wordPromptID: prompt.id
        )
        let savedProgress = try await learningRepository.progress(
            for: profile.id,
            wordPromptID: prompt.id
        )

        XCTAssertTrue(updated.readPool.isEmpty)
        XCTAssertEqual(allEntries.count, 1)
        XCTAssertFalse(try XCTUnwrap(allEntries.first).isActive)
        XCTAssertEqual(savedAttempts, [attempt])
        XCTAssertEqual(savedProgress, progress)
    }

    func testContextRequiredWordCanBeResubmittedWithOneSpokenContext()
        async throws
    {
        let repository = InMemoryWordPoolRepository()
        let profile = makeProfile(number: 1, name: "Ava")
        let store = makeStore(profile: profile, repository: repository)

        let rejected = try await store.importWords(
            GuardianWordImportRequest(rawText: "too", learningMode: .write)
        )
        let accepted = try await store.importWords(
            GuardianWordImportRequest(
                rawText: "too",
                learningMode: .write,
                spokenContextsByNormalizedWord: [
                    "too": "I want to play too."
                ]
            )
        )
        let snapshot = try await store.dashboardSnapshot()
        let prompt = try XCTUnwrap(snapshot.writePool.first)

        XCTAssertTrue(rejected.accepted.isEmpty)
        XCTAssertEqual(rejected.rejected.map(\.sourceText), ["too"])
        XCTAssertEqual(accepted.accepted, ["too"])
        XCTAssertEqual(prompt.audioCue.spokenContext, "I want to play too.")
        XCTAssertNil(prompt.audioCue.pronunciationKey)
    }

    func testAttentionUsesOnlySelectedProfilesActivePoolAndLearningEvidence()
        async throws
    {
        let wordRepository = InMemoryWordPoolRepository()
        let learningRepository = InMemoryLearningRecordRepository()
        let selectedProfile = makeProfile(number: 1, name: "Ava")
        let otherProfile = makeProfile(number: 2, name: "Leo")
        let selectedStore = makeStore(
            profile: selectedProfile,
            repository: wordRepository,
            learningRepository: learningRepository
        )
        let otherStore = makeStore(
            profile: otherProfile,
            repository: wordRepository,
            learningRepository: learningRepository
        )
        _ = try await selectedStore.importWords(
            GuardianWordImportRequest(rawText: "cat", learningMode: .read)
        )
        _ = try await otherStore.importWords(
            GuardianWordImportRequest(rawText: "dog", learningMode: .read)
        )
        let selectedSnapshot = try await selectedStore.dashboardSnapshot()
        let otherSnapshot = try await otherStore.dashboardSnapshot()
        let selectedPrompt = try XCTUnwrap(selectedSnapshot.readPool.first)
        let otherPrompt = try XCTUnwrap(otherSnapshot.readPool.first)
        try await saveMissedEvidence(
            prompt: selectedPrompt,
            profileID: selectedProfile.id,
            in: learningRepository
        )
        try await saveMissedEvidence(
            prompt: otherPrompt,
            profileID: otherProfile.id,
            in: learningRepository
        )

        let snapshot = try await selectedStore.dashboardSnapshot()

        XCTAssertEqual(snapshot.needsAttention.map(\.prompt.id), [selectedPrompt.id])
        XCTAssertEqual(snapshot.needsAttention.first?.reason, .missedOften)
        XCTAssertEqual(
            snapshot.needsAttention.first?.whyNow,
            "Missed 2 of 2 first tries."
        )
    }

    private let testDate = Date(timeIntervalSince1970: 2_000_000_000)

    private func makeStore(
        profile: KidProfile,
        repository: any WordPoolRepository,
        settingsRepository: any PracticeSettingsRepository =
            InMemoryPracticeSettingsRepository(),
        learningRepository:
            (any AttemptEventRepository & WordProgressRepository)? = nil
    ) -> RepositoryGuardianWordStore {
        RepositoryGuardianWordStore(
            profile: profile,
            wordPoolRepository: repository,
            practiceSettingsRepository: settingsRepository,
            learningRecordRepository: learningRepository,
            clock: FixedGuardianClock(now: testDate)
        )
    }

    private func saveMissedEvidence(
        prompt: WordPrompt,
        profileID: ProfileID,
        in repository: InMemoryLearningRecordRepository
    ) async throws {
        for offset in 0..<2 {
            try await repository.append(
                AttemptEvent(
                    profileID: profileID,
                    wordPromptID: prompt.id,
                    learningMode: prompt.learningMode,
                    evidence: .firstIndependentAttempt,
                    outcome: .incorrect,
                    occurredAt: testDate.addingTimeInterval(TimeInterval(offset))
                )
            )
        }
        try await repository.save(
            WordProgress(
                profileID: profileID,
                wordPromptID: prompt.id,
                learningMode: prompt.learningMode,
                firstIndependentAttemptCount: 2,
                firstIndependentCorrectCount: 0,
                lastEncounterAt: testDate.addingTimeInterval(1)
            )
        )
    }

    private func makeRouteSettings(
        newWords: Int,
        reviewWords: Int,
        order: QuestContentOrder,
        emergencyAfterSeconds: Int
    ) -> LearningRouteSettings {
        LearningRouteSettings(
            newWordLimit: newWords,
            reviewWordLimit: reviewWords,
            contentOrder: order,
            emergencyAfterSeconds: emergencyAfterSeconds
        )
    }

    private func makeProfile(number: Int, name: String) -> KidProfile {
        let suffix = String(format: "%012X", number)
        return KidProfile(
            id: ProfileID(
                rawValue: UUID(
                    uuidString: "81000000-0000-0000-0000-\(suffix)"
                )!
            ),
            displayName: name,
            avatar: .cartoonAnimal(assetID: "hare"),
            selectedWorld: .moonpetalKingdom,
            createdAt: Date(timeIntervalSince1970: 0)
        )
    }

    private func makeSnapshotURL() throws -> URL {
        let directoryURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(
                "GuardianWordStoreTests-\(UUID().uuidString)",
                isDirectory: true
            )
        try FileManager.default.createDirectory(
            at: directoryURL,
            withIntermediateDirectories: true
        )
        addTeardownBlock {
            try? FileManager.default.removeItem(at: directoryURL)
        }
        return directoryURL.appendingPathComponent("word-pool.json")
    }

    private func makeSettingsSnapshotURL() throws -> URL {
        let directoryURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(
                "GuardianPracticeSettingsTests-\(UUID().uuidString)",
                isDirectory: true
            )
        try FileManager.default.createDirectory(
            at: directoryURL,
            withIntermediateDirectories: true
        )
        addTeardownBlock {
            try? FileManager.default.removeItem(at: directoryURL)
        }
        return directoryURL.appendingPathComponent("practice-settings.json")
    }
}

private struct FixedGuardianClock: AppClock {
    let now: Date
}

private actor MismatchedPracticeSettingsRepository: PracticeSettingsRepository {
    let returnedSettings: ProfilePracticeSettings

    init(returnedSettings: ProfilePracticeSettings) {
        self.returnedSettings = returnedSettings
    }

    func settings(
        for profileID: ProfileID
    ) async throws -> ProfilePracticeSettings? {
        returnedSettings
    }

    func save(_ settings: ProfilePracticeSettings) async throws {}

    func delete(for profileID: ProfileID) async throws {}
}

private actor FailingGuardianPracticeSettingsRepository: PracticeSettingsRepository {
    func settings(for profileID: ProfileID) async throws -> ProfilePracticeSettings? {
        _ = profileID
        throw GuardianWordStoreTestFailure.unavailable
    }

    func save(_ settings: ProfilePracticeSettings) async throws {
        _ = settings
        throw GuardianWordStoreTestFailure.unavailable
    }

    func delete(for profileID: ProfileID) async throws {
        _ = profileID
        throw GuardianWordStoreTestFailure.unavailable
    }
}

private enum GuardianWordStoreTestFailure: Error {
    case unavailable
}
