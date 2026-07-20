import Darwin
import Foundation
import TadaWordsDomain

/// Routes UIKit registration callbacks into the process-only Family Sync
/// summary. Its API deliberately has no device-token parameter.
@MainActor
public final class AppleRemoteNotificationRegistrationObserver {
    private enum CallbackEvent: Sendable {
        case registered(FamilySyncRemoteNotificationRegistrationAttempt)
        case failed(
            FamilySyncRemoteNotificationRegistrationFailureCategory,
            FamilySyncRemoteNotificationRegistrationAttempt
        )
        case barrier(CheckedContinuation<Void, Never>)
    }

    private let bridge: FamilySyncRemoteNotificationBridge
    private let callbackEvents: AsyncStream<CallbackEvent>.Continuation
    private let callbackConsumer: Task<Void, Never>
    private var attemptsAwaitingCallback: [FamilySyncRemoteNotificationRegistrationAttempt] = []

    public init(
        bridge: FamilySyncRemoteNotificationBridge = .shared
    ) {
        self.bridge = bridge
        let (events, continuation) = AsyncStream.makeStream(
            of: CallbackEvent.self
        )
        callbackEvents = continuation
        callbackConsumer = Task {
            for await event in events {
                switch event {
                case .registered(let attempt):
                    await bridge.recordRegistrationSucceeded(for: attempt)
                case .failed(let category, let attempt):
                    await bridge.recordRegistrationFailed(
                        category: category,
                        for: attempt
                    )
                case .barrier(let completion):
                    completion.resume()
                }
            }
        }
    }

    deinit {
        callbackEvents.finish()
        callbackConsumer.cancel()
    }

    /// Called immediately before UIKit registration on the main actor. The
    /// observer keeps only attempt leases, never device-token bytes.
    public func registrationDidStart(
        _ attempt: FamilySyncRemoteNotificationRegistrationAttempt
    ) {
        guard attempt.isCurrent else { return }
        attemptsAwaitingCallback.append(attempt)
    }

    public func enqueueDidRegister() {
        guard let attempt = takeOldestAttemptAwaitingCallback() else { return }
        callbackEvents.yield(.registered(attempt))
    }

    public func enqueueDidFail(error: Error) {
        enqueueDidFail(category: Self.failureCategory(for: error))
    }

    public func enqueueDidFail(
        category: FamilySyncRemoteNotificationRegistrationFailureCategory
    ) {
        guard let attempt = takeOldestAttemptAwaitingCallback() else { return }
        callbackEvents.yield(.failed(category, attempt))
    }

    public func finishPendingCallbacks() async {
        await withCheckedContinuation { completion in
            callbackEvents.yield(.barrier(completion))
        }
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

    private func takeOldestAttemptAwaitingCallback()
        -> FamilySyncRemoteNotificationRegistrationAttempt?
    {
        guard !attemptsAwaitingCallback.isEmpty else { return nil }
        return attemptsAwaitingCallback.removeFirst()
    }
}
