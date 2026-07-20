import Foundation
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

struct FirstRunOnboardingState: Codable, Equatable, Sendable {
    static let currentSchemaVersion = 2

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
        pendingCreatedProfileID: ProfileID? = nil
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
            pendingCreatedProfileID: nil
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
            pendingCreatedProfileID: nil
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
            pendingCreatedProfileID: pendingCreatedProfileID
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
                : pendingCreatedProfileID
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
            pendingCreatedProfileID: profileID
        )
    }

    func updatingPurpose(
        _ purpose: FirstRunOnboardingPurpose
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
            profileIntent: profileIntent,
            pendingCreatedProfileID: pendingCreatedProfileID
        )
    }
}

enum FirstRunOnboardingRepositoryError: Error, Equatable, Sendable {
    case onboardingAlreadyCompleted
    case pendingProfileCreationChanged
}

protocol FirstRunOnboardingPersisting: Sendable {
    func markDiscoveryIntent() async throws

    /// Durably fences an unfinished local creation from discovery/sync and
    /// returns the one exact identity whose local staging must be contained.
    func prepareForProfileDiscovery() async throws -> ProfileID?

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
        consentVersion: Int?
    ) async throws
}

actor LocalFirstRunOnboardingRepository: FirstRunOnboardingPersisting {
    let snapshotURL: URL

    init(snapshotURL: URL) {
        self.snapshotURL = snapshotURL
    }

    func state() throws -> FirstRunOnboardingState? {
        guard FileManager.default.fileExists(atPath: snapshotURL.path) else {
            return nil
        }
        return try JSONDecoder().decode(
            FirstRunOnboardingState.self,
            from: Data(contentsOf: snapshotURL)
        )
    }

    func markPending(
        startedAt: Date,
        purpose: FirstRunOnboardingPurpose
    ) throws {
        let current = try state()
        if current?.status == .pending, current?.purpose == purpose { return }
        let resolvedPurpose =
            current?.status == .pending
            ? current?.purpose ?? purpose
            : purpose
        try persist(
            .pending(
                startedAt: current?.startedAt ?? startedAt,
                purpose: resolvedPurpose
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
        if current.profileIntent != .discoverExisting {
            try persist(current.recordingDiscoveryIntent())
        }
        return current.pendingCreatedProfileID
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
        consentVersion: Int? = nil
    ) throws {
        let current =
            try state()
            ?? .pending(startedAt: completedAt, purpose: .fullSetup)
        try persist(
            current.completed(
                profileID: profileID,
                completedAt: completedAt,
                consentVersion: consentVersion
            )
        )
    }

    private func persist(_ state: FirstRunOnboardingState) throws {
        try FileManager.default.createDirectory(
            at: snapshotURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        try encoder.encode(state).write(to: snapshotURL, options: .atomic)
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

    init(
        familySyncCoordinator: any FamilySyncCoordinating,
        familySyncTransport: any FamilySyncTransport,
        profileRepository: any KidProfileRepository,
        practiceSettingsRepository: any PracticeSettingsRepository,
        childSessionRepository: any ChildSessionRepository,
        onboardingRepository: any FirstRunOnboardingPersisting
    ) {
        self.familySyncCoordinator = familySyncCoordinator
        self.familySyncTransport = familySyncTransport
        self.profileRepository = profileRepository
        self.practiceSettingsRepository = practiceSettingsRepository
        self.childSessionRepository = childSessionRepository
        self.onboardingRepository = onboardingRepository
    }

    func discoverProfiles() async throws -> [KidProfile] {
        do {
            if let pendingProfileID =
                try await onboardingRepository.prepareForProfileDiscovery()
            {
                try await containPendingProfileCreation(
                    profileID: pendingProfileID
                )
            }
        } catch {
            throw FirstRunProfileDiscoveryError.failed
        }
        switch await familySyncTransport.availability() {
        case .temporarilyUnavailable:
            throw FirstRunProfileDiscoveryError.offline
        case .noAccount, .restricted, .deviceOnly:
            throw FirstRunProfileDiscoveryError.iCloudUnavailable
        case .available:
            break
        }
        let status: FamilySyncStatus
        if await familySyncCoordinator.isEnabled() {
            // Re-enabling reconfirms the account and intentionally resets the
            // CKSyncEngine state. A retry/relaunch must instead continue from
            // the durable cursor and inbox already owned by this consent.
            status = await familySyncCoordinator.synchronize()
        } else {
            do {
                status = try await familySyncCoordinator.setEnabled(true)
            } catch {
                switch await familySyncTransport.availability() {
                case .temporarilyUnavailable:
                    throw FirstRunProfileDiscoveryError.offline
                case .noAccount, .restricted, .deviceOnly:
                    throw FirstRunProfileDiscoveryError.iCloudUnavailable
                case .available:
                    throw FirstRunProfileDiscoveryError.failed
                }
            }
        }

        switch status {
        case .synced:
            return try await profileRepository.profiles().sorted(by: Self.order)
        case .pendingOffline:
            throw FirstRunProfileDiscoveryError.offline
        case .iCloudUnavailable, .deviceOnly, .optedOut:
            throw FirstRunProfileDiscoveryError.iCloudUnavailable
        case .idle, .syncing, .failed:
            throw FirstRunProfileDiscoveryError.failed
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

        if try await childSessionRepository.lastSelectedProfileID() == profileID {
            try await childSessionRepository.clearLastSelectedProfileID()
        }
        try await practiceSettingsRepository.delete(for: profileID)
        try await profileRepository.delete(id: profileID)

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

    init(
        action: Action,
        consentVersion: Int = Self.currentConsentVersion
    ) {
        self.action = action
        self.consentVersion = consentVersion
    }
}

actor FirstRunOnboardingCoordinator {
    static let maximumDisplayNameCharacterCount = 24

    private let profileRepository: any KidProfileRepository
    private let childSessionRepository: any ChildSessionRepository
    private let onboardingRepository: any FirstRunOnboardingPersisting
    private let guardianStore: any GuardianFamilyStore
    private let clock: any AppClock

    init(
        profileRepository: any KidProfileRepository,
        childSessionRepository: any ChildSessionRepository,
        onboardingRepository: any FirstRunOnboardingPersisting,
        guardianStore: any GuardianFamilyStore,
        clock: any AppClock
    ) {
        self.profileRepository = profileRepository
        self.childSessionRepository = childSessionRepository
        self.onboardingRepository = onboardingRepository
        self.guardianStore = guardianStore
        self.clock = clock
    }

    func complete(
        profileID: ProfileID?,
        submission: FirstRunOnboardingSubmission
    ) async throws -> FirstRunOnboardingCompletion {
        guard
            submission.consentVersion
                == FirstRunOnboardingSubmission.currentConsentVersion
        else {
            throw FirstRunOnboardingError.consentRequired
        }
        switch submission.action {
        case .adoptExistingProfile(let adoptedProfileID):
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
                consentVersion: submission.consentVersion
            )
            return FirstRunOnboardingCompletion(
                profiles: profiles,
                selectedProfileID: adoptedProfileID
            )
        case .confirmExistingProfiles:
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
                consentVersion: submission.consentVersion
            )
            return FirstRunOnboardingCompletion(
                profiles: profiles,
                selectedProfileID: selectedProfileID
            )
        case .createProfile(let draft):
            let existing: KidProfile?
            if let profileID {
                existing = try await profileRepository.profile(id: profileID)
            } else {
                existing = nil
            }
            return try await createProfile(
                from: draft,
                replacing: existing,
                consentVersion: submission.consentVersion
            )
        }
    }

    private func createProfile(
        from draft: GuardianProfileDraft,
        replacing existing: KidProfile?,
        consentVersion: Int
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
            consentVersion: consentVersion
        )
        return FirstRunOnboardingCompletion(
            profiles: profiles,
            selectedProfileID: profile.id
        )
    }
}
