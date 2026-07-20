@preconcurrency import CloudKit
import Foundation
import TadaWordsDomain
import XCTest

@testable import TadaWordsApplePlatform

final class CloudKitFamilyMetadataSnapshotValidationTests: XCTestCase {
    func testSchemaV2DuplicateProfileTerminalAndActiveBindingsFailClosed()
        throws
    {
        let fixture = try CloudKitMetadataSnapshotValidationFixture()
        defer { fixture.remove() }
        let profileID = ProfileID()
        let store = try fixture.configuredStore(named: "duplicate-profile")
        try store.save(
            binding: fixture.ownerBinding(
                profileID: profileID,
                zoneName: "duplicate-profile-zone"
            )
        )

        let corruptedBytes = try fixture.mutateSnapshot(named: "duplicate-profile") {
            snapshot in
            let bindings = try XCTUnwrap(
                snapshot["bindings"] as? [[String: Any]]
            )
            let active = try XCTUnwrap(bindings.first)
            var terminal = active
            terminal["state"] = ProfileCloudBindingState.ownerDeleted.rawValue
            snapshot["bindings"] = [terminal, active]
        }

        try fixture.assertFailsClosed(
            named: "duplicate-profile",
            originalBytes: corruptedBytes
        )
    }

    func testSchemaV2DuplicateNonNilZoneAcrossProfilesFailsClosed() throws {
        let fixture = try CloudKitMetadataSnapshotValidationFixture()
        defer { fixture.remove() }
        let store = try fixture.configuredStore(named: "duplicate-zone")
        try store.save(
            binding: fixture.ownerBinding(
                profileID: ProfileID(),
                zoneName: "first-zone"
            )
        )
        try store.save(
            binding: fixture.ownerBinding(
                profileID: ProfileID(),
                zoneName: "second-zone"
            )
        )

        let corruptedBytes = try fixture.mutateSnapshot(named: "duplicate-zone") {
            snapshot in
            var bindings = try XCTUnwrap(
                snapshot["bindings"] as? [[String: Any]]
            )
            XCTAssertEqual(bindings.count, 2)
            let first = bindings[0]
            bindings[1]["zoneName"] = first["zoneName"]
            bindings[1]["ownerName"] = first["ownerName"]
            snapshot["bindings"] = bindings
        }

        try fixture.assertFailsClosed(
            named: "duplicate-zone",
            originalBytes: corruptedBytes
        )
    }

    func testSchemaV2ActiveOwnerMissingRootFailsClosed() throws {
        let fixture = try CloudKitMetadataSnapshotValidationFixture()
        defer { fixture.remove() }
        let store = try fixture.configuredStore(named: "missing-root")
        try store.save(
            binding: fixture.ownerBinding(
                profileID: ProfileID(),
                zoneName: "missing-root-zone"
            )
        )

        let corruptedBytes = try fixture.mutateSnapshot(named: "missing-root") {
            snapshot in
            var bindings = try XCTUnwrap(
                snapshot["bindings"] as? [[String: Any]]
            )
            bindings[0].removeValue(forKey: "rootRecordName")
            snapshot["bindings"] = bindings
        }

        try fixture.assertFailsClosed(
            named: "missing-root",
            originalBytes: corruptedBytes
        )
    }

    func testSchemaV2ActiveOwnerMissingAccountProvenanceFailsClosed() throws {
        let fixture = try CloudKitMetadataSnapshotValidationFixture()
        defer { fixture.remove() }
        let store = try fixture.configuredStore(named: "missing-account")
        try store.save(
            binding: fixture.ownerBinding(
                profileID: ProfileID(),
                zoneName: "missing-account-zone"
            )
        )

        let corruptedBytes = try fixture.mutateSnapshot(named: "missing-account") {
            snapshot in
            var bindings = try XCTUnwrap(
                snapshot["bindings"] as? [[String: Any]]
            )
            bindings[0].removeValue(forKey: "originAccountRecordName")
            snapshot["bindings"] = bindings
        }

        try fixture.assertFailsClosed(
            named: "missing-account",
            originalBytes: corruptedBytes
        )
    }

    func testSchemaV2OwnerWithParticipantRouteFailsClosed() throws {
        let fixture = try CloudKitMetadataSnapshotValidationFixture()
        defer { fixture.remove() }
        let store = try fixture.configuredStore(named: "wrong-route")
        try store.save(
            binding: fixture.ownerBinding(
                profileID: ProfileID(),
                zoneName: "wrong-route-zone"
            )
        )

        let corruptedBytes = try fixture.mutateSnapshot(named: "wrong-route") {
            snapshot in
            var bindings = try XCTUnwrap(
                snapshot["bindings"] as? [[String: Any]]
            )
            bindings[0]["originErasureRoute"] =
                ProfileErasureRoute.participant.rawValue
            snapshot["bindings"] = bindings
        }

        try fixture.assertFailsClosed(
            named: "wrong-route",
            originalBytes: corruptedBytes
        )
    }
}

private struct CloudKitMetadataSnapshotValidationFixture {
    private static let accountRecordName = "snapshot-validation-account"

    let directory: URL

    init() throws {
        directory = FileManager.default.temporaryDirectory.appendingPathComponent(
            "TadaCloudMetadataValidation-\(UUID().uuidString)",
            isDirectory: true
        )
        try FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true
        )
    }

    func configuredStore(named name: String) throws -> CloudKitFamilyMetadataStore {
        let store = CloudKitFamilyMetadataStore(snapshotURL: metadataURL(named: name))
        try store.confirm(accountRecordName: Self.accountRecordName)
        return store
    }

    func ownerBinding(
        profileID: ProfileID,
        zoneName: String
    ) -> ProfileCloudBinding {
        ProfileCloudBinding(
            profileID: profileID,
            state: .privateOwner,
            zoneName: zoneName,
            ownerName: CKCurrentUserDefaultName,
            rootRecordName: "root-\(profileID.rawValue.uuidString)"
        )
    }

    func mutateSnapshot(
        named name: String,
        _ mutation: (inout [String: Any]) throws -> Void
    ) throws -> Data {
        let url = metadataURL(named: name)
        let data = try Data(contentsOf: url)
        var snapshot = try XCTUnwrap(
            try JSONSerialization.jsonObject(with: data) as? [String: Any]
        )
        try mutation(&snapshot)
        let corruptedBytes = try JSONSerialization.data(
            withJSONObject: snapshot,
            options: [.sortedKeys]
        )
        try corruptedBytes.write(to: url, options: .atomic)
        return corruptedBytes
    }

    func assertFailsClosed(
        named name: String,
        originalBytes: Data,
        file: StaticString = #filePath,
        line: UInt = #line
    ) throws {
        let url = metadataURL(named: name)
        let restarted = CloudKitFamilyMetadataStore(snapshotURL: url)

        XCTAssertThrowsError(
            try restarted.accountGate(
                currentAccountRecordName: Self.accountRecordName
            ),
            file: file,
            line: line
        ) { error in
            XCTAssertEqual(
                error as? CloudKitFamilyPersistenceError,
                .corruptMetadata,
                file: file,
                line: line
            )
        }
        XCTAssertEqual(
            try Data(contentsOf: url),
            originalBytes,
            file: file,
            line: line
        )
    }

    func metadataURL(named name: String) -> URL {
        directory.appendingPathComponent("\(name).json")
    }

    func remove() {
        try? FileManager.default.removeItem(at: directory)
    }
}
