/// The orientation contract is route-based rather than device-global. Child
/// learning stays landscape, while parent workflows may follow the device.
public enum InterfaceOrientationMode: Equatable, Sendable {
    case childLandscape
    case parentFlexible
}

/// Platform-neutral boundary used by AppShell. UIKit remains isolated in the
/// Apple platform adapter, and previews/tests can use the inert implementation.
@MainActor
public protocol InterfaceOrientationControlling: AnyObject {
    func apply(_ mode: InterfaceOrientationMode)
}

@MainActor
public final class InertInterfaceOrientationController:
    InterfaceOrientationControlling
{
    public init() {}

    public func apply(_ mode: InterfaceOrientationMode) {
        _ = mode
    }
}
