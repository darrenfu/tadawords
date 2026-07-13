import TadaWordsDomain
import XCTest

@testable import TadaWordsLearning

final class PersonalPaceBaselineBuilderTests: XCTestCase {
    func testThreeHistoricalSamplesBuildAComfortableBandForTheNextQuest() throws {
        let context = TestFixture.paceContext()
        let measurements = [1.8, 2.0, 2.2].map {
            PaceMeasurement(
                context: context,
                elapsedTime: ElapsedTime(seconds: $0)
            )
        }

        let band = try XCTUnwrap(
            PersonalPaceBaselineBuilder().bands(from: measurements).first
        )

        XCTAssertEqual(band.context, context)
        XCTAssertEqual(band.sampleCount, 3)
        XCTAssertTrue(band.contains(ElapsedTime(seconds: 2)))
        XCTAssertFalse(band.contains(ElapsedTime(seconds: 0.2)))
        XCTAssertFalse(band.contains(ElapsedTime(seconds: 8)))
    }

    func testContextDimensionsRemainStrictlySeparated() {
        let tabletRead = TestFixture.paceContext()
        let phoneRead = PaceContext(
            learningMode: .read,
            deviceClass: .phone,
            inputMethod: .speech,
            wordLength: 3
        )
        let tabletWrite = PaceContext(
            learningMode: .write,
            deviceClass: .tablet,
            inputMethod: .fingerWriting,
            wordLength: 3
        )
        let longerRead = PaceContext(
            learningMode: .read,
            deviceClass: .tablet,
            inputMethod: .speech,
            wordLength: 4
        )
        let contexts = [tabletRead, phoneRead, tabletWrite, longerRead]
        let measurements = contexts.flatMap { context in
            [1.8, 2, 2.2].map {
                PaceMeasurement(
                    context: context,
                    elapsedTime: ElapsedTime(seconds: $0)
                )
            }
        }

        let bands = PersonalPaceBaselineBuilder().bands(from: measurements)

        XCTAssertEqual(bands.count, contexts.count)
        XCTAssertEqual(Set(bands.map(\.context)), Set(contexts))
        XCTAssertTrue(bands.allSatisfy { $0.sampleCount == 3 })
    }

    func testWriteTimingExcludesReplayPause() throws {
        let context = TestFixture.paceContext(mode: .write)
        let attempt = TestFixture.attempt(
            number: 1,
            wordNumber: 1,
            mode: .write,
            outcome: .correct,
            responseSeconds: nil
        )
        let timedAttempt = AttemptEvent(
            id: attempt.id,
            questID: attempt.questID,
            profileID: attempt.profileID,
            wordPromptID: attempt.wordPromptID,
            learningMode: attempt.learningMode,
            evidence: attempt.evidence,
            outcome: attempt.outcome,
            timing: AttemptTiming(
                totalResponseTime: ElapsedTime(seconds: 6),
                replayPauseTime: ElapsedTime(seconds: 2)
            ),
            occurredAt: attempt.occurredAt
        )

        let measurement = try XCTUnwrap(
            AttemptPaceMeasurementExtractor().measurement(
                from: timedAttempt,
                context: context
            )
        )

        XCTAssertEqual(measurement.elapsedTime.seconds, 4)
    }
}
