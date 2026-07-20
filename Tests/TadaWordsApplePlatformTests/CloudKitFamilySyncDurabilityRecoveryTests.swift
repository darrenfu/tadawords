import Foundation
import TadaWordsDomain
import XCTest

@testable import TadaWordsApplePlatform

final class CloudKitFamilySyncDurabilityRecoveryTests: XCTestCase {
    func testDurabilityFailureRequiresCurrentGenerationEngineRebuild() async throws {
        let fixture = try DurabilityRecoveryFixture()
        defer { fixture.remove() }
        let buffer = CloudKitFamilySyncEventBuffer(
            metadataStore: fixture.metadataStore
        )

        let initiallyRequiresRebuild = await buffer.requiresEngineRebuild(
            generation: 1
        )
        XCTAssertFalse(initiallyRequiresRebuild)

        await buffer.noteStatePersistenceFailure(1)
        let failure = await buffer.drain()

        XCTAssertEqual(failure.failures.count, 1)
        XCTAssertEqual(failure.failures.first?.category, .corruptState)
        let currentGenerationRequiresRebuild =
            await buffer.requiresEngineRebuild(generation: 1)
        let futureGenerationRequiresRebuild =
            await buffer.requiresEngineRebuild(generation: 2)
        XCTAssertTrue(
            currentGenerationRequiresRebuild,
            "Draining the user-visible failure must not clear the recovery fence"
        )
        XCTAssertFalse(
            futureGenerationRequiresRebuild,
            "Only the delegate generation that consumed the callback may rebuild"
        )
    }

    func testNewGenerationClearsRebuildRequirementAndRejectsLateFailure() async throws {
        let fixture = try DurabilityRecoveryFixture()
        defer { fixture.remove() }
        let buffer = CloudKitFamilySyncEventBuffer(
            metadataStore: fixture.metadataStore
        )

        await buffer.noteStatePersistenceFailure(1)
        let failedGenerationRequiresRebuild =
            await buffer.requiresEngineRebuild(generation: 1)
        XCTAssertTrue(failedGenerationRequiresRebuild)

        let newGeneration = await buffer.nextGeneration()

        XCTAssertEqual(newGeneration, 2)
        let replacementRequiresRebuild =
            await buffer.requiresEngineRebuild(generation: 2)
        XCTAssertFalse(replacementRequiresRebuild)

        await buffer.noteStatePersistenceFailure(1)

        let poisonedReplacementRequiresRebuild =
            await buffer.requiresEngineRebuild(generation: 2)
        let lateFailureResult = await buffer.drain()
        XCTAssertFalse(
            poisonedReplacementRequiresRebuild,
            "A late callback from the discarded engine must not poison its replacement"
        )
        XCTAssertTrue(lateFailureResult.failures.isEmpty)
    }
}

private struct DurabilityRecoveryFixture {
    let directory: URL
    let metadataStore: CloudKitFamilyMetadataStore

    init() throws {
        directory = FileManager.default.temporaryDirectory.appendingPathComponent(
            "TadaDurabilityRecovery-\(UUID().uuidString)",
            isDirectory: true
        )
        try FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true
        )
        metadataStore = CloudKitFamilyMetadataStore(
            snapshotURL: directory.appendingPathComponent(
                "cloudkit-sync-metadata.json"
            )
        )
    }

    func remove() {
        try? FileManager.default.removeItem(at: directory)
    }
}
