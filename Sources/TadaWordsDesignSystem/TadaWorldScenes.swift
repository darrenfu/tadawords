import SwiftUI

/// Controls how much story art appears behind a child-facing screen.
/// Quest screens deliberately use the quiet variant so the learning target stays dominant.
public enum TadaWorldSceneStyle: Sendable {
    case lobby
    case quest
    case celebration

    fileprivate var decorationOpacity: Double {
        switch self {
        case .lobby: 1
        case .quest: 0.42
        case .celebration: 1
        }
    }

    fileprivate var allowsAmbientMotion: Bool {
        self != .quest
    }
}

enum TadaWorldSceneMotionPolicy {
    static func shouldAnimate(
        style: TadaWorldSceneStyle,
        reduceMotion: Bool
    ) -> Bool {
        style.allowsAmbientMotion && !reduceMotion
    }
}

enum TadaWorldStoryArtLayoutPolicy {
    static let moonpetalCastleHeightRatio: CGFloat = 0.28
    static let moonpetalUnicornAdditionalOffset: CGFloat = 10
    static let moonpetalMinimumDownwardMotion: CGFloat = 0
    static let moonpetalMaximumDownwardMotion: CGFloat = 3

    static func verticalOffset(canvasHeight: CGFloat) -> CGFloat {
        min(max(canvasHeight, 0) * 0.05, 32)
    }
}

public enum TadaMascotPose: Sendable {
    case resting
    case cheering
    case encouraging
    case rescue
}

public enum TadaFeedbackKind: Sendable {
    case success
    case tryAgain
    case technical
    case celebration

    fileprivate var symbol: String {
        switch self {
        case .success: "checkmark"
        case .tryAgain: "arrow.clockwise"
        case .technical: "wrench.adjustable.fill"
        case .celebration: "star.fill"
        }
    }

    fileprivate var accessibilityLabel: String {
        switch self {
        case .success: "Great job"
        case .tryAgain: "Try again"
        case .technical: "Device needs another try"
        case .celebration: "Quest celebration"
        }
    }
}

/// An original, asset-free story scene for each launch world.
public struct TadaWorldSceneLayer: View {
    private let theme: TadaWorldTheme
    private let style: TadaWorldSceneStyle

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var isDrifting = false

    public init(theme: TadaWorldTheme, style: TadaWorldSceneStyle) {
        self.theme = theme
        self.style = style
    }

    public var body: some View {
        GeometryReader { proxy in
            Group {
                switch theme.id {
                case .moonpetal:
                    MoonpetalScene(theme: theme, isDrifting: isDrifting)
                case .buildItBay:
                    BuildItScene(theme: theme, isDrifting: isDrifting)
                case .pawsAndPines:
                    PawsScene(theme: theme, isDrifting: isDrifting)
                case .dinoDiscovery:
                    DinoDiscoveryScene(theme: theme, isDrifting: isDrifting)
                case .firehouseHeroes:
                    FirehouseHeroesScene(theme: theme, isDrifting: isDrifting)
                case .brickworkCity:
                    BrickworkCityScene(theme: theme, isDrifting: isDrifting)
                case .frostlightWorld:
                    FrostlightWorldScene(theme: theme, isDrifting: isDrifting)
                case .coasterCarnival:
                    CoasterCarnivalScene(theme: theme, isDrifting: isDrifting)
                }
            }
            .frame(width: proxy.size.width, height: proxy.size.height)
            .opacity(style.decorationOpacity)
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
        .onAppear {
            synchronizeAmbientMotion()
        }
        .onChange(of: reduceMotion) { _, _ in
            synchronizeAmbientMotion()
        }
    }

    private func synchronizeAmbientMotion() {
        guard
            TadaWorldSceneMotionPolicy.shouldAnimate(
                style: style,
                reduceMotion: reduceMotion
            )
        else {
            withAnimation(.linear(duration: 0.01)) {
                isDrifting = false
            }
            return
        }
        withAnimation(
            .easeInOut(duration: TadaPrimitiveTokens.Motion.ambient)
                .repeatForever(autoreverses: true)
        ) {
            isDrifting = true
        }
    }
}

/// A small original companion assembled from simple SwiftUI shapes.
public struct TadaWorldMascot: View {
    private let theme: TadaWorldTheme
    private let pose: TadaMascotPose
    private let size: CGFloat

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var isReacting = false

    public init(
        theme: TadaWorldTheme,
        pose: TadaMascotPose = .resting,
        size: CGFloat = 84
    ) {
        self.theme = theme
        self.pose = pose
        self.size = size
    }

    public var body: some View {
        ZStack {
            mascotShadow
            mascotBody
        }
        .frame(width: size, height: size)
        .rotationEffect(.degrees(reactionRotation))
        .offset(y: reactionOffset)
        .shadow(color: theme.ink.opacity(0.16), radius: size * 0.10, y: size * 0.07)
        .animation(
            reduceMotion
                ? .linear(duration: 0.01)
                : .spring(response: TadaPrimitiveTokens.Motion.reaction, dampingFraction: 0.58),
            value: isReacting
        )
        .onAppear {
            guard pose != .resting, !reduceMotion else { return }
            isReacting = true
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(theme.mascotName), the \(theme.name) helper")
    }

    private var mascotShadow: some View {
        Ellipse()
            .fill(theme.ink.opacity(0.12))
            .frame(width: size * 0.66, height: size * 0.16)
            .offset(y: size * 0.40)
    }

    @ViewBuilder
    private var mascotBody: some View {
        switch theme.id {
        case .moonpetal:
            MoonpetalMascot(theme: theme, size: size, pose: pose)
        case .buildItBay:
            BuildItMascot(theme: theme, size: size, pose: pose)
        case .pawsAndPines:
            PawsMascot(theme: theme, size: size, pose: pose)
        case .dinoDiscovery:
            DinoWorldMascot(theme: theme, size: size, pose: pose)
        case .firehouseHeroes:
            FirehouseWorldMascot(theme: theme, size: size, pose: pose)
        case .brickworkCity:
            BrickworkWorldMascot(theme: theme, size: size, pose: pose)
        case .frostlightWorld:
            FrostlightWorldMascot(theme: theme, size: size, pose: pose)
        case .coasterCarnival:
            CoasterWorldMascot(theme: theme, size: size, pose: pose)
        }
    }

    private var reactionRotation: Double {
        guard isReacting else { return 0 }
        return switch pose {
        case .resting: 0
        case .cheering: -7
        case .encouraging: 5
        case .rescue: -4
        }
    }

    private var reactionOffset: CGFloat {
        guard isReacting else { return 0 }
        return switch pose {
        case .resting: 0
        case .cheering: -size * 0.10
        case .encouraging: -size * 0.04
        case .rescue: -size * 0.07
        }
    }
}

/// Non-text visual grammar for Read (round voice bubble) and Write (writing tile).
public struct TadaModeMark: View {
    private let tokens: TadaQuestEntranceTokens
    private let size: CGFloat

    public init(tokens: TadaQuestEntranceTokens, size: CGFloat = 96) {
        self.tokens = tokens
        self.size = size
    }

    public var body: some View {
        ZStack {
            switch tokens.iconShape {
            case .circle:
                Circle()
                    .fill(tokens.accent)
                Circle()
                    .strokeBorder(Color.white.opacity(0.76), lineWidth: size * 0.045)
                    .padding(size * 0.08)
                Image(systemName: tokens.companionSymbol)
                    .font(.system(size: size * 0.62, weight: .bold))
                    .foregroundStyle(Color.white.opacity(0.26))
                Image(systemName: tokens.symbol)
                    .font(.system(size: size * 0.34, weight: .bold))
                    .foregroundStyle(Color.white)

            case .writingTile:
                RoundedRectangle(cornerRadius: size * 0.23, style: .continuous)
                    .fill(tokens.accent)
                    .rotationEffect(.degrees(-4))
                Image(systemName: tokens.companionSymbol)
                    .font(.system(size: size * 0.26, weight: .bold))
                    .foregroundStyle(Color.white.opacity(0.78))
                    .offset(x: -size * 0.19, y: -size * 0.18)
                Image(systemName: tokens.symbol)
                    .font(.system(size: size * 0.42, weight: .bold))
                    .foregroundStyle(Color.white)
                    .offset(x: size * 0.08, y: size * 0.04)
                Capsule()
                    .fill(Color.white.opacity(0.82))
                    .frame(width: size * 0.55, height: size * 0.045)
                    .offset(y: size * 0.29)
            }
        }
        .frame(width: size, height: size)
        .shadow(color: tokens.accent.opacity(0.26), radius: size * 0.12, y: size * 0.08)
        .accessibilityHidden(true)
    }
}

/// A deterministic preview of this world's collectible family.
public struct TadaRewardShelf: View {
    private let theme: TadaWorldTheme
    private let highlightedCount: Int
    private let isCompact: Bool
    private let visibleLimit: Int

    public init(
        theme: TadaWorldTheme,
        highlightedCount: Int = 1,
        isCompact: Bool = false,
        visibleLimit: Int? = nil
    ) {
        self.theme = theme
        self.highlightedCount = max(0, min(highlightedCount, theme.rewardSymbols.count))
        self.isCompact = isCompact
        self.visibleLimit = max(
            1,
            min(visibleLimit ?? theme.rewardSymbols.count, theme.rewardSymbols.count)
        )
    }

    public var body: some View {
        HStack(spacing: isCompact ? TadaPrimitiveTokens.Spacing.small : 12) {
            ForEach(
                Array(theme.rewardSymbols.prefix(visibleLimit).enumerated()),
                id: \.offset
            ) { index, symbol in
                ZStack {
                    Circle()
                        .fill(
                            index < highlightedCount
                                ? theme.sceneAccent
                                : theme.ink.opacity(0.09)
                        )
                    Image(systemName: index < highlightedCount ? symbol : "lock.fill")
                        .font(
                            .system(
                                size: isCompact ? 15 : 19,
                                weight: .bold,
                                design: .rounded
                            )
                        )
                        .foregroundStyle(
                            index < highlightedCount
                                ? theme.ink.opacity(0.76)
                                : theme.ink.opacity(0.30)
                        )
                }
                .frame(width: isCompact ? 34 : 44, height: isCompact ? 34 : 44)
            }

            if theme.rewardSymbols.count > visibleLimit {
                Text("+\(theme.rewardSymbols.count - visibleLimit)")
                    .font(.system(.caption, design: .rounded, weight: .bold))
                    .foregroundStyle(theme.ink.opacity(0.64))
                    .frame(width: isCompact ? 34 : 44, height: isCompact ? 34 : 44)
                    .background(theme.ink.opacity(0.09), in: Circle())
                    .accessibilityHidden(true)
            }
        }
        .padding(.horizontal, isCompact ? 10 : 14)
        .padding(.vertical, isCompact ? 6 : 9)
        .background(theme.ink.opacity(0.07), in: Capsule())
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(highlightedCount) \(theme.name) collectibles found")
    }
}

/// A brief, noninteractive reaction layer. It never owns focus or captures taps.
public struct TadaFeedbackBurst: View {
    private let theme: TadaWorldTheme
    private let kind: TadaFeedbackKind
    private let message: String

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var isVisible = false

    public init(theme: TadaWorldTheme, kind: TadaFeedbackKind, message: String) {
        self.theme = theme
        self.kind = kind
        self.message = message
    }

    public var body: some View {
        ZStack {
            ForEach(0..<6, id: \.self) { index in
                Circle()
                    .fill(index.isMultiple(of: 2) ? theme.secondary : theme.sceneAccent)
                    .frame(width: 13, height: 13)
                    .offset(
                        x: isVisible ? cos(Double(index) * .pi / 3) * 108 : 0,
                        y: isVisible ? sin(Double(index) * .pi / 3) * 82 : 0
                    )
                    .opacity(isVisible ? 0 : 0.90)
            }

            HStack(spacing: TadaPrimitiveTokens.Spacing.medium) {
                TadaWorldMascot(
                    theme: theme,
                    pose: kind == .technical ? .encouraging : .cheering,
                    size: 74
                )

                Label(message, systemImage: kind.symbol)
                    .font(.system(.title3, design: .rounded, weight: .heavy))
                    .foregroundStyle(theme.ink)
                    .multilineTextAlignment(.leading)
            }
            .padding(.horizontal, TadaPrimitiveTokens.Spacing.large)
            .padding(.vertical, TadaPrimitiveTokens.Spacing.medium)
            .background(
                theme.surface,
                in: RoundedRectangle(
                    cornerRadius: TadaPrimitiveTokens.Radius.large,
                    style: .continuous
                )
            )
            .overlay {
                RoundedRectangle(
                    cornerRadius: TadaPrimitiveTokens.Radius.large,
                    style: .continuous
                )
                .strokeBorder(Color.white.opacity(0.76), lineWidth: 2)
            }
            .shadow(color: theme.primary.opacity(0.24), radius: 24, y: 12)
            .scaleEffect(isVisible ? 1 : 0.88)
            .opacity(isVisible ? 1 : 0)
        }
        .animation(
            .spring(
                response: reduceMotion ? 0.01 : TadaPrimitiveTokens.Motion.reaction,
                dampingFraction: 0.68
            ),
            value: isVisible
        )
        .onAppear { isVisible = true }
        .allowsHitTesting(false)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(kind.accessibilityLabel). \(message)")
    }
}

public struct TadaEmergencyAtmosphere: View {
    private let theme: TadaWorldTheme
    private let isActive: Bool

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var isBreathing = false

    public init(theme: TadaWorldTheme, isActive: Bool) {
        self.theme = theme
        self.isActive = isActive
    }

    public var body: some View {
        RoundedRectangle(cornerRadius: TadaPrimitiveTokens.Radius.large, style: .continuous)
            .strokeBorder(theme.sceneAccent.opacity(isBreathing ? 0.46 : 0.18), lineWidth: 8)
            .padding(TadaPrimitiveTokens.Spacing.xSmall)
            .ignoresSafeArea()
            .opacity(isActive ? 1 : 0)
            .animation(
                reduceMotion
                    ? .linear(duration: 0.01)
                    : .easeInOut(duration: 1.4).repeatForever(autoreverses: true),
                value: isBreathing
            )
            .onAppear {
                guard isActive, !reduceMotion else { return }
                isBreathing = true
            }
            .onChange(of: isActive) { _, newValue in
                if newValue, !reduceMotion {
                    isBreathing = true
                } else if !newValue {
                    isBreathing = false
                }
            }
            .allowsHitTesting(false)
            .accessibilityHidden(true)
    }
}

private struct MoonpetalScene: View {
    let theme: TadaWorldTheme
    let isDrifting: Bool

    private let sparklePoints: [UnitPoint] = [
        UnitPoint(x: 0.08, y: 0.16), UnitPoint(x: 0.22, y: 0.29),
        UnitPoint(x: 0.54, y: 0.12), UnitPoint(x: 0.74, y: 0.24),
        UnitPoint(x: 0.91, y: 0.12),
    ]

    var body: some View {
        GeometryReader { proxy in
            let layout = MoonpetalSceneDecorationLayout(canvasSize: proxy.size)
            let storyOffset = TadaWorldStoryArtLayoutPolicy.verticalOffset(
                canvasHeight: proxy.size.height
            )
            ZStack {
                MoonpetalRainbow(theme: theme)
                    .frame(width: layout.rainbowSize.width, height: layout.rainbowSize.height)
                    .position(layout.rainbowCenter)
                    .offset(y: isDrifting ? -3 : 2)

                ForEach(Array(sparklePoints.enumerated()), id: \.offset) { index, point in
                    Image(systemName: index.isMultiple(of: 2) ? "sparkle" : "star.fill")
                        .font(.system(size: max(10, proxy.size.height * 0.030), weight: .bold))
                        .foregroundStyle(theme.sceneAccent.opacity(0.56))
                        .position(x: proxy.size.width * point.x, y: proxy.size.height * point.y)
                        .offset(y: isDrifting ? -5 : 4)
                }

                ZStack {
                    Circle().fill(theme.sceneAccent.opacity(0.68))
                    Circle()
                        .fill(theme.backgroundTop)
                        .offset(x: -proxy.size.height * 0.025, y: -proxy.size.height * 0.018)
                }
                .frame(width: proxy.size.height * 0.18, height: proxy.size.height * 0.18)
                .position(x: proxy.size.width * 0.84, y: proxy.size.height * 0.20)

                HillShape(amplitude: 0.12)
                    .fill(theme.ground.opacity(0.22))
                    .frame(height: proxy.size.height * 0.34)
                    .frame(maxHeight: .infinity, alignment: .bottom)

                MoonpetalCastle(theme: theme)
                    .frame(
                        width: proxy.size.width * 0.22,
                        height: proxy.size.height
                            * TadaWorldStoryArtLayoutPolicy.moonpetalCastleHeightRatio
                    )
                    .position(
                        x: proxy.size.width * 0.14,
                        y: proxy.size.height * 0.80 + storyOffset
                    )

                MoonpetalUnicorn(theme: theme)
                    .frame(width: layout.unicornSize.width, height: layout.unicornSize.height)
                    .position(
                        x: layout.unicornCenter.x,
                        y: layout.unicornCenter.y + storyOffset
                            + TadaWorldStoryArtLayoutPolicy.moonpetalUnicornAdditionalOffset
                    )
                    .offset(
                        y: isDrifting
                            ? TadaWorldStoryArtLayoutPolicy.moonpetalMinimumDownwardMotion
                            : TadaWorldStoryArtLayoutPolicy.moonpetalMaximumDownwardMotion
                    )
            }
        }
    }
}

struct MoonpetalSceneDecorationLayout: Equatable {
    let rainbowSize: CGSize
    let rainbowCenter: CGPoint
    let unicornSize: CGSize
    let unicornCenter: CGPoint

    init(canvasSize: CGSize) {
        rainbowSize = CGSize(
            width: min(canvasSize.width * 0.19, canvasSize.height * 0.42),
            height: min(canvasSize.width * 0.10, canvasSize.height * 0.22)
        )
        rainbowCenter = CGPoint(x: canvasSize.width * 0.12, y: canvasSize.height * 0.27)
        unicornSize = CGSize(
            width: min(canvasSize.width * 0.13, canvasSize.height * 0.29),
            height: min(canvasSize.width * 0.108, canvasSize.height * 0.27)
        )
        unicornCenter = CGPoint(x: canvasSize.width * 0.91, y: canvasSize.height * 0.80)
    }
}

/// A quiet edge decoration assembled from original shapes. Its compact footprint keeps the
/// center of both phone and tablet landscape layouts clear for the learning target.
private struct MoonpetalRainbow: View {
    let theme: TadaWorldTheme

    var body: some View {
        GeometryReader { proxy in
            let band = max(3, proxy.size.height * 0.13)
            ZStack(alignment: .bottom) {
                rainbowBand(
                    color: theme.secondary.opacity(0.42),
                    inset: 0,
                    band: band,
                    size: proxy.size
                )
                rainbowBand(
                    color: theme.sceneAccent.opacity(0.48),
                    inset: band,
                    band: band,
                    size: proxy.size
                )
                rainbowBand(
                    color: theme.accent.opacity(0.38),
                    inset: band * 2,
                    band: band,
                    size: proxy.size
                )
                rainbowBand(
                    color: theme.primary.opacity(0.32),
                    inset: band * 3,
                    band: band,
                    size: proxy.size
                )

                HStack {
                    rainbowCloud(size: proxy.size.height * 0.31)
                    Spacer()
                    rainbowCloud(size: proxy.size.height * 0.31)
                }
                .padding(.horizontal, proxy.size.width * 0.015)
            }
        }
    }

    private func rainbowBand(
        color: Color,
        inset: CGFloat,
        band: CGFloat,
        size: CGSize
    ) -> some View {
        MoonpetalRainbowArc(insetAmount: inset)
            .stroke(
                color,
                style: StrokeStyle(lineWidth: band, lineCap: .round)
            )
            .frame(width: size.width, height: size.height)
    }

    private func rainbowCloud(size: CGFloat) -> some View {
        ZStack {
            Circle()
                .fill(Color.white.opacity(0.58))
                .frame(width: size, height: size)
                .offset(x: -size * 0.24)
            Circle()
                .fill(Color.white.opacity(0.68))
                .frame(width: size * 1.12, height: size * 1.12)
            Circle()
                .fill(Color.white.opacity(0.54))
                .frame(width: size * 0.82, height: size * 0.82)
                .offset(x: size * 0.34, y: size * 0.08)
        }
        .frame(width: size * 1.7, height: size * 1.2)
    }
}

private struct MoonpetalRainbowArc: InsettableShape {
    var insetAmount: CGFloat = 0

    func path(in rect: CGRect) -> Path {
        let radius = max(0, min(rect.width * 0.5, rect.height) - insetAmount)
        let center = CGPoint(x: rect.midX, y: rect.maxY)
        var path = Path()
        path.addArc(
            center: center,
            radius: radius,
            startAngle: .degrees(180),
            endAngle: .degrees(0),
            clockwise: false
        )
        return path
    }

    func inset(by amount: CGFloat) -> MoonpetalRainbowArc {
        var copy = self
        copy.insetAmount += amount
        return copy
    }
}

/// A tiny storybook unicorn kept at the trailing edge so it adds delight without becoming a
/// competing instruction or tappable control.
private struct MoonpetalUnicorn: View {
    let theme: TadaWorldTheme

    var body: some View {
        GeometryReader { proxy in
            let unit = min(proxy.size.width, proxy.size.height)
            ZStack {
                Capsule()
                    .fill(theme.secondary.opacity(0.52))
                    .frame(width: unit * 0.38, height: unit * 0.13)
                    .rotationEffect(.degrees(-28))
                    .offset(x: -unit * 0.42, y: -unit * 0.03)

                ForEach([-0.25, 0.18], id: \.self) { horizontalOffset in
                    Capsule()
                        .fill(Color.white.opacity(0.74))
                        .frame(width: unit * 0.13, height: unit * 0.45)
                        .offset(x: unit * horizontalOffset, y: unit * 0.28)
                }

                Capsule()
                    .fill(Color.white.opacity(0.78))
                    .frame(width: unit * 0.85, height: unit * 0.50)
                    .rotationEffect(.degrees(-5))
                    .offset(x: -unit * 0.08, y: unit * 0.08)

                Circle()
                    .fill(Color.white.opacity(0.82))
                    .frame(width: unit * 0.54, height: unit * 0.54)
                    .offset(x: unit * 0.31, y: -unit * 0.24)

                Triangle()
                    .fill(theme.sceneAccent.opacity(0.76))
                    .frame(width: unit * 0.17, height: unit * 0.40)
                    .rotationEffect(.degrees(22))
                    .offset(x: unit * 0.40, y: -unit * 0.55)

                VStack(spacing: -unit * 0.03) {
                    Circle().fill(theme.secondary.opacity(0.72))
                    Circle().fill(theme.accent.opacity(0.66))
                    Circle().fill(theme.primary.opacity(0.58))
                }
                .frame(width: unit * 0.18, height: unit * 0.50)
                .rotationEffect(.degrees(-12))
                .offset(x: unit * 0.10, y: -unit * 0.24)

                Circle()
                    .fill(theme.ink.opacity(0.66))
                    .frame(width: unit * 0.055, height: unit * 0.055)
                    .offset(x: unit * 0.43, y: -unit * 0.29)

                Image(systemName: "sparkle")
                    .font(.system(size: unit * 0.18, weight: .bold))
                    .foregroundStyle(theme.sceneAccent.opacity(0.72))
                    .offset(x: unit * 0.64, y: -unit * 0.55)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }
}

private struct MoonpetalCastle: View {
    let theme: TadaWorldTheme

    var body: some View {
        GeometryReader { proxy in
            HStack(alignment: .bottom, spacing: proxy.size.width * 0.025) {
                castleTower(height: proxy.size.height * 0.62, width: proxy.size.width * 0.24)
                castleTower(height: proxy.size.height * 0.86, width: proxy.size.width * 0.30)
                castleTower(height: proxy.size.height * 0.70, width: proxy.size.width * 0.24)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
        }
    }

    private func castleTower(height: CGFloat, width: CGFloat) -> some View {
        VStack(spacing: 0) {
            Triangle()
                .fill(theme.secondary.opacity(0.38))
                .frame(width: width * 1.26, height: height * 0.30)
            RoundedRectangle(cornerRadius: width * 0.16, style: .continuous)
                .fill(theme.primary.opacity(0.24))
                .frame(width: width, height: height * 0.70)
                .overlay(alignment: .bottom) {
                    Capsule()
                        .fill(theme.sceneAccent.opacity(0.52))
                        .frame(width: width * 0.34, height: height * 0.30)
                }
        }
    }
}

private struct BuildItScene: View {
    let theme: TadaWorldTheme
    let isDrifting: Bool

    var body: some View {
        GeometryReader { proxy in
            let storyOffset = TadaWorldStoryArtLayoutPolicy.verticalOffset(
                canvasHeight: proxy.size.height
            )
            ZStack(alignment: .bottom) {
                Circle()
                    .fill(theme.sceneAccent.opacity(0.48))
                    .frame(width: proxy.size.height * 0.16)
                    .position(x: proxy.size.width * 0.84, y: proxy.size.height * 0.18)

                HStack(alignment: .bottom, spacing: proxy.size.width * 0.012) {
                    ForEach(0..<7, id: \.self) { index in
                        RoundedRectangle(cornerRadius: 5, style: .continuous)
                            .fill(
                                (index.isMultiple(of: 2) ? theme.primary : theme.secondary)
                                    .opacity(0.14)
                            )
                            .frame(
                                width: proxy.size.width * 0.075,
                                height: proxy.size.height * (0.14 + Double(index % 3) * 0.045)
                            )
                    }
                }
                .padding(.leading, proxy.size.width * 0.26)
                .padding(.bottom, proxy.size.height * 0.10)
                .offset(y: storyOffset)

                CraneShape()
                    .stroke(
                        theme.primary.opacity(0.28),
                        style: StrokeStyle(
                            lineWidth: max(6, proxy.size.width * 0.009), lineCap: .round)
                    )
                    .frame(width: proxy.size.width * 0.28, height: proxy.size.height * 0.54)
                    .position(x: proxy.size.width * 0.13, y: proxy.size.height * 0.54)
                    .offset(y: storyOffset)

                RoundedRectangle(cornerRadius: 4, style: .continuous)
                    .fill(theme.secondary.opacity(0.40))
                    .frame(width: proxy.size.width * 0.045, height: proxy.size.height * 0.07)
                    .position(
                        x: proxy.size.width * 0.245,
                        y: proxy.size.height * (isDrifting ? 0.48 : 0.43)
                    )
                    .offset(y: storyOffset)

                Rectangle()
                    .fill(theme.ground.opacity(0.24))
                    .frame(height: proxy.size.height * 0.11)
                    .overlay {
                        HStack(spacing: proxy.size.width * 0.045) {
                            ForEach(0..<8, id: \.self) { _ in
                                Capsule()
                                    .fill(Color.white.opacity(0.52))
                                    .frame(width: proxy.size.width * 0.045, height: 5)
                            }
                        }
                    }
            }
        }
    }
}

private struct PawsScene: View {
    let theme: TadaWorldTheme
    let isDrifting: Bool

    var body: some View {
        GeometryReader { proxy in
            let storyOffset = TadaWorldStoryArtLayoutPolicy.verticalOffset(
                canvasHeight: proxy.size.height
            )
            ZStack(alignment: .bottom) {
                Circle()
                    .fill(theme.sceneAccent.opacity(0.48))
                    .frame(width: proxy.size.height * 0.17)
                    .position(x: proxy.size.width * 0.14, y: proxy.size.height * 0.18)

                HillShape(amplitude: 0.16)
                    .fill(theme.ground.opacity(0.18))
                    .frame(height: proxy.size.height * 0.38)

                HStack(alignment: .bottom, spacing: proxy.size.width * 0.032) {
                    ForEach(0..<6, id: \.self) { index in
                        PineTree(theme: theme)
                            .frame(
                                width: proxy.size.height * 0.12,
                                height: proxy.size.height * (index.isMultiple(of: 2) ? 0.30 : 0.23)
                            )
                            .offset(y: index.isMultiple(of: 2) && isDrifting ? -3 : 0)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .trailing)
                .padding(.trailing, proxy.size.width * 0.05)
                .padding(.bottom, proxy.size.height * 0.05)
                .offset(y: storyOffset)

                Image(systemName: "bird.fill")
                    .font(.system(size: max(18, proxy.size.height * 0.05)))
                    .foregroundStyle(theme.primary.opacity(0.34))
                    .position(
                        x: proxy.size.width * (isDrifting ? 0.59 : 0.54),
                        y: proxy.size.height * (isDrifting ? 0.18 : 0.22)
                    )
            }
        }
    }
}

private struct PineTree: View {
    let theme: TadaWorldTheme

    var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .bottom) {
                Capsule()
                    .fill(theme.secondary.opacity(0.22))
                    .frame(width: proxy.size.width * 0.16, height: proxy.size.height * 0.40)
                VStack(spacing: -proxy.size.height * 0.13) {
                    Triangle().fill(theme.primary.opacity(0.25))
                    Triangle().fill(theme.primary.opacity(0.30))
                    Triangle().fill(theme.primary.opacity(0.36))
                }
                .padding(.bottom, proxy.size.height * 0.14)
            }
        }
    }
}

private struct MoonpetalMascot: View {
    let theme: TadaWorldTheme
    let size: CGFloat
    let pose: TadaMascotPose

    var body: some View {
        ZStack {
            ForEach(0..<5, id: \.self) { index in
                Capsule()
                    .fill(theme.secondary)
                    .frame(width: size * 0.30, height: size * 0.56)
                    .offset(y: -size * 0.12)
                    .rotationEffect(.degrees(Double(index) * 72))
            }
            Circle()
                .fill(theme.primary)
                .frame(width: size * 0.68, height: size * 0.68)
            TadaExpressiveMascotFace(
                theme: theme,
                size: size,
                pose: pose,
                personality: .storybook
            )
            Image(systemName: "sparkles")
                .font(.system(size: size * 0.18, weight: .bold))
                .foregroundStyle(theme.sceneAccent)
                .offset(x: size * 0.23, y: -size * 0.22)
        }
    }
}

private struct BuildItMascot: View {
    let theme: TadaWorldTheme
    let size: CGFloat
    let pose: TadaMascotPose

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: size * 0.22, style: .continuous)
                .fill(theme.primary)
                .frame(width: size * 0.72, height: size * 0.64)
                .offset(y: size * 0.08)
            Capsule()
                .fill(theme.sceneAccent)
                .frame(width: size * 0.78, height: size * 0.22)
                .offset(y: -size * 0.25)
            RoundedRectangle(cornerRadius: size * 0.08, style: .continuous)
                .fill(theme.sceneAccent)
                .frame(width: size * 0.54, height: size * 0.24)
                .offset(y: -size * 0.20)
            TadaExpressiveMascotFace(
                theme: theme,
                size: size,
                pose: pose,
                personality: .vehicle
            )
            .offset(y: size * 0.08)
            Circle()
                .fill(theme.secondary)
                .frame(width: size * 0.13)
                .offset(x: -size * 0.38, y: size * 0.06)
            Circle()
                .fill(theme.secondary)
                .frame(width: size * 0.13)
                .offset(x: size * 0.38, y: size * 0.06)
        }
    }
}

private struct PawsMascot: View {
    let theme: TadaWorldTheme
    let size: CGFloat
    let pose: TadaMascotPose

    var body: some View {
        ZStack {
            Triangle()
                .fill(theme.primary)
                .frame(width: size * 0.36, height: size * 0.42)
                .rotationEffect(.degrees(-28))
                .offset(x: -size * 0.24, y: -size * 0.22)
            Triangle()
                .fill(theme.primary)
                .frame(width: size * 0.36, height: size * 0.42)
                .rotationEffect(.degrees(28))
                .offset(x: size * 0.24, y: -size * 0.22)
            Circle()
                .fill(theme.primary)
                .frame(width: size * 0.76, height: size * 0.76)
            TadaExpressiveMascotFace(
                theme: theme,
                size: size,
                pose: pose,
                personality: .woodland
            )
            Image(systemName: "leaf.fill")
                .font(.system(size: size * 0.17, weight: .bold))
                .foregroundStyle(theme.sceneAccent)
                .rotationEffect(.degrees(-24))
                .offset(x: size * 0.27, y: -size * 0.30)
        }
    }
}

private struct HillShape: Shape {
    let amplitude: CGFloat

    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.minX, y: rect.height * 0.50))
        path.addCurve(
            to: CGPoint(x: rect.maxX, y: rect.height * 0.34),
            control1: CGPoint(x: rect.width * 0.24, y: rect.height * (0.50 - amplitude)),
            control2: CGPoint(x: rect.width * 0.66, y: rect.height * (0.34 + amplitude))
        )
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.minX, y: rect.maxY))
        path.closeSubpath()
        return path
    }
}

private struct Triangle: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.midX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.minX, y: rect.maxY))
        path.closeSubpath()
        return path
    }
}

private struct CraneShape: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.width * 0.18, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.width * 0.18, y: rect.height * 0.18))
        path.addLine(to: CGPoint(x: rect.width * 0.92, y: rect.height * 0.18))
        path.move(to: CGPoint(x: rect.width * 0.18, y: rect.height * 0.18))
        path.addLine(to: CGPoint(x: rect.width * 0.02, y: rect.height * 0.38))
        path.move(to: CGPoint(x: rect.width * 0.76, y: rect.height * 0.18))
        path.addLine(to: CGPoint(x: rect.width * 0.76, y: rect.height * 0.64))
        path.move(to: CGPoint(x: rect.width * 0.08, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.width * 0.28, y: rect.maxY))
        return path
    }
}
