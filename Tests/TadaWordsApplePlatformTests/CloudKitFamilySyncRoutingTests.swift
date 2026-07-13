import XCTest

@testable import TadaWordsApplePlatform

final class CloudKitFamilySyncRoutingTests: XCTestCase {
    func testOwnerWritesPrivateAndParticipantWritesSharedZone() {
        XCTAssertEqual(
            CloudKitFamilyWriteRoute.select(sharedRootAvailable: false),
            .privateOwner
        )
        XCTAssertEqual(
            CloudKitFamilyWriteRoute.select(sharedRootAvailable: true),
            .sharedParticipant
        )
    }
}
