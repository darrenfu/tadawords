import XCTest

@testable import TadaWordsFeatures

final class ReadAssistanceTests: XCTestCase {
    func testReadCaptureAllowsSixSeconds() {
        XCTAssertEqual(
            ReadSpeechCapturePolicy.maximumRecordingDuration.seconds,
            6
        )
    }

    func testHelpStaysHiddenUntilTwoValidWrongAnswers() {
        XCTAssertFalse(
            ReadAssistancePolicy.shouldReveal(
                validIncorrectAttemptCount: 0,
                isComplete: false
            )
        )
        XCTAssertFalse(
            ReadAssistancePolicy.shouldReveal(
                validIncorrectAttemptCount: 1,
                isComplete: false
            )
        )
        XCTAssertTrue(
            ReadAssistancePolicy.shouldReveal(
                validIncorrectAttemptCount: 2,
                isComplete: false
            )
        )
    }

    func testHelpIsNotLeftVisibleAfterCompletion() {
        XCTAssertFalse(
            ReadAssistancePolicy.shouldReveal(
                validIncorrectAttemptCount: 3,
                isComplete: true
            )
        )
    }
}
