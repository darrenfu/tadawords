import SwiftUI

/// Shared landscape geometry for the five expansion worlds.
/// Large story elements stay in the outer quarter of the canvas so quest content owns the center.
struct TadaExpandedWorldSceneLayout: Equatable {
    static let minimumDownwardMotion: CGFloat = 0
    static let maximumDownwardMotion: CGFloat = 4

    let leftStoryFrame: CGRect
    let rightStoryFrame: CGRect
    let groundHeight: CGFloat
    let storyVerticalOffset: CGFloat

    init(canvasSize: CGSize) {
        let storyWidth = min(canvasSize.width * 0.21, canvasSize.height * 0.50)
        let initialStoryHeight = min(canvasSize.height * 0.52, canvasSize.width * 0.27)
        let storyVerticalOffset = TadaWorldStoryArtLayoutPolicy.verticalOffset(
            canvasHeight: canvasSize.height
        )
        let frameOriginY = canvasSize.height * 0.47
        let safeShiftedHeight = max(
            0,
            canvasSize.height - frameOriginY - storyVerticalOffset
                - Self.maximumDownwardMotion
        )
        let storyHeight = min(initialStoryHeight, safeShiftedHeight)

        let leftStoryFrame = CGRect(
            x: canvasSize.width * 0.12 - storyWidth * 0.5,
            y: frameOriginY,
            width: storyWidth,
            height: storyHeight
        )
        let rightStoryFrame = CGRect(
            x: canvasSize.width * 0.88 - storyWidth * 0.5,
            y: frameOriginY,
            width: storyWidth,
            height: storyHeight
        )
        self.leftStoryFrame = leftStoryFrame
        self.rightStoryFrame = rightStoryFrame
        groundHeight = min(canvasSize.height * 0.14, 112)
        self.storyVerticalOffset = storyVerticalOffset
    }
}

struct DinoDiscoveryScene: View {
    let theme: TadaWorldTheme
    let isDrifting: Bool

    var body: some View {
        GeometryReader { proxy in
            let layout = TadaExpandedWorldSceneLayout(canvasSize: proxy.size)
            ZStack(alignment: .bottom) {
                Rectangle()
                    .fill(theme.ground.opacity(0.16))
                    .frame(height: layout.groundHeight)

                DinoHabitat(theme: theme)
                    .frame(width: layout.leftStoryFrame.width, height: layout.leftStoryFrame.height)
                    .position(
                        x: layout.leftStoryFrame.midX,
                        y: layout.leftStoryFrame.midY + layout.storyVerticalOffset
                            + (isDrifting
                                ? TadaExpandedWorldSceneLayout.minimumDownwardMotion : 2)
                    )

                SceneDinosaur(theme: theme)
                    .frame(
                        width: layout.rightStoryFrame.width, height: layout.rightStoryFrame.height
                    )
                    .position(
                        x: layout.rightStoryFrame.midX,
                        y: layout.rightStoryFrame.midY + layout.storyVerticalOffset
                            + (isDrifting
                                ? TadaExpandedWorldSceneLayout.minimumDownwardMotion : 3)
                    )
            }
        }
    }
}

struct FirehouseHeroesScene: View {
    let theme: TadaWorldTheme
    let isDrifting: Bool

    var body: some View {
        GeometryReader { proxy in
            let layout = TadaExpandedWorldSceneLayout(canvasSize: proxy.size)
            ZStack(alignment: .bottom) {
                Rectangle()
                    .fill(theme.ground.opacity(0.16))
                    .frame(height: layout.groundHeight)
                    .overlay {
                        Capsule()
                            .fill(Color.white.opacity(0.48))
                            .frame(height: 5)
                            .padding(.horizontal, proxy.size.width * 0.34)
                    }

                StoryFirehouse(theme: theme)
                    .frame(width: layout.leftStoryFrame.width, height: layout.leftStoryFrame.height)
                    .position(
                        x: layout.leftStoryFrame.midX,
                        y: layout.leftStoryFrame.midY + layout.storyVerticalOffset
                    )

                StoryFireEngine(theme: theme)
                    .frame(
                        width: layout.rightStoryFrame.width, height: layout.rightStoryFrame.height
                    )
                    .position(
                        x: layout.rightStoryFrame.midX,
                        y: layout.rightStoryFrame.midY + layout.storyVerticalOffset
                            + (isDrifting
                                ? TadaExpandedWorldSceneLayout.minimumDownwardMotion : 2)
                    )
            }
        }
    }
}

struct BrickworkCityScene: View {
    let theme: TadaWorldTheme
    let isDrifting: Bool

    var body: some View {
        GeometryReader { proxy in
            let layout = TadaExpandedWorldSceneLayout(canvasSize: proxy.size)
            ZStack(alignment: .bottom) {
                Rectangle()
                    .fill(theme.ground.opacity(0.14))
                    .frame(height: layout.groundHeight)

                ColorBlockSkyline(theme: theme, isMirrored: false)
                    .frame(width: layout.leftStoryFrame.width, height: layout.leftStoryFrame.height)
                    .position(
                        x: layout.leftStoryFrame.midX,
                        y: layout.leftStoryFrame.midY + layout.storyVerticalOffset
                            + (isDrifting
                                ? TadaExpandedWorldSceneLayout.minimumDownwardMotion : 2)
                    )

                ColorBlockSkyline(theme: theme, isMirrored: true)
                    .frame(
                        width: layout.rightStoryFrame.width, height: layout.rightStoryFrame.height
                    )
                    .position(
                        x: layout.rightStoryFrame.midX,
                        y: layout.rightStoryFrame.midY + layout.storyVerticalOffset
                            + (isDrifting
                                ? 2 : TadaExpandedWorldSceneLayout.minimumDownwardMotion)
                    )
            }
        }
    }
}

struct FrostlightWorldScene: View {
    let theme: TadaWorldTheme
    let isDrifting: Bool

    var body: some View {
        GeometryReader { proxy in
            let layout = TadaExpandedWorldSceneLayout(canvasSize: proxy.size)
            ZStack(alignment: .bottom) {
                FrostlightAurora(theme: theme)
                    .frame(width: proxy.size.width, height: proxy.size.height * 0.22)
                    .frame(maxHeight: .infinity, alignment: .top)
                    .opacity(0.42)

                Rectangle()
                    .fill(Color.white.opacity(0.28))
                    .frame(height: layout.groundHeight)

                IceSpireCluster(theme: theme)
                    .frame(width: layout.leftStoryFrame.width, height: layout.leftStoryFrame.height)
                    .position(
                        x: layout.leftStoryFrame.midX,
                        y: layout.leftStoryFrame.midY + layout.storyVerticalOffset
                            + (isDrifting
                                ? TadaExpandedWorldSceneLayout.minimumDownwardMotion : 2)
                    )

                StorySnowBuddy(theme: theme)
                    .frame(
                        width: layout.rightStoryFrame.width, height: layout.rightStoryFrame.height
                    )
                    .position(
                        x: layout.rightStoryFrame.midX,
                        y: layout.rightStoryFrame.midY + layout.storyVerticalOffset
                            + (isDrifting
                                ? TadaExpandedWorldSceneLayout.minimumDownwardMotion : 3)
                    )
            }
        }
    }
}

struct CoasterCarnivalScene: View {
    let theme: TadaWorldTheme
    let isDrifting: Bool

    var body: some View {
        GeometryReader { proxy in
            let layout = TadaExpandedWorldSceneLayout(canvasSize: proxy.size)
            ZStack(alignment: .bottom) {
                Rectangle()
                    .fill(theme.ground.opacity(0.14))
                    .frame(height: layout.groundHeight)

                CoasterLoop(theme: theme)
                    .frame(width: layout.leftStoryFrame.width, height: layout.leftStoryFrame.height)
                    .position(
                        x: layout.leftStoryFrame.midX,
                        y: layout.leftStoryFrame.midY + layout.storyVerticalOffset
                    )

                StoryCoasterCar(theme: theme)
                    .frame(
                        width: layout.rightStoryFrame.width, height: layout.rightStoryFrame.height
                    )
                    .position(
                        x: layout.rightStoryFrame.midX,
                        y: layout.rightStoryFrame.midY + layout.storyVerticalOffset
                            + (isDrifting
                                ? TadaExpandedWorldSceneLayout.minimumDownwardMotion : 4)
                    )
            }
        }
    }
}

struct DinoWorldMascot: View {
    let theme: TadaWorldTheme
    let size: CGFloat
    let pose: TadaMascotPose

    var body: some View {
        ZStack {
            HStack(spacing: -size * 0.05) {
                ForEach(0..<3, id: \.self) { _ in
                    TadaMiniTriangle()
                        .fill(theme.sceneAccent)
                        .frame(width: size * 0.20, height: size * 0.22)
                }
            }
            .rotationEffect(.degrees(-22))
            .offset(x: -size * 0.20, y: -size * 0.31)

            Circle()
                .fill(theme.primary)
                .frame(width: size * 0.76, height: size * 0.72)
            Capsule()
                .fill(theme.secondary)
                .frame(width: size * 0.48, height: size * 0.29)
                .offset(x: size * 0.16, y: size * 0.18)
            TadaExpressiveMascotFace(
                theme: theme,
                size: size,
                pose: pose,
                personality: .dinosaur
            )
            .offset(x: size * 0.06, y: -size * 0.01)
        }
    }
}

struct FirehouseWorldMascot: View {
    let theme: TadaWorldTheme
    let size: CGFloat
    let pose: TadaMascotPose

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: size * 0.17, style: .continuous)
                .fill(theme.primary)
                .frame(width: size * 0.80, height: size * 0.60)
                .offset(y: size * 0.08)
            RoundedRectangle(cornerRadius: size * 0.10, style: .continuous)
                .fill(theme.secondary)
                .frame(width: size * 0.40, height: size * 0.28)
                .offset(x: size * 0.18, y: -size * 0.18)
            Capsule()
                .fill(theme.sceneAccent)
                .frame(width: size * 0.24, height: size * 0.10)
                .offset(y: -size * 0.38)
            HStack(spacing: size * 0.42) {
                Circle().fill(theme.ink).frame(width: size * 0.17)
                Circle().fill(theme.ink).frame(width: size * 0.17)
            }
            .offset(y: size * 0.36)
            TadaExpressiveMascotFace(
                theme: theme,
                size: size,
                pose: pose,
                personality: .helper
            )
            .offset(y: size * 0.07)
        }
    }
}

struct BrickworkWorldMascot: View {
    let theme: TadaWorldTheme
    let size: CGFloat
    let pose: TadaMascotPose

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: size * 0.13, style: .continuous)
                .fill(theme.primary)
                .frame(width: size * 0.70, height: size * 0.68)
            HStack(spacing: size * 0.10) {
                Circle().fill(theme.sceneAccent).frame(width: size * 0.15)
                Circle().fill(theme.secondary).frame(width: size * 0.15)
                Circle().fill(theme.accent).frame(width: size * 0.15)
            }
            .offset(y: -size * 0.39)
            Capsule()
                .fill(theme.secondary)
                .frame(width: size * 0.12, height: size * 0.27)
                .offset(y: -size * 0.52)
            Circle()
                .fill(theme.sceneAccent)
                .frame(width: size * 0.17)
                .offset(y: -size * 0.67)
            TadaExpressiveMascotFace(
                theme: theme,
                size: size,
                pose: pose,
                personality: .builder
            )
        }
    }
}

struct FrostlightWorldMascot: View {
    let theme: TadaWorldTheme
    let size: CGFloat
    let pose: TadaMascotPose

    var body: some View {
        ZStack {
            Circle()
                .fill(Color.white.opacity(0.92))
                .frame(width: size * 0.78, height: size * 0.78)
            Capsule()
                .fill(theme.secondary)
                .frame(width: size * 0.84, height: size * 0.13)
                .offset(y: -size * 0.30)
            RoundedRectangle(cornerRadius: size * 0.08, style: .continuous)
                .fill(theme.primary)
                .frame(width: size * 0.48, height: size * 0.27)
                .offset(y: -size * 0.46)
            TadaExpressiveMascotFace(
                theme: theme,
                size: size,
                pose: pose,
                personality: .snow
            )
            Circle()
                .fill(theme.sceneAccent)
                .frame(width: size * 0.09)
                .offset(y: size * 0.28)
        }
    }
}

struct CoasterWorldMascot: View {
    let theme: TadaWorldTheme
    let size: CGFloat
    let pose: TadaMascotPose

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: size * 0.22, style: .continuous)
                .fill(theme.primary)
                .frame(width: size * 0.82, height: size * 0.60)
                .offset(y: size * 0.09)
            Capsule()
                .stroke(theme.sceneAccent, lineWidth: size * 0.07)
                .frame(width: size * 0.56, height: size * 0.43)
                .offset(y: -size * 0.14)
            HStack(spacing: size * 0.40) {
                Circle().fill(theme.ink).frame(width: size * 0.16)
                Circle().fill(theme.ink).frame(width: size * 0.16)
            }
            .offset(y: size * 0.38)
            TadaExpressiveMascotFace(
                theme: theme,
                size: size,
                pose: pose,
                personality: .adventurer
            )
            .offset(y: size * 0.08)
            Image(systemName: "star.fill")
                .font(.system(size: size * 0.15, weight: .bold))
                .foregroundStyle(theme.sceneAccent)
                .offset(x: size * 0.30, y: size * 0.11)
        }
    }
}

private struct DinoHabitat: View {
    let theme: TadaWorldTheme

    var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .bottom) {
                TadaMiniTriangle()
                    .fill(theme.primary.opacity(0.28))
                    .frame(width: proxy.size.width * 0.78, height: proxy.size.height * 0.72)
                    .overlay(alignment: .top) {
                        TadaMiniTriangle()
                            .fill(theme.sceneAccent.opacity(0.54))
                            .frame(width: proxy.size.width * 0.24, height: proxy.size.height * 0.18)
                            .offset(y: proxy.size.height * 0.10)
                    }

                HStack(alignment: .bottom, spacing: proxy.size.width * 0.13) {
                    ForEach(0..<3, id: \.self) { index in
                        Image(systemName: "leaf.fill")
                            .font(.system(size: proxy.size.height * (index == 1 ? 0.22 : 0.16)))
                            .foregroundStyle(theme.ground.opacity(0.64))
                            .rotationEffect(.degrees(index.isMultiple(of: 2) ? -26 : 22))
                    }
                }
            }
        }
    }
}

private struct SceneDinosaur: View {
    let theme: TadaWorldTheme

    var body: some View {
        GeometryReader { proxy in
            let unit = min(proxy.size.width, proxy.size.height)
            ZStack {
                Capsule()
                    .fill(theme.primary.opacity(0.52))
                    .frame(width: unit * 0.86, height: unit * 0.48)
                    .rotationEffect(.degrees(-7))
                    .offset(y: unit * 0.15)
                Circle()
                    .fill(theme.primary.opacity(0.62))
                    .frame(width: unit * 0.50)
                    .offset(x: unit * 0.30, y: -unit * 0.18)
                HStack(spacing: unit * 0.04) {
                    ForEach(0..<4, id: \.self) { _ in
                        TadaMiniTriangle()
                            .fill(theme.sceneAccent.opacity(0.70))
                            .frame(width: unit * 0.14, height: unit * 0.16)
                    }
                }
                .rotationEffect(.degrees(-8))
                .offset(x: -unit * 0.08, y: -unit * 0.18)
                Circle()
                    .fill(theme.ink.opacity(0.70))
                    .frame(width: unit * 0.055)
                    .offset(x: unit * 0.38, y: -unit * 0.23)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }
}

private struct StoryFirehouse: View {
    let theme: TadaWorldTheme

    var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .bottom) {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(theme.primary.opacity(0.38))
                    .frame(width: proxy.size.width * 0.78, height: proxy.size.height * 0.72)
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(theme.surface.opacity(0.64))
                    .frame(width: proxy.size.width * 0.42, height: proxy.size.height * 0.47)
                Circle()
                    .fill(theme.sceneAccent.opacity(0.82))
                    .frame(width: proxy.size.height * 0.20)
                    .overlay {
                        Image(systemName: "flame.fill")
                            .font(.system(size: proxy.size.height * 0.10, weight: .bold))
                            .foregroundStyle(theme.primary)
                    }
                    .offset(y: -proxy.size.height * 0.55)
            }
        }
    }
}

private struct StoryFireEngine: View {
    let theme: TadaWorldTheme

    var body: some View {
        GeometryReader { proxy in
            ZStack {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(theme.primary.opacity(0.58))
                    .frame(width: proxy.size.width * 0.90, height: proxy.size.height * 0.42)
                    .offset(y: proxy.size.height * 0.18)
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(theme.secondary.opacity(0.64))
                    .frame(width: proxy.size.width * 0.36, height: proxy.size.height * 0.34)
                    .offset(x: proxy.size.width * 0.23, y: -proxy.size.height * 0.12)
                Capsule()
                    .fill(theme.sceneAccent.opacity(0.74))
                    .frame(width: proxy.size.width * 0.22, height: proxy.size.height * 0.08)
                    .offset(y: -proxy.size.height * 0.34)
                HStack(spacing: proxy.size.width * 0.48) {
                    Circle().fill(theme.ink.opacity(0.64)).frame(width: proxy.size.height * 0.18)
                    Circle().fill(theme.ink.opacity(0.64)).frame(width: proxy.size.height * 0.18)
                }
                .offset(y: proxy.size.height * 0.38)
            }
        }
    }
}

private struct ColorBlockSkyline: View {
    let theme: TadaWorldTheme
    let isMirrored: Bool

    var body: some View {
        GeometryReader { proxy in
            HStack(alignment: .bottom, spacing: proxy.size.width * 0.04) {
                blockColumn(color: theme.primary, count: isMirrored ? 3 : 5, proxy: proxy)
                blockColumn(color: theme.secondary, count: isMirrored ? 5 : 3, proxy: proxy)
                blockColumn(color: theme.sceneAccent, count: 4, proxy: proxy)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
        }
    }

    private func blockColumn(
        color: Color,
        count: Int,
        proxy: GeometryProxy
    ) -> some View {
        VStack(spacing: proxy.size.height * 0.018) {
            ForEach(0..<count, id: \.self) { index in
                RoundedRectangle(cornerRadius: 5, style: .continuous)
                    .fill(color.opacity(0.36 + Double(index % 2) * 0.12))
                    .overlay(alignment: .top) {
                        HStack(spacing: 4) {
                            Circle().fill(Color.white.opacity(0.36))
                            Circle().fill(Color.white.opacity(0.36))
                        }
                        .frame(height: proxy.size.height * 0.035)
                    }
                    .frame(height: proxy.size.height * 0.12)
            }
        }
    }
}

private struct FrostlightAurora: View {
    let theme: TadaWorldTheme

    var body: some View {
        GeometryReader { proxy in
            Path { path in
                path.move(to: CGPoint(x: 0, y: proxy.size.height * 0.68))
                path.addCurve(
                    to: CGPoint(x: proxy.size.width, y: proxy.size.height * 0.38),
                    control1: CGPoint(x: proxy.size.width * 0.24, y: 0),
                    control2: CGPoint(x: proxy.size.width * 0.68, y: proxy.size.height)
                )
            }
            .stroke(
                LinearGradient(
                    colors: [theme.sceneAccent, theme.secondary, theme.accent],
                    startPoint: .leading,
                    endPoint: .trailing
                ),
                style: StrokeStyle(lineWidth: proxy.size.height * 0.25, lineCap: .round)
            )
        }
    }
}

private struct IceSpireCluster: View {
    let theme: TadaWorldTheme

    var body: some View {
        GeometryReader { proxy in
            HStack(alignment: .bottom, spacing: -proxy.size.width * 0.05) {
                ForEach(0..<4, id: \.self) { index in
                    TadaMiniTriangle()
                        .fill(
                            (index.isMultiple(of: 2) ? theme.primary : theme.secondary)
                                .opacity(0.24 + Double(index) * 0.05)
                        )
                        .frame(
                            width: proxy.size.width * 0.34,
                            height: proxy.size.height * (0.50 + Double(index % 3) * 0.12)
                        )
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
        }
    }
}

private struct StorySnowBuddy: View {
    let theme: TadaWorldTheme

    var body: some View {
        GeometryReader { proxy in
            let unit = min(proxy.size.width, proxy.size.height)
            ZStack {
                Circle()
                    .fill(Color.white.opacity(0.72))
                    .frame(width: unit * 0.82)
                    .offset(y: unit * 0.24)
                Circle()
                    .fill(Color.white.opacity(0.84))
                    .frame(width: unit * 0.58)
                    .offset(y: -unit * 0.22)
                Capsule()
                    .fill(theme.secondary.opacity(0.70))
                    .frame(width: unit * 0.70, height: unit * 0.12)
                    .offset(y: -unit * 0.52)
                HStack(spacing: unit * 0.20) {
                    Circle().fill(theme.ink.opacity(0.62)).frame(width: unit * 0.06)
                    Circle().fill(theme.ink.opacity(0.62)).frame(width: unit * 0.06)
                }
                .offset(y: -unit * 0.25)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }
}

private struct CoasterLoop: View {
    let theme: TadaWorldTheme

    var body: some View {
        GeometryReader { proxy in
            ZStack {
                Circle()
                    .stroke(
                        theme.primary.opacity(0.46), lineWidth: max(5, proxy.size.width * 0.035)
                    )
                    .frame(width: proxy.size.width * 0.78, height: proxy.size.width * 0.78)
                Circle()
                    .stroke(
                        theme.sceneAccent.opacity(0.46), lineWidth: max(2, proxy.size.width * 0.014)
                    )
                    .frame(width: proxy.size.width * 0.58, height: proxy.size.width * 0.58)
                HStack(spacing: proxy.size.width * 0.24) {
                    Capsule().fill(theme.ink.opacity(0.22)).frame(width: 5)
                    Capsule().fill(theme.ink.opacity(0.22)).frame(width: 5)
                }
                .padding(.top, proxy.size.height * 0.44)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }
}

private struct StoryCoasterCar: View {
    let theme: TadaWorldTheme

    var body: some View {
        GeometryReader { proxy in
            ZStack {
                Capsule()
                    .stroke(
                        theme.secondary.opacity(0.42), lineWidth: max(6, proxy.size.width * 0.035)
                    )
                    .rotationEffect(.degrees(-18))
                    .padding(proxy.size.width * 0.08)
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(theme.primary.opacity(0.66))
                    .frame(width: proxy.size.width * 0.62, height: proxy.size.height * 0.32)
                    .rotationEffect(.degrees(-8))
                HStack(spacing: proxy.size.width * 0.30) {
                    Circle().fill(theme.ink.opacity(0.62)).frame(width: proxy.size.height * 0.12)
                    Circle().fill(theme.ink.opacity(0.62)).frame(width: proxy.size.height * 0.12)
                }
                .rotationEffect(.degrees(-8))
                .offset(y: proxy.size.height * 0.18)
                Image(systemName: "star.fill")
                    .font(.system(size: proxy.size.height * 0.11, weight: .bold))
                    .foregroundStyle(theme.sceneAccent)
            }
        }
    }
}

struct TadaMiniTriangle: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.midX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.minX, y: rect.maxY))
        path.closeSubpath()
        return path
    }
}
