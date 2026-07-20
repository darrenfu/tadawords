import Foundation
import TadaWordsDomain
import TadaWordsGuardianFeatures

enum FirstRunOnboardingPurpose: String, Codable, Equatable, Sendable {
    case fullSetup
    case consentRefresh
}

struct FirstRunOnboardingState: Codable, Equatable, Sendable {
    static let currentSchemaVersion = 1

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
            purpose: purpose
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
            purpose: purpose
        )
    }
}

actor LocalFirstRunOnboardingRepository {
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
        try persist(
            .pending(
                startedAt: current.startedAt,
                purpose: purpose
            )
        )
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

struct FirstRunOnboardingCompletion: Sendable {
    let profiles: [KidProfile]
    /// A valid remembered child opens directly. `nil` intentionally routes
    /// families without a remembered choice to the profile chooser.
    let selectedProfileID: ProfileID?
}

enum FirstRunOnboardingProfileSelection {
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
    private let onboardingRepository: LocalFirstRunOnboardingRepository
    private let guardianStore: any GuardianFamilyStore
    private let clock: any AppClock

    init(
        profileRepository: any KidProfileRepository,
        childSessionRepository: any ChildSessionRepository,
        onboardingRepository: LocalFirstRunOnboardingRepository,
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

        let profile: KidProfile
        if let existing {
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

        // The completion marker is committed last. If the app is interrupted,
        // the flow reopens with the safely persisted profile instead of
        // exposing a half-configured child home.
        try await childSessionRepository.saveLastSelectedProfileID(profile.id)
        try await onboardingRepository.markCompleted(
            profileID: profile.id,
            completedAt: clock.now,
            consentVersion: consentVersion
        )
        return FirstRunOnboardingCompletion(
            profiles: try await profileRepository.profiles(),
            selectedProfileID: profile.id
        )
    }
}
