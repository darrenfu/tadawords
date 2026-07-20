import Foundation
import TadaWordsDomain
import XCTest

@testable import TadaWordsContent

final class RepositoryFamilySyncPendingDeletionBarrierTests: XCTestCase {
    func testSealingDeletionRejectsAlreadyQueuedChildWritesWithoutResurrection()
        async throws
    {
        let fixture = try PendingDeletionBarrierFixture()
        defer { fixture.remove() }
        let queuedWrites = PendingDeletionQueuedWriteProbe(expectedStarts: 3)
        let attempt = fixture.makeAttempt()
        let dailyPlan = fixture.makeDailyPlan()
        let settings = ProfilePracticeSettings.defaults(
            for: fixture.profile.id
        )
        let tombstone = ProfileDeletionTombstone(
            profileID: fixture.profile.id,
            deletedAt: fixture.now
        )

        let tasks: [Task<Void, any Error>] = try await withProfileScopedMutationLease(
            fixture.mutationGate,
            for: fixture.profile.id,
            allowingTerminal: true,
            isolation: fixture.mutationGate
        ) {
            let attemptTask = Task.detached {
                await queuedWrites.markStarted()
                do {
                    try await fixture.learning.append(attempt)
                    await queuedWrites.markCompleted()
                } catch {
                    await queuedWrites.markCompleted()
                    throw error
                }
            }
            let questTask = Task.detached {
                await queuedWrites.markStarted()
                do {
                    _ = try await fixture.daily.createPlanIfAbsent(dailyPlan)
                    await queuedWrites.markCompleted()
                } catch {
                    await queuedWrites.markCompleted()
                    throw error
                }
            }
            let settingsTask = Task.detached {
                await queuedWrites.markStarted()
                do {
                    try await fixture.settings.save(settings)
                    await queuedWrites.markCompleted()
                } catch {
                    await queuedWrites.markCompleted()
                    throw error
                }
            }

            await queuedWrites.waitUntilEveryWriteStarted()
            // Give every detached writer an executor turn to reach the
            // already-held Profile lease. These are real concurrent calls,
            // not writes invoked serially after the tombstone.
            for _ in 0..<10 { await Task.yield() }
            try await Task.sleep(for: .milliseconds(50))
            let completedBeforeSeal = await queuedWrites.completedCount
            XCTAssertEqual(completedBeforeSeal, 0)

            // A durable deletion tombstone is the terminal admission
            // fence. The queued writers must be rejected when this lease
            // transfers instead of recreating child data after purge.
            try await fixture.tombstones.save(tombstone)
            return [attemptTask, questTask, settingsTask]
        }

        for task in tasks {
            switch await task.result {
            case .success:
                XCTFail("A normal write entered a terminal Profile")
            case .failure(let error):
                XCTAssertEqual(
                    error as? ProfileScopedMutationGateError,
                    .terminalProfile(fixture.profile.id)
                )
            }
        }

        let completedCount = await queuedWrites.completedCount
        let attempts = try await fixture.learning.attempts(
            for: fixture.profile.id,
            wordPromptID: nil
        )
        let plans = try await fixture.daily.allPlans(for: fixture.profile.id)
        let storedSettings = try await fixture.settings.settings(
            for: fixture.profile.id
        )
        XCTAssertEqual(completedCount, 3)
        XCTAssertEqual(attempts, [])
        XCTAssertEqual(plans, [])
        XCTAssertNil(storedSettings)
    }

    func testTerminalAllowedDeletionAndSyncReadsStillEnterSealedProfile()
        async throws
    {
        let fixture = try PendingDeletionBarrierFixture()
        defer { fixture.remove() }
        let tombstone = ProfileDeletionTombstone(
            profileID: fixture.profile.id,
            deletedAt: fixture.now
        )

        try await fixture.tombstones.save(tombstone)

        do {
            try await withProfileScopedMutationLease(
                fixture.mutationGate,
                for: fixture.profile.id,
                isolation: fixture.mutationGate
            ) {
                XCTFail("A normal operation entered a terminal Profile")
            }
            XCTFail("A normal operation did not receive the terminal fence")
        } catch let error as ProfileScopedMutationGateError {
            XCTAssertEqual(error, .terminalProfile(fixture.profile.id))
        }

        let terminalProbe = PendingDeletionTerminalProbe()
        try await withProfileScopedMutationLease(
            fixture.mutationGate,
            for: fixture.profile.id,
            allowingTerminal: true,
            isolation: fixture.mutationGate
        ) {
            await terminalProbe.markEntered()
        }
        let didEnterTerminalPath = await terminalProbe.didEnter
        XCTAssertTrue(didEnterTerminalPath)

        // Tombstone commit and sync export are terminal-maintenance paths and
        // must remain live after sealing so deletion can converge remotely.
        try await fixture.tombstones.markCommitted(for: fixture.profile.id)
        let records = try await fixture.makeStore().records(
            for: fixture.profile.id
        )
        XCTAssertEqual(records.map(\.kind), [.profileDeletion])
        XCTAssertEqual(records.first?.profileID, fixture.profile.id)
    }

    func testPendingLocalDeletionRefusesEveryExportUntilCommit() async throws {
        let fixture = try PendingDeletionBarrierFixture()
        defer { fixture.remove() }
        try await fixture.profiles.save(fixture.profile)
        let tombstone = ProfileDeletionTombstone(
            profileID: fixture.profile.id,
            deletedAt: fixture.now
        )
        try await fixture.tombstones.save(tombstone)
        let store = fixture.makeStore()

        do {
            let profileIDs = try await store.profileIDsForSync()
            XCTFail(
                "Pending local deletion exported profile IDs: \(profileIDs)"
            )
        } catch {
            // A pending tombstone represents an incomplete local transaction.
            // Refusing the entire export prevents a partial purge from being
            // reconciled as a valid remote deletion.
        }

        do {
            let records = try await store.records(for: fixture.profile.id)
            XCTFail(
                "Pending local deletion exported records: \(records.map(\.recordName))"
            )
        } catch {
            // The profile-specific path must fail closed for the same reason.
        }

        try await fixture.tombstones.markCommitted(for: fixture.profile.id)

        let profileIDs = try await store.profileIDsForSync()
        let records = try await store.records(for: fixture.profile.id)
        XCTAssertEqual(profileIDs, [fixture.profile.id])
        XCTAssertEqual(records.count, 1)
        let deletionRecord = try XCTUnwrap(records.first)
        XCTAssertEqual(
            deletionRecord.recordName,
            "profile-\(fixture.profile.id)"
        )
        XCTAssertEqual(deletionRecord.profileID, fixture.profile.id)
        XCTAssertEqual(deletionRecord.kind, .profileDeletion)
        XCTAssertTrue(deletionRecord.isDeleted)
        XCTAssertEqual(
            try InspectableSnapshotJSONCodec.makeDecoder().decode(
                ProfileDeletionTombstone.self,
                from: deletionRecord.payload
            ),
            tombstone
        )
    }

    func testRecordsReadWaitsForSharedProfileMutationLease() async throws {
        let fixture = try PendingDeletionBarrierFixture()
        defer { fixture.remove() }
        try await fixture.profiles.save(fixture.profile)
        let store = fixture.makeStore()
        let probe = PendingDeletionReadProbe()

        try await fixture.mutationGate.acquire(fixture.profile.id)
        let readTask = Task {
            await probe.markStarted()
            let records = try await store.records(for: fixture.profile.id)
            await probe.markCompleted()
            return records
        }
        await probe.waitUntilStarted()
        try await Task.sleep(for: .milliseconds(100))
        let completedWhileLeaseWasHeld = await probe.isCompleted

        await fixture.mutationGate.release(fixture.profile.id)
        let records = try await readTask.value

        XCTAssertFalse(
            completedWhileLeaseWasHeld,
            "Sync export bypassed the shared profile mutation lease"
        )
        XCTAssertEqual(records.filter { $0.kind == .profile }.count, 1)
    }
}

private struct PendingDeletionBarrierFixture {
    let directory: URL
    let now = Date(timeIntervalSince1970: 2_180_000_000)
    let profile: KidProfile
    let mutationGate = ProfileScopedMutationGate()
    let profiles: LocalJSONKidProfileRepository
    let words: LocalJSONWordPoolRepository
    let settings: LocalJSONPracticeSettingsRepository
    let learning: LocalJSONLearningRecordRepository
    let daily: LocalJSONDailyQuestRepository
    let tombstones: LocalJSONProfileDeletionTombstoneRepository

    init() throws {
        directory = FileManager.default.temporaryDirectory.appendingPathComponent(
            "TadaPendingDeletionBarrier-\(UUID().uuidString)",
            isDirectory: true
        )
        try FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true
        )
        profile = KidProfile(
            displayName: "Mia",
            avatar: .cartoonAnimal(assetID: "hare"),
            selectedWorld: .moonpetalKingdom,
            createdAt: now.addingTimeInterval(-60)
        )
        profiles = LocalJSONKidProfileRepository(
            snapshotURL: directory.appendingPathComponent("profiles.json"),
            mutationGate: mutationGate
        )
        words = LocalJSONWordPoolRepository(
            snapshotURL: directory.appendingPathComponent("words.json"),
            mutationGate: mutationGate
        )
        settings = LocalJSONPracticeSettingsRepository(
            snapshotURL: directory.appendingPathComponent("settings.json"),
            mutationGate: mutationGate
        )
        learning = LocalJSONLearningRecordRepository(
            snapshotURL: directory.appendingPathComponent("learning.json"),
            mutationGate: mutationGate
        )
        daily = LocalJSONDailyQuestRepository(
            snapshotURL: directory.appendingPathComponent("daily.json"),
            mutationGate: mutationGate
        )
        tombstones = LocalJSONProfileDeletionTombstoneRepository(
            snapshotURL: directory.appendingPathComponent("deletions.json"),
            mutationGate: mutationGate
        )
    }

    func makeStore() -> RepositoryFamilySyncRecordStore {
        RepositoryFamilySyncRecordStore(
            profileRepository: profiles,
            wordPoolRepository: words,
            practiceSettingsRepository: settings,
            learningRepository: learning,
            dailyQuestRepository: daily,
            tombstoneRepository: tombstones,
            mutationGate: mutationGate,
            deviceID: "pending-deletion-test-device"
        )
    }

    func makeAttempt() -> AttemptEvent {
        AttemptEvent(
            profileID: profile.id,
            wordPromptID: WordPromptID(),
            learningMode: .read,
            evidence: .firstIndependentAttempt,
            outcome: .correct,
            occurredAt: now
        )
    }

    func makeDailyPlan() -> DailyQuestPlan {
        DailyQuestPlan(
            localDay: try! LocalDay(year: 2039, month: 1, day: 28),
            questPlan: QuestPlan(
                profileID: profile.id,
                configuration: .defaultRead,
                reviewWordIDs: [],
                newWordIDs: [WordPromptID()],
                createdAt: now
            )
        )
    }

    func remove() {
        try? FileManager.default.removeItem(at: directory)
    }
}

private actor PendingDeletionQueuedWriteProbe {
    private let expectedStarts: Int
    private var startedCount = 0
    private(set) var completedCount = 0
    private var startWaiters: [CheckedContinuation<Void, Never>] = []

    init(expectedStarts: Int) {
        self.expectedStarts = expectedStarts
    }

    func markStarted() {
        startedCount += 1
        guard startedCount == expectedStarts else { return }
        let waiters = startWaiters
        startWaiters.removeAll()
        for waiter in waiters { waiter.resume() }
    }

    func markCompleted() {
        completedCount += 1
    }

    func waitUntilEveryWriteStarted() async {
        guard startedCount == expectedStarts else {
            await withCheckedContinuation { continuation in
                startWaiters.append(continuation)
            }
            return
        }
    }
}

private actor PendingDeletionTerminalProbe {
    private(set) var didEnter = false

    func markEntered() {
        didEnter = true
    }
}

private actor PendingDeletionReadProbe {
    private var started = false
    private var completed = false
    private var startWaiters: [CheckedContinuation<Void, Never>] = []

    var isCompleted: Bool { completed }

    func markStarted() {
        started = true
        let waiters = startWaiters
        startWaiters.removeAll()
        for waiter in waiters {
            waiter.resume()
        }
    }

    func markCompleted() {
        completed = true
    }

    func waitUntilStarted() async {
        guard !started else { return }
        await withCheckedContinuation { continuation in
            startWaiters.append(continuation)
        }
    }
}
