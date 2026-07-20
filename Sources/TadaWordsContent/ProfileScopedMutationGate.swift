import Foundation
import TadaWordsDomain

/// A process-local profile mutex shared by every production JSON repository
/// and the remote apply adapter. It closes the compare/apply race without
/// making child-facing writes wait on the network: CloudKit is fetched before
/// this lease is acquired, and the lease covers local file commits only.
public actor ProfileScopedMutationGate {
    private var heldProfiles = Set<ProfileID>()
    private var terminalProfiles = Set<ProfileID>()
    private var waiters: [ProfileID: [CheckedContinuation<Void, Never>]] = [:]

    public init() {}

    public func acquire(
        _ profileID: ProfileID,
        allowingTerminal: Bool = false
    ) async throws {
        guard heldProfiles.contains(profileID) else {
            guard allowingTerminal || !terminalProfiles.contains(profileID) else {
                throw ProfileScopedMutationGateError.terminalProfile(profileID)
            }
            heldProfiles.insert(profileID)
            return
        }
        await withCheckedContinuation { continuation in
            waiters[profileID, default: []].append(continuation)
        }
        guard allowingTerminal || !terminalProfiles.contains(profileID) else {
            // Ownership was transferred directly to this waiter. Pass it on
            // before rejecting the mutation so a terminal-aware cleanup or
            // sync reader behind it cannot deadlock.
            release(profileID)
            throw ProfileScopedMutationGateError.terminalProfile(profileID)
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

    public func release(_ profileID: ProfileID) {
        guard var profileWaiters = waiters[profileID], !profileWaiters.isEmpty else {
            heldProfiles.remove(profileID)
            waiters.removeValue(forKey: profileID)
            return
        }
        let next = profileWaiters.removeFirst()
        if profileWaiters.isEmpty {
            waiters.removeValue(forKey: profileID)
        } else {
            waiters[profileID] = profileWaiters
        }
        // Ownership transfers directly; the profile remains in heldProfiles.
        next.resume()
    }
}

public enum ProfileScopedMutationGateError: Error, Equatable, Sendable {
    case terminalProfile(ProfileID)
}

/// Repository calls made by the remote store inherit this TaskLocal marker and
/// do not reacquire the lease already held by `applyIfUnchanged`.
enum ProfileScopedMutationLeaseContext {
    @TaskLocal static var profileID: ProfileID?
}

/// Runs a complete Profile-scoped transaction under the same lease used by
/// local repositories and Family Sync apply. Nested repository calls inherit
/// the TaskLocal marker, so they do not deadlock by reacquiring the lease.
public func withProfileScopedMutationLease<T>(
    _ mutationGate: ProfileScopedMutationGate?,
    for profileID: ProfileID,
    allowingTerminal: Bool = false,
    isolation: isolated (any Actor) = #isolation,
    operation: () async throws -> T
) async throws -> T {
    _ = isolation
    guard let mutationGate,
        ProfileScopedMutationLeaseContext.profileID != profileID
    else {
        return try await operation()
    }

    try await mutationGate.acquire(
        profileID,
        allowingTerminal: allowingTerminal
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
