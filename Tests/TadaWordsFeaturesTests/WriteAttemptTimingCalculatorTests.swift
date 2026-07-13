import Foundation
import TadaWordsDomain
import TadaWordsLearning
import XCTest

@testable import TadaWordsFeatures

final class WriteAttemptTimingCalculatorTests: XCTestCase {
    func testPromptPlaybackIsRetainedForStorageAndExcludedOnceFromPace() throws {
        let sample = HandwritingSample(
            strokes: [
                HandwritingStroke(
                    points: [
                        point(at: 3),
                        point(at: 4),
                    ]
                ),
                HandwritingStroke(
                    points: [
                        point(at: 5),
                        point(at: 7),
                    ]
                ),
            ],
            inputMethod: .finger
        )

        let timing = WriteAttemptTimingCalculator().timing(
            for: sample,
            promptPlaybackSeconds: 2
        )

        XCTAssertEqual(timing.totalResponseTime?.seconds, 7)
        XCTAssertEqual(timing.firstStrokeLatency?.seconds, 1)
        XCTAssertEqual(timing.activeStrokeTime?.seconds, 3)
        XCTAssertEqual(timing.idleTime?.seconds, 1)
        XCTAssertEqual(timing.replayPauseTime?.seconds, 2)

        let attempt = AttemptEvent(
            profileID: ProfileID(),
            wordPromptID: WordPromptID(),
            learningMode: .write,
            evidence: .firstIndependentAttempt,
            outcome: .correct,
            timing: timing,
            occurredAt: Date(timeIntervalSince1970: 1)
        )
        let measurement = try XCTUnwrap(
            AttemptPaceMeasurementExtractor().measurement(
                from: attempt,
                context: PaceContext(
                    learningMode: .write,
                    deviceClass: .tablet,
                    inputMethod: .fingerWriting,
                    wordLength: 4
                )
            )
        )
        XCTAssertEqual(measurement.elapsedTime.seconds, 5)
    }

    func testEmptySampleHasNoFabricatedTiming() {
        let timing = WriteAttemptTimingCalculator().timing(
            for: HandwritingSample(strokes: [], inputMethod: .finger),
            promptPlaybackSeconds: 2
        )

        XCTAssertEqual(timing, .unmeasured)
    }

    private func point(at seconds: TimeInterval) -> HandwritingPoint {
        HandwritingPoint(
            location: NormalizedPoint(x: 0.5, y: 0.5),
            elapsedSincePrompt: ElapsedTime(seconds: seconds)
        )
    }
}
