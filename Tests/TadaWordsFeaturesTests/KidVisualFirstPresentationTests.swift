import TadaWordsDesignSystem
import XCTest

@testable import TadaWordsFeatures

final class KidVisualFirstPresentationTests: XCTestCase {
    func testIdleReadMicrophoneNeedsNoVisibleInstruction() {
        XCTAssertNil(
            KidReadMicrophonePresentation.visibleStatus(
                isRequestingPermission: false,
                isListening: false
            )
        )
        XCTAssertEqual(
            KidReadMicrophonePresentation.visibleStatus(
                isRequestingPermission: false,
                isListening: true
            ),
            "Listening…"
        )
        XCTAssertEqual(
            KidReadMicrophonePresentation.visibleStatus(
                isRequestingPermission: true,
                isListening: false
            ),
            "Checking microphone…"
        )
    }

    func testIconOnlySubmissionControlsKeepAccessibleMeaningAndStableHooks() {
        XCTAssertEqual(
            Set(KidSubmissionControl.allCases.map(\.accessibilityIdentifier)),
            ["write.done", "spell.done"]
        )
        for control in KidSubmissionControl.allCases {
            XCTAssertEqual(control.accessibilityLabel, "Done")
            XCTAssertFalse(control.accessibilityHint.isEmpty)
            XCTAssertGreaterThanOrEqual(control.minimumTouchSize, 72)
        }
    }

    func testPrimaryKidActionTokenMeetsSeventyTwoPointAcceptanceTarget() {
        XCTAssertEqual(TadaChildScaleTokens.Action.primaryTouchDiameter, 72)
    }
}
