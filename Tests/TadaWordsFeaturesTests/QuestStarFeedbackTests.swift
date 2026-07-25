import CoreGraphics
import Foundation
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
}
