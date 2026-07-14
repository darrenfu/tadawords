import SwiftUI
import TadaWordsDesignSystem
import TadaWordsDomain

#if os(iOS)
    import UIKit
#endif

struct InkStroke: Identifiable, Equatable {
    let id: UUID
    var points: [HandwritingPoint]
    var inputMethod: WritingInputMethod
    let tool: HandwritingTool
    let ink: HandwritingInkChoice

    init(
        id: UUID = UUID(),
        points: [HandwritingPoint],
        inputMethod: WritingInputMethod = .finger,
        tool: HandwritingTool = .pencil,
        ink: HandwritingInkChoice = .basic(.black)
    ) {
        self.id = id
        self.points = points
        self.inputMethod = inputMethod
        self.tool = tool
        self.ink = ink
    }
}

struct HandwritingCanvasView: View {
    @Binding var strokes: [InkStroke]
    let selectedTool: HandwritingTool
    let selectedInk: HandwritingInkChoice
    let isErasing: Bool
    let themeInkColor: Color
    let guideColor: Color
    let elapsedSincePrompt: () -> TimeInterval
    let onWritingSound: (HandwritingTool) -> Void
    let onEraserTappedBlank: () -> Void

    @State private var activePoints: [HandwritingPoint] = []
    @State private var activeTool = HandwritingTool.pencil
    @State private var activeInk = HandwritingInkChoice.basic(.black)
    @State private var interactionIsErasing = false
    @State private var eraserDidChangeInk = false
    @State private var interactionStartLocation: CGPoint?
    @State private var lastWritingSoundLocation: CGPoint?
    @State private var lastWritingSoundTime: TimeInterval = 0

    var body: some View {
        #if os(iOS)
            PencilAwareCanvas(
                strokes: $strokes,
                selectedTool: selectedTool,
                selectedInk: selectedInk,
                isErasing: isErasing,
                themeInkColor: UIColor(themeInkColor),
                guideColor: UIColor(guideColor),
                elapsedSincePrompt: elapsedSincePrompt,
                onWritingSound: onWritingSound,
                onEraserTappedBlank: onEraserTappedBlank
            )
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Handwriting area")
            .accessibilityValue(isErasing ? "Eraser selected" : toolAccessibilityValue)
            .accessibilityHint(handwritingHint)
        #else
            swiftUICanvas
        #endif
    }

    private var swiftUICanvas: some View {
        GeometryReader { proxy in
            Canvas { context, size in
                drawGuides(in: &context, size: size)

                for stroke in strokes {
                    draw(stroke, in: &context, size: size)
                }
                if !interactionIsErasing, !activePoints.isEmpty {
                    draw(
                        InkStroke(
                            points: activePoints,
                            tool: activeTool,
                            ink: activeInk
                        ),
                        in: &context,
                        size: size
                    )
                }
            }
            .contentShape(Rectangle())
            .gesture(drawingGesture(in: proxy.size))
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Handwriting area")
        .accessibilityValue(isErasing ? "Eraser selected" : toolAccessibilityValue)
        .accessibilityHint(handwritingHint)
    }

    private var toolAccessibilityValue: String {
        HandwritingToolPolicy.displayName(for: selectedTool)
    }

    private var handwritingHint: String {
        if isErasing {
            return "Draw over part of a mark to erase it"
        }
        #if os(iOS)
            if UIDevice.current.userInterfaceIdiom == .phone {
                return "Draw the word with a finger"
            }
        #endif
        return "Draw the word with a finger or Apple Pencil"
    }

    private func drawingGesture(in size: CGSize) -> some Gesture {
        DragGesture(minimumDistance: 0, coordinateSpace: .local)
            .onChanged { value in
                let point = point(from: value.location, in: size)
                if activePoints.isEmpty {
                    activeTool = selectedTool
                    activeInk = selectedInk
                    interactionIsErasing = isErasing
                    eraserDidChangeInk = false
                    interactionStartLocation = value.location
                    activePoints = [point]
                    lastWritingSoundLocation = value.location
                    if interactionIsErasing {
                        eraserDidChangeInk = applyEraser(along: [point], in: size)
                    }
                    return
                }

                let previousPoint = activePoints.last
                activePoints = HandwritingStrokePointCollector.appending(
                    [point],
                    to: activePoints,
                    canvasSize: size
                )
                if interactionIsErasing {
                    eraserDidChangeInk =
                        applyEraser(
                            along: [previousPoint, point].compactMap { $0 },
                            in: size
                        ) || eraserDidChangeInk
                } else {
                    emitWritingSoundIfNeeded(at: value.location)
                }
            }
            .onEnded { value in
                let finalPoint = point(from: value.location, in: size)
                if interactionIsErasing {
                    eraserDidChangeInk =
                        applyEraser(
                            along: [activePoints.last, finalPoint].compactMap { $0 },
                            in: size
                        ) || eraserDidChangeInk
                    if !eraserDidChangeInk,
                        isTap(
                            from: interactionStartLocation,
                            to: value.location
                        )
                    {
                        onEraserTappedBlank()
                    }
                } else if !activePoints.isEmpty {
                    activePoints = HandwritingStrokePointCollector.finalizing(
                        activePoints,
                        with: finalPoint,
                        canvasSize: size
                    )
                    strokes.append(
                        InkStroke(
                            points: activePoints,
                            tool: activeTool,
                            ink: activeInk
                        )
                    )
                }
                resetActiveInteraction()
            }
    }

    @discardableResult
    private func applyEraser(
        along points: [HandwritingPoint],
        in size: CGSize
    ) -> Bool {
        let updated = InkStrokeEraser.erase(
            strokes: strokes,
            along: points,
            canvasSize: size,
            eraserLineWidth: HandwritingToolPolicy.eraserLineWidth(for: activeTool)
        )
        guard updated != strokes else { return false }
        strokes = updated
        return true
    }

    private func emitWritingSoundIfNeeded(at location: CGPoint) {
        let now = ProcessInfo.processInfo.systemUptime
        guard let previous = lastWritingSoundLocation else {
            lastWritingSoundLocation = location
            return
        }
        let moved = hypot(location.x - previous.x, location.y - previous.y)
        guard moved >= 5, now - lastWritingSoundTime >= 0.11 else { return }
        lastWritingSoundLocation = location
        lastWritingSoundTime = now
        onWritingSound(activeTool)
    }

    private func resetActiveInteraction() {
        activePoints.removeAll(keepingCapacity: true)
        interactionIsErasing = false
        eraserDidChangeInk = false
        interactionStartLocation = nil
        lastWritingSoundLocation = nil
        lastWritingSoundTime = 0
    }

    private func point(from location: CGPoint, in size: CGSize) -> HandwritingPoint {
        let width = max(1, size.width)
        let height = max(1, size.height)
        return HandwritingPoint(
            location: NormalizedPoint(
                x: Double(location.x / width),
                y: Double(location.y / height)
            ),
            elapsedSincePrompt: ElapsedTime(
                seconds: elapsedSincePrompt()
            )
        )
    }

    private func drawGuides(in context: inout GraphicsContext, size: CGSize) {
        let guides: [(CGFloat, StrokeStyle)] = [
            (0.20, StrokeStyle(lineWidth: 1.5, dash: [8, 7])),
            (0.48, StrokeStyle(lineWidth: 1.2, dash: [5, 6])),
            (0.78, StrokeStyle(lineWidth: 2.2)),
        ]

        for (fraction, style) in guides {
            var path = Path()
            let y = size.height * fraction
            path.move(to: CGPoint(x: 16, y: y))
            path.addLine(to: CGPoint(x: size.width - 16, y: y))
            context.stroke(path, with: .color(guideColor), style: style)
        }
    }

    private func draw(
        _ stroke: InkStroke,
        in context: inout GraphicsContext,
        size: CGSize
    ) {
        guard let first = stroke.points.first else { return }
        let appearance = HandwritingToolPolicy.appearance(for: stroke.tool)
        let color = stroke.ink.color(themeInk: themeInkColor).opacity(appearance.opacity)

        if stroke.points.count == 1 {
            let center = canvasPoint(first, in: size)
            let diameter = max(appearance.lineWidth, 2)
            context.fill(
                Path(
                    ellipseIn: CGRect(
                        x: center.x - (diameter / 2),
                        y: center.y - (diameter / 2),
                        width: diameter,
                        height: diameter
                    )
                ),
                with: .color(color)
            )
            return
        }

        if appearance.respondsToPressure, stroke.points.count > 1 {
            for (start, end) in zip(stroke.points, stroke.points.dropFirst()) {
                var segment = Path()
                segment.move(to: canvasPoint(start, in: size))
                segment.addLine(to: canvasPoint(end, in: size))
                context.stroke(
                    segment,
                    with: .color(color),
                    style: StrokeStyle(
                        lineWidth: HandwritingToolPolicy.lineWidth(
                            for: stroke.tool,
                            pressure: end.pressure
                        ),
                        lineCap: .round,
                        lineJoin: .round
                    )
                )
            }
            return
        }

        var path = Path()
        path.move(to: canvasPoint(first, in: size))
        for point in stroke.points.dropFirst() {
            path.addLine(to: canvasPoint(point, in: size))
        }
        context.stroke(
            path,
            with: .color(color),
            style: StrokeStyle(
                lineWidth: appearance.lineWidth,
                lineCap: .round,
                lineJoin: .round,
                dash: appearance.dash
            )
        )
    }

    private func canvasPoint(_ point: HandwritingPoint, in size: CGSize) -> CGPoint {
        CGPoint(
            x: CGFloat(point.location.x) * size.width,
            y: CGFloat(point.location.y) * size.height
        )
    }

    private func isTap(from start: CGPoint?, to end: CGPoint) -> Bool {
        guard let start else { return false }
        return hypot(end.x - start.x, end.y - start.y) <= 12
    }
}

#if os(iOS)
    private struct PencilAwareCanvas: UIViewRepresentable {
        @Binding var strokes: [InkStroke]
        let selectedTool: HandwritingTool
        let selectedInk: HandwritingInkChoice
        let isErasing: Bool
        let themeInkColor: UIColor
        let guideColor: UIColor
        let elapsedSincePrompt: () -> TimeInterval
        let onWritingSound: (HandwritingTool) -> Void
        let onEraserTappedBlank: () -> Void

        func makeCoordinator() -> Coordinator {
            Coordinator(strokes: $strokes)
        }

        func makeUIView(context: Context) -> PencilAwareCanvasView {
            let view = PencilAwareCanvasView()
            view.isOpaque = false
            view.backgroundColor = .clear
            configure(view, coordinator: context.coordinator)
            return view
        }

        func updateUIView(_ view: PencilAwareCanvasView, context: Context) {
            configure(view, coordinator: context.coordinator)
            view.setNeedsDisplay()
        }

        private func configure(
            _ view: PencilAwareCanvasView,
            coordinator: Coordinator
        ) {
            view.selectedTool = selectedTool
            view.selectedInk = selectedInk
            view.isErasing = isErasing
            view.themeInkColor = themeInkColor
            view.guideColor = guideColor
            view.elapsedSincePrompt = elapsedSincePrompt
            view.persistedStrokes = strokes
            view.onStroke = coordinator.append
            view.onStrokesChanged = coordinator.replace
            view.onWritingSound = onWritingSound
            view.onEraserTappedBlank = onEraserTappedBlank
        }

        final class Coordinator {
            @Binding private var strokes: [InkStroke]

            init(strokes: Binding<[InkStroke]>) {
                _strokes = strokes
            }

            func append(_ stroke: InkStroke) {
                strokes.append(stroke)
            }

            func replace(with newStrokes: [InkStroke]) {
                strokes = newStrokes
            }
        }
    }

    private final class PencilAwareCanvasView: UIView {
        var persistedStrokes: [InkStroke] = []
        var selectedTool = HandwritingTool.pencil
        var selectedInk = HandwritingInkChoice.basic(.black)
        var isErasing = false
        var themeInkColor = UIColor.label
        var guideColor = UIColor.separator
        var elapsedSincePrompt: () -> TimeInterval = { 0 }
        var onStroke: (InkStroke) -> Void = { _ in }
        var onStrokesChanged: ([InkStroke]) -> Void = { _ in }
        var onWritingSound: (HandwritingTool) -> Void = { _ in }
        var onEraserTappedBlank: () -> Void = {}

        private var activePoints: [HandwritingPoint] = []
        private var activeTouch: UITouch?
        private var activeInputMethod: WritingInputMethod = .finger
        private var activeTool = HandwritingTool.pencil
        private var activeInk = HandwritingInkChoice.basic(.black)
        private var activeInteractionIsErasing = false
        private var eraserDidChangeInk = false
        private var interactionStartLocation: CGPoint?
        private var lastWritingSoundLocation: CGPoint?
        private var lastWritingSoundTime: TimeInterval = 0

        override func draw(_ rect: CGRect) {
            guard let context = UIGraphicsGetCurrentContext() else { return }
            drawGuides(context: context)
            for stroke in persistedStrokes {
                draw(stroke, context: context)
            }
            if !activeInteractionIsErasing, !activePoints.isEmpty {
                draw(
                    InkStroke(
                        points: activePoints,
                        inputMethod: activeInputMethod,
                        tool: activeTool,
                        ink: activeInk
                    ),
                    context: context
                )
            }
        }

        override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
            guard activeTouch == nil,
                let touch = preferredTouch(from: touches)
            else { return }
            activeTouch = touch
            activeInputMethod = touch.type == .pencil ? .pencil : .finger
            activeTool = selectedTool
            activeInk = selectedInk
            activeInteractionIsErasing = isErasing
            eraserDidChangeInk = false
            interactionStartLocation = touch.location(in: self)
            activePoints = [point(from: touch)]
            lastWritingSoundLocation = touch.location(in: self)
            if activeInteractionIsErasing {
                eraserDidChangeInk = applyEraser(along: activePoints)
            }
            setNeedsDisplay()
        }

        override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent?) {
            guard let activeTouch,
                touches.contains(where: { $0 === activeTouch })
            else { return }
            let coalesced = event?.coalescedTouches(for: activeTouch) ?? [activeTouch]
            let newPoints = coalesced.map { point(from: $0) }
            if activeInteractionIsErasing {
                eraserDidChangeInk =
                    applyEraser(
                        along: ([activePoints.last].compactMap { $0 }) + newPoints
                    ) || eraserDidChangeInk
            } else if let finalTouch = coalesced.last {
                emitWritingSoundIfNeeded(at: finalTouch.location(in: self))
            }
            activePoints = HandwritingStrokePointCollector.appending(
                newPoints,
                to: activePoints,
                canvasSize: bounds.size
            )
            setNeedsDisplay()
        }

        override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) {
            guard let activeTouch,
                touches.contains(where: { $0 === activeTouch })
            else { return }
            let endedTouch = touches.first(where: { $0 === activeTouch }) ?? activeTouch
            let finalPoint = point(from: endedTouch)
            if activeInteractionIsErasing {
                eraserDidChangeInk =
                    applyEraser(
                        along: [activePoints.last, finalPoint].compactMap { $0 }
                    ) || eraserDidChangeInk
                if !eraserDidChangeInk,
                    isTap(
                        from: interactionStartLocation,
                        to: endedTouch.location(in: self)
                    )
                {
                    onEraserTappedBlank()
                }
            } else {
                activePoints = HandwritingStrokePointCollector.finalizing(
                    activePoints,
                    with: finalPoint,
                    canvasSize: bounds.size
                )
                if !activePoints.isEmpty {
                    let stroke = InkStroke(
                        points: activePoints,
                        inputMethod: activeInputMethod,
                        tool: activeTool,
                        ink: activeInk
                    )
                    persistedStrokes.append(stroke)
                    onStroke(stroke)
                }
            }
            resetActiveInteraction()
        }

        override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent?) {
            resetActiveInteraction()
        }

        @discardableResult
        private func applyEraser(along points: [HandwritingPoint]) -> Bool {
            let updated = InkStrokeEraser.erase(
                strokes: persistedStrokes,
                along: points,
                canvasSize: bounds.size,
                eraserLineWidth: HandwritingToolPolicy.eraserLineWidth(for: activeTool)
            )
            guard
                updated.map(\.id) != persistedStrokes.map(\.id)
                    || updated.map(\.points) != persistedStrokes.map(\.points)
            else { return false }
            persistedStrokes = updated
            onStrokesChanged(updated)
            return true
        }

        private func emitWritingSoundIfNeeded(at location: CGPoint) {
            let now = ProcessInfo.processInfo.systemUptime
            guard let previous = lastWritingSoundLocation else {
                lastWritingSoundLocation = location
                return
            }
            let moved = hypot(location.x - previous.x, location.y - previous.y)
            guard moved >= 5, now - lastWritingSoundTime >= 0.11 else { return }
            lastWritingSoundLocation = location
            lastWritingSoundTime = now
            onWritingSound(activeTool)
        }

        private func preferredTouch(from touches: Set<UITouch>) -> UITouch? {
            if let pencil = touches.first(where: { $0.type == .pencil }) {
                return pencil
            }
            // Indirect and estimated palm contacts are ignored. When Pencil is
            // present in the same event it always wins over a direct touch.
            return touches.first(where: { $0.type == .direct })
        }

        private func point(from touch: UITouch) -> HandwritingPoint {
            let location = touch.location(in: self)
            let pressure: Double?
            if touch.maximumPossibleForce > 0 {
                pressure = Double(touch.force / touch.maximumPossibleForce)
            } else {
                pressure = nil
            }
            return HandwritingPoint(
                location: NormalizedPoint(
                    x: Double(location.x / max(1, bounds.width)),
                    y: Double(location.y / max(1, bounds.height))
                ),
                elapsedSincePrompt: ElapsedTime(seconds: elapsedSincePrompt()),
                pressure: pressure
            )
        }

        private func resetActiveInteraction() {
            activePoints.removeAll(keepingCapacity: true)
            activeTouch = nil
            activeInteractionIsErasing = false
            eraserDidChangeInk = false
            interactionStartLocation = nil
            lastWritingSoundLocation = nil
            lastWritingSoundTime = 0
            setNeedsDisplay()
        }

        private func drawGuides(context: CGContext) {
            let guides: [(CGFloat, [CGFloat], CGFloat)] = [
                (0.20, [8, 7], 1.5),
                (0.48, [5, 6], 1.2),
                (0.78, [], 2.2),
            ]
            context.setStrokeColor(guideColor.cgColor)
            for (fraction, dash, width) in guides {
                context.setLineWidth(width)
                context.setLineDash(phase: 0, lengths: dash)
                let y = bounds.height * fraction
                context.move(to: CGPoint(x: 16, y: y))
                context.addLine(to: CGPoint(x: bounds.width - 16, y: y))
                context.strokePath()
            }
            context.setLineDash(phase: 0, lengths: [])
        }

        private func draw(_ stroke: InkStroke, context: CGContext) {
            guard let first = stroke.points.first else { return }
            let appearance = HandwritingToolPolicy.appearance(for: stroke.tool)
            context.saveGState()
            context.setStrokeColor(
                resolvedColor(for: stroke.ink)
                    .withAlphaComponent(appearance.opacity).cgColor
            )
            context.setLineCap(.round)
            context.setLineJoin(.round)

            if stroke.points.count == 1 {
                let center = canvasPoint(first)
                let diameter = max(appearance.lineWidth, 2)
                context.setFillColor(
                    resolvedColor(for: stroke.ink)
                        .withAlphaComponent(appearance.opacity).cgColor
                )
                context.fillEllipse(
                    in: CGRect(
                        x: center.x - (diameter / 2),
                        y: center.y - (diameter / 2),
                        width: diameter,
                        height: diameter
                    )
                )
                context.restoreGState()
                return
            }

            if appearance.respondsToPressure, stroke.points.count > 1 {
                for (start, end) in zip(stroke.points, stroke.points.dropFirst()) {
                    context.setLineWidth(
                        HandwritingToolPolicy.lineWidth(
                            for: stroke.tool,
                            pressure: end.pressure
                        )
                    )
                    context.beginPath()
                    context.move(to: canvasPoint(start))
                    context.addLine(to: canvasPoint(end))
                    context.strokePath()
                }
            } else {
                context.setLineWidth(appearance.lineWidth)
                context.setLineDash(phase: 0, lengths: appearance.dash)
                context.beginPath()
                context.move(to: canvasPoint(first))
                for point in stroke.points.dropFirst() {
                    context.addLine(to: canvasPoint(point))
                }
                context.strokePath()
            }
            context.restoreGState()
        }

        private func resolvedColor(for ink: HandwritingInkChoice) -> UIColor {
            switch ink {
            case .theme:
                themeInkColor
            case .basic(let basicColor):
                UIColor(basicColor.color)
            }
        }

        private func canvasPoint(_ point: HandwritingPoint) -> CGPoint {
            CGPoint(
                x: CGFloat(point.location.x) * bounds.width,
                y: CGFloat(point.location.y) * bounds.height
            )
        }

        private func isTap(from start: CGPoint?, to end: CGPoint) -> Bool {
            guard let start else { return false }
            return hypot(end.x - start.x, end.y - start.y) <= 12
        }
    }
#endif
