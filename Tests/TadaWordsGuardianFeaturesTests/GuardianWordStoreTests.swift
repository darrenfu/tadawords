import Foundation
import TadaWordsContent
import TadaWordsDomain
import XCTest

@testable import TadaWordsGuardianFeatures

final class GuardianWordStoreTests: XCTestCase {
    @MainActor
    func testTeacherAudioImportFailuresStayParentRecoverableAndPrivacySafe() {
        let cases: [(Error, String)] = [
            (
                TeacherWordAudioError.serverRejected(statusCode: 422),
                "approved teacher-audio vocabulary"
            ),
            (
                TeacherWordAudioError.serverRejected(statusCode: 429),
                "temporarily busy"
            ),
            (
                TeacherWordAudioError.appAttestUnavailable,
                "could not verify"
            ),
            (
                TeacherWordAudioError.unconfiguredEndpoint,
                "not available in this build"
            ),
            (
                URLError(.notConnectedToInternet),
                "Connect to the internet"
            ),
        ]

        for (error, expectedCopy) in cases {
            let message = GuardianDashboardViewModel.wordImportErrorMessage(error)
            XCTAssertTrue(message.contains(expectedCopy))
            XCTAssertFalse(message.localizedCaseInsensitiveContains("profile"))
            XCTAssertFalse(message.localizedCaseInsensitiveContains("child"))
            XCTAssertFalse(message.contains("Mia"))
        }
    }

    func testKeyboardDismissGestureNeverOwnsControlTouchesExclusively() {
        XCTAssertFalse(GuardianKeyboardDismissGesturePolicy.cancelsControlTouches)
        XCTAssertFalse(GuardianKeyboardDismissGesturePolicy.delaysTouchDelivery)
        XCTAssertTrue(GuardianKeyboardDismissGesturePolicy.recognizesAlongsideControls)
    }

    func testOCRAddAllUsesCanonicalPronunciationForAmbiguousWords() async throws {
        let words = ["read", "bow", "lead", "to", "too", "two"]

        XCTAssertTrue(
            GuardianOCRSubmissionPolicy.canSubmit(
                addableWords: words,
                isAdding: false,
                isRecognizingAdditionalPhotos: false
            )
        )
        let store = DemoGuardianWordStore()
        let report = try await store.importWords(
            GuardianWordImportRequest(
                rawText: words.joined(separator: "\n"),
                learningMode: .write
            )
        )

        XCTAssertEqual(report.accepted, words)
        XCTAssertTrue(report.rejected.isEmpty)
        let imported = try await store.dashboardSnapshot().writePool.filter {
            words.contains($0.normalizedText)
        }
        XCTAssertEqual(imported.count, words.count)
        XCTAssertTrue(imported.allSatisfy { $0.audioCue == .isolated })
    }

    func testViewModelKeepsUsableUndoAcrossConsecutiveRemovals() async throws {
        let store = DemoGuardianFamilyStore()
        let originalWords = try await store.dashboardSnapshot().readPool
        let first = try XCTUnwrap(originalWords.first)
        let second = try XCTUnwrap(originalWords.dropFirst().first)
        let model = await MainActor.run {
            GuardianDashboardViewModel(
                store: store,
                audioPromptService: GuardianWordStoreSilentAudioPromptService()
            )
        }

        let removedFirst = await model.setWordsActive([first], isActive: false)
        XCTAssertTrue(removedFirst)
        let firstUndo = await MainActor.run { model.undoWordsByMode[.read] }
        XCTAssertEqual(firstUndo, [first])

        let removedSecond = await model.setWordsActive([second], isActive: false)
        XCTAssertTrue(removedSecond)
        let secondUndo = await MainActor.run { model.undoWordsByMode[.read] }
        XCTAssertEqual(secondUndo, [second])

        let restoredSecond = await model.setWordsActive([second], isActive: true)
        XCTAssertTrue(restoredSecond)
        let clearedUndo = await MainActor.run { model.undoWordsByMode[.read] }
        XCTAssertNil(clearedUndo)

        let activeWords = try await store.dashboardSnapshot().readPool
        XCTAssertFalse(activeWords.contains(first))
        XCTAssertTrue(activeWords.contains(second))
    }

    func testViewModelDeleteAllKeepsOtherPoolAndUndoRestoresEntirePool() async throws {
        let store = DemoGuardianFamilyStore()
        let original = try await store.dashboardSnapshot()
        let model = await MainActor.run {
            GuardianDashboardViewModel(
                store: store,
                audioPromptService: GuardianWordStoreSilentAudioPromptService()
            )
        }

        let removed = await model.setWordsActive(original.readPool, isActive: false)

        XCTAssertTrue(removed)
        let removalSnapshot = await MainActor.run { model.snapshot }
        let afterRemoval = try XCTUnwrap(removalSnapshot)
        XCTAssertTrue(afterRemoval.readPool.isEmpty)
        XCTAssertEqual(afterRemoval.writePool, original.writePool)
        let pendingUndo = await MainActor.run { model.undoWordsByMode[.read] }
        let undo = try XCTUnwrap(pendingUndo)
        XCTAssertEqual(undo, original.readPool)

        let restored = await model.setWordsActive(undo, isActive: true)

        XCTAssertTrue(restored)
        let undoSnapshot = await MainActor.run { model.snapshot }
        let afterUndo = try XCTUnwrap(undoSnapshot)
        XCTAssertEqual(afterUndo.readPool, original.readPool)
        XCTAssertEqual(afterUndo.writePool, original.writePool)
        let clearedUndo = await MainActor.run { model.undoWordsByMode[.read] }
        XCTAssertNil(clearedUndo)
    }

    func testWordRemovalUndoAndConfirmationStayScopedToEachProfile() async throws {
        let profileRepository = InMemoryKidProfileRepository()
        let firstProfile = KidProfile(
            displayName: "Mia",
            avatar: .cartoonAnimal(assetID: "hare"),
            selectedWorld: .moonpetalKingdom,
            createdAt: Date(timeIntervalSince1970: 1_999_999_900)
        )
        let secondProfile = KidProfile(
            displayName: "Leo",
            avatar: .cartoonAnimal(assetID: "fox"),
            selectedWorld: .pawsAndPines,
            createdAt: Date(timeIntervalSince1970: 1_999_999_901)
        )
        try await profileRepository.save(firstProfile)
        try await profileRepository.save(secondProfile)
        let store = RepositoryGuardianFamilyStore(
            profiles: [firstProfile, secondProfile],
            selectedProfileID: firstProfile.id,
            profileRepository: profileRepository,
            wordPoolRepository: InMemoryWordPoolRepository(),
            practiceSettingsRepository: InMemoryPracticeSettingsRepository(),
            clock: GuardianWordStoreFixedClock(now: Date(timeIntervalSince1970: 2_000_000_000))
        )
        _ = try await store.importWords(
            GuardianWordImportRequest(rawText: "cat", learningMode: .read)
        )
        _ = try await store.selectProfile(id: secondProfile.id)
        _ = try await store.importWords(
            GuardianWordImportRequest(rawText: "dog", learningMode: .read)
        )
        _ = try await store.selectProfile(id: firstProfile.id)
        let model = await MainActor.run {
            GuardianDashboardViewModel(
                store: store,
                audioPromptService: GuardianWordStoreSilentAudioPromptService()
            )
        }
        await MainActor.run { model.unlockGuardianArea() }
        try await waitForProfile(firstProfile.id, in: model)

        let firstWords = try await MainActor.run {
            try XCTUnwrap(model.snapshot).readPool
        }
        await MainActor.run { model.setWordRemovalConfirmation(true) }
        let removedFirstWords = await model.setWordsActive(firstWords, isActive: false)
        XCTAssertTrue(removedFirstWords)

        await MainActor.run { model.selectProfile(secondProfile) }
        try await waitForProfile(secondProfile.id, in: model)

        let secondProfileState = await MainActor.run {
            (
                model.hasConfirmedWordRemovalThisSession,
                model.undoWordsByMode[.read],
                model.snapshot?.readPool
            )
        }
        XCTAssertFalse(secondProfileState.0)
        XCTAssertNil(secondProfileState.1)
        XCTAssertEqual(secondProfileState.2?.map(\.normalizedText), ["dog"])

        await MainActor.run { model.selectProfile(firstProfile) }
        try await waitForProfile(firstProfile.id, in: model)

        let restoredFirstProfileState = await MainActor.run {
            (
                model.hasConfirmedWordRemovalThisSession,
                model.undoWordsByMode[.read]
            )
        }
        XCTAssertTrue(restoredFirstProfileState.0)
        XCTAssertEqual(restoredFirstProfileState.1, firstWords)
    }

    @MainActor
    func testPresetRollbackUsesExactIDsAfterImportRefreshFailure() async throws {
        let profileRepository = InMemoryKidProfileRepository()
        let profile = KidProfile(
            displayName: "Mia",
            avatar: .cartoonAnimal(assetID: "hare"),
            selectedWorld: .moonpetalKingdom,
            createdAt: Date(timeIntervalSince1970: 1_999_999_900)
        )
        try await profileRepository.save(profile)
        let wordRepository = InMemoryWordPoolRepository()
        let settingsRepository = GuardianFailOnSettingsReadNumber(failingRead: 2)
        let store = RepositoryGuardianFamilyStore(
            profiles: [profile],
            profileRepository: profileRepository,
            wordPoolRepository: wordRepository,
            practiceSettingsRepository: settingsRepository,
            clock: GuardianWordStoreFixedClock(
                now: Date(timeIntervalSince1970: 2_000_000_000)
            )
        )
        let model = GuardianDashboardViewModel(
            store: store,
            audioPromptService: GuardianWordStoreSilentAudioPromptService()
        )
        model.unlockGuardianArea()
        try await waitForProfile(profile.id, in: model)
        let plan = PresetWordSelectionPlanner().plan(
            selectedWords: ["dog"],
            destination: .both,
            existingReadWords: [],
            existingWriteWords: []
        )
        var submittedModes: [LearningMode] = []

        let outcome = await GuardianPresetImportCoordinator().execute(
            profileID: profile.id,
            plan: plan,
            submit: { profileID, request in
                submittedModes.append(request.learningMode)
                guard request.learningMode == .read else { return nil }
                return await model.addPresetWords(request, for: profileID)
            },
            rollback: model.rollbackPresetAdditions
        )

        XCTAssertEqual(submittedModes, [.read, .write])
        XCTAssertEqual(outcome, .failure(.rolledBack))
        let records = try await wordRepository.entries(
            for: profile.id,
            learningMode: .read,
            includingInactive: true
        )
        XCTAssertEqual(records.map(\.normalizedText), ["dog"])
        XCTAssertTrue(records.allSatisfy { !$0.isActive })
        XCTAssertTrue(model.snapshot?.readPool.isEmpty == true)
        XCTAssertFalse(model.isUpdatingWordPool)
    }

    func testDemoStoreConcurrentRefreshKeepsDashboardAndMutationOnOneProfile()
        async throws
    {
        let store = DemoGuardianFamilyStore()

        async let family = store.familySnapshot()
        async let dashboard = store.dashboardSnapshot()
        let (loadedFamily, loadedDashboard) = try await (family, dashboard)

        XCTAssertEqual(loadedFamily.profiles.count, 1)
        XCTAssertEqual(loadedFamily.selectedProfileID, loadedDashboard.profile.id)

        let first = try XCTUnwrap(loadedDashboard.readPool.first)
        let updated = try await store.setWordsActive(
            ids: [first.id],
            learningMode: first.learningMode,
            isActive: false
        )
        XCTAssertFalse(updated.readPool.contains(first))
    }

    func testImportRefreshThenPoolSortRemainsDeterministic() async throws {
        let store = DemoGuardianFamilyStore()
        let model = await MainActor.run {
            GuardianDashboardViewModel(
                store: store,
                audioPromptService: GuardianWordStoreSilentAudioPromptService()
            )
        }

        let report = await model.addWords(
            GuardianWordImportRequest(
                rawText: "zebra apple",
                learningMode: .read
            )
        )
        let snapshot = await MainActor.run { model.snapshot }
        let sorted = GuardianWordListPresentation.prompts(
            try XCTUnwrap(snapshot).readPool,
            sortOrder: .alphabetical,
            searchText: "",
            practiceFrequencyByWordID: [:]
        )

        XCTAssertEqual(report?.accepted, ["zebra", "apple"])
        XCTAssertEqual(sorted.map(\.normalizedText), sorted.map(\.normalizedText).sorted())
        let isUpdatingWordPool = await MainActor.run { model.isUpdatingWordPool }
        XCTAssertFalse(isUpdatingWordPool)
    }

    func testOCRPreviewSkipsExistingDuplicatesAndInvalidEdits() {
        let existing = Set(["cat"])
        let ready = GuardianEditableOCRWord(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000000001")!,
            text: "Dog"
        )
        let inPool = GuardianEditableOCRWord(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000000002")!,
            text: "CAT"
        )
        let duplicate = GuardianEditableOCRWord(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000000003")!,
            text: "dog"
        )
        let invalid = GuardianEditableOCRWord(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000000004")!,
            text: "123"
        )

        let analysis = GuardianOCRPreviewAnalysis(
            words: [ready, inPool, duplicate, invalid],
            existingNormalizedWords: existing
        )

        XCTAssertEqual(analysis.addableWords, ["dog"])
        XCTAssertEqual(analysis.stateByID[ready.id], .ready(normalizedWord: "dog"))
        XCTAssertEqual(analysis.stateByID[inPool.id], .alreadyInPool)
        XCTAssertEqual(analysis.stateByID[duplicate.id], .duplicateInPreview)
        XCTAssertEqual(analysis.stateByID[invalid.id], .invalid)
    }

    func testOCRBatchKeepsStableOneBasedNumbersAcrossMultiplePhotos() {
        let firstPhoto = GuardianOCRBatchAccumulator.appending(
            ["zebra", "cat"],
            to: []
        )
        let completeBatch = GuardianOCRBatchAccumulator.appending(
            ["apple"],
            to: firstPhoto
        )

        XCTAssertEqual(completeBatch.map(\.sourceOrdinal), [1, 2, 3])
        XCTAssertEqual(completeBatch.map(\.text), ["zebra", "cat", "apple"])

        let alphabetized = GuardianWordListPresentation.recognizedWords(
            completeBatch,
            sortOrder: .alphabetical,
            practiceFrequencyByNormalizedWord: [:]
        )
        XCTAssertEqual(alphabetized.map(\.text), ["apple", "cat", "zebra"])
        XCTAssertEqual(alphabetized.map(\.sourceOrdinal), [3, 2, 1])
    }

    func testOCRPhotoAllowsFiveHundredWordsAndRejectsFiveHundredOne() throws {
        let policy = GuardianOCRPhotoWordLimitPolicy()

        XCTAssertNoThrow(
            try policy.validate(recognizedWordCount: 500)
        )
        XCTAssertThrowsError(
            try policy.validate(recognizedWordCount: 501)
        ) { error in
            XCTAssertEqual(
                error as? GuardianOCRPhotoWordLimitError,
                .tooManyWords(recognizedCount: 501, maximum: 500)
            )
        }
    }

    func testWordPoolPresentationSupportsSearchAndFrequencySorting() throws {
        let cat = try WordPrompt(learningMode: .read, text: "cat")
        let dog = try WordPrompt(learningMode: .read, text: "dog")
        let apple = try WordPrompt(learningMode: .read, text: "apple")
        let prompts = [cat, dog, apple]
        let frequencies = [cat.id: 2, dog.id: 7, apple.id: 2]

        XCTAssertEqual(
            GuardianWordListPresentation.prompts(
                prompts,
                sortOrder: .addedOrder,
                searchText: "",
                practiceFrequencyByWordID: frequencies
            ).map(\.normalizedText),
            ["cat", "dog", "apple"]
        )
        XCTAssertEqual(
            GuardianWordListPresentation.prompts(
                prompts,
                sortOrder: .alphabetical,
                searchText: "",
                practiceFrequencyByWordID: frequencies
            ).map(\.normalizedText),
            ["apple", "cat", "dog"]
        )
        XCTAssertEqual(
            GuardianWordListPresentation.prompts(
                prompts,
                sortOrder: .practiceFrequency,
                searchText: "",
                practiceFrequencyByWordID: frequencies
            ).map(\.normalizedText),
            ["dog", "apple", "cat"]
        )
        XCTAssertEqual(
            GuardianWordListPresentation.prompts(
                prompts,
                sortOrder: .alphabetical,
                searchText: "og",
                practiceFrequencyByWordID: frequencies
            ).map(\.normalizedText),
            ["dog"]
        )
    }

    func testImportReportsAcceptedDuplicatesAndRejectedWords() async throws {
        let store = DemoGuardianWordStore()

        let report = try await store.importWords(
            GuardianWordImportRequest(
                rawText: "cat cat the bad!",
                learningMode: .read
            )
        )

        XCTAssertEqual(report.accepted, ["cat"])
        XCTAssertEqual(report.duplicates, ["the", "cat"])
        XCTAssertEqual(report.rejected.map(\.sourceText), ["bad!"])
    }

    func testSameWordCanBelongToSeparateReadAndWritePools() async throws {
        let store = DemoGuardianWordStore()

        let readReport = try await store.importWords(
            GuardianWordImportRequest(rawText: "jump", learningMode: .read)
        )
        let writeReport = try await store.importWords(
            GuardianWordImportRequest(rawText: "jump", learningMode: .write)
        )
        let snapshot = try await store.dashboardSnapshot()

        XCTAssertEqual(readReport.accepted, ["jump"])
        XCTAssertEqual(writeReport.accepted, ["jump"])
        XCTAssertTrue(snapshot.readPool.contains { $0.normalizedText == "jump" })
        XCTAssertTrue(snapshot.writePool.contains { $0.normalizedText == "jump" })
    }

    func testDefaultAndUpdatedPracticeSettings() async throws {
        let store = DemoGuardianWordStore()

        let initialSnapshot = try await store.dashboardSnapshot()
        XCTAssertEqual(
            initialSnapshot.practiceSettings,
            .defaults(for: initialSnapshot.profile.id)
        )

        let settings = ProfilePracticeSettings(
            profileID: initialSnapshot.profile.id,
            read: LearningRouteSettings(
                newWordLimit: 7,
                reviewWordLimit: 6,
                contentOrder: .reviewThenNew,
                emergencyAfterSeconds: 240
            ),
            write: LearningRouteSettings(
                newWordLimit: 4,
                reviewWordLimit: 2,
                contentOrder: .newThenReview,
                emergencyAfterSeconds: 420
            )
        )
        let updatedSnapshot = try await store.updatePracticeSettings(settings)

        XCTAssertEqual(updatedSnapshot.practiceSettings, settings)
    }
}

private struct GuardianWordStoreFixedClock: AppClock {
    let now: Date
}

private actor GuardianFailOnSettingsReadNumber: PracticeSettingsRepository {
    private let failingRead: Int
    private var reads = 0

    init(failingRead: Int) {
        self.failingRead = failingRead
    }

    func settings(for profileID: ProfileID) async throws -> ProfilePracticeSettings? {
        _ = profileID
        reads += 1
        if reads >= failingRead {
            throw GuardianWordStoreInjectedFailure.unavailable
        }
        return nil
    }

    func save(_ settings: ProfilePracticeSettings) async throws {
        _ = settings
    }

    func delete(for profileID: ProfileID) async throws {
        _ = profileID
    }
}

private enum GuardianWordStoreInjectedFailure: Error {
    case unavailable
}

private struct GuardianWordStoreWaitTimeout: Error {}

private func waitForProfile(
    _ profileID: ProfileID,
    in model: GuardianDashboardViewModel
) async throws {
    for _ in 0..<200 {
        let isReady = await MainActor.run {
            model.snapshot?.profile.id == profileID && !model.isLoading
        }
        if isReady { return }
        try await Task.sleep(for: .milliseconds(10))
    }
    throw GuardianWordStoreWaitTimeout()
}

private struct GuardianWordStoreSilentAudioPromptService: AudioPromptService {
    func play(_ prompt: WordPrompt, for profileID: ProfileID) async throws {
        _ = prompt
        _ = profileID
    }
}
