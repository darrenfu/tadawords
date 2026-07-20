import Darwin
import Foundation
import TadaWordsDomain

/// Routes UIKit registration callbacks into the process-only Family Sync
/// summary. Its API deliberately has no device-token parameter.
@MainActor
public final class AppleRemoteNotificationRegistrationObserver {
    private let bridge: FamilySyncRemoteNotificationBridge
    private var callbackPipeline: Task<Void, Never> = Task {}

    public init(
        bridge: FamilySyncRemoteNotificationBridge = .shared
    ) {
        self.bridge = bridge
    }

    public func enqueueDidRegister() {
        appendCallback {
            await $0.recordRegistrationSucceeded()
        }
    }

    public func enqueueDidFail(error: Error) {
        enqueueDidFail(category: Self.failureCategory(for: error))
    }

    public func enqueueDidFail(
        category: FamilySyncRemoteNotificationRegistrationFailureCategory
    ) {
        appendCallback {
            await $0.recordRegistrationFailed(category: category)
        }
    }

    public func finishPendingCallbacks() async {
        await callbackPipeline.value
    }

    nonisolated public static func failureCategory(
        for error: Error
    ) -> FamilySyncRemoteNotificationRegistrationFailureCategory {
        let error = error as NSError
        if error.domain == NSCocoaErrorDomain, error.code == 3_000 {
            return .configuration
        }
        if error.domain == NSURLErrorDomain {
            return .connectivity
        }
        if error.domain == NSPOSIXErrorDomain {
            switch Int32(error.code) {
            case ECONNABORTED, ECONNREFUSED, ECONNRESET, EHOSTDOWN,
                EHOSTUNREACH, ENETDOWN, ENETRESET, ENETUNREACH, ENOTCONN,
                ETIMEDOUT:
                return .connectivity
            default:
                return .system
            }
        }
        return .system
    }

    private func appendCallback(
        _ callback:
            @escaping @Sendable (
                FamilySyncRemoteNotificationBridge
            ) async -> Void
    ) {
        let predecessor = callbackPipeline
        let bridge = bridge
        callbackPipeline = Task {
            await predecessor.value
            await callback(bridge)
        }
    }
}
