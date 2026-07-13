import SwiftUI

public struct TadaWorldBackground<Content: View>: View {
    private let theme: TadaWorldTheme
    private let sceneStyle: TadaWorldSceneStyle
    private let content: Content

    public init(
        theme: TadaWorldTheme,
        sceneStyle: TadaWorldSceneStyle = .lobby,
        @ViewBuilder content: () -> Content
    ) {
        self.theme = theme
        self.sceneStyle = sceneStyle
        self.content = content()
    }

    public var body: some View {
        ZStack {
            LinearGradient(
                colors: [theme.backgroundTop, theme.backgroundBottom],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()

            TadaWorldSceneLayer(theme: theme, style: sceneStyle)
                .accessibilityHidden(true)

            content
        }
        .foregroundStyle(theme.ink)
    }
}

public struct TadaPanel<Content: View>: View {
    private let theme: TadaWorldTheme
    private let content: Content

    public init(
        theme: TadaWorldTheme,
        @ViewBuilder content: () -> Content
    ) {
        self.theme = theme
        self.content = content()
    }

    public var body: some View {
        content
            .padding(TadaPrimitiveTokens.Spacing.large)
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
                .strokeBorder(Color.white.opacity(0.62), lineWidth: 1)
            }
            .overlay(alignment: .bottom) {
                Capsule()
                    .fill(theme.primary.opacity(0.12))
                    .frame(height: TadaPrimitiveTokens.Depth.tactileLip)
                    .padding(.horizontal, TadaPrimitiveTokens.Spacing.large)
                    .offset(y: TadaPrimitiveTokens.Depth.tactileLip * 0.45)
            }
            .shadow(
                color: theme.ink.opacity(0.12),
                radius: TadaPrimitiveTokens.Depth.cardShadowRadius,
                y: TadaPrimitiveTokens.Depth.cardShadowY
            )
    }
}

public struct TadaPill: View {
    private let symbol: String?
    private let text: String
    private let tint: Color

    public init(symbol: String? = nil, text: String, tint: Color) {
        self.symbol = symbol
        self.text = text
        self.tint = tint
    }

    public var body: some View {
        HStack(spacing: TadaPrimitiveTokens.Spacing.small) {
            if let symbol {
                Image(systemName: symbol)
                    .accessibilityHidden(true)
            }
            Text(text)
                .font(.system(.subheadline, design: .rounded, weight: .semibold))
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 9)
        .foregroundStyle(tint)
        .background(tint.opacity(0.12), in: Capsule())
    }
}

public struct TadaRewardBadge: View {
    private let theme: TadaWorldTheme
    private let isUnlocked: Bool
    private let size: CGFloat
    private let symbol: String

    public init(
        theme: TadaWorldTheme,
        isUnlocked: Bool,
        size: CGFloat = 88,
        symbol: String? = nil
    ) {
        self.theme = theme
        self.isUnlocked = isUnlocked
        self.size = size
        self.symbol = symbol ?? theme.rewardSymbol
    }

    public var body: some View {
        ZStack {
            Circle()
                .fill(
                    LinearGradient(
                        colors: [theme.secondary, theme.accent],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
            Circle()
                .strokeBorder(Color.white.opacity(0.8), lineWidth: 4)
                .padding(5)
            Image(systemName: isUnlocked ? symbol : "lock.fill")
                .font(.system(size: size * 0.38, weight: .bold, design: .rounded))
                .foregroundStyle(Color.white)
                .symbolEffect(.bounce, value: isUnlocked)
        }
        .frame(width: size, height: size)
        .shadow(color: theme.primary.opacity(0.22), radius: 12, y: 7)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(isUnlocked ? "Unlocked: \(theme.rewardName)" : "Reward locked")
    }
}

public struct TadaStarRow: View {
    private let earned: Int
    private let tint: Color
    private let size: CGFloat

    public init(earned: Int, tint: Color, size: CGFloat = 42) {
        self.earned = min(max(earned, 0), 3)
        self.tint = tint
        self.size = size
    }

    public var body: some View {
        HStack(spacing: TadaPrimitiveTokens.Spacing.small) {
            ForEach(0..<3, id: \.self) { index in
                Image(systemName: index < earned ? "star.fill" : "star")
                    .font(.system(size: size, weight: .bold))
                    .foregroundStyle(index < earned ? tint : tint.opacity(0.24))
                    .accessibilityHidden(true)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(earned) of 3 stars")
    }
}

public struct TadaPrimaryButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled

    private let fill: Color
    private let foreground: Color
    private let isCompact: Bool

    public init(fill: Color, foreground: Color = .white, isCompact: Bool = false) {
        self.fill = fill
        self.foreground = foreground
        self.isCompact = isCompact
    }

    public func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(.headline, design: .rounded, weight: .bold))
            .padding(.horizontal, isCompact ? 16 : 24)
            .frame(minHeight: isCompact ? 48 : 58)
            .foregroundStyle(foreground)
            .background(
                fill,
                in: RoundedRectangle(
                    cornerRadius: isCompact
                        ? TadaPrimitiveTokens.Radius.small
                        : TadaPrimitiveTokens.Radius.medium,
                    style: .continuous
                )
            )
            .overlay(alignment: .top) {
                Capsule()
                    .fill(Color.white.opacity(configuration.isPressed ? 0.16 : 0.32))
                    .frame(height: 3)
                    .padding(.horizontal, isCompact ? 12 : 18)
                    .padding(.top, 4)
            }
            .shadow(
                color: fill.opacity(
                    isEnabled ? (configuration.isPressed ? 0.10 : 0.28) : 0.08
                ),
                radius: configuration.isPressed ? 2 : 8,
                y: configuration.isPressed ? 1 : 5
            )
            .saturation(isEnabled ? 1 : 0.18)
            .opacity(isEnabled ? 1 : 0.62)
            .scaleEffect(configuration.isPressed ? 0.975 : 1)
            .offset(y: configuration.isPressed ? 3 : 0)
            .animation(
                .easeOut(duration: TadaPrimitiveTokens.Motion.quick),
                value: configuration.isPressed
            )
    }
}

public struct TadaTactileCardButtonStyle: ButtonStyle {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    public init() {}

    public func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.985 : 1)
            .offset(y: configuration.isPressed ? 4 : 0)
            .animation(
                reduceMotion
                    ? .linear(duration: 0.01)
                    : .easeOut(duration: TadaPrimitiveTokens.Motion.quick),
                value: configuration.isPressed
            )
    }
}

public struct TadaDisabledControlStyle: ViewModifier {
    private let isDisabled: Bool
    private let theme: TadaWorldTheme

    public init(isDisabled: Bool, theme: TadaWorldTheme) {
        self.isDisabled = isDisabled
        self.theme = theme
    }

    public func body(content: Content) -> some View {
        content
            .foregroundStyle(isDisabled ? theme.ink.opacity(0.48) : theme.ink)
            .background(
                isDisabled ? theme.ink.opacity(0.08) : theme.surface.opacity(0.84),
                in: RoundedRectangle(
                    cornerRadius: TadaPrimitiveTokens.Radius.small,
                    style: .continuous
                )
            )
            .opacity(1)
    }
}

extension View {
    public func tadaDisabledControl(
        _ isDisabled: Bool,
        theme: TadaWorldTheme
    ) -> some View {
        modifier(TadaDisabledControlStyle(isDisabled: isDisabled, theme: theme))
    }

    public func tadaNavigationMotion<Value: Equatable>(
        value: Value,
        standardTransition: AnyTransition
    ) -> some View {
        modifier(
            TadaNavigationMotionModifier(
                value: value,
                standardTransition: standardTransition
            )
        )
    }
}

private struct TadaNavigationMotionModifier<Value: Equatable>: ViewModifier {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    let value: Value
    let standardTransition: AnyTransition

    func body(content: Content) -> some View {
        content
            .transition(reduceMotion ? .opacity : standardTransition)
            .animation(
                reduceMotion
                    ? .linear(duration: 0.01)
                    : .easeInOut(duration: TadaPrimitiveTokens.Motion.standard),
                value: value
            )
    }
}

public struct TadaChildStatePanel<Action: View>: View {
    private let theme: TadaWorldTheme
    private let symbol: String
    private let title: String
    private let message: String
    private let showsProgress: Bool
    private let action: Action

    public init(
        theme: TadaWorldTheme,
        symbol: String,
        title: String,
        message: String,
        showsProgress: Bool = false,
        @ViewBuilder action: () -> Action
    ) {
        self.theme = theme
        self.symbol = symbol
        self.title = title
        self.message = message
        self.showsProgress = showsProgress
        self.action = action()
    }

    public var body: some View {
        TadaPanel(theme: theme) {
            VStack(spacing: TadaPrimitiveTokens.Spacing.medium) {
                ZStack {
                    Circle()
                        .fill(theme.primary.opacity(0.12))
                    if showsProgress {
                        ProgressView()
                            .controlSize(.large)
                            .tint(theme.primary)
                    } else {
                        Image(systemName: symbol)
                            .font(.system(size: 38, weight: .bold))
                            .foregroundStyle(theme.primary)
                    }
                }
                .frame(width: 82, height: 82)
                .accessibilityHidden(true)

                Text(title)
                    .font(.system(.title2, design: .rounded, weight: .bold))
                    .multilineTextAlignment(.center)
                Text(message)
                    .font(.system(.body, design: .rounded, weight: .medium))
                    .foregroundStyle(TadaSemanticColors.secondaryOnSurface(for: theme))
                    .multilineTextAlignment(.center)
                action
            }
            .frame(maxWidth: TadaLayoutTokens.statePanelMaximumWidth)
        }
        .accessibilityElement(children: .contain)
    }
}

extension TadaChildStatePanel where Action == EmptyView {
    public init(
        theme: TadaWorldTheme,
        symbol: String,
        title: String,
        message: String,
        showsProgress: Bool = false
    ) {
        self.init(
            theme: theme,
            symbol: symbol,
            title: title,
            message: message,
            showsProgress: showsProgress
        ) {
            EmptyView()
        }
    }
}

public struct TadaInlineError: View {
    private let message: String

    public init(_ message: String) {
        self.message = message
    }

    public var body: some View {
        Label(message, systemImage: "exclamationmark.circle.fill")
            .font(.system(.subheadline, design: .rounded, weight: .bold))
            .foregroundStyle(TadaPrimitiveTokens.ColorValue.error)
            .accessibilityElement(children: .combine)
    }
}
