import SwiftUI

enum TadaMascotPersonality: Sendable {
    case storybook
    case vehicle
    case woodland
    case dinosaur
    case helper
    case builder
    case snow
    case adventurer
}

enum TadaMascotEyeExpression: Equatable, Sendable {
    case bright
    case happyArcs
    case gentleWink
    case focused
}

enum TadaMascotMouthExpression: Equatable, Sendable {
    case friendlySmile
    case openCheer
    case softSmile
    case readySmile
}

struct TadaMascotExpression: Equatable, Sendable {
    let eyes: TadaMascotEyeExpression
    let mouth: TadaMascotMouthExpression
    let showsBlush: Bool
}

enum TadaMascotExpressionPolicy {
    static func expression(
        for pose: TadaMascotPose,
        personality: TadaMascotPersonality
    ) -> TadaMascotExpression {
        switch pose {
        case .resting:
            TadaMascotExpression(
                eyes: .bright,
                mouth: .friendlySmile,
                showsBlush: personality.prefersBlush
            )
        case .cheering:
            TadaMascotExpression(
                eyes: .happyArcs,
                mouth: .openCheer,
                showsBlush: true
            )
        case .encouraging:
            TadaMascotExpression(
                eyes: .gentleWink,
                mouth: .softSmile,
                showsBlush: personality.prefersBlush
            )
        case .rescue:
            TadaMascotExpression(
                eyes: .focused,
                mouth: .readySmile,
                showsBlush: false
            )
        }
    }
}

extension TadaMascotPersonality {
    fileprivate var prefersBlush: Bool {
        switch self {
        case .storybook, .woodland, .dinosaur, .snow:
            true
        case .vehicle, .helper, .builder, .adventurer:
            false
        }
    }

    fileprivate var eyeSpacingFactor: CGFloat {
        switch self {
        case .storybook, .snow:
            0.20
        case .vehicle, .helper, .builder:
            0.16
        case .woodland, .dinosaur, .adventurer:
            0.18
        }
    }

    fileprivate var eyeScale: CGFloat {
        switch self {
        case .storybook, .woodland:
            1.08
        case .vehicle, .helper, .builder:
            0.90
        case .dinosaur, .snow, .adventurer:
            1
        }
    }
}

struct TadaExpressiveMascotFace: View {
    let theme: TadaWorldTheme
    let size: CGFloat
    let pose: TadaMascotPose
    let personality: TadaMascotPersonality

    private var expression: TadaMascotExpression {
        TadaMascotExpressionPolicy.expression(for: pose, personality: personality)
    }

    var body: some View {
        VStack(spacing: size * 0.045) {
            eyes
                .frame(width: size * 0.42, height: size * 0.15)
            mouth
                .frame(width: size * 0.28, height: size * 0.17)
        }
        .overlay {
            if expression.showsBlush {
                HStack(spacing: size * 0.34) {
                    Capsule()
                        .fill(theme.secondary.opacity(0.48))
                        .frame(width: size * 0.09, height: size * 0.035)
                    Capsule()
                        .fill(theme.secondary.opacity(0.48))
                        .frame(width: size * 0.09, height: size * 0.035)
                }
                .offset(y: size * 0.075)
            }
        }
    }

    @ViewBuilder
    private var eyes: some View {
        switch expression.eyes {
        case .bright:
            HStack(spacing: size * personality.eyeSpacingFactor) {
                brightEye
                brightEye
            }

        case .happyArcs:
            HStack(spacing: size * personality.eyeSpacingFactor) {
                TadaMascotArc(curvesDown: true)
                    .stroke(
                        Color.white,
                        style: StrokeStyle(lineWidth: size * 0.045, lineCap: .round)
                    )
                TadaMascotArc(curvesDown: true)
                    .stroke(
                        Color.white,
                        style: StrokeStyle(lineWidth: size * 0.045, lineCap: .round)
                    )
            }

        case .gentleWink:
            HStack(spacing: size * personality.eyeSpacingFactor) {
                brightEye
                TadaMascotArc(curvesDown: true)
                    .stroke(
                        Color.white,
                        style: StrokeStyle(lineWidth: size * 0.045, lineCap: .round)
                    )
                    .frame(width: size * 0.11, height: size * 0.08)
            }

        case .focused:
            HStack(spacing: size * personality.eyeSpacingFactor) {
                focusedEye(rotation: 12)
                focusedEye(rotation: -12)
            }
        }
    }

    private var brightEye: some View {
        Circle()
            .fill(Color.white)
            .frame(width: size * 0.11 * personality.eyeScale)
            .overlay {
                Circle()
                    .fill(theme.ink.opacity(0.78))
                    .frame(width: size * 0.045 * personality.eyeScale)
                    .offset(y: size * 0.006)
            }
    }

    private func focusedEye(rotation: Double) -> some View {
        brightEye
            .overlay(alignment: .top) {
                Capsule()
                    .fill(theme.ink.opacity(0.56))
                    .frame(width: size * 0.12, height: size * 0.025)
                    .rotationEffect(.degrees(rotation))
                    .offset(y: -size * 0.025)
            }
    }

    @ViewBuilder
    private var mouth: some View {
        switch expression.mouth {
        case .friendlySmile:
            TadaMascotArc(curvesDown: false)
                .stroke(
                    Color.white.opacity(0.96),
                    style: StrokeStyle(lineWidth: size * 0.045, lineCap: .round)
                )
                .padding(.horizontal, size * 0.045)

        case .openCheer:
            Capsule()
                .fill(Color.white.opacity(0.96))
                .overlay(alignment: .bottom) {
                    Capsule()
                        .fill(theme.secondary.opacity(0.62))
                        .frame(width: size * 0.12, height: size * 0.045)
                        .padding(.bottom, size * 0.018)
                }
                .frame(width: size * 0.25, height: size * 0.15)

        case .softSmile:
            TadaMascotArc(curvesDown: false)
                .stroke(
                    Color.white.opacity(0.96),
                    style: StrokeStyle(lineWidth: size * 0.040, lineCap: .round)
                )
                .padding(.horizontal, size * 0.065)

        case .readySmile:
            TadaMascotArc(curvesDown: false)
                .stroke(
                    Color.white.opacity(0.96),
                    style: StrokeStyle(lineWidth: size * 0.044, lineCap: .round)
                )
                .padding(.horizontal, size * 0.025)
        }
    }
}

private struct TadaMascotArc: Shape {
    let curvesDown: Bool

    func path(in rect: CGRect) -> Path {
        var path = Path()
        let edgeY = curvesDown ? rect.maxY * 0.72 : rect.minY + rect.height * 0.22
        let centerY = curvesDown ? rect.minY + rect.height * 0.20 : rect.maxY * 0.78
        path.move(to: CGPoint(x: rect.minX, y: edgeY))
        path.addQuadCurve(
            to: CGPoint(x: rect.maxX, y: edgeY),
            control: CGPoint(x: rect.midX, y: centerY)
        )
        return path
    }
}
