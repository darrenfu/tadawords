import TadaWordsDomain
import XCTest

@testable import TadaWordsFeatures

final class TreasureCardPresentationTests: XCTestCase {
    private let item = RewardCatalogItem(
        id: RewardItemID(rawValue: "moonpetalKingdom.starlight-tiara"),
        world: .moonpetalKingdom,
        displayName: "Starlight Tiara",
        iconAssetID: "crown.fill"
    )

    func testLockedTreasureKeepsItsOwnGrayableIconUnderLockBadge() {
        let presentation = TreasureCardPresentation(
            state: RewardCollectionItemState(item: item, isCollected: false),
            selectedTreasureAvatar: nil
        )

        XCTAssertEqual(presentation.iconAssetID, "crown.fill")
        XCTAssertEqual(presentation.badgeSymbol, "lock.fill")
        XCTAssertEqual(presentation.statusText, "Locked")
        XCTAssertFalse(presentation.isCurrent)
    }

    func testCollectedTreasureCanBePresentedAsAvailableAvatar() {
        let presentation = TreasureCardPresentation(
            state: RewardCollectionItemState(item: item, isCollected: true),
            selectedTreasureAvatar: nil
        )

        XCTAssertNil(presentation.badgeSymbol)
        XCTAssertEqual(presentation.statusText, "Use as icon")
    }

    func testSelectedTreasureShowsCurrentBadge() {
        let presentation = TreasureCardPresentation(
            state: RewardCollectionItemState(item: item, isCollected: true),
            selectedTreasureAvatar: TreasureAvatarSelection(
                rewardItemID: item.id,
                iconAssetID: item.iconAssetID
            )
        )

        XCTAssertTrue(presentation.isCurrent)
        XCTAssertEqual(presentation.badgeSymbol, "checkmark.circle.fill")
        XCTAssertEqual(presentation.statusText, "Using as icon")
    }
}
