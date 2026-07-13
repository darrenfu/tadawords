import TadaWordsDomain
import XCTest

@testable import TadaWordsLearning

final class PersonalPaceEvaluatorTests: XCTestCase {
    func testFirstThreeComparableSamplesAreCalibrationHistory() {
        let context = TestFixture.paceContext()
        let assessment = PersonalPaceEvaluator().assess(
            measurements: [
                PaceMeasurement(
                    context: context,
                    elapsedTime: ElapsedTime(seconds: 2)
                )
            ],
            personalBands: [
                TestFixture.paceBand(context: context, sampleCount: 2)
            ]
        )

        XCTAssertEqual(
            assessment,
            .calibrating(sampleCount: 2, requiredSampleCount: 3)
        )
    }

    func testConfiguredMinimumCannotDropBelowThreeSamples() {
        let context = TestFixture.paceContext()
        let assessment = PersonalPaceEvaluator(
            requiredBaselineSampleCount: 2
        ).assess(
            measurements: [
                PaceMeasurement(
                    context: context,
                    elapsedTime: ElapsedTime(seconds: 2)
                )
            ],
            personalBands: [
                TestFixture.paceBand(context: context, sampleCount: 2)
            ]
        )

        XCTAssertEqual(
            assessment,
            .calibrating(sampleCount: 2, requiredSampleCount: 3)
        )
    }

    func testMajorityMustBeWithinBandAndTooFastIsNotBetter() {
        let context = TestFixture.paceContext()
        let band = TestFixture.paceBand(context: context)
        let withinAssessment = PersonalPaceEvaluator().assess(
            measurements: [0.2, 2, 2.5].map {
                PaceMeasurement(
                    context: context,
                    elapsedTime: ElapsedTime(seconds: $0)
                )
            },
            personalBands: [band]
        )
        let outsideAssessment = PersonalPaceEvaluator().assess(
            measurements: [0.2, 0.3, 2].map {
                PaceMeasurement(
                    context: context,
                    elapsedTime: ElapsedTime(seconds: $0)
                )
            },
            personalBands: [band]
        )

        XCTAssertEqual(withinAssessment, .withinPersonalBand)
        XCTAssertEqual(outsideAssessment, .outsidePersonalBand)
    }

    func testSlowSideGetsTwentyFivePercentRewardGrace() {
        let context = TestFixture.paceContext()
        let band = TestFixture.paceBand(
            context: context,
            lower: 1,
            upper: 3
        )

        let slightlySlow = PersonalPaceEvaluator().assess(
            measurements: [
                PaceMeasurement(
                    context: context,
                    elapsedTime: ElapsedTime(seconds: 3.6)
                )
            ],
            personalBands: [band]
        )
        let beyondGrace = PersonalPaceEvaluator().assess(
            measurements: [
                PaceMeasurement(
                    context: context,
                    elapsedTime: ElapsedTime(seconds: 3.8)
                )
            ],
            personalBands: [band]
        )

        XCTAssertEqual(slightlySlow, .withinPersonalBand)
        XCTAssertEqual(beyondGrace, .outsidePersonalBand)
    }

    func testFastEdgeDoesNotReceiveSymmetricGrace() {
        let context = TestFixture.paceContext()
        let assessment = PersonalPaceEvaluator().assess(
            measurements: [
                PaceMeasurement(
                    context: context,
                    elapsedTime: ElapsedTime(seconds: 0.9)
                )
            ],
            personalBands: [
                TestFixture.paceBand(
                    context: context,
                    lower: 1,
                    upper: 3
                )
            ]
        )

        XCTAssertEqual(assessment, .outsidePersonalBand)
    }

    func testDeviceClassIsPartOfComparablePaceContext() {
        let tabletContext = TestFixture.paceContext()
        let phoneContext = PaceContext(
            learningMode: .read,
            deviceClass: .phone,
            inputMethod: .speech,
            wordLength: 3
        )

        let assessment = PersonalPaceEvaluator().assess(
            measurements: [
                PaceMeasurement(
                    context: phoneContext,
                    elapsedTime: ElapsedTime(seconds: 2)
                )
            ],
            personalBands: [TestFixture.paceBand(context: tabletContext)]
        )

        XCTAssertEqual(
            assessment,
            .calibrating(sampleCount: 0, requiredSampleCount: 3)
        )
    }
}
