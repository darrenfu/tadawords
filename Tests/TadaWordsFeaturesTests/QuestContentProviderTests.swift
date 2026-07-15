import Foundation
import TadaWordsContent
import TadaWordsDomain
import XCTest

@testable import TadaWordsFeatures

final class QuestContentProviderTests: XCTestCase {
    func testGuardianEnteredPoolBecomesDefaultOrderedDailyNewWords() async throws {
        let fixture = ProviderFixture()
        _ = try await ManualWordPoolImporter(repository: fixture.wordPool).importBatch(
            "cat dog fox hen pig cow",
            profileID: fixture.profile.id,
            learningMode: .read,
            addedAt: fixture.clock.now
        )

        let prepared = try await fixture.provider.prepareQuest(
            for: .read,
            profile: fixture.profile
        )

        XCTAssertEqual(
            prepared.orderedPrompts.map(\.normalizedText),
            ["cat", "dog", "fox", "hen", "pig"]
        )
        XCTAssertEqual(
            prepared.plan.newWordIDs,
            prepared.orderedPrompts.map(\.id)
        )
        XCTAssertTrue(prepared.plan.reviewWordIDs.isEmpty)
        XCTAssertEqual(prepared.plan.configuration, .defaultRead)
        XCTAssertEqual(prepared.emergencyAfter, 180)
    }

    func testPreparedQuestCarriesProfilesInterfacePreferences() async throws {
        let fixture = ProviderFixture()
        _ = try await ManualWordPoolImporter(repository: fixture.wordPool).importBatch(
            "look",
            profileID: fixture.profile.id,
            learningMode: .write,
            addedAt: fixture.clock.now
        )
        try await fixture.settings.save(
            ProfilePracticeSettings(
                profileID: fixture.profile.id,
                interface: PracticeInterfacePreferences(
                    leftHandedLayoutEnabled: true
                )
            )
        )

        let prepared = try await fixture.provider.prepareQuest(
            for: .write,
            profile: fixture.profile
        )

        XCTAssertTrue(prepared.interfacePreferences.leftHandedLayoutEnabled)
    }

    func testEmptyPoolProducesTypedNoPromptFailure() async {
        let fixture = ProviderFixture()

        do {
            _ = try await fixture.provider.prepareQuest(
                for: .read,
                profile: fixture.profile
            )
            XCTFail("Expected an empty-pool failure")
        } catch let error as QuestContentError {
            XCTAssertEqual(error, .emptyPool)
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    func testStartedPoolWithoutDueReviewReportsCaughtUp() async throws {
        let fixture = ProviderFixture()
        _ = try await ManualWordPoolImporter(repository: fixture.wordPool).importBatch(
            "cat",
            profileID: fixture.profile.id,
            learningMode: .read,
            addedAt: fixture.clock.now.addingTimeInterval(-172_800)
        )
        let entries = try await fixture.wordPool.entries(
            for: fixture.profile.id,
            learningMode: .read,
            includingInactive: false
        )
        let entry = try XCTUnwrap(entries.first)
        try await fixture.records.save(
            fixture.progress(
                for: entry.prompt,
                nextReviewAt: fixture.clock.now.addingTimeInterval(86_400)
            )
        )

        do {
            _ = try await fixture.provider.prepareQuest(
                for: .read,
                profile: fixture.profile
            )
            XCTFail("Expected caught-up review state")
        } catch let error as QuestContentError {
            XCTAssertEqual(error, .noReviewDue)
        }
    }

    func testWeakNotYetDueWordFillsReviewAndIsNotReclassifiedAsNew() async throws {
        let fixture = ProviderFixture()
        _ = try await ManualWordPoolImporter(repository: fixture.wordPool).importBatch(
            "cat",
            profileID: fixture.profile.id,
            learningMode: .read,
            addedAt: fixture.clock.now
        )
        let entries = try await fixture.wordPool.entries(
            for: fixture.profile.id,
            learningMode: .read,
            includingInactive: false
        )
        let entry = try XCTUnwrap(entries.first)
        try await fixture.records.save(
            fixture.progress(
                for: entry.prompt,
                nextReviewAt: fixture.clock.now.addingTimeInterval(86_400),
                attemptCount: 1,
                correctCount: 0
            )
        )

        let prepared = try await fixture.provider.prepareQuest(
            for: .read,
            profile: fixture.profile
        )

        XCTAssertEqual(prepared.plan.reviewWordIDs, [entry.prompt.id])
        XCTAssertTrue(prepared.plan.newWordIDs.isEmpty)
    }

    func testNewWordsPrecedeDueReviewAndStartedFutureWordsAreExcluded() async throws {
        let fixture = ProviderFixture()
        _ = try await ManualWordPoolImporter(repository: fixture.wordPool).importBatch(
            "cat dog fox",
            profileID: fixture.profile.id,
            learningMode: .read,
            addedAt: fixture.clock.now.addingTimeInterval(-172_800)
        )
        let entries = try await fixture.wordPool.entries(
            for: fixture.profile.id,
            learningMode: .read,
            includingInactive: false
        )
        let dueEntry = entries[0]
        let futureEntry = entries[1]
        let newEntry = entries[2]
        try await fixture.records.save(
            fixture.progress(
                for: dueEntry.prompt,
                nextReviewAt: fixture.clock.now.addingTimeInterval(-60)
            )
        )
        try await fixture.records.save(
            fixture.progress(
                for: futureEntry.prompt,
                nextReviewAt: fixture.clock.now.addingTimeInterval(86_400)
            )
        )

        let prepared = try await fixture.provider.prepareQuest(
            for: .read,
            profile: fixture.profile
        )

        XCTAssertEqual(prepared.plan.newWordIDs, [newEntry.prompt.id])
        XCTAssertEqual(prepared.plan.reviewWordIDs, [dueEntry.prompt.id])
        XCTAssertEqual(
            prepared.orderedPrompts.map(\.id),
            [newEntry.prompt.id, dueEntry.prompt.id]
        )
        XCTAssertFalse(prepared.orderedPrompts.contains { $0.id == futureEntry.prompt.id })
    }

    func testWriteDefaultsSelectFiveNewThenFiveDueReviewWords() async throws {
        let fixture = ProviderFixture()
        _ = try await ManualWordPoolImporter(repository: fixture.wordPool).importBatch(
            "look play jump stop run big red cat dog sun",
            profileID: fixture.profile.id,
            learningMode: .write,
            addedAt: fixture.clock.now
        )
        let entries = try await fixture.wordPool.entries(
            for: fixture.profile.id,
            learningMode: .write,
            includingInactive: false
        )
        for entry in entries.prefix(5) {
            try await fixture.records.save(
                fixture.progress(
                    for: entry.prompt,
                    nextReviewAt: fixture.clock.now.addingTimeInterval(-60)
                )
            )
        }

        let prepared = try await fixture.provider.prepareQuest(
            for: .write,
            profile: fixture.profile
        )

        XCTAssertEqual(prepared.plan.configuration, .defaultWrite)
        XCTAssertEqual(prepared.plan.newWordIDs, entries.suffix(5).map(\.prompt.id))
        XCTAssertEqual(prepared.plan.reviewWordIDs, entries.prefix(5).map(\.prompt.id))
        XCTAssertEqual(
            prepared.orderedPrompts.map(\.id),
            entries.suffix(5).map(\.prompt.id) + entries.prefix(5).map(\.prompt.id)
        )
    }

    func testDueReviewUsesLowestPredictedRecallBeforeHigherErrorRate() async throws {
        let fixture = ProviderFixture()
        _ = try await ManualWordPoolImporter(repository: fixture.wordPool).importBatch(
            "cat dog",
            profileID: fixture.profile.id,
            learningMode: .read,
            addedAt: fixture.clock.now
        )
        let entries = try await fixture.wordPool.entries(
            for: fixture.profile.id,
            learningMode: .read,
            includingInactive: false
        )
        let dueAt = fixture.clock.now.addingTimeInterval(-60)
        try await fixture.records.save(
            fixture.progress(
                for: entries[0].prompt,
                nextReviewAt: dueAt,
                attemptCount: 4,
                correctCount: 0,
                stabilityDays: 10,
                elapsedSinceLastAttemptDays: 1
            )
        )
        try await fixture.records.save(
            fixture.progress(
                for: entries[1].prompt,
                nextReviewAt: dueAt,
                attemptCount: 4,
                correctCount: 4,
                stabilityDays: 1,
                elapsedSinceLastAttemptDays: 2
            )
        )

        let prepared = try await fixture.provider.prepareQuest(
            for: .read,
            profile: fixture.profile
        )

        XCTAssertEqual(
            prepared.plan.reviewWordIDs,
            [entries[1].prompt.id, entries[0].prompt.id]
        )
    }

    func testPersonalPaceBandsUseOnlyMatchingProfileAndKeepDevicesSeparate()
        async throws
    {
        let fixture = ProviderFixture()
        _ = try await ManualWordPoolImporter(repository: fixture.wordPool).importBatch(
            "cat",
            profileID: fixture.profile.id,
            learningMode: .read,
            addedAt: fixture.clock.now
        )
        let entries = try await fixture.wordPool.entries(
            for: fixture.profile.id,
            learningMode: .read,
            includingInactive: false
        )
        let prompt = try XCTUnwrap(entries.first?.prompt)
        let tabletContext = prompt.paceContext(deviceClass: .tablet)
        let phoneContext = prompt.paceContext(deviceClass: .phone)
        for (index, context)
            in ([tabletContext, phoneContext].flatMap { context in
                Array(repeating: context, count: 3)
            }).enumerated()
        {
            let elapsed = context.deviceClass == .tablet ? 2.0 : 4.0
            try await fixture.records.append(
                AttemptEvent(
                    profileID: fixture.profile.id,
                    wordPromptID: prompt.id,
                    learningMode: .read,
                    evidence: .firstIndependentAttempt,
                    outcome: .correct,
                    timing: AttemptTiming(
                        totalResponseTime: ElapsedTime(seconds: elapsed),
                        speechOnsetLatency: ElapsedTime(seconds: elapsed)
                    ),
                    occurredAt: fixture.clock.now.addingTimeInterval(
                        Double(index - 10)
                    ),
                    paceContext: context
                )
            )
        }
        try await fixture.records.append(
            AttemptEvent(
                profileID: TestFixture.profile(name: "Leo", number: 2).id,
                wordPromptID: prompt.id,
                learningMode: .read,
                evidence: .firstIndependentAttempt,
                outcome: .correct,
                timing: AttemptTiming(
                    speechOnsetLatency: ElapsedTime(seconds: 20)
                ),
                occurredAt: fixture.clock.now,
                paceContext: tabletContext
            )
        )

        let prepared = try await fixture.provider.prepareQuest(
            for: .read,
            profile: fixture.profile
        )

        XCTAssertEqual(prepared.deviceClass, .tablet)
        XCTAssertEqual(prepared.personalPaceBands.count, 2)
        XCTAssertEqual(
            Set(prepared.personalPaceBands.map(\.context)),
            [tabletContext, phoneContext]
        )
        XCTAssertTrue(
            prepared.personalPaceBands.allSatisfy { $0.sampleCount == 3 }
        )
    }

    func testDueReviewUsesErrorPaceReplayAndHelpSignalsFromProgress() async throws {
        let fixture = ProviderFixture()
        _ = try await ManualWordPoolImporter(repository: fixture.wordPool).importBatch(
            "cat dog fox hen",
            profileID: fixture.profile.id,
            learningMode: .read,
            addedAt: fixture.clock.now
        )
        let entries = try await fixture.wordPool.entries(
            for: fixture.profile.id,
            learningMode: .read,
            includingInactive: false
        )
        let dueAt = fixture.clock.now.addingTimeInterval(-60)
        try await fixture.records.save(
            fixture.progress(
                for: entries[0].prompt,
                nextReviewAt: dueAt,
                attemptCount: 4,
                correctCount: 4,
                meanResponseSeconds: 2,
                helpCount: 8
            )
        )
        try await fixture.records.save(
            fixture.progress(
                for: entries[1].prompt,
                nextReviewAt: dueAt,
                attemptCount: 4,
                correctCount: 4,
                meanResponseSeconds: 2,
                replayCount: 8
            )
        )
        try await fixture.records.save(
            fixture.progress(
                for: entries[2].prompt,
                nextReviewAt: dueAt,
                attemptCount: 4,
                correctCount: 4,
                meanResponseSeconds: 8
            )
        )
        try await fixture.records.save(
            fixture.progress(
                for: entries[3].prompt,
                nextReviewAt: dueAt,
                attemptCount: 4,
                correctCount: 1,
                meanResponseSeconds: 2
            )
        )
        try await fixture.settings.save(
            ProfilePracticeSettings(
                profileID: fixture.profile.id,
                read: LearningRouteSettings(
                    newWordLimit: 0,
                    reviewWordLimit: 3,
                    contentOrder: .reviewThenNew,
                    emergencyAfterSeconds: 180
                )
            )
        )

        let prepared = try await fixture.provider.prepareQuest(
            for: .read,
            profile: fixture.profile
        )

        XCTAssertEqual(
            prepared.plan.reviewWordIDs,
            [entries[3], entries[2], entries[1]].map(\.prompt.id)
        )
        XCTAssertEqual(
            prepared.plan.deferredReviewWordIDs,
            [entries[0].prompt.id]
        )
    }

    func testDemoSeedsEverySelectedProfileIndependently() async throws {
        let wordPool = InMemoryWordPoolRepository()
        let records = InMemoryLearningRecordRepository()
        let settings = InMemoryPracticeSettingsRepository()
        let clock = TestClock()
        let provider = DemoQuestContentProvider(
            wordPoolRepository: wordPool,
            wordProgressRepository: records,
            practiceSettingsRepository: settings,
            attemptEventRepository: records,
            deviceClass: .tablet,
            clock: clock,
            timeZone: TestFixture.utc
        )
        let firstProfile = TestFixture.profile(name: "Mia", number: 1)
        let secondProfile = TestFixture.profile(name: "Leo", number: 2)

        let first = try await provider.prepareQuest(for: .read, profile: firstProfile)
        let second = try await provider.prepareQuest(for: .read, profile: secondProfile)

        XCTAssertEqual(first.orderedPrompts.count, 5)
        XCTAssertEqual(second.orderedPrompts.count, 5)
        XCTAssertEqual(
            first.orderedPrompts.map(\.normalizedText),
            second.orderedPrompts.map(\.normalizedText)
        )
        let secondEntries = try await wordPool.entries(
            for: secondProfile.id,
            learningMode: .read,
            includingInactive: false
        )
        XCTAssertEqual(secondEntries.count, 5)
        let secondSettings = try await settings.settings(for: secondProfile.id)
        XCTAssertEqual(
            secondSettings,
            .defaults(for: secondProfile.id)
        )
    }

    func testCustomProfileSettingsDriveLimitsOrderAndEmergencyThreshold() async throws {
        let fixture = ProviderFixture()
        _ = try await ManualWordPoolImporter(repository: fixture.wordPool).importBatch(
            "cat dog fox hen pig cow",
            profileID: fixture.profile.id,
            learningMode: .read,
            addedAt: fixture.clock.now
        )
        let entries = try await fixture.wordPool.entries(
            for: fixture.profile.id,
            learningMode: .read,
            includingInactive: false
        )
        for entry in entries.prefix(3) {
            try await fixture.records.save(
                fixture.progress(
                    for: entry.prompt,
                    nextReviewAt: fixture.clock.now.addingTimeInterval(-60)
                )
            )
        }
        let customRoute = LearningRouteSettings(
            newWordLimit: 2,
            reviewWordLimit: 1,
            contentOrder: .reviewThenNew,
            emergencyAfterSeconds: 75
        )
        try await fixture.settings.save(
            ProfilePracticeSettings(
                profileID: fixture.profile.id,
                read: customRoute
            )
        )

        let prepared = try await fixture.provider.prepareQuest(
            for: .read,
            profile: fixture.profile
        )

        XCTAssertEqual(
            prepared.plan.configuration,
            QuestConfiguration(
                learningMode: .read,
                newWordLimit: 2,
                reviewWordLimit: 1,
                attentionBudget: 3,
                contentOrder: .reviewThenNew
            )
        )
        XCTAssertEqual(prepared.plan.reviewWordIDs, [entries[0].prompt.id])
        XCTAssertEqual(
            prepared.plan.deferredReviewWordIDs,
            entries[1...2].map(\.prompt.id)
        )
        XCTAssertEqual(
            prepared.plan.newWordIDs,
            entries[3...4].map(\.prompt.id)
        )
        XCTAssertEqual(
            prepared.orderedPrompts.map(\.id),
            [entries[0].prompt.id] + entries[3...4].map(\.prompt.id)
        )
        XCTAssertEqual(prepared.emergencyAfter, 75)
    }

    func testZeroReviewLimitDefersDueWordsAndKeepsConfiguredNewCapacity() async throws {
        let fixture = ProviderFixture()
        _ = try await ManualWordPoolImporter(repository: fixture.wordPool).importBatch(
            "cat dog fox hen",
            profileID: fixture.profile.id,
            learningMode: .read,
            addedAt: fixture.clock.now
        )
        let entries = try await fixture.wordPool.entries(
            for: fixture.profile.id,
            learningMode: .read,
            includingInactive: false
        )
        for entry in entries.prefix(2) {
            try await fixture.records.save(
                fixture.progress(
                    for: entry.prompt,
                    nextReviewAt: fixture.clock.now.addingTimeInterval(-60)
                )
            )
        }
        try await fixture.settings.save(
            ProfilePracticeSettings(
                profileID: fixture.profile.id,
                read: LearningRouteSettings(
                    newWordLimit: 2,
                    reviewWordLimit: 0,
                    contentOrder: .newThenReview,
                    emergencyAfterSeconds: 60
                )
            )
        )

        let prepared = try await fixture.provider.prepareQuest(
            for: .read,
            profile: fixture.profile
        )

        XCTAssertTrue(prepared.plan.reviewWordIDs.isEmpty)
        XCTAssertEqual(
            prepared.plan.deferredReviewWordIDs,
            entries.prefix(2).map(\.prompt.id)
        )
        XCTAssertEqual(
            prepared.plan.newWordIDs,
            entries.suffix(2).map(\.prompt.id)
        )
        XCTAssertEqual(
            prepared.orderedPrompts.map(\.id),
            entries.suffix(2).map(\.prompt.id)
        )
    }

    func testSharedProviderLoadsSettingsForEachProfileIndependently() async throws {
        let firstProfile = TestFixture.profile(name: "Mia", number: 1)
        let secondProfile = TestFixture.profile(name: "Leo", number: 2)
        let clock = TestClock()
        let wordPool = InMemoryWordPoolRepository()
        let records = InMemoryLearningRecordRepository()
        let settings = InMemoryPracticeSettingsRepository()
        let provider = RepositoryBackedQuestContentProvider(
            wordPoolRepository: wordPool,
            wordProgressRepository: records,
            practiceSettingsRepository: settings,
            clock: clock,
            timeZone: TestFixture.utc
        )
        for profile in [firstProfile, secondProfile] {
            _ = try await ManualWordPoolImporter(repository: wordPool).importBatch(
                "cat dog fox hen",
                profileID: profile.id,
                learningMode: .read,
                addedAt: clock.now
            )
        }
        try await settings.save(
            ProfilePracticeSettings(
                profileID: firstProfile.id,
                read: LearningRouteSettings(
                    newWordLimit: 1,
                    reviewWordLimit: 0,
                    contentOrder: .newThenReview,
                    emergencyAfterSeconds: 60
                )
            )
        )
        try await settings.save(
            ProfilePracticeSettings(
                profileID: secondProfile.id,
                read: LearningRouteSettings(
                    newWordLimit: 3,
                    reviewWordLimit: 0,
                    contentOrder: .newThenReview,
                    emergencyAfterSeconds: 120
                )
            )
        )

        let firstPrepared = try await provider.prepareQuest(
            for: .read,
            profile: firstProfile
        )
        let secondPrepared = try await provider.prepareQuest(
            for: .read,
            profile: secondProfile
        )

        XCTAssertEqual(firstPrepared.orderedPrompts.count, 1)
        XCTAssertEqual(firstPrepared.emergencyAfter, 60)
        XCTAssertEqual(secondPrepared.orderedPrompts.count, 3)
        XCTAssertEqual(secondPrepared.emergencyAfter, 120)
    }
}

private struct ProviderFixture {
    let profile = TestFixture.profile(name: "Mia", number: 1)
    let clock = TestClock()
    let wordPool = InMemoryWordPoolRepository()
    let records = InMemoryLearningRecordRepository()
    let settings = InMemoryPracticeSettingsRepository()

    var provider: RepositoryBackedQuestContentProvider {
        RepositoryBackedQuestContentProvider(
            wordPoolRepository: wordPool,
            wordProgressRepository: records,
            practiceSettingsRepository: settings,
            attemptEventRepository: records,
            deviceClass: .tablet,
            clock: clock,
            timeZone: TestFixture.utc
        )
    }

    func progress(
        for prompt: WordPrompt,
        nextReviewAt: Date,
        attemptCount: Int = 1,
        correctCount: Int = 1,
        meanResponseSeconds: TimeInterval? = nil,
        replayCount: Int = 0,
        helpCount: Int = 0,
        uncertainCount: Int = 0,
        stabilityDays: Double = 1,
        elapsedSinceLastAttemptDays: Double = 1
    ) -> WordProgress {
        let timedAttemptCount = meanResponseSeconds == nil ? 0 : attemptCount
        return WordProgress(
            profileID: profile.id,
            wordPromptID: prompt.id,
            learningMode: prompt.learningMode,
            memoryState: MemoryState(
                stabilityDays: stabilityDays,
                difficulty: 0.5,
                nextReviewAt: nextReviewAt,
                lastIndependentAttemptAt: clock.now.addingTimeInterval(
                    -86_400 * elapsedSinceLastAttemptDays
                ),
                consecutiveIndependentSuccesses: 1
            ),
            firstIndependentAttemptCount: attemptCount,
            firstIndependentCorrectCount: correctCount,
            firstIndependentResponseTimeTotal: ElapsedTime(
                seconds: (meanResponseSeconds ?? 0) * Double(timedAttemptCount)
            ),
            firstIndependentTimedAttemptCount: timedAttemptCount,
            totalReplayCount: replayCount,
            helpedAttemptCount: helpCount,
            uncertainAttemptCount: uncertainCount,
            lastEncounterAt: clock.now.addingTimeInterval(-86_400)
        )
    }
}
