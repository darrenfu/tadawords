import CoreGraphics
import Foundation
import SwiftUI
import TadaWordsContent
import TadaWordsDomain

enum BasicHandwritingInkColor: String, CaseIterable, Hashable {
    case black
    case gray
    case brown
    case red
    case orange
    case yellow
    case green
    case teal
    case blue
    case indigo
    case purple
    case pink

    var accessibilityName: String {
        rawValue.capitalized
    }

    var rgb: HandwritingRGB {
        switch self {
        case .black:
            HandwritingRGB(red: 0.10, green: 0.12, blue: 0.16)
        case .gray:
            HandwritingRGB(red: 0.36, green: 0.40, blue: 0.46)
        case .brown:
            HandwritingRGB(red: 0.48, green: 0.27, blue: 0.14)
        case .red:
            HandwritingRGB(red: 0.86, green: 0.16, blue: 0.19)
        case .orange:
            HandwritingRGB(red: 0.94, green: 0.39, blue: 0.08)
        case .yellow:
            HandwritingRGB(red: 0.78, green: 0.56, blue: 0.00)
        case .green:
            HandwritingRGB(red: 0.09, green: 0.54, blue: 0.25)
        case .teal:
            HandwritingRGB(red: 0.00, green: 0.52, blue: 0.55)
        case .blue:
            HandwritingRGB(red: 0.06, green: 0.36, blue: 0.84)
        case .indigo:
            HandwritingRGB(red: 0.25, green: 0.25, blue: 0.68)
        case .purple:
            HandwritingRGB(red: 0.52, green: 0.20, blue: 0.72)
        case .pink:
            HandwritingRGB(red: 0.86, green: 0.20, blue: 0.51)
        }
    }

    var color: Color {
        Color(red: rgb.red, green: rgb.green, blue: rgb.blue)
    }
}

struct HandwritingRGB: Hashable {
    let red: Double
    let green: Double
    let blue: Double
}

enum HandwritingInkChoice: Hashable {
    case theme
    case basic(BasicHandwritingInkColor)

    var accessibilityName: String {
        switch self {
        case .theme:
            "World ink"
        case .basic(let basicColor):
            basicColor.accessibilityName
        }
    }

    func color(themeInk: Color) -> Color {
        switch self {
        case .theme:
            themeInk
        case .basic(let basicColor):
            basicColor.color
        }
    }
}

struct HandwritingToolAppearance: Equatable {
    let lineWidth: CGFloat
    let opacity: CGFloat
    let dash: [CGFloat]
    let respondsToPressure: Bool
}

enum HandwritingToolPolicy {
    /// The tools offered to children in Write Practice. Crayon remains in the
    /// shared domain enum so legacy strokes and audio data can still decode,
    /// but it is no longer selectable for new writing.
    static let selectableTools: [HandwritingTool] = [
        .pencil,
        .chalk,
        .brush,
    ]

    static func selectableTool(orPencil tool: HandwritingTool) -> HandwritingTool {
        selectableTools.contains(tool) ? tool : .pencil
    }

    static func appearance(for tool: HandwritingTool) -> HandwritingToolAppearance {
        switch tool {
        case .pencil:
            HandwritingToolAppearance(
                lineWidth: 6,
                opacity: 0.92,
                dash: [],
                respondsToPressure: true
            )
        case .crayon:
            HandwritingToolAppearance(
                lineWidth: 11,
                opacity: 0.76,
                dash: [8, 1.8],
                respondsToPressure: false
            )
        case .chalk:
            HandwritingToolAppearance(
                lineWidth: 13,
                opacity: 0.56,
                dash: [3, 3.5],
                respondsToPressure: false
            )
        case .brush:
            HandwritingToolAppearance(
                lineWidth: 15,
                opacity: 0.90,
                dash: [],
                respondsToPressure: true
            )
        }
    }

    static func eraserLineWidth(for tool: HandwritingTool) -> CGFloat {
        appearance(for: tool).lineWidth * 4
    }

    static func lineWidth(
        for tool: HandwritingTool,
        pressure: Double?
    ) -> CGFloat {
        let appearance = appearance(for: tool)
        guard appearance.respondsToPressure,
            let pressure,
            pressure.isFinite
        else {
            return appearance.lineWidth
        }
        let clampedPressure = min(1, max(0, pressure))
        let scale = 0.72 + (0.58 * clampedPressure)
        return appearance.lineWidth * scale
    }

    static func displayName(for tool: HandwritingTool) -> String {
        switch tool {
        case .pencil: "Pencil"
        case .crayon: "Crayon"
        case .chalk: "Chalk"
        case .brush: "Brush"
        }
    }

    static func symbol(for tool: HandwritingTool) -> String {
        switch tool {
        case .pencil: "pencil"
        case .crayon: "pencil.and.outline"
        case .chalk: "scribble.variable"
        case .brush: "paintbrush.pointed.fill"
        }
    }
}

struct HandwritingSelectionState: Equatable {
    private(set) var tool: HandwritingTool = .pencil
    private(set) var isErasing = false

    /// Write Practice intentionally uses one high-contrast ink. Keeping this
    /// as a computed value prevents hidden or restored state from creating a
    /// new non-black stroke after the color picker was removed.
    var ink: HandwritingInkChoice { .basic(.black) }

    init(
        tool: HandwritingTool = .pencil,
        isErasing: Bool = false
    ) {
        self.tool = HandwritingToolPolicy.selectableTool(orPencil: tool)
        self.isErasing = isErasing
    }

    mutating func selectTool(_ newTool: HandwritingTool) {
        tool = HandwritingToolPolicy.selectableTool(orPencil: newTool)
        isErasing = false
    }

    mutating func toggleEraser() {
        isErasing.toggle()
    }

    mutating func stopErasing() {
        isErasing = false
    }

    mutating func reconcileCanvas(hasInk: Bool) {
        if !hasInk {
            isErasing = false
        }
    }
}

/// Stores only the durable pen choice. The legacy color field remains in the
/// payload so existing preferences decode safely; all newly stored selections
/// use black. Eraser mode is deliberately transient so a child always returns
/// to a drawing tool in a later session.
public struct HandwritingPreferenceStore: LegacyHandwritingPreferenceMigrating,
    @unchecked Sendable
{
    private let userDefaults: UserDefaults
    private let keyPrefix: String

    public init(
        userDefaults: UserDefaults = .standard,
        keyPrefix: String = "tada.handwriting.selection"
    ) {
        self.userDefaults = userDefaults
        self.keyPrefix = keyPrefix
    }

    func selection(for profileID: ProfileID) -> HandwritingSelectionState {
        guard let data = userDefaults.data(forKey: key(for: profileID)) else {
            return HandwritingSelectionState()
        }
        guard let stored = try? JSONDecoder().decode(StoredSelection.self, from: data),
            let tool = HandwritingTool(rawValue: stored.tool),
            let color = BasicHandwritingInkColor(rawValue: stored.color),
            HandwritingToolPolicy.selectableTools.contains(tool),
            color == .black
        else {
            return migrateToDefault(for: profileID)
        }
        return HandwritingSelectionState(tool: tool)
    }

    func save(
        _ selection: HandwritingSelectionState,
        for profileID: ProfileID
    ) {
        let stored = StoredSelection(
            tool: HandwritingToolPolicy.selectableTool(orPencil: selection.tool).rawValue,
            color: BasicHandwritingInkColor.black.rawValue
        )
        guard let data = try? JSONEncoder().encode(stored) else { return }
        userDefaults.set(data, forKey: key(for: profileID))
    }

    public func remove(for profileID: ProfileID) {
        userDefaults.removeObject(forKey: key(for: profileID))
    }

    public func consumeLegacyTool(
        for profileID: ProfileID
    ) -> HandwritingTool? {
        guard let data = userDefaults.data(forKey: key(for: profileID)) else {
            return nil
        }
        defer { remove(for: profileID) }
        guard
            let stored = try? JSONDecoder().decode(StoredSelection.self, from: data),
            let tool = HandwritingTool(rawValue: stored.tool)
        else {
            return .pencil
        }
        return HandwritingToolPolicy.selectableTool(orPencil: tool)
    }

    private func key(for profileID: ProfileID) -> String {
        "\(keyPrefix).\(profileID.rawValue.uuidString.lowercased())"
    }

    private func migrateToDefault(for profileID: ProfileID) -> HandwritingSelectionState {
        let selection = HandwritingSelectionState()
        save(selection, for: profileID)
        return selection
    }

    private struct StoredSelection: Codable {
        let tool: String
        let color: String
    }
}

enum HandwritingStrokePointCollector {
    /// Coalesced touch streams can repeat the same location many times. Keeping
    /// only visible movement reduces redraw work without splitting a connected
    /// shape (for example, a child drawing "vv" continuously as "w").
    static func appending(
        _ candidates: [HandwritingPoint],
        to existing: [HandwritingPoint],
        canvasSize: CGSize,
        minimumCanvasDistance: CGFloat = 0.5
    ) -> [HandwritingPoint] {
        var result = existing
        for candidate in candidates {
            guard let previous = result.last else {
                result.append(candidate)
                continue
            }
            let previousPoint = canvasPoint(
                for: previous,
                canvasSize: canvasSize
            )
            let candidatePoint = canvasPoint(
                for: candidate,
                canvasSize: canvasSize
            )
            guard
                hypot(
                    candidatePoint.x - previousPoint.x,
                    candidatePoint.y - previousPoint.y
                ) >= minimumCanvasDistance
            else { continue }
            result.append(candidate)
        }
        return result
    }

    /// A tap is a real one-point stroke (the dot over an i, for example), not an
    /// empty gesture. A moved finger adds the final location once.
    static func finalizing(
        _ existing: [HandwritingPoint],
        with finalPoint: HandwritingPoint,
        canvasSize: CGSize
    ) -> [HandwritingPoint] {
        appending(
            [finalPoint],
            to: existing,
            canvasSize: canvasSize
        )
    }

    private static func canvasPoint(
        for point: HandwritingPoint,
        canvasSize: CGSize
    ) -> CGPoint {
        CGPoint(
            x: CGFloat(point.location.x) * canvasSize.width,
            y: CGFloat(point.location.y) * canvasSize.height
        )
    }
}

enum InkStrokeEraser {
    static func erase(
        strokes: [InkStroke],
        along eraserPoints: [HandwritingPoint],
        canvasSize: CGSize,
        eraserLineWidth: CGFloat
    ) -> [InkStroke] {
        guard !strokes.isEmpty, !eraserPoints.isEmpty,
            canvasSize.width > 0, canvasSize.height > 0,
            eraserLineWidth > 0
        else {
            return strokes
        }

        let eraserPath = eraserPoints.map {
            canvasPoint(for: $0, canvasSize: canvasSize)
        }
        let hitRadius = eraserLineWidth / 2

        return strokes.flatMap { stroke in
            fragments(
                of: stroke,
                outside: eraserPath,
                canvasSize: canvasSize,
                hitRadius: hitRadius
            )
        }
    }

    private static func fragments(
        of stroke: InkStroke,
        outside eraserPath: [CGPoint],
        canvasSize: CGSize,
        hitRadius: CGFloat
    ) -> [InkStroke] {
        guard !stroke.points.isEmpty else { return [] }

        var fragments: [[HandwritingPoint]] = []
        var activeFragment: [HandwritingPoint] = []

        func finishFragment() {
            guard !activeFragment.isEmpty else {
                activeFragment.removeAll(keepingCapacity: true)
                return
            }
            fragments.append(activeFragment)
            activeFragment.removeAll(keepingCapacity: true)
        }

        for index in stroke.points.indices {
            let point = stroke.points[index]
            let currentCanvasPoint = canvasPoint(for: point, canvasSize: canvasSize)
            if pointIsHit(currentCanvasPoint, by: eraserPath, radius: hitRadius) {
                finishFragment()
                continue
            }

            if index > stroke.points.startIndex {
                let previous = stroke.points[stroke.points.index(before: index)]
                let previousCanvasPoint = canvasPoint(
                    for: previous,
                    canvasSize: canvasSize
                )
                if segmentIsHit(
                    from: previousCanvasPoint,
                    to: currentCanvasPoint,
                    by: eraserPath,
                    radius: hitRadius
                ) {
                    finishFragment()
                }
            }
            activeFragment.append(point)
        }
        finishFragment()

        return fragments.enumerated().map { index, points in
            InkStroke(
                id: index == 0 ? stroke.id : UUID(),
                points: points,
                inputMethod: stroke.inputMethod,
                tool: stroke.tool,
                ink: stroke.ink
            )
        }
    }

    private static func pointIsHit(
        _ point: CGPoint,
        by eraserPath: [CGPoint],
        radius: CGFloat
    ) -> Bool {
        guard eraserPath.count > 1 else {
            guard let eraserPoint = eraserPath.first else { return false }
            return distance(from: point, to: eraserPoint) <= radius
        }

        return zip(eraserPath, eraserPath.dropFirst()).contains {
            distance(from: point, toSegmentFrom: $0, to: $1) <= radius
        }
    }

    private static func segmentIsHit(
        from start: CGPoint,
        to end: CGPoint,
        by eraserPath: [CGPoint],
        radius: CGFloat
    ) -> Bool {
        guard eraserPath.count > 1 else {
            guard let eraserPoint = eraserPath.first else { return false }
            return distance(from: eraserPoint, toSegmentFrom: start, to: end) <= radius
        }

        return zip(eraserPath, eraserPath.dropFirst()).contains {
            segmentDistance(start, end, $0, $1) <= radius
        }
    }

    private static func segmentDistance(
        _ firstStart: CGPoint,
        _ firstEnd: CGPoint,
        _ secondStart: CGPoint,
        _ secondEnd: CGPoint
    ) -> CGFloat {
        if segmentsIntersect(firstStart, firstEnd, secondStart, secondEnd) {
            return 0
        }
        return min(
            distance(from: firstStart, toSegmentFrom: secondStart, to: secondEnd),
            distance(from: firstEnd, toSegmentFrom: secondStart, to: secondEnd),
            distance(from: secondStart, toSegmentFrom: firstStart, to: firstEnd),
            distance(from: secondEnd, toSegmentFrom: firstStart, to: firstEnd)
        )
    }

    private static func segmentsIntersect(
        _ firstStart: CGPoint,
        _ firstEnd: CGPoint,
        _ secondStart: CGPoint,
        _ secondEnd: CGPoint
    ) -> Bool {
        let firstA = cross(firstStart, firstEnd, secondStart)
        let firstB = cross(firstStart, firstEnd, secondEnd)
        let secondA = cross(secondStart, secondEnd, firstStart)
        let secondB = cross(secondStart, secondEnd, firstEnd)
        let epsilon = CGFloat.ulpOfOne.squareRoot()

        if firstA * firstB < 0, secondA * secondB < 0 {
            return true
        }
        if abs(firstA) <= epsilon,
            point(secondStart, liesOnSegmentFrom: firstStart, to: firstEnd)
        {
            return true
        }
        if abs(firstB) <= epsilon,
            point(secondEnd, liesOnSegmentFrom: firstStart, to: firstEnd)
        {
            return true
        }
        if abs(secondA) <= epsilon,
            point(firstStart, liesOnSegmentFrom: secondStart, to: secondEnd)
        {
            return true
        }
        if abs(secondB) <= epsilon,
            point(firstEnd, liesOnSegmentFrom: secondStart, to: secondEnd)
        {
            return true
        }
        return false
    }

    private static func point(
        _ point: CGPoint,
        liesOnSegmentFrom start: CGPoint,
        to end: CGPoint
    ) -> Bool {
        point.x >= min(start.x, end.x)
            && point.x <= max(start.x, end.x)
            && point.y >= min(start.y, end.y)
            && point.y <= max(start.y, end.y)
    }

    private static func cross(_ a: CGPoint, _ b: CGPoint, _ c: CGPoint) -> CGFloat {
        ((b.x - a.x) * (c.y - a.y)) - ((b.y - a.y) * (c.x - a.x))
    }

    private static func distance(
        from point: CGPoint,
        toSegmentFrom start: CGPoint,
        to end: CGPoint
    ) -> CGFloat {
        let dx = end.x - start.x
        let dy = end.y - start.y
        let squaredLength = (dx * dx) + (dy * dy)
        guard squaredLength > 0 else { return distance(from: point, to: start) }
        let projection = min(
            1,
            max(0, ((point.x - start.x) * dx + (point.y - start.y) * dy) / squaredLength)
        )
        let closest = CGPoint(
            x: start.x + (projection * dx),
            y: start.y + (projection * dy)
        )
        return distance(from: point, to: closest)
    }

    private static func distance(from first: CGPoint, to second: CGPoint) -> CGFloat {
        hypot(first.x - second.x, first.y - second.y)
    }

    private static func canvasPoint(
        for point: HandwritingPoint,
        canvasSize: CGSize
    ) -> CGPoint {
        CGPoint(
            x: CGFloat(point.location.x) * canvasSize.width,
            y: CGFloat(point.location.y) * canvasSize.height
        )
    }
}
