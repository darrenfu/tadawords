import SwiftUI
import TadaWordsDesignSystem
import TadaWordsDomain

#if os(iOS)
    import UIKit
#endif

enum GuardianPrimitiveTokens {
    enum Spacing {
        static let xSmall: CGFloat = 4
        static let small: CGFloat = 8
        static let medium: CGFloat = 16
        static let large: CGFloat = 24
        static let xLarge: CGFloat = 32
    }

    enum Radius {
        static let small: CGFloat = 10
        static let medium: CGFloat = 16
        static let large: CGFloat = 24
    }

    enum ColorValue {
        static let navy = Color(red: 0.08, green: 0.15, blue: 0.28)
        static let slate = Color(red: 0.37, green: 0.42, blue: 0.51)
        static let blue = Color(red: 0.16, green: 0.39, blue: 0.82)
        static let indigo = Color(red: 0.38, green: 0.30, blue: 0.76)
        static let teal = Color(red: 0.05, green: 0.56, blue: 0.59)
        static let orange = Color(red: 0.92, green: 0.48, blue: 0.13)
        static let red = Color(red: 0.78, green: 0.20, blue: 0.23)
        static let green = Color(red: 0.12, green: 0.55, blue: 0.35)
        static let canvas = Color(red: 0.96, green: 0.97, blue: 0.99)
        static let white = Color.white
    }
}

enum GuardianSemanticTokens {
    static let background = GuardianPrimitiveTokens.ColorValue.canvas
    static let surface = GuardianPrimitiveTokens.ColorValue.white
    static let foreground = GuardianPrimitiveTokens.ColorValue.navy
    static let secondaryForeground = GuardianPrimitiveTokens.ColorValue.slate
    static let primary = GuardianPrimitiveTokens.ColorValue.blue
    static let success = GuardianPrimitiveTokens.ColorValue.green
    static let destructive = GuardianPrimitiveTokens.ColorValue.red

    static func accent(for mode: LearningMode) -> Color {
        switch mode {
        case .read:
            GuardianPrimitiveTokens.ColorValue.indigo
        case .write:
            GuardianPrimitiveTokens.ColorValue.teal
        }
    }
}

struct GuardianCard<Content: View>: View {
    let content: Content

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    var body: some View {
        content
            .padding(GuardianPrimitiveTokens.Spacing.large)
            .background(
                GuardianSemanticTokens.surface,
                in: RoundedRectangle(
                    cornerRadius: GuardianPrimitiveTokens.Radius.large,
                    style: .continuous
                )
            )
            .overlay {
                RoundedRectangle(
                    cornerRadius: GuardianPrimitiveTokens.Radius.large,
                    style: .continuous
                )
                .strokeBorder(GuardianSemanticTokens.foreground.opacity(0.07), lineWidth: 1)
            }
            .shadow(
                color: GuardianSemanticTokens.foreground.opacity(0.07),
                radius: 18,
                y: 7
            )
    }
}

struct GuardianPrimaryButtonStyle: ButtonStyle {
    let tint: Color

    init(tint: Color = GuardianSemanticTokens.primary) {
        self.tint = tint
    }

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(.headline, design: .rounded, weight: .bold))
            .frame(maxWidth: .infinity, minHeight: 52)
            .padding(.horizontal, 18)
            .foregroundStyle(Color.white)
            .background(
                tint.opacity(configuration.isPressed ? 0.82 : 1),
                in: RoundedRectangle(
                    cornerRadius: GuardianPrimitiveTokens.Radius.medium,
                    style: .continuous
                )
            )
            .scaleEffect(configuration.isPressed ? 0.985 : 1)
            .animation(.easeOut(duration: 0.14), value: configuration.isPressed)
    }
}

struct GuardianSecondaryButtonStyle: ButtonStyle {
    let tint: Color

    init(tint: Color = GuardianSemanticTokens.primary) {
        self.tint = tint
    }

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(.headline, design: .rounded, weight: .bold))
            .frame(
                maxWidth: .infinity,
                minHeight: TadaPrimitiveTokens.TouchTarget.minimum
            )
            .padding(.horizontal, 18)
            .foregroundStyle(tint)
            .background(
                tint.opacity(configuration.isPressed ? 0.14 : 0.08),
                in: RoundedRectangle(
                    cornerRadius: GuardianPrimitiveTokens.Radius.medium,
                    style: .continuous
                )
            )
            .overlay {
                RoundedRectangle(
                    cornerRadius: GuardianPrimitiveTokens.Radius.medium,
                    style: .continuous
                )
                .strokeBorder(tint.opacity(0.32), lineWidth: 1.5)
            }
    }
}

struct GuardianModeBadge: View {
    let mode: LearningMode
    var includesPoolSuffix = false

    var body: some View {
        Label(
            includesPoolSuffix ? "\(mode.guardianTitle) Pool" : mode.guardianTitle,
            systemImage: mode.guardianSymbol
        )
        .font(.system(.subheadline, design: .rounded, weight: .bold))
        .foregroundStyle(GuardianSemanticTokens.accent(for: mode))
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(
            GuardianSemanticTokens.accent(for: mode).opacity(0.10),
            in: Capsule()
        )
    }
}

extension LearningMode {
    var guardianTitle: String {
        switch self {
        case .read:
            "Read"
        case .write:
            "Write"
        }
    }

    var guardianSymbol: String {
        switch self {
        case .read:
            "book.pages.fill"
        case .write:
            "pencil.line"
        }
    }
}

extension View {
    /// Parent forms share one keyboard rule: a tap anywhere outside the active
    /// text input dismisses the keyboard without swallowing the tapped control.
    func guardianDismissesKeyboardOnOutsideTap() -> some View {
        #if os(iOS)
            background(GuardianKeyboardDismissInstaller())
        #else
            self
        #endif
    }
}

/// The keyboard-dismiss gesture lives on the window so it also covers sheets.
/// It must remain observational: SwiftUI controls own the same touch sequence.
enum GuardianKeyboardDismissGesturePolicy {
    static let cancelsControlTouches = false
    static let delaysTouchDelivery = false
    static let recognizesAlongsideControls = true
}

#if os(iOS)
    private struct GuardianKeyboardDismissInstaller: UIViewRepresentable {
        func makeCoordinator() -> Coordinator {
            Coordinator()
        }

        func makeUIView(context: Context) -> WindowObservingView {
            let view = WindowObservingView()
            view.isUserInteractionEnabled = false
            view.onWindowChange = { [weak coordinator = context.coordinator] window in
                coordinator?.attach(to: window)
            }
            return view
        }

        func updateUIView(_ uiView: WindowObservingView, context: Context) {
            context.coordinator.attach(to: uiView.window)
        }

        static func dismantleUIView(
            _ uiView: WindowObservingView,
            coordinator: Coordinator
        ) {
            uiView.onWindowChange = nil
            coordinator.detach()
        }

        final class WindowObservingView: UIView {
            var onWindowChange: ((UIWindow?) -> Void)?

            override func didMoveToWindow() {
                super.didMoveToWindow()
                onWindowChange?(window)
            }
        }

        final class Coordinator: NSObject, UIGestureRecognizerDelegate {
            private weak var installedWindow: UIWindow?
            private lazy var tapRecognizer: UITapGestureRecognizer = {
                let recognizer = UITapGestureRecognizer(
                    target: self,
                    action: #selector(dismissKeyboard)
                )
                recognizer.cancelsTouchesInView =
                    GuardianKeyboardDismissGesturePolicy.cancelsControlTouches
                recognizer.delaysTouchesBegan =
                    GuardianKeyboardDismissGesturePolicy.delaysTouchDelivery
                recognizer.delaysTouchesEnded =
                    GuardianKeyboardDismissGesturePolicy.delaysTouchDelivery
                recognizer.delegate = self
                return recognizer
            }()

            func attach(to window: UIWindow?) {
                guard installedWindow !== window else { return }
                detach()
                installedWindow = window
                window?.addGestureRecognizer(tapRecognizer)
            }

            func detach() {
                installedWindow?.removeGestureRecognizer(tapRecognizer)
                installedWindow = nil
            }

            func gestureRecognizer(
                _ gestureRecognizer: UIGestureRecognizer,
                shouldReceive touch: UITouch
            ) -> Bool {
                var candidate = touch.view
                while let view = candidate {
                    if view is UITextField || view is UITextView {
                        return false
                    }
                    candidate = view.superview
                }
                return true
            }

            func gestureRecognizer(
                _ gestureRecognizer: UIGestureRecognizer,
                shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer
            ) -> Bool {
                GuardianKeyboardDismissGesturePolicy.recognizesAlongsideControls
            }

            @objc private func dismissKeyboard() {
                installedWindow?.endEditing(true)
            }
        }
    }
#endif
