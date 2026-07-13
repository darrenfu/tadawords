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
}
