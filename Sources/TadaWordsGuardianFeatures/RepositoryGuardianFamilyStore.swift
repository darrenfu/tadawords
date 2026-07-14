import Foundation
import TadaWordsContent
import TadaWordsDomain

/// Owns the Guardian area's current child selection while keeping every
/// repository operation scoped to that profile's stable identity.
public actor RepositoryGuardianFamilyStore: GuardianFamilyStore {
    public static let maximumDisplayNameCharacterCount = 24

    private let profileRepository: any KidProfileRepository
    private let wordPoolRepository: any WordPoolRepository
    private let practiceSettingsRepository: any PracticeSettingsRepository
    private let learningRecordRepository: (any AttemptEventRepository & WordProgressRepository)?
    private let dailyQuestRepository: any DailyQuestRepository
    private let tombstoneRepository: (any ProfileDeletionTombstoneRepository)?
    private let childSessionRepository: (any ChildSessionRepository)?
    private let handwritingPreferenceRemover: (any HandwritingPreferenceRemoving)?
    private let clock: any AppClock
    private let timeZone: TimeZone
    private var selectedProfileID: ProfileID

    public init(
        profiles: [KidProfile],
        selectedProfileID: ProfileID? = nil,
        profileRepository: any KidProfileRepository,
        wordPoolRepository: any WordPoolRepository,
        practiceSettingsRepository: any PracticeSettingsRepository,
        learningRecordRepository:
            (any AttemptEventRepository & WordProgressRepository)? = nil,
        dailyQuestRepository: any DailyQuestRepository = InMemoryDailyQuestRepository(),
        tombstoneRepository: (any ProfileDeletionTombstoneRepository)? = nil,
        childSessionRepository: (any ChildSessionRepository)? = nil,
        handwritingPreferenceRemover: (any HandwritingPreferenceRemoving)? = nil,
        clock: any AppClock,
        timeZone: TimeZone = .current
    ) {
        precondition(!profiles.isEmpty, "A family store requires at least one profile.")
        self.profileRepository = profileRepository
        self.wordPoolRepository = wordPoolRepository
        self.practiceSettingsRepository = practiceSettingsRepository
        self.learningRecordRepository = learningRecordRepository
        self.dailyQuestRepository = dailyQuestRepository
        self.tombstoneRepository = tombstoneRepository
        self.childSessionRepository = childSessionRepository
        self.handwritingPreferenceRemover = handwritingPreferenceRemover
        self.clock = clock
        self.timeZone = timeZone
        self.selectedProfileID =
            selectedProfileID.flatMap { candidate in
                profiles.contains(where: { $0.id == candidate }) ? candidate : nil
            }
            ?? profiles[0].id
    }

    public func familySnapshot() async throws -> GuardianFamilySnapshot {
        let profiles = try await profileRepository.profiles()
        let selectedProfile = try resolveSelectedProfile(in: profiles)
        return GuardianFamilySnapshot(
            profiles: profiles,
            selectedProfileID: selectedProfile.id
        )
    }

    public func selectProfile(
        id: ProfileID
    ) async throws -> GuardianDashboardSnapshot {
        guard let profile = try await profileRepository.profile(id: id) else {
            throw GuardianFamilyStoreError.profileNotFound(id)
        }
        selectedProfileID = id
        return try await makeWordStore(for: profile).dashboardSnapshot()
    }

    public func createProfile(
        from draft: GuardianProfileDraft
    ) async throws -> GuardianDashboardSnapshot {
        let values = try validatedValues(from: draft, requiresAge: true)
        let profile = KidProfile(
            displayName: values.displayName,
            avatar: values.avatar,
            selectedWorld: draft.selectedWorld,
            starterWorld: draft.selectedWorld,
            guardianUnlockedWorlds: draft.guardianUnlockedWorlds,
            schoolGrade: draft.schoolGrade,
            ageYears: draft.ageYears,
            createdAt: clock.now
        )
        let preparedDashboard = try await makeWordStore(
            for: profile
        ).dashboardSnapshot()
        try await profileRepository.save(profile)
        selectedProfileID = profile.id
        return preparedDashboard
    }

    public func updateProfile(
        id: ProfileID,
        from draft: GuardianProfileDraft
    ) async throws -> GuardianDashboardSnapshot {
        guard let existing = try await profileRepository.profile(id: id) else {
            throw GuardianFamilyStoreError.profileNotFound(id)
        }
        let values = try validatedValues(from: draft, requiresAge: false)
        let updated = KidProfile(
            id: existing.id,
            displayName: values.displayName,
            avatar: values.avatar,
            selectedWorld: draft.selectedWorld,
            starterWorld: existing.starterWorld,
            guardianUnlockedWorlds: draft.guardianUnlockedWorlds,
            selectedCartoonIconAssetID: values.avatar == existing.avatar
                ? existing.selectedCartoonIconAssetID
                : nil,
            selectedTreasureAvatar: values.avatar == existing.avatar
                ? existing.selectedTreasureAvatar
                : nil,
            schoolGrade: draft.schoolGrade,
            ageYears: draft.ageYears,
            voiceprintStatus: existing.voiceprintStatus,
            createdAt: existing.createdAt,
            updatedAt: clock.now
        )
        let preparedDashboard = try await makeWordStore(
            for: updated
        ).dashboardSnapshot()
        try await profileRepository.save(updated)
        selectedProfileID = updated.id
        return preparedDashboard
    }

    public func dashboardSnapshot() async throws -> GuardianDashboardSnapshot {
        let profile = try await selectedProfile()
        return try await makeWordStore(for: profile).dashboardSnapshot()
    }

    public func dashboardSnapshot(
        for profileID: ProfileID
    ) async throws -> GuardianDashboardSnapshot {
        let profile = try await requiredProfile(id: profileID)
        return try await makeWordStore(for: profile).dashboardSnapshot()
    }

    public func updateVoiceprintStatus(
        profileID: ProfileID,
        status: VoiceprintEnrollmentStatus
    ) async throws -> GuardianDashboardSnapshot {
        guard let existing = try await profileRepository.profile(id: profileID) else {
            throw GuardianFamilyStoreError.profileNotFound(profileID)
        }
        let updated = KidProfile(
            id: existing.id,
            displayName: existing.displayName,
            avatar: existing.avatar,
            selectedWorld: existing.selectedWorld,
            starterWorld: existing.starterWorld,
            guardianUnlockedWorlds: existing.guardianUnlockedWorlds,
            selectedCartoonIconAssetID: existing.selectedCartoonIconAssetID,
            selectedTreasureAvatar: existing.selectedTreasureAvatar,
            schoolGrade: existing.schoolGrade,
            ageYears: existing.ageYears,
            voiceprintStatus: status,
            createdAt: existing.createdAt,
            updatedAt: existing.updatedAt
        )
        try await profileRepository.save(updated)
        selectedProfileID = profileID
        return try await makeWordStore(for: updated).dashboardSnapshot()
    }

    public func importWords(
        _ request: GuardianWordImportRequest
    ) async throws -> GuardianWordImportReport {
        let profile = try await selectedProfile()
        return try await makeWordStore(for: profile).importWords(request)
    }

    public func importWords(
        _ request: GuardianWordImportRequest,
        for profileID: ProfileID
    ) async throws -> GuardianWordImportReport {
        let profile = try await requiredProfile(id: profileID)
        return try await makeWordStore(for: profile).importWords(request)
    }

    public func updatePracticeSettings(
        _ settings: ProfilePracticeSettings
    ) async throws -> GuardianDashboardSnapshot {
        let profile = try await selectedProfile()
        return try await makeWordStore(for: profile).updatePracticeSettings(settings)
    }

    public func deactivateWord(
        id: WordPromptID,
        learningMode: LearningMode
    ) async throws -> GuardianDashboardSnapshot {
        let profile = try await selectedProfile()
        return try await makeWordStore(for: profile).deactivateWord(
            id: id,
            learningMode: learningMode
        )
    }

    public func setWordsActive(
        ids: [WordPromptID],
        learningMode: LearningMode,
        isActive: Bool
    ) async throws -> GuardianDashboardSnapshot {
        let profile = try await selectedProfile()
        return try await makeWordStore(for: profile).setWordsActive(
            ids: ids,
            learningMode: learningMode,
            isActive: isActive
        )
    }

    public func setWordsActive(
        ids: [WordPromptID],
        learningMode: LearningMode,
        isActive: Bool,
        for profileID: ProfileID
    ) async throws -> GuardianDashboardSnapshot {
        let profile = try await requiredProfile(id: profileID)
        return try await makeWordStore(for: profile).setWordsActive(
            ids: ids,
            learningMode: learningMode,
            isActive: isActive
        )
    }

    public func setMembershipsActive(
        ids: [WordPoolEntryID],
        learningMode: LearningMode,
        isActive: Bool,
        for profileID: ProfileID
    ) async throws {
        let profile = try await requiredProfile(id: profileID)
        try await makeWordStore(for: profile).setMembershipsActive(
            ids: ids,
            learningMode: learningMode,
            isActive: isActive
        )
    }

    public func report(
        for period: GuardianReportPeriod
    ) async throws -> GuardianLearningReport {
        let profile = try await selectedProfile()
        return try await makeWordStore(for: profile).report(for: period)
    }

    public func correctAttempt(
        id: AttemptID,
        to outcome: AttemptOutcome
    ) async throws -> GuardianLearningReport {
        let profile = try await selectedProfile()
        return try await makeWordStore(for: profile).correctAttempt(
            id: id,
            to: outcome
        )
    }

    /// Deletes every profile-scoped local record before removing the profile
    /// identity. The actor serializes the lifecycle boundary, and each durable
    /// repository commits its own candidate atomically.
    public func deleteProfile(
        id: ProfileID
    ) async throws -> GuardianProfileDeletionResult {
        let profiles = try await profileRepository.profiles()
        guard profiles.count > 1 else {
            throw GuardianFamilyStoreError.cannotDeleteOnlyProfile
        }
        guard let profile = profiles.first(where: { $0.id == id }) else {
            throw GuardianFamilyStoreError.profileNotFound(id)
        }
        // Read every dependency first so malformed durable data cannot begin a
        // partially applied delete.
        _ = try await makeWordStore(for: profile).dashboardSnapshot()
        let fallback = profiles.first { $0.id != id }!

        let tombstone = ProfileDeletionTombstone(
            profileID: id,
            deletedAt: clock.now
        )
        try await tombstoneRepository?.save(tombstone)
        try await wordPoolRepository.deleteAll(for: id)
        try await practiceSettingsRepository.delete(for: id)
        if let learning = learningRecordRepository
            as? any ProfileLearningRecordRepository
        {
            try await learning.deleteLearningRecords(for: id)
        }
        if let history = dailyQuestRepository
            as? any DailyQuestHistoryRepository
        {
            try await history.deleteHistory(for: id)
        }
        try await profileRepository.delete(id: id)
        handwritingPreferenceRemover?.remove(for: id)
        try await tombstoneRepository?.markCommitted(for: id)
        if let childSessionRepository,
            (try? await childSessionRepository.lastSelectedProfileID()) == id
        {
            // The session pointer is a convenience, not learning data. A
            // storage failure here must not roll back or misreport the
            // already committed profile deletion; bootstrap repairs it too.
            try? await childSessionRepository.saveLastSelectedProfileID(
                fallback.id
            )
        }
        if selectedProfileID == id {
            selectedProfileID = fallback.id
        }
        return GuardianProfileDeletionResult(
            dashboard: try await makeWordStore(for: fallback).dashboardSnapshot(),
            tombstone: tombstone
        )
    }

    private func selectedProfile() async throws -> KidProfile {
        let requestedProfileID = selectedProfileID
        let profiles = try await profileRepository.profiles()
        if let selected = profiles.first(where: { $0.id == requestedProfileID }) {
            return selected
        }
        guard let fallback = profiles.first else {
            throw GuardianFamilyStoreError.profileNotFound(requestedProfileID)
        }
        if selectedProfileID == requestedProfileID {
            selectedProfileID = fallback.id
        }
        return fallback
    }

    private func requiredProfile(id: ProfileID) async throws -> KidProfile {
        guard let profile = try await profileRepository.profile(id: id) else {
            throw GuardianFamilyStoreError.profileNotFound(id)
        }
        return profile
    }

    private func resolveSelectedProfile(
        in profiles: [KidProfile]
    ) throws -> KidProfile {
        if let selected = profiles.first(where: { $0.id == selectedProfileID }) {
            return selected
        }
        guard let fallback = profiles.first else {
            throw GuardianFamilyStoreError.profileNotFound(selectedProfileID)
        }
        selectedProfileID = fallback.id
        return fallback
    }

    private func makeWordStore(
        for profile: KidProfile
    ) -> RepositoryGuardianWordStore {
        RepositoryGuardianWordStore(
            profile: profile,
            wordPoolRepository: wordPoolRepository,
            practiceSettingsRepository: practiceSettingsRepository,
            learningRecordRepository: learningRecordRepository,
            dailyQuestRepository: dailyQuestRepository,
            clock: clock,
            timeZone: timeZone
        )
    }

    private func validatedValues(
        from draft: GuardianProfileDraft,
        requiresAge: Bool
    ) throws -> (displayName: String, avatar: ProfileAvatar) {
        let displayName = draft.displayName.trimmingCharacters(
            in: .whitespacesAndNewlines
        )
        guard !displayName.isEmpty else {
            throw GuardianFamilyStoreError.emptyDisplayName
        }
        guard displayName.count <= Self.maximumDisplayNameCharacterCount else {
            throw GuardianFamilyStoreError.displayNameTooLong(
                maximumCharacterCount: Self.maximumDisplayNameCharacterCount
            )
        }
        guard !requiresAge || draft.ageYears != nil else {
            throw GuardianFamilyStoreError.invalidAge
        }
        let ageIsValid =
            draft.ageYears.map {
                requiresAge
                    ? ProfileAgePolicy.isSupported($0)
                    : ProfileAgePolicy.isDurable($0)
            } ?? true
        guard ageIsValid else {
            throw GuardianFamilyStoreError.invalidAge
        }
        switch draft.avatar {
        case .cartoonAnimal(let assetID):
            guard GuardianAnimalAvatar.option(for: assetID) != nil else {
                throw GuardianFamilyStoreError.unsupportedAvatar(assetID)
            }
        case .photo(let assetID, _):
            guard !assetID.isEmpty else {
                throw GuardianFamilyStoreError.unsupportedAvatar(assetID)
            }
        case .treasure(_, let iconAssetID):
            throw GuardianFamilyStoreError.unsupportedAvatar(iconAssetID)
        }
        return (displayName, draft.avatar)
    }
}
