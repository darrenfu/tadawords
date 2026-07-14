import CoreGraphics
import TadaWordsDomain
import XCTest

@testable import TadaWordsFeatures

final class HandwritingToolsTests: XCTestCase {
    func testEveryToolHasADistinctStableLineWidth() {
        let widths = HandwritingTool.allCases.map {
            HandwritingToolPolicy.appearance(for: $0).lineWidth
        }

        XCTAssertEqual(widths.count, 4)
        XCTAssertEqual(Set(widths).count, widths.count)
    }

    func testEraserIsTwoAndAHalfTimesTheCurrentToolWidth() {
        for tool in HandwritingTool.allCases {
            XCTAssertEqual(
                HandwritingToolPolicy.eraserLineWidth(for: tool),
                HandwritingToolPolicy.appearance(for: tool).lineWidth * 2.5,
                accuracy: 0.001
            )
        }
    }

    func testPaletteHasTwelveUniquelyNamedUniqueBasicColors() {
        let colors = BasicHandwritingInkColor.allCases

        XCTAssertEqual(colors.count, 12)
        XCTAssertEqual(Set(colors.map(\.accessibilityName)).count, 12)
        XCTAssertEqual(Set(colors.map(\.rgb)).count, 12)
    }

    func testChangingToolKeepsColorAndTurnsOffEraser() {
        var selection = HandwritingSelectionState()
        selection.selectInk(.basic(.pink))
        selection.toggleEraser()

        selection.selectTool(.brush)

        XCTAssertEqual(selection.tool, .brush)
        XCTAssertEqual(selection.ink, .basic(.pink))
        XCTAssertFalse(selection.isErasing)
    }

    func testChangingColorDoesNotChangeTool() {
        var selection = HandwritingSelectionState()
        selection.selectTool(.chalk)

        selection.selectInk(.basic(.blue))

        XCTAssertEqual(selection.tool, .chalk)
        XCTAssertEqual(selection.ink, .basic(.blue))
    }

    func testErasingStopsWhenTheLastInkIsRemoved() {
        var selection = HandwritingSelectionState()
        selection.toggleEraser()

        selection.reconcileCanvas(hasInk: false)

        XCTAssertFalse(selection.isErasing)
        XCTAssertEqual(selection.tool, .pencil)
    }

    func testStrokeKeepsToolAndColorSnapshotAfterSelectionChanges() {
        var selection = HandwritingSelectionState()
        selection.selectTool(.crayon)
        selection.selectInk(.basic(.orange))
        let stroke = InkStroke(
            points: [point(x: 0.1), point(x: 0.2)],
            tool: selection.tool,
            ink: selection.ink
        )

        selection.selectTool(.brush)
        selection.selectInk(.basic(.purple))

        XCTAssertEqual(stroke.tool, .crayon)
        XCTAssertEqual(stroke.ink, .basic(.orange))
    }

    func testEraserSplitsOnlyTheHitSectionAndKeepsOriginalPointData() {
        let originalPoints = [0.1, 0.2, 0.3, 0.4, 0.5, 0.6, 0.7].map {
            point(x: $0)
        }
        let stroke = InkStroke(
            points: originalPoints,
            inputMethod: .pencil,
            tool: .crayon,
            ink: .basic(.green)
        )

        let result = InkStrokeEraser.erase(
            strokes: [stroke],
            along: [point(x: 0.4)],
            canvasSize: CGSize(width: 100, height: 100),
            eraserLineWidth: 15
        )

        XCTAssertEqual(result.count, 2)
        guard result.count == 2 else {
            XCTFail("Expected two surviving fragments, got \(result.map { $0.points.count })")
            return
        }
        XCTAssertEqual(result[0].points, Array(originalPoints[0...2]))
        XCTAssertEqual(result[1].points, Array(originalPoints[4...6]))
        XCTAssertTrue(result.allSatisfy { $0.inputMethod == .pencil })
        XCTAssertTrue(result.allSatisfy { $0.tool == .crayon })
        XCTAssertTrue(result.allSatisfy { $0.ink == .basic(.green) })
    }

    func testEraserLeavesAnUnrelatedStrokeUntouched() {
        let first = InkStroke(
            points: [point(x: 0.1, y: 0.2), point(x: 0.2, y: 0.2)]
        )
        let second = InkStroke(
            points: [point(x: 0.7, y: 0.8), point(x: 0.8, y: 0.8)],
            tool: .brush,
            ink: .basic(.red)
        )

        let result = InkStrokeEraser.erase(
            strokes: [first, second],
            along: [point(x: 0.15, y: 0.2)],
            canvasSize: CGSize(width: 200, height: 100),
            eraserLineWidth: 20
        )

        XCTAssertEqual(result.count, 1)
        XCTAssertEqual(result[0].id, second.id)
        XCTAssertEqual(result[0].points, second.points)
        XCTAssertEqual(result[0].tool, .brush)
        XCTAssertEqual(result[0].ink, .basic(.red))
    }

    func testEraserMissIsANoOp() {
        let stroke = InkStroke(
            points: [point(x: 0.1, y: 0.1), point(x: 0.2, y: 0.1)]
        )

        let result = InkStrokeEraser.erase(
            strokes: [stroke],
            along: [point(x: 0.9, y: 0.9)],
            canvasSize: CGSize(width: 100, height: 100),
            eraserLineWidth: 15
        )

        XCTAssertEqual(result.map(\.id), [stroke.id])
        XCTAssertEqual(result[0].points, stroke.points)
    }

    private func point(
        x: Double,
        y: Double = 0.5
    ) -> HandwritingPoint {
        HandwritingPoint(
            location: NormalizedPoint(x: x, y: y),
            elapsedSincePrompt: ElapsedTime(seconds: x)
        )
    }
}
