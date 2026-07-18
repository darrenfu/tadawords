import Foundation
import TadaWordsDomain
import XCTest

@testable import TadaWordsContent

final class FamilySyncDataManifestCoverageHarnessTests: XCTestCase {
    func testEveryRecordKindHasOneExplicitTransportClassification() {
        let synchronized = FamilySyncDataManifest.synchronizedRecordKinds
        let expectedSynchronized = Set(FamilySyncRecordKind.allCases).subtracting([
            .wordProgress
        ])

        XCTAssertEqual(synchronized, expectedSynchronized)
        let progressEntries = FamilySyncDataManifest.entries.filter {
            $0.recordKind == .wordProgress
        }
        XCTAssertFalse(progressEntries.isEmpty)
        XCTAssertTrue(
            progressEntries.allSatisfy { $0.classification == .derived },
            "wordProgress must be manifest-visible but never authoritative transport data"
        )
        XCTAssertFalse(
            FamilySyncDataManifest.entries.contains {
                $0.classification == .synchronized && $0.recordKind == nil
            }
        )
    }

    func testManifestEntriesHaveStableMachineEvidenceIDs() {
        let entries = FamilySyncDataManifest.entries
        XCTAssertEqual(Set(entries.map(\.fieldPath)).count, entries.count)

        for entry in entries {
            XCTAssertFalse(entry.fieldPath.trimmingCharacters(in: .whitespaces).isEmpty)
            XCTAssertFalse(entry.rationale.trimmingCharacters(in: .whitespaces).isEmpty)
            guard let evidenceIDs = evidenceIDs(for: entry) else {
                XCTFail(
                    "\(entry.fieldPath) has no machine-readable evidenceIDs property"
                )
                continue
            }
            XCTAssertFalse(
                evidenceIDs.isEmpty,
                "\(entry.fieldPath) must cite at least one stable evidence ID"
            )
            XCTAssertTrue(
                evidenceIDs.allSatisfy {
                    !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                }
            )
        }
    }

    func testPersistedSnapshotFieldsMatchReviewedInventoryAndManifestEvidence()
        throws
    {
        let snapshots: [String: any Encodable] = [
            "ChildSessionSnapshot": ChildSessionSnapshot(
                lastSelectedProfileID: ProfileID()
            ),
            "DailyQuestSnapshot": DailyQuestSnapshot(
                plans: [],
                completions: [],
                rewardGrants: []
            ),
            "FamilySyncJournalSnapshot": FamilySyncJournalSnapshot(),
            "FamilySyncApplyTransactionSnapshot":
                FamilySyncApplyTransactionSnapshot(),
            "FamilySyncPreferenceSnapshot": FamilySyncPreferenceSnapshot(
                isEnabled: true,
                disclosureVersion:
                    FamilySyncPreferenceSnapshot.currentDisclosureVersion,
                consentedAt: Date(timeIntervalSince1970: 1),
                updatedAt: Date(timeIntervalSince1970: 2)
            ),
            "KidProfileSnapshot": KidProfileSnapshot(profiles: []),
            "LearningRecordSnapshot": LearningRecordSnapshot(
                attempts: [],
                corrections: [],
                progress: []
            ),
            "PracticeSettingsSnapshot": PracticeSettingsSnapshot(settings: []),
            "WordPoolSnapshot": WordPoolSnapshot(entries: []),
        ]
        let reviewedInventory: [String: Set<String>] = [
            "ChildSessionSnapshot": [
                "schemaVersion", "lastSelectedProfileID",
            ],
            "DailyQuestSnapshot": [
                "schemaVersion",
                "canonicalBusinessKeyVersion",
                "plans",
                "completions",
                "rewardGrants",
                "pendingCompletions",
                "pendingRewardGrants",
            ],
            "FamilySyncJournalSnapshot": [
                "schemaVersion",
                "localManifest",
                "acknowledgedManifest",
                "outbox",
                "status",
            ],
            "FamilySyncApplyTransactionSnapshot": [
                "schemaVersion",
                "pending",
                "lastCommitted",
            ],
            "FamilySyncPreferenceSnapshot": [
                "schemaVersion",
                "isEnabled",
                "disclosureVersion",
                "consentedAt",
                "updatedAt",
            ],
            "KidProfileSnapshot": ["schemaVersion", "profiles"],
            "LearningRecordSnapshot": [
                "schemaVersion",
                "projectionAlgorithmVersion",
                "canonicalFactsChecksum",
                "attempts",
                "corrections",
                "correctionRoutes",
                "promptAliases",
                "progress",
            ],
            "PracticeSettingsSnapshot": ["schemaVersion", "settings"],
            "WordPoolSnapshot": ["schemaVersion", "entries"],
        ]
        XCTAssertEqual(Set(snapshots.keys), Set(reviewedInventory.keys))

        for (name, snapshot) in snapshots {
            XCTAssertEqual(
                try topLevelKeys(snapshot),
                reviewedInventory[name],
                "Persisted fields changed for \(name). Review its sync classification and update this inventory explicitly."
            )
        }

        let requiredEvidence = Set(
            reviewedInventory.flatMap { snapshotName, fields in
                fields.map { "snapshot:\(snapshotName).\($0)" }
            }
        )
        let manifestSnapshotEvidence = Set(
            FamilySyncDataManifest.entries.flatMap {
                evidenceIDs(for: $0) ?? []
            }.filter { $0.hasPrefix("snapshot:") }
        )
        XCTAssertEqual(
            manifestSnapshotEvidence,
            requiredEvidence,
            "Every persisted snapshot field needs exactly one reviewed machine evidence ID"
        )
    }

    private func evidenceIDs(
        for entry: FamilySyncDataManifestEntry
    ) -> Set<String>? {
        guard
            let value = Mirror(reflecting: entry).children.first(where: {
                $0.label == "evidenceIDs"
            })?.value
        else { return nil }
        if let set = value as? Set<String> { return set }
        if let array = value as? [String] { return Set(array) }
        return nil
    }

    private func topLevelKeys(_ value: any Encodable) throws -> Set<String> {
        let data = try InspectableSnapshotJSONCodec.makeEncoder().encode(value)
        let object = try XCTUnwrap(
            JSONSerialization.jsonObject(with: data) as? [String: Any]
        )
        return Set(object.keys)
    }
}
