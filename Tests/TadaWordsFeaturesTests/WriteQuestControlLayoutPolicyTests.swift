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
}
