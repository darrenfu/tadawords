import Foundation
import TadaWordsDomain
import XCTest

final class ProfileAvatarTests: XCTestCase {
    func testStarterCatalogUsesCanonicalZodiacOrderAndUniqueAssets() throws {
        XCTAssertEqual(
            StarterProfileAvatar.zodiac.map(\.id),
            [
                "rat", "ox", "tiger", "rabbit", "dragon", "snake",
                "horse", "goat", "monkey", "rooster", "dog", "pig",
            ]
        )
        XCTAssertEqual(Set(StarterProfileAvatar.zodiac.map(\.id)).count, 12)
        XCTAssertEqual(
            Set(StarterProfileAvatar.zodiac.compactMap(\.imageAssetName)).count,
            12
        )
        XCTAssertTrue(
            StarterProfileAvatar.zodiac.allSatisfy { $0.imageAssetName != nil }
        )
    }

    func testLegacyStarterIDsRemainReadableWithoutReturningToPicker() {
        XCTAssertEqual(
            StarterProfileAvatar.option(for: "hare")?.name,
            "Bunny"
        )
        XCTAssertFalse(StarterProfileAvatar.zodiac.map(\.id).contains("hare"))
        XCTAssertEqual(
            ProfileAvatar.cartoonAnimal(assetID: "fox")
                .starterProfileAvatar?.fallbackSystemImageName,
            "pawprint.fill"
        )
    }

    func testZodiacPickerUsesExactlyTwoRowsOfSix() {
        XCTAssertEqual(StarterProfileAvatar.pickerColumnCount, 6)
        XCTAssertEqual(
            StarterProfileAvatar.zodiac.count,
            StarterProfileAvatar.pickerColumnCount * 2
        )
    }

    func testEmbeddedPhotoRoundTripsPreparedImageData() {
        let data = Data([0, 1, 2, 3, 254, 255])

        let avatar = ProfileAvatar.embeddedPhoto(
            data: data,
            source: .photoLibrary
        )

        XCTAssertEqual(avatar.embeddedPhotoData, data)
    }

    func testAnimalAvatarDoesNotExposePhotoData() {
        XCTAssertNil(
            ProfileAvatar.cartoonAnimal(assetID: "hare").embeddedPhotoData
        )
    }

    func testSelectedCartoonIconKeepsSourcePhotoAvailable() throws {
        let photoData = Data([8, 6, 7, 5, 3, 0, 9])
        let profile = KidProfile(
            displayName: "Mia",
            avatar: .embeddedPhoto(data: photoData, source: .camera),
            selectedWorld: .moonpetalKingdom,
            selectedCartoonIconAssetID: "hare",
            createdAt: Date(timeIntervalSince1970: 100)
        )

        let roundTripped = try JSONDecoder().decode(
            KidProfile.self,
            from: JSONEncoder().encode(profile)
        )

        XCTAssertEqual(roundTripped.avatar.embeddedPhotoData, photoData)
        XCTAssertEqual(
            roundTripped.displayAvatar,
            .cartoonAnimal(assetID: "hare")
        )
    }

    func testSelectedTreasureAvatarRoundTripsAndKeepsSourcePhoto() throws {
        let photoData = Data([4, 2, 4, 2])
        let rewardItemID = RewardItemID(
            rawValue: "moonpetalKingdom.starlight-tiara"
        )
        let profile = KidProfile(
            displayName: "Mia",
            avatar: .embeddedPhoto(data: photoData, source: .camera),
            selectedWorld: .moonpetalKingdom,
            selectedCartoonIconAssetID: "hare",
            selectedTreasureAvatar: TreasureAvatarSelection(
                rewardItemID: rewardItemID,
                iconAssetID: "crown.fill"
            ),
            createdAt: Date(timeIntervalSince1970: 100)
        )

        let roundTripped = try JSONDecoder().decode(
            KidProfile.self,
            from: JSONEncoder().encode(profile)
        )

        XCTAssertEqual(roundTripped.avatar.embeddedPhotoData, photoData)
        XCTAssertNil(roundTripped.selectedCartoonIconAssetID)
        XCTAssertEqual(
            roundTripped.displayAvatar,
            .treasure(
                rewardItemID: rewardItemID,
                iconAssetID: "crown.fill"
            )
        )
    }
}
