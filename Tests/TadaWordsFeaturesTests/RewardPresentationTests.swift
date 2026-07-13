import TadaWordsDomain
import XCTest

@testable import TadaWordsFeatures

final class RewardPresentationTests: XCTestCase {
    func testMoonpetalRewardUsesItsOwnCollectibleSymbol() {
        XCTAssertEqual(
            item(id: "moonpetalKingdom.cloud-carriage", world: .moonpetalKingdom)
                .presentationSymbol,
            "cloud.fill"
        )
    }

    func testBuildItRewardUsesItsOwnCollectibleSymbol() {
        XCTAssertEqual(
            item(id: "buildItBay.road-roller", world: .buildItBay).presentationSymbol,
            "road.lanes"
        )
    }

    func testPawsRewardUsesItsOwnCollectibleSymbol() {
        XCTAssertEqual(
            item(id: "pawsAndPines.bunny-burrow", world: .pawsAndPines)
                .presentationSymbol,
            "hare.fill"
        )
    }

    func testUnknownFutureRewardFallsBackToBrandSparkles() {
        XCTAssertEqual(
            item(id: "moonpetalKingdom.future-item", world: .moonpetalKingdom)
                .presentationSymbol,
            "sparkles"
        )
    }

    private func item(id: String, world: WorldTheme) -> RewardCatalogItem {
        RewardCatalogItem(
            id: RewardItemID(rawValue: id),
            world: world,
            displayName: "Test reward"
        )
    }
}
