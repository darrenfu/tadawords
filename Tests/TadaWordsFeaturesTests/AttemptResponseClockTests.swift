import XCTest

@testable import TadaWordsFeatures

final class AttemptResponseClockTests: XCTestCase {
    func testResetExcludesEveryEarlierAttemptFromNextResponseTime() {
        var clock = AttemptResponseClock(startingAt: 100)

        XCTAssertEqual(clock.elapsed(at: 104), 4)
        clock.reset(at: 110)

        XCTAssertEqual(clock.elapsed(at: 112.5), 2.5)
    }

    func testClockFailsClosedForInvalidOrReversedElapsedValues() {
        var clock = AttemptResponseClock(startingAt: .infinity)
        XCTAssertEqual(clock.originElapsedSeconds, 0)
        XCTAssertEqual(clock.elapsed(at: -.infinity), 0)

        clock.reset(at: 5)
        XCTAssertEqual(clock.elapsed(at: 3), 0)
    }
}
