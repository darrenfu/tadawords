import Foundation
import TadaWordsDomain
import XCTest

final class ProfileWorldProgressionTests: XCTestCase {
    func testOlderProfileSnapshotDefaultsNewMetadataSafely() throws {
        let createdAt = Date(timeIntervalSince1970: 1_000)
        let original = KidProfile(
            displayName: "Mia",
            avatar: .cartoonAnimal(assetID: "hare"),
            selectedWorld: .buildItBay,
            createdAt: createdAt
        )
        let encoded = try JSONEncoder().encode(original)
        var object = try XCTUnwrap(
            JSONSerialization.jsonObject(with: encoded) as? [String: Any]
        )
        for key in [
            "starterWorld", "guardianUnlockedWorlds", "schoolGrade",
            "ageYears", "selectedCartoonIconAssetID", "selectedTreasureAvatar",
            "updatedAt",
        ] {
            object.removeValue(forKey: key)
        }

        let decoded = try JSONDecoder().decode(
            KidProfile.self,
            from: JSONSerialization.data(withJSONObject: object)
        )

        XCTAssertEqual(decoded.starterWorld, .buildItBay)
        XCTAssertEqual(decoded.guardianUnlockedWorlds, [])
        XCTAssertEqual(decoded.schoolGrade, .preK)
        XCTAssertNil(decoded.ageYears)
        XCTAssertNil(decoded.selectedCartoonIconAssetID)
        XCTAssertNil(decoded.selectedTreasureAvatar)
        XCTAssertEqual(decoded.updatedAt, createdAt)
    }

    func testOnlyPriorDaysWithBothTodayModesQualify() throws {
        let profile = makeProfile()
        let anotherProfile = makeProfile(idNumber: 2)
        let completions = [
            completion(
                profile: profile,
                number: 1,
                mode: .read,
                day: try day(month: 7, day: 10)
            ),
            completion(
                profile: profile,
                number: 2,
                mode: .write,
                day: try day(month: 7, day: 10)
            ),
            completion(
                profile: profile,
                number: 3,
                mode: .read,
                day: try day(month: 7, day: 11)
            ),
            completion(
                profile: profile,
                number: 4,
                mode: .write,
                day: try day(month: 7, day: 11),
                kind: .practiceAgain
            ),
            completion(
                profile: profile,
                number: 5,
                mode: .read,
                day: try day(month: 7, day: 12)
            ),
            completion(
                profile: profile,
                number: 6,
                mode: .write,
                day: try day(month: 7, day: 12)
            ),
            completion(
                profile: profile,
                number: 7,
                mode: .read,
                day: try day(month: 7, day: 13)
            ),
            completion(
                profile: profile,
                number: 8,
                mode: .write,
                day: try day(month: 7, day: 13)
            ),
            completion(
                profile: anotherProfile,
                number: 9,
                mode: .write,
                day: try day(month: 7, day: 11)
            ),
        ]

        let progression = WorldProgression(
            profile: profile,
            completions: completions,
            currentLocalDay: try day(month: 7, day: 12)
        )

        XCTAssertEqual(progression.qualifyingPriorDayCount, 1)
        XCTAssertEqual(
            progression.unlockedWorlds,
            [.moonpetalKingdom, .buildItBay]
        )
        XCTAssertEqual(
            progression.unlockedCartoonIconAssetIDs,
            ["hare", "rat"]
        )
    }

    func testDuplicateRunsQualifyOnceAndCrossMonthNaturally() throws {
        let profile = makeProfile()
        let january31 = try day(month: 1, day: 31)
        let completions = [
            completion(
                profile: profile,
                number: 1,
                mode: .read,
                day: january31
            ),
            completion(
                profile: profile,
                number: 2,
                mode: .read,
                day: january31
            ),
            completion(
                profile: profile,
                number: 3,
                mode: .write,
                day: january31
            ),
            completion(
                profile: profile,
                number: 4,
                mode: .write,
                day: january31
            ),
        ]

        let progression = WorldProgression(
            profile: profile,
            completions: completions,
            currentLocalDay: try day(month: 2, day: 1)
        )

        XCTAssertEqual(progression.qualifyingPriorDayCount, 1)
        XCTAssertEqual(progression.unlockedWorlds.count, 2)
        XCTAssertEqual(progression.unlockedCartoonIconAssetIDs.count, 2)
    }

    func testStatesExposeRemainingQualifyingDays() throws {
        let profile = makeProfile()
        let progression = WorldProgression(
            profile: profile,
            completions: qualifyingCompletions(
                profile: profile,
                localDays: [try day(month: 7, day: 10)]
            ),
            currentLocalDay: try day(month: 7, day: 12)
        )

        XCTAssertEqual(
            progression.states.map(\.world),
            CosmeticProgressionCatalog.worlds
        )
        XCTAssertEqual(
            progression.states.map(\.requiredQualifyingDayCount),
            Array(0..<CosmeticProgressionCatalog.worlds.count)
        )
        XCTAssertEqual(
            progression.states.map(\.remainingQualifyingDayCount),
            [0, 0] + Array(1..<(CosmeticProgressionCatalog.worlds.count - 1))
        )
        XCTAssertEqual(
            progression.cartoonIconStates.prefix(3).map(
                \.remainingQualifyingDayCount
            ),
            [0, 0, 1]
        )
    }

    func testStarterAndGuardianWorldsDoNotConsumeEarnedDay() throws {
        let profile = makeProfile(
            starterWorld: .buildItBay,
            guardianUnlockedWorlds: [.moonpetalKingdom]
        )
        let progression = WorldProgression(
            profile: profile,
            completions: qualifyingCompletions(
                profile: profile,
                localDays: [try day(month: 7, day: 10)]
            ),
            currentLocalDay: try day(month: 7, day: 12)
        )

        XCTAssertEqual(
            progression.unlockedWorlds,
            [.moonpetalKingdom, .buildItBay, .pawsAndPines]
        )
        XCTAssertEqual(
            progression.state(for: .pawsAndPines)?.requiredQualifyingDayCount,
            1
        )
        XCTAssertEqual(
            progression.state(for: .dinoDiscovery)?.requiredQualifyingDayCount,
            2
        )
    }

    func testPreviouslySelectedWorldIsNotRelockedAfterRuleMigration() throws {
        let profile = KidProfile(
            displayName: "Mia",
            avatar: .cartoonAnimal(assetID: "hare"),
            selectedWorld: .pawsAndPines,
            starterWorld: .moonpetalKingdom,
            createdAt: Date(timeIntervalSince1970: 0)
        )

        let progression = WorldProgression(
            profile: profile,
            completions: [],
            currentLocalDay: try day(month: 7, day: 12)
        )

        XCTAssertTrue(progression.unlockedWorlds.contains(.moonpetalKingdom))
        XCTAssertTrue(progression.unlockedWorlds.contains(.pawsAndPines))
        XCTAssertFalse(progression.unlockedWorlds.contains(.buildItBay))
    }

    func testCatalogsStopAfterEveryCosmeticIsUnlocked() throws {
        let profile = makeProfile(avatar: .cartoonAnimal(assetID: "rat"))
        let localDays = try (1...12).map { try day(month: 6, day: $0) }
        let progression = WorldProgression(
            profile: profile,
            completions: qualifyingCompletions(
                profile: profile,
                localDays: localDays
            ),
            currentLocalDay: try day(month: 7, day: 12)
        )

        XCTAssertEqual(progression.qualifyingPriorDayCount, 12)
        XCTAssertEqual(progression.unlockedWorlds, Set(WorldTheme.allCases))
        XCTAssertEqual(
            progression.unlockedCartoonIconAssetIDs,
            Set(CosmeticProgressionCatalog.cartoonIconAssetIDs)
        )
        XCTAssertEqual(
            progression.cartoonIconStates.count,
            CosmeticProgressionCatalog.cartoonIconAssetIDs.count
        )
        XCTAssertEqual(
            Set(CosmeticProgressionCatalog.worlds),
            Set(WorldTheme.allCases),
            "Append every new world to the stable progression catalog"
        )
    }

    func testCartoonAvatarIsPermanentStarterAndPhotoUsesFallback() throws {
        let foxProfile = makeProfile(avatar: .cartoonAnimal(assetID: "fox"))
        let foxProgression = WorldProgression(
            profile: foxProfile,
            completions: [],
            currentLocalDay: try day(month: 7, day: 12)
        )
        XCTAssertEqual(foxProgression.starterCartoonIconAssetID, "fox")
        XCTAssertEqual(foxProgression.unlockedCartoonIconAssetIDs, ["fox"])
        XCTAssertEqual(
            foxProgression.cartoonIconStates.map(\.assetID).prefix(2),
            [
                "fox", "rat",
            ])

        let photoProfile = makeProfile(
            idNumber: 3,
            avatar: .photo(assetID: "photo", source: .photoLibrary)
        )
        let photoProgression = WorldProgression(
            profile: photoProfile,
            completions: [],
            currentLocalDay: try day(month: 7, day: 12)
        )
        XCTAssertEqual(photoProgression.starterCartoonIconAssetID, "rat")
        XCTAssertEqual(photoProgression.unlockedCartoonIconAssetIDs, ["rat"])
    }

    func testOldThreeAndEightQuestThresholdsNoLongerApply() throws {
        let profile = makeProfile()
        let localDay = try day(month: 7, day: 10)
        let sameDayCompletions = (1...8).map { number in
            completion(
                profile: profile,
                number: number,
                mode: number.isMultiple(of: 2) ? .read : .write,
                day: localDay
            )
        }
        let progression = WorldProgression(
            profile: profile,
            completions: sameDayCompletions,
            currentLocalDay: try day(month: 7, day: 12)
        )

        XCTAssertEqual(progression.qualifyingPriorDayCount, 1)
        XCTAssertEqual(
            progression.unlockedWorlds,
            [.moonpetalKingdom, .buildItBay]
        )
    }

    func testCollectionNeverMixesThemesAndDerivesMilestones() {
        let profile = makeProfile()
        let small = RewardCatalogItem(
            id: RewardItemID(rawValue: "moonpetalKingdom.tiara"),
            world: .moonpetalKingdom,
            displayName: "Tiara"
        )
        let milestone = RewardCatalogItem(
            id: RewardItemID(rawValue: "moonpetalKingdom.milestone.garden"),
            world: .moonpetalKingdom,
            displayName: "Garden",
            tier: .milestone,
            requiredTodayQuestCount: 3
        )
        let wrongWorld = RewardCatalogItem(
            id: RewardItemID(rawValue: "buildItBay.truck"),
            world: .buildItBay,
            displayName: "Truck"
        )
        let grants = (1...3).map { number in
            rewardGrant(
                profile: profile,
                item: number == 1
                    ? small
                    : RewardCatalogItem(
                        id: RewardItemID(rawValue: "moonpetalKingdom.extra\(number)"),
                        world: .moonpetalKingdom,
                        displayName: "Extra"
                    ),
                number: number
            )
        }

        let collection = RewardCollection(
            profileID: profile.id,
            world: .moonpetalKingdom,
            catalogItems: [small, milestone, wrongWorld],
            rewardGrants: grants
        )

        XCTAssertEqual(
            collection.items.map(\.item.world),
            [
                .moonpetalKingdom, .moonpetalKingdom,
            ])
        XCTAssertTrue(collection.items.allSatisfy(\.isCollected))
    }

    private func makeProfile(
        idNumber: Int = 1,
        avatar: ProfileAvatar = .cartoonAnimal(assetID: "hare"),
        starterWorld: WorldTheme = .moonpetalKingdom,
        guardianUnlockedWorlds: Set<WorldTheme> = []
    ) -> KidProfile {
        KidProfile(
            id: ProfileID(rawValue: uuid(idNumber)),
            displayName: "Mia",
            avatar: avatar,
            selectedWorld: starterWorld,
            starterWorld: starterWorld,
            guardianUnlockedWorlds: guardianUnlockedWorlds,
            createdAt: Date(timeIntervalSince1970: 0)
        )
    }

    private func completion(
        profile: KidProfile,
        number: Int,
        mode: LearningMode,
        day: LocalDay,
        kind: DailyQuestRunKind = .today
    ) -> DailyQuestCompletion {
        DailyQuestCompletion(
            id: DailyQuestCompletionID(rawValue: uuid(100 + number)),
            dailyPlanID: QuestID(rawValue: uuid(200 + number)),
            runQuestID: QuestID(rawValue: uuid(300 + number)),
            profileID: profile.id,
            learningMode: mode,
            localDay: day,
            runKind: kind,
            points: 80,
            stars: QuestStars(earned: [.completion]),
            completedAt: Date(timeIntervalSince1970: TimeInterval(number))
        )
    }

    private func qualifyingCompletions(
        profile: KidProfile,
        localDays: [LocalDay]
    ) -> [DailyQuestCompletion] {
        localDays.enumerated().flatMap { index, localDay in
            [
                completion(
                    profile: profile,
                    number: index * 2 + 1,
                    mode: .read,
                    day: localDay
                ),
                completion(
                    profile: profile,
                    number: index * 2 + 2,
                    mode: .write,
                    day: localDay
                ),
            ]
        }
    }

    private func day(month: Int, day: Int) throws -> LocalDay {
        try LocalDay(year: 2026, month: month, day: day)
    }

    private func rewardGrant(
        profile: KidProfile,
        item: RewardCatalogItem,
        number: Int
    ) -> RewardGrant {
        let completionID = DailyQuestCompletionID(rawValue: uuid(400 + number))
        return RewardGrant(
            id: RewardGrantID(rawValue: uuid(500 + number)),
            key: RewardGrantKey(
                profileID: profile.id,
                world: .moonpetalKingdom,
                localDay: try! LocalDay(year: 2026, month: 7, day: number),
                learningMode: number.isMultiple(of: 2) ? .read : .write
            ),
            dailyPlanID: QuestID(rawValue: uuid(600 + number)),
            completionID: completionID,
            item: item,
            grantedAt: Date(timeIntervalSince1970: TimeInterval(number))
        )
    }

    private func uuid(_ number: Int) -> UUID {
        UUID(
            uuidString: String(
                format: "A5000000-0000-0000-0000-%012X",
                number
            )
        )!
    }
}
