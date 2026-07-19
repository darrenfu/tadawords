import Foundation
import TadaWordsDomain
import XCTest

@testable import TadaWordsContent

final class FamilySyncApplyReceiptStreamHarnessTests: XCTestCase {
    func testStartupCommitBeforeSubscriptionReplaysReceiptAndRefreshesProfileSource()
        async throws
    {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(
                "TadaApplyReceiptStartup-\(UUID().uuidString)",
                isDirectory: true
            )
        try FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true
        )
        defer { try? FileManager.default.removeItem(at: directory) }

        let now = Date(timeIntervalSince1970: 2_178_100_000)
        let localProfile = KidProfile(
            displayName: "My Kid",
            avatar: .cartoonAnimal(assetID: "hare"),
            selectedWorld: .moonpetalKingdom,
            createdAt: now.addingTimeInterval(-100)
        )
        let remoteProfile = KidProfile(
            id: localProfile.id,
            displayName: "Remote Mia",
            avatar: .cartoonAnimal(assetID: "fox"),
            selectedWorld: .pawsAndPines,
            starterWorld: localProfile.starterWorld,
            guardianUnlockedWorlds: [.pawsAndPines],
            schoolGrade: .kindergarten,
            ageYears: 5,
            createdAt: localProfile.createdAt,
            updatedAt: now
        )
        let profiles = InMemoryKidProfileRepository()
        try await profiles.save(localProfile)
        let transactions = LocalJSONFamilySyncApplyTransactionRepository(
            snapshotURL: directory.appendingPathComponent("transactions.json")
        )
        let store = RepositoryFamilySyncRecordStore(
            profileRepository: profiles,
            wordPoolRepository: LocalJSONWordPoolRepository(
                snapshotURL: directory.appendingPathComponent("words.json")
            ),
            practiceSettingsRepository: LocalJSONPracticeSettingsRepository(
                snapshotURL: directory.appendingPathComponent("settings.json")
            ),
            learningRepository: InMemoryLearningRecordRepository(),
            dailyQuestRepository: InMemoryDailyQuestRepository(),
            tombstoneRepository: InMemoryProfileDeletionTombstoneRepository(),
            applyTransactionRepository: transactions,
            deviceID: "local-device",
            clock: ApplyReceiptStreamClock(now: now)
        )
        let remoteRecord = FamilySyncRecord(
            recordName: "profile-\(localProfile.id)",
            profileID: localProfile.id,
            kind: .profile,
            payload: try InspectableSnapshotJSONCodec.makeEncoder().encode(
                remoteProfile
            ),
            updatedAt: now,
            deviceID: "remote-device",
            logicalRevision: FamilySyncLogicalRevision(
                counter: 2,
                deviceID: "remote-device"
            )
        )

        // Reproduce the startup ordering directly: SwiftUI already captured
        // its bootstrap snapshot, then the initial sync commits before the
        // receipt-observation task gets a chance to subscribe.
        let bootstrapProfiles = try await profiles.profiles()
        try await store.apply([remoteRecord], for: localProfile.id)
        XCTAssertEqual(bootstrapProfiles.map(\.displayName), ["My Kid"])

        let lateStream = await transactions.committedReceipts()
        var iterator = lateStream.makeAsyncIterator()
        let nextReceipt = await iterator.next()
        let replayedReceipt = try XCTUnwrap(nextReceipt)
        let refreshedProfiles = try await profiles.profiles()

        XCTAssertEqual(replayedReceipt.profileID, localProfile.id)
        XCTAssertEqual(replayedReceipt.affectedKinds, [.profile])
        XCTAssertEqual(refreshedProfiles, [remoteProfile])
    }

    func testLiveSubscriberReceivesReceiptOnlyAfterDurableCommit()
        async throws
    {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(
                "TadaApplyReceiptStream-\(UUID().uuidString)",
                isDirectory: true
            )
        try FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true
        )
        defer { try? FileManager.default.removeItem(at: directory) }
        let snapshotURL = directory.appendingPathComponent("transactions.json")
        let repository = LocalJSONFamilySyncApplyTransactionRepository(
            snapshotURL: snapshotURL
        )
        let now = Date(timeIntervalSince1970: 2_178_000_000)
        let profile = KidProfile(
            displayName: "Mia",
            avatar: .cartoonAnimal(assetID: "hare"),
            selectedWorld: .moonpetalKingdom,
            createdAt: now
        )
        let record = FamilySyncRecord(
            recordName: "profile-\(profile.id)",
            profileID: profile.id,
            kind: .profile,
            payload: try InspectableSnapshotJSONCodec.makeEncoder().encode(
                profile
            ),
            updatedAt: now,
            deviceID: "remote-device",
            logicalRevision: FamilySyncLogicalRevision(
                counter: 4,
                deviceID: "remote-device"
            )
        )
        let stream = await repository.committedReceipts()
        let emittedReceipt = Task {
            var iterator = stream.makeAsyncIterator()
            return await iterator.next()
        }

        let start = try await repository.begin(
            profileID: profile.id,
            records: [record],
            at: now
        )
        guard case .pending(let transaction) = start else {
            return XCTFail("A new batch must begin as a durable pending transaction")
        }
        let beforeCommit = try await repository.lastCommittedReceipt(
            for: profile.id
        )
        XCTAssertNil(beforeCommit)
        let committed = try await repository.markCommitted(
            transactionID: transaction.id,
            at: now.addingTimeInterval(1)
        )

        let emitted = await emittedReceipt.value
        XCTAssertEqual(emitted, committed)
        let restarted = LocalJSONFamilySyncApplyTransactionRepository(
            snapshotURL: snapshotURL
        )
        let durableReceipt = try await restarted.lastCommittedReceipt(
            for: profile.id
        )
        XCTAssertEqual(durableReceipt, committed)
        XCTAssertEqual(committed.recordCount, 1)
        XCTAssertEqual(committed.affectedKinds, [.profile])
        XCTAssertFalse(committed.deletedProfile)
    }
}

private struct ApplyReceiptStreamClock: AppClock {
    let now: Date
}
