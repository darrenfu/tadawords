import TadaWordsDomain
import XCTest

@testable import TadaWordsGuardianFeatures

final class GuardianWordStoreTests: XCTestCase {
    func testOCRPreviewSkipsExistingDuplicatesAndInvalidEdits() {
        let existing = Set(["cat"])
        let ready = GuardianEditableOCRWord(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000000001")!,
            text: "Dog"
        )
        let inPool = GuardianEditableOCRWord(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000000002")!,
            text: "CAT"
        )
        let duplicate = GuardianEditableOCRWord(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000000003")!,
            text: "dog"
        )
        let invalid = GuardianEditableOCRWord(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000000004")!,
            text: "123"
        )

        let analysis = GuardianOCRPreviewAnalysis(
            words: [ready, inPool, duplicate, invalid],
            existingNormalizedWords: existing
        )

        XCTAssertEqual(analysis.addableWords, ["dog"])
        XCTAssertEqual(analysis.stateByID[ready.id], .ready(normalizedWord: "dog"))
        XCTAssertEqual(analysis.stateByID[inPool.id], .alreadyInPool)
        XCTAssertEqual(analysis.stateByID[duplicate.id], .duplicateInPreview)
        XCTAssertEqual(analysis.stateByID[invalid.id], .invalid)
    }

    func testImportReportsAcceptedDuplicatesAndRejectedWords() async throws {
        let store = DemoGuardianWordStore()

        let report = try await store.importWords(
            GuardianWordImportRequest(
                rawText: "cat cat the bad!",
                learningMode: .read
            )
        )

        XCTAssertEqual(report.accepted, ["cat"])
        XCTAssertEqual(report.duplicates, ["the", "cat"])
        XCTAssertEqual(report.rejected.map(\.sourceText), ["bad!"])
    }

    func testSameWordCanBelongToSeparateReadAndWritePools() async throws {
        let store = DemoGuardianWordStore()

        let readReport = try await store.importWords(
            GuardianWordImportRequest(rawText: "jump", learningMode: .read)
        )
        let writeReport = try await store.importWords(
            GuardianWordImportRequest(rawText: "jump", learningMode: .write)
        )
        let snapshot = try await store.dashboardSnapshot()

        XCTAssertEqual(readReport.accepted, ["jump"])
        XCTAssertEqual(writeReport.accepted, ["jump"])
        XCTAssertTrue(snapshot.readPool.contains { $0.normalizedText == "jump" })
        XCTAssertTrue(snapshot.writePool.contains { $0.normalizedText == "jump" })
    }

    func testDefaultAndUpdatedPracticeSettings() async throws {
        let store = DemoGuardianWordStore()

        let initialSnapshot = try await store.dashboardSnapshot()
        XCTAssertEqual(
            initialSnapshot.practiceSettings,
            .defaults(for: initialSnapshot.profile.id)
        )

        let settings = ProfilePracticeSettings(
            profileID: initialSnapshot.profile.id,
            read: LearningRouteSettings(
                newWordLimit: 7,
                reviewWordLimit: 6,
                contentOrder: .reviewThenNew,
                emergencyAfterSeconds: 240
            ),
            write: LearningRouteSettings(
                newWordLimit: 4,
                reviewWordLimit: 2,
                contentOrder: .newThenReview,
                emergencyAfterSeconds: 420
            )
        )
        let updatedSnapshot = try await store.updatePracticeSettings(settings)

        XCTAssertEqual(updatedSnapshot.practiceSettings, settings)
    }
}
