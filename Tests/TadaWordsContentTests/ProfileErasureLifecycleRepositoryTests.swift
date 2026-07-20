import Foundation
import TadaWordsDomain
import XCTest

@testable import TadaWordsContent

final class ProfileErasureLifecycleRepositoryTests: XCTestCase {
    func testSaveDurablyCreatesRequestedLifecycleBeforeLocalPurgeCommit() async throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let tombstone = fixture.tombstone

        try await fixture.repository.save(tombstone)

        let loadedLifecycle = try await fixture.repository.erasureLifecycle(
            for: tombstone.profileID
        )
        let lifecycle = try XCTUnwrap(loadedLifecycle)
        XCTAssertEqual(lifecycle.state, .requested)
        XCTAssertEqual(lifecycle.route, .unresolved)
        XCTAssertEqual(lifecycle.requestedAt, tombstone.deletedAt)
        let pendingBeforePurge = try await fixture.repository.pendingTombstones()
        XCTAssertEqual(pendingBeforePurge, [tombstone])

        try await fixture.repository.markCommitted(for: tombstone.profileID)

        let pendingAfterPurge = try await fixture.repository.pendingTombstones()
        let afterPurge = try await fixture.repository.erasureLifecycle(
            for: tombstone.profileID
        )
        XCTAssertTrue(pendingAfterPurge.isEmpty)
        XCTAssertEqual(
            afterPurge?.state,
            .requested,
            "A local purge commit must never masquerade as remote erasure completion."
        )
    }

    func testRouteIsMonotonicAndConflictingRoleFailsClosed() async throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        try await fixture.repository.save(fixture.tombstone)
        try await fixture.repository.recordErasureEvent(
            .attemptStarted(route: .owner, at: fixture.now),
            for: fixture.profileID
        )

        await assertThrowsErrorAsync(
            try await fixture.repository.recordErasureEvent(
                .needsAttention(route: .participant, category: .account, at: fixture.now),
                for: fixture.profileID
            )
        ) { error in
            XCTAssertEqual(
                error as? ProfileErasureLifecycleRepositoryError,
                .routeConflict(
                    profileID: fixture.profileID,
                    existing: .owner,
                    requested: .participant
                )
            )
        }
        let retained = try await fixture.repository.erasureLifecycle(
            for: fixture.profileID
        )
        XCTAssertEqual(retained?.route, .owner)
    }

    func testRouteResolutionIsDurableWithoutChangingAttemptMetadata() async throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        try await fixture.repository.save(fixture.tombstone)
        try await fixture.repository.recordErasureEvent(
            .attemptStarted(route: .unresolved, at: fixture.now),
            for: fixture.profileID
        )
        let loadedBefore = try await fixture.repository.erasureLifecycle(
            for: fixture.profileID
        )
        let before = try XCTUnwrap(loadedBefore)

        try await fixture.repository.recordErasureEvent(
            .routeResolved(route: .participant, at: fixture.now.addingTimeInterval(1)),
            for: fixture.profileID
        )

        let restarted = LocalJSONProfileDeletionTombstoneRepository(
            snapshotURL: fixture.snapshotURL
        )
        let loadedResolved = try await restarted.erasureLifecycle(for: fixture.profileID)
        let resolved = try XCTUnwrap(loadedResolved)
        XCTAssertEqual(resolved.route, .participant)
        XCTAssertEqual(resolved.state, before.state)
        XCTAssertEqual(resolved.attemptCount, before.attemptCount)
        XCTAssertEqual(resolved.retryCount, before.retryCount)
        XCTAssertEqual(resolved.lastAttemptAt, before.lastAttemptAt)
    }

    func testCompletedLifecycleIsTerminalAcrossDuplicateAndLateCallbacks() async throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        try await fixture.repository.save(fixture.tombstone)
        try await fixture.repository.recordErasureEvent(
            .attemptStarted(route: .owner, at: fixture.now),
            for: fixture.profileID
        )
        try await fixture.repository.recordErasureEvent(
            .retryScheduled(
                route: .owner,
                retryCount: 1,
                nextRetryAt: fixture.now.addingTimeInterval(60),
                category: .connectivity,
                at: fixture.now.addingTimeInterval(1)
            ),
            for: fixture.profileID
        )
        let completedAt = fixture.now.addingTimeInterval(2)
        try await fixture.repository.recordErasureEvent(
            .completed(route: .owner, at: completedAt),
            for: fixture.profileID
        )
        let loadedCompleted = try await fixture.repository.erasureLifecycle(
            for: fixture.profileID
        )
        let completed = try XCTUnwrap(loadedCompleted)

        try await fixture.repository.recordErasureEvent(
            .completed(route: .owner, at: completedAt.addingTimeInterval(5)),
            for: fixture.profileID
        )
        try await fixture.repository.recordErasureEvent(
            .needsAttention(
                route: .participant,
                category: .account,
                at: completedAt.addingTimeInterval(10)
            ),
            for: fixture.profileID
        )

        let afterDuplicates = try await fixture.repository.erasureLifecycle(
            for: fixture.profileID
        )
        XCTAssertEqual(afterDuplicates, completed)
        XCTAssertEqual(completed.state, .complete)
        XCTAssertEqual(completed.attemptCount, 1)
        XCTAssertEqual(completed.retryCount, 1)
        XCTAssertEqual(completed.lastSuccessAt, completedAt)
        XCTAssertNil(completed.errorCategory)
    }

    func testLifecycleSurvivesRepositoryRestart() async throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        try await fixture.repository.save(fixture.tombstone)
        try await fixture.repository.recordErasureEvent(
            .needsAttention(route: .participant, category: .account, at: fixture.now),
            for: fixture.profileID
        )
        let before = try await fixture.repository.erasureLifecycle(for: fixture.profileID)

        let restarted = LocalJSONProfileDeletionTombstoneRepository(
            snapshotURL: fixture.snapshotURL
        )

        let afterRestart = try await restarted.erasureLifecycle(for: fixture.profileID)
        XCTAssertEqual(afterRestart, before)
    }

    func testV1SnapshotMigratesToRequestedLifecycleWithoutChangingCommitState()
        async throws
    {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let legacy = LegacySnapshot(
            schemaVersion: 1,
            entries: [
                .init(tombstone: fixture.tombstone, isCommitted: true)
            ]
        )
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .secondsSince1970
        try encoder.encode(legacy).write(to: fixture.snapshotURL)

        let loadedLifecycle = try await fixture.repository.erasureLifecycle(
            for: fixture.profileID
        )
        let lifecycle = try XCTUnwrap(loadedLifecycle)

        XCTAssertEqual(lifecycle.state, .requested)
        let pending = try await fixture.repository.pendingTombstones()
        XCTAssertTrue(pending.isEmpty)
        let migrated =
            try JSONSerialization.jsonObject(
                with: Data(contentsOf: fixture.snapshotURL)
            ) as? [String: Any]
        XCTAssertEqual(migrated?["schemaVersion"] as? Int, 2)
    }

    func testCorruptLifecycleProfileLinkFailsWithoutRewritingBytes() async throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        try await fixture.repository.save(fixture.tombstone)
        var object = try XCTUnwrap(
            try JSONSerialization.jsonObject(
                with: Data(contentsOf: fixture.snapshotURL)
            ) as? [String: Any]
        )
        var entries = try XCTUnwrap(object["entries"] as? [[String: Any]])
        var lifecycle = try XCTUnwrap(entries[0]["lifecycle"] as? [String: Any])
        lifecycle["profileID"] = ProfileID().description
        entries[0]["lifecycle"] = lifecycle
        object["entries"] = entries
        let corrupt = try JSONSerialization.data(withJSONObject: object)
        try corrupt.write(to: fixture.snapshotURL)
        let restarted = LocalJSONProfileDeletionTombstoneRepository(
            snapshotURL: fixture.snapshotURL
        )

        await assertThrowsErrorAsync(
            try await restarted.erasureLifecycles()
        )

        XCTAssertEqual(try Data(contentsOf: fixture.snapshotURL), corrupt)
    }

    func testDuplicateLifecycleEntriesFailWithoutRewritingBytes() async throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        try await fixture.repository.save(fixture.tombstone)
        var object = try XCTUnwrap(
            try JSONSerialization.jsonObject(
                with: Data(contentsOf: fixture.snapshotURL)
            ) as? [String: Any]
        )
        var entries = try XCTUnwrap(object["entries"] as? [[String: Any]])
        entries.append(entries[0])
        object["entries"] = entries
        let corrupt = try JSONSerialization.data(withJSONObject: object)
        try corrupt.write(to: fixture.snapshotURL)
        let restarted = LocalJSONProfileDeletionTombstoneRepository(
            snapshotURL: fixture.snapshotURL
        )

        await assertThrowsErrorAsync(
            try await restarted.erasureLifecycles()
        )

        XCTAssertEqual(try Data(contentsOf: fixture.snapshotURL), corrupt)
    }

    func testFutureLifecycleSchemaFailsWithoutRewritingBytes() async throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        try await fixture.repository.save(fixture.tombstone)
        var object = try XCTUnwrap(
            try JSONSerialization.jsonObject(
                with: Data(contentsOf: fixture.snapshotURL)
            ) as? [String: Any]
        )
        object["schemaVersion"] =
            LocalJSONProfileDeletionTombstoneRepository.currentSchemaVersion + 1
        let future = try JSONSerialization.data(withJSONObject: object)
        try future.write(to: fixture.snapshotURL)
        let restarted = LocalJSONProfileDeletionTombstoneRepository(
            snapshotURL: fixture.snapshotURL
        )

        await assertThrowsErrorAsync(
            try await restarted.erasureLifecycles()
        )

        XCTAssertEqual(try Data(contentsOf: fixture.snapshotURL), future)
    }
}

extension ProfileErasureLifecycleRepositoryTests {
    fileprivate struct LegacySnapshot: Encodable {
        struct Entry: Encodable {
            let tombstone: ProfileDeletionTombstone
            let isCommitted: Bool
        }

        let schemaVersion: Int
        let entries: [Entry]
    }

    fileprivate struct Fixture {
        let directory: URL
        let snapshotURL: URL
        let repository: LocalJSONProfileDeletionTombstoneRepository
        let profileID = ContentTestFixture.profileID
        let now = Date(timeIntervalSince1970: 2_050_000_000)

        init() throws {
            directory = FileManager.default.temporaryDirectory.appendingPathComponent(
                "ProfileErasureLifecycle-\(UUID().uuidString)",
                isDirectory: true
            )
            try FileManager.default.createDirectory(
                at: directory,
                withIntermediateDirectories: true
            )
            snapshotURL = directory.appendingPathComponent("profile-deletions.json")
            repository = LocalJSONProfileDeletionTombstoneRepository(
                snapshotURL: snapshotURL
            )
        }

        var tombstone: ProfileDeletionTombstone {
            ProfileDeletionTombstone(
                profileID: profileID,
                deletedAt: now.addingTimeInterval(-10)
            )
        }

        func remove() {
            try? FileManager.default.removeItem(at: directory)
        }
    }
}

private func assertThrowsErrorAsync<T>(
    _ expression: @autoclosure () async throws -> T,
    _ handler: (Error) -> Void = { _ in }
) async {
    do {
        _ = try await expression()
        XCTFail("Expected expression to throw")
    } catch {
        handler(error)
    }
}
