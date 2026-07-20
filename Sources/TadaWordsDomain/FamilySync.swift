import CryptoKit
import Foundation

extension Notification.Name {
    public static let tadaWordsFamilySyncRemoteChange = Notification.Name(
        "com.tadawords.family-sync.remote-change"
    )
}

public enum FamilySyncBackgroundFetchResult: Sendable {
    case newData
    case noData
    case failed
}

/// Coarse enough for Parent and release diagnostics without retaining Apple's
/// error domain, code, description, account details, or device identifiers.
public enum FamilySyncRemoteNotificationRegistrationFailureCategory:
    String, Equatable, Sendable
{
    case configuration
    case connectivity
    case system
}

/// A bounded, process-only registration summary. The APNs device token is
/// intentionally absent from every case and never enters the domain layer.
public enum FamilySyncRemoteNotificationRegistrationState: Equatable, Sendable {
    case notRequested
    case pending(since: Date)
    /// UIKit does not identify which registration request produced a callback.
    /// After an in-flight request is cancelled and another starts in the same
    /// process, reporting success or failure would invent attribution.
    case unverified(at: Date)
    case registered(at: Date)
    case failed(
        category: FamilySyncRemoteNotificationRegistrationFailureCategory,
        at: Date
    )
}

/// A process-only lease for one platform registration attempt. The lease lets
/// the platform adapter make callback enrollment and its UIKit call atomic
/// with consent invalidation, without exposing or retaining an APNs token.
public final class FamilySyncRemoteNotificationRegistrationAttempt:
    @unchecked Sendable
{
    fileprivate let generation: UInt64
    private let validityLock = NSLock()
    private var current = true

    fileprivate init(generation: UInt64) {
        self.generation = generation
    }

    /// A point-in-time diagnostic snapshot. Do not use this value to authorize
    /// a later platform side effect; use `performIfCurrent(_:)` instead.
    public var isCurrent: Bool {
        validityLock.withLock { current }
    }

    /// Runs a short synchronous platform operation only while the lease is
    /// current. The lock establishes one order between the whole operation and
    /// opt-out invalidation, closing any check-then-call race.
    @discardableResult
    public func performIfCurrent(_ operation: () -> Void) -> Bool {
        validityLock.withLock {
            guard current else { return false }
            operation()
            return true
        }
    }

    fileprivate func invalidate() {
        validityLock.withLock {
            current = false
        }
    }
}

/// Process-wide handoff from UIApplicationDelegate to the bootstrapped
/// coordinator. A push received before SwiftUI composition is ready is latched
/// and replayed after registration instead of being silently lost.
public actor FamilySyncRemoteNotificationBridge {
    public static let shared = FamilySyncRemoteNotificationBridge()

    public typealias Handler = @Sendable () async -> FamilySyncBackgroundFetchResult
    /// Returns whether the adapter actually invoked the platform registration
    /// API. Adapters must lease-protect callback enrollment and the UIKit call
    /// together with `attempt.performIfCurrent(_:)`.
    public typealias RegistrationHandler =
        @Sendable (FamilySyncRemoteNotificationRegistrationAttempt) async -> Bool
    public typealias UnregistrationHandler = @Sendable () async -> Void

    private struct RegistrationAttempt {
        let lease: FamilySyncRemoteNotificationRegistrationAttempt
        let requestedAt: Date
        var didQueuePlatformRegistration = false
        var isDispatchingPlatformRegistration = false
        var didStartPlatformRegistration = false
        var didReceiveTerminalCallback = false
        var isCancelled = false
    }

    private enum RegistrationCallbackOutcome {
        case succeeded
        case failed(FamilySyncRemoteNotificationRegistrationFailureCategory)
    }

    private enum RegistrationPipelineOperation {
        case register(generation: UInt64, handler: RegistrationHandler)
        case unregister(UnregistrationHandler)
        case callback(
            generation: UInt64?,
            outcome: RegistrationCallbackOutcome
        )
    }

    private struct QueuedRegistrationPipelineOperation {
        let operation: RegistrationPipelineOperation
        let completion: CheckedContinuation<Void, Never>
    }

    private var handler: Handler?
    private var handlerWaiters: [UUID: CheckedContinuation<Handler?, Never>] = [:]
    private var registerHandler: RegistrationHandler?
    private var unregisterHandler: UnregistrationHandler?
    private var registrationRequested = false
    private var nextRegistrationGeneration: UInt64 = 0
    private var currentRegistrationGeneration: UInt64?
    private var registrationAttempts: [UInt64: RegistrationAttempt] = [:]
    /// UIApplicationDelegate registration callbacks carry no attempt ID. Once
    /// a started attempt is cancelled, no callback in this process can be
    /// safely attributed to that attempt or any replacement attempt.
    private var hasAmbiguousPlatformRegistrationCallbackAttribution = false
    private var registrationPipelineQueue: [QueuedRegistrationPipelineOperation] = []
    private var isRegistrationPipelineRunning = false
    private let clock: any AppClock
    private var currentRegistrationState: FamilySyncRemoteNotificationRegistrationState =
        .notRequested
    private var registrationStateContinuations:
        [UUID: AsyncStream<FamilySyncRemoteNotificationRegistrationState>.Continuation] = [:]

    public init(clock: any AppClock = SystemAppClock()) {
        self.clock = clock
    }

    public func register(handler: @escaping Handler) {
        self.handler = handler
        let waiters = handlerWaiters.values
        handlerWaiters.removeAll()
        for waiter in waiters { waiter.resume(returning: handler) }
    }

    public func configureRegistration(
        register: @escaping RegistrationHandler,
        unregister: @escaping UnregistrationHandler
    ) async {
        registerHandler = register
        unregisterHandler = unregister
        guard let operation = beginCurrentPlatformRegistrationIfNeeded() else {
            return
        }
        await enqueueRegistrationPipelineOperation(operation)
    }

    public func requestRegistration() async {
        if registrationRequested,
            let currentRegistrationGeneration,
            let currentRegistrationAttempt =
                registrationAttempts[currentRegistrationGeneration],
            !currentRegistrationAttempt.didReceiveTerminalCallback
        {
            return
        }
        if registrationRequested,
            case .registered = currentRegistrationState
        {
            return
        }

        if let currentRegistrationGeneration,
            registrationAttempts[currentRegistrationGeneration]?
                .didReceiveTerminalCallback == true
        {
            registrationAttempts.removeValue(
                forKey: currentRegistrationGeneration
            )
        }

        registrationRequested = true
        nextRegistrationGeneration &+= 1
        let generation = nextRegistrationGeneration
        let lease = FamilySyncRemoteNotificationRegistrationAttempt(
            generation: generation
        )
        registrationAttempts[generation] = RegistrationAttempt(
            lease: lease,
            requestedAt: clock.now
        )
        currentRegistrationGeneration = generation
        if hasAmbiguousPlatformRegistrationCallbackAttribution
            || hasUnresolvedCancelledCallback(before: generation)
        {
            publishRegistrationState(.unverified(at: clock.now))
        } else {
            publishRegistrationState(.pending(since: clock.now))
        }
        guard let operation = beginCurrentPlatformRegistrationIfNeeded() else {
            return
        }
        await enqueueRegistrationPipelineOperation(operation)
    }

    /// Retries only while Family Sync still owns registration consent. This is
    /// safe to call from a stale Parent failure card after an opt-out finishes.
    public func retryRegistrationIfRequested() async {
        guard registrationRequested else { return }
        await requestRegistration()
    }

    public func requestUnregistration() async {
        guard registrationRequested || currentRegistrationGeneration != nil else {
            return
        }
        if let currentRegistrationGeneration,
            var currentRegistrationAttempt =
                registrationAttempts[currentRegistrationGeneration]
        {
            currentRegistrationAttempt.lease.invalidate()
            currentRegistrationAttempt.isCancelled = true
            if currentRegistrationAttempt.didStartPlatformRegistration,
                !currentRegistrationAttempt.didReceiveTerminalCallback
            {
                hasAmbiguousPlatformRegistrationCallbackAttribution = true
            }
            if currentRegistrationAttempt.didReceiveTerminalCallback
                || (!currentRegistrationAttempt.didStartPlatformRegistration
                    && !currentRegistrationAttempt
                        .isDispatchingPlatformRegistration)
            {
                registrationAttempts.removeValue(
                    forKey: currentRegistrationGeneration
                )
            } else {
                registrationAttempts[currentRegistrationGeneration] =
                    currentRegistrationAttempt
            }
        }
        registrationRequested = false
        currentRegistrationGeneration = nil
        publishRegistrationState(.notRequested)
        guard let unregisterHandler else { return }
        await enqueueRegistrationPipelineOperation(
            .unregister(unregisterHandler)
        )
    }

    public func registrationState()
        -> FamilySyncRemoteNotificationRegistrationState
    {
        currentRegistrationState
    }

    /// Replays the latest state and keeps only one unread update per observer.
    /// Terminated observers are removed so the process-wide bridge remains
    /// bounded as Parent views appear and disappear.
    public func registrationStates()
        -> AsyncStream<FamilySyncRemoteNotificationRegistrationState>
    {
        let id = UUID()
        let (stream, continuation) = AsyncStream.makeStream(
            of: FamilySyncRemoteNotificationRegistrationState.self,
            bufferingPolicy: .bufferingNewest(1)
        )
        continuation.onTermination = { [weak self] _ in
            Task { await self?.removeRegistrationStateContinuation(id) }
        }
        registrationStateContinuations[id] = continuation
        continuation.yield(currentRegistrationState)
        return stream
    }

    public func recordRegistrationSucceeded() async {
        await enqueueRegistrationPipelineOperation(
            .callback(generation: nil, outcome: .succeeded)
        )
    }

    public func recordRegistrationSucceeded(
        for attempt: FamilySyncRemoteNotificationRegistrationAttempt
    ) async {
        await enqueueRegistrationPipelineOperation(
            .callback(
                generation: attempt.generation,
                outcome: .succeeded
            )
        )
    }

    public func recordRegistrationFailed(
        category: FamilySyncRemoteNotificationRegistrationFailureCategory
    ) async {
        await enqueueRegistrationPipelineOperation(
            .callback(generation: nil, outcome: .failed(category))
        )
    }

    public func recordRegistrationFailed(
        category: FamilySyncRemoteNotificationRegistrationFailureCategory,
        for attempt: FamilySyncRemoteNotificationRegistrationAttempt
    ) async {
        await enqueueRegistrationPipelineOperation(
            .callback(
                generation: attempt.generation,
                outcome: .failed(category)
            )
        )
    }

    public func handleNotification() async -> FamilySyncBackgroundFetchResult {
        let resolvedHandler: Handler?
        if let handler {
            resolvedHandler = handler
        } else {
            resolvedHandler = await waitForHandler()
        }
        guard let resolvedHandler else { return .noData }
        return await resolvedHandler()
    }

    private func waitForHandler() async -> Handler? {
        if let handler { return handler }
        let id = UUID()
        return await withCheckedContinuation { continuation in
            handlerWaiters[id] = continuation
            Task {
                try? await Task.sleep(for: .seconds(15))
                self.timeoutWaiter(id)
            }
        }
    }

    private func timeoutWaiter(_ id: UUID) {
        handlerWaiters.removeValue(forKey: id)?.resume(returning: nil)
    }

    private func beginCurrentPlatformRegistrationIfNeeded()
        -> RegistrationPipelineOperation?
    {
        guard registrationRequested,
            let currentRegistrationGeneration,
            var currentRegistrationAttempt =
                registrationAttempts[currentRegistrationGeneration],
            !currentRegistrationAttempt.didQueuePlatformRegistration,
            let registerHandler
        else {
            return nil
        }
        currentRegistrationAttempt.didQueuePlatformRegistration = true
        registrationAttempts[currentRegistrationGeneration] =
            currentRegistrationAttempt
        return .register(
            generation: currentRegistrationGeneration,
            handler: registerHandler
        )
    }

    private func enqueueRegistrationPipelineOperation(
        _ operation: RegistrationPipelineOperation
    ) async {
        guard isRegistrationPipelineRunning else {
            isRegistrationPipelineRunning = true
            await performRegistrationPipelineOperation(operation)
            await drainRegistrationPipeline()
            isRegistrationPipelineRunning = false
            return
        }

        await withCheckedContinuation { continuation in
            registrationPipelineQueue.append(
                QueuedRegistrationPipelineOperation(
                    operation: operation,
                    completion: continuation
                )
            )
        }
    }

    private func drainRegistrationPipeline() async {
        while !registrationPipelineQueue.isEmpty {
            let queued = registrationPipelineQueue.removeFirst()
            await performRegistrationPipelineOperation(queued.operation)
            queued.completion.resume()
        }
    }

    private func performRegistrationPipelineOperation(
        _ operation: RegistrationPipelineOperation
    ) async {
        switch operation {
        case .register(let generation, let handler):
            guard registrationRequested,
                currentRegistrationGeneration == generation,
                var registrationAttempt = registrationAttempts[generation],
                registrationAttempt.lease.isCurrent
            else {
                removeCancelledAttemptIfItCannotProduceCallback(generation)
                return
            }
            registrationAttempt.isDispatchingPlatformRegistration = true
            registrationAttempts[generation] = registrationAttempt

            let didStartPlatformRegistration = await handler(
                registrationAttempt.lease
            )
            guard var completedAttempt = registrationAttempts[generation] else {
                return
            }
            completedAttempt.isDispatchingPlatformRegistration = false
            completedAttempt.didStartPlatformRegistration =
                didStartPlatformRegistration
            if completedAttempt.isCancelled,
                didStartPlatformRegistration,
                !completedAttempt.didReceiveTerminalCallback
            {
                hasAmbiguousPlatformRegistrationCallbackAttribution = true
            }
            if completedAttempt.isCancelled,
                !didStartPlatformRegistration
            {
                registrationAttempts.removeValue(forKey: generation)
                publishPendingIfCurrentAttemptBecameAttributable()
            } else {
                registrationAttempts[generation] = completedAttempt
            }
        case .unregister(let handler):
            await handler()
        case .callback(let generation, let outcome):
            applyRegistrationCallback(
                generation: generation,
                outcome: outcome
            )
        }
    }

    private func applyRegistrationCallback(
        generation: UInt64?,
        outcome: RegistrationCallbackOutcome
    ) {
        guard !hasAmbiguousPlatformRegistrationCallbackAttribution else {
            return
        }
        let resolvedGeneration =
            generation ?? oldestAttemptAwaitingCallbackGeneration()
        guard let resolvedGeneration,
            var registrationAttempt = registrationAttempts[resolvedGeneration],
            registrationAttempt.didStartPlatformRegistration,
            !registrationAttempt.didReceiveTerminalCallback
        else {
            return
        }

        registrationAttempt.didReceiveTerminalCallback = true
        if registrationAttempt.isCancelled
            || !registrationAttempt.lease.isCurrent
            || !registrationRequested
            || currentRegistrationGeneration != resolvedGeneration
        {
            registrationAttempts.removeValue(forKey: resolvedGeneration)
            return
        }

        registrationAttempts[resolvedGeneration] = registrationAttempt
        switch outcome {
        case .succeeded:
            publishRegistrationState(.registered(at: clock.now))
        case .failed(let category):
            publishRegistrationState(.failed(category: category, at: clock.now))
        }
    }

    private func hasUnresolvedCancelledCallback(before generation: UInt64) -> Bool {
        registrationAttempts.contains { candidateGeneration, attempt in
            candidateGeneration < generation
                && attempt.isCancelled
                && !attempt.didReceiveTerminalCallback
                && (attempt.didStartPlatformRegistration
                    || attempt.isDispatchingPlatformRegistration)
        }
    }

    private func oldestAttemptAwaitingCallbackGeneration() -> UInt64? {
        registrationAttempts
            .filter { _, attempt in
                attempt.didStartPlatformRegistration
                    && !attempt.didReceiveTerminalCallback
            }
            .map(\.key)
            .min()
    }

    private func removeCancelledAttemptIfItCannotProduceCallback(
        _ generation: UInt64
    ) {
        guard let attempt = registrationAttempts[generation],
            attempt.isCancelled,
            !attempt.didStartPlatformRegistration,
            !attempt.isDispatchingPlatformRegistration
        else {
            return
        }
        registrationAttempts.removeValue(forKey: generation)
        publishPendingIfCurrentAttemptBecameAttributable()
    }

    private func publishPendingIfCurrentAttemptBecameAttributable() {
        guard registrationRequested,
            case .unverified = currentRegistrationState,
            !hasAmbiguousPlatformRegistrationCallbackAttribution,
            let currentRegistrationGeneration,
            let currentAttempt =
                registrationAttempts[currentRegistrationGeneration],
            !hasUnresolvedCancelledCallback(
                before: currentRegistrationGeneration
            )
        else {
            return
        }
        publishRegistrationState(.pending(since: currentAttempt.requestedAt))
    }

    private func publishRegistrationState(
        _ state: FamilySyncRemoteNotificationRegistrationState
    ) {
        currentRegistrationState = state
        for continuation in registrationStateContinuations.values {
            continuation.yield(state)
        }
    }

    private func removeRegistrationStateContinuation(_ id: UUID) {
        registrationStateContinuations.removeValue(forKey: id)
    }
}

public actor FamilySyncConnectivityRecoveryBridge {
    public static let shared = FamilySyncConnectivityRecoveryBridge()
    public typealias Handler = @Sendable () async -> Void

    private var handler: Handler?
    private var hasPendingRecovery = false

    public init() {}

    public func register(handler: @escaping Handler) {
        self.handler = handler
        guard hasPendingRecovery else { return }
        hasPendingRecovery = false
        Task { await handler() }
    }

    public func handleRecovery() async {
        guard let handler else {
            hasPendingRecovery = true
            return
        }
        await handler()
    }
}

public enum FamilySyncRecordKind: String, Codable, CaseIterable, Hashable, Sendable {
    case profile
    case wordPoolEntry
    case practiceSettings
    case attempt
    case attemptCorrection
    case wordProgress
    case dailyPlan
    case dailyCompletion
    case rewardGrant
    case profileDeletion
}

public struct FamilySyncLogicalRevision: Codable, Hashable, Sendable {
    public let counter: UInt64
    public let deviceID: String

    public init(counter: UInt64, deviceID: String) {
        self.counter = counter
        self.deviceID = deviceID.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    public static func next(
        after revisions: [Self],
        deviceID: String
    ) -> Self {
        let greatest = revisions.map(\.counter).max() ?? 0
        let nextCounter = greatest == .max ? UInt64.max : greatest + 1
        return Self(counter: nextCounter, deviceID: deviceID)
    }
}

extension FamilySyncLogicalRevision: Comparable {
    public static func < (lhs: Self, rhs: Self) -> Bool {
        if lhs.counter != rhs.counter {
            return lhs.counter < rhs.counter
        }
        return lhs.deviceID < rhs.deviceID
    }
}

public struct FamilySyncRecord: Codable, Hashable, Sendable {
    public static let currentSchemaVersion = 2
    public static let minimumReadableSchemaVersion = 1
    public static let maximumPayloadSize = 384 * 1_024
    public static let maximumEncodedEnvelopeSize = 600_000

    public let recordName: String
    public let profileID: ProfileID
    public let kind: FamilySyncRecordKind
    public let payload: Data
    public let updatedAt: Date
    public let deviceID: String
    public let isDeleted: Bool
    public let schemaVersion: Int
    public let minimumReadableVersion: Int
    public let logicalRevision: FamilySyncLogicalRevision
    public let payloadChecksum: String
    public let payloadSize: Int

    public init(
        recordName: String,
        profileID: ProfileID,
        kind: FamilySyncRecordKind,
        payload: Data,
        updatedAt: Date,
        deviceID: String,
        isDeleted: Bool = false,
        schemaVersion: Int = Self.currentSchemaVersion,
        minimumReadableVersion: Int = Self.minimumReadableSchemaVersion,
        logicalRevision: FamilySyncLogicalRevision? = nil,
        payloadChecksum: String? = nil,
        payloadSize: Int? = nil
    ) {
        let normalizedDeviceID = deviceID.trimmingCharacters(in: .whitespacesAndNewlines)
        self.recordName = recordName.trimmingCharacters(in: .whitespacesAndNewlines)
        self.profileID = profileID
        self.kind = kind
        self.payload = payload
        self.updatedAt = updatedAt
        self.deviceID = normalizedDeviceID
        self.isDeleted = isDeleted
        self.schemaVersion = schemaVersion
        self.minimumReadableVersion = minimumReadableVersion
        self.logicalRevision =
            logicalRevision
            ?? FamilySyncLogicalRevision(counter: 0, deviceID: normalizedDeviceID)
        self.payloadChecksum = payloadChecksum ?? Self.checksum(for: payload)
        self.payloadSize = payloadSize ?? payload.count
    }

    public func assigning(revision: FamilySyncLogicalRevision) -> Self {
        Self(
            recordName: recordName,
            profileID: profileID,
            kind: kind,
            payload: payload,
            updatedAt: updatedAt,
            deviceID: revision.deviceID,
            isDeleted: isDeleted,
            schemaVersion: schemaVersion,
            minimumReadableVersion: minimumReadableVersion,
            logicalRevision: revision,
            payloadChecksum: payloadChecksum,
            payloadSize: payloadSize
        )
    }

    public func validateCompatibility() throws {
        guard !recordName.isEmpty else {
            throw FamilySyncEnvelopeError.invalidIdentity
        }
        guard !deviceID.isEmpty, !logicalRevision.deviceID.isEmpty,
            deviceID == logicalRevision.deviceID
        else {
            throw FamilySyncEnvelopeError.invalidIdentity
        }
        guard schemaVersion >= Self.minimumReadableSchemaVersion else {
            throw FamilySyncEnvelopeError.unsupportedSchemaVersion(schemaVersion)
        }
        guard schemaVersion <= Self.currentSchemaVersion else {
            // A future schema may contain fields this client would silently
            // discard during a read-modify-write. Preserve it in quarantine.
            throw FamilySyncEnvelopeError.unsupportedSchemaVersion(schemaVersion)
        }
        guard minimumReadableVersion <= Self.currentSchemaVersion else {
            throw FamilySyncEnvelopeError.requiresNewerClient(minimumReadableVersion)
        }
        guard payloadSize >= 0, payloadSize == payload.count else {
            throw FamilySyncEnvelopeError.payloadSizeMismatch(
                expected: payloadSize,
                actual: payload.count
            )
        }
        guard payloadSize <= Self.maximumPayloadSize else {
            throw FamilySyncEnvelopeError.payloadTooLarge(
                payloadSize,
                maximum: Self.maximumPayloadSize
            )
        }
        let actualChecksum = Self.checksum(for: payload)
        guard payloadChecksum == actualChecksum else {
            throw FamilySyncEnvelopeError.checksumMismatch
        }
        if let encodedEnvelope = try? JSONEncoder().encode(
            FamilySyncEnvelope(record: self)
        ), encodedEnvelope.count > Self.maximumEncodedEnvelopeSize {
            throw FamilySyncEnvelopeError.envelopeTooLarge(
                encodedEnvelope.count,
                maximum: Self.maximumEncodedEnvelopeSize
            )
        }
    }

    public static func checksum(for payload: Data) -> String {
        SHA256.hash(data: payload).map { String(format: "%02x", $0) }.joined()
    }
}

public struct FamilySyncEnvelope: Codable, Hashable, Sendable {
    public let recordName: String
    public let profileID: ProfileID
    public let kindIdentifier: String
    public let payload: Data
    public let updatedAt: Date
    public let isDeleted: Bool
    public let schemaVersion: Int
    public let minimumReadableVersion: Int
    public let logicalRevision: FamilySyncLogicalRevision
    public let payloadChecksum: String
    public let payloadSize: Int

    public init(record: FamilySyncRecord) {
        recordName = record.recordName
        profileID = record.profileID
        kindIdentifier = record.kind.rawValue
        payload = record.payload
        updatedAt = record.updatedAt
        isDeleted = record.isDeleted
        schemaVersion = record.schemaVersion
        minimumReadableVersion = record.minimumReadableVersion
        logicalRevision = record.logicalRevision
        payloadChecksum = record.payloadChecksum
        payloadSize = record.payloadSize
    }

    public func decodedRecord() throws -> FamilySyncRecord {
        guard let kind = FamilySyncRecordKind(rawValue: kindIdentifier) else {
            throw FamilySyncEnvelopeError.unknownRecordKind(kindIdentifier)
        }
        let record = FamilySyncRecord(
            recordName: recordName,
            profileID: profileID,
            kind: kind,
            payload: payload,
            updatedAt: updatedAt,
            deviceID: logicalRevision.deviceID,
            isDeleted: isDeleted,
            schemaVersion: schemaVersion,
            minimumReadableVersion: minimumReadableVersion,
            logicalRevision: logicalRevision,
            payloadChecksum: payloadChecksum,
            payloadSize: payloadSize
        )
        try record.validateCompatibility()
        return record
    }
}

public enum FamilySyncEnvelopeError: Error, Equatable, Sendable {
    case invalidIdentity
    case unsupportedSchemaVersion(Int)
    case requiresNewerClient(Int)
    case unknownRecordKind(String)
    case payloadSizeMismatch(expected: Int, actual: Int)
    case payloadTooLarge(Int, maximum: Int)
    case envelopeTooLarge(Int, maximum: Int)
    case checksumMismatch
}

public enum FamilySyncCapability: Equatable, Sendable {
    case deviceOnly
    case iCloud
}

public enum FamilySyncAvailability: Equatable, Sendable {
    case available
    case deviceOnly
    case noAccount
    case restricted
    case temporarilyUnavailable
}

public enum FamilySyncStatus: Equatable, Sendable {
    case idle
    case optedOut(message: String)
    case deviceOnly(message: String)
    case syncing(pendingCount: Int)
    case synced(at: Date)
    case pendingOffline(
        pendingCount: Int,
        retryCount: Int = 0,
        nextRetryAt: Date? = nil
    )
    case iCloudUnavailable(message: String)
    case failed(message: String, pendingCount: Int)
}

public enum FamilySyncConsentError: Error, Equatable, Sendable {
    case deviceOnly
    case optInRequired
}

public struct FamilySyncChangeKey: Codable, Hashable, Sendable {
    public let profileID: ProfileID
    public let recordName: String

    public init(profileID: ProfileID, recordName: String) {
        self.profileID = profileID
        self.recordName = recordName
    }
}

public enum FamilySyncPendingOperation: Hashable, Sendable {
    case save(FamilySyncRecord)
    case delete(key: FamilySyncChangeKey, revision: FamilySyncLogicalRevision)

    public var key: FamilySyncChangeKey {
        switch self {
        case .save(let record):
            FamilySyncChangeKey(profileID: record.profileID, recordName: record.recordName)
        case .delete(let key, _):
            key
        }
    }

    public var revision: FamilySyncLogicalRevision {
        switch self {
        case .save(let record):
            record.logicalRevision
        case .delete(_, let revision):
            revision
        }
    }

    public var operationKind: FamilySyncChangeOperationKind {
        switch self {
        case .save:
            .save
        case .delete:
            .delete
        }
    }
}

public enum FamilySyncChangeOperationKind: String, Codable, Hashable, Sendable {
    case save
    case delete
}

public struct FamilySyncChangeAcknowledgement: Hashable, Sendable {
    public let key: FamilySyncChangeKey
    public let revision: FamilySyncLogicalRevision
    public let operation: FamilySyncChangeOperationKind

    public init(
        key: FamilySyncChangeKey,
        revision: FamilySyncLogicalRevision,
        operation: FamilySyncChangeOperationKind
    ) {
        self.key = key
        self.revision = revision
        self.operation = operation
    }

    public init(operation: FamilySyncPendingOperation) {
        key = operation.key
        revision = operation.revision
        self.operation = operation.operationKind
    }
}

public struct FamilySyncTransportBatch: Sendable {
    public let profileIDs: [ProfileID]
    public let changes: [FamilySyncPendingOperation]

    public init(profileIDs: [ProfileID], changes: [FamilySyncPendingOperation]) {
        self.profileIDs = profileIDs
        self.changes = changes
    }
}

public struct FamilySyncRemoteDeletion: Hashable, Sendable {
    public let key: FamilySyncChangeKey

    public init(key: FamilySyncChangeKey) {
        self.key = key
    }
}

public struct FamilySyncFetchedReceipt: Hashable, Sendable {
    public let id: UUID
    public let key: FamilySyncChangeKey
    public let operation: FamilySyncChangeOperationKind
    public let revision: FamilySyncLogicalRevision?

    public init(
        id: UUID,
        key: FamilySyncChangeKey,
        operation: FamilySyncChangeOperationKind,
        revision: FamilySyncLogicalRevision?
    ) {
        self.id = id
        self.key = key
        self.operation = operation
        self.revision = revision
    }
}

public enum FamilySyncPrivacySafeErrorCategory:
    String, Codable, Equatable, Hashable, Sendable
{
    case account
    case connectivity
    case rateLimited
    case server
    case compatibility
    case corruptState
    case conflict
    case unknown
}

/// Privacy-minimal role used to explain a Profile erasure without retaining
/// an Apple Account identifier, share URL, or any child-owned content.
public enum ProfileErasureRoute: String, Codable, Equatable, Hashable, Sendable {
    case unresolved
    case owner
    case participant
}

public enum ProfileErasureState: String, Codable, Equatable, Hashable, Sendable {
    case requested
    case deleting
    case waitingForConnection
    case needsAttention
    case complete
}

/// A bounded, Profile-scoped summary of remote erasure progress. This value is
/// intentionally unsuitable for child UI and diagnostics must aggregate it
/// before display so the opaque Profile ID never leaves the repository layer.
public struct ProfileErasureLifecycle: Codable, Equatable, Sendable {
    public let profileID: ProfileID
    public let route: ProfileErasureRoute
    public let state: ProfileErasureState
    public let requestedAt: Date
    public let attemptCount: Int
    public let retryCount: Int
    public let lastAttemptAt: Date?
    public let nextRetryAt: Date?
    public let lastSuccessAt: Date?
    public let errorCategory: FamilySyncPrivacySafeErrorCategory?

    public init(
        profileID: ProfileID,
        route: ProfileErasureRoute = .unresolved,
        state: ProfileErasureState = .requested,
        requestedAt: Date,
        attemptCount: Int = 0,
        retryCount: Int = 0,
        lastAttemptAt: Date? = nil,
        nextRetryAt: Date? = nil,
        lastSuccessAt: Date? = nil,
        errorCategory: FamilySyncPrivacySafeErrorCategory? = nil
    ) {
        self.profileID = profileID
        self.route = route
        self.state = state
        self.requestedAt = requestedAt
        self.attemptCount = max(0, attemptCount)
        self.retryCount = max(0, retryCount)
        self.lastAttemptAt = lastAttemptAt
        self.nextRetryAt = nextRetryAt
        self.lastSuccessAt = lastSuccessAt
        self.errorCategory = errorCategory
    }
}

public enum ProfileErasureTransportOutcome: Equatable, Hashable, Sendable {
    case completed
    case failed(
        category: FamilySyncPrivacySafeErrorCategory,
        retryAfter: TimeInterval? = nil
    )
}

/// Exact transport evidence for one versioned Profile tombstone. A completed
/// disposition is emitted only after the route-specific remote cleanup has
/// finished; a failed disposition still preserves the resolved owner or
/// participant route for durable Parent-facing status.
public struct ProfileErasureTransportDisposition: Equatable, Hashable, Sendable {
    public let change: FamilySyncChangeAcknowledgement
    public let route: ProfileErasureRoute
    public let outcome: ProfileErasureTransportOutcome

    public init(
        change: FamilySyncChangeAcknowledgement,
        route: ProfileErasureRoute,
        outcome: ProfileErasureTransportOutcome
    ) {
        self.change = change
        self.route = route
        self.outcome = outcome
    }
}

public struct ProfileErasureTransportReceipt: Equatable, Hashable, Sendable {
    public let acknowledgement: FamilySyncChangeAcknowledgement
    public let route: ProfileErasureRoute

    public init(
        acknowledgement: FamilySyncChangeAcknowledgement,
        route: ProfileErasureRoute
    ) {
        self.acknowledgement = acknowledgement
        self.route = route
    }
}

public struct FamilySyncTransportFailure: Equatable, Sendable {
    public let key: FamilySyncChangeKey?
    public let category: FamilySyncPrivacySafeErrorCategory
    public let retryAfter: TimeInterval?

    public init(
        key: FamilySyncChangeKey?,
        category: FamilySyncPrivacySafeErrorCategory,
        retryAfter: TimeInterval? = nil
    ) {
        self.key = key
        self.category = category
        self.retryAfter = retryAfter
    }
}

public enum FamilySyncAccountChange: Equatable, Sendable {
    case signedIn
    case signedOut
    case switchedAccounts
}

public struct FamilySyncTransportResult: Sendable {
    public let records: [FamilySyncRecord]
    public let deletions: [FamilySyncRemoteDeletion]
    public let acknowledged: Set<FamilySyncChangeAcknowledgement>
    public let failures: [FamilySyncTransportFailure]
    public let accountChange: FamilySyncAccountChange?
    public let quarantinedRecordCount: Int
    public let receiptIDs: Set<UUID>
    public let receipts: [FamilySyncFetchedReceipt]
    public let profileErasureDispositions: [ProfileErasureTransportDisposition]
    /// `false` means the transport replayed its durable local inbox without
    /// contacting CloudKit. The coordinator must apply and acknowledge those
    /// receipts, then fetch again before it is safe to upload local changes.
    public let reachedServerHead: Bool
    public let replayedDurableInbox: Bool
    /// A send encountered a mutable `serverRecordChanged` and durably staged
    /// the server version. The coordinator must fetch/apply/ACK it before
    /// deciding whether the local operation is still a winner and retryable.
    public let requiresFetchPass: Bool

    public init(
        records: [FamilySyncRecord] = [],
        deletions: [FamilySyncRemoteDeletion] = [],
        acknowledged: Set<FamilySyncChangeAcknowledgement> = [],
        failures: [FamilySyncTransportFailure] = [],
        accountChange: FamilySyncAccountChange? = nil,
        quarantinedRecordCount: Int = 0,
        receiptIDs: Set<UUID> = [],
        receipts: [FamilySyncFetchedReceipt] = [],
        profileErasureDispositions: [ProfileErasureTransportDisposition] = [],
        reachedServerHead: Bool = true,
        replayedDurableInbox: Bool = false,
        requiresFetchPass: Bool = false
    ) {
        self.records = records
        self.deletions = deletions
        self.acknowledged = acknowledged
        self.failures = failures
        self.accountChange = accountChange
        self.quarantinedRecordCount = quarantinedRecordCount
        self.receipts = receipts
        self.profileErasureDispositions = profileErasureDispositions
        self.receiptIDs = receiptIDs.union(receipts.map(\.id))
        self.reachedServerHead = reachedServerHead
        self.replayedDurableInbox = replayedDurableInbox
        self.requiresFetchPass = requiresFetchPass
    }

    public var profileErasureReceipts: [ProfileErasureTransportReceipt] {
        profileErasureDispositions.compactMap { disposition in
            guard disposition.outcome == .completed else { return nil }
            return ProfileErasureTransportReceipt(
                acknowledgement: disposition.change,
                route: disposition.route
            )
        }
    }
}

/// Content-only compare token used by the local-first coordinator. Logical
/// revisions are journal metadata and are intentionally excluded: this token
/// answers only whether repository-owned bytes changed after the fetch began.
public struct FamilySyncRecordSetFingerprint: Hashable, Sendable {
    public let value: String

    public init(records: [FamilySyncRecord]) {
        var bytes = Data()
        for record in records.sorted(by: Self.order) {
            bytes.append(contentsOf: record.profileID.description.utf8)
            bytes.append(0)
            bytes.append(contentsOf: record.recordName.utf8)
            bytes.append(0)
            bytes.append(contentsOf: record.kind.rawValue.utf8)
            bytes.append(0)
            bytes.append(contentsOf: record.payloadChecksum.utf8)
            bytes.append(record.isDeleted ? 1 : 0)
        }
        value = FamilySyncRecord.checksum(for: bytes)
    }

    private static func order(
        _ lhs: FamilySyncRecord,
        _ rhs: FamilySyncRecord
    ) -> Bool {
        if lhs.profileID != rhs.profileID {
            return lhs.profileID.description < rhs.profileID.description
        }
        if lhs.recordName != rhs.recordName {
            return lhs.recordName < rhs.recordName
        }
        return lhs.kind.rawValue < rhs.kind.rawValue
    }
}

public protocol FamilySyncTransport: Sendable {
    var capability: FamilySyncCapability { get }

    func availability() async -> FamilySyncAvailability

    func prepareProfileZone(_ profileID: ProfileID) async throws

    func fetchRecords(for profileID: ProfileID) async throws -> [FamilySyncRecord]

    func push(_ records: [FamilySyncRecord], for profileID: ProfileID) async throws

    func exchange(_ batch: FamilySyncTransportBatch) async throws -> FamilySyncTransportResult

    func fetchChanges(
        for profileIDs: [ProfileID]
    ) async throws -> FamilySyncTransportResult

    /// Supplies local terminal identities before route preparation. A Cloud
    /// transport must not create/recreate a payload zone for these Profiles;
    /// it may only reconcile the privacy-minimal deletion ledger.
    func fetchChanges(
        for profileIDs: [ProfileID],
        terminalProfileIDs: Set<ProfileID>
    ) async throws -> FamilySyncTransportResult

    func sendChanges(
        _ changes: [FamilySyncPendingOperation]
    ) async throws -> FamilySyncTransportResult

    func acknowledgeFetchedChanges(receiptIDs: Set<UUID>) async throws

    func quarantineFetchedChanges(
        receiptIDs: Set<UUID>,
        category: FamilySyncPrivacySafeErrorCategory
    ) async throws

    /// Confirms the currently signed-in CloudKit account and reports whether
    /// it differs from the account generation previously authorized by the
    /// parent. Coordinators use this to invalidate acknowledgements that must
    /// never cross account boundaries.
    func confirmCurrentAccount() async throws -> FamilySyncAccountChange?

    func suspend() async

    func createShare(for profileID: ProfileID) async throws -> URL

    func acceptShare(at url: URL) async throws -> ProfileID
}

extension FamilySyncTransport {
    public func confirmCurrentAccount() async throws -> FamilySyncAccountChange? {
        nil
    }

    public func suspend() async {}

    public func fetchChanges(
        for profileIDs: [ProfileID]
    ) async throws -> FamilySyncTransportResult {
        var records: [FamilySyncRecord] = []
        for profileID in profileIDs {
            records += try await fetchRecords(for: profileID)
        }
        return FamilySyncTransportResult(records: records)
    }

    public func fetchChanges(
        for profileIDs: [ProfileID],
        terminalProfileIDs: Set<ProfileID>
    ) async throws -> FamilySyncTransportResult {
        _ = terminalProfileIDs
        return try await fetchChanges(for: profileIDs)
    }

    public func sendChanges(
        _ changes: [FamilySyncPendingOperation]
    ) async throws -> FamilySyncTransportResult {
        var acknowledged: Set<FamilySyncChangeAcknowledgement> = []
        var failures: [FamilySyncTransportFailure] = []
        for profileID in Set(changes.map { $0.key.profileID }) {
            let saves = changes.compactMap { operation -> FamilySyncRecord? in
                guard case .save(let record) = operation, record.profileID == profileID else {
                    return nil
                }
                return record
            }
            if !saves.isEmpty {
                try await push(saves, for: profileID)
                for operation in changes where operation.key.profileID == profileID {
                    if case .save = operation {
                        acknowledged.insert(
                            FamilySyncChangeAcknowledgement(operation: operation)
                        )
                    }
                }
            }
            for operation in changes where operation.key.profileID == profileID {
                if case .delete = operation {
                    failures.append(
                        FamilySyncTransportFailure(
                            key: operation.key,
                            category: .unknown
                        )
                    )
                }
            }
        }
        return FamilySyncTransportResult(
            acknowledged: acknowledged,
            failures: failures
        )
    }

    public func acknowledgeFetchedChanges(receiptIDs: Set<UUID>) async throws {
        _ = receiptIDs
    }

    public func quarantineFetchedChanges(
        receiptIDs: Set<UUID>,
        category: FamilySyncPrivacySafeErrorCategory
    ) async throws {
        _ = receiptIDs
        _ = category
        throw FamilySyncTransportContractError.quarantineUnsupported
    }

    public func exchange(
        _ batch: FamilySyncTransportBatch
    ) async throws -> FamilySyncTransportResult {
        let fetched = try await fetchChanges(for: batch.profileIDs)
        if !fetched.records.isEmpty || !fetched.deletions.isEmpty
            || fetched.accountChange != nil || !fetched.receiptIDs.isEmpty
            || !fetched.failures.isEmpty || fetched.quarantinedRecordCount > 0
        {
            return fetched
        }
        return try await sendChanges(batch.changes)
    }
}

public enum FamilySyncTransportContractError: Error, Equatable, Sendable {
    case quarantineUnsupported
    case corruptState
}

public protocol FamilySyncCoordinating: Sendable {
    func isEnabled() async -> Bool

    func setEnabled(_ isEnabled: Bool) async throws -> FamilySyncStatus

    func synchronize() async -> FamilySyncStatus

    func status() async -> FamilySyncStatus

    /// Returns privacy-minimal Profile-erasure evidence for Parent UI. A
    /// corrupt or unreadable lifecycle must throw so callers never mistake an
    /// unavailable status for an empty history.
    func profileErasureLifecycles() async throws -> [ProfileErasureLifecycle]

    func createShare(for profileID: ProfileID) async throws -> URL

    func acceptShare(at url: URL) async throws
}

extension FamilySyncCoordinating {
    public func profileErasureLifecycles() async throws
        -> [ProfileErasureLifecycle]
    {
        []
    }
}

public enum FamilySyncConflictResolver {
    /// Mutable records converge by logical revision. A Profile deletion is
    /// terminal; clock timestamps are consulted only for legacy revision-zero
    /// records produced before the versioned envelope existed.
    public static func resolved(
        local: FamilySyncRecord?,
        remote: FamilySyncRecord?
    ) -> FamilySyncRecord? {
        guard let local else { return remote }
        guard let remote else { return local }

        if local.kind == .profileDeletion, local.isDeleted { return local }
        if remote.kind == .profileDeletion, remote.isDeleted { return remote }
        if local.logicalRevision.counter == 0, remote.logicalRevision.counter == 0,
            local.updatedAt != remote.updatedAt
        {
            return local.updatedAt > remote.updatedAt ? local : remote
        }
        if local.logicalRevision != remote.logicalRevision {
            return local.logicalRevision > remote.logicalRevision ? local : remote
        }
        if local.isDeleted != remote.isDeleted {
            return local.isDeleted ? local : remote
        }
        if local.logicalRevision == remote.logicalRevision,
            local.payloadChecksum != remote.payloadChecksum
        {
            return local
        }
        if local.deviceID != remote.deviceID {
            return local.deviceID > remote.deviceID ? local : remote
        }
        return local.payload.lexicographicallyPrecedes(remote.payload) ? remote : local
    }
}
