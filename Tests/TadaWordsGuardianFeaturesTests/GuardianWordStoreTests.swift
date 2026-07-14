import TadaWordsContent
import TadaWordsDomain
import XCTest

@testable import TadaWordsGuardianFeatures

final class GuardianWordStoreTests: XCTestCase {
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

private struct GuardianWordStoreSilentAudioPromptService: AudioPromptService {
    func play(_ prompt: WordPrompt, for profileID: ProfileID) async throws {
        _ = prompt
        _ = profileID
    }
}
