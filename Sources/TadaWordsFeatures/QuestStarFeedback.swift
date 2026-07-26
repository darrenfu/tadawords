import Foundation
import SwiftUI
import TadaWordsDomain

enum QuestStarFeedbackKind: Equatable, Sendable {
    case earned
    case missed
}

struct QuestStarFeedbackEvent: Equatable, Identifiable, Sendable {
    let id: UUID
    let kind: QuestStarFeedbackKind
    let targetSlot: Int

    init(
        id: UUID = UUID(),
        kind: QuestStarFeedbackKind,
        targetSlot: Int
    ) {
        self.id = id
        self.kind = kind
        self.targetSlot = targetSlot
    }
}

struct QuestAttemptFeedbackPresentation: Equatable, Sendable {
    let kind: QuestStarFeedbackKind?
    let cue: FunctionalAudioCue
}

enum QuestAttemptFeedbackPolicy {
    static func presentation(
        for decision: RecognitionDecision
    ) -> QuestAttemptFeedbackPresentation {
        switch decision {
        case .matched:
            QuestAttemptFeedbackPresentation(kind: .earned, cue: .correct)
        case .notMatched, .uncertain:
            QuestAttemptFeedbackPresentation(kind: .missed, cue: .validRetry)
        case .technicalFailure(.noUsableAudio),
            .technicalFailure(.timedOut):
            QuestAttemptFeedbackPresentation(kind: .missed, cue: .validRetry)
        case .technicalFailure:
            QuestAttemptFeedbackPresentation(kind: nil, cue: .technicalRetry)
        }
    }
}

enum QuestStarCoordinateSpace {
    static func localCenter(
        of globalFrame: CGRect,
        in globalViewportFrame: CGRect
    ) -> CGPoint {
        CGPoint(
            x: globalFrame.midX - globalViewportFrame.minX,
            y: globalFrame.midY - globalViewportFrame.minY
        )
    }
}

struct QuestStarSlotFramesPreferenceKey: PreferenceKey {
    static let defaultValue: [Int: CGRect] = [:]

    static func reduce(
        value: inout [Int: CGRect],
        nextValue: () -> [Int: CGRect]
    ) {
        value.merge(nextValue(), uniquingKeysWith: { _, latest in latest })
    }
}

struct QuestStarProgressState: Equatable, Sendable {
    private(set) var earnedCount: Int
    private(set) var lastHandledEventID: UUID?

    init(earnedCount: Int) {
        self.earnedCount = max(0, earnedCount)
    }

    mutating func synchronize(earnedCount: Int) {
        self.earnedCount = max(self.earnedCount, earnedCount)
    }

    mutating func begin(_ event: QuestStarFeedbackEvent) -> Bool {
        guard event.id != lastHandledEventID else { return false }
        lastHandledEventID = event.id
        return true
    }

    @discardableResult
    mutating func commit(_ event: QuestStarFeedbackEvent) -> Bool {
        guard event.kind == .earned else { return false }
        let newCount = max(earnedCount, event.targetSlot + 1)
        guard newCount != earnedCount else { return false }
        earnedCount = newCount
        return true
    }
}

struct QuestStarTrajectory: Equatable, Sendable {
    let source: CGPoint
    let control: CGPoint
    let target: CGPoint
    let floorY: CGFloat
    let bounceHeight: CGFloat

    init(
        source: CGPoint,
        target: CGPoint,
        viewportSize: CGSize,
        targetSlot: Int
    ) {
        let safeHeight = max(180, viewportSize.height)
        self.source = source
        let horizontalDelta = target.x - source.x
        let bend: CGFloat =
            if abs(horizontalDelta) < 48 {
                targetSlot.isMultiple(of: 2) ? 88 : -88
            } else {
                horizontalDelta.sign == .minus ? -72 : 72
            }
        control = CGPoint(
            x: source.x + horizontalDelta * 0.46 + bend,
            y: target.y + (source.y - target.y) * 0.43
        )
        self.target = target
        // The approved floor is 10% above the original bottom plane.
        floorY = safeHeight * 0.90
        bounceHeight = min(64, max(42, safeHeight * 0.085))
    }

    func point(at rawProgress: CGFloat) -> CGPoint {
        let progress = min(1, max(0, rawProgress))
        let inverse = 1 - progress
        return CGPoint(
            x: inverse * inverse * source.x
                + 2 * inverse * progress * control.x
                + progress * progress * target.x,
            y: inverse * inverse * source.y
                + 2 * inverse * progress * control.y
                + progress * progress * target.y
        )
    }

    var path: Path {
        var path = Path()
        path.move(to: source)
        path.addQuadCurve(to: target, control: control)
        return path
    }
}

struct QuestStarFlightFrame: Equatable, Sendable {
    let pathProgress: CGFloat
    let center: CGPoint
    let scale: CGFloat
    let opacity: CGFloat
}

enum QuestStarFlightMotion {
    static func frame(
        rawProgress: CGFloat,
        trajectory: QuestStarTrajectory
    ) -> QuestStarFlightFrame {
        let raw = min(1, max(0, rawProgress))
        let pathProgress = 1 - pow(1 - raw, 3)
        let scale =
            if raw < 0.80 {
                0.76 + 0.27 * sin((raw / 0.80) * .pi / 2)
            } else {
                1.03 - ((raw - 0.80) / 0.20) * 0.57
            }
        let opacity: CGFloat =
            if raw < 0.08 {
                raw / 0.08
            } else if raw > 0.96 {
                CGFloat(0.46)
            } else {
                CGFloat(1)
            }
        return QuestStarFlightFrame(
            pathProgress: pathProgress,
            center: trajectory.point(at: pathProgress),
            scale: scale,
            opacity: opacity
        )
    }

    static func trailRanges(
        pathProgress: CGFloat
    ) -> [ClosedRange<CGFloat>] {
        let head = min(1, max(0, pathProgress))
        return [0.34, 0.24, 0.10].map { length in
            max(0, head - length)...head
        }
    }
}

struct QuestStarProgressBar: View {
    let earnedStarCount: Int
    let totalStarCount: Int
    let feedbackEvent: QuestStarFeedbackEvent?
    let accent: Color
    let surface: Color

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var progressState: QuestStarProgressState
    @State private var activeEvent: QuestStarFeedbackEvent?
    @State private var committingSlot: Int?

    private let horizontalPadding: CGFloat = 8

    init(
        earnedStarCount: Int,
        totalStarCount: Int,
        feedbackEvent: QuestStarFeedbackEvent?,
        accent: Color,
        surface: Color
    ) {
        self.earnedStarCount = earnedStarCount
        self.totalStarCount = totalStarCount
        self.feedbackEvent = feedbackEvent
        self.accent = accent
        self.surface = surface
        _progressState = State(
            initialValue: QuestStarProgressState(earnedCount: earnedStarCount)
        )
    }

    var body: some View {
        HStack(spacing: slotSpacing) {
            ForEach(0..<safeTotal, id: \.self) { index in
                starSlot(at: index)
            }
        }
        .padding(.horizontal, horizontalPadding)
        .padding(.vertical, 7)
        .frame(width: barWidth)
        .background(surface.opacity(0.72), in: Capsule())
        .overlay {
            Capsule().strokeBorder(Color.white.opacity(0.52), lineWidth: 1)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Star progress")
        .accessibilityValue(
            "\(progressState.earnedCount) of \(safeTotal) stars"
        )
        .onChange(of: earnedStarCount) { _, newValue in
            progressState.synchronize(earnedCount: newValue)
        }
        .task(id: feedbackEvent?.id) {
            guard let feedbackEvent, progressState.begin(feedbackEvent) else {
                return
            }
            await commit(feedbackEvent)
        }
    }

    private var safeTotal: Int {
        max(1, totalStarCount)
    }

    private var slotSize: CGFloat {
        safeTotal > 8 ? 16 : 21
    }

    private var slotSpacing: CGFloat {
        safeTotal > 8 ? 4 : 6
    }

    private var barWidth: CGFloat {
        horizontalPadding * 2
            + CGFloat(safeTotal) * slotSize
            + CGFloat(max(0, safeTotal - 1)) * slotSpacing
    }

    private func starSlot(at index: Int) -> some View {
        let isEarned = index < progressState.earnedCount
        let isActive = activeEvent?.targetSlot == index
        return Image(systemName: isEarned ? "star.fill" : "star")
            .font(.system(size: slotSize, weight: .bold))
            .foregroundStyle(
                isEarned
                    ? Color.yellow
                    : accent.opacity(isActive ? 0.62 : 0.24)
            )
            .shadow(
                color: isEarned ? Color.orange.opacity(0.34) : .clear,
                radius: 4,
                y: 2
            )
            .scaleEffect(committingSlot == index ? 1.34 : 1)
            .animation(
                .spring(response: 0.30, dampingFraction: 0.54),
                value: committingSlot
            )
            .frame(width: slotSize, height: slotSize)
            .background {
                GeometryReader { proxy in
                    Color.clear.preference(
                        key: QuestStarSlotFramesPreferenceKey.self,
                        value: [index: proxy.frame(in: .global)]
                    )
                }
            }
    }

    @MainActor
    private func commit(_ event: QuestStarFeedbackEvent) async {
        activeEvent = event
        if event.kind == .earned {
            if !reduceMotion {
                do {
                    try await Task.sleep(for: .milliseconds(660))
                } catch {
                    activeEvent = nil
                    return
                }
            }
            guard !Task.isCancelled else {
                activeEvent = nil
                return
            }
            _ = progressState.commit(event)
            committingSlot = event.targetSlot
            try? await Task.sleep(for: .milliseconds(120))
        }
        activeEvent = nil
        committingSlot = nil
    }
}

struct QuestStarFeedbackOverlay: View {
    let event: QuestStarFeedbackEvent?
    let targetSlotFrame: CGRect?
    let viewportFrame: CGRect
    let accent: Color

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var activeEvent: QuestStarFeedbackEvent?
    @State private var activeTrajectory: QuestStarTrajectory?
    @State private var flightProgress: CGFloat = 0
    @State private var fallingY: CGFloat = 0
    @State private var transientOpacity: CGFloat = 0
    @State private var transientScale: CGFloat = 1

    var body: some View {
        ZStack(alignment: .topLeading) {
            if let activeEvent, let trajectory = activeTrajectory {
                if activeEvent.kind == .earned {
                    QuestStarEarnedFlightView(
                        trajectory: trajectory,
                        progress: flightProgress
                    )
                } else {
                    missedStar
                        .position(x: trajectory.target.x, y: fallingY)
                        .scaleEffect(transientScale)
                        .opacity(transientOpacity)
                }
            }
        }
        .frame(
            width: viewportFrame.width,
            height: max(180, viewportFrame.height),
            alignment: .topLeading
        )
        .allowsHitTesting(false)
        .accessibilityHidden(true)
        .task(id: event?.id) {
            guard let event, let targetSlotFrame else { return }
            await animate(event, targetSlotFrame: targetSlotFrame)
        }
    }

    private var missedStar: some View {
        Image(systemName: "star.fill")
            .font(.system(size: 44, weight: .bold))
            .foregroundStyle(
                LinearGradient(
                    colors: [
                        Color.white.opacity(0.82),
                        accent.opacity(0.44),
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            )
            .shadow(color: accent.opacity(0.18), radius: 6, y: 4)
    }

    @MainActor
    private func animate(
        _ event: QuestStarFeedbackEvent,
        targetSlotFrame: CGRect
    ) async {
        resetTransient()
        activeEvent = event
        let viewportSize = CGSize(
            width: viewportFrame.width,
            height: max(180, viewportFrame.height)
        )
        let target = QuestStarCoordinateSpace.localCenter(
            of: targetSlotFrame,
            in: viewportFrame
        )
        let trajectory = QuestStarTrajectory(
            source: CGPoint(
                x: viewportSize.width * 0.5,
                y: viewportSize.height * 0.68
            ),
            target: target,
            viewportSize: viewportSize,
            targetSlot: event.targetSlot
        )
        activeTrajectory = trajectory

        if reduceMotion {
            resetTransient()
            return
        }

        switch event.kind {
        case .earned:
            flightProgress = 0
            transientOpacity = 1
            withAnimation(.linear(duration: 0.66)) {
                flightProgress = 1
            }
            do {
                try await Task.sleep(for: .milliseconds(660))
            } catch {
                resetTransient()
                return
            }
            guard !Task.isCancelled else {
                resetTransient()
                return
            }
            withAnimation(.easeOut(duration: 0.08)) {
                transientOpacity = 0
            }
            try? await Task.sleep(for: .milliseconds(120))
            resetTransient()

        case .missed:
            fallingY = trajectory.target.y
            transientOpacity = 0.88
            transientScale = 1
            withAnimation(.easeIn(duration: 0.52)) {
                fallingY = trajectory.floorY
            }
            do {
                try await Task.sleep(for: .milliseconds(520))
            } catch {
                resetTransient()
                return
            }
            guard !Task.isCancelled else {
                resetTransient()
                return
            }
            withAnimation(.easeOut(duration: 0.13)) {
                fallingY = trajectory.floorY - trajectory.bounceHeight
                transientScale = 0.82
            }
            try? await Task.sleep(for: .milliseconds(130))
            withAnimation(.easeIn(duration: 0.11)) {
                fallingY = trajectory.floorY
                transientScale = 0.88
            }
            try? await Task.sleep(for: .milliseconds(110))
            withAnimation(.easeOut(duration: 0.08)) {
                fallingY = trajectory.floorY + 3
                transientScale = 0.08
                transientOpacity = 0
            }
            try? await Task.sleep(for: .milliseconds(80))
            resetTransient()
        }
    }

    @MainActor
    private func resetTransient() {
        activeEvent = nil
        activeTrajectory = nil
        flightProgress = 0
        fallingY = 0
        transientOpacity = 0
        transientScale = 1
    }
}

private struct QuestStarEarnedFlightView: View, @MainActor Animatable {
    let trajectory: QuestStarTrajectory
    var progress: CGFloat

    var animatableData: CGFloat {
        get { progress }
        set { progress = newValue }
    }

    var body: some View {
        let frame = QuestStarFlightMotion.frame(
            rawProgress: progress,
            trajectory: trajectory
        )
        ZStack(alignment: .topLeading) {
            fadingTrail(pathProgress: frame.pathProgress)
            Image(systemName: "star.fill")
                .font(.system(size: 54, weight: .bold))
                .foregroundStyle(
                    LinearGradient(
                        colors: [.white, .yellow, .orange],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .shadow(color: Color.orange.opacity(0.38), radius: 7, y: 4)
                .position(frame.center)
                .scaleEffect(frame.scale)
                .rotationEffect(.degrees(-16 + 38 * frame.pathProgress))
                .opacity(frame.opacity)
        }
    }

    private func fadingTrail(pathProgress: CGFloat) -> some View {
        Canvas { context, _ in
            guard pathProgress > 0 else { return }
            let ranges = QuestStarFlightMotion.trailRanges(
                pathProgress: pathProgress
            )
            let styles: [(width: CGFloat, opacity: CGFloat, blur: CGFloat)] = [
                (9, 0.10, 2.5),
                (5, 0.24, 0),
                (3, 0.58, 0),
            ]
            for (range, style) in zip(ranges, styles) {
                var layer = context
                if style.blur > 0 {
                    layer.addFilter(.blur(radius: style.blur))
                }
                layer.stroke(
                    trajectory.path.trimmedPath(
                        from: range.lowerBound,
                        to: range.upperBound
                    ),
                    with: .linearGradient(
                        Gradient(colors: [
                            Color.orange.opacity(0),
                            Color.yellow.opacity(style.opacity),
                        ]),
                        startPoint: trajectory.point(at: range.lowerBound),
                        endPoint: trajectory.point(at: range.upperBound)
                    ),
                    style: StrokeStyle(
                        lineWidth: style.width,
                        lineCap: .round
                    )
                )
            }
        }
    }
}
