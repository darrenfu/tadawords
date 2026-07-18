import Foundation
import TadaWordsDomain
import XCTest

final class FamilySyncEnvelopeTests: XCTestCase {
    func testEnvelopeRoundTripsVersionedRecordAndChecksum() throws {
        let source = makeRecord(payload: Data("cat".utf8)).assigning(
            revision: FamilySyncLogicalRevision(counter: 7, deviceID: "device-b")
        )

        let decoded = try FamilySyncEnvelope(record: source).decodedRecord()

        XCTAssertEqual(decoded, source)
        XCTAssertEqual(decoded.payloadSize, 3)
        XCTAssertEqual(
            decoded.payloadChecksum,
            FamilySyncRecord.checksum(for: Data("cat".utf8))
        )
    }

    func testEnvelopeRejectsFutureSchemaChecksumMismatchAndIdentityMismatch() {
        let source = makeRecord(payload: Data("cat".utf8))
        assertCompatibilityError(
            FamilySyncRecord(
                recordName: source.recordName,
                profileID: source.profileID,
                kind: source.kind,
                payload: source.payload,
                updatedAt: source.updatedAt,
                deviceID: source.deviceID,
                schemaVersion: FamilySyncRecord.currentSchemaVersion + 1
            ),
            equals: .unsupportedSchemaVersion(
                FamilySyncRecord.currentSchemaVersion + 1
            )
        )
        assertCompatibilityError(
            FamilySyncRecord(
                recordName: source.recordName,
                profileID: source.profileID,
                kind: source.kind,
                payload: source.payload,
                updatedAt: source.updatedAt,
                deviceID: source.deviceID,
                payloadChecksum: "not-a-checksum"
            ),
            equals: .checksumMismatch
        )
        assertCompatibilityError(
            FamilySyncRecord(
                recordName: source.recordName,
                profileID: source.profileID,
                kind: source.kind,
                payload: source.payload,
                updatedAt: source.updatedAt,
                deviceID: "device-a",
                logicalRevision: FamilySyncLogicalRevision(
                    counter: 1,
                    deviceID: "device-b"
                )
            ),
            equals: .invalidIdentity
        )
    }

    func testEnvelopeRejectsOversizedPayloadAndUnknownKind() throws {
        let payload = Data(
            repeating: 1,
            count: FamilySyncRecord.maximumPayloadSize + 1
        )
        assertCompatibilityError(
            makeRecord(payload: payload),
            equals: .payloadTooLarge(
                payload.count,
                maximum: FamilySyncRecord.maximumPayloadSize
            )
        )

        let source = makeRecord(payload: Data("cat".utf8))
        let data = try JSONEncoder().encode(FamilySyncEnvelope(record: source))
        var object = try XCTUnwrap(
            JSONSerialization.jsonObject(with: data) as? [String: Any]
        )
        object["kindIdentifier"] = "future-kind"
        let modified = try JSONSerialization.data(withJSONObject: object)
        let envelope = try JSONDecoder().decode(
            FamilySyncEnvelope.self,
            from: modified
        )
        XCTAssertThrowsError(try envelope.decodedRecord()) { error in
            XCTAssertEqual(
                error as? FamilySyncEnvelopeError,
                .unknownRecordKind("future-kind")
            )
        }
    }

    func testLogicalRevisionSaturatesAndFingerprintIgnoresJournalRevision() {
        let source = makeRecord(payload: Data("cat".utf8))
        XCTAssertEqual(
            FamilySyncLogicalRevision.next(
                after: [
                    FamilySyncLogicalRevision(
                        counter: .max,
                        deviceID: "older"
                    )
                ],
                deviceID: "newer"
            ).counter,
            .max
        )
        XCTAssertEqual(
            FamilySyncRecordSetFingerprint(records: [source]),
            FamilySyncRecordSetFingerprint(
                records: [
                    source.assigning(
                        revision: FamilySyncLogicalRevision(
                            counter: 99,
                            deviceID: "another-device"
                        )
                    )
                ]
            )
        )
    }

    private func makeRecord(payload: Data) -> FamilySyncRecord {
        let profileID = ProfileID(
            rawValue: UUID(uuidString: "AAAAAAAA-BBBB-CCCC-DDDD-EEEEEEEEEEEE")!
        )
        return FamilySyncRecord(
            recordName: "profile-\(profileID)",
            profileID: profileID,
            kind: .profile,
            payload: payload,
            updatedAt: Date(timeIntervalSince1970: 10),
            deviceID: "device-a"
        )
    }

    private func assertCompatibilityError(
        _ record: FamilySyncRecord,
        equals expected: FamilySyncEnvelopeError,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        XCTAssertThrowsError(
            try record.validateCompatibility(),
            file: file,
            line: line
        ) { error in
            XCTAssertEqual(
                error as? FamilySyncEnvelopeError,
                expected,
                file: file,
                line: line
            )
        }
    }
}
