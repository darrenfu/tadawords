import SwiftUI
import TadaWordsDesignSystem
import TadaWordsDomain

#if os(iOS)
    import UIKit
#endif

struct InkStroke: Identifiable {
    let id = UUID()
    var points: [HandwritingPoint]
    var inputMethod: WritingInputMethod = .finger
}

struct HandwritingCanvasView: View {
    @Binding var strokes: [InkStroke]
    let inkColor: Color
    let guideColor: Color
    let elapsedSincePrompt: () -> TimeInterval

    @State private var activePoints: [HandwritingPoint] = []

    var body: some View {
        #if os(iOS)
            PencilAwareCanvas(
                strokes: $strokes,
                inkColor: UIColor(inkColor),
                guideColor: UIColor(guideColor),
                elapsedSincePrompt: elapsedSincePrompt
            )
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Handwriting area")
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
                    draw(stroke.points, in: &context, size: size)
                }
                draw(activePoints, in: &context, size: size)
            }
            .contentShape(Rectangle())
            .gesture(drawingGesture(in: proxy.size))
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Handwriting area")
        .accessibilityHint(handwritingHint)
    }

    private var handwritingHint: String {
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
                activePoints.append(point(from: value.location, in: size))
            }
            .onEnded { value in
                activePoints.append(point(from: value.location, in: size))
                guard activePoints.count > 1 else {
                    activePoints.removeAll(keepingCapacity: true)
                    return
                }
                strokes.append(InkStroke(points: activePoints))
                activePoints.removeAll(keepingCapacity: true)
            }
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
        _ points: [HandwritingPoint],
        in context: inout GraphicsContext,
        size: CGSize
    ) {
        guard let first = points.first else { return }
        var path = Path()
        path.move(to: canvasPoint(first, in: size))
        for point in points.dropFirst() {
            path.addLine(to: canvasPoint(point, in: size))
        }
        context.stroke(
            path,
            with: .color(inkColor),
            style: StrokeStyle(lineWidth: 8, lineCap: .round, lineJoin: .round)
        )
    }

    private func canvasPoint(_ point: HandwritingPoint, in size: CGSize) -> CGPoint {
        CGPoint(
            x: CGFloat(point.location.x) * size.width,
            y: CGFloat(point.location.y) * size.height
        )
    }
}

#if os(iOS)
    private struct PencilAwareCanvas: UIViewRepresentable {
        @Binding var strokes: [InkStroke]
        let inkColor: UIColor
        let guideColor: UIColor
        let elapsedSincePrompt: () -> TimeInterval

        func makeCoordinator() -> Coordinator {
            Coordinator(strokes: $strokes)
        }

        func makeUIView(context: Context) -> PencilAwareCanvasView {
            let view = PencilAwareCanvasView()
            view.isOpaque = false
            view.backgroundColor = .clear
            view.inkColor = inkColor
            view.guideColor = guideColor
            view.elapsedSincePrompt = elapsedSincePrompt
            view.onStroke = context.coordinator.append
            return view
        }

        func updateUIView(_ view: PencilAwareCanvasView, context: Context) {
            view.inkColor = inkColor
            view.guideColor = guideColor
            view.persistedStrokes = strokes
            view.setNeedsDisplay()
        }

        final class Coordinator {
            @Binding private var strokes: [InkStroke]

            init(strokes: Binding<[InkStroke]>) {
                _strokes = strokes
            }

            func append(_ stroke: InkStroke) {
                strokes.append(stroke)
            }
        }
    }

    private final class PencilAwareCanvasView: UIView {
        var persistedStrokes: [InkStroke] = []
        var inkColor: UIColor = .label
        var guideColor: UIColor = .separator
        var elapsedSincePrompt: () -> TimeInterval = { 0 }
        var onStroke: (InkStroke) -> Void = { _ in }

        private var activePoints: [HandwritingPoint] = []
        private var activeTouch: UITouch?
        private var activeInputMethod: WritingInputMethod = .finger

        override func draw(_ rect: CGRect) {
            guard let context = UIGraphicsGetCurrentContext() else { return }
            drawGuides(context: context)
            context.setStrokeColor(inkColor.cgColor)
            context.setLineWidth(8)
            context.setLineCap(.round)
            context.setLineJoin(.round)
            for stroke in persistedStrokes {
                draw(stroke.points, context: context)
            }
            draw(activePoints, context: context)
        }

        override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
            guard activeTouch == nil,
                let touch = preferredTouch(from: touches)
            else { return }
            activeTouch = touch
            activeInputMethod = touch.type == .pencil ? .pencil : .finger
            activePoints = [point(from: touch)]
            setNeedsDisplay()
        }

        override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent?) {
            guard let activeTouch,
                touches.contains(where: { $0 === activeTouch })
            else { return }
            let coalesced = event?.coalescedTouches(for: activeTouch) ?? [activeTouch]
            activePoints.append(
                contentsOf: coalesced.map { point(from: $0) }
            )
            setNeedsDisplay()
        }

        override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) {
            guard let activeTouch,
                touches.contains(where: { $0 === activeTouch })
            else { return }
            activePoints.append(point(from: activeTouch))
            if activePoints.count > 1 {
                let stroke = InkStroke(
                    points: activePoints,
                    inputMethod: activeInputMethod
                )
                persistedStrokes.append(stroke)
                onStroke(stroke)
            }
            resetActiveStroke()
        }

        override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent?) {
            resetActiveStroke()
        }

        private func preferredTouch(from touches: Set<UITouch>) -> UITouch? {
            if let pencil = touches.first(where: { $0.type == .pencil }) {
                return pencil
            }
            // Indirect and estimated palm contacts are ignored. When Pencil is
            // present in the same event it always wins over a direct touch.
            return touches.first(where: {
                $0.type == .direct && $0.majorRadius < 30
            })
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

        private func resetActiveStroke() {
            activePoints.removeAll(keepingCapacity: true)
            activeTouch = nil
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

        private func draw(
            _ points: [HandwritingPoint],
            context: CGContext
        ) {
            guard let first = points.first else { return }
            context.beginPath()
            context.move(to: canvasPoint(first))
            for point in points.dropFirst() {
                context.addLine(to: canvasPoint(point))
            }
            context.strokePath()
        }

        private func canvasPoint(_ point: HandwritingPoint) -> CGPoint {
            CGPoint(
                x: CGFloat(point.location.x) * bounds.width,
                y: CGFloat(point.location.y) * bounds.height
            )
        }
    }
#endif
