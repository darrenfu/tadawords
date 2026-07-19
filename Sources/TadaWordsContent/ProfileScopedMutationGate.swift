import Foundation
import TadaWordsDomain

/// A process-local profile mutex shared by every production JSON repository
/// and the remote apply adapter. It closes the compare/apply race without
/// making child-facing writes wait on the network: CloudKit is fetched before
/// this lease is acquired, and the lease covers local file commits only.
public actor ProfileScopedMutationGate {
    private var heldProfiles = Set<ProfileID>()
    private var waiters: [ProfileID: [CheckedContinuation<Void, Never>]] = [:]

    public init() {}

    public func acquire(_ profileID: ProfileID) async {
        guard heldProfiles.contains(profileID) else {
            heldProfiles.insert(profileID)
            return
        }
        await withCheckedContinuation { continuation in
            waiters[profileID, default: []].append(continuation)
        }
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

/// Repository calls made by the remote store inherit this TaskLocal marker and
/// do not reacquire the lease already held by `applyIfUnchanged`.
enum ProfileScopedMutationLeaseContext {
    @TaskLocal static var profileID: ProfileID?
}
