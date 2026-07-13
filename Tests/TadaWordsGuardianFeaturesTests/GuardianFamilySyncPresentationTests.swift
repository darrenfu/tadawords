import Foundation
import TadaWordsDomain
import XCTest

@testable import TadaWordsGuardianFeatures

final class GuardianFamilySyncPresentationTests: XCTestCase {
    func testDeviceOnlyModeHidesEveryCloudControl() {
        let presentation = GuardianFamilySyncPresentation(
            status: .deviceOnly(
                message: "This version keeps learning data on this device."
            ),
            isEnabled: false
        )

        XCTAssertEqual(presentation.navigationTitle, "Device storage")
        XCTAssertEqual(presentation.title, "This device only")
        XCTAssertFalse(presentation.message.localizedCaseInsensitiveContains("icloud"))
        XCTAssertFalse(presentation.showsPreferenceToggle)
        XCTAssertFalse(presentation.showsSyncAction)
        XCTAssertFalse(presentation.showsInvitationActions)
    }

    func testOptedOutICloudModeShowsOnlyExplicitPreferenceControl() {
        let presentation = GuardianFamilySyncPresentation(
            status: .optedOut(message: "Family sync is off."),
            isEnabled: false
        )

        XCTAssertEqual(presentation.navigationTitle, "Family sync")
        XCTAssertEqual(presentation.title, "Family sync is off")
        XCTAssertTrue(presentation.showsPreferenceToggle)
        XCTAssertFalse(presentation.showsSyncAction)
        XCTAssertFalse(presentation.showsInvitationActions)
    }

    func testInvitationsAppearOnlyAfterEnabledSyncSucceeds() {
        let unavailable = GuardianFamilySyncPresentation(
            status: .iCloudUnavailable(message: "Sign in to iCloud."),
            isEnabled: true
        )
        let synced = GuardianFamilySyncPresentation(
            status: .synced(at: Date(timeIntervalSince1970: 1_735_689_600)),
            isEnabled: true
        )

        XCTAssertTrue(unavailable.showsSyncAction)
        XCTAssertFalse(unavailable.showsInvitationActions)
        XCTAssertTrue(synced.showsSyncAction)
        XCTAssertTrue(synced.showsInvitationActions)
    }
}
