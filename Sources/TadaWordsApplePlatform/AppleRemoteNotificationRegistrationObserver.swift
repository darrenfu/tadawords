import Foundation
import TadaWordsDomain

/// Routes UIKit registration callbacks into the process-only Family Sync
/// summary. Its API deliberately has no device-token parameter.
public struct AppleRemoteNotificationRegistrationObserver: Sendable {
    private let bridge: FamilySyncRemoteNotificationBridge

    public init(
        bridge: FamilySyncRemoteNotificationBridge = .shared
    ) {
        self.bridge = bridge
    }

    public func didRegister() async {
        await bridge.recordRegistrationSucceeded()
    }

    public func didFail(error: Error) async {
        await didFail(category: Self.failureCategory(for: error))
    }

    public func didFail(
        category: FamilySyncRemoteNotificationRegistrationFailureCategory
    ) async {
        await bridge.recordRegistrationFailed(category: category)
    }

    public static func failureCategory(
        for error: Error
    ) -> FamilySyncRemoteNotificationRegistrationFailureCategory {
        let error = error as NSError
        if error.domain == NSCocoaErrorDomain, error.code == 3_000 {
            return .configuration
        }
        if error.domain == NSURLErrorDomain || error.domain == NSPOSIXErrorDomain {
            return .connectivity
        }
        return .system
    }
}
