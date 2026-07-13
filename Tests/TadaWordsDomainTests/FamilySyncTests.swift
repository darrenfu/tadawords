import Foundation
import TadaWordsDomain
import XCTest

final class FamilySyncTests: XCTestCase {
    func testConflictResolutionUsesRevisionThenDeviceAndDeletion() {
        let profileID = ProfileID()
        let date = Date(timeIntervalSince1970: 100)
        let older = record(
            profileID: profileID,
            payload: Data("old".utf8),
            updatedAt: date.addingTimeInterval(-1),
            deviceID: "z"
        )
        let newer = record(
            profileID: profileID,
            payload: Data("new".utf8),
            updatedAt: date,
            deviceID: "a"
        )
        XCTAssertEqual(
            FamilySyncConflictResolver.resolved(local: older, remote: newer),
            newer
        )

        let firstDevice = record(
            profileID: profileID,
            payload: Data("a".utf8),
            updatedAt: date,
            deviceID: "a"
        )
        let lastDevice = record(
            profileID: profileID,
            payload: Data("z".utf8),
            updatedAt: date,
            deviceID: "z"
        )
        XCTAssertEqual(
            FamilySyncConflictResolver.resolved(
                local: firstDevice,
                remote: lastDevice
            ),
            lastDevice
        )

        let deletion = FamilySyncRecord(
            recordName: firstDevice.recordName,
            profileID: profileID,
            kind: .profileDeletion,
            payload: Data(),
            updatedAt: date,
            deviceID: "a",
            isDeleted: true
        )
        XCTAssertEqual(
            FamilySyncConflictResolver.resolved(local: lastDevice, remote: deletion),
            deletion
        )
    }

    private func record(
        profileID: ProfileID,
        payload: Data,
        updatedAt: Date,
        deviceID: String
    ) -> FamilySyncRecord {
        FamilySyncRecord(
            recordName: "profile-\(profileID)",
            profileID: profileID,
            kind: .profile,
            payload: payload,
            updatedAt: updatedAt,
            deviceID: deviceID
        )
    }
}
