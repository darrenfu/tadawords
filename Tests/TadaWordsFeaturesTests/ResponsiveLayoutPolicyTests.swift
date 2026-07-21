import TadaWordsDesignSystem
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

    func testCompactProfileChooserKeepsNewKidWithAtMostThreeProfiles() {
        XCTAssertEqual(
            ProfileChooserCompactGridPolicy.itemCounts(profileCount: 0),
            [1]
        )
        XCTAssertEqual(
            ProfileChooserCompactGridPolicy.itemCounts(profileCount: 1),
            [2]
        )
        XCTAssertEqual(
            ProfileChooserCompactGridPolicy.itemCounts(profileCount: 3),
            [4]
        )
        XCTAssertEqual(
            ProfileChooserCompactGridPolicy.itemCounts(profileCount: 4),
            [4, 1]
        )
        XCTAssertEqual(
            ProfileChooserCompactGridPolicy.itemCounts(profileCount: 7),
            [4, 3, 1]
        )
    }

    func testCompactProfileChooserNeverPlacesFourProfilesInOneRow() {
        for profileCount in 0...20 {
            let itemCounts = ProfileChooserCompactGridPolicy.itemCounts(
                profileCount: profileCount
            )
            XCTAssertLessThanOrEqual(itemCounts[0], 4)
            XCTAssertTrue(itemCounts.dropFirst().allSatisfy { $0 <= 3 })
        }
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

    func testLastPlayedProfileCardGetsStaticEmphasisOnly() {
        XCTAssertEqual(
            ProfileChooserPresentation.cardScale(isLastPlayed: true),
            TadaChildScaleTokens.Profile.lastPlayedScale
        )
        XCTAssertEqual(
            ProfileChooserPresentation.cardScale(isLastPlayed: false),
            1
        )
        XCTAssertEqual(
            ProfileChooserPresentation.cardZIndex(isLastPlayed: true),
            1
        )
        XCTAssertEqual(
            ProfileChooserPresentation.cardZIndex(isLastPlayed: false),
            0
        )
    }
}
