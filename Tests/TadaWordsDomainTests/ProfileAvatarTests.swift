import Foundation
import TadaWordsDomain
import XCTest

final class ProfileAvatarTests: XCTestCase {
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
