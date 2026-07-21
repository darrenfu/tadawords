import Foundation
import TadaWordsContent
import TadaWordsDomain
import TadaWordsGuardianFeatures

enum FirstRunOnboardingPurpose: String, Codable, Equatable, Sendable {
    case fullSetup
    case consentRefresh
}

enum FirstRunProfileIntent: String, Codable, Equatable, Sendable {
    case createNew
    case discoverExisting
}

enum FirstRunDiscoveryResetPhase: String, Codable, Equatable, Sendable {
    /// Canonical repositories and both sync durability layers must be purged
    /// before Create or Adopt may mutate onboarding state.
    case required

    /// Account-bound cache is empty and sync is durably disabled. Creating a
    /// new child is safe, but adopting a remote Profile is not yet allowed.
    case cacheCleared

    /// The current-account confirmation/full fetch has started. Any failure
    /// or crash must return through the destructive reset before retrying.
    case fetchingCurrentAccount
}

struct FirstRunOnboardingState: Codable, Equatable, Sendable {
    static let currentSchemaVersion = 3

    enum Status: String, Codable, Sendable {
        case pending
        case completed
    }

    let schemaVersion: Int
    let status: Status
    let startedAt: Date
    let completedAt: Date?
    let profileID: ProfileID?
    let consentVersion: Int?
    let consentedAt: Date?
    let purpose: FirstRunOnboardingPurpose?
    let profileIntent: FirstRunProfileIntent?
    let pendingCreatedProfileID: ProfileID?
    let discoveryResetPhase: FirstRunDiscoveryResetPhase?
    /// True only when Create was started from a successful, account-bound Find
    /// cache. It preserves the cleanup provenance while `profileIntent`
    /// becomes `.createNew` for interruption-safe retry.
    let creationOriginatedFromDiscovery: Bool?

    init(
        schemaVersion: Int,
        status: Status,
        startedAt: Date,
        completedAt: Date?,
        profileID: ProfileID?,
        consentVersion: Int?,
        consentedAt: Date?,
        purpose: FirstRunOnboardingPurpose?,
        profileIntent: FirstRunProfileIntent? = nil,
        pendingCreatedProfileID: ProfileID? = nil,
        discoveryResetPhase: FirstRunDiscoveryResetPhase? = nil,
        creationOriginatedFromDiscovery: Bool? = nil
    ) {
        self.schemaVersion = schemaVersion
        self.status = status
        self.startedAt = startedAt
        self.completedAt = completedAt
        self.profileID = profileID
        self.consentVersion = consentVersion
        self.consentedAt = consentedAt
        self.purpose = purpose
        self.profileIntent = profileIntent
        self.pendingCreatedProfileID = pendingCreatedProfileID
        self.discoveryResetPhase = discoveryResetPhase
        self.creationOriginatedFromDiscovery = creationOriginatedFromDiscovery
    }

    var hasAccountBoundDiscoveryProvenance: Bool {
        profileIntent == .discoverExisting
            || (profileIntent == .createNew
                && creationOriginatedFromDiscovery == true)
    }

    static func pending(
        startedAt: Date,
        purpose: FirstRunOnboardingPurpose
    ) -> FirstRunOnboardingState {
        FirstRunOnboardingState(
            schemaVersion: Self.currentSchemaVersion,
            status: .pending,
            startedAt: startedAt,
            completedAt: nil,
            profileID: nil,
            consentVersion: nil,
            consentedAt: nil,
            purpose: purpose,
            profileIntent: nil,
            pendingCreatedProfileID: nil,
            discoveryResetPhase: nil
        )
    }

    func completed(
        profileID: ProfileID,
        completedAt: Date,
        consentVersion: Int? = nil
    ) -> FirstRunOnboardingState {
        FirstRunOnboardingState(
            schemaVersion: schemaVersion,
            status: .completed,
            startedAt: startedAt,
            completedAt: completedAt,
            profileID: profileID,
            consentVersion: consentVersion,
            consentedAt: consentVersion == nil ? nil : completedAt,
            purpose: purpose,
            profileIntent: nil,
            pendingCreatedProfileID: nil,
            discoveryResetPhase: nil
        )
    }

    func recordingDiscoveryIntent() -> FirstRunOnboardingState {
        FirstRunOnboardingState(
            schemaVersion: Self.currentSchemaVersion,
            status: status,
            startedAt: startedAt,
            completedAt: completedAt,
            profileID: profileID,
            consentVersion: consentVersion,
            consentedAt: consentedAt,
            purpose: purpose,
            profileIntent: .discoverExisting,
            // A Create -> Find transition is a durable containment
            // transaction. Keep the exact reserved identity until its local
            // Profile/defaults/session pointer are verified absent; a crash
            // can then resume cleanup without guessing or touching another
            // child.
            pendingCreatedProfileID: pendingCreatedProfileID,
            discoveryResetPhase: purpose == .fullSetup ? .required : nil,
            creationOriginatedFromDiscovery:
                creationOriginatedFromDiscovery
        )
    }

    func resolvingPendingProfileCreationForDiscovery(
        profileID: ProfileID
    ) -> FirstRunOnboardingState {
        FirstRunOnboardingState(
            schemaVersion: Self.currentSchemaVersion,
            status: status,
            startedAt: startedAt,
            completedAt: completedAt,
            profileID: self.profileID,
            consentVersion: consentVersion,
            consentedAt: consentedAt,
            purpose: purpose,
            profileIntent: .discoverExisting,
            pendingCreatedProfileID:
                pendingCreatedProfileID == profileID
                ? nil
                : pendingCreatedProfileID,
            discoveryResetPhase: discoveryResetPhase,
            creationOriginatedFromDiscovery:
                creationOriginatedFromDiscovery
        )
    }

    func markingDiscoveryCacheCleared() -> FirstRunOnboardingState {
        FirstRunOnboardingState(
            schemaVersion: Self.currentSchemaVersion,
            status: status,
            startedAt: startedAt,
            completedAt: completedAt,
            profileID: profileID,
            consentVersion: consentVersion,
            consentedAt: consentedAt,
            purpose: purpose,
            profileIntent: profileIntent,
            pendingCreatedProfileID: pendingCreatedProfileID,
            discoveryResetPhase: .cacheCleared,
            creationOriginatedFromDiscovery: nil
        )
    }

    func beginningAccountBoundDiscovery() -> FirstRunOnboardingState {
        FirstRunOnboardingState(
            schemaVersion: Self.currentSchemaVersion,
            status: status,
            startedAt: startedAt,
            completedAt: completedAt,
            profileID: profileID,
            consentVersion: consentVersion,
            consentedAt: consentedAt,
            purpose: purpose,
            profileIntent: profileIntent,
            pendingCreatedProfileID: pendingCreatedProfileID,
            discoveryResetPhase: .fetchingCurrentAccount,
            creationOriginatedFromDiscovery:
                creationOriginatedFromDiscovery
        )
    }

    func completingProfileDiscovery() -> FirstRunOnboardingState {
        FirstRunOnboardingState(
            schemaVersion: Self.currentSchemaVersion,
            status: status,
            startedAt: startedAt,
            completedAt: completedAt,
            profileID: profileID,
            consentVersion: consentVersion,
            consentedAt: consentedAt,
            purpose: purpose,
            profileIntent: profileIntent,
            pendingCreatedProfileID: pendingCreatedProfileID,
            discoveryResetPhase: nil,
            creationOriginatedFromDiscovery:
                creationOriginatedFromDiscovery
        )
    }

    func recordingProfileCreation(
        profileID: ProfileID
    ) -> FirstRunOnboardingState {
        FirstRunOnboardingState(
            schemaVersion: Self.currentSchemaVersion,
            status: status,
            startedAt: startedAt,
            completedAt: completedAt,
            profileID: profileID,
            consentVersion: consentVersion,
            consentedAt: consentedAt,
            purpose: purpose,
            profileIntent: .createNew,
            pendingCreatedProfileID: profileID,
            discoveryResetPhase: nil,
            creationOriginatedFromDiscovery:
                creationOriginatedFromDiscovery == true
                || (profileIntent == .discoverExisting
                    && discoveryResetPhase == nil)
        )
    }

    func updatingPurpose(
        _ purpose: FirstRunOnboardingPurpose
    ) -> FirstRunOnboardingState {
        let resetPhase: FirstRunDiscoveryResetPhase? =
            purpose == .fullSetup && hasAccountBoundDiscoveryProvenance
            ? discoveryResetPhase ?? .required
            : nil
        return FirstRunOnboardingState(
            schemaVersion: Self.currentSchemaVersion,
            status: status,
            startedAt: startedAt,
            completedAt: completedAt,
            profileID: profileID,
            consentVersion: consentVersion,
            consentedAt: consentedAt,
            purpose: purpose,
            profileIntent: profileIntent,
            pendingCreatedProfileID: pendingCreatedProfileID,
            discoveryResetPhase: resetPhase,
            creationOriginatedFromDiscovery:
                creationOriginatedFromDiscovery
        )
    }

    func requiringDiscoveryResetForMigration() -> FirstRunOnboardingState {
        FirstRunOnboardingState(
            schemaVersion: Self.currentSchemaVersion,
            status: status,
            startedAt: startedAt,
            completedAt: completedAt,
            profileID: profileID,
            consentVersion: consentVersion,
            consentedAt: consentedAt,
            purpose: purpose,
            profileIntent: profileIntent,
            pendingCreatedProfileID: pendingCreatedProfileID,
            discoveryResetPhase: .required,
            creationOriginatedFromDiscovery:
                creationOriginatedFromDiscovery
        )
    }
}

enum FirstRunOnboardingRepositoryError: Error, Equatable, Sendable {
    case onboardingAlreadyCompleted
    case pendingProfileCreationChanged
    case discoveryResetRequired
    case unsupportedSchemaVersion(found: Int, supported: Int)
}

/// Process-local admission fence layered over the durable onboarding state.
///
/// Returning to the foreground can expose a different signed-in iCloud
/// account before the asynchronous durable reset write starts. Closing this
/// gate is synchronous, so a stale Find result cannot be adopted (or replaced
/// by Create) during that window. A generation prevents an older revalidation
/// task from reopening the gate after a newer foreground transition.
final class FirstRunDiscoveryAdmissionGate: @unchecked Sendable {
    struct Generation: Equatable, Sendable {
        fileprivate let value: UInt64
    }

    private let lock = NSLock()
    private var generation: UInt64 = 0
    private var isClosed: Bool

    init(initiallyClosed: Bool = false) {
        isClosed = initiallyClosed
    }

    @discardableResult
    func closeForAccountRevalidation() -> Generation {
        lock.lock()
        defer { lock.unlock() }
        generation &+= 1
        isClosed = true
        return Generation(value: generation)
    }

    func currentGeneration() -> Generation {
        lock.lock()
        defer { lock.unlock() }
        return Generation(value: generation)
    }

    @discardableResult
    func reopen(ifCurrent candidate: Generation) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        guard candidate.value == generation else { return false }
        isClosed = false
        return true
    }

    func acquireAdmissionLease() throws -> Generation {
        lock.lock()
        defer { lock.unlock() }
        guard !isClosed else {
            throw FirstRunOnboardingRepositoryError.discoveryResetRequired
        }
        return Generation(value: generation)
    }

    func requireAdmissionAllowed() throws {
        _ = try acquireAdmissionLease()
    }

    /// Executes the final synchronous completion-marker write under the same
    /// lock used by `closeForAccountRevalidation`. This is the linearization
    /// point: either the old admission commits first, or foreground revocation
    /// wins and the stale operation cannot complete.
    func commit<T>(
        ifCurrent candidate: Generation,
        _ operation: () throws -> T
    ) throws -> T {
        lock.lock()
        defer { lock.unlock() }
        guard !isClosed, candidate.value == generation else {
            throw FirstRunOnboardingRepositoryError.discoveryResetRequired
        }
        return try operation()
    }

    func admissionIsClosed() -> Bool {
        lock.lock()
        defer { lock.unlock() }
        return isClosed
    }
}

enum FirstRunDiscoveryAdmissionRevalidator {
    /// Completes the asynchronous half of a foreground fence. The caller must
    /// close the gate synchronously before starting this operation.
    ///
    /// Any repository or quiescence failure deliberately leaves the gate
    /// closed. A later Find or foreground retry is the only path that may
    /// reopen admission after the underlying failure recovers.
    @discardableResult
    static func revalidate(
        generation: FirstRunDiscoveryAdmissionGate.Generation,
        gate: FirstRunDiscoveryAdmissionGate,
        onboardingRepository: any FirstRunOnboardingPersisting,
        familySyncCoordinator: any FamilySyncCoordinating
    ) async -> Bool {
        do {
            let didRearm =
                try await onboardingRepository.rearmPendingDiscoveryReset()
            let discoveryIsPending: Bool
            if didRearm {
                discoveryIsPending = true
            } else {
                discoveryIsPending =
                    try await onboardingRepository.hasPendingDiscoveryIntent()
            }
            if discoveryIsPending {
                _ = try await familySyncCoordinator.disableAndAwaitQuiescence()
            }
            return gate.reopen(ifCurrent: generation)
        } catch {
            return false
        }
    }
}

protocol FirstRunOnboardingPersisting: Sendable {
    func markDiscoveryIntent() async throws

    /// Durably fences an unfinished local creation from discovery/sync and
    /// returns the one exact identity whose local staging must be contained.
    func prepareForProfileDiscovery() async throws -> ProfileID?

    /// True only while the app is in the never-admitted full-setup flow.
    /// Consent refresh owns real child data and must never use discovery-cache
    /// erasure, even if a stale UI action asks to Find.
    func canDiscardUnadoptedDiscoveryState() async throws -> Bool

    /// Re-arms a successful-but-unadopted Find when the app returns to the
    /// foreground, because the signed-in iCloud account may have changed.
    @discardableResult
    func rearmPendingDiscoveryReset() async throws -> Bool

    /// Distinguishes an already-fenced discovery from ordinary full setup or
    /// consent refresh. Foreground revalidation uses this to await sync
    /// quiescence even when another task already persisted the reset phase.
    func hasPendingDiscoveryIntent() async throws -> Bool

    /// Clears the durable reset gate only after the caller verifies canonical
    /// and sync-owned nonterminal state are absent. This permits offline
    /// Create but still blocks adoption.
    func finishDiscoveryReset() async throws

    /// Moves the empty-cache fence into account-confirmation/full-fetch mode.
    func beginAccountBoundDiscovery() async throws

    /// Clears the adoption gate only after a successful current-account fetch.
    func finishProfileDiscovery() async throws

    /// Fail-closed admission gate for adopting/confirming remote Profiles.
    func requireDiscoveryResetCompleted() async throws

    /// Allows Create only when no account-bound bytes can survive: before any
    /// discovery or after the cache was durably cleared under opt-out.
    func requireProfileCreationAllowed() async throws

    /// Clears the durable fence only after every local staged byte for this
    /// exact identity has been verified absent. Repeating after a crash is
    /// safe; a different identity always fails closed.
    func finishPendingProfileContainment(
        profileID: ProfileID
    ) async throws

    func beginProfileCreation(
        proposedProfileID: ProfileID?,
        startedAt: Date
    ) async throws -> ProfileID

    func markCompleted(
        profileID: ProfileID,
        completedAt: Date,
        consentVersion: Int?,
        admissionGate: FirstRunDiscoveryAdmissionGate,
        admissionLease: FirstRunDiscoveryAdmissionGate.Generation
    ) async throws
}

actor LocalFirstRunOnboardingRepository: FirstRunOnboardingPersisting {
    let snapshotURL: URL
    private let fileManager: FileManager
    private var didInspectLaunchState = false

    init(
        snapshotURL: URL,
        fileManager: FileManager = .default
    ) {
        self.snapshotURL = snapshotURL
        self.fileManager = fileManager
    }

    func state() throws -> FirstRunOnboardingState? {
        guard let data = try snapshotFile.readIfPresent() else {
            didInspectLaunchState = true
            return nil
        }
        let decoded = try JSONDecoder().decode(
            FirstRunOnboardingState.self,
            from: data
        )
        guard
            (1...FirstRunOnboardingState.currentSchemaVersion).contains(
                decoded.schemaVersion
            )
        else {
            throw FirstRunOnboardingRepositoryError.unsupportedSchemaVersion(
                found: decoded.schemaVersion,
                supported: FirstRunOnboardingState.currentSchemaVersion
            )
        }
        let isInitialRead = !didInspectLaunchState
        didInspectLaunchState = true
        guard
            decoded.schemaVersion
                < FirstRunOnboardingState.currentSchemaVersion,
            decoded.status == .pending,
            decoded.profileIntent == .discoverExisting
                || (decoded.profileIntent == .createNew
                    && decoded.pendingCreatedProfileID != nil),
            decoded.purpose != .consentRefresh
        else {
            guard
                isInitialRead,
                decoded.schemaVersion
                    == FirstRunOnboardingState.currentSchemaVersion,
                decoded.status == .pending,
                decoded.purpose == .fullSetup,
                decoded.hasAccountBoundDiscoveryProvenance,
                decoded.discoveryResetPhase == nil
            else { return decoded }
            // A nil phase means a prior Find succeeded in another process.
            // The CloudKit account can change between launches, so hide and
            // fence that cache until the parent explicitly retries Find.
            let rearmed = decoded.requiringDiscoveryResetForMigration()
            try persist(rearmed)
            return rearmed
        }
        // Schema 1/2 had no durable account-reset phase. Treat a legacy
        // pending discovery as full setup unless it explicitly says consent
        // refresh, persist the fence atomically, and only then expose it to
        // bootstrap, Create, or Adopt.
        let migrated = decoded.requiringDiscoveryResetForMigration()
        try persist(migrated)
        return migrated
    }

    func markPending(
        startedAt: Date,
        purpose: FirstRunOnboardingPurpose
    ) throws {
        let current = try state()
        if let current, current.status == .pending {
            guard current.purpose != purpose else { return }
            try persist(current.updatingPurpose(current.purpose ?? purpose))
            return
        }
        try persist(
            .pending(
                startedAt: current?.startedAt ?? startedAt,
                purpose: purpose
            )
        )
    }

    /// Repairs a still-pending flow after Family Sync changes the family shape
    /// underneath it. In particular, consent refresh cannot continue once the
    /// final Profile has been deleted on another device.
    func normalizePendingPurpose(
        _ purpose: FirstRunOnboardingPurpose
    ) throws {
        guard let current = try state(), current.status == .pending else {
            return
        }
        guard current.purpose != purpose else { return }
        try persist(current.updatingPurpose(purpose))
    }

    func markDiscoveryIntent() throws {
        _ = try prepareForProfileDiscovery()
    }

    func prepareForProfileDiscovery() throws -> ProfileID? {
        guard let current = try state(), current.status == .pending else {
            return nil
        }
        let expectedResetPhase: FirstRunDiscoveryResetPhase? =
            current.purpose == .fullSetup ? .required : nil
        if current.profileIntent != .discoverExisting
            || current.discoveryResetPhase != expectedResetPhase
        {
            try persist(current.recordingDiscoveryIntent())
        }
        return current.pendingCreatedProfileID
    }

    func canDiscardUnadoptedDiscoveryState() throws -> Bool {
        guard let current = try state() else { return false }
        return current.status == .pending
            && current.purpose == .fullSetup
            && current.profileIntent == .discoverExisting
            && current.discoveryResetPhase == .required
    }

    @discardableResult
    func rearmPendingDiscoveryReset() throws -> Bool {
        guard let current = try state(), current.status == .pending,
            current.purpose == .fullSetup,
            current.hasAccountBoundDiscoveryProvenance,
            current.discoveryResetPhase == nil
        else { return false }
        try persist(current.requiringDiscoveryResetForMigration())
        return true
    }

    func hasPendingDiscoveryIntent() throws -> Bool {
        guard let current = try state() else { return false }
        return current.status == .pending
            && current.purpose == .fullSetup
            && current.hasAccountBoundDiscoveryProvenance
    }

    func finishDiscoveryReset() throws {
        guard let current = try state(), current.status == .pending,
            current.purpose == .fullSetup,
            current.profileIntent == .discoverExisting,
            current.discoveryResetPhase == .required
        else {
            throw FirstRunOnboardingRepositoryError.discoveryResetRequired
        }
        guard current.pendingCreatedProfileID == nil else {
            throw FirstRunOnboardingRepositoryError
                .pendingProfileCreationChanged
        }
        try persist(current.markingDiscoveryCacheCleared())
    }

    func beginAccountBoundDiscovery() throws {
        guard let current = try state(), current.status == .pending,
            current.purpose == .fullSetup,
            current.profileIntent == .discoverExisting,
            current.discoveryResetPhase == .cacheCleared,
            current.pendingCreatedProfileID == nil
        else {
            throw FirstRunOnboardingRepositoryError.discoveryResetRequired
        }
        try persist(current.beginningAccountBoundDiscovery())
    }

    func finishProfileDiscovery() throws {
        guard let current = try state(), current.status == .pending,
            current.purpose == .fullSetup,
            current.profileIntent == .discoverExisting,
            current.discoveryResetPhase == .fetchingCurrentAccount,
            current.pendingCreatedProfileID == nil
        else {
            throw FirstRunOnboardingRepositoryError.discoveryResetRequired
        }
        try persist(current.completingProfileDiscovery())
    }

    func requireDiscoveryResetCompleted() throws {
        guard try state()?.discoveryResetPhase == nil else {
            throw FirstRunOnboardingRepositoryError.discoveryResetRequired
        }
    }

    func requireProfileCreationAllowed() throws {
        guard let phase = try state()?.discoveryResetPhase else { return }
        guard phase == .cacheCleared else {
            throw FirstRunOnboardingRepositoryError.discoveryResetRequired
        }
    }

    func finishPendingProfileContainment(
        profileID: ProfileID
    ) throws {
        guard let current = try state(), current.status == .pending else {
            throw FirstRunOnboardingRepositoryError
                .pendingProfileCreationChanged
        }
        guard current.profileIntent == .discoverExisting else {
            throw FirstRunOnboardingRepositoryError
                .pendingProfileCreationChanged
        }
        guard let pendingCreatedProfileID = current.pendingCreatedProfileID else {
            throw FirstRunOnboardingRepositoryError
                .pendingProfileCreationChanged
        }
        guard pendingCreatedProfileID == profileID else {
            throw FirstRunOnboardingRepositoryError
                .pendingProfileCreationChanged
        }
        try persist(
            current.resolvingPendingProfileCreationForDiscovery(
                profileID: profileID
            )
        )
    }

    /// Reserves one exact identity before settings, Profile, session, or
    /// completion writes begin. Every retry receives the same ID, including a
    /// retry in the same process after a later write fails.
    func beginProfileCreation(
        proposedProfileID: ProfileID?,
        startedAt: Date
    ) throws -> ProfileID {
        let current =
            try state()
            ?? .pending(startedAt: startedAt, purpose: .fullSetup)
        guard current.status == .pending else {
            throw FirstRunOnboardingRepositoryError.onboardingAlreadyCompleted
        }
        guard
            current.discoveryResetPhase == nil
                || current.discoveryResetPhase == .cacheCleared
        else {
            throw FirstRunOnboardingRepositoryError.discoveryResetRequired
        }
        if current.profileIntent == .createNew,
            let pendingCreatedProfileID = current.pendingCreatedProfileID
        {
            return pendingCreatedProfileID
        }
        // Moving from discovery to explicit creation must never reuse a remote
        // candidate passed by stale UI state. Device-only bootstrap may still
        // reserve its historical local seed when there was no discovery.
        let profileID =
            current.profileIntent == .discoverExisting
            ? ProfileID()
            : proposedProfileID ?? ProfileID()
        try persist(current.recordingProfileCreation(profileID: profileID))
        return profileID
    }

    func markCompleted(
        profileID: ProfileID,
        completedAt: Date,
        consentVersion: Int? = nil,
        admissionGate: FirstRunDiscoveryAdmissionGate,
        admissionLease: FirstRunDiscoveryAdmissionGate.Generation
    ) throws {
        let current =
            try state()
            ?? .pending(startedAt: completedAt, purpose: .fullSetup)
        guard current.discoveryResetPhase == nil else {
            throw FirstRunOnboardingRepositoryError.discoveryResetRequired
        }
        try admissionGate.commit(ifCurrent: admissionLease) {
            try persist(
                current.completed(
                    profileID: profileID,
                    completedAt: completedAt,
                    consentVersion: consentVersion
                )
            )
        }
    }

    private func persist(_ state: FirstRunOnboardingState) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        try snapshotFile.write(encoder.encode(state))
    }

    private var snapshotFile: AtomicSnapshotFile {
        AtomicSnapshotFile(
            snapshotURL: snapshotURL,
            fileManager: fileManager
        )
    }
}

enum FirstRunOnboardingError: Error, Equatable {
    case consentRequired
    case profileNotFound
    case emptyDisplayName
    case displayNameTooLong(maximumCharacterCount: Int)
    case invalidAge
    case unsupportedAvatar
}

enum FirstRunProfileDiscoveryError: Error, Equatable, Sendable {
    case offline
    case iCloudUnavailable
    case resetRequired
    case failed
}

/// Performs the parent-authorized first sync before any new Profile is
/// committed. Discovery imports records through the same durable transaction
/// path as ordinary Family Sync; the returned identities are the exact remote
/// UUIDs and are never coalesced by display attributes.
actor FirstRunProfileDiscoveryCoordinator {
    private let familySyncCoordinator: any FamilySyncCoordinating
    private let familySyncTransport: any FamilySyncTransport
    private let profileRepository: any KidProfileRepository
    private let practiceSettingsRepository: any PracticeSettingsRepository
    private let childSessionRepository: any ChildSessionRepository
    private let onboardingRepository: any FirstRunOnboardingPersisting
    private let profileDataEraser: any ProfileDataErasing
    private let familySyncJournalRepository: any FamilySyncJournalRepository
    private let familySyncApplyTransactionRepository: any FamilySyncApplyTransactionRepository
    private let discoveryAdmissionGate: FirstRunDiscoveryAdmissionGate
    private let discoveryAdmissionGeneration: FirstRunDiscoveryAdmissionGate.Generation

    init(
        familySyncCoordinator: any FamilySyncCoordinating,
        familySyncTransport: any FamilySyncTransport,
        profileRepository: any KidProfileRepository,
        practiceSettingsRepository: any PracticeSettingsRepository,
        childSessionRepository: any ChildSessionRepository,
        onboardingRepository: any FirstRunOnboardingPersisting,
        profileDataEraser: any ProfileDataErasing,
        familySyncJournalRepository: any FamilySyncJournalRepository,
        familySyncApplyTransactionRepository:
            any FamilySyncApplyTransactionRepository,
        discoveryAdmissionGate: FirstRunDiscoveryAdmissionGate,
        discoveryAdmissionGeneration:
            FirstRunDiscoveryAdmissionGate.Generation
    ) {
        self.familySyncCoordinator = familySyncCoordinator
        self.familySyncTransport = familySyncTransport
        self.profileRepository = profileRepository
        self.practiceSettingsRepository = practiceSettingsRepository
        self.childSessionRepository = childSessionRepository
        self.onboardingRepository = onboardingRepository
        self.profileDataEraser = profileDataEraser
        self.familySyncJournalRepository = familySyncJournalRepository
        self.familySyncApplyTransactionRepository =
            familySyncApplyTransactionRepository
        self.discoveryAdmissionGate = discoveryAdmissionGate
        self.discoveryAdmissionGeneration = discoveryAdmissionGeneration
    }

    func discoverProfiles() async throws -> [KidProfile] {
        let pendingProfileID: ProfileID?
        do {
            pendingProfileID =
                try await onboardingRepository.prepareForProfileDiscovery()
        } catch {
            throw FirstRunProfileDiscoveryError.resetRequired
        }
        let requiresAccountBoundaryCompletion: Bool
        do {
            requiresAccountBoundaryCompletion =
                try await onboardingRepository
                .canDiscardUnadoptedDiscoveryState()
            if requiresAccountBoundaryCompletion {
                // This preference write is the durable account-bound fence. A
                // crash during cleanup leaves every background/notification
                // path opted out, so account A bytes cannot replay into B.
                _ = try await familySyncCoordinator.disableAndAwaitQuiescence()
                if let pendingProfileID {
                    try await containPendingProfileCreation(
                        profileID: pendingProfileID
                    )
                }
                try await discardUnadoptedDiscoveryState()
            } else if pendingProfileID != nil {
                // A staged create may only be purged inside full setup.
                throw FirstRunProfileDiscoveryError.failed
            }
        } catch {
            throw FirstRunProfileDiscoveryError.resetRequired
        }
        switch await familySyncTransport.availability() {
        case .temporarilyUnavailable:
            throw FirstRunProfileDiscoveryError.offline
        case .noAccount, .restricted, .deviceOnly:
            throw FirstRunProfileDiscoveryError.iCloudUnavailable
        case .available:
            break
        }
        if requiresAccountBoundaryCompletion {
            do {
                try await onboardingRepository.beginAccountBoundDiscovery()
            } catch {
                throw FirstRunProfileDiscoveryError.resetRequired
            }
        }
        let status: FamilySyncStatus
        do {
            // Find is a parent-owned account boundary, not an ordinary
            // foreground refresh. Re-confirm even when durable consent is
            // already enabled so a sign-out/account switch cannot keep reading
            // the previous account's authorized engine state. Discovery cache
            // state was discarded under opt-out, so this authorized full fetch
            // is the only source allowed to repopulate canonical repositories.
            status = try await familySyncCoordinator.setEnabled(true)
        } catch {
            _ = try? await familySyncCoordinator.disableAndAwaitQuiescence()
            switch await familySyncTransport.availability() {
            case .temporarilyUnavailable:
                throw FirstRunProfileDiscoveryError.offline
            case .noAccount, .restricted, .deviceOnly:
                throw FirstRunProfileDiscoveryError.iCloudUnavailable
            case .available:
                throw FirstRunProfileDiscoveryError.failed
            }
        }

        switch status {
        case .synced:
            do {
                let profiles = try await profileRepository.profiles().sorted(
                    by: Self.order
                )
                try await requireCurrentDiscoveryGeneration()
                if requiresAccountBoundaryCompletion {
                    try await onboardingRepository.finishProfileDiscovery()
                }
                try await requireCurrentDiscoveryGeneration()
                return profiles
            } catch {
                _ =
                    try? await familySyncCoordinator
                    .disableAndAwaitQuiescence()
                throw FirstRunProfileDiscoveryError.resetRequired
            }
        case .pendingOffline:
            _ = try? await familySyncCoordinator.disableAndAwaitQuiescence()
            throw FirstRunProfileDiscoveryError.offline
        case .iCloudUnavailable, .deviceOnly, .optedOut:
            _ = try? await familySyncCoordinator.disableAndAwaitQuiescence()
            throw FirstRunProfileDiscoveryError.iCloudUnavailable
        case .idle, .syncing, .failed:
            _ = try? await familySyncCoordinator.disableAndAwaitQuiescence()
            throw FirstRunProfileDiscoveryError.failed
        }
    }

    /// A foreground transition may observe a different iCloud account after
    /// the full fetch returns but before its candidates reach SwiftUI. The
    /// process generation is therefore checked at both sides of the final
    /// onboarding-state write and once more by the application view after this
    /// actor returns. A stale Find is converted back into the durable reset
    /// phase and sync is opted out before any candidate can be selected.
    func requireCurrentDiscoveryGeneration() async throws {
        guard
            discoveryAdmissionGate.currentGeneration()
                == discoveryAdmissionGeneration
        else {
            _ = discoveryAdmissionGate.closeForAccountRevalidation()
            do {
                _ = try await onboardingRepository.prepareForProfileDiscovery()
            } catch {
                // The process gate remains closed even when durable storage is
                // temporarily unavailable. Retry must pass through Find again.
            }
            do {
                _ = try await familySyncCoordinator.disableAndAwaitQuiescence()
            } catch {
                // `setEnabled(false)` closes its actor-local consent gate before
                // awaiting persistence. A later Find/bootstrap retries the
                // durable opt-out if this write failed.
            }
            throw FirstRunProfileDiscoveryError.resetRequired
        }
    }

    private static func order(_ lhs: KidProfile, _ rhs: KidProfile) -> Bool {
        let comparison = lhs.displayName.localizedCaseInsensitiveCompare(
            rhs.displayName
        )
        if comparison != .orderedSame {
            return comparison == .orderedAscending
        }
        return lhs.id.description < rhs.id.description
    }

    private func discardUnadoptedDiscoveryState() async throws {
        // First-run has not admitted any Profile to child play. Profiles in
        // the canonical repositories are therefore a replaceable discovery
        // cache, not locally authored family state. Purge them without a
        // tombstone, then remove the matching nonterminal sync manifests and
        // committed-receipt dedupe state so the confirmed account can refetch
        // its own complete generation. Both repositories retain terminal
        // Profile-deletion authority.
        async let journalProfileIDs =
            familySyncJournalRepository.unadoptedProfileIDs()
        async let applyProfileIDs =
            familySyncApplyTransactionRepository.unadoptedProfileIDs()
        var profileIDs = Set(try await profileRepository.profiles().map(\.id))
        profileIDs.formUnion(try await journalProfileIDs)
        profileIDs.formUnion(try await applyProfileIDs)

        for profileID in profileIDs.sorted(by: {
            $0.description < $1.description
        }) {
            try await profileDataEraser.eraseUnadoptedProfileData(
                for: profileID
            )
        }
        try await familySyncApplyTransactionRepository
            .discardUnadoptedProfileState()
        try await familySyncJournalRepository.discardUnadoptedProfileState()

        async let hasJournalState =
            familySyncJournalRepository.hasUnadoptedProfileState()
        async let hasApplyState =
            familySyncApplyTransactionRepository.hasUnadoptedProfileState()
        let journalStateRemains = try await hasJournalState
        let applyStateRemains = try await hasApplyState
        guard try await profileRepository.profiles().isEmpty,
            !journalStateRemains,
            !applyStateRemains
        else {
            throw FirstRunProfileDiscoveryError.failed
        }
        try await onboardingRepository.finishDiscoveryReset()
    }

    private func containPendingProfileCreation(
        profileID: ProfileID
    ) async throws {
        // First-run has not opened child play yet, so the only allowed
        // settings payload is the exact default row staged by createProfile.
        // Any other shape could be real child data and must fail closed.
        if let settings = try await practiceSettingsRepository.settings(
            for: profileID
        ) {
            guard settings == .defaults(for: profileID) else {
                throw FirstRunProfileDiscoveryError.failed
            }
        }

        try await profileDataEraser.eraseProfileData(for: profileID)

        guard try await profileRepository.profile(id: profileID) == nil,
            try await practiceSettingsRepository.settings(for: profileID) == nil,
            try await childSessionRepository.lastSelectedProfileID() != profileID
        else {
            throw FirstRunProfileDiscoveryError.failed
        }
        try await onboardingRepository.finishPendingProfileContainment(
            profileID: profileID
        )
    }
}

struct FirstRunOnboardingCompletion: Sendable {
    let profiles: [KidProfile]
    /// A valid remembered child opens directly. `nil` intentionally routes
    /// families without a remembered choice to the profile chooser.
    let selectedProfileID: ProfileID?
}

enum FirstRunOnboardingProfileSelection {
    static func profilesForPresentation(
        liveProfiles: [KidProfile],
        bootstrappedProfilesWereEmpty: Bool,
        purpose: FirstRunOnboardingPurpose,
        familySyncCapability: FamilySyncCapability,
        profileIntent: FirstRunProfileIntent?,
        pendingCreatedProfileID: ProfileID?
    ) -> [KidProfile] {
        guard familySyncCapability == .iCloud, purpose == .fullSetup else {
            return liveProfiles
        }
        switch profileIntent {
        case .discoverExisting:
            return []
        case .createNew:
            guard let pendingCreatedProfileID else { return [] }
            return liveProfiles.filter { $0.id == pendingCreatedProfileID }
        case nil:
            return bootstrappedProfilesWereEmpty ? [] : liveProfiles
        }
    }

    static func resolvedPurpose(
        _ requestedPurpose: FirstRunOnboardingPurpose,
        in profiles: [KidProfile]
    ) -> FirstRunOnboardingPurpose {
        profiles.isEmpty ? .fullSetup : requestedPurpose
    }

    static func profile(
        in profiles: [KidProfile],
        purpose: FirstRunOnboardingPurpose,
        lastSelectedProfileID: ProfileID?
    ) -> KidProfile? {
        if purpose == .consentRefresh,
            let lastSelectedProfileID,
            let selected = profiles.first(where: { $0.id == lastSelectedProfileID })
        {
            return selected
        }
        return profiles.first
    }

    static func validLastSelectedProfileID(
        in profiles: [KidProfile],
        lastSelectedProfileID: ProfileID?
    ) -> ProfileID? {
        lastSelectedProfileID.flatMap { candidate in
            profiles.contains(where: { $0.id == candidate }) ? candidate : nil
        }
    }
}

struct FirstRunOnboardingSubmission: Sendable {
    enum Action: Sendable {
        case createProfile(GuardianProfileDraft)
        case adoptExistingProfile(ProfileID)
        case confirmExistingProfiles
    }

    static let currentConsentVersion = 1

    let action: Action
    let consentVersion: Int
    /// The first-run agreement presents Family Sync as the recommended default
    /// on iCloud-capable devices. A parent may explicitly opt out before any
    /// local profile mutation is made.
    let familySyncEnabled: Bool

    init(
        action: Action,
        consentVersion: Int = Self.currentConsentVersion,
        familySyncEnabled: Bool = false
    ) {
        self.action = action
        self.consentVersion = consentVersion
        self.familySyncEnabled = familySyncEnabled
    }
}

actor FirstRunOnboardingCoordinator {
    static let maximumDisplayNameCharacterCount = 24

    private let profileRepository: any KidProfileRepository
    private let childSessionRepository: any ChildSessionRepository
    private let onboardingRepository: any FirstRunOnboardingPersisting
    private let guardianStore: any GuardianFamilyStore
    private let familySyncCoordinator: (any FamilySyncCoordinating)?
    private let discoveryAdmissionGate: FirstRunDiscoveryAdmissionGate
    private let clock: any AppClock

    init(
        profileRepository: any KidProfileRepository,
        childSessionRepository: any ChildSessionRepository,
        onboardingRepository: any FirstRunOnboardingPersisting,
        guardianStore: any GuardianFamilyStore,
        familySyncCoordinator: (any FamilySyncCoordinating)? = nil,
        discoveryAdmissionGate: FirstRunDiscoveryAdmissionGate =
            FirstRunDiscoveryAdmissionGate(),
        clock: any AppClock
    ) {
        self.profileRepository = profileRepository
        self.childSessionRepository = childSessionRepository
        self.onboardingRepository = onboardingRepository
        self.guardianStore = guardianStore
        self.familySyncCoordinator = familySyncCoordinator
        self.discoveryAdmissionGate = discoveryAdmissionGate
        self.clock = clock
    }

    func complete(
        profileID: ProfileID?,
        submission: FirstRunOnboardingSubmission
    ) async throws -> FirstRunOnboardingCompletion {
        // This process-local check closes the foreground/account-change window
        // before the durable repository gates and any Profile mutation run.
        let admissionLease = try discoveryAdmissionGate.acquireAdmissionLease()
        guard
            submission.consentVersion
                == FirstRunOnboardingSubmission.currentConsentVersion
        else {
            throw FirstRunOnboardingError.consentRequired
        }
        // Apply the parent's explicit first-run choice before profile creation
        // so a default-on choice can immediately carry that first mutation,
        // while an opt-out never queues it for CloudKit.
        if let familySyncCoordinator {
            _ = try await familySyncCoordinator.setEnabled(
                submission.familySyncEnabled
            )
        }
        switch submission.action {
        case .adoptExistingProfile(let adoptedProfileID):
            try await onboardingRepository.requireDiscoveryResetCompleted()
            guard
                try await profileRepository.profile(id: adoptedProfileID) != nil
            else {
                throw FirstRunOnboardingError.profileNotFound
            }
            // Selection is an exact-ID read. It deliberately performs no save,
            // merge, nickname comparison, or Profile mutation.
            _ = try await guardianStore.selectProfile(id: adoptedProfileID)
            try await childSessionRepository.saveLastSelectedProfileID(
                adoptedProfileID
            )
            let profiles = try await profileRepository.profiles()
            try await onboardingRepository.markCompleted(
                profileID: adoptedProfileID,
                completedAt: clock.now,
                consentVersion: submission.consentVersion,
                admissionGate: discoveryAdmissionGate,
                admissionLease: admissionLease
            )
            return FirstRunOnboardingCompletion(
                profiles: profiles,
                selectedProfileID: adoptedProfileID
            )
        case .confirmExistingProfiles:
            try await onboardingRepository.requireDiscoveryResetCompleted()
            guard let profileID,
                let existing = try await profileRepository.profile(id: profileID)
            else {
                throw FirstRunOnboardingError.profileNotFound
            }
            let profiles = try await profileRepository.profiles()
            let lastSelectedProfileID =
                try await childSessionRepository
                .lastSelectedProfileID()
            let selectedProfileID =
                FirstRunOnboardingProfileSelection
                .validLastSelectedProfileID(
                    in: profiles,
                    lastSelectedProfileID: lastSelectedProfileID
                )
            try await onboardingRepository.markCompleted(
                profileID: selectedProfileID ?? existing.id,
                completedAt: clock.now,
                consentVersion: submission.consentVersion,
                admissionGate: discoveryAdmissionGate,
                admissionLease: admissionLease
            )
            return FirstRunOnboardingCompletion(
                profiles: profiles,
                selectedProfileID: selectedProfileID
            )
        case .createProfile(let draft):
            try await onboardingRepository.requireProfileCreationAllowed()
            let existing: KidProfile?
            if let profileID {
                existing = try await profileRepository.profile(id: profileID)
            } else {
                existing = nil
            }
            return try await createProfile(
                from: draft,
                replacing: existing,
                consentVersion: submission.consentVersion,
                admissionLease: admissionLease
            )
        }
    }

    private func createProfile(
        from draft: GuardianProfileDraft,
        replacing existing: KidProfile?,
        consentVersion: Int,
        admissionLease: FirstRunDiscoveryAdmissionGate.Generation
    ) async throws -> FirstRunOnboardingCompletion {
        let displayName = draft.displayName.trimmingCharacters(
            in: .whitespacesAndNewlines
        )
        guard !displayName.isEmpty else {
            throw FirstRunOnboardingError.emptyDisplayName
        }
        guard displayName.count <= Self.maximumDisplayNameCharacterCount else {
            throw FirstRunOnboardingError.displayNameTooLong(
                maximumCharacterCount: Self.maximumDisplayNameCharacterCount
            )
        }
        guard let ageYears = draft.ageYears,
            ProfileAgePolicy.isSupported(ageYears)
        else {
            throw FirstRunOnboardingError.invalidAge
        }
        guard case .cartoonAnimal(let assetID) = draft.avatar,
            GuardianAnimalAvatar.option(for: assetID) != nil
        else {
            // Camera and photo-library access are intentionally deferred until
            // the parent explicitly edits the profile later.
            throw FirstRunOnboardingError.unsupportedAvatar
        }

        let pendingProfileID = try await onboardingRepository.beginProfileCreation(
            proposedProfileID: existing?.id,
            startedAt: clock.now
        )
        let pendingExisting = try await profileRepository.profile(
            id: pendingProfileID
        )

        let profile: KidProfile
        if let existing = pendingExisting {
            profile = KidProfile(
                id: existing.id,
                displayName: displayName,
                avatar: draft.avatar,
                selectedWorld: draft.selectedWorld,
                starterWorld: draft.selectedWorld,
                guardianUnlockedWorlds: [draft.selectedWorld],
                schoolGrade: draft.schoolGrade,
                ageYears: ageYears,
                voiceprintStatus: existing.voiceprintStatus,
                createdAt: existing.createdAt,
                updatedAt: clock.now
            )
            try await profileRepository.save(profile)
            _ = try await guardianStore.selectProfile(id: profile.id)
        } else {
            let created = try await guardianStore.createProfile(
                id: pendingProfileID,
                from: GuardianProfileDraft(
                    displayName: displayName,
                    avatar: draft.avatar,
                    selectedWorld: draft.selectedWorld,
                    schoolGrade: draft.schoolGrade,
                    ageYears: ageYears,
                    guardianUnlockedWorlds: [draft.selectedWorld]
                )
            )
            profile = created.profile
        }

        // The completion marker is the final throwing operation. If the app is
        // interrupted, or even the final result read fails, the flow reopens
        // with the safely persisted profile and its reserved identity.
        try await childSessionRepository.saveLastSelectedProfileID(profile.id)
        let profiles = try await profileRepository.profiles()
        try await onboardingRepository.markCompleted(
            profileID: profile.id,
            completedAt: clock.now,
            consentVersion: consentVersion,
            admissionGate: discoveryAdmissionGate,
            admissionLease: admissionLease
        )
        return FirstRunOnboardingCompletion(
            profiles: profiles,
            selectedProfileID: profile.id
        )
    }
}
