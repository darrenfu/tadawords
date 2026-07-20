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
    private let voiceprintRepository: (any DeviceVoiceprintRepository)?
    private let handwritingPreferenceRemover: (any HandwritingPreferenceRemoving)?
    private let mutationGate: ProfileScopedMutationGate?
    private let onLocalMutation: @Sendable (ProfileID) -> Void
    private let clock: any AppClock
    private let timeZone: TimeZone
    private var selectedProfileID: ProfileID?

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
        voiceprintRepository: (any DeviceVoiceprintRepository)? = nil,
        handwritingPreferenceRemover: (any HandwritingPreferenceRemoving)? = nil,
        mutationGate: ProfileScopedMutationGate? = nil,
        onLocalMutation: @escaping @Sendable (ProfileID) -> Void = { _ in },
        clock: any AppClock,
        timeZone: TimeZone = .current
    ) {
        self.profileRepository = profileRepository
        self.wordPoolRepository = wordPoolRepository
        self.practiceSettingsRepository = practiceSettingsRepository
        self.learningRecordRepository = learningRecordRepository
        self.dailyQuestRepository = dailyQuestRepository
        self.tombstoneRepository = tombstoneRepository
        self.childSessionRepository = childSessionRepository
        self.voiceprintRepository = voiceprintRepository
        self.handwritingPreferenceRemover = handwritingPreferenceRemover
        self.mutationGate = mutationGate
        self.onLocalMutation = onLocalMutation
        self.clock = clock
        self.timeZone = timeZone
        self.selectedProfileID =
            selectedProfileID.flatMap { candidate in
                profiles.contains(where: { $0.id == candidate }) ? candidate : nil
            }
            ?? profiles.first?.id
    }

    public func familySnapshot() async throws -> GuardianFamilySnapshot {
        let profiles = try await profileRepository.profiles()
        // External receipt refreshes cancel the superseded task. Do not let a
        // repository that ignores cancellation resume later and mutate the
        // shared selection behind the newer Parent snapshot.
        try Task.checkCancellation()
        guard !profiles.isEmpty else {
            return GuardianFamilySnapshot(
                profiles: [],
                selectedProfileID: nil
            )
        }
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
        try Task.checkCancellation()
        selectedProfileID = id
        return try await makeWordStore(for: profile).dashboardSnapshot()
    }

    public func createProfile(
        from draft: GuardianProfileDraft
    ) async throws -> GuardianDashboardSnapshot {
        try await createProfile(id: ProfileID(), from: draft)
    }

    public func createProfile(
        id: ProfileID,
        from draft: GuardianProfileDraft
    ) async throws -> GuardianDashboardSnapshot {
        let values = try validatedValues(from: draft, requiresAge: true)
        let profile = KidProfile(
            id: id,
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
        try await practiceSettingsRepository.save(.defaults(for: profile.id))
        do {
            try await profileRepository.save(profile)
        } catch {
            // Settings are written first so a visible Profile is never
            // published without its isolated defaults. Roll them back if the
            // Profile commit fails.
            try? await practiceSettingsRepository.delete(for: profile.id)
            throw error
        }
        selectedProfileID = profile.id
        onLocalMutation(profile.id)
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
        onLocalMutation(updated.id)
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
        let report = try await makeWordStore(for: profile).importWords(request)
        onLocalMutation(profile.id)
        return report
    }

    public func importWords(
        _ request: GuardianWordImportRequest,
        for profileID: ProfileID
    ) async throws -> GuardianWordImportReport {
        let profile = try await requiredProfile(id: profileID)
        let report = try await makeWordStore(for: profile).importWords(request)
        onLocalMutation(profile.id)
        return report
    }

    public func updatePracticeSettings(
        _ settings: ProfilePracticeSettings
    ) async throws -> GuardianDashboardSnapshot {
        let profile = try await selectedProfile()
        let snapshot = try await makeWordStore(for: profile)
            .updatePracticeSettings(settings)
        onLocalMutation(profile.id)
        return snapshot
    }

    public func deactivateWord(
        id: WordPromptID,
        learningMode: LearningMode
    ) async throws -> GuardianDashboardSnapshot {
        let profile = try await selectedProfile()
        let snapshot = try await makeWordStore(for: profile).deactivateWord(
            id: id,
            learningMode: learningMode
        )
        onLocalMutation(profile.id)
        return snapshot
    }

    public func setWordsActive(
        ids: [WordPromptID],
        learningMode: LearningMode,
        isActive: Bool
    ) async throws -> GuardianDashboardSnapshot {
        let profile = try await selectedProfile()
        let snapshot = try await makeWordStore(for: profile).setWordsActive(
            ids: ids,
            learningMode: learningMode,
            isActive: isActive
        )
        onLocalMutation(profile.id)
        return snapshot
    }

    public func setWordsActive(
        ids: [WordPromptID],
        learningMode: LearningMode,
        isActive: Bool,
        for profileID: ProfileID
    ) async throws -> GuardianDashboardSnapshot {
        let profile = try await requiredProfile(id: profileID)
        let snapshot = try await makeWordStore(for: profile).setWordsActive(
            ids: ids,
            learningMode: learningMode,
            isActive: isActive
        )
        onLocalMutation(profile.id)
        return snapshot
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
        onLocalMutation(profile.id)
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
        let report = try await makeWordStore(for: profile).correctAttempt(
            id: id,
            to: outcome
        )
        onLocalMutation(profile.id)
        return report
    }

    /// Deletes every Profile-scoped local record before removing its identity.
    /// One shared lease covers the tombstone, every local purge, and the final
    /// commit marker, so Family Sync cannot observe a half-finished deletion.
    public func deleteProfile(
        id: ProfileID
    ) async throws -> GuardianProfileDeletionResult {
        let result = try await withProfileScopedMutationLease(
            mutationGate,
            for: id,
            allowingTerminal: true
        ) {
            try await self.deleteProfileHoldingLease(id: id)
        }
        // Fire-and-forget sync work must not inherit the transaction's
        // TaskLocal lease marker. Notify only after the lease is released.
        onLocalMutation(id)
        return result
    }

    private func deleteProfileHoldingLease(
        id: ProfileID
    ) async throws -> GuardianProfileDeletionResult {
        let profiles = try await profileRepository.profiles()
        guard let profile = profiles.first(where: { $0.id == id }) else {
            throw GuardianFamilyStoreError.profileNotFound(id)
        }
        // Read every dependency first so malformed durable data cannot begin a
        // partially applied delete.
        _ = try await makeWordStore(for: profile).dashboardSnapshot()

        let tombstone = ProfileDeletionTombstone(
            profileID: id,
            deletedAt: clock.now
        )
        try await tombstoneRepository?.save(tombstone)
        await mutationGate?.seal(id)
        // Voiceprint templates are sensitive device-local child data. Their
        // throwing deletion is part of the durable local purge, never a
        // best-effort cleanup after the deletion has been reported complete.
        try await voiceprintRepository?.delete(for: id)
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
        let remainingProfiles = try await profileRepository.profiles()
        let nextSelectedProfileID =
            selectedProfileID.flatMap { candidate in
                remainingProfiles.contains(where: { $0.id == candidate })
                    ? candidate
                    : nil
            } ?? remainingProfiles.first?.id
        selectedProfileID = nextSelectedProfileID
        if let childSessionRepository,
            (try? await childSessionRepository.lastSelectedProfileID()) == id
        {
            // The session pointer is a convenience, not learning data. A
            // storage failure here must not roll back or misreport the
            // already committed profile deletion; bootstrap repairs it too.
            if let nextSelectedProfileID {
                try? await childSessionRepository.saveLastSelectedProfileID(
                    nextSelectedProfileID
                )
            } else {
                try? await childSessionRepository.clearLastSelectedProfileID()
            }
        }
        let family = GuardianFamilySnapshot(
            profiles: remainingProfiles,
            selectedProfileID: nextSelectedProfileID
        )
        let dashboard: GuardianDashboardSnapshot?
        if let nextProfile = family.selectedProfile {
            dashboard = try await makeWordStore(for: nextProfile).dashboardSnapshot()
        } else {
            dashboard = nil
        }
        return GuardianProfileDeletionResult(
            family: family,
            dashboard: dashboard,
            tombstone: tombstone
        )
    }

    private func selectedProfile() async throws -> KidProfile {
        let requestedProfileID = selectedProfileID
        let profiles = try await profileRepository.profiles()
        try Task.checkCancellation()
        if let requestedProfileID,
            let selected = profiles.first(where: { $0.id == requestedProfileID })
        {
            return selected
        }
        guard let fallback = profiles.first else {
            throw GuardianFamilyStoreError.noProfiles
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
        if let selectedProfileID,
            let selected = profiles.first(where: { $0.id == selectedProfileID })
        {
            return selected
        }
        guard let fallback = profiles.first else {
            throw GuardianFamilyStoreError.noProfiles
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
