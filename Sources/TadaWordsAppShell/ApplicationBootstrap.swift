import Foundation
import SwiftUI
import TadaWordsContent
import TadaWordsDomain
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
    let lastSelectedProfileID: ProfileID?
    let guardianStore: RepositoryGuardianFamilyStore
    let familySyncCoordinator: LocalFirstFamilySyncCoordinator
    let tombstoneRepository: LocalJSONProfileDeletionTombstoneRepository
    let notificationReconciler: ProductionLearningNotificationReconciler?
    let firstRunOnboardingRepository: LocalFirstRunOnboardingRepository
    let firstRunOnboardingPurpose: FirstRunOnboardingPurpose?
    let requiresFirstRunOnboarding: Bool
    let clock: any AppClock
    let timeZone: TimeZone
    let dataPaths: ApplicationDataPaths
}

protocol ApplicationBootstrapping: Sendable {
    func bootstrap() async throws -> ProductionApplicationEnvironment
}

enum ApplicationBootstrapError: Error, Equatable, Sendable {
    case defaultProfileWasNotPersisted(ProfileID)
    case profileSnapshotMissingWithDependentData
}

struct ProductionApplicationBootstrapper: ApplicationBootstrapping, Sendable {
    private let applicationSupportDirectory: @Sendable () throws -> URL
    private let defaultProfile: KidProfile
    private let clock: any AppClock
    private let timeZone: TimeZone
    private let familySyncTransport: any FamilySyncTransport
    private let notificationScheduler: (any LearningNotificationScheduling)?

    init(
        applicationSupportDirectory: @escaping @Sendable () throws -> URL,
        defaultProfile: KidProfile,
        clock: any AppClock,
        timeZone: TimeZone,
        familySyncTransport: any FamilySyncTransport = LocalOnlyFamilySyncTransport(),
        notificationScheduler: (any LearningNotificationScheduling)? = nil
    ) {
        self.applicationSupportDirectory = applicationSupportDirectory
        self.defaultProfile = defaultProfile
        self.clock = clock
        self.timeZone = timeZone
        self.familySyncTransport = familySyncTransport
        self.notificationScheduler = notificationScheduler
    }

    func bootstrap() async throws -> ProductionApplicationEnvironment {
        let dataPaths = ApplicationDataPaths(
            applicationSupportDirectory: try applicationSupportDirectory()
        )
        let profileRepository = LocalJSONKidProfileRepository(
            snapshotURL: dataPaths.profilesSnapshot
        )
        let wordPoolRepository = LocalJSONWordPoolRepository(
            snapshotURL: dataPaths.wordPoolSnapshot
        )
        let learningRecordRepository = LocalJSONLearningRecordRepository(
            snapshotURL: dataPaths.learningRecordsSnapshot
        )
        let practiceSettingsRepository = LocalJSONPracticeSettingsRepository(
            snapshotURL: dataPaths.practiceSettingsSnapshot
        )
        let dailyQuestRepository = LocalJSONDailyQuestRepository(
            snapshotURL: dataPaths.dailyQuestsSnapshot
        )
        let childSessionRepository = LocalJSONChildSessionRepository(
            snapshotURL: dataPaths.childSessionSnapshot
        )
        let tombstoneRepository = LocalJSONProfileDeletionTombstoneRepository(
            snapshotURL: dataPaths.profileDeletionTombstonesSnapshot
        )
        let firstRunOnboardingRepository = LocalFirstRunOnboardingRepository(
            snapshotURL: dataPaths.firstRunOnboardingSnapshot
        )
        let familySyncPreferenceRepository = LocalJSONFamilySyncPreferenceRepository(
            snapshotURL: dataPaths.familySyncPreferenceSnapshot
        )

        try await recoverPendingProfileDeletions(
            tombstoneRepository: tombstoneRepository,
            profileRepository: profileRepository,
            wordPoolRepository: wordPoolRepository,
            practiceSettingsRepository: practiceSettingsRepository,
            learningRecordRepository: learningRecordRepository,
            dailyQuestRepository: dailyQuestRepository,
            childSessionRepository: childSessionRepository
        )

        let existingProfiles = try await profileRepository.profiles()
        let firstRunOnboardingPurpose = try await prepareFirstRunOnboarding(
            repository: firstRunOnboardingRepository,
            existingProfiles: existingProfiles
        )
        let requiresFirstRunOnboarding = firstRunOnboardingPurpose != nil
        let seedProfile = try await seedingProfile(
            tombstoneRepository: tombstoneRepository
        )
        let profilesToValidate =
            existingProfiles.isEmpty
            ? [seedProfile]
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
            dataPaths: dataPaths
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
        let lastSelectedProfileID = await validatedLastSelectedProfileID(
            in: childSessionRepository,
            profiles: profiles
        )

        let guardianStore = RepositoryGuardianFamilyStore(
            profiles: profiles,
            profileRepository: profileRepository,
            wordPoolRepository: wordPoolRepository,
            practiceSettingsRepository: practiceSettingsRepository,
            learningRecordRepository: learningRecordRepository,
            dailyQuestRepository: dailyQuestRepository,
            tombstoneRepository: tombstoneRepository,
            childSessionRepository: childSessionRepository,
            clock: clock,
            timeZone: timeZone
        )
        let syncStore = RepositoryFamilySyncRecordStore(
            profileRepository: profileRepository,
            wordPoolRepository: wordPoolRepository,
            practiceSettingsRepository: practiceSettingsRepository,
            learningRepository: learningRecordRepository,
            dailyQuestRepository: dailyQuestRepository,
            tombstoneRepository: tombstoneRepository,
            deviceID: try loadOrCreateDeviceID(at: dataPaths.deviceIdentitySnapshot)
        )
        let familySyncCoordinator = LocalFirstFamilySyncCoordinator(
            store: syncStore,
            transport: familySyncTransport,
            preferenceRepository: familySyncPreferenceRepository,
            clock: clock
        )
        let notificationReconciler = notificationScheduler.map { scheduler in
            ProductionLearningNotificationReconciler(
                scheduler: scheduler,
                profileRepository: profileRepository,
                wordPoolRepository: wordPoolRepository,
                practiceSettingsRepository: practiceSettingsRepository,
                learningRecordRepository: learningRecordRepository,
                dailyQuestRepository: dailyQuestRepository,
                familySyncCoordinator: familySyncCoordinator,
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
            lastSelectedProfileID: lastSelectedProfileID,
            guardianStore: guardianStore,
            familySyncCoordinator: familySyncCoordinator,
            tombstoneRepository: tombstoneRepository,
            notificationReconciler: notificationReconciler,
            firstRunOnboardingRepository: firstRunOnboardingRepository,
            firstRunOnboardingPurpose: firstRunOnboardingPurpose,
            requiresFirstRunOnboarding: requiresFirstRunOnboarding,
            clock: clock,
            timeZone: timeZone,
            dataPaths: dataPaths
        )
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
                return purpose
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
        childSessionRepository: LocalJSONChildSessionRepository
    ) async throws {
        for tombstone in try await tombstoneRepository.pendingTombstones() {
            let profileID = tombstone.profileID
            try await wordPoolRepository.deleteAll(for: profileID)
            try await practiceSettingsRepository.delete(for: profileID)
            try await learningRecordRepository.deleteLearningRecords(for: profileID)
            try await dailyQuestRepository.deleteHistory(for: profileID)
            try await profileRepository.delete(id: profileID)
            if try await childSessionRepository.lastSelectedProfileID() == profileID {
                try await childSessionRepository.clearLastSelectedProfileID()
            }
            try await tombstoneRepository.markCommitted(for: profileID)
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
        seedProfile: KidProfile,
        in repository: LocalJSONKidProfileRepository
    ) async throws -> [KidProfile] {
        guard existingProfiles.isEmpty else { return existingProfiles }

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
        dataPaths: ApplicationDataPaths
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
            throw ApplicationBootstrapError
                .profileSnapshotMissingWithDependentData
        }
    }
}

actor ProductionLearningNotificationReconciler {
    private let scheduler: any LearningNotificationScheduling
    private let profileRepository: any KidProfileRepository
    private let wordPoolRepository: any WordPoolRepository
    private let practiceSettingsRepository: any PracticeSettingsRepository
    private let learningRecordRepository: (any AttemptEventRepository & WordProgressRepository)?
    private let dailyQuestRepository: any DailyQuestRepository
    private let familySyncCoordinator: any FamilySyncCoordinating
    private let clock: any AppClock
    private let timeZone: TimeZone

    init(
        scheduler: any LearningNotificationScheduling,
        profileRepository: any KidProfileRepository,
        wordPoolRepository: any WordPoolRepository,
        practiceSettingsRepository: any PracticeSettingsRepository,
        learningRecordRepository:
            (any AttemptEventRepository & WordProgressRepository)? = nil,
        dailyQuestRepository: any DailyQuestRepository,
        familySyncCoordinator: any FamilySyncCoordinating,
        clock: any AppClock,
        timeZone: TimeZone
    ) {
        self.scheduler = scheduler
        self.profileRepository = profileRepository
        self.wordPoolRepository = wordPoolRepository
        self.practiceSettingsRepository = practiceSettingsRepository
        self.learningRecordRepository = learningRecordRepository
        self.dailyQuestRepository = dailyQuestRepository
        self.familySyncCoordinator = familySyncCoordinator
        self.clock = clock
        self.timeZone = timeZone
    }

    /// Runtime refreshes never prompt. Permission is requested only from the
    /// explicit Guardian settings save path.
    func reconcileAll() async {
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

        for profile in profiles {
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
        title = "Saved data couldn’t open"
        message =
            "Tada Words did not replace or reset any files. Check that storage is available, then try again."
        debugDetails = String(describing: error)
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
            state = .failed(ApplicationBootstrapFailure(error: error))
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
