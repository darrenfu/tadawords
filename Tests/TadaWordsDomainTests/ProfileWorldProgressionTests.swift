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
            "ageYears", "updatedAt",
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
        XCTAssertEqual(decoded.updatedAt, createdAt)
    }

    func testWorldsUnlockAtThreeAndEightTodayCompletionsOnly() {
        let profile = makeProfile()
        let twoTodayAndPractice = [
            completion(profile: profile, number: 1, kind: .today),
            completion(profile: profile, number: 2, kind: .today),
            completion(profile: profile, number: 3, kind: .practiceAgain),
        ]
        XCTAssertEqual(
            WorldProgression(
                profile: profile,
                completions: twoTodayAndPractice
            ).unlockedWorlds,
            [.moonpetalKingdom]
        )

        let three =
            twoTodayAndPractice + [
                completion(profile: profile, number: 4, kind: .today)
            ]
        XCTAssertEqual(
            WorldProgression(profile: profile, completions: three).unlockedWorlds,
            [.moonpetalKingdom, .buildItBay]
        )

        let eight = (1...8).map {
            completion(profile: profile, number: 20 + $0, kind: .today)
        }
        XCTAssertEqual(
            WorldProgression(profile: profile, completions: eight).unlockedWorlds,
            Set(WorldTheme.allCases)
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

    private func makeProfile() -> KidProfile {
        KidProfile(
            id: ProfileID(rawValue: uuid(1)),
            displayName: "Mia",
            avatar: .cartoonAnimal(assetID: "hare"),
            selectedWorld: .moonpetalKingdom,
            createdAt: Date(timeIntervalSince1970: 0)
        )
    }

    private func completion(
        profile: KidProfile,
        number: Int,
        kind: DailyQuestRunKind
    ) -> DailyQuestCompletion {
        DailyQuestCompletion(
            id: DailyQuestCompletionID(rawValue: uuid(100 + number)),
            dailyPlanID: QuestID(rawValue: uuid(200 + number)),
            runQuestID: QuestID(rawValue: uuid(300 + number)),
            profileID: profile.id,
            learningMode: number.isMultiple(of: 2) ? .read : .write,
            localDay: try! LocalDay(year: 2026, month: 7, day: 12),
            runKind: kind,
            points: 80,
            stars: QuestStars(earned: [.completion]),
            completedAt: Date(timeIntervalSince1970: TimeInterval(number))
        )
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
