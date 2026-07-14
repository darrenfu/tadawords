import XCTest

@testable import TadaWordsGuardianFeatures

final class GuardianParentGateTests: XCTestCase {
    func testAnswerStaysIncompleteUntilExpectedDigitCount() {
        XCTAssertEqual(
            ParentGateAnswerPolicy.decision(input: "4", expectedAnswer: 42),
            .incomplete
        )
    }

    func testCompleteAnswerImmediatelyUnlocksOrRejects() {
        XCTAssertEqual(
            ParentGateAnswerPolicy.decision(input: "42", expectedAnswer: 42),
            .correct
        )
        XCTAssertEqual(
            ParentGateAnswerPolicy.decision(input: "41", expectedAnswer: 42),
            .incorrect
        )
        XCTAssertEqual(
            ParentGateAnswerPolicy.decision(input: "420", expectedAnswer: 42),
            .incorrect
        )
    }

    func testWrongAnswerFeedbackSurvivesProgrammaticClear() {
        XCTAssertTrue(
            ParentGateAnswerPolicy.shouldShowError(
                after: .incorrect,
                input: "41",
                wasShowingError: false
            )
        )
        XCTAssertTrue(
            ParentGateAnswerPolicy.shouldShowError(
                after: .incomplete,
                input: "",
                wasShowingError: true
            )
        )
        XCTAssertFalse(
            ParentGateAnswerPolicy.shouldShowError(
                after: .incomplete,
                input: "4",
                wasShowingError: true
            )
        )
    }
}
