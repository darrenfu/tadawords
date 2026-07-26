import CoreGraphics
import Foundation
import TadaWordsDomain
import XCTest

@testable import TadaWordsFeatures

final class QuestStarFeedbackTests: XCTestCase {
    func testEarnedEventCommitsExactlyOnceAtItsTargetSlot() {
        var state = QuestStarProgressState(earnedCount: 2)
        let event = QuestStarFeedbackEvent(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000000007")!,
            kind: .earned,
            targetSlot: 2
        )

        XCTAssertTrue(state.begin(event))
        XCTAssertTrue(state.commit(event))
        XCTAssertEqual(state.earnedCount, 3)

        XCTAssertFalse(state.begin(event))
        XCTAssertFalse(state.commit(event))
        XCTAssertEqual(state.earnedCount, 3)
    }

    func testMissedEventNeverChangesEarnedProgress() {
        var state = QuestStarProgressState(earnedCount: 2)
        let event = QuestStarFeedbackEvent(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000000008")!,
            kind: .missed,
            targetSlot: 2
        )

        XCTAssertTrue(state.begin(event))
        XCTAssertFalse(state.commit(event))
        XCTAssertEqual(state.earnedCount, 2)
    }

    func testTrajectoryTravelsBottomToTopAndEndsAtExactSlot() {
        let slotCenter = CGPoint(x: 132, y: 18)
        let source = CGPoint(x: 110, y: 496)
        let trajectory = QuestStarTrajectory(
            source: source,
            target: slotCenter,
            viewportSize: CGSize(width: 220, height: 800),
            targetSlot: 3
        )

        XCTAssertGreaterThan(trajectory.source.y, trajectory.target.y)
        XCTAssertEqual(trajectory.point(at: 0), trajectory.source)
        XCTAssertEqual(trajectory.point(at: 1), slotCenter)
        XCTAssertNotEqual(trajectory.control.x, trajectory.source.x)
    }

    func testTrajectoryUsesTheApprovedDemoBend() {
        let trajectory = QuestStarTrajectory(
            source: CGPoint(x: 110, y: 496),
            target: CGPoint(x: 132, y: 18),
            viewportSize: CGSize(width: 220, height: 800),
            targetSlot: 3
        )

        XCTAssertEqual(trajectory.control.x, 32.12, accuracy: 0.001)
        XCTAssertEqual(trajectory.control.y, 223.54, accuracy: 0.001)
    }

    func testEveryFlightFrameRecomputesTheBezierPosition() {
        let trajectory = QuestStarTrajectory(
            source: CGPoint(x: 110, y: 496),
            target: CGPoint(x: 132, y: 18),
            viewportSize: CGSize(width: 220, height: 800),
            targetSlot: 3
        )

        let frame = QuestStarFlightMotion.frame(
            rawProgress: 0.5,
            trajectory: trajectory
        )
        let linearMidpoint = CGPoint(
            x: (trajectory.source.x + trajectory.target.x) / 2,
            y: (trajectory.source.y + trajectory.target.y) / 2
        )

        XCTAssertEqual(frame.pathProgress, 0.875, accuracy: 0.001)
        XCTAssertEqual(
            frame.center.x,
            trajectory.point(at: frame.pathProgress).x,
            accuracy: 0.001
        )
        XCTAssertEqual(
            frame.center.y,
            trajectory.point(at: frame.pathProgress).y,
            accuracy: 0.001
        )
        XCTAssertNotEqual(frame.center, linearMidpoint)
    }

    func testTrailLayersEndAtTheStarAndFadeOverDifferentLengths() {
        let ranges = QuestStarFlightMotion.trailRanges(pathProgress: 0.75)

        XCTAssertEqual(ranges.map(\.upperBound), [0.75, 0.75, 0.75])
        XCTAssertEqual(ranges[0].lowerBound, 0.41, accuracy: 0.001)
        XCTAssertEqual(ranges[1].lowerBound, 0.51, accuracy: 0.001)
        XCTAssertEqual(ranges[2].lowerBound, 0.65, accuracy: 0.001)
    }

    func testMissFloorIsTenPercentAboveBottomWithVisibleBounce() {
        let trajectory = QuestStarTrajectory(
            source: CGPoint(x: 90, y: 496),
            target: CGPoint(x: 80, y: 18),
            viewportSize: CGSize(width: 180, height: 800),
            targetSlot: 1
        )

        XCTAssertEqual(trajectory.floorY, 720, accuracy: 0.001)
        XCTAssertGreaterThanOrEqual(trajectory.bounceHeight, 42)
        XCTAssertLessThanOrEqual(trajectory.bounceHeight, 64)
    }

    func testRelaunchSynchronizationRestoresPersistedEarnedCount() {
        var state = QuestStarProgressState(earnedCount: 0)

        state.synchronize(earnedCount: 4)

        XCTAssertEqual(state.earnedCount, 4)
    }

    func testEachFeedbackEventGetsAUniqueIdentity() {
        let first = QuestStarFeedbackEvent(kind: .missed, targetSlot: 1)
        let second = QuestStarFeedbackEvent(kind: .missed, targetSlot: 1)

        XCTAssertNotEqual(first.id, second.id)
    }

    func testUncertainAndNotHeardFailuresUseMissedStarFeedback() {
        XCTAssertEqual(
            QuestAttemptFeedbackPolicy.presentation(for: .uncertain),
            QuestAttemptFeedbackPresentation(kind: .missed, cue: .validRetry)
        )
        XCTAssertEqual(
            QuestAttemptFeedbackPolicy.presentation(
                for: .technicalFailure(.noUsableAudio)
            ),
            QuestAttemptFeedbackPresentation(kind: .missed, cue: .validRetry)
        )
        XCTAssertEqual(
            QuestAttemptFeedbackPolicy.presentation(
                for: .technicalFailure(.timedOut)
            ),
            QuestAttemptFeedbackPresentation(kind: .missed, cue: .validRetry)
        )
    }

    func testPermissionFailureStaysTechnicalAndDoesNotBlameChild() {
        XCTAssertEqual(
            QuestAttemptFeedbackPolicy.presentation(
                for: .technicalFailure(.permissionDenied)
            ),
            QuestAttemptFeedbackPresentation(kind: nil, cue: .technicalRetry)
        )
    }

    func testGlobalSlotCenterConvertsOnceIntoStableViewportCoordinates() {
        let viewport = CGRect(x: 40, y: 80, width: 820, height: 520)
        let slot = CGRect(x: 306, y: 102, width: 24, height: 24)

        XCTAssertEqual(
            QuestStarCoordinateSpace.localCenter(
                of: slot,
                in: viewport
            ),
            CGPoint(x: 278, y: 34)
        )
    }
}
