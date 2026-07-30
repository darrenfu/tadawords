import TadaWordsDesignSystem
import TadaWordsDomain
import XCTest

@testable import TadaWordsFeatures

final class WriteQuestControlLayoutPolicyTests: XCTestCase {
    func testNextWordGetsBreathingRoomAfterTransitionAudio() {
        XCTAssertEqual(
            QuestAdvanceTimingPolicy.breathingRoom(hasNextItem: true),
            .milliseconds(700)
        )
    }

    func testFinalWordDoesNotAddAnInterItemPause() {
        XCTAssertEqual(
            QuestAdvanceTimingPolicy.breathingRoom(hasNextItem: false),
            .zero
        )
    }

    func testRightHandedLayoutKeepsPromptLeadingAndActionsTrailing() {
        XCTAssertEqual(
            WriteQuestControlLayoutPolicy.sideRails(
                leftHandedLayoutEnabled: false
            ),
            WriteQuestSideRailLayout(leading: .prompt, trailing: .actions)
        )
    }

    func testLeftHandedLayoutMovesWritingActionsToLeadingEdge() {
        XCTAssertEqual(
            WriteQuestControlLayoutPolicy.sideRails(
                leftHandedLayoutEnabled: true
            ),
            WriteQuestSideRailLayout(leading: .actions, trailing: .prompt)
        )
    }

    func testRegularCanvasIsTenPercentWiderThanPreviousLayout() {
        let availableWidth: CGFloat = 1_318
        let originalWidth =
            availableWidth
            - (TadaLayoutTokens.standardActionRailWidth * 2)
            - (22 * 2)

        let metrics = WriteQuestControlLayoutPolicy.metrics(
            availableWidth: availableWidth,
            isCompact: false
        )

        XCTAssertEqual(
            metrics.canvasWidth,
            originalWidth * WriteQuestControlLayoutPolicy.canvasWidthScale,
            accuracy: 0.001
        )
    }

    func testCompactCanvasIsTenPercentWiderThanPreviousLayout() {
        let availableWidth: CGFloat = 912
        let originalWidth =
            availableWidth
            - (TadaLayoutTokens.compactActionRailWidth * 2)
            - (10 * 2)

        let metrics = WriteQuestControlLayoutPolicy.metrics(
            availableWidth: availableWidth,
            isCompact: true
        )

        XCTAssertEqual(
            metrics.canvasWidth,
            originalWidth * WriteQuestControlLayoutPolicy.canvasWidthScale,
            accuracy: 0.001
        )
    }

    func testCompletionFeedbackRemainsVisibleLongerThanFourTenthsOfASecond() {
        XCTAssertGreaterThanOrEqual(
            WriteQuestTimingPolicy.completionFeedbackVisibility,
            Duration.milliseconds(400)
        )
    }

    func testRevealedWriteSpellingUsesAllCaps() {
        XCTAssertEqual(
            WriteQuestSpellingPresentation.revealedWord("Butterfly"),
            "BUTTERFLY"
        )
    }

    func testPictureHintIsRequestedOnlyForFirstIndependentMismatch() {
        XCTAssertTrue(
            WritePictureHintRequestPolicy.shouldRequest(
                decision: .notMatched,
                validAttemptCount: 0,
                usedGuidance: false
            )
        )
        XCTAssertFalse(
            WritePictureHintRequestPolicy.shouldRequest(
                decision: .uncertain,
                validAttemptCount: 0,
                usedGuidance: false
            )
        )
        XCTAssertFalse(
            WritePictureHintRequestPolicy.shouldRequest(
                decision: .notMatched,
                validAttemptCount: 1,
                usedGuidance: false
            )
        )
        XCTAssertFalse(
            WritePictureHintRequestPolicy.shouldRequest(
                decision: .notMatched,
                validAttemptCount: 0,
                usedGuidance: true
            )
        )
    }

    func testClearRemovesInkImmediatelyWithoutAConfirmationState() {
        var strokes = [
            InkStroke(points: []),
            InkStroke(points: []),
        ]

        let didClear = WriteQuestInkEditor.clear(&strokes)

        XCTAssertTrue(didClear)
        XCTAssertTrue(strokes.isEmpty)
    }

    func testClearDoesNotEmitFeedbackWhenCanvasIsAlreadyEmpty() {
        var strokes: [InkStroke] = []

        let didClear = WriteQuestInkEditor.clear(&strokes)

        XCTAssertFalse(didClear)
        XCTAssertTrue(strokes.isEmpty)
    }

    func testHelpImmediatelyRevealsWordAndMarksAttemptAsGuided() throws {
        var machine = QuestAttemptStateMachine(policy: .write)
        var strokes = [InkStroke(points: [])]

        WriteQuestHelpAction.revealWord(
            attemptState: &machine,
            strokes: &strokes
        )

        XCTAssertTrue(strokes.isEmpty)
        XCTAssertTrue(machine.beginAttempt())
        machine.receive(RecognitionResult(decision: .matched))
        let summary = try XCTUnwrap(machine.completedSummary)
        XCTAssertTrue(summary.usedGuidance)
        XCTAssertEqual(summary.completion, .completedWithGuidance)
        XCTAssertEqual(summary.records.map(\.evidence), [.helped, .guidedRetry])
    }

    func testRepeatedHelpTapsDoNotDuplicateGuidanceEvidence() throws {
        var machine = QuestAttemptStateMachine(policy: .write)
        var strokes: [InkStroke] = []

        WriteQuestHelpAction.revealWord(
            attemptState: &machine,
            strokes: &strokes
        )
        WriteQuestHelpAction.revealWord(
            attemptState: &machine,
            strokes: &strokes
        )

        XCTAssertTrue(machine.beginAttempt())
        machine.receive(RecognitionResult(decision: .matched))
        let summary = try XCTUnwrap(machine.completedSummary)
        XCTAssertEqual(
            summary.records.filter { $0.evidence == .helped }.count,
            1
        )
    }
}
