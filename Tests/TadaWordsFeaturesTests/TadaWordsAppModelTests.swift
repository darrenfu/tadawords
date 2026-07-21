import Foundation
import TadaWordsContent
import TadaWordsDomain
import XCTest

@testable import TadaWordsFeatures

@MainActor
final class TadaWordsAppModelTests: XCTestCase {
    func testValidRememberedProfileIsHighlightedButStillRequiresAChildTap() {
        let first = TestFixture.profile(name: "Mia", number: 901)
        let remembered = TestFixture.profile(name: "Coco", number: 902)

        let restored = TadaWordsAppModel(
            profiles: [first, remembered],
            initialProfileID: remembered.id
        )
        XCTAssertNil(restored.selectedProfile)
        XCTAssertEqual(restored.lastPlayedProfileID, remembered.id)
        guard case .profileChooser = restored.destination else {
            return XCTFail("Cold launch must wait for the child to tap a player.")
        }

        restored.selectProfile(remembered)
        XCTAssertEqual(restored.selectedProfile, remembered)
        XCTAssertEqual(restored.lastPlayedProfileID, remembered.id)
        guard case .lobby = restored.destination else {
            return XCTFail("Tapping the highlighted player should open the lobby.")
        }

        restored.showProfiles()
        XCTAssertNil(restored.selectedProfile)
        XCTAssertEqual(restored.lastPlayedProfileID, remembered.id)
        guard case .profileChooser = restored.destination else {
            return XCTFail("Choosing another player must end the active child session.")
        }
    }

    func testMissingRememberedProfileHasNoHighlightAndStaysInChooser() {
        let first = TestFixture.profile(name: "Mia", number: 901)
        let deleted = TestFixture.profile(name: "Coco", number: 902)

        let stale = TadaWordsAppModel(
            profiles: [first],
            initialProfileID: deleted.id
        )
        XCTAssertNil(stale.selectedProfile)
        XCTAssertNil(stale.lastPlayedProfileID)
        guard case .profileChooser = stale.destination else {
            return XCTFail("A deleted remembered player must return to the chooser.")
        }
    }

    func testSelectedProfileIsRememberedWithoutBlockingPlayWhenPreferenceWriteFails()
        async
    {
        let profile = TestFixture.profile(name: "Mia", number: 903)
        let model = TadaWordsAppModel(
            profiles: [profile],
            childSessionRepository: FailingChildSessionRepository()
        )

        await model.selectProfileAndWait(profile)

        XCTAssertEqual(model.selectedProfile, profile)
        guard case .lobby = model.destination else {
            return XCTFail("A preference failure must not block the child's lobby.")
        }
    }

    func testChildCreationPersistsSelectsAndBecomesTheRememberedProfile()
        async throws
    {
        let existing = TestFixture.profile(name: "Mia", number: 904)
        let profiles = InMemoryKidProfileRepository()
        try await profiles.save(existing)
        let settings = InMemoryPracticeSettingsRepository()
        let session = InMemoryChildSessionRepository()
        let model = TadaWordsAppModel(
            profiles: [existing],
            practiceSettingsRepository: settings,
            clock: TestClock(),
            childSessionRepository: session,
            childProfileCreator: RepositoryChildProfileCreator(
                profileRepository: profiles,
                practiceSettingsRepository: settings,
                clock: TestClock()
            )
        )

        let didCreate = await model.createChildProfileAndWait(
            nickname: "  Coco ",
            ageYears: 5
        )
        XCTAssertTrue(didCreate)

        let created = try XCTUnwrap(model.selectedProfile)
        let persistedProfile = try await profiles.profile(id: created.id)
        let createdSettings = try await settings.settings(for: created.id)
        let rememberedProfileID = try await session.lastSelectedProfileID()
        XCTAssertEqual(created.displayName, "Coco")
        XCTAssertEqual(created.ageYears, 5)
        XCTAssertEqual(created.schoolGrade, .kindergarten)
        XCTAssertEqual(model.profiles.count, 2)
        XCTAssertEqual(persistedProfile, created)
        XCTAssertEqual(
            createdSettings,
            .defaults(for: created.id)
        )
        XCTAssertEqual(rememberedProfileID, created.id)
        XCTAssertNil(model.childProfileCreationError)
        guard case .lobby = model.destination else {
            return XCTFail("A newly created player should enter its lobby immediately.")
        }
    }

    func testChildCreationRequiresAnExplicitAgeSelection() async {
        let existing = TestFixture.profile(name: "Mia", number: 906)
        let model = TadaWordsAppModel(
            profiles: [existing],
            childProfileCreator: nil
        )

        let didCreate = await model.createChildProfileAndWait(
            nickname: "Coco",
            ageYears: nil
        )

        XCTAssertFalse(didCreate)
        XCTAssertEqual(model.profiles, [existing])
        XCTAssertNil(model.selectedProfile)
        XCTAssertEqual(
            model.childProfileCreationError,
            "Choose your age, then try again."
        )
    }

    func testChildCreationFailureDoesNotAddOrSelectPhantomProfile() async {
        let existing = TestFixture.profile(name: "Mia", number: 905)
        let model = TadaWordsAppModel(
            profiles: [existing],
            childProfileCreator: FailingChildProfileCreator()
        )

        let didCreate = await model.createChildProfileAndWait(
            nickname: "Coco",
            ageYears: 4
        )
        XCTAssertFalse(didCreate)

        XCTAssertEqual(model.profiles, [existing])
        XCTAssertNil(model.selectedProfile)
        guard case .profileChooser = model.destination else {
            return XCTFail("A failed create must keep the real profile chooser visible.")
        }
        XCTAssertNotNil(model.childProfileCreationError)
    }

    func testPromptFailureBlocksThePromptRouteInsteadOfAlwaysShowingWrite() async throws {
        let profile = TestFixture.profile(name: "Mia", number: 1)
        let readPrompt = try TestFixture.prompt("cat", number: 1)
        let model = TadaWordsAppModel(
            profiles: [profile],
            audioPromptService: FailingAudioPromptService()
        )
        model.selectProfile(profile)

        await model.speakAndWait(readPrompt)

        guard case .blocked(let mode, let reason) = model.destination else {
            return XCTFail("Expected the Read route to show its audio failure")
        }
        XCTAssertEqual(mode, .read)
        XCTAssertEqual(reason, .audioUnavailable)
    }

    func testStartQuestPublishesPreparingStateBeforeAsyncWorkRuns() throws {
        let fixture = try ModelFixture(wordCount: 1)

        fixture.model.startQuest(.read)

        guard case .loading(let mode, let phase) = fixture.model.destination else {
            throw TestFailure.expectedLoading
        }
        XCTAssertEqual(mode, .read)
        XCTAssertEqual(phase, .preparing)
        fixture.model.showLobby()
    }

    func testWriteRouteOffersChoiceBeforePreparingSharedQuest() throws {
        let fixture = try ModelFixture(wordCount: 1, mode: .write)

        fixture.model.chooseQuest(.write)

        guard case .writeInputChooser = fixture.model.destination else {
            return XCTFail("Expected the Write response chooser")
        }
    }

    func testLetterKeyboardChoiceReachesSessionAndPersistedPaceContext()
        async throws
    {
        let fixture = try ModelFixture(wordCount: 1, mode: .write)
        await fixture.model.prepareQuestAndWait(
            .write,
            writeInputMethod: .letterKeyboard
        )
        let session = try questSession(from: fixture.model.destination)
        XCTAssertEqual(session.writeInputMethod, .letterKeyboard)

        var attemptState = QuestAttemptStateMachine(policy: .write)
        XCTAssertTrue(attemptState.beginAttempt())
        attemptState.receive(
            RecognitionResult(decision: .matched),
            timing: AttemptTiming(
                totalResponseTime: ElapsedTime(seconds: 2)
            )
        )
        let summary = try XCTUnwrap(attemptState.completedSummary)

        await fixture.model.finishItemAndWait(session, summary: summary)

        let attempts = try await fixture.records.attempts(
            for: fixture.profile.id,
            wordPromptID: session.prompt.id
        )
        let context = try XCTUnwrap(attempts.first?.paceContext)
        XCTAssertEqual(context.learningMode, .write)
        XCTAssertEqual(context.inputMethod, .letterKeyboard)
    }

    func testFocusedReplayKeepsLetterKeyboardChoice() async throws {
        let fixture = try ModelFixture(wordCount: 1, mode: .write)
        await fixture.model.prepareQuestAndWait(
            .write,
            writeInputMethod: .letterKeyboard
        )
        let firstSession = try questSession(from: fixture.model.destination)
        await fixture.model.finishItemAndWait(
            firstSession,
            summary: try TestFixture.summary(decisions: [.notMatched, .matched])
        )

        await fixture.model.replayMissedWordsAndWait()

        let replaySession = try questSession(from: fixture.model.destination)
        XCTAssertEqual(replaySession.writeInputMethod, .letterKeyboard)
        XCTAssertEqual(replaySession.prompt.id, firstSession.prompt.id)
    }

    func testInjectedProfileIDIsUsedForPreparationAndQuestSession() async throws {
        let profile = TestFixture.profile(name: "Nora", number: 42)
        let prompt = try TestFixture.prompt("cat", number: 42)
        let provider = ProfileRecordingContentProvider(prompt: prompt)
        let records = InMemoryLearningRecordRepository()
        let model = TadaWordsAppModel(
            profiles: [profile],
            contentProvider: provider,
            attemptEventRepository: records,
            wordProgressRepository: records,
            clock: TestClock()
        )
        model.selectProfile(profile)

        await model.prepareQuestAndWait(.read)

        let receivedProfileIDs = await provider.receivedProfileIDs
        XCTAssertEqual(receivedProfileIDs, [profile.id])
        let session = try questSession(from: model.destination)
        XCTAssertEqual(session.profileID, profile.id)
        XCTAssertEqual(session.source, .new)
        XCTAssertEqual(session.timer.emergencyAfter, 47)
        model.showLobby()
        XCTAssertTrue(session.timer.isFinished)
    }

    func testPreparedInterfacePreferencesReachQuestSession() async throws {
        let fixture = try ModelFixture(
            wordCount: 1,
            interfacePreferences: PracticeInterfacePreferences(
                leftHandedLayoutEnabled: true
            )
        )

        await fixture.model.prepareQuestAndWait(.read)

        let session = try questSession(from: fixture.model.destination)
        XCTAssertTrue(session.interfacePreferences.leftHandedLayoutEnabled)
    }

    func testPersistedItemAdvancesUntilOneActualFinalScore() async throws {
        let fixture = try ModelFixture(wordCount: 2)
        await fixture.model.prepareQuestAndWait(.read)

        let firstSession = try questSession(from: fixture.model.destination)
        let stableQuestTransitionKey = fixture.model.transitionKey
        XCTAssertEqual(firstSession.profileID, fixture.profile.id)
        XCTAssertEqual(firstSession.currentItem, 1)
        XCTAssertEqual(firstSession.totalItems, 2)
        await fixture.model.finishItemAndWait(
            firstSession,
            summary: try TestFixture.summary(decisions: [.matched])
        )

        let secondSession = try questSession(from: fixture.model.destination)
        XCTAssertEqual(fixture.model.transitionKey, stableQuestTransitionKey)
        XCTAssertEqual(secondSession.currentItem, 2)
        XCTAssertEqual(secondSession.source, .review)
        XCTAssertEqual(secondSession.prompt.id, fixture.prompts[1].id)
        let firstAttempts = try await fixture.records.attempts(
            for: fixture.profile.id,
            wordPromptID: fixture.prompts[0].id
        )
        XCTAssertEqual(firstAttempts.count, 1)
        let firstProgress = try await fixture.records.progress(
            for: fixture.profile.id,
            wordPromptID: fixture.prompts[0].id
        )
        XCTAssertEqual(firstProgress?.firstIndependentAttemptCount, 1)
        XCTAssertEqual(firstProgress?.firstIndependentCorrectCount, 1)

        await fixture.model.finishItemAndWait(
            secondSession,
            summary: try TestFixture.summary(decisions: [.matched])
        )

        let result = try resultState(from: fixture.model.destination)
        XCTAssertTrue(firstSession.timer.isFinished)
        XCTAssertEqual(result.score.firstIndependentAttemptCount, 2)
        XCTAssertEqual(result.score.firstIndependentCorrectCount, 2)
        XCTAssertEqual(result.score.points, 100)
        XCTAssertEqual(
            result.score.stars.earned,
            [.completion, .accuracy, .personalPace]
        )
        let allAttempts = try await fixture.records.attempts(
            for: fixture.profile.id,
            wordPromptID: nil
        )
        XCTAssertEqual(Set(allAttempts.compactMap(\.questID)), [fixture.plan.id])
    }

    func testProblemNewDisplacesLowestReviewWithoutExtendingNewFirstQuest()
        async throws
    {
        let fixture = try ModelFixture(wordCount: 2)
        await fixture.model.prepareQuestAndWait(.read)

        let newSession = try questSession(from: fixture.model.destination)
        XCTAssertEqual(newSession.source, .new)
        await fixture.model.finishItemAndWait(
            newSession,
            summary: try TestFixture.summary(decisions: [.notMatched, .matched])
        )

        let result = try resultState(from: fixture.model.destination)
        XCTAssertTrue(result.score.stars.earned.contains(.completion))
        let displacedReviewAttempts = try await fixture.records.attempts(
            for: fixture.profile.id,
            wordPromptID: fixture.prompts[1].id
        )
        XCTAssertTrue(displacedReviewAttempts.isEmpty)
    }

    func testRelaunchResumesAtFirstWordWithoutTerminalCheckpoint() async throws {
        let records = PartialFailureLearningRepository(failingAppendNumber: 2)
        let dailyRepository = InMemoryDailyQuestRepository()
        let coordinator = DailyQuestCoordinator(
            repository: dailyRepository,
            timeZone: .gmt
        )
        let firstRun = try ModelFixture(
            wordCount: 1,
            records: records,
            dailyQuestCoordinator: coordinator
        )
        await firstRun.model.prepareQuestAndWait(.read)
        let firstSession = try questSession(from: firstRun.model.destination)
        await firstRun.model.finishItemAndWait(
            firstSession,
            summary: try TestFixture.summary(decisions: [.notMatched, .matched])
        )
        XCTAssertEqual(blockedReason(from: firstRun.model.destination), .storageUnavailable)
        firstRun.model.showLobby()

        let relaunched = try ModelFixture(
            wordCount: 1,
            records: records,
            dailyQuestCoordinator: coordinator
        )
        await relaunched.model.prepareQuestAndWait(.read)

        let recoveredSession = try questSession(from: relaunched.model.destination)
        XCTAssertEqual(recoveredSession.currentItem, 1)
        await relaunched.model.finishItemAndWait(
            recoveredSession,
            summary: try TestFixture.summary(decisions: [.matched])
        )
        let result = try resultState(from: relaunched.model.destination)
        XCTAssertEqual(result.score.firstIndependentAttemptCount, 1)
        XCTAssertEqual(result.score.firstIndependentCorrectCount, 0)
        let progress = try await records.progress(
            for: relaunched.profile.id,
            wordPromptID: relaunched.prompts[0].id
        )
        XCTAssertEqual(progress?.firstIndependentAttemptCount, 1)
        XCTAssertEqual(progress?.firstIndependentCorrectCount, 0)
    }

    func testRelaunchSkipsDurablyCompletedPrefix() async throws {
        let records = InMemoryLearningRecordRepository()
        let dailyRepository = InMemoryDailyQuestRepository()
        let coordinator = DailyQuestCoordinator(
            repository: dailyRepository,
            timeZone: .gmt
        )
        let firstRun = try ModelFixture(
            wordCount: 2,
            records: records,
            dailyQuestCoordinator: coordinator
        )
        await firstRun.model.prepareQuestAndWait(.read)
        let firstSession = try questSession(from: firstRun.model.destination)
        await firstRun.model.finishItemAndWait(
            firstSession,
            summary: try TestFixture.summary(decisions: [.matched])
        )
        XCTAssertEqual(
            try questSession(from: firstRun.model.destination).currentItem,
            2
        )
        firstRun.model.showLobby()

        let relaunched = try ModelFixture(
            wordCount: 2,
            records: records,
            dailyQuestCoordinator: coordinator
        )
        await relaunched.model.prepareQuestAndWait(.read)

        let recoveredSession = try questSession(from: relaunched.model.destination)
        XCTAssertEqual(recoveredSession.currentItem, 2)
        XCTAssertEqual(recoveredSession.prompt.id, relaunched.prompts[1].id)
        await relaunched.model.finishItemAndWait(
            recoveredSession,
            summary: try TestFixture.summary(decisions: [.matched])
        )
        let result = try resultState(from: relaunched.model.destination)
        XCTAssertEqual(result.score.firstIndependentAttemptCount, 2)
        XCTAssertEqual(result.score.firstIndependentCorrectCount, 2)
        let storedAttempts = try await records.attempts(
            for: relaunched.profile.id,
            wordPromptID: nil
        )
        XCTAssertEqual(storedAttempts.count, 2)
    }

    func testRelaunchRecoversLetterKeyboardFromPersistedAttemptContext()
        async throws
    {
        let records = InMemoryLearningRecordRepository()
        let dailyRepository = InMemoryDailyQuestRepository()
        let coordinator = DailyQuestCoordinator(
            repository: dailyRepository,
            timeZone: .gmt
        )
        let firstRun = try ModelFixture(
            wordCount: 2,
            mode: .write,
            records: records,
            dailyQuestCoordinator: coordinator
        )
        await firstRun.model.prepareQuestAndWait(
            .write,
            writeInputMethod: .letterKeyboard
        )
        let firstSession = try questSession(from: firstRun.model.destination)
        await firstRun.model.finishItemAndWait(
            firstSession,
            summary: try TestFixture.summary(decisions: [.matched])
        )
        firstRun.model.showLobby()

        let relaunched = try ModelFixture(
            wordCount: 2,
            mode: .write,
            records: records,
            dailyQuestCoordinator: coordinator
        )
        // A generic Recover path requests its documented handwriting
        // fallback. Durable evidence from this same quest must win.
        await relaunched.model.prepareQuestAndWait(.write)

        let recovered = try questSession(from: relaunched.model.destination)
        XCTAssertEqual(recovered.currentItem, 2)
        XCTAssertEqual(recovered.writeInputMethod, .letterKeyboard)
    }

    func testExplicitSpellChoiceOverridesRecoveredHandwritingAttemptContext()
        async throws
    {
        let records = InMemoryLearningRecordRepository()
        let dailyRepository = InMemoryDailyQuestRepository()
        let coordinator = DailyQuestCoordinator(
            repository: dailyRepository,
            timeZone: .gmt
        )
        let fixture = try ModelFixture(
            wordCount: 2,
            mode: .write,
            records: records,
            dailyQuestCoordinator: coordinator
        )
        await fixture.model.prepareQuestAndWait(
            .write,
            writeInputMethod: .handwriting
        )
        let handwritingSession = try questSession(
            from: fixture.model.destination
        )
        await fixture.model.finishItemAndWait(
            handwritingSession,
            summary: try TestFixture.summary(decisions: [.matched])
        )
        fixture.model.showLobby()

        await fixture.model.startWriteQuestAndWait(using: .letterKeyboard)

        let spellSession = try questSession(from: fixture.model.destination)
        XCTAssertEqual(spellSession.currentItem, 2)
        XCTAssertEqual(spellSession.writeInputMethod, .letterKeyboard)
    }

    func testWriteRelaunchBeforeFirstAttemptKeepsGenericHandwritingFallback()
        async throws
    {
        let records = InMemoryLearningRecordRepository()
        let dailyRepository = InMemoryDailyQuestRepository()
        let coordinator = DailyQuestCoordinator(
            repository: dailyRepository,
            timeZone: .gmt
        )
        let firstRun = try ModelFixture(
            wordCount: 1,
            mode: .write,
            records: records,
            dailyQuestCoordinator: coordinator
        )
        await firstRun.model.prepareQuestAndWait(
            .write,
            writeInputMethod: .letterKeyboard
        )
        firstRun.model.showLobby()

        let relaunched = try ModelFixture(
            wordCount: 1,
            mode: .write,
            records: records,
            dailyQuestCoordinator: coordinator
        )
        await relaunched.model.prepareQuestAndWait(.write)

        let recovered = try questSession(from: relaunched.model.destination)
        XCTAssertEqual(recovered.currentItem, 1)
        XCTAssertEqual(recovered.writeInputMethod, .handwriting)
    }

    func testRelaunchWithEveryItemCheckpointCompletesAndGrantsRewardOnce()
        async throws
    {
        let records = InMemoryLearningRecordRepository()
        let dailyRepository = FailOnceDailyQuestRepository()
        let coordinator = DailyQuestCoordinator(
            repository: dailyRepository,
            timeZone: .gmt
        )
        let firstRun = try ModelFixture(
            wordCount: 1,
            records: records,
            dailyQuestCoordinator: coordinator
        )
        await firstRun.model.prepareQuestAndWait(.read)
        let session = try questSession(from: firstRun.model.destination)
        await firstRun.model.finishItemAndWait(
            session,
            summary: try TestFixture.summary(decisions: [.matched])
        )
        XCTAssertEqual(blockedReason(from: firstRun.model.destination), .storageUnavailable)
        firstRun.model.showLobby()

        let relaunched = try ModelFixture(
            wordCount: 1,
            records: records,
            dailyQuestCoordinator: coordinator
        )
        await relaunched.model.prepareQuestAndWait(.read)

        let result = try resultState(from: relaunched.model.destination)
        XCTAssertEqual(result.runKind, .today)
        XCTAssertTrue(result.showsNewCollectible)
        XCTAssertEqual(result.score.firstIndependentAttemptCount, 1)
        let key = DailyQuestKey(
            profileID: relaunched.profile.id,
            learningMode: .read,
            localDay: LocalDay(date: TestFixture.now, timeZone: .gmt)
        )
        let state = try await dailyRepository.state(for: key)
        XCTAssertNotNil(state.todayCompletion)
        XCTAssertNotNil(state.rewardGrant)
        let recordedProposals = await dailyRepository.recordedProposals
        XCTAssertEqual(recordedProposals.count, 2)
    }

    func testPersistedTimingAndPersonalBaselineEarnThirdStar() async throws {
        let context = PaceContext(
            learningMode: .read,
            deviceClass: .phone,
            inputMethod: .speech,
            wordLength: 3
        )
        let band = PersonalPaceBand(
            context: context,
            lowerBound: ElapsedTime(seconds: 1),
            upperBound: ElapsedTime(seconds: 3),
            sampleCount: 3
        )
        let fixture = try ModelFixture(
            wordCount: 1,
            deviceClass: .phone,
            personalPaceBands: [band]
        )
        await fixture.model.prepareQuestAndWait(.read)
        let session = try questSession(from: fixture.model.destination)
        var attemptState = QuestAttemptStateMachine()
        XCTAssertTrue(attemptState.beginAttempt())
        attemptState.receive(
            RecognitionResult(decision: .matched),
            timing: AttemptTiming(
                totalResponseTime: ElapsedTime(seconds: 2.5),
                speechOnsetLatency: ElapsedTime(seconds: 2)
            )
        )
        let summary = try XCTUnwrap(attemptState.completedSummary)

        await fixture.model.finishItemAndWait(session, summary: summary)

        let result = try resultState(from: fixture.model.destination)
        XCTAssertEqual(result.score.points, 100)
        XCTAssertEqual(result.score.personalPaceAssessment, .withinPersonalBand)
        XCTAssertEqual(
            result.score.stars.earned,
            [.completion, .accuracy, .personalPace]
        )
        let savedAttempts = try await fixture.records.attempts(
            for: fixture.profile.id,
            wordPromptID: fixture.prompts[0].id
        )
        let savedAttempt = try XCTUnwrap(savedAttempts.first)
        XCTAssertEqual(savedAttempt.paceContext, context)
        XCTAssertEqual(savedAttempt.timing.speechOnsetLatency?.seconds, 2)
    }

    func testResultReplayContainsOnlyWordsMissedOnFirstIndependentTry()
        async throws
    {
        let fixture = try ModelFixture(wordCount: 2)
        await fixture.model.prepareQuestAndWait(.read)

        let correctSession = try questSession(from: fixture.model.destination)
        await fixture.model.finishItemAndWait(
            correctSession,
            summary: try TestFixture.summary(decisions: [.matched])
        )
        let missedSession = try questSession(from: fixture.model.destination)
        await fixture.model.finishItemAndWait(
            missedSession,
            summary: try TestFixture.summary(decisions: [.notMatched, .matched])
        )

        let firstResult = try resultState(from: fixture.model.destination)
        XCTAssertEqual(firstResult.replayWordCount, 1)
        XCTAssertTrue(firstResult.showsReplayAction)

        await fixture.model.replayMissedWordsAndWait()

        let replaySession = try questSession(from: fixture.model.destination)
        XCTAssertEqual(replaySession.prompt.id, missedSession.prompt.id)
        XCTAssertEqual(replaySession.totalItems, 1)
        XCTAssertNotEqual(replaySession.id, missedSession.id)

        await fixture.model.finishItemAndWait(
            replaySession,
            summary: try TestFixture.summary(decisions: [.matched])
        )
        let replayResult = try resultState(from: fixture.model.destination)
        XCTAssertEqual(replayResult.runKind, .practiceAgain)
        XCTAssertEqual(replayResult.replayWordCount, 0)
        XCTAssertFalse(replayResult.showsReplayAction)
    }

    func testPerfectQuestOffersNoReplayAndStillKeepsResultVisible() async throws {
        let fixture = try ModelFixture(wordCount: 1)
        await fixture.model.prepareQuestAndWait(.read)
        let session = try questSession(from: fixture.model.destination)
        await fixture.model.finishItemAndWait(
            session,
            summary: try TestFixture.summary(decisions: [.matched])
        )

        let result = try resultState(from: fixture.model.destination)
        XCTAssertEqual(result.replayWordCount, 0)
        XCTAssertFalse(result.showsReplayAction)

        await fixture.model.replayMissedWordsAndWait()
        _ = try resultState(from: fixture.model.destination)
    }

    func testPartialAppendFailureBlocksWithoutRewardAndRetryUsesSameEventIDs()
        async throws
    {
        let records = PartialFailureLearningRepository(failingAppendNumber: 2)
        let fixture = try ModelFixture(wordCount: 1, records: records)
        await fixture.model.prepareQuestAndWait(.read)
        let session = try questSession(from: fixture.model.destination)
        let summary = try TestFixture.summary(decisions: [.notMatched, .matched])

        await fixture.model.finishItemAndWait(session, summary: summary)

        XCTAssertEqual(
            blockedReason(from: fixture.model.destination),
            .storageUnavailable
        )
        let attemptsAfterFailure = try await records.attempts(
            for: fixture.profile.id,
            wordPromptID: session.prompt.id
        )
        XCTAssertEqual(attemptsAfterFailure.count, 1)
        let progressAfterFailure = try await records.progress(
            for: fixture.profile.id,
            wordPromptID: session.prompt.id
        )
        XCTAssertNil(progressAfterFailure)

        await fixture.model.recoverQuestAndWait(.read)

        let result = try resultState(from: fixture.model.destination)
        XCTAssertEqual(result.score.firstIndependentAttemptCount, 1)
        XCTAssertEqual(result.score.firstIndependentCorrectCount, 0)
        XCTAssertEqual(result.score.stars.earned, [.completion, .accuracy])
        let attemptsAfterRetry = try await records.attempts(
            for: fixture.profile.id,
            wordPromptID: session.prompt.id
        )
        XCTAssertEqual(attemptsAfterRetry.count, 2)
        XCTAssertEqual(Set(attemptsAfterRetry.map(\.id)).count, 2)
        let appendInvocationCount = await records.appendInvocationCount
        XCTAssertEqual(appendInvocationCount, 4)
        let progressAfterRetry = try await records.progress(
            for: fixture.profile.id,
            wordPromptID: session.prompt.id
        )
        XCTAssertEqual(progressAfterRetry?.firstIndependentAttemptCount, 1)
        XCTAssertEqual(progressAfterRetry?.firstIndependentCorrectCount, 0)
    }

    func testQuestTimerCarriesIdentityAndElapsedAcrossItemsThenRenewsForNextQuest()
        async throws
    {
        var now: TimeInterval = 0
        var createdTimers: [QuestTimerModel] = []
        let fixture = try ModelFixture(
            wordCount: 2,
            questTimerFactory: { threshold in
                let timer = QuestTimerModel(
                    emergencyAfter: threshold,
                    now: { now }
                )
                createdTimers.append(timer)
                return timer
            }
        )
        await fixture.model.prepareQuestAndWait(.read)
        let firstSession = try questSession(from: fixture.model.destination)
        XCTAssertTrue(firstSession.timer.isRunning)
        XCTAssertEqual(firstSession.timer.elapsedSeconds, 0)

        now += 92
        await fixture.model.finishItemAndWait(
            firstSession,
            summary: try TestFixture.summary(decisions: [.matched])
        )

        let secondSession = try questSession(from: fixture.model.destination)
        XCTAssertTrue(firstSession.timer === secondSession.timer)
        XCTAssertEqual(secondSession.timer.elapsedSeconds, 92, accuracy: 0.001)
        XCTAssertTrue(secondSession.timer.isEmergency)
        XCTAssertTrue(secondSession.timer.isRunning)
        XCTAssertEqual(createdTimers.count, 1)

        now += 5
        fixture.model.showLobby()
        XCTAssertFalse(firstSession.timer.isRunning)
        XCTAssertTrue(firstSession.timer.isFinished)
        XCTAssertEqual(firstSession.timer.elapsedSeconds, 97, accuracy: 0.001)
        firstSession.timer.resume()
        XCTAssertFalse(firstSession.timer.isRunning)

        await fixture.model.prepareQuestAndWait(.read)
        let nextQuestSession = try questSession(from: fixture.model.destination)
        XCTAssertFalse(firstSession.timer === nextQuestSession.timer)
        XCTAssertEqual(nextQuestSession.timer.elapsedSeconds, 0)
        XCTAssertTrue(nextQuestSession.timer.isRunning)
        XCTAssertFalse(nextQuestSession.timer.isFinished)
        XCTAssertEqual(createdTimers.count, 2)
        fixture.model.showLobby()
    }

    func testApplicationInactiveTimeDoesNotAdvanceQuestTimer() async throws {
        var now: TimeInterval = 0
        let fixture = try ModelFixture(
            wordCount: 1,
            questTimerFactory: { threshold in
                QuestTimerModel(
                    emergencyAfter: threshold,
                    now: { now }
                )
            }
        )
        await fixture.model.prepareQuestAndWait(.read)
        let session = try questSession(from: fixture.model.destination)

        now = 7
        fixture.model.setApplicationActive(false)
        XCTAssertFalse(session.timer.isRunning)
        XCTAssertEqual(session.timer.elapsedSeconds, 7, accuracy: 0.001)

        now = 107
        fixture.model.setApplicationActive(true)
        XCTAssertTrue(session.timer.isRunning)
        now = 112
        fixture.model.setApplicationActive(false)
        XCTAssertEqual(session.timer.elapsedSeconds, 12, accuracy: 0.001)
        fixture.model.showLobby()
    }

    func testStorageFailureAndRetryKeepSamePausedTimerWithoutResettingElapsed()
        async throws
    {
        var now: TimeInterval = 0
        var createdTimers: [QuestTimerModel] = []
        let records = PartialFailureLearningRepository(failingAppendNumber: 1)
        let fixture = try ModelFixture(
            wordCount: 2,
            records: records,
            questTimerFactory: { threshold in
                let timer = QuestTimerModel(
                    emergencyAfter: threshold,
                    now: { now }
                )
                createdTimers.append(timer)
                return timer
            }
        )
        await fixture.model.prepareQuestAndWait(.read)
        let firstSession = try questSession(from: fixture.model.destination)
        now += 9

        await fixture.model.finishItemAndWait(
            firstSession,
            summary: try TestFixture.summary(decisions: [.matched])
        )

        XCTAssertEqual(
            blockedReason(from: fixture.model.destination),
            .storageUnavailable
        )
        XCTAssertFalse(firstSession.timer.isRunning)
        XCTAssertFalse(firstSession.timer.isFinished)
        XCTAssertEqual(firstSession.timer.elapsedSeconds, 9, accuracy: 0.001)
        now += 100
        XCTAssertEqual(firstSession.timer.elapsedSeconds, 9, accuracy: 0.001)

        await fixture.model.recoverQuestAndWait(.read)

        let secondSession = try questSession(from: fixture.model.destination)
        XCTAssertTrue(firstSession.timer === secondSession.timer)
        XCTAssertEqual(secondSession.timer.elapsedSeconds, 9, accuracy: 0.001)
        XCTAssertTrue(secondSession.timer.isRunning)
        XCTAssertEqual(createdTimers.count, 1)
        fixture.model.showLobby()
    }

    func testRestartReusesCompletedTodayPlanAsPracticeAgainWithoutNewReward()
        async throws
    {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true
        )
        addTeardownBlock {
            try? FileManager.default.removeItem(at: directory)
        }
        let snapshotURL = directory.appendingPathComponent("daily-quests.json")
        let profile = TestFixture.profile(name: "Mia", number: 70)
        let cat = try TestFixture.prompt("cat", number: 70)
        let dog = try TestFixture.prompt("dog", number: 71)
        let firstPlan = QuestPlan(
            id: QuestID(),
            profileID: profile.id,
            configuration: .defaultRead,
            reviewWordIDs: [],
            newWordIDs: [cat.id],
            createdAt: TestFixture.now
        )
        let laterCandidate = QuestPlan(
            id: QuestID(),
            profileID: profile.id,
            configuration: .defaultRead,
            reviewWordIDs: [],
            newWordIDs: [dog.id],
            createdAt: TestFixture.now.addingTimeInterval(60)
        )
        let records = InMemoryLearningRecordRepository()
        let firstDailyRepository = LocalJSONDailyQuestRepository(
            snapshotURL: snapshotURL
        )
        let firstModel = TadaWordsAppModel(
            profiles: [profile],
            contentProvider: CatalogQuestContentProvider(
                candidate: firstPlan,
                prompts: [cat, dog]
            ),
            attemptEventRepository: records,
            wordProgressRepository: records,
            dailyQuestCoordinator: DailyQuestCoordinator(
                repository: firstDailyRepository,
                timeZone: .gmt
            ),
            clock: TestClock()
        )
        firstModel.selectProfile(profile)
        await firstModel.prepareQuestAndWait(.read)
        let todaySession = try questSession(from: firstModel.destination)
        XCTAssertEqual(todaySession.prompt.id, cat.id)
        await firstModel.finishItemAndWait(
            todaySession,
            summary: try TestFixture.summary(decisions: [.matched])
        )
        let todayResult = try resultState(from: firstModel.destination)
        XCTAssertEqual(todayResult.runKind, .today)
        XCTAssertNotNil(todayResult.rewardGrant)
        XCTAssertTrue(todayResult.showsNewCollectible)
        XCTAssertEqual(
            firstModel.todayRouteStatus(for: .read).action,
            .practiceAgain
        )
        XCTAssertEqual(
            firstModel.todayRouteStatus(for: .read).completedPoints,
            todayResult.points
        )

        let restartedDailyRepository = LocalJSONDailyQuestRepository(
            snapshotURL: snapshotURL
        )
        let restartedCoordinator = DailyQuestCoordinator(
            repository: restartedDailyRepository,
            timeZone: .gmt
        )
        let restartedModel = TadaWordsAppModel(
            profiles: [profile],
            contentProvider: CatalogQuestContentProvider(
                candidate: laterCandidate,
                prompts: [cat, dog]
            ),
            attemptEventRepository: records,
            wordProgressRepository: records,
            dailyQuestCoordinator: restartedCoordinator,
            clock: TestClock()
        )
        restartedModel.selectProfile(profile)
        await restartedModel.prepareQuestAndWait(.read)
        let practiceSession = try questSession(from: restartedModel.destination)
        XCTAssertEqual(practiceSession.prompt.id, cat.id)
        XCTAssertNotEqual(practiceSession.prompt.id, dog.id)
        XCTAssertNotEqual(practiceSession.id, firstPlan.id)
        await restartedModel.finishItemAndWait(
            practiceSession,
            summary: try TestFixture.summary(decisions: [.matched])
        )
        let practiceResult = try resultState(from: restartedModel.destination)
        XCTAssertEqual(practiceResult.runKind, .practiceAgain)
        XCTAssertNil(practiceResult.rewardGrant)
        XCTAssertFalse(practiceResult.showsNewCollectible)

        let key = DailyQuestKey(
            profileID: profile.id,
            learningMode: .read,
            localDay: LocalDay(date: TestFixture.now, timeZone: .gmt)
        )
        let completions = try await restartedDailyRepository.completions(
            for: key
        )
        XCTAssertEqual(completions.map(\.runKind), [.today, .practiceAgain])
        let persistedState = try await restartedDailyRepository.state(for: key)
        XCTAssertEqual(persistedState.plan?.questPlan, firstPlan)
        XCTAssertEqual(
            persistedState.rewardGrant?.id,
            todayResult.rewardGrant?.id
        )
    }

    func testCompletionStorageFailureBlocksThenRetryUsesSameIDsAndGrantsOnce()
        async throws
    {
        let dailyRepository = FailOnceDailyQuestRepository()
        let records = InMemoryLearningRecordRepository()
        let fixture = try ModelFixture(
            wordCount: 1,
            records: records,
            dailyQuestCoordinator: DailyQuestCoordinator(
                repository: dailyRepository,
                timeZone: .gmt
            )
        )
        await fixture.model.prepareQuestAndWait(.read)
        let session = try questSession(from: fixture.model.destination)
        await fixture.model.finishItemAndWait(
            session,
            summary: try TestFixture.summary(decisions: [.matched])
        )

        XCTAssertEqual(
            blockedReason(from: fixture.model.destination),
            .storageUnavailable
        )
        let attemptsBeforeRetry = try await records.attempts(
            for: fixture.profile.id,
            wordPromptID: session.prompt.id
        )
        XCTAssertEqual(attemptsBeforeRetry.count, 1)
        let stateBeforeRetry = try await dailyRepository.state(
            for: DailyQuestKey(
                profileID: fixture.profile.id,
                learningMode: .read,
                localDay: LocalDay(date: TestFixture.now, timeZone: .gmt)
            )
        )
        XCTAssertNil(stateBeforeRetry.todayCompletion)
        XCTAssertNil(stateBeforeRetry.rewardGrant)

        await fixture.model.recoverQuestAndWait(.read)

        let result = try resultState(from: fixture.model.destination)
        XCTAssertEqual(result.runKind, .today)
        XCTAssertNotNil(result.rewardGrant)
        XCTAssertTrue(result.showsNewCollectible)
        let recorded = await dailyRepository.recordedProposals
        XCTAssertEqual(recorded.count, 2)
        XCTAssertEqual(recorded[0].completionID, recorded[1].completionID)
        XCTAssertEqual(recorded[0].rewardGrantID, recorded[1].rewardGrantID)
        let attemptsAfterRetry = try await records.attempts(
            for: fixture.profile.id,
            wordPromptID: session.prompt.id
        )
        XCTAssertEqual(attemptsAfterRetry.count, 1)
    }

    private func questSession(from destination: AppDestination) throws -> QuestSession {
        guard case .quest(let session) = destination else {
            throw TestFailure.expectedQuest
        }
        return session
    }

    private func resultState(from destination: AppDestination) throws -> QuestResultViewState {
        guard case .result(let result) = destination else {
            throw TestFailure.expectedResult
        }
        return result
    }

    private func blockedReason(from destination: AppDestination) -> QuestBlockReason? {
        guard case .blocked(_, let reason) = destination else { return nil }
        return reason
    }
}

private actor FailingChildSessionRepository: ChildSessionRepository {
    func lastSelectedProfileID() async throws -> ProfileID? { nil }

    func saveLastSelectedProfileID(_ profileID: ProfileID) async throws {
        _ = profileID
        throw TestFailure.injectedStorageFailure
    }

    func clearLastSelectedProfileID() async throws {}
}

private actor FailingChildProfileCreator: ChildProfileCreating {
    func createProfile(
        displayName: String,
        ageYears: Int,
        existingProfiles: [KidProfile]
    ) async throws -> KidProfile {
        _ = displayName
        _ = ageYears
        _ = existingProfiles
        throw ChildProfileCreationError.profilePersistenceFailed
    }
}

private struct ModelFixture {
    let profile: KidProfile
    let prompts: [WordPrompt]
    let plan: QuestPlan
    let records: any AttemptEventRepository & WordProgressRepository
    let model: TadaWordsAppModel

    @MainActor
    init(
        wordCount: Int,
        mode: LearningMode = .read,
        records: any AttemptEventRepository & WordProgressRepository =
            InMemoryLearningRecordRepository(),
        dailyQuestCoordinator: DailyQuestCoordinator = DailyQuestCoordinator(
            repository: InMemoryDailyQuestRepository(),
            timeZone: .gmt
        ),
        deviceClass: DeviceClass = .tablet,
        personalPaceBands: [PersonalPaceBand] = [],
        interfacePreferences: PracticeInterfacePreferences = .default,
        questTimerFactory: @escaping (TimeInterval) -> QuestTimerModel = {
            QuestTimerModel(emergencyAfter: $0)
        }
    ) throws {
        profile = TestFixture.profile(name: "Mia", number: 1)
        let words = ["cat", "dog", "fox", "hen", "pig"]
        prompts = try (1...wordCount).map { number in
            try TestFixture.prompt(
                words[number - 1],
                number: number,
                mode: mode
            )
        }
        plan = QuestPlan(
            id: TestFixture.questID,
            profileID: profile.id,
            configuration: mode == .read ? .defaultRead : .defaultWrite,
            reviewWordIDs: wordCount > 1 ? [prompts[1].id] : [],
            newWordIDs: [prompts[0].id],
            createdAt: TestFixture.now
        )
        self.records = records
        model = TadaWordsAppModel(
            profiles: [profile],
            contentProvider: StaticQuestContentProvider(
                preparedQuest: PreparedQuest(
                    plan: plan,
                    orderedPrompts: prompts,
                    emergencyAfter: 91,
                    deviceClass: deviceClass,
                    personalPaceBands: personalPaceBands,
                    interfacePreferences: interfacePreferences
                )
            ),
            attemptEventRepository: records,
            wordProgressRepository: records,
            dailyQuestCoordinator: dailyQuestCoordinator,
            clock: TestClock(),
            questTimerFactory: questTimerFactory
        )
        model.selectProfile(profile)
    }
}

private struct StaticQuestContentProvider: QuestContentProviding {
    let preparedQuest: PreparedQuest

    func availability(for mode: LearningMode, profile: KidProfile) -> QuestAvailability {
        _ = mode
        _ = profile
        return .available
    }

    func prepareQuest(
        for mode: LearningMode,
        profile: KidProfile
    ) async throws -> PreparedQuest {
        _ = mode
        _ = profile
        return preparedQuest
    }

    func prompts(
        for plan: QuestPlan,
        profile: KidProfile
    ) async throws -> [WordPrompt] {
        guard plan.profileID == profile.id else {
            throw TestFailure.injectedStorageFailure
        }
        let promptsByID = Dictionary(
            uniqueKeysWithValues: preparedQuest.orderedPrompts.map { ($0.id, $0) }
        )
        return try plan.orderedItems.map { item in
            guard let prompt = promptsByID[item.wordPromptID] else {
                throw TestFailure.injectedStorageFailure
            }
            return prompt
        }
    }
}

private actor ProfileRecordingContentProvider: QuestContentProviding {
    let prompt: WordPrompt
    private(set) var receivedProfileIDs: [ProfileID] = []

    init(prompt: WordPrompt) {
        self.prompt = prompt
    }

    nonisolated func availability(
        for mode: LearningMode,
        profile: KidProfile
    ) -> QuestAvailability {
        _ = mode
        _ = profile
        return .available
    }

    func prepareQuest(
        for mode: LearningMode,
        profile: KidProfile
    ) async throws -> PreparedQuest {
        receivedProfileIDs.append(profile.id)
        let plan = QuestPlan(
            id: TestFixture.questID,
            profileID: profile.id,
            configuration: mode == .read ? .defaultRead : .defaultWrite,
            reviewWordIDs: [],
            newWordIDs: [prompt.id],
            createdAt: TestFixture.now
        )
        return PreparedQuest(
            plan: plan,
            orderedPrompts: [prompt],
            emergencyAfter: 47
        )
    }

    func prompts(
        for plan: QuestPlan,
        profile: KidProfile
    ) async throws -> [WordPrompt] {
        guard plan.profileID == profile.id,
            plan.orderedItems.map(\.wordPromptID) == [prompt.id]
        else {
            throw TestFailure.injectedStorageFailure
        }
        return [prompt]
    }
}

private struct CatalogQuestContentProvider: QuestContentProviding {
    let candidate: QuestPlan
    let promptsByID: [WordPromptID: WordPrompt]

    init(candidate: QuestPlan, prompts: [WordPrompt]) {
        self.candidate = candidate
        promptsByID = Dictionary(
            uniqueKeysWithValues: prompts.map { ($0.id, $0) }
        )
    }

    func availability(
        for mode: LearningMode,
        profile: KidProfile
    ) -> QuestAvailability {
        _ = mode
        _ = profile
        return .available
    }

    func prepareQuest(
        for mode: LearningMode,
        profile: KidProfile
    ) async throws -> PreparedQuest {
        guard candidate.profileID == profile.id,
            candidate.configuration.learningMode == mode
        else {
            throw TestFailure.injectedStorageFailure
        }
        return PreparedQuest(
            plan: candidate,
            orderedPrompts: try await prompts(for: candidate, profile: profile),
            emergencyAfter: 60
        )
    }

    func prompts(
        for plan: QuestPlan,
        profile: KidProfile
    ) async throws -> [WordPrompt] {
        guard plan.profileID == profile.id else {
            throw TestFailure.injectedStorageFailure
        }
        return try plan.orderedItems.map { item in
            guard let prompt = promptsByID[item.wordPromptID] else {
                throw TestFailure.injectedStorageFailure
            }
            return prompt
        }
    }
}

private actor FailOnceDailyQuestRepository: DailyQuestRepository {
    struct Proposal: Sendable {
        let completionID: DailyQuestCompletionID
        let rewardGrantID: RewardGrantID?
    }

    private let underlying = InMemoryDailyQuestRepository()
    private var hasFailed = false
    private(set) var recordedProposals: [Proposal] = []

    func state(for key: DailyQuestKey) async throws -> DailyQuestState {
        try await underlying.state(for: key)
    }

    func createPlanIfAbsent(
        _ plan: DailyQuestPlan
    ) async throws -> DailyQuestPlan {
        try await underlying.createPlanIfAbsent(plan)
    }

    func completions(
        for key: DailyQuestKey
    ) async throws -> [DailyQuestCompletion] {
        try await underlying.completions(for: key)
    }

    func completions(
        for profileID: ProfileID,
        in month: LocalMonth
    ) async throws -> [DailyQuestCompletion] {
        try await underlying.completions(for: profileID, in: month)
    }

    func recordCompletion(
        _ completion: DailyQuestCompletion,
        proposedRewardGrant: RewardGrant?
    ) async throws -> DailyQuestCompletionWriteResult {
        recordedProposals.append(
            Proposal(
                completionID: completion.id,
                rewardGrantID: proposedRewardGrant?.id
            )
        )
        if !hasFailed {
            hasFailed = true
            throw TestFailure.injectedStorageFailure
        }
        return try await underlying.recordCompletion(
            completion,
            proposedRewardGrant: proposedRewardGrant
        )
    }
}

private actor PartialFailureLearningRepository: AttemptEventRepository,
    WordProgressRepository
{
    private let failingAppendNumber: Int
    private var didFail = false
    private var attemptsByID: [AttemptID: AttemptEvent] = [:]
    private var progressByWordID: [WordPromptID: WordProgress] = [:]
    private(set) var appendInvocationCount = 0

    init(failingAppendNumber: Int) {
        self.failingAppendNumber = failingAppendNumber
    }

    func append(_ event: AttemptEvent) async throws {
        appendInvocationCount += 1
        if !didFail, appendInvocationCount == failingAppendNumber {
            didFail = true
            throw TestFailure.injectedStorageFailure
        }
        if let existing = attemptsByID[event.id] {
            XCTAssertEqual(existing, event)
        } else {
            attemptsByID[event.id] = event
        }
    }

    func append(_ correction: AttemptCorrectionEvent) async throws {
        _ = correction
    }

    func attempts(
        for profileID: ProfileID,
        wordPromptID: WordPromptID?
    ) async throws -> [AttemptEvent] {
        attemptsByID.values
            .filter { event in
                event.profileID == profileID
                    && (wordPromptID == nil || event.wordPromptID == wordPromptID)
            }
            .sorted { $0.occurredAt < $1.occurredAt }
    }

    func corrections(for attemptID: AttemptID) async throws -> [AttemptCorrectionEvent] {
        _ = attemptID
        return []
    }

    func progress(
        for profileID: ProfileID,
        wordPromptID: WordPromptID
    ) async throws -> WordProgress? {
        guard let progress = progressByWordID[wordPromptID] else { return nil }
        return progress.profileID == profileID ? progress : nil
    }

    func save(_ progress: WordProgress) async throws {
        progressByWordID[progress.wordPromptID] = progress
    }
}

private enum TestFailure: Error {
    case expectedLoading
    case expectedQuest
    case expectedResult
    case injectedStorageFailure
}

private struct FailingAudioPromptService: AudioPromptService {
    func play(_ prompt: WordPrompt, for profileID: ProfileID) async throws {
        _ = prompt
        _ = profileID
        throw TestFailure.injectedStorageFailure
    }
}
