import Foundation
import TadaWordsContent
import TadaWordsDomain
import XCTest

final class FamilySyncJournalRepositoryTests: XCTestCase {
    func testUnadoptedProfileIDsClassifyEachJournalEntryIndependently()
        async throws
    {
        let fixture = try JournalFixture()
        defer { fixture.remove() }
        let repository = LocalJSONFamilySyncJournalRepository(
            snapshotURL: fixture.url
        )
        let child = fixture.record(
            "ACCOUNT_A_CHILD_BYTES",
            suffix: "word",
            profileID: fixture.profileID
        )
        let deletion = try fixture.profileDeletionRecord()
        _ = try await repository.reconcileLocalRecords(
            [child, deletion],
            deviceID: "device-a",
            now: fixture.now
        )

        let profileIDs = try await repository.unadoptedProfileIDs()
        XCTAssertEqual(
            profileIDs,
            [fixture.profileID],
            "A deletion must not hide a child entry for the same Profile."
        )

        try await repository.discardUnadoptedProfileState()
        let retainedProfileIDs = try await repository.unadoptedProfileIDs()
        XCTAssertTrue(retainedProfileIDs.isEmpty)
    }

    func testDeletionKeyDoesNotBlessStaleAcknowledgementOrOutboxMetadata()
        async throws
    {
        let fixture = try JournalFixture()
        defer { fixture.remove() }
        let deletionRecord = try fixture.profileDeletionRecord().assigning(
            revision: FamilySyncLogicalRevision(
                counter: 2,
                deviceID: "device-a"
            )
        )
        let staleProfileRecord = fixture.record("STALE_PROFILE_BYTES").assigning(
            revision: FamilySyncLogicalRevision(
                counter: 1,
                deviceID: "device-a"
            )
        )
        let snapshot = FamilySyncJournalSnapshot(
            localManifest: [FamilySyncManifestEntry(record: deletionRecord)],
            acknowledgedManifest: [
                FamilySyncManifestEntry(record: staleProfileRecord)
            ],
            outbox: [
                FamilySyncOutboxEntry(
                    key: FamilySyncChangeKey(
                        profileID: fixture.profileID,
                        recordName: deletionRecord.recordName
                    ),
                    operation: .delete,
                    revision: staleProfileRecord.logicalRevision,
                    firstQueuedAt: fixture.now,
                    lastQueuedAt: fixture.now
                )
            ]
        )
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .secondsSince1970
        try encoder.encode(snapshot).write(to: fixture.url)
        let repository = LocalJSONFamilySyncJournalRepository(
            snapshotURL: fixture.url
        )

        let profileIDs = try await repository.unadoptedProfileIDs()
        XCTAssertEqual(profileIDs, [fixture.profileID])

        try await repository.discardUnadoptedProfileState()
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .secondsSince1970
        let persisted = try decoder.decode(
            FamilySyncJournalSnapshot.self,
            from: Data(contentsOf: fixture.url)
        )
        XCTAssertEqual(persisted.localManifest.map(\.kind), [.profileDeletion])
        XCTAssertTrue(persisted.acknowledgedManifest.isEmpty)
        XCTAssertTrue(persisted.outbox.isEmpty)
    }

    func testFirstRunRediscoveryDiscardRemovesNonterminalStateButRetainsDeletionAuthority()
        async throws
    {
        let fixture = try JournalFixture()
        defer { fixture.remove() }
        let repository = LocalJSONFamilySyncJournalRepository(
            snapshotURL: fixture.url
        )
        let unadopted = fixture.record(
            "ACCOUNT_A_PROFILE_BYTES",
            profileID: fixture.unrelatedProfileID
        )
        let deletion = try fixture.profileDeletionRecord()
        _ = try await repository.reconcileLocalRecords(
            [unadopted, deletion],
            deviceID: "device-a",
            now: fixture.now
        )
        try await repository.discardUnadoptedProfileState()

        let persisted = try JSONDecoder().decode(
            FamilySyncJournalSnapshot.self,
            from: Data(contentsOf: fixture.url)
        )
        XCTAssertEqual(persisted.localManifest.map(\.kind), [.profileDeletion])
        XCTAssertEqual(
            persisted.localManifest.map(\.key.profileID),
            [fixture.profileID]
        )
        XCTAssertEqual(persisted.outbox.map(\.key.profileID), [fixture.profileID])
        XCTAssertEqual(persisted.status.pendingCount, 1)
        XCTAssertFalse(
            try Data(contentsOf: fixture.url).contains(
                Data("ACCOUNT_A_PROFILE_BYTES".utf8)
            )
        )
    }

    func testOutboxSurvivesRestartAndStaleAcknowledgementCannotClearNewerWrite()
        async throws
    {
        let fixture = try JournalFixture()
        defer { fixture.remove() }
        let firstRepository = LocalJSONFamilySyncJournalRepository(
            snapshotURL: fixture.url
        )
        let first = try await firstRepository.reconcileLocalRecords(
            [fixture.record("cat")],
            deviceID: "device-a",
            now: fixture.now
        )[0]
        try await firstRepository.recordTransportResult(
            acknowledged: [
                FamilySyncChangeAcknowledgement(
                    operation: .save(first)
                )
            ],
            failures: [],
            at: fixture.now
        )

        let second = try await firstRepository.reconcileLocalRecords(
            [fixture.record("dog")],
            deviceID: "device-a",
            now: fixture.now.addingTimeInterval(1)
        )[0]
        XCTAssertGreaterThan(second.logicalRevision, first.logicalRevision)
        try await firstRepository.recordTransportResult(
            acknowledged: [
                FamilySyncChangeAcknowledgement(
                    operation: .save(first)
                )
            ],
            failures: [],
            at: fixture.now.addingTimeInterval(2)
        )

        let restarted = LocalJSONFamilySyncJournalRepository(
            snapshotURL: fixture.url
        )
        let status = try await restarted.durableStatus()
        let pending = try await restarted.pendingChanges(
            using: [second],
            now: fixture.now.addingTimeInterval(3)
        )
        XCTAssertEqual(status.pendingCount, 1)
        XCTAssertEqual(pending.map(\.revision), [second.logicalRevision])
    }

    func testPartialFailureBacksOffOnlyFailedKey() async throws {
        let fixture = try JournalFixture()
        defer { fixture.remove() }
        let repository = LocalJSONFamilySyncJournalRepository(
            snapshotURL: fixture.url
        )
        let records = try await repository.reconcileLocalRecords(
            [fixture.record("cat", suffix: "a"), fixture.record("dog", suffix: "b")],
            deviceID: "device-a",
            now: fixture.now
        )
        let acknowledged = records[0]
        let failed = records[1]
        try await repository.recordTransportResult(
            acknowledged: [
                FamilySyncChangeAcknowledgement(operation: .save(acknowledged))
            ],
            failures: [
                FamilySyncTransportFailure(
                    key: FamilySyncChangeKey(
                        profileID: failed.profileID,
                        recordName: failed.recordName
                    ),
                    category: .connectivity,
                    retryAfter: 30
                )
            ],
            at: fixture.now
        )

        let beforeRetry = try await repository.pendingChanges(
            using: records,
            now: fixture.now.addingTimeInterval(29)
        )
        XCTAssertTrue(beforeRetry.isEmpty)
        let retried = try await repository.pendingChanges(
            using: records,
            now: fixture.now.addingTimeInterval(31)
        )
        let status = try await repository.durableStatus()
        XCTAssertEqual(retried.map(\.key.recordName), [failed.recordName])
        XCTAssertEqual(status.pendingCount, 1)
        XCTAssertEqual(status.condition, .waitingForConnection)
        XCTAssertEqual(status.errorCategory, .connectivity)
        XCTAssertEqual(status.retryCount, 1)
        XCTAssertEqual(
            status.nextRetryAt,
            fixture.now.addingTimeInterval(30)
        )
    }

    func testPhysicalDeletionNeverClearsNewerLocalValue() async throws {
        let fixture = try JournalFixture()
        defer { fixture.remove() }
        let repository = LocalJSONFamilySyncJournalRepository(
            snapshotURL: fixture.url
        )
        let record = try await repository.reconcileLocalRecords(
            [fixture.record("cat")],
            deviceID: "device-a",
            now: fixture.now
        )[0]
        let key = FamilySyncChangeKey(
            profileID: record.profileID,
            recordName: record.recordName
        )
        try await repository.recordAppliedRemote(
            records: [],
            deletions: [FamilySyncRemoteDeletion(key: key)],
            at: fixture.now.addingTimeInterval(1)
        )

        let pending = try await repository.pendingChanges(
            using: [record],
            now: fixture.now.addingTimeInterval(2)
        )
        XCTAssertEqual(pending, [.save(record)])
    }

    func testRemoteProfileDeletionAbsorbsChildJournalStateAndLateChildrenAcrossRestart()
        async throws
    {
        let fixture = try JournalFixture()
        defer { fixture.remove() }
        let repository = LocalJSONFamilySyncJournalRepository(
            snapshotURL: fixture.url
        )
        let firstChild = fixture.record(
            "CHILD_NICKNAME_AND_PHOTO_BYTES"
        )
        let secondChild = fixture.record(
            "CHILD_ATTEMPT_WORD_BYTES",
            suffix: "sensitive-attempt-child"
        )
        let unrelated = fixture.record(
            "UNRELATED_PROFILE_BYTES",
            suffix: "unrelated-profile-child",
            profileID: fixture.unrelatedProfileID
        )
        let initial = try await repository.reconcileLocalRecords(
            [firstChild, secondChild, unrelated],
            deviceID: "device-a",
            now: fixture.now
        )
        try await repository.recordTransportResult(
            acknowledged: Set(
                initial.map {
                    FamilySyncChangeAcknowledgement(operation: .save($0))
                }
            ),
            failures: [],
            at: fixture.now
        )

        // Leave both target child keys in a newer local outbox so terminal
        // absorption must remove local, acknowledged, and pending state.
        _ = try await repository.reconcileLocalRecords(
            [
                fixture.record("NEW_PROFILE_BYTES"),
                fixture.record("NEW_ATTEMPT_BYTES", suffix: "sensitive-attempt-child"),
                unrelated,
            ],
            deviceID: "device-a",
            now: fixture.now.addingTimeInterval(1)
        )
        let deletion = try fixture.profileDeletionRecord().assigning(
            revision: FamilySyncLogicalRevision(
                // The semantic tombstone has already won conflict resolution,
                // so terminal absorption must not re-compare it as a normal
                // value write against the newer local Profile manifest.
                counter: 1,
                deviceID: "remote-owner"
            )
        )
        let sameBatchLateChild = fixture.record(
            "SAME_BATCH_LATE_CHILD_BYTES",
            suffix: "same-batch-late-child"
        ).assigning(
            revision: FamilySyncLogicalRevision(
                counter: 49,
                deviceID: "stale-device"
            )
        )
        try await repository.recordAppliedRemote(
            records: [deletion, sameBatchLateChild],
            deletions: [
                FamilySyncRemoteDeletion(
                    key: FamilySyncChangeKey(
                        profileID: fixture.profileID,
                        recordName: firstChild.recordName
                    )
                )
            ],
            at: fixture.now.addingTimeInterval(2)
        )

        // A callback that was already queued before the terminal barrier must
        // not recreate a child manifest on a later journal call either.
        let laterLateChild = fixture.record(
            "LATER_LATE_CHILD_BYTES",
            suffix: "later-late-child"
        ).assigning(
            revision: FamilySyncLogicalRevision(
                counter: 51,
                deviceID: "stale-device"
            )
        )
        try await repository.recordAppliedRemote(
            records: [laterLateChild],
            deletions: [],
            at: fixture.now.addingTimeInterval(3)
        )

        let restarted = LocalJSONFamilySyncJournalRepository(
            snapshotURL: fixture.url
        )
        let localRecords = try await restarted.reconcileLocalRecords(
            [deletion, unrelated],
            deviceID: "device-a",
            now: fixture.now.addingTimeInterval(4)
        )
        let pending = try await restarted.pendingChanges(
            using: localRecords,
            now: fixture.now.addingTimeInterval(5)
        )
        let status = try await restarted.durableStatus()

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .secondsSince1970
        let snapshot = try decoder.decode(
            FamilySyncJournalSnapshot.self,
            from: Data(contentsOf: fixture.url)
        )
        let targetLocal = snapshot.localManifest.filter {
            $0.key.profileID == fixture.profileID
        }
        let targetAcknowledged = snapshot.acknowledgedManifest.filter {
            $0.key.profileID == fixture.profileID
        }
        let targetOutbox = snapshot.outbox.filter {
            $0.key.profileID == fixture.profileID
        }
        let snapshotText = try String(contentsOf: fixture.url, encoding: .utf8)

        XCTAssertTrue(pending.isEmpty)
        XCTAssertEqual(status.pendingCount, 0)
        XCTAssertEqual(targetLocal.count, 1)
        XCTAssertEqual(targetLocal.first?.kind, .profileDeletion)
        XCTAssertEqual(targetLocal.first?.key.recordName, deletion.recordName)
        XCTAssertEqual(targetLocal.first?.payloadChecksum, deletion.payloadChecksum)
        XCTAssertEqual(targetAcknowledged, targetLocal)
        XCTAssertTrue(targetOutbox.isEmpty)
        XCTAssertTrue(
            snapshot.localManifest.contains {
                $0.key.profileID == fixture.unrelatedProfileID
            },
            "Terminal cleanup must stay Profile-scoped"
        )
        for forbidden in [
            secondChild.recordName,
            sameBatchLateChild.recordName,
            laterLateChild.recordName,
            "CHILD_NICKNAME_AND_PHOTO_BYTES",
            "CHILD_ATTEMPT_WORD_BYTES",
            "SAME_BATCH_LATE_CHILD_BYTES",
            "LATER_LATE_CHILD_BYTES",
        ] {
            XCTAssertFalse(snapshotText.contains(forbidden))
        }
    }

    func testCorruptSnapshotFailsClosedWithoutReplacement() async throws {
        let fixture = try JournalFixture()
        defer { fixture.remove() }
        let bytes = Data("not-json".utf8)
        try bytes.write(to: fixture.url, options: .atomic)
        let repository = LocalJSONFamilySyncJournalRepository(
            snapshotURL: fixture.url
        )

        do {
            _ = try await repository.durableStatus()
            XCTFail("Expected invalid JSON")
        } catch let error as FamilySyncJournalError {
            guard case .invalidJSON(let url, _) = error else {
                return XCTFail("Unexpected error: \(error)")
            }
            XCTAssertEqual(url, fixture.url)
        }
        XCTAssertEqual(try Data(contentsOf: fixture.url), bytes)
    }

    func testProfileDeletionEvidenceSurvivesAckOutboxRemovalAndRestart() async throws {
        let fixture = try JournalFixture()
        defer { fixture.remove() }
        let repository = LocalJSONFamilySyncJournalRepository(
            snapshotURL: fixture.url
        )
        let versioned = try await repository.reconcileLocalRecords(
            [try fixture.profileDeletionRecord()],
            deviceID: "device-a",
            now: fixture.now
        )[0]
        let expectedAcknowledgement = FamilySyncChangeAcknowledgement(
            operation: .save(versioned)
        )

        let pending = try await repository.profileDeletionDeliveryEvidence(
            for: fixture.profileID
        )
        guard case .pending(let metadata) = pending else {
            return XCTFail("Expected pending evidence, got \(pending)")
        }
        XCTAssertEqual(metadata.acknowledgement, expectedAcknowledgement)
        XCTAssertEqual(metadata.retryCount, 0)

        try await repository.recordTransportResult(
            acknowledged: [expectedAcknowledgement],
            failures: [],
            at: fixture.now.addingTimeInterval(1)
        )
        let restarted = LocalJSONFamilySyncJournalRepository(
            snapshotURL: fixture.url
        )
        let afterRestart = try await restarted.profileDeletionDeliveryEvidence(
            for: fixture.profileID
        )
        let pendingAfterRestart = try await restarted.pendingChanges(
            using: [versioned],
            now: fixture.now.addingTimeInterval(2)
        )

        XCTAssertEqual(afterRestart, .acknowledged(expectedAcknowledgement))
        XCTAssertTrue(pendingAfterRestart.isEmpty)
    }

    func testProfileDeletionEvidenceDoesNotInventQueueForUnknownProfile() async throws {
        let fixture = try JournalFixture()
        defer { fixture.remove() }
        let repository = LocalJSONFamilySyncJournalRepository(
            snapshotURL: fixture.url
        )

        let evidence = try await repository.profileDeletionDeliveryEvidence(
            for: fixture.profileID
        )
        XCTAssertEqual(evidence, .notQueued)
    }

    func testRouteLessAcknowledgementCanBeRequeuedAcrossRestart() async throws {
        let fixture = try JournalFixture()
        defer { fixture.remove() }
        let repository = LocalJSONFamilySyncJournalRepository(
            snapshotURL: fixture.url
        )
        let versioned = try await repository.reconcileLocalRecords(
            [try fixture.profileDeletionRecord()],
            deviceID: "legacy-device",
            now: fixture.now
        )[0]
        let acknowledgement = FamilySyncChangeAcknowledgement(
            operation: .save(versioned)
        )
        try await repository.recordTransportResult(
            acknowledged: [acknowledgement],
            failures: [],
            at: fixture.now
        )

        try await repository.requeueProfileDeletion(
            for: fixture.profileID,
            errorCategory: .compatibility,
            at: fixture.now.addingTimeInterval(1)
        )
        let restarted = LocalJSONFamilySyncJournalRepository(
            snapshotURL: fixture.url
        )
        let evidence = try await restarted.profileDeletionDeliveryEvidence(
            for: fixture.profileID
        )
        let pending = try await restarted.pendingChanges(
            using: [versioned],
            now: fixture.now.addingTimeInterval(2)
        )

        guard case .pending(let metadata) = evidence else {
            return XCTFail("Expected requeued deletion evidence")
        }
        XCTAssertEqual(metadata.acknowledgement, acknowledgement)
        XCTAssertEqual(metadata.errorCategory, .compatibility)
        XCTAssertEqual(pending, [.save(versioned)])
    }

    func testAccountChangeKeepsAcknowledgedProfileDeletionTerminal() async throws {
        let fixture = try JournalFixture()
        defer { fixture.remove() }
        let repository = LocalJSONFamilySyncJournalRepository(
            snapshotURL: fixture.url
        )
        let versioned = try await repository.reconcileLocalRecords(
            [try fixture.profileDeletionRecord()],
            deviceID: "device-a",
            now: fixture.now
        )
        let acknowledgement = FamilySyncChangeAcknowledgement(
            operation: .save(versioned[0])
        )
        try await repository.recordTransportResult(
            acknowledged: [acknowledgement],
            failures: [],
            at: fixture.now
        )

        try await repository.invalidateAcknowledgementsForAccountChange(
            at: fixture.now.addingTimeInterval(1)
        )
        let pending = try await repository.pendingChanges(
            using: versioned,
            now: fixture.now.addingTimeInterval(2)
        )
        let status = try await repository.durableStatus()
        let evidence = try await repository.profileDeletionDeliveryEvidence(
            for: fixture.profileID
        )
        XCTAssertTrue(pending.isEmpty)
        XCTAssertEqual(evidence, .acknowledged(acknowledgement))
        XCTAssertEqual(status.condition, .iCloudUnavailable)
        XCTAssertEqual(status.errorCategory, .account)
        XCTAssertNil(status.lastSuccessAt)
    }

    func testAccountChangeKeepsUnacknowledgedProfileDeletionPendingWithAccountError()
        async throws
    {
        let fixture = try JournalFixture()
        defer { fixture.remove() }
        let repository = LocalJSONFamilySyncJournalRepository(
            snapshotURL: fixture.url
        )
        let versioned = try await repository.reconcileLocalRecords(
            [try fixture.profileDeletionRecord()],
            deviceID: "device-a",
            now: fixture.now
        )[0]

        try await repository.invalidateAcknowledgementsForAccountChange(
            at: fixture.now.addingTimeInterval(1)
        )

        let evidence = try await repository.profileDeletionDeliveryEvidence(
            for: fixture.profileID
        )
        guard case .pending(let metadata) = evidence else {
            return XCTFail("Expected pending account attention, got \(evidence)")
        }
        XCTAssertEqual(metadata.acknowledgement.revision, versioned.logicalRevision)
        XCTAssertEqual(metadata.errorCategory, .account)
        XCTAssertEqual(metadata.lastAttemptAt, fixture.now.addingTimeInterval(1))
    }
}

private struct JournalFixture {
    let directory: URL
    let url: URL
    let profileID = ProfileID(
        rawValue: UUID(uuidString: "11111111-2222-3333-4444-555555555555")!
    )
    let unrelatedProfileID = ProfileID(
        rawValue: UUID(uuidString: "AAAAAAAA-BBBB-CCCC-DDDD-EEEEEEEEEEEE")!
    )
    let now = Date(timeIntervalSince1970: 1_000)

    init() throws {
        directory = FileManager.default.temporaryDirectory.appendingPathComponent(
            "TadaWordsFamilySyncJournal-\(UUID().uuidString)",
            isDirectory: true
        )
        try FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true
        )
        url = directory.appendingPathComponent("journal.json")
    }

    func record(
        _ payload: String,
        suffix: String = "profile",
        profileID: ProfileID? = nil
    ) -> FamilySyncRecord {
        let profileID = profileID ?? self.profileID
        return FamilySyncRecord(
            recordName: "\(suffix)-\(profileID)",
            profileID: profileID,
            kind: .profile,
            payload: Data(payload.utf8),
            updatedAt: now,
            deviceID: "raw-device"
        )
    }

    func profileDeletionRecord() throws -> FamilySyncRecord {
        let tombstone = ProfileDeletionTombstone(
            profileID: profileID,
            deletedAt: now
        )
        return FamilySyncRecord(
            recordName: "profile-\(profileID)",
            profileID: profileID,
            kind: .profileDeletion,
            payload: try JSONEncoder().encode(tombstone),
            updatedAt: now,
            deviceID: "raw-device",
            isDeleted: true
        )
    }

    func remove() {
        try? FileManager.default.removeItem(at: directory)
    }
}
