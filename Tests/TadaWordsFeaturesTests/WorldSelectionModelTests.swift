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

        await model.refreshWorldProgressAndWait()
        await model.selectWorldAndWait(.buildItBay)
        let persisted = try await repository.profile(id: profile.id)

        XCTAssertEqual(model.selectedProfile?.selectedWorld, .buildItBay)
        XCTAssertEqual(persisted?.selectedWorld, .buildItBay)
        XCTAssertEqual(persisted?.updatedAt, Date(timeIntervalSince1970: 200))

        await model.selectWorldAndWait(.pawsAndPines)
        XCTAssertEqual(model.selectedProfile?.selectedWorld, .buildItBay)
    }
}

private struct WorldSelectionClock: AppClock {
    let now: Date
}
