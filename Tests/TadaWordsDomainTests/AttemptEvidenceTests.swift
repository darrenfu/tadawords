import Foundation
import XCTest

@testable import TadaWordsDomain

final class AttemptEvidenceTests: XCTestCase {
    func testOnlyFirstIndependentAttemptCountsForAccuracyAndMemory() {
        for evidence in EncounterEvidence.allCases {
            let expected = evidence == .firstIndependentAttempt
            XCTAssertEqual(evidence.countsTowardAccuracy, expected)
            XCTAssertEqual(evidence.canUpdateMemory, expected)
        }
    }

    func testTechnicalAndUncertainEvidenceCannotAffectMastery() {
        XCTAssertFalse(EncounterEvidence.technicalRetry.countsTowardAccuracy)
        XCTAssertFalse(EncounterEvidence.recognitionUncertain.countsTowardAccuracy)
        XCTAssertTrue(EncounterEvidence.technicalRetry.isTechnicalEvidence)
        XCTAssertTrue(EncounterEvidence.recognitionUncertain.isTechnicalEvidence)
    }

    func testCorrectionIsAnIndependentAppendOnlyFact() {
        let originalID = AttemptID(
            rawValue: UUID(uuidString: "00000000-0000-0000-0000-000000000001")!
        )
        let original = AttemptEvent(
            id: originalID,
            profileID: ProfileID(
                rawValue: UUID(uuidString: "00000000-0000-0000-0000-000000000002")!
            ),
            wordPromptID: WordPromptID(
                rawValue: UUID(uuidString: "00000000-0000-0000-0000-000000000003")!
            ),
            learningMode: .read,
            evidence: .firstIndependentAttempt,
            outcome: .incorrect,
            occurredAt: Date(timeIntervalSince1970: 100)
        )

        let correction = AttemptCorrectionEvent(
            originalAttemptID: original.id,
            correctedOutcome: .correct,
            reason: .guardianOverride,
            correctedAt: Date(timeIntervalSince1970: 200)
        )

        XCTAssertEqual(original.outcome, .incorrect)
        XCTAssertEqual(correction.originalAttemptID, original.id)
        XCTAssertEqual(correction.correctedOutcome, .correct)
        XCTAssertNotEqual(correction.correctedAt, original.occurredAt)
    }

    func testLegacyAttemptWithoutPaceContextStillDecodes() throws {
        let attempt = AttemptEvent(
            profileID: ProfileID(
                rawValue: try XCTUnwrap(
                    UUID(uuidString: "00000000-0000-0000-0000-000000000001")
                )
            ),
            wordPromptID: WordPromptID(
                rawValue: try XCTUnwrap(
                    UUID(uuidString: "00000000-0000-0000-0000-000000000002")
                )
            ),
            learningMode: .read,
            evidence: .firstIndependentAttempt,
            outcome: .correct,
            timing: AttemptTiming(
                speechOnsetLatency: ElapsedTime(seconds: 2)
            ),
            occurredAt: Date(timeIntervalSince1970: 100),
            paceContext: PaceContext(
                learningMode: .read,
                deviceClass: .phone,
                inputMethod: .speech,
                wordLength: 3
            )
        )
        let encoded = try JSONEncoder().encode(attempt)
        var object = try XCTUnwrap(
            JSONSerialization.jsonObject(with: encoded) as? [String: Any]
        )
        object.removeValue(forKey: "paceContext")

        let legacyData = try JSONSerialization.data(withJSONObject: object)
        let decoded = try JSONDecoder().decode(AttemptEvent.self, from: legacyData)

        XCTAssertNil(decoded.paceContext)
        XCTAssertEqual(decoded.id, attempt.id)
        XCTAssertEqual(decoded.timing, attempt.timing)
    }
}
