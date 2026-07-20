import Foundation
import TadaWordsDomain
import XCTest

final class ProfileErasureTransportEvidenceTests: XCTestCase {
    func testOnlyExactCompletedDispositionBecomesCompletionReceipt() {
        let profileID = ProfileID()
        let acknowledgement = FamilySyncChangeAcknowledgement(
            key: FamilySyncChangeKey(
                profileID: profileID,
                recordName: "profile-\(profileID)"
            ),
            revision: FamilySyncLogicalRevision(
                counter: 4,
                deviceID: "privacy-minimal-device"
            ),
            operation: .save
        )
        let failure = FamilySyncChangeAcknowledgement(
            key: FamilySyncChangeKey(
                profileID: ProfileID(),
                recordName: "profile-failed"
            ),
            revision: FamilySyncLogicalRevision(
                counter: 2,
                deviceID: "privacy-minimal-device"
            ),
            operation: .save
        )

        let result = FamilySyncTransportResult(
            profileErasureDispositions: [
                ProfileErasureTransportDisposition(
                    change: acknowledgement,
                    route: .owner,
                    outcome: .completed
                ),
                ProfileErasureTransportDisposition(
                    change: failure,
                    route: .participant,
                    outcome: .failed(category: .connectivity, retryAfter: 30)
                ),
            ]
        )

        XCTAssertEqual(
            result.profileErasureReceipts,
            [
                ProfileErasureTransportReceipt(
                    acknowledgement: acknowledgement,
                    route: .owner
                )
            ]
        )
    }
}
