import TadaWordsDomain
import XCTest

@testable import TadaWordsFeatures

final class SpellQuestTests: XCTestCase {
    func testEvaluationIgnoresCaseDiacriticsAndNonLetterStructure() {
        let evaluator = SpellingAnswerEvaluator()

        XCTAssertTrue(evaluator.matches("CANT", target: "can't"))
        XCTAssertTrue(evaluator.matches("cafe", target: "CAFÉ"))
        XCTAssertTrue(evaluator.matches("icecream", target: "ice-cream"))
        XCTAssertFalse(evaluator.matches("come", target: "came"))
        XCTAssertFalse(evaluator.matches("", target: "the"))
    }

    func testLetterKeyboardAcceptsOnlyAZAndStopsAtWordLength() {
        var state = LetterKeyboardInputState(maximumLetterCount: 2)

        XCTAssertTrue(state.append("O"))
        XCTAssertFalse(state.append("!"))
        XCTAssertTrue(state.append("F"))
        XCTAssertFalse(state.append("X"))
        XCTAssertEqual(state.response, "of")
        XCTAssertTrue(state.isFull)
    }

    func testDeleteAndClearKeepKeyboardStateDeterministic() {
        var state = LetterKeyboardInputState(
            maximumLetterCount: 4,
            response: "Go!!"
        )

        XCTAssertEqual(state.response, "go")
        XCTAssertTrue(state.removeLast())
        XCTAssertEqual(state.response, "g")
        state.clear()
        XCTAssertTrue(state.isEmpty)
        XCTAssertFalse(state.removeLast())
    }

    func testTypedAndHandwrittenWriteUseSeparatePaceContexts() throws {
        let prompt = try WordPrompt(
            learningMode: .write,
            text: "come"
        )

        let handwriting = prompt.paceContext(
            deviceClass: .tablet,
            writeInputMethod: .handwriting
        )
        let spelling = prompt.paceContext(
            deviceClass: .tablet,
            writeInputMethod: .letterKeyboard
        )

        XCTAssertEqual(handwriting.learningMode, .write)
        XCTAssertEqual(spelling.learningMode, .write)
        XCTAssertEqual(handwriting.inputMethod, .fingerWriting)
        XCTAssertEqual(spelling.inputMethod, .letterKeyboard)
        XCTAssertNotEqual(handwriting, spelling)
    }

    func testLetterKeyboardInputMethodRoundTripsThroughPersistedPaceContext()
        throws
    {
        let context = PaceContext(
            learningMode: .write,
            deviceClass: .phone,
            inputMethod: .letterKeyboard,
            wordLength: 2
        )

        let data = try JSONEncoder().encode(context)
        let restored = try JSONDecoder().decode(PaceContext.self, from: data)

        XCTAssertEqual(restored, context)
    }
}
