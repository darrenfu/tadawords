import Foundation
import SwiftUI

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
        let alternatingBend: CGFloat = targetSlot.isMultiple(of: 2) ? 44 : -44
        control = CGPoint(
            x: source.x + horizontalDelta * 0.46 + alternatingBend,
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

struct QuestStarProgressBar: View {
    let earnedStarCount: Int
    let totalStarCount: Int
    let feedbackEvent: QuestStarFeedbackEvent?
    let feedbackViewportFrame: CGRect
    let accent: Color
    let surface: Color

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var progressState: QuestStarProgressState
    @State private var activeEvent: QuestStarFeedbackEvent?
    @State private var flightProgress: CGFloat = 0
    @State private var fallingY: CGFloat = 0
    @State private var transientOpacity: CGFloat = 0
    @State private var transientScale: CGFloat = 1
    @State private var committingSlot: Int?
    @State private var barFrame: CGRect = .zero

    private let horizontalPadding: CGFloat = 8

    init(
        earnedStarCount: Int,
        totalStarCount: Int,
        feedbackEvent: QuestStarFeedbackEvent?,
        feedbackViewportFrame: CGRect,
        accent: Color,
        surface: Color
    ) {
        self.earnedStarCount = earnedStarCount
        self.totalStarCount = totalStarCount
        self.feedbackEvent = feedbackEvent
        self.feedbackViewportFrame = feedbackViewportFrame
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
        .overlay(alignment: .topLeading) {
            transientLayer
                .frame(
                    width: feedbackViewportFrame.width,
                    height: max(180, feedbackViewportFrame.height),
                    alignment: .topLeading
                )
                .offset(
                    x: feedbackViewportFrame.minX - barFrame.minX,
                    y: feedbackViewportFrame.minY - barFrame.minY
                )
                .allowsHitTesting(false)
                .accessibilityHidden(true)
        }
        .background {
            GeometryReader { proxy in
                let frame = proxy.frame(in: .global)
                Color.clear
                    .onAppear {
                        barFrame = frame
                    }
                    .onChange(of: frame) { _, newFrame in
                        barFrame = newFrame
                    }
            }
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
            await animate(feedbackEvent)
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

    private func slotCenter(for rawIndex: Int) -> CGPoint {
        let index = min(max(0, rawIndex), safeTotal - 1)
        return CGPoint(
            x: horizontalPadding + slotSize * 0.5
                + CGFloat(index) * (slotSize + slotSpacing),
            y: slotSize * 0.5 + 7
        )
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
    }

    @ViewBuilder
    private var transientLayer: some View {
        if let activeEvent, barFrame != .zero {
            let trajectory = trajectory(for: activeEvent)

            if activeEvent.kind == .earned {
                fadingTrail(trajectory: trajectory)
                rewardStar
                    .position(trajectory.point(at: flightProgress))
                    .scaleEffect(
                        flightProgress < 0.80
                            ? 0.78 + flightProgress * 0.31
                            : max(0.52, 1.09 - (flightProgress - 0.80) * 2.85)
                    )
                    .rotationEffect(.degrees(-16 + 38 * flightProgress))
                    .opacity(transientOpacity)
            } else {
                missedStar
                    .position(x: trajectory.target.x, y: fallingY)
                    .scaleEffect(transientScale)
                    .opacity(transientOpacity)
            }
        }
    }

    private func fadingTrail(trajectory: QuestStarTrajectory) -> some View {
        Canvas { context, _ in
            guard flightProgress > 0 else { return }
            let segmentLength: CGFloat = 0.026
            let segmentGap: CGFloat = 0.018
            for segment in 0..<12 {
                let end = flightProgress - CGFloat(segment) * segmentGap
                guard end > 0 else { continue }
                let start = max(0, end - segmentLength)
                let opacity = 0.62 * (1 - CGFloat(segment) / 12)
                context.stroke(
                    trajectory.path.trimmedPath(from: start, to: min(1, end)),
                    with: .color(Color.orange.opacity(opacity)),
                    style: StrokeStyle(
                        lineWidth: segment < 3 ? 3.2 : 2.2,
                        lineCap: .round
                    )
                )
            }
        }
    }

    private var rewardStar: some View {
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
    private func animate(_ event: QuestStarFeedbackEvent) async {
        resetTransient()
        activeEvent = event
        let trajectory = trajectory(for: event)

        if reduceMotion {
            if progressState.commit(event) {
                committingSlot = event.targetSlot
                try? await Task.sleep(for: .milliseconds(90))
            }
            resetTransient()
            return
        }

        switch event.kind {
        case .earned:
            flightProgress = 0
            transientOpacity = 1
            withAnimation(.easeOut(duration: 0.66)) {
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
            _ = progressState.commit(event)
            committingSlot = event.targetSlot
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
        flightProgress = 0
        fallingY = 0
        transientOpacity = 0
        transientScale = 1
        committingSlot = nil
    }

    private func trajectory(
        for event: QuestStarFeedbackEvent
    ) -> QuestStarTrajectory {
        let viewportSize = CGSize(
            width: feedbackViewportFrame.width,
            height: max(180, feedbackViewportFrame.height)
        )
        let localSlot = slotCenter(for: event.targetSlot)
        let target = CGPoint(
            x: barFrame.minX - feedbackViewportFrame.minX + localSlot.x,
            y: barFrame.minY - feedbackViewportFrame.minY + localSlot.y
        )
        let source = CGPoint(
            x: viewportSize.width * 0.5,
            y: viewportSize.height * 0.62
        )
        return QuestStarTrajectory(
            source: source,
            target: target,
            viewportSize: viewportSize,
            targetSlot: event.targetSlot
        )
    }
}
