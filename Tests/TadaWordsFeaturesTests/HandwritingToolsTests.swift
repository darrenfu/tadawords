import CoreGraphics
import Foundation
import TadaWordsDomain
import XCTest

@testable import TadaWordsFeatures

final class HandwritingToolsTests: XCTestCase {
    func testSelectableToolsExcludeCrayonAndHaveDistinctStableLineWidths() {
        XCTAssertEqual(
            HandwritingToolPolicy.selectableTools,
            [.pencil, .chalk, .brush]
        )

        let widths = HandwritingToolPolicy.selectableTools.map {
            HandwritingToolPolicy.appearance(for: $0).lineWidth
        }

        XCTAssertEqual(widths.count, 3)
        XCTAssertEqual(Set(widths).count, widths.count)
    }

    func testEraserIsFourTimesTheCurrentToolWidth() {
        for tool in HandwritingToolPolicy.selectableTools {
            XCTAssertEqual(
                HandwritingToolPolicy.eraserLineWidth(for: tool),
                HandwritingToolPolicy.appearance(for: tool).lineWidth * 4,
                accuracy: 0.001
            )
        }
    }

    func testDefaultSelectionUsesBlackPencilWithoutEraser() {
        let selection = HandwritingSelectionState()

        XCTAssertEqual(selection.tool, .pencil)
        XCTAssertEqual(selection.ink, .basic(.black))
        XCTAssertFalse(selection.isErasing)
    }

    func testChangingToolKeepsBlackInkAndTurnsOffEraser() {
        var selection = HandwritingSelectionState()
        selection.toggleEraser()

        selection.selectTool(.brush)

        XCTAssertEqual(selection.tool, .brush)
        XCTAssertEqual(selection.ink, .basic(.black))
        XCTAssertFalse(selection.isErasing)
    }

    func testSelectingLegacyCrayonFallsBackToBlackPencil() {
        var selection = HandwritingSelectionState(tool: .chalk)

        selection.selectTool(.crayon)

        XCTAssertEqual(selection.tool, .pencil)
        XCTAssertEqual(selection.ink, .basic(.black))
    }

    func testErasingStopsWhenTheLastInkIsRemoved() {
        var selection = HandwritingSelectionState()
        selection.toggleEraser()

        selection.reconcileCanvas(hasInk: false)

        XCTAssertFalse(selection.isErasing)
        XCTAssertEqual(selection.tool, .pencil)
    }

    func testStoppingEraserRestoresThePreviouslySelectedBlackTool() {
        var selection = HandwritingSelectionState(tool: .brush)
        selection.toggleEraser()

        selection.stopErasing()

        XCTAssertFalse(selection.isErasing)
        XCTAssertEqual(selection.tool, .brush)
        XCTAssertEqual(selection.ink, .basic(.black))
    }

    func testPenPersistsIndependentlyForEachProfileWithBlackInk() throws {
        let suiteName = "HandwritingPreferenceStoreTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let store = HandwritingPreferenceStore(
            userDefaults: defaults,
            keyPrefix: "selection"
        )
        let firstProfile = ProfileID()
        let secondProfile = ProfileID()
        var firstSelection = HandwritingSelectionState(tool: .chalk)
        firstSelection.toggleEraser()

        store.save(firstSelection, for: firstProfile)

        XCTAssertEqual(
            store.selection(for: firstProfile),
            HandwritingSelectionState(tool: .chalk)
        )
        XCTAssertEqual(
            store.selection(for: secondProfile),
            HandwritingSelectionState()
        )
    }

    func testRemovingProfilePreferenceClearsOnlyItsPen() throws {
        let suiteName = "HandwritingPreferenceRemovalTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let store = HandwritingPreferenceStore(
            userDefaults: defaults,
            keyPrefix: "selection"
        )
        let deletedProfile = ProfileID()
        let retainedProfile = ProfileID()
        store.save(
            HandwritingSelectionState(tool: .chalk),
            for: deletedProfile
        )
        store.save(
            HandwritingSelectionState(tool: .brush),
            for: retainedProfile
        )

        store.remove(for: deletedProfile)

        XCTAssertEqual(
            store.selection(for: deletedProfile),
            HandwritingSelectionState()
        )
        XCTAssertEqual(
            store.selection(for: retainedProfile),
            HandwritingSelectionState(tool: .brush)
        )
    }

    func testLoadingLegacyCrayonPreferenceMigratesToBlackPencil() throws {
        let context = try preferenceStoreContext()
        defer { context.defaults.removePersistentDomain(forName: context.suiteName) }
        let profileID = ProfileID()
        try seedPreference(
            tool: .crayon,
            color: .black,
            profileID: profileID,
            defaults: context.defaults
        )

        XCTAssertEqual(
            context.store.selection(for: profileID),
            HandwritingSelectionState()
        )
        XCTAssertEqual(
            try storedPreference(for: profileID, defaults: context.defaults),
            StoredSelectionFixture(tool: "pencil", color: "black")
        )
    }

    func testLoadingLegacyNonBlackPreferenceMigratesToBlackPencil() throws {
        let context = try preferenceStoreContext()
        defer { context.defaults.removePersistentDomain(forName: context.suiteName) }
        let profileID = ProfileID()
        try seedPreference(
            tool: .brush,
            color: .purple,
            profileID: profileID,
            defaults: context.defaults
        )

        XCTAssertEqual(
            context.store.selection(for: profileID),
            HandwritingSelectionState()
        )
        XCTAssertEqual(
            try storedPreference(for: profileID, defaults: context.defaults),
            StoredSelectionFixture(tool: "pencil", color: "black")
        )
    }

    func testNewStrokeKeepsSelectedToolAndBlackInkSnapshot() {
        var selection = HandwritingSelectionState(tool: .chalk)
        let stroke = InkStroke(
            points: [point(x: 0.1), point(x: 0.2)],
            tool: selection.tool,
            ink: selection.ink
        )

        selection.selectTool(.brush)

        XCTAssertEqual(stroke.tool, .chalk)
        XCTAssertEqual(stroke.ink, .basic(.black))
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

    func testEraserKeepsAnUnrelatedSinglePointDot() {
        let dot = InkStroke(
            points: [point(x: 0.2, y: 0.2)],
            tool: .pencil,
            ink: .basic(.black)
        )

        let result = InkStrokeEraser.erase(
            strokes: [dot],
            along: [point(x: 0.9, y: 0.9)],
            canvasSize: CGSize(width: 100, height: 100),
            eraserLineWidth: 24
        )

        XCTAssertEqual(result, [dot])
    }

    func testConnectedDirectionChangesRemainOneStroke() {
        let points = HandwritingStrokePointCollector.appending(
            [
                point(x: 0.1, y: 0.2),
                point(x: 0.2, y: 0.8),
                point(x: 0.3, y: 0.2),
                point(x: 0.4, y: 0.8),
                point(x: 0.5, y: 0.2),
            ],
            to: [],
            canvasSize: CGSize(width: 200, height: 100)
        )

        XCTAssertEqual(points.count, 5)
    }

    func testFinalizingTapKeepsSinglePointDot() {
        let dot = point(x: 0.4, y: 0.2)

        let points = HandwritingStrokePointCollector.finalizing(
            [dot],
            with: dot,
            canvasSize: CGSize(width: 200, height: 100)
        )

        XCTAssertEqual(points, [dot])
    }

    private func preferenceStoreContext() throws -> (
        suiteName: String,
        defaults: UserDefaults,
        store: HandwritingPreferenceStore
    ) {
        let suiteName = "HandwritingMigrationTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        return (
            suiteName,
            defaults,
            HandwritingPreferenceStore(
                userDefaults: defaults,
                keyPrefix: "selection"
            )
        )
    }

    private func seedPreference(
        tool: HandwritingTool,
        color: BasicHandwritingInkColor,
        profileID: ProfileID,
        defaults: UserDefaults
    ) throws {
        let stored = StoredSelectionFixture(
            tool: tool.rawValue,
            color: color.rawValue
        )
        defaults.set(
            try JSONEncoder().encode(stored),
            forKey: preferenceKey(for: profileID)
        )
    }

    private func storedPreference(
        for profileID: ProfileID,
        defaults: UserDefaults
    ) throws -> StoredSelectionFixture {
        let data = try XCTUnwrap(
            defaults.data(forKey: preferenceKey(for: profileID))
        )
        return try JSONDecoder().decode(StoredSelectionFixture.self, from: data)
    }

    private func preferenceKey(for profileID: ProfileID) -> String {
        "selection.\(profileID.rawValue.uuidString.lowercased())"
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

    private struct StoredSelectionFixture: Codable, Equatable {
        let tool: String
        let color: String
    }
}
