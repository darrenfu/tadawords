import Foundation
import XCTest

@testable import TadaWordsDomain

final class FamilySyncAcceptanceCoverageTests: XCTestCase {
    func testEveryManifestFieldHasExactlyOneExplicitEvidenceAtEveryLevel() {
        let rows = FamilySyncAcceptanceCoverageMatrix.rows
        XCTAssertEqual(
            Set(rows.map(\.fieldPath)),
            Set(FamilySyncDataManifest.entries.map(\.fieldPath))
        )
        XCTAssertEqual(rows.count, FamilySyncDataManifest.entries.count)

        for row in rows {
            XCTAssertEqual(row.evidence.count, FamilySyncEvidenceLevel.allCases.count)
            XCTAssertEqual(
                Set(row.evidence.map(\.level)),
                Set(FamilySyncEvidenceLevel.allCases),
                "\(row.fieldPath) must make every evidence layer explicit"
            )
        }

        let allEvidence = rows.flatMap(\.evidence)
        XCTAssertEqual(
            Set(allEvidence.map(\.id)).count,
            allEvidence.count,
            "Evidence IDs must be globally stable and unique"
        )
    }

    func testPassedEvidenceNamesAConcreteTestFileThatExists() {
        let repositoryRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()

        for evidence in FamilySyncAcceptanceCoverageMatrix.rows.flatMap(\.evidence) {
            XCTAssertFalse(evidence.summary.isEmpty)
            XCTAssertFalse(evidence.locator.isEmpty)
            switch evidence.status {
            case .passed:
                let fileLocator = evidence.locator.split(
                    separator: "#",
                    maxSplits: 1
                )[0]
                XCTAssertTrue(
                    fileLocator.hasPrefix("Tests/")
                        && fileLocator.hasSuffix(".swift"),
                    "Passing evidence must name a concrete test file: \(evidence.id)"
                )
                XCTAssertTrue(
                    FileManager.default.fileExists(
                        atPath:
                            repositoryRoot
                            .appendingPathComponent(String(fileLocator)).path
                    ),
                    "Passing evidence file does not exist: \(evidence.locator)"
                )
            case .pending:
                XCTAssertTrue(
                    evidence.locator.hasPrefix("gate:"),
                    "Pending evidence must name its explicit release gate"
                )
            }
            XCTAssertFalse(
                evidence.locator.contains("family-sync-manifest:"),
                "Self-referential code markers are inventory metadata, not acceptance evidence"
            )
        }
    }

    func testSimulatorEvidenceIsLimitedToTheExactObservedUIRows() {
        let expectedPassed: Set<String> = [
            "profiles.id",
            "profiles.displayName",
            "wordPool.entries.id",
            "wordPool.entries.profileID",
            "wordPool.entries.prompt",
            "wordPool.entries.isActive",
            "practiceSettings.read.*",
            "practiceSettings.write.*",
            "learning.attempts.*",
            "learning.progress.*",
            "dailyQuests.completions.*",
            "dailyQuests.rewardGrants.*",
            "profileDeletions.*",
            "childSession.lastSelectedProfileID",
            "familySyncJournal.*",
            "familySyncApplyTransaction.*",
            "views.badgeCollection",
            "views.scoresAndReports",
            "views.lastSyncPresentation",
        ]

        let actualPassed = Set(
            FamilySyncAcceptanceCoverageMatrix.rows.compactMap { row in
                row.evidence(at: .simulator)?.status == .passed
                    ? row.fieldPath
                    : nil
            }
        )
        XCTAssertEqual(actualPassed, expectedPassed)

        for row in FamilySyncAcceptanceCoverageMatrix.rows {
            for level in [FamilySyncEvidenceLevel.physicalDevice, .human] {
                XCTAssertEqual(
                    row.evidence(at: level)?.status,
                    .pending,
                    "Do not mark \(row.fieldPath) \(level.rawValue) passed without an exact-HEAD artifact"
                )
            }
        }
        XCTAssertFalse(FamilySyncAcceptanceCoverageMatrix.releaseAccepted)
        XCTAssertFalse(FamilySyncAcceptanceCoverageMatrix.pendingEvidence.isEmpty)
    }

    func testCoverageMatrixIsCodableMachineReadableData() throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let data = try encoder.encode(FamilySyncAcceptanceCoverageMatrix.rows)
        let decoded = try JSONDecoder().decode(
            [FamilySyncManifestCoverageRow].self,
            from: data
        )
        XCTAssertEqual(decoded, FamilySyncAcceptanceCoverageMatrix.rows)
    }
}
