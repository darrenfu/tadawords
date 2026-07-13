import Foundation
import XCTest

@testable import TadaWordsDomain

final class ProgressCompatibilityTests: XCTestCase {
    func testWordProgressDecodesSnapshotWrittenBeforeSignalAggregates() throws {
        let original = WordProgress(
            profileID: ProfileID(
                rawValue: try XCTUnwrap(
                    UUID(uuidString: "10000000-0000-0000-0000-000000000001")
                )
            ),
            wordPromptID: WordPromptID(
                rawValue: try XCTUnwrap(
                    UUID(uuidString: "20000000-0000-0000-0000-000000000001")
                )
            ),
            learningMode: .read,
            memoryState: MemoryState(
                stabilityDays: 2,
                nextReviewAt: Date(timeIntervalSince1970: 2_000_000_000)
            ),
            firstIndependentAttemptCount: 3,
            firstIndependentCorrectCount: 2
        )
        let encoded = try JSONEncoder().encode(original)
        var object = try XCTUnwrap(
            JSONSerialization.jsonObject(with: encoded) as? [String: Any]
        )
        for key in [
            "firstIndependentResponseTimeTotal",
            "firstIndependentTimedAttemptCount",
            "totalReplayCount",
            "helpedAttemptCount",
            "uncertainAttemptCount",
            "independentSuccessDates",
        ] {
            object.removeValue(forKey: key)
        }

        let legacyData = try JSONSerialization.data(withJSONObject: object)
        let decoded = try JSONDecoder().decode(WordProgress.self, from: legacyData)

        XCTAssertEqual(decoded.profileID, original.profileID)
        XCTAssertEqual(decoded.firstIndependentAttemptCount, 3)
        XCTAssertEqual(decoded.firstIndependentCorrectCount, 2)
        XCTAssertEqual(decoded.firstIndependentResponseTimeTotal, .zero)
        XCTAssertEqual(decoded.firstIndependentTimedAttemptCount, 0)
        XCTAssertEqual(decoded.totalReplayCount, 0)
        XCTAssertEqual(decoded.helpedAttemptCount, 0)
        XCTAssertEqual(decoded.uncertainAttemptCount, 0)
        XCTAssertTrue(decoded.independentSuccessDates.isEmpty)
    }
}
