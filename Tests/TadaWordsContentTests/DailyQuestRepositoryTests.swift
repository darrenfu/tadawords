import Foundation
import TadaWordsContent
import TadaWordsDomain
import XCTest

final class DailyQuestRepositoryTests: XCTestCase {
    func testProfileModeDayKeepsFirstPlanAcrossRestart() async throws {
        let snapshotURL = try makeSnapshotURL()
        let firstCoordinator = DailyQuestCoordinator(
            repository: LocalJSONDailyQuestRepository(snapshotURL: snapshotURL),
            timeZone: Self.timeZone
        )
        let firstCandidate = plan(
            id: questID(1),
            mode: .read,
            newWordNumbers: [1, 2]
        )
        let firstState = try await firstCoordinator.loadOrCreateToday(
            candidate: firstCandidate,
            on: Self.today
        )
        XCTAssertEqual(firstState.plan?.questPlan, firstCandidate)

        let restartedCoordinator = DailyQuestCoordinator(
            repository: LocalJSONDailyQuestRepository(snapshotURL: snapshotURL),
            timeZone: Self.timeZone
        )
        let laterCandidate = plan(
            id: questID(2),
            mode: .read,
            newWordNumbers: [8, 9]
        )
        let restartedState = try await restartedCoordinator.loadOrCreateToday(
            candidate: laterCandidate,
            on: Self.today.addingTimeInterval(60 * 60)
        )

        XCTAssertEqual(restartedState.plan?.questPlan, firstCandidate)
        XCTAssertNotEqual(restartedState.plan?.questPlan, laterCandidate)
    }

    func testReadAndWriteRoutesHaveIndependentDailyPlans() async throws {
        let repository = InMemoryDailyQuestRepository()
        let coordinator = DailyQuestCoordinator(
            repository: repository,
            timeZone: Self.timeZone
        )
        let readPlan = plan(
            id: questID(10),
            mode: .read,
            newWordNumbers: [10]
        )
        let writePlan = plan(
            id: questID(11),
            mode: .write,
            newWordNumbers: [11]
        )

        _ = try await coordinator.loadOrCreateToday(
            candidate: readPlan,
            on: Self.today
        )
        _ = try await coordinator.loadOrCreateToday(
            candidate: writePlan,
            on: Self.today
        )

        let readState = try await coordinator.state(
            profileID: Self.profileID,
            learningMode: .read,
            on: Self.today
        )
        let writeState = try await coordinator.state(
            profileID: Self.profileID,
            learningMode: .write,
            on: Self.today
        )
        XCTAssertEqual(readState.plan?.questPlan, readPlan)
        XCTAssertEqual(writeState.plan?.questPlan, writePlan)
    }

    func testTodayCompletionAndRewardAreIdempotentAndPracticeAgainCannotRegrant()
        async throws
    {
        let repository = InMemoryDailyQuestRepository()
        let coordinator = DailyQuestCoordinator(
            repository: repository,
            timeZone: Self.timeZone
        )
        let candidate = plan(
            id: questID(20),
            mode: .read,
            reviewWordNumbers: [20],
            newWordNumbers: [21, 22]
        )
        let initialState = try await coordinator.loadOrCreateToday(
            candidate: candidate,
            on: Self.today
        )
        let todayLaunch = try XCTUnwrap(
            coordinator.todayLaunch(from: initialState)
        )
        let completionID = DailyQuestCompletionID(rawValue: uuid(30))
        let firstGrantID = RewardGrantID(rawValue: uuid(31))

        let firstWrite = try await coordinator.complete(
            todayLaunch,
            score: Self.score,
            world: .moonpetalKingdom,
            completionID: completionID,
            rewardGrantID: firstGrantID,
            completedAt: Self.today.addingTimeInterval(300)
        )
        XCTAssertTrue(firstWrite.insertedCompletion)
        XCTAssertTrue(firstWrite.grantedReward)
        XCTAssertEqual(firstWrite.completion.points, 88)
        XCTAssertEqual(firstWrite.completion.stars, Self.score.stars)
        XCTAssertEqual(firstWrite.rewardGrant?.id, firstGrantID)

        let retry = try await coordinator.complete(
            todayLaunch,
            score: Self.score,
            world: .moonpetalKingdom,
            completionID: completionID,
            rewardGrantID: RewardGrantID(rawValue: uuid(32)),
            completedAt: Self.today.addingTimeInterval(300)
        )
        XCTAssertFalse(retry.insertedCompletion)
        XCTAssertFalse(retry.grantedReward)
        XCTAssertEqual(retry.rewardGrant?.id, firstGrantID)

        let completedState = try await coordinator.state(
            profileID: Self.profileID,
            learningMode: .read,
            on: Self.today
        )
        XCTAssertNil(coordinator.todayLaunch(from: completedState))
        let practiceLaunch = try XCTUnwrap(
            coordinator.practiceAgainLaunch(
                from: completedState,
                questID: questID(21),
                startedAt: Self.today.addingTimeInterval(600)
            )
        )
        XCTAssertEqual(practiceLaunch.runKind, .practiceAgain)
        XCTAssertEqual(practiceLaunch.questPlan.newWordIDs, [])
        XCTAssertEqual(
            practiceLaunch.questPlan.reviewWordIDs,
            candidate.orderedItems.map(\.wordPromptID)
        )

        let practiceWrite = try await coordinator.complete(
            practiceLaunch,
            score: Self.score,
            world: .buildItBay,
            completionID: DailyQuestCompletionID(rawValue: uuid(33)),
            completedAt: Self.today.addingTimeInterval(900)
        )
        XCTAssertTrue(practiceWrite.insertedCompletion)
        XCTAssertFalse(practiceWrite.grantedReward)
        XCTAssertNil(practiceWrite.rewardGrant)

        let completions = try await coordinator.completions(
            profileID: Self.profileID,
            learningMode: .read,
            on: Self.today
        )
        XCTAssertEqual(completions.count, 2)
        XCTAssertEqual(completions.map(\.runKind), [.today, .practiceAgain])
        let finalState = try await coordinator.state(
            profileID: Self.profileID,
            learningMode: .read,
            on: Self.today
        )
        XCTAssertEqual(finalState.rewardGrant?.id, firstGrantID)

        do {
            _ = try await coordinator.complete(
                todayLaunch,
                score: Self.score,
                world: .moonpetalKingdom,
                completionID: DailyQuestCompletionID(rawValue: uuid(34)),
                completedAt: Self.today.addingTimeInterval(1_000)
            )
            XCTFail("Expected Today to accept only one logical completion")
        } catch let error as DailyQuestRepositoryError {
            XCTAssertEqual(error, .todayAlreadyCompleted(completionID))
        }
    }

    func testCompletionPointsStarsAndRewardSurviveRepositoryRestart()
        async throws
    {
        let snapshotURL = try makeSnapshotURL()
        let firstCoordinator = DailyQuestCoordinator(
            repository: LocalJSONDailyQuestRepository(snapshotURL: snapshotURL),
            timeZone: Self.timeZone
        )
        let initialState = try await firstCoordinator.loadOrCreateToday(
            candidate: plan(
                id: questID(40),
                mode: .write,
                newWordNumbers: [40]
            ),
            on: Self.today
        )
        let launch = try XCTUnwrap(
            firstCoordinator.todayLaunch(from: initialState)
        )
        let write = try await firstCoordinator.complete(
            launch,
            score: Self.score,
            world: .buildItBay,
            completionID: DailyQuestCompletionID(rawValue: uuid(41)),
            rewardGrantID: RewardGrantID(rawValue: uuid(42)),
            completedAt: Self.today.addingTimeInterval(400)
        )

        let restartedCoordinator = DailyQuestCoordinator(
            repository: LocalJSONDailyQuestRepository(snapshotURL: snapshotURL),
            timeZone: Self.timeZone
        )
        let restored = try await restartedCoordinator.state(
            profileID: Self.profileID,
            learningMode: .write,
            on: Self.today
        )

        XCTAssertEqual(restored.todayCompletion, write.completion)
        XCTAssertEqual(restored.rewardGrant, write.rewardGrant)
        XCTAssertEqual(restored.todayCompletion?.points, 88)
        XCTAssertEqual(restored.todayCompletion?.stars.count, 2)
    }

    func testCorruptSnapshotIsPreservedLatchedAndReloadableAfterRepair()
        async throws
    {
        let snapshotURL = try makeSnapshotURL()
        let corruptData = Data("not daily quest json".utf8)
        try corruptData.write(to: snapshotURL)
        let repository = LocalJSONDailyQuestRepository(snapshotURL: snapshotURL)
        let key = DailyQuestKey(
            profileID: Self.profileID,
            learningMode: .read,
            localDay: LocalDay(date: Self.today, timeZone: Self.timeZone)
        )

        await assertInvalidJSON(repository: repository, key: key)
        XCTAssertEqual(try Data(contentsOf: snapshotURL), corruptData)

        let repaired = DailyQuestSnapshot(
            plans: [],
            completions: [],
            rewardGrants: []
        )
        try Self.encoder.encode(repaired).write(to: snapshotURL)
        await assertInvalidJSON(repository: repository, key: key)

        try await repository.reloadFromDisk()
        let state = try await repository.state(for: key)
        XCTAssertNil(state.plan)
    }

    func testUnsupportedSchemaIsTypedAndPreserved() async throws {
        let snapshotURL = try makeSnapshotURL()
        let unsupported = DailyQuestSnapshot(
            schemaVersion: 999,
            plans: [],
            completions: [],
            rewardGrants: []
        )
        let data = try Self.encoder.encode(unsupported)
        try data.write(to: snapshotURL)
        let repository = LocalJSONDailyQuestRepository(snapshotURL: snapshotURL)
        let key = DailyQuestKey(
            profileID: Self.profileID,
            learningMode: .read,
            localDay: LocalDay(date: Self.today, timeZone: Self.timeZone)
        )

        do {
            _ = try await repository.state(for: key)
            XCTFail("Expected unsupported schema")
        } catch let error as LocalDailyQuestRepositoryError {
            XCTAssertEqual(
                error,
                .unsupportedSchemaVersion(
                    snapshotURL: snapshotURL,
                    found: 999,
                    supported: DailyQuestSnapshot.currentSchemaVersion
                )
            )
        }
        XCTAssertEqual(try Data(contentsOf: snapshotURL), data)
    }

    func testDuplicateDailyPlanBusinessKeyFailsClosed() async throws {
        let snapshotURL = try makeSnapshotURL()
        let first = DailyQuestPlan(
            localDay: LocalDay(date: Self.today, timeZone: Self.timeZone),
            questPlan: plan(
                id: questID(50),
                mode: .read,
                newWordNumbers: [50]
            )
        )
        let duplicateKey = DailyQuestPlan(
            localDay: first.localDay,
            questPlan: plan(
                id: questID(51),
                mode: .read,
                newWordNumbers: [51]
            )
        )
        let invalidData = try Self.encoder.encode(
            DailyQuestSnapshot(
                plans: [first, duplicateKey],
                completions: [],
                rewardGrants: []
            )
        )
        try invalidData.write(to: snapshotURL)
        let repository = LocalJSONDailyQuestRepository(snapshotURL: snapshotURL)

        do {
            _ = try await repository.state(for: first.key)
            XCTFail("Expected duplicate Daily Quest key")
        } catch let error as LocalDailyQuestRepositoryError {
            XCTAssertEqual(
                error,
                .invalidSnapshot(
                    snapshotURL: snapshotURL,
                    issue: .duplicatePlanKey(first.key)
                )
            )
        }
        XCTAssertEqual(try Data(contentsOf: snapshotURL), invalidData)
    }

    func testWriteFailureDoesNotCommitCandidateToActorState() async throws {
        let snapshotURL = try makeSnapshotURL()
        let repository = LocalJSONDailyQuestRepository(snapshotURL: snapshotURL)
        let dailyPlan = DailyQuestPlan(
            localDay: LocalDay(date: Self.today, timeZone: Self.timeZone),
            questPlan: plan(
                id: questID(60),
                mode: .read,
                newWordNumbers: [60]
            )
        )
        let initialState = try await repository.state(for: dailyPlan.key)
        XCTAssertNil(initialState.plan)

        let blockingParent = snapshotURL.deletingLastPathComponent()
        try FileManager.default.removeItem(at: blockingParent)
        try Data("keep me".utf8).write(to: blockingParent)

        do {
            _ = try await repository.createPlanIfAbsent(dailyPlan)
            XCTFail("Expected atomic write failure")
        } catch let error as LocalDailyQuestRepositoryError {
            guard case .writeFailed = error else {
                return XCTFail("Unexpected error: \(error)")
            }
        }
        let stateAfterFailure = try await repository.state(for: dailyPlan.key)
        XCTAssertNil(stateAfterFailure.plan)
        XCTAssertEqual(
            try Data(contentsOf: blockingParent),
            Data("keep me".utf8)
        )
    }

    func testCatalogHasMultipleThemeOnlyRewardsAndStableDailyRotation()
        throws
    {
        let catalog = ThemedRewardCatalog()
        for world in WorldTheme.allCases {
            let items = catalog.items(for: world)
            XCTAssertEqual(items.count, 25)
            XCTAssertEqual(
                items.filter { $0.tier == .smallCollectible }.count,
                20
            )
            XCTAssertEqual(items.filter { $0.tier == .milestone }.count, 5)
            XCTAssertTrue(items.allSatisfy { $0.world == world })
            XCTAssertEqual(Set(items.map(\.id)).count, items.count)
            XCTAssertTrue(items.allSatisfy { !$0.iconAssetID.isEmpty })
            XCTAssertEqual(
                Set(items.map(\.iconAssetID)).count,
                items.count,
                "Every treasure in \(world.displayName) needs different artwork"
            )
        }

        let firstDay = try LocalDay(year: 2026, month: 7, day: 12)
        let nextDay = try LocalDay(year: 2026, month: 7, day: 13)
        let firstKey = RewardGrantKey(
            profileID: Self.profileID,
            world: .pawsAndPines,
            localDay: firstDay,
            learningMode: .read
        )
        let nextKey = RewardGrantKey(
            profileID: Self.profileID,
            world: .pawsAndPines,
            localDay: nextDay,
            learningMode: .read
        )
        XCTAssertEqual(catalog.reward(for: firstKey), catalog.reward(for: firstKey))
        XCTAssertNotEqual(catalog.reward(for: firstKey), catalog.reward(for: nextKey))
    }

    func testMonthSummaryCountsReadWriteAndPracticeAndIsolatesProfiles()
        async throws
    {
        let repository = InMemoryDailyQuestRepository()
        let coordinator = DailyQuestCoordinator(
            repository: repository,
            timeZone: Self.timeZone
        )
        let julyDate = try XCTUnwrap(
            ISO8601DateFormatter().date(from: "2026-07-12T19:00:00Z")
        )
        let secondProfileID = ProfileID(rawValue: uuid(700))

        let readState = try await coordinator.loadOrCreateToday(
            candidate: plan(
                id: questID(700),
                mode: .read,
                newWordNumbers: [700]
            ),
            on: julyDate
        )
        let readLaunch = try XCTUnwrap(coordinator.todayLaunch(from: readState))
        _ = try await coordinator.complete(
            readLaunch,
            score: Self.score,
            world: .moonpetalKingdom,
            completedAt: julyDate.addingTimeInterval(10)
        )
        let completedReadState = try await coordinator.state(
            profileID: Self.profileID,
            learningMode: .read,
            on: julyDate
        )
        let practiceLaunch = try XCTUnwrap(
            coordinator.practiceAgainLaunch(
                from: completedReadState,
                questID: questID(701),
                startedAt: julyDate.addingTimeInterval(20)
            )
        )
        _ = try await coordinator.complete(
            practiceLaunch,
            score: Self.score,
            world: .moonpetalKingdom,
            completedAt: julyDate.addingTimeInterval(30)
        )

        let writeState = try await coordinator.loadOrCreateToday(
            candidate: plan(
                id: questID(702),
                mode: .write,
                newWordNumbers: [702]
            ),
            on: julyDate
        )
        _ = try await coordinator.complete(
            try XCTUnwrap(coordinator.todayLaunch(from: writeState)),
            score: Self.score,
            world: .moonpetalKingdom,
            completedAt: julyDate.addingTimeInterval(40)
        )

        let otherState = try await coordinator.loadOrCreateToday(
            candidate: plan(
                id: questID(703),
                profileID: secondProfileID,
                mode: .read,
                newWordNumbers: [703]
            ),
            on: julyDate
        )
        _ = try await coordinator.complete(
            try XCTUnwrap(coordinator.todayLaunch(from: otherState)),
            score: Self.score,
            world: .pawsAndPines,
            completedAt: julyDate.addingTimeInterval(50)
        )

        let summary = try await coordinator.monthSummary(
            profileID: Self.profileID,
            containing: julyDate
        )
        let july12 = try LocalDay(year: 2026, month: 7, day: 12)
        XCTAssertEqual(summary.month, try LocalMonth(year: 2026, month: 7))
        XCTAssertEqual(summary.completionCount(on: july12), 3)
        XCTAssertEqual(summary.completionCountByDay.values.reduce(0, +), 3)

        let otherSummary = try await coordinator.monthSummary(
            profileID: secondProfileID,
            containing: julyDate
        )
        XCTAssertEqual(otherSummary.completionCount(on: july12), 1)
    }

    func testMonthQueryHonorsLocalTimeZoneBoundaryAndReturnsEmptyMonth()
        async throws
    {
        let repository = InMemoryDailyQuestRepository()
        let instant = try XCTUnwrap(
            ISO8601DateFormatter().date(from: "2026-07-01T06:30:00Z")
        )
        let losAngelesCoordinator = DailyQuestCoordinator(
            repository: repository,
            timeZone: Self.timeZone
        )
        let state = try await losAngelesCoordinator.loadOrCreateToday(
            candidate: plan(
                id: questID(710),
                mode: .read,
                newWordNumbers: [710]
            ),
            on: instant
        )
        _ = try await losAngelesCoordinator.complete(
            try XCTUnwrap(losAngelesCoordinator.todayLaunch(from: state)),
            score: Self.score,
            world: .buildItBay,
            completedAt: instant
        )

        let juneSummary = try await losAngelesCoordinator.monthSummary(
            profileID: Self.profileID,
            containing: instant
        )
        XCTAssertEqual(juneSummary.month, try LocalMonth(year: 2026, month: 6))
        XCTAssertEqual(
            juneSummary.completionCount(
                on: try LocalDay(year: 2026, month: 6, day: 30)
            ),
            1
        )

        let emptyJuly = try await repository.completions(
            for: Self.profileID,
            in: try LocalMonth(year: 2026, month: 7)
        )
        XCTAssertTrue(emptyJuly.isEmpty)
    }

    func testCorruptSnapshotMonthQueryFailsClosed() async throws {
        let snapshotURL = try makeSnapshotURL()
        let corruptData = Data("not daily quest json".utf8)
        try corruptData.write(to: snapshotURL)
        let repository = LocalJSONDailyQuestRepository(snapshotURL: snapshotURL)

        do {
            _ = try await repository.completions(
                for: Self.profileID,
                in: try LocalMonth(year: 2026, month: 7)
            )
            XCTFail("Expected invalid Daily Quest JSON")
        } catch let error as LocalDailyQuestRepositoryError {
            guard case .invalidJSON = error else {
                return XCTFail("Unexpected error: \(error)")
            }
        }
        XCTAssertEqual(try Data(contentsOf: snapshotURL), corruptData)
    }

    func testLocalJSONMonthQuerySurvivesRestartWithoutSchemaChange()
        async throws
    {
        let snapshotURL = try makeSnapshotURL()
        let date = try XCTUnwrap(
            ISO8601DateFormatter().date(from: "2026-07-22T17:00:00Z")
        )
        let firstCoordinator = DailyQuestCoordinator(
            repository: LocalJSONDailyQuestRepository(snapshotURL: snapshotURL),
            timeZone: Self.timeZone
        )
        let state = try await firstCoordinator.loadOrCreateToday(
            candidate: plan(
                id: questID(720),
                mode: .write,
                newWordNumbers: [720]
            ),
            on: date
        )
        _ = try await firstCoordinator.complete(
            try XCTUnwrap(firstCoordinator.todayLaunch(from: state)),
            score: Self.score,
            world: .pawsAndPines,
            completedAt: date.addingTimeInterval(25)
        )

        let restartedRepository = LocalJSONDailyQuestRepository(
            snapshotURL: snapshotURL
        )
        let completions = try await restartedRepository.completions(
            for: Self.profileID,
            in: try LocalMonth(year: 2026, month: 7)
        )

        XCTAssertEqual(completions.count, 1)
        XCTAssertEqual(completions.first?.learningMode, .write)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .secondsSince1970
        let decoded = try decoder.decode(
            DailyQuestSnapshot.self,
            from: Data(contentsOf: snapshotURL)
        )
        XCTAssertEqual(
            decoded.schemaVersion,
            DailyQuestSnapshot.currentSchemaVersion
        )
    }

    private func assertInvalidJSON(
        repository: LocalJSONDailyQuestRepository,
        key: DailyQuestKey
    ) async {
        do {
            _ = try await repository.state(for: key)
            XCTFail("Expected invalid Daily Quest JSON")
        } catch let error as LocalDailyQuestRepositoryError {
            guard case .invalidJSON = error else {
                return XCTFail("Unexpected error: \(error)")
            }
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    private func makeSnapshotURL() throws -> URL {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true
        )
        addTeardownBlock {
            try? FileManager.default.removeItem(at: directory)
        }
        return directory.appendingPathComponent("daily-quests.json")
    }

    private func plan(
        id: QuestID,
        profileID: ProfileID = DailyQuestRepositoryTests.profileID,
        mode: LearningMode,
        reviewWordNumbers: [Int] = [],
        newWordNumbers: [Int]
    ) -> QuestPlan {
        QuestPlan(
            id: id,
            profileID: profileID,
            configuration: QuestConfiguration(
                learningMode: mode,
                newWordLimit: 5,
                reviewWordLimit: 5,
                attentionBudget: 10,
                contentOrder: .newThenReview
            ),
            reviewWordIDs: reviewWordNumbers.map(wordID),
            newWordIDs: newWordNumbers.map(wordID),
            createdAt: Self.today
        )
    }

    private func questID(_ number: Int) -> QuestID {
        QuestID(rawValue: uuid(1_000 + number))
    }

    private func wordID(_ number: Int) -> WordPromptID {
        WordPromptID(rawValue: uuid(2_000 + number))
    }

    private func uuid(_ number: Int) -> UUID {
        UUID(
            uuidString: String(
                format: "64000000-0000-0000-0000-%012X",
                number
            )
        )!
    }

    private static let profileID = ProfileID(
        rawValue: UUID(uuidString: "64000000-0000-0000-0000-000000000001")!
    )
    private static let timeZone = TimeZone(identifier: "America/Los_Angeles")!
    private static let today = Date(timeIntervalSince1970: 1_783_884_000)
    private static let score = QuestScore(
        points: 88,
        firstIndependentCorrectCount: 4,
        firstIndependentAttemptCount: 5,
        stars: QuestStars(earned: [.completion, .accuracy]),
        personalPaceAssessment: .outsidePersonalBand
    )
    private static let encoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .secondsSince1970
        return encoder
    }()
}
