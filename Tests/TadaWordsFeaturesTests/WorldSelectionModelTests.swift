import Foundation
import TadaWordsContent
import TadaWordsDomain
import XCTest

@testable import TadaWordsFeatures

@MainActor
final class WorldSelectionModelTests: XCTestCase {
    func testUnlockedWorldSelectionPersistsAndLockedWorldCannotBeSelected()
        async throws
    {
        let repository = InMemoryKidProfileRepository()
        let profile = KidProfile(
            displayName: "Mia",
            avatar: .cartoonAnimal(assetID: "hare"),
            selectedWorld: .moonpetalKingdom,
            guardianUnlockedWorlds: [.buildItBay],
            createdAt: Date(timeIntervalSince1970: 100)
        )
        try await repository.save(profile)
        let model = TadaWordsAppModel(
            profiles: [profile],
            dailyQuestCoordinator: DailyQuestCoordinator(
                repository: InMemoryDailyQuestRepository(),
                timeZone: TimeZone(secondsFromGMT: 0)!
            ),
            clock: WorldSelectionClock(now: Date(timeIntervalSince1970: 200)),
            initialProfileID: profile.id,
            profileRepository: repository
        )
        model.selectProfile(profile)

        await model.refreshWorldProgressAndWait()
        await model.selectWorldAndWait(.buildItBay)
        let persisted = try await repository.profile(id: profile.id)

        XCTAssertEqual(model.selectedProfile?.selectedWorld, .buildItBay)
        XCTAssertEqual(persisted?.selectedWorld, .buildItBay)
        XCTAssertEqual(persisted?.updatedAt, Date(timeIntervalSince1970: 200))

        await model.selectWorldAndWait(.pawsAndPines)
        XCTAssertEqual(model.selectedProfile?.selectedWorld, .buildItBay)
    }

    func testEarnedIconSelectionPersistsWithoutReplacingPhoto() async throws {
        let repository = InMemoryKidProfileRepository()
        let photoData = Data([1, 3, 3, 7])
        let profile = KidProfile(
            displayName: "Mia",
            avatar: .embeddedPhoto(data: photoData, source: .photoLibrary),
            selectedWorld: .moonpetalKingdom,
            createdAt: Date(timeIntervalSince1970: 100)
        )
        try await repository.save(profile)
        let model = TadaWordsAppModel(
            profiles: [profile],
            dailyQuestCoordinator: DailyQuestCoordinator(
                repository: InMemoryDailyQuestRepository(),
                timeZone: TimeZone(secondsFromGMT: 0)!
            ),
            clock: WorldSelectionClock(now: Date(timeIntervalSince1970: 200)),
            initialProfileID: profile.id,
            profileRepository: repository
        )
        model.selectProfile(profile)

        await model.refreshWorldProgressAndWait()
        await model.selectCartoonIconAndWait("hare")
        var storedProfile = try await repository.profile(id: profile.id)
        var persisted = try XCTUnwrap(storedProfile)
        XCTAssertEqual(persisted.selectedCartoonIconAssetID, "hare")
        XCTAssertEqual(persisted.avatar.embeddedPhotoData, photoData)
        XCTAssertEqual(
            model.selectedProfile?.displayAvatar,
            .cartoonAnimal(assetID: "hare")
        )

        await model.selectCartoonIconAndWait("dog")
        storedProfile = try await repository.profile(id: profile.id)
        persisted = try XCTUnwrap(storedProfile)
        XCTAssertEqual(persisted.selectedCartoonIconAssetID, "hare")

        await model.selectOriginalAvatarAndWait()
        storedProfile = try await repository.profile(id: profile.id)
        persisted = try XCTUnwrap(storedProfile)
        XCTAssertNil(persisted.selectedCartoonIconAssetID)
        XCTAssertEqual(persisted.displayAvatar.embeddedPhotoData, photoData)
    }

    func testOnlyCollectedTreasureCanBecomeAvatarAndAnimalSelectionReplacesIt()
        async throws
    {
        let profileRepository = InMemoryKidProfileRepository()
        let dailyQuestRepository = InMemoryDailyQuestRepository()
        let photoData = Data([9, 8, 7, 6])
        let profile = KidProfile(
            displayName: "Mia",
            avatar: .embeddedPhoto(data: photoData, source: .photoLibrary),
            selectedWorld: .moonpetalKingdom,
            createdAt: Date(timeIntervalSince1970: 100)
        )
        try await profileRepository.save(profile)

        let completedAt = Date(timeIntervalSince1970: 200)
        let localDay = LocalDay(
            date: completedAt,
            timeZone: TimeZone(secondsFromGMT: 0)!
        )
        let questPlan = QuestPlan(
            profileID: profile.id,
            configuration: .defaultRead,
            reviewWordIDs: [],
            newWordIDs: [],
            createdAt: completedAt
        )
        let dailyPlan = DailyQuestPlan(localDay: localDay, questPlan: questPlan)
        _ = try await dailyQuestRepository.createPlanIfAbsent(dailyPlan)
        let completion = DailyQuestCompletion(
            dailyPlanID: dailyPlan.id,
            runQuestID: dailyPlan.id,
            profileID: profile.id,
            learningMode: .read,
            localDay: localDay,
            runKind: .today,
            points: 10,
            stars: QuestStars(earned: [.completion]),
            completedAt: completedAt
        )
        let catalogItems = ThemedRewardCatalog().items(for: .moonpetalKingdom)
        let collectedItem = try XCTUnwrap(catalogItems.first)
        let lockedItem = try XCTUnwrap(catalogItems.dropFirst().first)
        let rewardGrant = RewardGrant(
            key: RewardGrantKey(
                profileID: profile.id,
                world: .moonpetalKingdom,
                localDay: localDay,
                learningMode: .read
            ),
            dailyPlanID: dailyPlan.id,
            completionID: completion.id,
            item: collectedItem,
            grantedAt: completedAt
        )
        _ = try await dailyQuestRepository.recordCompletion(
            completion,
            proposedRewardGrant: rewardGrant
        )

        let model = TadaWordsAppModel(
            profiles: [profile],
            dailyQuestCoordinator: DailyQuestCoordinator(
                repository: dailyQuestRepository,
                timeZone: TimeZone(secondsFromGMT: 0)!
            ),
            clock: WorldSelectionClock(now: completedAt),
            initialProfileID: profile.id,
            profileRepository: profileRepository
        )
        model.selectProfile(profile)
        await model.refreshWorldProgressAndWait()

        await model.selectTreasureAvatarAndWait(lockedItem)
        XCTAssertNil(model.selectedProfile?.selectedTreasureAvatar)

        await model.selectTreasureAvatarAndWait(collectedItem)
        var storedProfile = try await profileRepository.profile(id: profile.id)
        var persisted = try XCTUnwrap(storedProfile)
        XCTAssertEqual(
            persisted.selectedTreasureAvatar,
            TreasureAvatarSelection(
                rewardItemID: collectedItem.id,
                iconAssetID: collectedItem.iconAssetID
            )
        )
        XCTAssertEqual(persisted.avatar.embeddedPhotoData, photoData)

        await model.selectCartoonIconAndWait("hare")
        storedProfile = try await profileRepository.profile(id: profile.id)
        persisted = try XCTUnwrap(storedProfile)
        XCTAssertNil(persisted.selectedTreasureAvatar)
        XCTAssertEqual(persisted.selectedCartoonIconAssetID, "hare")
        XCTAssertEqual(persisted.avatar.embeddedPhotoData, photoData)
    }
}

private struct WorldSelectionClock: AppClock {
    let now: Date
}
