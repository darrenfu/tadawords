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
        let values = try validatedValues(from: draft)
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
        let values = try validatedValues(from: draft)
        let updated = KidProfile(
            id: existing.id,
            displayName: values.displayName,
            avatar: values.avatar,
            selectedWorld: draft.selectedWorld,
            starterWorld: existing.starterWorld,
            guardianUnlockedWorlds: draft.guardianUnlockedWorlds,
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
        let profiles = try await profileRepository.profiles()
        return try resolveSelectedProfile(in: profiles)
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
        from draft: GuardianProfileDraft
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
        guard draft.ageYears.map({ (2...18).contains($0) }) ?? true else {
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
        }
        return (displayName, draft.avatar)
    }
}
