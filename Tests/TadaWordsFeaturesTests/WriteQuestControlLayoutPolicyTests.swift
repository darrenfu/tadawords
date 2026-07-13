import TadaWordsDomain
import XCTest

@testable import TadaWordsFeatures

final class WriteQuestControlLayoutPolicyTests: XCTestCase {
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
