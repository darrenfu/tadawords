import Foundation
import OSLog
import SwiftUI
import TadaWordsContent
import TadaWordsDomain
import TadaWordsFeatures
import TadaWordsGuardianFeatures

struct ApplicationDataPaths: Equatable, Sendable {
    static let dataDirectoryName = "TadaWords"

    let dataDirectory: URL
    let profilesSnapshot: URL
    let wordPoolSnapshot: URL
    let learningRecordsSnapshot: URL
    let practiceSettingsSnapshot: URL
    let dailyQuestsSnapshot: URL
    let childSessionSnapshot: URL
    let profileDeletionTombstonesSnapshot: URL
    let deviceIdentitySnapshot: URL
    let firstRunOnboardingSnapshot: URL
    let familySyncPreferenceSnapshot: URL
    let familySyncJournalSnapshot: URL
    let familySyncApplyTransactionsSnapshot: URL

    init(applicationSupportDirectory: URL) {
        dataDirectory = applicationSupportDirectory.appendingPathComponent(
            Self.dataDirectoryName,
            isDirectory: true
        )
        profilesSnapshot = dataDirectory.appendingPathComponent(
            "profiles.json",
            isDirectory: false
        )
        wordPoolSnapshot = dataDirectory.appendingPathComponent(
            "word-pool.json",
            isDirectory: false
        )
        learningRecordsSnapshot = dataDirectory.appendingPathComponent(
            "learning-records.json",
            isDirectory: false
        )
        practiceSettingsSnapshot = dataDirectory.appendingPathComponent(
            "practice-settings.json",
            isDirectory: false
        )
        dailyQuestsSnapshot = dataDirectory.appendingPathComponent(
            "daily-quests.json",
            isDirectory: false
        )
        childSessionSnapshot = dataDirectory.appendingPathComponent(
            "child-session.json",
            isDirectory: false
        )
        profileDeletionTombstonesSnapshot = dataDirectory.appendingPathComponent(
            "profile-deletions.json",
            isDirectory: false
        )
        deviceIdentitySnapshot = dataDirectory.appendingPathComponent(
            "device-identity.txt",
            isDirectory: false
        )
        firstRunOnboardingSnapshot = dataDirectory.appendingPathComponent(
            "first-run-onboarding.json",
            isDirectory: false
        )
        familySyncPreferenceSnapshot = dataDirectory.appendingPathComponent(
            "family-sync-preference.json",
            isDirectory: false
        )
        familySyncJournalSnapshot = dataDirectory.appendingPathComponent(
            "family-sync-journal.json",
            isDirectory: false
        )
        familySyncApplyTransactionsSnapshot = dataDirectory.appendingPathComponent(
            "family-sync-apply-transactions.json",
            isDirectory: false
        )
    }
}

struct ProductionApplicationEnvironment: Sendable {
    let profiles: [KidProfile]
    let profileRepository: LocalJSONKidProfileRepository
    let wordPoolRepository: LocalJSONWordPoolRepository
    let learningRecordRepository: LocalJSONLearningRecordRepository
    let practiceSettingsRepository: LocalJSONPracticeSettingsRepository
    let dailyQuestRepository: LocalJSONDailyQuestRepository
    let childSessionRepository: LocalJSONChildSessionRepository
    let profileDataEraser: RepositoryProfileDataEraser
    let lastSelectedProfileID: ProfileID?
    let guardianStore: RepositoryGuardianFamilyStore
    let familySyncCoordinator: LocalFirstFamilySyncCoordinator
    let familySyncCanonicalRecovery: CanonicalFamilySyncRecoveryCoordinator
    let familySyncTransport: any FamilySyncTransport
    let familySyncJournalRepository: LocalJSONFamilySyncJournalRepository
    let familySyncApplyTransactionRepository: LocalJSONFamilySyncApplyTransactionRepository
    let tombstoneRepository: LocalJSONProfileDeletionTombstoneRepository
    let profileMutationGate: ProfileScopedMutationGate
    let notificationReconciler: ProductionLearningNotificationReconciler?
    let firstRunOnboardingRepository: LocalFirstRunOnboardingRepository
    let firstRunDiscoveryAdmissionGate: FirstRunDiscoveryAdmissionGate
    let firstRunOnboardingPurpose: FirstRunOnboardingPurpose?
    let firstRunProfileIntent: FirstRunProfileIntent?
    let firstRunPendingCreatedProfileID: ProfileID?
    let requiresFirstRunOnboarding: Bool
    let clock: any AppClock
    let timeZone: TimeZone
    let dataPaths: ApplicationDataPaths
}

protocol ApplicationBootstrapping: Sendable {
    func bootstrap() async throws -> ProductionApplicationEnvironment
}

enum ApplicationSnapshotStore: String, Equatable, Sendable {
    case profiles
    case wordPool
    case learningRecords
    case practiceSettings
    case dailyQuests
    case childSession
    case profileDeletionTombstones
    case firstRunOnboarding
    case familySyncPreference
    case familySyncJournal
    case familySyncApplyTransactions
}

enum ApplicationBootstrapError: Error, Equatable, Sendable {
    case defaultProfileWasNotPersisted(ProfileID)
    case freshInstallationVoiceprintResetUnavailable
    case profileSnapshotMissingWithDependentData
    case snapshotReadFailed(store: ApplicationSnapshotStore)
    case invalidSnapshotEnvelope(store: ApplicationSnapshotStore)
    case requiresNewerApp(
        store: ApplicationSnapshotStore,
        found: Int,
        supported: Int
    )
}

struct ProductionApplicationBootstrapper: ApplicationBootstrapping, Sendable {
    private let applicationSupportDirectory: @Sendable () throws -> URL
    private let defaultProfile: KidProfile
    private let clock: any AppClock
    private let timeZone: TimeZone
    private let familySyncTransport: any FamilySyncTransport
    private let notificationScheduler: (any LearningNotificationScheduling)?
    private let voiceprintRepository: (any DeviceVoiceprintRepository)?
    private let handwritingPreferenceRemover: any HandwritingPreferenceRemoving
    private let profileMutationGate: ProfileScopedMutationGate
    private let teacherAudioPreparer: (any TeacherWordAudioPreparing)?

    init(
        applicationSupportDirectory: @escaping @Sendable () throws -> URL,
        defaultProfile: KidProfile,
        clock: any AppClock,
        timeZone: TimeZone,
        familySyncTransport: any FamilySyncTransport = LocalOnlyFamilySyncTransport(),
        notificationScheduler: (any LearningNotificationScheduling)? = nil,
        voiceprintRepository: (any DeviceVoiceprintRepository)? = nil,
        teacherAudioPreparer: (any TeacherWordAudioPreparing)? = nil,
        profileMutationGate: ProfileScopedMutationGate = ProfileScopedMutationGate(),
        handwritingPreferenceRemover: any HandwritingPreferenceRemoving =
            HandwritingPreferenceStore()
    ) {
        self.applicationSupportDirectory = applicationSupportDirectory
        self.defaultProfile = defaultProfile
        self.clock = clock
        self.timeZone = timeZone
        self.familySyncTransport = familySyncTransport
        self.notificationScheduler = notificationScheduler
        self.voiceprintRepository = voiceprintRepository
        self.teacherAudioPreparer = teacherAudioPreparer
        self.profileMutationGate = profileMutationGate
        self.handwritingPreferenceRemover = handwritingPreferenceRemover
    }

    func bootstrap() async throws -> ProductionApplicationEnvironment {
        let dataPaths = ApplicationDataPaths(
            applicationSupportDirectory: try applicationSupportDirectory()
        )
        let dataDirectoryExistedAtStart = FileManager.default.fileExists(
            atPath: dataPaths.dataDirectory.path
        )
        try await resetRetainedVoiceprintsForFreshInstallationIfNeeded(
            dataDirectoryExistedAtStart: dataDirectoryExistedAtStart
        )
        let profileSnapshotExistedAtStart = FileManager.default.fileExists(
            atPath: dataPaths.profilesSnapshot.path
        )
        try preflightSnapshotSchemas(at: dataPaths)
        let deviceID = try loadOrCreateDeviceID(
            at: dataPaths.deviceIdentitySnapshot
        )
        let profileRepository = LocalJSONKidProfileRepository(
            snapshotURL: dataPaths.profilesSnapshot,
            mutationGate: profileMutationGate
        )
        let wordPoolRepository = LocalJSONWordPoolRepository(
            snapshotURL: dataPaths.wordPoolSnapshot,
            mutationGate: profileMutationGate,
            deviceID: deviceID
        )
        let learningRecordRepository = LocalJSONLearningRecordRepository(
            snapshotURL: dataPaths.learningRecordsSnapshot,
            mutationGate: profileMutationGate
        )
        let practiceSettingsRepository = LocalJSONPracticeSettingsRepository(
            snapshotURL: dataPaths.practiceSettingsSnapshot,
            mutationGate: profileMutationGate
        )
        let dailyQuestRepository = LocalJSONDailyQuestRepository(
            snapshotURL: dataPaths.dailyQuestsSnapshot,
            mutationGate: profileMutationGate
        )
        let childSessionRepository = LocalJSONChildSessionRepository(
            snapshotURL: dataPaths.childSessionSnapshot
        )
        let tombstoneRepository = LocalJSONProfileDeletionTombstoneRepository(
            snapshotURL: dataPaths.profileDeletionTombstonesSnapshot,
            mutationGate: profileMutationGate
        )
        let firstRunOnboardingRepository = LocalFirstRunOnboardingRepository(
            snapshotURL: dataPaths.firstRunOnboardingSnapshot
        )
        let familySyncPreferenceRepository = LocalJSONFamilySyncPreferenceRepository(
            snapshotURL: dataPaths.familySyncPreferenceSnapshot
        )
        let familySyncJournalRepository = LocalJSONFamilySyncJournalRepository(
            snapshotURL: dataPaths.familySyncJournalSnapshot
        )
        let familySyncApplyTransactionRepository =
            LocalJSONFamilySyncApplyTransactionRepository(
                snapshotURL: dataPaths.familySyncApplyTransactionsSnapshot
            )
        let profileDataEraser = RepositoryProfileDataEraser(
            profileRepository: profileRepository,
            wordPoolRepository: wordPoolRepository,
            practiceSettingsRepository: practiceSettingsRepository,
            learningRecordRepository: learningRecordRepository,
            dailyQuestRepository: dailyQuestRepository,
            childSessionRepository: childSessionRepository,
            voiceprintRepository: voiceprintRepository,
            handwritingPreferenceRemover: handwritingPreferenceRemover
        )
        let syncStore = RepositoryFamilySyncRecordStore(
            profileRepository: profileRepository,
            wordPoolRepository: wordPoolRepository,
            practiceSettingsRepository: practiceSettingsRepository,
            learningRepository: learningRecordRepository,
            dailyQuestRepository: dailyQuestRepository,
            tombstoneRepository: tombstoneRepository,
            applyTransactionRepository: familySyncApplyTransactionRepository,
            childSessionRepository: childSessionRepository,
            voiceprintRepository: voiceprintRepository,
            handwritingPreferenceRemover: handwritingPreferenceRemover,
            mutationGate: profileMutationGate,
            excludedProfileIDs: {
                guard
                    let state = try await firstRunOnboardingRepository.state(),
                    state.status == .pending,
                    let pendingProfileID = state.pendingCreatedProfileID
                else {
                    return []
                }
                return [pendingProfileID]
            },
            deviceID: deviceID,
            clock: clock
        )

        // Rebuild the process-local terminal admission fence from the durable
        // privacy authority before crash replay or any ordinary repository
        // mutation can run.
        let deletionTombstones = try await tombstoneRepository.tombstones()
        for tombstone in deletionTombstones {
            await profileMutationGate.seal(tombstone.profileID)
        }

        // Finish an accepted remote batch before any Profile snapshot is read
        // for onboarding or SwiftUI. A failed replay keeps the exact pending
        // bytes and fails bootstrap closed instead of showing partial state.
        try await syncStore.replayPendingApplyTransactions()

        try await recoverPendingProfileDeletions(
            tombstoneRepository: tombstoneRepository,
            profileRepository: profileRepository,
            wordPoolRepository: wordPoolRepository,
            practiceSettingsRepository: practiceSettingsRepository,
            learningRecordRepository: learningRecordRepository,
            dailyQuestRepository: dailyQuestRepository,
            childSessionRepository: childSessionRepository,
            voiceprintRepository: voiceprintRepository,
            handwritingPreferenceRemover: handwritingPreferenceRemover,
            mutationGate: profileMutationGate
        )

        let existingProfiles = try await profileRepository.profiles()
        let firstRunOnboardingPurpose = try await prepareFirstRunOnboarding(
            repository: firstRunOnboardingRepository,
            existingProfiles: existingProfiles
        )
        let firstRunState = try await firstRunOnboardingRepository.state()
        if firstRunState?.discoveryResetPhase != nil {
            // A legacy Find flow can relaunch after the iCloud account has
            // changed. Persist opt-out before the environment exposes remote
            // notification/connectivity handlers, then suspend any transport
            // generation retained by this process. Find will explicitly
            // re-confirm the current account before enabling sync again.
            try await familySyncPreferenceRepository.setEnabled(
                false,
                updatedAt: clock.now
            )
            await familySyncTransport.suspend()
        }
        let firstRunProfileIntent = firstRunState?.profileIntent
        let firstRunPendingCreatedProfileID =
            firstRunState?.pendingCreatedProfileID
        let requiresFirstRunOnboarding = firstRunOnboardingPurpose != nil
        // Keep first-run actions closed until the application view completes
        // its initial foreground revalidation. Durable repository gates remain
        // authoritative across relaunches; this fence covers the same-process
        // window before their asynchronous write begins.
        let firstRunDiscoveryAdmissionGate =
            FirstRunDiscoveryAdmissionGate(
                initiallyClosed: requiresFirstRunOnboarding
            )
        // Seed only a genuinely new installation. Once a family has durable
        // deletion history, an empty Profile repository is intentional and
        // must remain empty until someone explicitly creates a new child.
        let seedProfile: KidProfile?
        let currentDeletionTombstones = try await tombstoneRepository.tombstones()
        if existingProfiles.isEmpty,
            !profileSnapshotExistedAtStart,
            currentDeletionTombstones.isEmpty,
            familySyncTransport.initialProfilePolicy == .seedLocalProfile
        {
            seedProfile = try await seedingProfile(
                tombstoneRepository: tombstoneRepository
            )
        } else {
            seedProfile = nil
        }
        let profilesToValidate =
            existingProfiles.isEmpty
            ? seedProfile.map { [$0] } ?? []
            : existingProfiles
        try await validateWordPool(
            wordPoolRepository,
            profiles: profilesToValidate
        )
        try await validateLearningRecords(
            learningRecordRepository,
            profiles: profilesToValidate
        )
        try await validateDailyQuests(
            dailyQuestRepository,
            profiles: profilesToValidate
        )
        let profilesMissingSettings = try await profilesMissingSettings(
            in: practiceSettingsRepository,
            profiles: profilesToValidate
        )
        try validateDefaultProfileSeeding(
            existingProfiles: existingProfiles,
            dataPaths: dataPaths,
            firstRunState: firstRunState
        )
        let profiles = try await loadOrCreateProfiles(
            existingProfiles: existingProfiles,
            seedProfile: seedProfile,
            in: profileRepository
        )
        try await seedDefaultSettings(
            in: practiceSettingsRepository,
            profiles: profilesMissingSettings
        )
        try await migrateLegacyHandwritingPreferences(
            for: profiles,
            in: practiceSettingsRepository,
            preferenceStore: handwritingPreferenceRemover
        )
        let lastSelectedProfileID = await validatedLastSelectedProfileID(
            in: childSessionRepository,
            profiles: profiles
        )

        let familySyncCoordinator = LocalFirstFamilySyncCoordinator(
            store: syncStore,
            transport: familySyncTransport,
            preferenceRepository: familySyncPreferenceRepository,
            journalRepository: familySyncJournalRepository,
            profileDeletionRepository: tombstoneRepository,
            deviceID: deviceID,
            clock: clock
        )
        let familySyncCanonicalRecovery =
            CanonicalFamilySyncRecoveryCoordinator(
                store: syncStore,
                transport: familySyncTransport,
                journal: familySyncJournalRepository,
                installationID: deviceID,
                clock: clock
            )
        let guardianStore = RepositoryGuardianFamilyStore(
            profiles: profiles,
            selectedProfileID: lastSelectedProfileID,
            profileRepository: profileRepository,
            wordPoolRepository: wordPoolRepository,
            practiceSettingsRepository: practiceSettingsRepository,
            learningRecordRepository: learningRecordRepository,
            dailyQuestRepository: dailyQuestRepository,
            tombstoneRepository: tombstoneRepository,
            childSessionRepository: childSessionRepository,
            voiceprintRepository: voiceprintRepository,
            handwritingPreferenceRemover: handwritingPreferenceRemover,
            mutationGate: profileMutationGate,
            teacherAudioPreparer: teacherAudioPreparer,
            onLocalMutation: { _ in
                Task {
                    _ = await familySyncCoordinator.synchronize(
                        trigger: .localMutation
                    )
                }
            },
            clock: clock,
            timeZone: timeZone
        )
        let notificationReconciler = notificationScheduler.map { scheduler in
            ProductionLearningNotificationReconciler(
                scheduler: scheduler,
                profileRepository: profileRepository,
                profileDeletionRepository: tombstoneRepository,
                wordPoolRepository: wordPoolRepository,
                practiceSettingsRepository: practiceSettingsRepository,
                learningRecordRepository: learningRecordRepository,
                dailyQuestRepository: dailyQuestRepository,
                familySyncCoordinator: familySyncCoordinator,
                profileMutationGate: profileMutationGate,
                clock: clock,
                timeZone: timeZone
            )
        }
        return ProductionApplicationEnvironment(
            profiles: profiles,
            profileRepository: profileRepository,
            wordPoolRepository: wordPoolRepository,
            learningRecordRepository: learningRecordRepository,
            practiceSettingsRepository: practiceSettingsRepository,
            dailyQuestRepository: dailyQuestRepository,
            childSessionRepository: childSessionRepository,
            profileDataEraser: profileDataEraser,
            lastSelectedProfileID: lastSelectedProfileID,
            guardianStore: guardianStore,
            familySyncCoordinator: familySyncCoordinator,
            familySyncCanonicalRecovery: familySyncCanonicalRecovery,
            familySyncTransport: familySyncTransport,
            familySyncJournalRepository: familySyncJournalRepository,
            familySyncApplyTransactionRepository:
                familySyncApplyTransactionRepository,
            tombstoneRepository: tombstoneRepository,
            profileMutationGate: profileMutationGate,
            notificationReconciler: notificationReconciler,
            firstRunOnboardingRepository: firstRunOnboardingRepository,
            firstRunDiscoveryAdmissionGate:
                firstRunDiscoveryAdmissionGate,
            firstRunOnboardingPurpose: firstRunOnboardingPurpose,
            firstRunProfileIntent: firstRunProfileIntent,
            firstRunPendingCreatedProfileID: firstRunPendingCreatedProfileID,
            requiresFirstRunOnboarding: requiresFirstRunOnboarding,
            clock: clock,
            timeZone: timeZone,
            dataPaths: dataPaths
        )
    }

    private func resetRetainedVoiceprintsForFreshInstallationIfNeeded(
        dataDirectoryExistedAtStart: Bool
    ) async throws {
        guard !dataDirectoryExistedAtStart, let voiceprintRepository else {
            return
        }
        guard
            let resetter =
                voiceprintRepository as? any FreshInstallationVoiceprintResetting
        else {
            throw ApplicationBootstrapError
                .freshInstallationVoiceprintResetUnavailable
        }

        // This must stay before loadOrCreateDeviceID and every repository
        // write. If Keychain rejects the reset, the absent directory remains
        // absent so Retry performs the reset again instead of classifying the
        // failed attempt as an existing installation.
        try await resetter.resetVoiceprintsForFreshInstallation()
    }

    private func prepareFirstRunOnboarding(
        repository: LocalFirstRunOnboardingRepository,
        existingProfiles: [KidProfile]
    ) async throws -> FirstRunOnboardingPurpose? {
        if let state = try await repository.state() {
            let hasCurrentConsent =
                state.status == .completed
                && state.consentVersion
                    == FirstRunOnboardingSubmission.currentConsentVersion
            if hasCurrentConsent {
                return nil
            }
            if state.status == .pending, let purpose = state.purpose {
                let resolvedPurpose =
                    FirstRunOnboardingProfileSelection.resolvedPurpose(
                        purpose,
                        in: existingProfiles
                    )
                if resolvedPurpose != purpose {
                    try await repository.normalizePendingPurpose(
                        resolvedPurpose
                    )
                }
                return resolvedPurpose
            }
            if state.status == .pending {
                // Legacy pending markers predate the purpose field and came
                // from an interrupted first-run setup. Preserve that intent
                // instead of treating the seeded default profile as an old
                // install that only needs a consent refresh.
                try await repository.markPending(
                    startedAt: clock.now,
                    purpose: .fullSetup
                )
                return .fullSetup
            }
        }

        // Missing or stale consent always reopens the parent flow without
        // rewriting any existing profile or learning data during migration.
        let purpose = onboardingPurpose(for: existingProfiles)
        try await repository.markPending(startedAt: clock.now, purpose: purpose)
        return purpose
    }

    private func onboardingPurpose(
        for existingProfiles: [KidProfile]
    ) -> FirstRunOnboardingPurpose {
        existingProfiles.isEmpty ? .fullSetup : .consentRefresh
    }

    private func recoverPendingProfileDeletions(
        tombstoneRepository: any ProfileDeletionTombstoneRepository,
        profileRepository: any KidProfileRepository,
        wordPoolRepository: any WordPoolRepository,
        practiceSettingsRepository: any PracticeSettingsRepository,
        learningRecordRepository: any ProfileLearningRecordRepository,
        dailyQuestRepository: any DailyQuestHistoryRepository,
        childSessionRepository: LocalJSONChildSessionRepository,
        voiceprintRepository: (any DeviceVoiceprintRepository)?,
        handwritingPreferenceRemover: any HandwritingPreferenceRemoving,
        mutationGate: ProfileScopedMutationGate
    ) async throws {
        // Sweep every tombstone, including committed records from older builds.
        // This is idempotent and removes any Profile bytes that a process crash
        // or historical best-effort cleanup left behind after commit.
        let tombstones = try await tombstoneRepository.tombstones()
        let pendingProfileIDs = Set(
            try await tombstoneRepository.pendingTombstones().map(\.profileID)
        )
        for tombstone in tombstones {
            let profileID = tombstone.profileID
            try await withProfileScopedMutationLease(
                mutationGate,
                for: profileID,
                allowingTerminal: true,
                isolation: mutationGate
            ) {
                try await voiceprintRepository?.delete(for: profileID)
                handwritingPreferenceRemover.remove(for: profileID)
                try await wordPoolRepository.deleteAll(for: profileID)
                try await practiceSettingsRepository.delete(for: profileID)
                try await learningRecordRepository.deleteLearningRecords(for: profileID)
                try await dailyQuestRepository.deleteHistory(for: profileID)
                try await profileRepository.delete(id: profileID)
                if try await childSessionRepository.lastSelectedProfileID() == profileID {
                    try await childSessionRepository.clearLastSelectedProfileID()
                }
                if pendingProfileIDs.contains(profileID) {
                    try await tombstoneRepository.markCommitted(for: profileID)
                }
            }
        }
    }

    private func seedingProfile(
        tombstoneRepository: any ProfileDeletionTombstoneRepository
    ) async throws -> KidProfile {
        guard try await tombstoneRepository.tombstone(for: defaultProfile.id) != nil else {
            return defaultProfile
        }
        return KidProfile(
            displayName: defaultProfile.displayName,
            avatar: defaultProfile.avatar,
            selectedWorld: defaultProfile.selectedWorld,
            starterWorld: defaultProfile.starterWorld,
            guardianUnlockedWorlds: defaultProfile.guardianUnlockedWorlds,
            selectedCartoonIconAssetID: defaultProfile.selectedCartoonIconAssetID,
            selectedTreasureAvatar: defaultProfile.selectedTreasureAvatar,
            schoolGrade: defaultProfile.schoolGrade,
            ageYears: defaultProfile.ageYears,
            voiceprintStatus: .notEnrolled,
            createdAt: clock.now
        )
    }

    private func loadOrCreateDeviceID(at url: URL) throws -> String {
        if let value = try? String(contentsOf: url, encoding: .utf8)
            .trimmingCharacters(in: .whitespacesAndNewlines),
            !value.isEmpty
        {
            return value
        }
        let value = UUID().uuidString
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try Data(value.utf8).write(to: url, options: .atomic)
        return value
    }

    private func migrateLegacyHandwritingPreferences(
        for profiles: [KidProfile],
        in repository: any PracticeSettingsRepository,
        preferenceStore: any HandwritingPreferenceRemoving
    ) async throws {
        guard
            let migrator = preferenceStore
                as? any LegacyHandwritingPreferenceMigrating
        else { return }

        for profile in profiles {
            guard let legacyTool = migrator.consumeLegacyTool(for: profile.id)
            else { continue }
            let current =
                try await repository.settings(for: profile.id)
                ?? .defaults(for: profile.id)
            // A value already written into the synchronized settings is newer
            // than the one-way UserDefaults residue.
            guard current.interface.selectedHandwritingTool == .pencil,
                legacyTool != .pencil
            else { continue }
            try await repository.save(
                ProfilePracticeSettings(
                    profileID: current.profileID,
                    read: current.read,
                    write: current.write,
                    audio: current.audio,
                    notifications: current.notifications,
                    interface: PracticeInterfacePreferences(
                        leftHandedLayoutEnabled:
                            current.interface.leftHandedLayoutEnabled,
                        selectedHandwritingTool: legacyTool
                    ),
                    wordRecommendationMode: current.wordRecommendationMode
                )
            )
        }
    }

    /// Rejects files created by a newer app before bootstrap can write a
    /// device identity, replay a transaction, recover a tombstone, or update
    /// onboarding. Older supported schemas continue into their repository's
    /// explicit migration path.
    private func preflightSnapshotSchemas(
        at paths: ApplicationDataPaths
    ) throws {
        let requirements = [
            SnapshotSchemaRequirement(
                store: .profiles,
                url: paths.profilesSnapshot,
                supportedVersion: KidProfileSnapshot.currentSchemaVersion
            ),
            SnapshotSchemaRequirement(
                store: .wordPool,
                url: paths.wordPoolSnapshot,
                supportedVersion: WordPoolSnapshot.currentSchemaVersion
            ),
            SnapshotSchemaRequirement(
                store: .learningRecords,
                url: paths.learningRecordsSnapshot,
                supportedVersion: LearningRecordSnapshot.currentSchemaVersion
            ),
            SnapshotSchemaRequirement(
                store: .practiceSettings,
                url: paths.practiceSettingsSnapshot,
                supportedVersion: PracticeSettingsSnapshot.currentSchemaVersion
            ),
            SnapshotSchemaRequirement(
                store: .dailyQuests,
                url: paths.dailyQuestsSnapshot,
                supportedVersion: DailyQuestSnapshot.currentSchemaVersion
            ),
            SnapshotSchemaRequirement(
                store: .childSession,
                url: paths.childSessionSnapshot,
                supportedVersion: ChildSessionSnapshot.currentSchemaVersion,
                rejectsInvalidEnvelope: false
            ),
            SnapshotSchemaRequirement(
                store: .profileDeletionTombstones,
                url: paths.profileDeletionTombstonesSnapshot,
                supportedVersion:
                    LocalJSONProfileDeletionTombstoneRepository.currentSchemaVersion
            ),
            SnapshotSchemaRequirement(
                store: .firstRunOnboarding,
                url: paths.firstRunOnboardingSnapshot,
                supportedVersion: FirstRunOnboardingState.currentSchemaVersion
            ),
            SnapshotSchemaRequirement(
                store: .familySyncPreference,
                url: paths.familySyncPreferenceSnapshot,
                supportedVersion:
                    FamilySyncPreferenceSnapshot.currentSchemaVersion,
                rejectsInvalidEnvelope: false
            ),
            SnapshotSchemaRequirement(
                store: .familySyncJournal,
                url: paths.familySyncJournalSnapshot,
                supportedVersion: FamilySyncJournalSnapshot.currentSchemaVersion
            ),
            SnapshotSchemaRequirement(
                store: .familySyncApplyTransactions,
                url: paths.familySyncApplyTransactionsSnapshot,
                supportedVersion:
                    FamilySyncApplyTransactionSnapshot.currentSchemaVersion
            ),
        ]

        for requirement in requirements {
            try preflight(requirement)
        }
    }

    private func preflight(
        _ requirement: SnapshotSchemaRequirement
    ) throws {
        guard FileManager.default.fileExists(atPath: requirement.url.path) else {
            return
        }
        let data: Data
        do {
            data = try Data(contentsOf: requirement.url)
        } catch {
            throw ApplicationBootstrapError.snapshotReadFailed(
                store: requirement.store
            )
        }
        let envelope: SnapshotSchemaEnvelope
        do {
            envelope = try JSONDecoder().decode(
                SnapshotSchemaEnvelope.self,
                from: data
            )
        } catch {
            guard requirement.rejectsInvalidEnvelope else { return }
            throw ApplicationBootstrapError.invalidSnapshotEnvelope(
                store: requirement.store
            )
        }
        guard envelope.schemaVersion > 0 else {
            throw ApplicationBootstrapError.invalidSnapshotEnvelope(
                store: requirement.store
            )
        }
        guard envelope.schemaVersion <= requirement.supportedVersion else {
            throw ApplicationBootstrapError.requiresNewerApp(
                store: requirement.store,
                found: envelope.schemaVersion,
                supported: requirement.supportedVersion
            )
        }
    }

    private func validatedLastSelectedProfileID(
        in repository: LocalJSONChildSessionRepository,
        profiles: [KidProfile]
    ) async -> ProfileID? {
        guard let profileID = try? await repository.lastSelectedProfileID() else {
            return nil
        }
        guard profiles.contains(where: { $0.id == profileID }) else {
            // This file is only a convenience pointer. A deleted child must
            // fall back to the chooser, and a failed cleanup must not block
            // the rest of the child's durable learning data.
            try? await repository.clearLastSelectedProfileID()
            return nil
        }
        return profileID
    }

    private func loadOrCreateProfiles(
        existingProfiles: [KidProfile],
        seedProfile: KidProfile?,
        in repository: LocalJSONKidProfileRepository
    ) async throws -> [KidProfile] {
        guard existingProfiles.isEmpty, let seedProfile else {
            return existingProfiles
        }

        try await repository.save(seedProfile)
        let savedProfiles = try await repository.profiles()
        guard savedProfiles.contains(where: { $0.id == seedProfile.id }) else {
            throw ApplicationBootstrapError.defaultProfileWasNotPersisted(
                seedProfile.id
            )
        }
        return savedProfiles
    }

    private func validateWordPool(
        _ repository: LocalJSONWordPoolRepository,
        profiles: [KidProfile]
    ) async throws {
        for profile in profiles {
            async let readEntries = repository.entries(
                for: profile.id,
                learningMode: .read,
                includingInactive: true
            )
            async let writeEntries = repository.entries(
                for: profile.id,
                learningMode: .write,
                includingInactive: true
            )
            _ = try await (readEntries, writeEntries)
        }
    }

    private func validateLearningRecords(
        _ repository: LocalJSONLearningRecordRepository,
        profiles: [KidProfile]
    ) async throws {
        for profile in profiles {
            _ = try await repository.attempts(
                for: profile.id,
                wordPromptID: nil
            )
        }
    }

    private func profilesMissingSettings(
        in repository: LocalJSONPracticeSettingsRepository,
        profiles: [KidProfile]
    ) async throws -> [KidProfile] {
        var missingSettings: [KidProfile] = []
        for profile in profiles {
            let settings = try await repository.settings(for: profile.id)
            if settings == nil {
                missingSettings.append(profile)
            }
        }
        return missingSettings
    }

    private func validateDailyQuests(
        _ repository: LocalJSONDailyQuestRepository,
        profiles: [KidProfile]
    ) async throws {
        let localDay = LocalDay(date: clock.now, timeZone: timeZone)
        for profile in profiles {
            for mode in LearningMode.allCases {
                _ = try await repository.state(
                    for: DailyQuestKey(
                        profileID: profile.id,
                        learningMode: mode,
                        localDay: localDay
                    )
                )
            }
        }
    }

    private func seedDefaultSettings(
        in repository: LocalJSONPracticeSettingsRepository,
        profiles: [KidProfile]
    ) async throws {
        for profile in profiles {
            try await repository.save(.defaults(for: profile.id))
        }
    }

    private func validateDefaultProfileSeeding(
        existingProfiles: [KidProfile],
        dataPaths: ApplicationDataPaths,
        firstRunState: FirstRunOnboardingState?
    ) throws {
        guard existingProfiles.isEmpty else { return }
        guard
            !FileManager.default.fileExists(
                atPath: dataPaths.profilesSnapshot.path
            )
        else {
            return
        }
        let dependentSnapshots = [
            dataPaths.wordPoolSnapshot,
            dataPaths.learningRecordsSnapshot,
            dataPaths.practiceSettingsSnapshot,
            dataPaths.dailyQuestsSnapshot,
        ]
        guard
            !dependentSnapshots.contains(where: {
                FileManager.default.fileExists(atPath: $0.path)
            })
        else {
            if try isRecoverablePendingProfileCreation(
                state: firstRunState,
                dataPaths: dataPaths
            ) {
                return
            }
            throw ApplicationBootstrapError
                .profileSnapshotMissingWithDependentData
        }
    }

    private func isRecoverablePendingProfileCreation(
        state: FirstRunOnboardingState?,
        dataPaths: ApplicationDataPaths
    ) throws -> Bool {
        guard state?.status == .pending,
            state?.profileIntent == .createNew,
            let pendingProfileID = state?.pendingCreatedProfileID
        else {
            return false
        }
        // Only the one write boundary produced by first-run createProfile is
        // recoverable: exact default settings for the durably reserved UUID,
        // with no word, learning, or quest bytes. Every broader orphan shape
        // remains a saved-data error rather than being guessed or erased.
        guard
            !FileManager.default.fileExists(
                atPath: dataPaths.wordPoolSnapshot.path
            ),
            !FileManager.default.fileExists(
                atPath: dataPaths.learningRecordsSnapshot.path
            ),
            !FileManager.default.fileExists(
                atPath: dataPaths.dailyQuestsSnapshot.path
            ),
            FileManager.default.fileExists(
                atPath: dataPaths.practiceSettingsSnapshot.path
            )
        else {
            return false
        }
        let snapshot = try JSONDecoder().decode(
            PracticeSettingsSnapshot.self,
            from: Data(contentsOf: dataPaths.practiceSettingsSnapshot)
        )
        return snapshot.schemaVersion
            == PracticeSettingsSnapshot.currentSchemaVersion
            && snapshot.settings == [.defaults(for: pendingProfileID)]
    }
}

private struct SnapshotSchemaEnvelope: Decodable {
    let schemaVersion: Int
}

private struct SnapshotSchemaRequirement {
    let store: ApplicationSnapshotStore
    let url: URL
    let supportedVersion: Int
    let rejectsInvalidEnvelope: Bool

    init(
        store: ApplicationSnapshotStore,
        url: URL,
        supportedVersion: Int,
        rejectsInvalidEnvelope: Bool = true
    ) {
        self.store = store
        self.url = url
        self.supportedVersion = supportedVersion
        self.rejectsInvalidEnvelope = rejectsInvalidEnvelope
    }
}

actor ProductionLearningNotificationReconciler {
    private let scheduler: any LearningNotificationScheduling
    private let profileRepository: any KidProfileRepository
    private let profileDeletionRepository: (any ProfileDeletionTombstoneRepository)?
    private let wordPoolRepository: any WordPoolRepository
    private let practiceSettingsRepository: any PracticeSettingsRepository
    private let learningRecordRepository: (any AttemptEventRepository & WordProgressRepository)?
    private let dailyQuestRepository: any DailyQuestRepository
    private let familySyncCoordinator: any FamilySyncCoordinating
    private let profileMutationGate: ProfileScopedMutationGate?
    private let clock: any AppClock
    private let timeZone: TimeZone

    init(
        scheduler: any LearningNotificationScheduling,
        profileRepository: any KidProfileRepository,
        profileDeletionRepository:
            (any ProfileDeletionTombstoneRepository)? = nil,
        wordPoolRepository: any WordPoolRepository,
        practiceSettingsRepository: any PracticeSettingsRepository,
        learningRecordRepository:
            (any AttemptEventRepository & WordProgressRepository)? = nil,
        dailyQuestRepository: any DailyQuestRepository,
        familySyncCoordinator: any FamilySyncCoordinating,
        profileMutationGate: ProfileScopedMutationGate? = nil,
        clock: any AppClock,
        timeZone: TimeZone
    ) {
        self.scheduler = scheduler
        self.profileRepository = profileRepository
        self.profileDeletionRepository = profileDeletionRepository
        self.wordPoolRepository = wordPoolRepository
        self.practiceSettingsRepository = practiceSettingsRepository
        self.learningRecordRepository = learningRecordRepository
        self.dailyQuestRepository = dailyQuestRepository
        self.familySyncCoordinator = familySyncCoordinator
        self.profileMutationGate = profileMutationGate
        self.clock = clock
        self.timeZone = timeZone
    }

    /// Runtime refreshes never prompt. Permission is requested only from the
    /// explicit Guardian settings save path.
    func reconcileAll() async {
        try? await withAllProfilesCommittedRead(profileMutationGate) {
            await reconcileCommittedGeneration()
        }
    }

    private func reconcileCommittedGeneration() async {
        let deletedProfileIDs: Set<ProfileID>
        if let profileDeletionRepository {
            // Tombstones are the durable deletion authority. Clear scheduled
            // notifications even when a remote deletion has not yet finished
            // every local purge step, and never rebuild them from stale rows.
            guard
                let tombstones =
                    try? await profileDeletionRepository
                    .tombstones()
            else { return }
            deletedProfileIDs = Set(tombstones.map(\.profileID))
            for profileID in deletedProfileIDs {
                await scheduler.removeNotifications(for: profileID)
            }
        } else {
            deletedProfileIDs = []
        }

        guard await scheduler.authorizationStatus() == .authorized else { return }
        guard let profiles = try? await profileRepository.profiles() else { return }
        let syncStatus = await familySyncCoordinator.status()
        let hasSyncFailure: Bool
        if case .failed = syncStatus {
            hasSyncFailure = true
        } else {
            hasSyncFailure = false
        }
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        let day = LocalDay(date: clock.now, timeZone: timeZone)

        for profile in profiles where !deletedProfileIDs.contains(profile.id) {
            guard
                let settings = try? await practiceSettingsRepository.settings(
                    for: profile.id
                )
            else { continue }
            if !settings.notifications.hasEnabledNotifications {
                await scheduler.removeNotifications(for: profile.id)
                continue
            }
            do {
                let attentionCount = try await RepositoryGuardianWordStore(
                    profile: profile,
                    wordPoolRepository: wordPoolRepository,
                    practiceSettingsRepository: practiceSettingsRepository,
                    learningRecordRepository: learningRecordRepository,
                    dailyQuestRepository: dailyQuestRepository,
                    clock: clock,
                    timeZone: timeZone
                ).dashboardSnapshot().needsAttention.count
                async let readEntries = wordPoolRepository.entries(
                    for: profile.id,
                    learningMode: .read,
                    includingInactive: false
                )
                async let writeEntries = wordPoolRepository.entries(
                    for: profile.id,
                    learningMode: .write,
                    includingInactive: false
                )
                async let readCompletions = dailyQuestRepository.completions(
                    for: DailyQuestKey(
                        profileID: profile.id,
                        learningMode: .read,
                        localDay: day
                    )
                )
                async let writeCompletions = dailyQuestRepository.completions(
                    for: DailyQuestKey(
                        profileID: profile.id,
                        learningMode: .write,
                        localDay: day
                    )
                )
                let (read, write, readRuns, writeRuns) = try await (
                    readEntries,
                    writeEntries,
                    readCompletions,
                    writeCompletions
                )
                let context = LearningNotificationContext(
                    profileID: profile.id,
                    readPoolCount: read.count,
                    writePoolCount: write.count,
                    completedQuestCountToday: readRuns.count + writeRuns.count,
                    hasPendingSyncFailure: hasSyncFailure,
                    weeklyAttentionCount: attentionCount
                )
                try await scheduler.reconcile(
                    preferences: settings.notifications,
                    context: context,
                    calendar: calendar
                )
            } catch {
                continue
            }
        }
    }
}

struct ApplicationBootstrapFailure: Equatable, Sendable {
    let title: String
    let message: String
    let debugDetails: String

    init(error: any Error) {
        switch error {
        case ApplicationBootstrapError.requiresNewerApp(
            let
                store,
            let
                found,
            let
                supported
        ):
            title = "Update Tada Words"
            message =
                "Your saved data is safe, but this app is older than the data on this device. Install the latest Tada Words build, then try again."
            debugDetails =
                "requires-newer-app:\(store.rawValue):\(found):\(supported)"
        case ApplicationBootstrapError.snapshotReadFailed(let store):
            title = "Saved data couldn’t open"
            message =
                "Tada Words did not replace or reset any files. Check that storage is available, then try again."
            debugDetails = "snapshot-read-failed:\(store.rawValue)"
        case ApplicationBootstrapError.invalidSnapshotEnvelope(let store):
            title = "Saved data couldn’t open"
            message =
                "Tada Words kept the original file unchanged. A parent can retry after updating the app."
            debugDetails = "invalid-snapshot-envelope:\(store.rawValue)"
        default:
            title = "Saved data couldn’t open"
            message =
                "Tada Words did not replace or reset any files. Check that storage is available, then try again."
            debugDetails = String(reflecting: type(of: error))
        }
    }
}

enum ApplicationBootstrapState {
    case idle
    case loading
    case ready(ProductionApplicationEnvironment)
    case failed(ApplicationBootstrapFailure)
}

@MainActor
final class ApplicationBootstrapModel: ObservableObject {
    @Published private(set) var state: ApplicationBootstrapState = .idle

    private let bootstrapper: any ApplicationBootstrapping
    private let logger = Logger(
        subsystem: Bundle.main.bundleIdentifier ?? "app.tadawords.app",
        category: "ApplicationBootstrap"
    )
    private var loadTask: Task<Void, Never>?
    private var activeLoadID: UUID?

    init(bootstrapper: any ApplicationBootstrapping) {
        self.bootstrapper = bootstrapper
    }

    func startIfNeeded() {
        guard case .idle = state else { return }
        startLoading()
    }

    func retry() {
        guard case .failed = state else { return }
        startLoading()
    }

    func loadAndWait() async {
        loadTask?.cancel()
        let loadID = beginLoading()
        await performLoad(loadID: loadID)
    }

    private func startLoading() {
        loadTask?.cancel()
        let loadID = beginLoading()
        loadTask = Task { [weak self] in
            await self?.performLoad(loadID: loadID)
        }
    }

    private func beginLoading() -> UUID {
        let loadID = UUID()
        activeLoadID = loadID
        state = .loading
        return loadID
    }

    private func performLoad(loadID: UUID) async {
        do {
            let environment = try await bootstrapper.bootstrap()
            try Task.checkCancellation()
            guard activeLoadID == loadID else { return }
            activeLoadID = nil
            loadTask = nil
            state = .ready(environment)
        } catch is CancellationError {
            return
        } catch {
            guard activeLoadID == loadID else { return }
            activeLoadID = nil
            loadTask = nil
            let failure = ApplicationBootstrapFailure(error: error)
            logger.error(
                "Bootstrap failed: \(failure.debugDetails, privacy: .public)"
            )
            state = .failed(failure)
        }
    }
}

struct UnavailableApplicationBootstrapper: ApplicationBootstrapping {
    func bootstrap() async throws -> ProductionApplicationEnvironment {
        throw UnavailableApplicationBootstrapError()
    }
}

private struct UnavailableApplicationBootstrapError: Error {}

actor LocalOnlyFamilySyncTransport: FamilySyncTransport {
    nonisolated let capability = FamilySyncCapability.deviceOnly

    func availability() async -> FamilySyncAvailability { .deviceOnly }

    func prepareProfileZone(_ profileID: ProfileID) async throws {
        _ = profileID
    }

    func fetchRecords(
        for profileID: ProfileID
    ) async throws -> [FamilySyncRecord] {
        _ = profileID
        return []
    }

    func push(
        _ records: [FamilySyncRecord],
        for profileID: ProfileID
    ) async throws {
        _ = records
        _ = profileID
    }

    func createShare(for profileID: ProfileID) async throws -> URL {
        _ = profileID
        throw LocalOnlyFamilySyncError.unavailable
    }

    func acceptShare(at url: URL) async throws -> ProfileID {
        _ = url
        throw LocalOnlyFamilySyncError.unavailable
    }
}

private enum LocalOnlyFamilySyncError: Error {
    case unavailable
}
