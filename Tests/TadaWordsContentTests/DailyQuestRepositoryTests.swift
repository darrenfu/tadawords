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
        let focusedPracticeLaunch = try XCTUnwrap(
            coordinator.practiceAgainLaunch(
                from: completedState,
                replaying: [wordID(22), wordID(999)],
                questID: questID(22),
                startedAt: Self.today.addingTimeInterval(700)
            )
        )
        XCTAssertEqual(
            focusedPracticeLaunch.questPlan.reviewWordIDs,
            [wordID(22)]
        )
        XCTAssertNil(
            coordinator.practiceAgainLaunch(
                from: completedState,
                replaying: [wordID(999)],
                startedAt: Self.today.addingTimeInterval(700)
            )
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

    func testCanonicalMergeReplacesDailyWinnersAndRemapsAllReferences()
        async throws
    {
        let repository = InMemoryDailyQuestRepository()
        let coordinator = DailyQuestCoordinator(
            repository: repository,
            timeZone: Self.timeZone
        )
        let localState = try await coordinator.loadOrCreateToday(
            candidate: plan(
                id: questID(100),
                mode: .read,
                newWordNumbers: [100]
            ),
            on: Self.today
        )
        _ = try await coordinator.complete(
            try XCTUnwrap(coordinator.todayLaunch(from: localState)),
            score: Self.score,
            world: .moonpetalKingdom,
            completedAt: Self.today.addingTimeInterval(10)
        )

        let key = try XCTUnwrap(localState.plan?.key)
        let remotePlan = DailyQuestPlan(
            localDay: key.localDay,
            questPlan: plan(
                id: questID(101),
                mode: .read,
                newWordNumbers: [101, 102]
            )
        )
        let remoteCompletion = DailyQuestCompletion(
            id: DailyQuestCompletionID(rawValue: uuid(110)),
            dailyPlanID: questID(998),
            runQuestID: questID(997),
            profileID: key.profileID,
            learningMode: key.learningMode,
            localDay: key.localDay,
            runKind: .today,
            points: 97,
            stars: QuestStars(
                earned: [.completion, .accuracy, .personalPace]
            ),
            completedAt: Self.today.addingTimeInterval(20)
        )
        let rewardKey = RewardGrantKey(
            profileID: key.profileID,
            world: .buildItBay,
            localDay: key.localDay,
            learningMode: key.learningMode
        )
        let remoteReward = RewardGrant(
            id: RewardGrantID(rawValue: uuid(111)),
            key: rewardKey,
            dailyPlanID: questID(996),
            completionID: DailyQuestCompletionID(rawValue: uuid(995)),
            item: ThemedRewardCatalog().reward(for: rewardKey),
            grantedAt: remoteCompletion.completedAt
        )
        let batch = DailyQuestCanonicalMergeBatch(
            plans: [remotePlan],
            completions: [remoteCompletion],
            rewardGrants: [remoteReward]
        )

        let firstMerge = try await repository.mergeCanonical(batch)
        XCTAssertTrue(firstMerge.didChange)
        XCTAssertEqual(firstMerge.affectedKeys, [key])

        let merged = try await repository.state(for: key)
        XCTAssertEqual(merged.plan, remotePlan)
        XCTAssertEqual(merged.todayCompletion?.id, remoteCompletion.id)
        XCTAssertEqual(merged.todayCompletion?.dailyPlanID, remotePlan.id)
        XCTAssertEqual(merged.todayCompletion?.runQuestID, remotePlan.id)
        XCTAssertEqual(merged.todayCompletion?.points, 97)
        XCTAssertEqual(merged.rewardGrant?.id, remoteReward.id)
        XCTAssertEqual(merged.rewardGrant?.dailyPlanID, remotePlan.id)
        XCTAssertEqual(
            merged.rewardGrant?.completionID,
            remoteCompletion.id
        )
        XCTAssertEqual(merged.rewardGrant?.key.world, .buildItBay)
        let mergedCompletions = try await repository.completions(for: key)
        XCTAssertEqual(
            mergedCompletions.filter { $0.runKind == .today }.count,
            1
        )

        let duplicateMerge = try await repository.mergeCanonical(batch)
        XCTAssertFalse(duplicateMerge.didChange)
    }

    func testCanonicalMergeRequiresDependencyClosedTodayAndPreservesBytes()
        async throws
    {
        let snapshotURL = try makeSnapshotURL()
        let repository = LocalJSONDailyQuestRepository(snapshotURL: snapshotURL)
        let storedPlan = DailyQuestPlan(
            localDay: LocalDay(date: Self.today, timeZone: Self.timeZone),
            questPlan: plan(
                id: questID(120),
                mode: .write,
                newWordNumbers: [120]
            )
        )
        _ = try await repository.createPlanIfAbsent(storedPlan)
        let originalData = try Data(contentsOf: snapshotURL)
        let incompleteToday = DailyQuestCompletion(
            id: DailyQuestCompletionID(rawValue: uuid(121)),
            dailyPlanID: storedPlan.id,
            runQuestID: storedPlan.id,
            profileID: storedPlan.key.profileID,
            learningMode: storedPlan.key.learningMode,
            localDay: storedPlan.key.localDay,
            runKind: .today,
            points: 88,
            stars: Self.score.stars,
            completedAt: Self.today.addingTimeInterval(20)
        )

        do {
            _ = try await repository.mergeCanonical(
                DailyQuestCanonicalMergeBatch(
                    completions: [incompleteToday]
                )
            )
            XCTFail("Expected Today and reward to arrive together")
        } catch let error as DailyQuestRepositoryError {
            XCTAssertEqual(
                error,
                .incompleteCanonicalToday(storedPlan.key)
            )
        }

        XCTAssertEqual(try Data(contentsOf: snapshotURL), originalData)
        let state = try await repository.state(for: storedPlan.key)
        XCTAssertNil(state.todayCompletion)
        XCTAssertNil(state.rewardGrant)
    }

    func testCanonicalMergeConvergesTwoDevicesAndUnionsPracticeAgain()
        async throws
    {
        let firstURL = try makeSnapshotURL()
        let secondURL = try makeSnapshotURL()
        let firstRepository = LocalJSONDailyQuestRepository(
            snapshotURL: firstURL
        )
        let secondRepository = LocalJSONDailyQuestRepository(
            snapshotURL: secondURL
        )
        let firstCoordinator = DailyQuestCoordinator(
            repository: firstRepository,
            timeZone: Self.timeZone
        )
        let secondCoordinator = DailyQuestCoordinator(
            repository: secondRepository,
            timeZone: Self.timeZone
        )

        let firstInitial = try await firstCoordinator.loadOrCreateToday(
            candidate: plan(
                id: questID(130),
                mode: .read,
                newWordNumbers: [130]
            ),
            on: Self.today
        )
        let secondInitial = try await secondCoordinator.loadOrCreateToday(
            candidate: plan(
                id: questID(131),
                mode: .read,
                newWordNumbers: [131]
            ),
            on: Self.today
        )
        _ = try await firstCoordinator.complete(
            try XCTUnwrap(firstCoordinator.todayLaunch(from: firstInitial)),
            score: Self.score,
            world: .moonpetalKingdom,
            completionID: DailyQuestCompletionID(rawValue: uuid(132)),
            rewardGrantID: RewardGrantID(rawValue: uuid(133)),
            completedAt: Self.today.addingTimeInterval(10)
        )
        _ = try await secondCoordinator.complete(
            try XCTUnwrap(secondCoordinator.todayLaunch(from: secondInitial)),
            score: Self.score,
            world: .buildItBay,
            completionID: DailyQuestCompletionID(rawValue: uuid(134)),
            rewardGrantID: RewardGrantID(rawValue: uuid(135)),
            completedAt: Self.today.addingTimeInterval(20)
        )

        let firstCompleted = try await firstCoordinator.state(
            profileID: Self.profileID,
            learningMode: .read,
            on: Self.today
        )
        let secondCompleted = try await secondCoordinator.state(
            profileID: Self.profileID,
            learningMode: .read,
            on: Self.today
        )
        let firstPractice = try await firstCoordinator.complete(
            try XCTUnwrap(
                firstCoordinator.practiceAgainLaunch(
                    from: firstCompleted,
                    questID: questID(136),
                    startedAt: Self.today.addingTimeInterval(30)
                )
            ),
            score: Self.score,
            world: .moonpetalKingdom,
            completionID: DailyQuestCompletionID(rawValue: uuid(137)),
            completedAt: Self.today.addingTimeInterval(40)
        ).completion
        let secondPractice = try await secondCoordinator.complete(
            try XCTUnwrap(
                secondCoordinator.practiceAgainLaunch(
                    from: secondCompleted,
                    questID: questID(138),
                    startedAt: Self.today.addingTimeInterval(50)
                )
            ),
            score: Self.score,
            world: .buildItBay,
            completionID: DailyQuestCompletionID(rawValue: uuid(139)),
            completedAt: Self.today.addingTimeInterval(60)
        ).completion

        let winningPlan = try XCTUnwrap(firstCompleted.plan)
        let winningToday = try XCTUnwrap(firstCompleted.todayCompletion)
        let winningReward = try XCTUnwrap(firstCompleted.rewardGrant)
        let firstBatch = DailyQuestCanonicalMergeBatch(
            plans: [winningPlan],
            completions: [
                winningToday,
                firstPractice,
                secondPractice,
            ],
            rewardGrants: [winningReward]
        )
        let secondBatch = DailyQuestCanonicalMergeBatch(
            plans: firstBatch.plans.reversed(),
            completions: firstBatch.completions.reversed(),
            rewardGrants: firstBatch.rewardGrants.reversed()
        )

        _ = try await firstRepository.mergeCanonical(firstBatch)
        _ = try await secondRepository.mergeCanonical(secondBatch)

        XCTAssertEqual(
            try Data(contentsOf: firstURL),
            try Data(contentsOf: secondURL)
        )
        let completions = try await secondRepository.completions(
            for: winningPlan.key
        )
        XCTAssertEqual(completions.filter { $0.runKind == .today }.count, 1)
        XCTAssertEqual(
            Set(
                completions
                    .filter { $0.runKind == .practiceAgain }
                    .map(\.id)
            ),
            [firstPractice.id, secondPractice.id]
        )
        XCTAssertTrue(
            completions.allSatisfy {
                $0.dailyPlanID == winningPlan.id
            }
        )
    }

    func testVersionOneSnapshotMigratesToCanonicalBusinessKeyMetadata()
        async throws
    {
        let snapshotURL = try makeSnapshotURL()
        let plan = DailyQuestPlan(
            localDay: LocalDay(date: Self.today, timeZone: Self.timeZone),
            questPlan: plan(
                id: questID(140),
                mode: .read,
                newWordNumbers: [140]
            )
        )
        let versionOne = DailyQuestSnapshot(
            schemaVersion: 1,
            plans: [plan],
            completions: [],
            rewardGrants: []
        )
        try Self.encoder.encode(versionOne).write(to: snapshotURL)

        let repository = LocalJSONDailyQuestRepository(snapshotURL: snapshotURL)
        let migratedState = try await repository.state(for: plan.key)
        XCTAssertEqual(migratedState.plan, plan)

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .secondsSince1970
        let migratedData = try Data(contentsOf: snapshotURL)
        let migrated = try decoder.decode(
            DailyQuestSnapshot.self,
            from: migratedData
        )
        XCTAssertEqual(
            migrated.schemaVersion,
            DailyQuestSnapshot.currentSchemaVersion
        )
        XCTAssertEqual(
            migrated.canonicalBusinessKeyVersion,
            DailyQuestSnapshot.currentCanonicalBusinessKeyVersion
        )
        XCTAssertEqual(migrated.plans, [plan])

        let restarted = LocalJSONDailyQuestRepository(snapshotURL: snapshotURL)
        _ = try await restarted.state(for: plan.key)
        XCTAssertEqual(try Data(contentsOf: snapshotURL), migratedData)
    }

    func testVersionOneSnapshotMigratesLegacyKeyedQuestStarsWithoutDataLoss()
        async throws
    {
        let snapshotURL = try makeSnapshotURL()
        let dailyPlan = DailyQuestPlan(
            localDay: LocalDay(date: Self.today, timeZone: Self.timeZone),
            questPlan: plan(
                id: questID(145),
                mode: .read,
                newWordNumbers: [145]
            )
        )
        let completion = DailyQuestCompletion(
            id: DailyQuestCompletionID(rawValue: uuid(146)),
            dailyPlanID: dailyPlan.id,
            runQuestID: dailyPlan.id,
            profileID: dailyPlan.key.profileID,
            learningMode: dailyPlan.key.learningMode,
            localDay: dailyPlan.key.localDay,
            runKind: .today,
            points: 88,
            stars: QuestStars(earned: [.completion, .accuracy]),
            completedAt: Self.today.addingTimeInterval(300)
        )
        let rewardKey = RewardGrantKey(
            profileID: dailyPlan.key.profileID,
            world: .moonpetalKingdom,
            localDay: dailyPlan.key.localDay,
            learningMode: dailyPlan.key.learningMode
        )
        let reward = RewardGrant(
            id: RewardGrantID(rawValue: uuid(147)),
            key: rewardKey,
            dailyPlanID: dailyPlan.id,
            completionID: completion.id,
            item: ThemedRewardCatalog().reward(for: rewardKey),
            grantedAt: completion.completedAt
        )
        let versionOne = DailyQuestSnapshot(
            schemaVersion: 1,
            plans: [dailyPlan],
            completions: [completion],
            rewardGrants: [reward]
        )
        let canonicalData = try Self.encoder.encode(versionOne)
        var legacyObject = try XCTUnwrap(
            JSONSerialization.jsonObject(with: canonicalData)
                as? [String: Any]
        )
        legacyObject.removeValue(forKey: "canonicalBusinessKeyVersion")
        legacyObject.removeValue(forKey: "pendingCompletions")
        legacyObject.removeValue(forKey: "pendingRewardGrants")
        var legacyCompletions = try XCTUnwrap(
            legacyObject["completions"] as? [[String: Any]]
        )
        legacyCompletions[0]["stars"] = [
            "earned": ["completion", "accuracy"]
        ]
        legacyObject["completions"] = legacyCompletions
        let legacyData = try JSONSerialization.data(
            withJSONObject: legacyObject,
            options: [.sortedKeys]
        )
        try legacyData.write(to: snapshotURL)

        let repository = LocalJSONDailyQuestRepository(
            snapshotURL: snapshotURL
        )
        let migratedState = try await repository.state(for: dailyPlan.key)

        XCTAssertEqual(migratedState.plan, dailyPlan)
        XCTAssertEqual(migratedState.todayCompletion, completion)
        XCTAssertEqual(migratedState.rewardGrant, reward)
        let migratedData = try Data(contentsOf: snapshotURL)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .secondsSince1970
        let migrated = try decoder.decode(
            DailyQuestSnapshot.self,
            from: migratedData
        )
        XCTAssertEqual(
            migrated.schemaVersion,
            DailyQuestSnapshot.currentSchemaVersion
        )
        XCTAssertEqual(migrated.plans, [dailyPlan])
        XCTAssertEqual(migrated.completions, [completion])
        XCTAssertEqual(migrated.rewardGrants, [reward])
        let migratedObject = try XCTUnwrap(
            JSONSerialization.jsonObject(with: migratedData)
                as? [String: Any]
        )
        let migratedCompletions = try XCTUnwrap(
            migratedObject["completions"] as? [[String: Any]]
        )
        XCTAssertEqual(
            migratedCompletions[0]["stars"] as? [String],
            ["completion", "accuracy"]
        )
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

    func testUnsupportedCanonicalBusinessKeyVersionIsTypedAndPreserved()
        async throws
    {
        let snapshotURL = try makeSnapshotURL()
        let unsupported = DailyQuestSnapshot(
            canonicalBusinessKeyVersion: 999,
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
            XCTFail("Expected unsupported canonical business-key version")
        } catch let error as LocalDailyQuestRepositoryError {
            XCTAssertEqual(
                error,
                .unsupportedCanonicalBusinessKeyVersion(
                    snapshotURL: snapshotURL,
                    found: 999,
                    supported:
                        DailyQuestSnapshot.currentCanonicalBusinessKeyVersion
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
