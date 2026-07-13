import XCTest

@testable import TadaWordsFeatures

@MainActor
final class QuestTimerModelTests: XCTestCase {
    func testOverlappingSuspensionsResumeOnlyAfterEveryReasonClears() {
        var now: TimeInterval = 0
        let timer = QuestTimerModel(
            emergencyAfter: 10,
            now: { now }
        )

        timer.start()
        now = 4
        timer.suspend(for: .promptPlayback)
        timer.suspend(for: .userPause)
        XCTAssertEqual(timer.elapsedSeconds, 4, accuracy: 0.001)
        XCTAssertFalse(timer.isRunning)

        now = 40
        timer.resume(from: .promptPlayback)
        XCTAssertFalse(timer.isRunning)
        XCTAssertEqual(timer.elapsedSeconds, 4, accuracy: 0.001)

        timer.resume(from: .userPause)
        XCTAssertTrue(timer.isRunning)
        now = 47
        timer.suspend(for: .saving)
        XCTAssertEqual(timer.elapsedSeconds, 11, accuracy: 0.001)
        XCTAssertTrue(timer.isEmergency)
    }

    func testFinishedTimerCannotRestartFromLateResume() {
        var now: TimeInterval = 0
        let timer = QuestTimerModel(
            emergencyAfter: 30,
            now: { now }
        )

        timer.start()
        now = 6
        timer.suspend(for: .handwritingRecognition)
        timer.stop()
        timer.resume(from: .handwritingRecognition)
        timer.resume(from: .appInactive)

        XCTAssertTrue(timer.isFinished)
        XCTAssertFalse(timer.isRunning)
        XCTAssertEqual(timer.elapsedSeconds, 6, accuracy: 0.001)
    }
}
