import TadaWordsDomain

enum AppleDeviceFamily: Equatable, Sendable {
    case phone
    case pad
}

struct AppleInterfaceOrientationOptions: OptionSet, Equatable, Sendable {
    let rawValue: UInt8

    static let portrait = Self(rawValue: 1 << 0)
    static let portraitUpsideDown = Self(rawValue: 1 << 1)
    static let landscapeLeft = Self(rawValue: 1 << 2)
    static let landscapeRight = Self(rawValue: 1 << 3)

    static let landscape: Self = [.landscapeLeft, .landscapeRight]
    static let allButUpsideDown: Self = [
        .portrait,
        .landscapeLeft,
        .landscapeRight,
    ]
    static let all: Self = [
        .portrait,
        .portraitUpsideDown,
        .landscapeLeft,
        .landscapeRight,
    ]
}

enum AppleInterfaceOrientationPolicy {
    static func options(
        for mode: InterfaceOrientationMode,
        deviceFamily: AppleDeviceFamily
    ) -> AppleInterfaceOrientationOptions {
        switch mode {
        case .childLandscape:
            .landscape
        case .parentFlexible:
            deviceFamily == .pad ? .all : .allButUpsideDown
        }
    }
}

#if os(iOS)
    import UIKit

    @MainActor
    public final class AppleInterfaceOrientationController:
        InterfaceOrientationControlling
    {
        public private(set) var mode: InterfaceOrientationMode = .childLandscape

        public init() {}

        public func apply(_ mode: InterfaceOrientationMode) {
            self.mode = mode
            for case let scene as UIWindowScene in UIApplication.shared.connectedScenes {
                requestGeometryUpdate(for: scene)
            }
        }

        public func supportedOrientations(
            for idiom: UIUserInterfaceIdiom
        ) -> UIInterfaceOrientationMask {
            AppleInterfaceOrientationPolicy.options(
                for: mode,
                deviceFamily: idiom == .pad ? .pad : .phone
            ).uiKitMask
        }

        private func requestGeometryUpdate(for scene: UIWindowScene) {
            for window in scene.windows {
                window.rootViewController?
                    .setNeedsUpdateOfSupportedInterfaceOrientations()
            }
            scene.requestGeometryUpdate(
                .iOS(
                    interfaceOrientations: supportedOrientations(
                        for: scene.traitCollection.userInterfaceIdiom
                    )
                )
            ) { _ in
                // Rotation is supportive navigation. A transient system-sheet
                // refusal is retried the next time the route becomes active.
            }
        }
    }

    extension AppleInterfaceOrientationOptions {
        fileprivate var uiKitMask: UIInterfaceOrientationMask {
            var mask: UIInterfaceOrientationMask = []
            if contains(.portrait) { mask.insert(.portrait) }
            if contains(.portraitUpsideDown) { mask.insert(.portraitUpsideDown) }
            if contains(.landscapeLeft) { mask.insert(.landscapeLeft) }
            if contains(.landscapeRight) { mask.insert(.landscapeRight) }
            return mask
        }
    }
#endif
