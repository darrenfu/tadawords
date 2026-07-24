import Foundation
import TadaWordsDomain

/// A process-local profile mutex shared by every production JSON repository
/// and the remote apply adapter. It closes the compare/apply race without
/// making child-facing writes wait on the network: CloudKit is fetched before
/// this lease is acquired, and the lease covers local file commits only.
public actor ProfileScopedMutationGate {
    private var heldProfiles = Set<ProfileID>()
    private var terminalProfiles = Set<ProfileID>()
    private var recoveryTransactions: [ProfileID: UUID] = [:]
    private var holdsAllProfiles = false
    private var waiters: [Waiter] = []

    private struct Waiter {
        let profileID: ProfileID?
        let continuation: CheckedContinuation<Void, Never>
    }

    public init() {}

    public func acquire(
        _ profileID: ProfileID,
        allowingTerminal: Bool = false,
        allowingRecovery: Bool = false
    ) async throws {
        if canAcquire(profileID), waiters.isEmpty {
            heldProfiles.insert(profileID)
        } else {
            await withCheckedContinuation { continuation in
                waiters.append(
                    Waiter(
                        profileID: profileID,
                        continuation: continuation
                    )
                )
            }
        }
        guard allowingTerminal || !terminalProfiles.contains(profileID) else {
            release(profileID)
            throw ProfileScopedMutationGateError.terminalProfile(profileID)
        }
        guard allowingRecovery || recoveryTransactions[profileID] == nil else {
            release(profileID)
            throw ProfileScopedMutationGateError.recoveryRequired(profileID)
        }
    }

    /// Pins a compound all-Profile read to one committed process generation.
    /// Profile-scoped writers wait until the snapshot finishes, and the
    /// snapshot fails closed if any accepted remote apply needs exact replay.
    public func acquireAll(allowingRecovery: Bool = false) async throws {
        if canAcquireAll, waiters.isEmpty {
            holdsAllProfiles = true
        } else {
            await withCheckedContinuation { continuation in
                waiters.append(
                    Waiter(
                        profileID: nil,
                        continuation: continuation
                    )
                )
            }
        }
        guard allowingRecovery || recoveryTransactions.isEmpty else {
            let profileID = recoveryTransactions.keys.sorted {
                $0.description < $1.description
            }[0]
            releaseAll()
            throw ProfileScopedMutationGateError.recoveryRequired(profileID)
        }
    }

    /// Permanently closes ordinary mutation admission for a deleted Profile.
    /// Callers persist the deletion tombstone before sealing, while still
    /// holding the Profile lease. Bootstrap reconstructs this process-local
    /// fence from durable tombstones before repository recovery starts.
    public func seal(_ profileID: ProfileID) {
        terminalProfiles.insert(profileID)
    }

    public func isTerminal(_ profileID: ProfileID) -> Bool {
        terminalProfiles.contains(profileID)
    }

    /// Closes ordinary reads and local writes after a partial accepted apply.
    /// The durable transaction repository remains the restart authority; this
    /// process-local state only prevents exposing its incomplete generation.
    public func requireRecovery(
        _ profileID: ProfileID,
        transactionID: UUID
    ) {
        recoveryTransactions[profileID] = transactionID
    }

    public func clearRecovery(
        _ profileID: ProfileID,
        transactionID: UUID
    ) {
        guard recoveryTransactions[profileID] == transactionID else { return }
        recoveryTransactions.removeValue(forKey: profileID)
    }

    public func recoveryTransactionID(for profileID: ProfileID) -> UUID? {
        recoveryTransactions[profileID]
    }

    public func release(_ profileID: ProfileID) {
        heldProfiles.remove(profileID)
        resumeNextWaiterIfPossible()
    }

    public func releaseAll() {
        holdsAllProfiles = false
        resumeNextWaiterIfPossible()
    }

    private var canAcquireAll: Bool {
        !holdsAllProfiles && heldProfiles.isEmpty
    }

    private func canAcquire(_ profileID: ProfileID) -> Bool {
        !holdsAllProfiles && !heldProfiles.contains(profileID)
    }

    private func resumeNextWaiterIfPossible() {
        guard let waiter = waiters.first else { return }
        if let profileID = waiter.profileID {
            guard canAcquire(profileID) else { return }
            heldProfiles.insert(profileID)
        } else {
            guard canAcquireAll else { return }
            holdsAllProfiles = true
        }
        waiters.removeFirst()
        waiter.continuation.resume()
    }
}

public enum ProfileScopedMutationGateError: Error, Equatable, Sendable {
    case terminalProfile(ProfileID)
    case recoveryRequired(ProfileID)
}

/// Repository calls made by the remote store inherit this TaskLocal marker and
/// do not reacquire the lease already held by `applyIfUnchanged`.
enum ProfileScopedMutationLeaseContext {
    @TaskLocal static var profileID: ProfileID?
    @TaskLocal static var holdsAllProfiles = false
}

/// Runs a complete Profile-scoped transaction under the same lease used by
/// local repositories and Family Sync apply. Nested repository calls inherit
/// the TaskLocal marker, so they do not deadlock by reacquiring the lease.
public func withProfileScopedMutationLease<T>(
    _ mutationGate: ProfileScopedMutationGate?,
    for profileID: ProfileID,
    allowingTerminal: Bool = false,
    allowingRecovery: Bool = false,
    isolation: isolated (any Actor) = #isolation,
    operation: () async throws -> T
) async throws -> T {
    _ = isolation
    guard let mutationGate,
        !ProfileScopedMutationLeaseContext.holdsAllProfiles,
        ProfileScopedMutationLeaseContext.profileID != profileID
    else {
        return try await operation()
    }

    try await mutationGate.acquire(
        profileID,
        allowingTerminal: allowingTerminal,
        allowingRecovery: allowingRecovery
    )
    do {
        let result = try await ProfileScopedMutationLeaseContext.$profileID
            .withValue(profileID) {
                try await operation()
            }
        await mutationGate.release(profileID)
        return result
    } catch {
        await mutationGate.release(profileID)
        throw error
    }
}

/// Runs a compound cross-Profile read against one committed process
/// generation. Nested repository reads inherit the TaskLocal marker and avoid
/// reacquiring the global lease.
public func withAllProfilesCommittedRead<T>(
    _ mutationGate: ProfileScopedMutationGate?,
    allowingRecovery: Bool = false,
    isolation: isolated (any Actor) = #isolation,
    operation: () async throws -> T
) async throws -> T {
    _ = isolation
    guard let mutationGate,
        !ProfileScopedMutationLeaseContext.holdsAllProfiles,
        ProfileScopedMutationLeaseContext.profileID == nil
    else {
        return try await operation()
    }

    try await mutationGate.acquireAll(allowingRecovery: allowingRecovery)
    do {
        let result =
            try await ProfileScopedMutationLeaseContext
            .$holdsAllProfiles.withValue(true) {
                try await operation()
            }
        await mutationGate.releaseAll()
        return result
    } catch {
        await mutationGate.releaseAll()
        throw error
    }
}
