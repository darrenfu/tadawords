import TadaWordsDomain
import XCTest

@testable import TadaWordsFeatures

final class ResponsiveLayoutPolicyTests: XCTestCase {
    func testProfileChooserUsesCompactLayoutOnlyForCompactHeight() {
        XCTAssertEqual(
            ProfileChooserLayoutMode.resolve(hasCompactHeight: true),
            .compactLandscape
        )
        XCTAssertEqual(
            ProfileChooserLayoutMode.resolve(hasCompactHeight: false),
            .standard
        )
    }

    func testQuestResultUsesCompactLayoutOnlyForCompactHeight() {
        XCTAssertEqual(
            QuestResultLayoutMode.resolve(hasCompactHeight: true),
            .compactLandscape
        )
        XCTAssertEqual(
            QuestResultLayoutMode.resolve(hasCompactHeight: false),
            .standard
        )
    }

    func testNewPlayerFormUsesKeyboardSafeCompactLandscapeLayout() {
        XCTAssertEqual(
            NewPlayerLayoutMode.resolve(hasCompactHeight: true),
            .compactLandscape
        )
        XCTAssertEqual(
            NewPlayerLayoutMode.resolve(hasCompactHeight: false),
            .standard
        )
    }

    func testLastPlayedBadgeOnlyMatchesTheRememberedProfile() {
        let rememberedID = ProfileID()
        let otherID = ProfileID()

        XCTAssertTrue(
            ProfileChooserPresentation.isLastPlayed(
                rememberedID,
                rememberedProfileID: rememberedID
            )
        )
        XCTAssertFalse(
            ProfileChooserPresentation.isLastPlayed(
                otherID,
                rememberedProfileID: rememberedID
            )
        )
        XCTAssertFalse(
            ProfileChooserPresentation.isLastPlayed(
                rememberedID,
                rememberedProfileID: nil
            )
        )
    }
}
