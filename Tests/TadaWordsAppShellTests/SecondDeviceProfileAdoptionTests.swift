import Foundation
import TadaWordsContent
import TadaWordsDomain
import TadaWordsGuardianFeatures
import XCTest

@testable import TadaWordsAppShell

final class SecondDeviceProfileAdoptionTests: XCTestCase {
    func testDiscoveryFirstBootstrapNeverPersistsRandomDefaultAcrossRelaunch()
        async throws
    {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let localDefault = profile(id: UUID(), name: "My Kid")
        let transport = DiscoveryTransport(
            availability: [.temporarilyUnavailable],
            remoteProfiles: []
        )

        let first = try await bootstrap(
            in: directory,
            defaultProfile: localDefault,
            transport: transport
        )
        let restarted = try await bootstrap(
            in: directory,
            defaultProfile: profile(id: UUID(), name: "Another Seed"),
            transport: transport
        )

        XCTAssertTrue(first.profiles.isEmpty)
        XCTAssertTrue(restarted.profiles.isEmpty)
        XCTAssertTrue(first.requiresFirstRunOnboarding)
        XCTAssertEqual(first.firstRunOnboardingPurpose, .fullSetup)
        XCTAssertFalse(
            FileManager.default.fileExists(
                atPath: first.dataPaths.profilesSnapshot.path
            )
        )
    }

    func testCleanSecondDeviceDiscoversAndAdoptsExactRemoteUUID() async throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let localDefault = profile(id: UUID(), name: "My Kid")
        let remote = profile(
            id: UUID(uuidString: "6F287B0A-0976-4BC9-92A3-77DDA93AEF30")!,
            name: "Mia",
            world: .frostlightWorld
        )
        let transport = DiscoveryTransport(
            availability: [.available],
            remoteProfiles: [remote]
        )
        let environment = try await bootstrap(
            in: directory,
            defaultProfile: localDefault,
            transport: transport
        )

        let discovered = try await discovery(in: environment).discoverProfiles()
        let completion = try await onboarding(in: environment).complete(
            profileID: nil,
            submission: FirstRunOnboardingSubmission(
                action: .adoptExistingProfile(remote.id)
            )
        )
        let unexpectedSeed = try await environment.profileRepository.profile(
            id: localDefault.id
        )
        let selectedProfileID = try await environment.childSessionRepository
            .lastSelectedProfileID()
        let tombstones = try await environment.tombstoneRepository.tombstones()
        let onboardingState = try await environment.firstRunOnboardingRepository
            .state()

        XCTAssertEqual(discovered.map(\.id), [remote.id])
        XCTAssertEqual(completion.profiles, [remote])
        XCTAssertEqual(completion.selectedProfileID, remote.id)
        XCTAssertNil(unexpectedSeed)
        XCTAssertEqual(selectedProfileID, remote.id)
        XCTAssertTrue(tombstones.isEmpty)
        XCTAssertNil(onboardingState?.profileIntent)

        let restarted = try await bootstrap(
            in: directory,
            defaultProfile: profile(id: UUID(), name: "New Random Seed"),
            transport: transport
        )
        XCTAssertFalse(restarted.requiresFirstRunOnboarding)
        XCTAssertEqual(restarted.profiles.map(\.id), [remote.id])
        XCTAssertEqual(restarted.lastSelectedProfileID, remote.id)
    }

    func testRelaunchAfterDiscoveryBeforeAdoptionKeepsRemoteProfilesReadOnly()
        async throws
    {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let remote = profile(
            id: UUID(uuidString: "08933BE5-CE79-4C35-AE44-B41B0B0DBCE4")!,
            name: "Mia"
        )
        let server = DiscoveryRemoteServer(profiles: [remote])
        let firstTransport = DiscoveryTransport(
            availability: [.available],
            server: server
        )
        let localDefault = profile(id: UUID(), name: "My Kid")
        let first = try await bootstrap(
            in: directory,
            defaultProfile: localDefault,
            transport: firstTransport
        )

        let discoveredBeforeRelaunch = try await discovery(in: first)
            .discoverProfiles()
        XCTAssertEqual(discoveredBeforeRelaunch.map(\.id), [remote.id])

        let restartedTransport = DiscoveryTransport(
            availability: [.available],
            server: server
        )
        let restarted = try await bootstrap(
            in: directory,
            defaultProfile: profile(id: UUID(), name: "Another Seed"),
            transport: restartedTransport
        )
        let presented = FirstRunOnboardingProfileSelection.profilesForPresentation(
            liveProfiles: restarted.profiles,
            bootstrappedProfilesWereEmpty: restarted.profiles.isEmpty,
            purpose: try XCTUnwrap(restarted.firstRunOnboardingPurpose),
            familySyncCapability: restartedTransport.capability,
            profileIntent: restarted.firstRunProfileIntent,
            pendingCreatedProfileID:
                restarted.firstRunPendingCreatedProfileID
        )
        let unexpectedSeed = try await restarted.profileRepository.profile(
            id: localDefault.id
        )

        XCTAssertEqual(restarted.profiles.map(\.id), [remote.id])
        XCTAssertNil(unexpectedSeed)
        XCTAssertEqual(restarted.firstRunProfileIntent, .discoverExisting)
        XCTAssertTrue(restarted.requiresFirstRunOnboarding)
        XCTAssertTrue(
            presented.isEmpty,
            "A discovered Profile must not become an editable new-kid seed."
        )

        let rediscovered = try await discovery(in: restarted).discoverProfiles()
        let firstConfirmationCalls = await firstTransport.confirmationCallCount()
        let restartedConfirmationCalls =
            await restartedTransport.confirmationCallCount()
        XCTAssertEqual(rediscovered.map(\.id), [remote.id])
        XCTAssertEqual(firstConfirmationCalls, 1)
        XCTAssertEqual(
            restartedConfirmationCalls,
            0,
            "Durable consent must continue its cursor instead of re-enabling sync."
        )
    }

    func testTemporaryAccountConfirmationFailureIsReportedAsOffline()
        async throws
    {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let transport = DiscoveryTransport(
            availability: [.available, .temporarilyUnavailable],
            remoteProfiles: [],
            confirmationFailures: 1
        )
        let environment = try await bootstrap(
            in: directory,
            defaultProfile: profile(id: UUID(), name: "My Kid"),
            transport: transport
        )

        do {
            _ = try await discovery(in: environment).discoverProfiles()
            XCTFail("A temporary confirmation failure must remain retryable.")
        } catch {
            XCTAssertEqual(error as? FirstRunProfileDiscoveryError, .offline)
        }

        let confirmationCalls = await transport.confirmationCallCount()
        let syncIsEnabled = await environment.familySyncCoordinator.isEnabled()
        let profiles = try await environment.profileRepository.profiles()
        XCTAssertEqual(confirmationCalls, 1)
        XCTAssertFalse(syncIsEnabled)
        XCTAssertTrue(profiles.isEmpty)
    }

    func testSameNicknameRemoteProfilesRemainDistinctAndSelectionUsesExactID()
        async throws
    {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let first = profile(
            id: UUID(uuidString: "2AC6D95E-6A04-4EA3-BD28-A6F75F94DC92")!,
            name: "Mia",
            world: .moonpetalKingdom
        )
        let second = profile(
            id: UUID(uuidString: "95E88702-2097-43DB-8869-919868994144")!,
            name: "Mia",
            world: .dinoDiscovery
        )
        let environment = try await bootstrap(
            in: directory,
            defaultProfile: profile(id: UUID(), name: "Mia"),
            transport: DiscoveryTransport(
                availability: [.available],
                remoteProfiles: [second, first]
            )
        )

        let discovered = try await discovery(in: environment).discoverProfiles()
        let completion = try await onboarding(in: environment).complete(
            profileID: nil,
            submission: FirstRunOnboardingSubmission(
                action: .adoptExistingProfile(second.id)
            )
        )
        let selectedProfileID = try await environment.childSessionRepository
            .lastSelectedProfileID()

        XCTAssertEqual(Set(discovered.map(\.id)), [first.id, second.id])
        XCTAssertEqual(Set(completion.profiles.map(\.id)), [first.id, second.id])
        XCTAssertEqual(completion.selectedProfileID, second.id)
        XCTAssertEqual(selectedProfileID, second.id)
    }

    func testOfflineDiscoveryLeavesFamilyEmptyThenRetryAfterRelaunchSucceeds()
        async throws
    {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let localDefault = profile(id: UUID(), name: "My Kid")
        let remote = profile(id: UUID(), name: "Mia")
        let transport = DiscoveryTransport(
            availability: [.temporarilyUnavailable, .available],
            remoteProfiles: [remote]
        )
        let first = try await bootstrap(
            in: directory,
            defaultProfile: localDefault,
            transport: transport
        )

        do {
            _ = try await discovery(in: first).discoverProfiles()
            XCTFail("Offline discovery should remain retryable.")
        } catch {
            XCTAssertEqual(error as? FirstRunProfileDiscoveryError, .offline)
        }
        let profilesAfterOfflineAttempt = try await first.profileRepository.profiles()
        XCTAssertTrue(profilesAfterOfflineAttempt.isEmpty)

        let restarted = try await bootstrap(
            in: directory,
            defaultProfile: profile(id: UUID(), name: "Another Seed"),
            transport: transport
        )
        let discovered = try await discovery(in: restarted).discoverProfiles()
        let unexpectedSeed = try await restarted.profileRepository.profile(
            id: localDefault.id
        )

        XCTAssertEqual(discovered.map(\.id), [remote.id])
        XCTAssertEqual(restarted.firstRunProfileIntent, .discoverExisting)
        XCTAssertNil(unexpectedSeed)
    }

    func testNoICloudAccountDoesNotCreatePlaceholder() async throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let localDefault = profile(id: UUID(), name: "My Kid")
        let environment = try await bootstrap(
            in: directory,
            defaultProfile: localDefault,
            transport: DiscoveryTransport(
                availability: [.noAccount],
                remoteProfiles: []
            )
        )

        do {
            _ = try await discovery(in: environment).discoverProfiles()
            XCTFail("A signed-out device should not report successful discovery.")
        } catch {
            XCTAssertEqual(
                error as? FirstRunProfileDiscoveryError,
                .iCloudUnavailable
            )
        }
        let profiles = try await environment.profileRepository.profiles()
        let selectedProfileID = try await environment.childSessionRepository
            .lastSelectedProfileID()
        let tombstones = try await environment.tombstoneRepository.tombstones()

        XCTAssertTrue(profiles.isEmpty)
        XCTAssertNil(selectedProfileID)
        XCTAssertTrue(tombstones.isEmpty)
    }

    func testExplicitOfflineNewKidCreatesFreshIdentityAndDefaultSettings()
        async throws
    {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let localDefault = profile(id: UUID(), name: "My Kid")
        let environment = try await bootstrap(
            in: directory,
            defaultProfile: localDefault,
            transport: DiscoveryTransport(
                availability: [.temporarilyUnavailable],
                remoteProfiles: []
            )
        )

        let completion = try await onboarding(in: environment).complete(
            profileID: nil,
            submission: FirstRunOnboardingSubmission(
                action: .createProfile(
                    GuardianProfileDraft(
                        displayName: "Coco",
                        avatarAssetID: "owl",
                        selectedWorld: .buildItBay,
                        schoolGrade: .preK,
                        ageYears: 4
                    )
                )
            )
        )
        let created = try XCTUnwrap(completion.profiles.first)
        let settings = try await environment.practiceSettingsRepository.settings(
            for: created.id
        )
        let isSyncEnabled = await environment.familySyncCoordinator.isEnabled()
        let tombstones = try await environment.tombstoneRepository.tombstones()
        let onboardingState = try await environment.firstRunOnboardingRepository
            .state()

        XCTAssertNotEqual(created.id, localDefault.id)
        XCTAssertEqual(created.displayName, "Coco")
        XCTAssertEqual(settings, .defaults(for: created.id))
        XCTAssertFalse(isSyncEnabled)
        XCTAssertTrue(tombstones.isEmpty)
        XCTAssertNil(onboardingState?.profileIntent)
    }

    func testExplicitNewKidCreationWorksWithoutAnICloudAccount() async throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let environment = try await bootstrap(
            in: directory,
            defaultProfile: profile(id: UUID(), name: "My Kid"),
            transport: DiscoveryTransport(
                availability: [.noAccount],
                remoteProfiles: []
            )
        )

        let completion = try await onboarding(in: environment).complete(
            profileID: nil,
            submission: FirstRunOnboardingSubmission(
                action: .createProfile(
                    GuardianProfileDraft(
                        displayName: "Coco",
                        avatarAssetID: "owl",
                        selectedWorld: .buildItBay,
                        schoolGrade: .preK,
                        ageYears: 4
                    )
                )
            )
        )
        let created = try XCTUnwrap(completion.profiles.first)
        let saved = try await environment.profileRepository.profile(id: created.id)
        let settings = try await environment.practiceSettingsRepository.settings(
            for: created.id
        )
        let onboardingState = try await environment.firstRunOnboardingRepository
            .state()

        XCTAssertEqual(saved?.displayName, "Coco")
        XCTAssertEqual(settings, .defaults(for: created.id))
        XCTAssertEqual(onboardingState?.status, .completed)
        XCTAssertNil(onboardingState?.profileIntent)
    }

    func testCreationIntentWriteFailureMutatesNoProfile() async throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let remote = profile(id: UUID(), name: "Mia")
        let profiles = InMemoryKidProfileRepository()
        try await profiles.save(remote)
        let settings = InMemoryPracticeSettingsRepository()
        let baseOnboarding = try await pendingDiscoveryRepository(in: directory)
        let onboarding = FailingOnceOnboardingRepository(
            base: baseOnboarding,
            failure: .beginCreation
        )
        let coordinator = creationCoordinator(
            profileRepository: profiles,
            settingsRepository: settings,
            childSessionRepository: InMemoryChildSessionRepository(),
            onboardingRepository: onboarding,
            existingProfiles: [remote]
        )

        await assertThrowsErrorAsync {
            _ = try await coordinator.complete(
                profileID: remote.id,
                submission: self.newKidSubmission
            )
        }

        let profilesAfterFailure = try await profiles.profiles()
        let remoteSettings = try await settings.settings(for: remote.id)
        XCTAssertEqual(profilesAfterFailure, [remote])
        XCTAssertNil(remoteSettings)
        let pending = try await baseOnboarding.state()
        XCTAssertEqual(pending?.profileIntent, .discoverExisting)
        XCTAssertNil(pending?.pendingCreatedProfileID)
    }

    func testSettingsFailureRetriesWithReservedIDWithoutTouchingRemote()
        async throws
    {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let remote = profile(id: UUID(), name: "Mia")
        let profiles = InMemoryKidProfileRepository()
        try await profiles.save(remote)
        let settings = FailingOncePracticeSettingsRepository()
        let onboarding = try await pendingDiscoveryRepository(in: directory)
        let coordinator = creationCoordinator(
            profileRepository: profiles,
            settingsRepository: settings,
            childSessionRepository: InMemoryChildSessionRepository(),
            onboardingRepository: onboarding,
            existingProfiles: [remote]
        )

        await assertThrowsErrorAsync {
            _ = try await coordinator.complete(
                profileID: remote.id,
                submission: self.newKidSubmission
            )
        }
        let pendingState = try await onboarding.state()
        let pendingID = try XCTUnwrap(pendingState?.pendingCreatedProfileID)
        let profilesAfterFailure = try await profiles.profiles()
        XCTAssertNotEqual(pendingID, remote.id)
        XCTAssertEqual(profilesAfterFailure, [remote])

        let completion = try await coordinator.complete(
            profileID: remote.id,
            submission: newKidSubmission
        )
        XCTAssertEqual(completion.selectedProfileID, pendingID)
        XCTAssertEqual(Set(completion.profiles.map(\.id)), [remote.id, pendingID])
        let savedRemote = try await profiles.profile(id: remote.id)
        let savedSettings = try await settings.settings(for: pendingID)
        XCTAssertEqual(savedRemote, remote)
        XCTAssertEqual(
            savedSettings,
            .defaults(for: pendingID)
        )
    }

    func testProfileFailureRollsBackSettingsAndRetriesTheReservedID()
        async throws
    {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let remote = profile(id: UUID(), name: "Mia")
        let profiles = FailingOnceKidProfileRepository(seed: [remote])
        let settings = InMemoryPracticeSettingsRepository()
        let onboarding = try await pendingDiscoveryRepository(in: directory)
        let coordinator = creationCoordinator(
            profileRepository: profiles,
            settingsRepository: settings,
            childSessionRepository: InMemoryChildSessionRepository(),
            onboardingRepository: onboarding,
            existingProfiles: [remote]
        )

        await assertThrowsErrorAsync {
            _ = try await coordinator.complete(
                profileID: remote.id,
                submission: self.newKidSubmission
            )
        }
        let pendingState = try await onboarding.state()
        let pendingID = try XCTUnwrap(pendingState?.pendingCreatedProfileID)
        let profilesAfterFailure = try await profiles.profiles()
        let rolledBackSettings = try await settings.settings(for: pendingID)
        XCTAssertNotEqual(pendingID, remote.id)
        XCTAssertEqual(profilesAfterFailure, [remote])
        XCTAssertNil(rolledBackSettings)

        let completion = try await coordinator.complete(
            profileID: remote.id,
            submission: newKidSubmission
        )
        XCTAssertEqual(completion.selectedProfileID, pendingID)
        XCTAssertEqual(Set(completion.profiles.map(\.id)), [remote.id, pendingID])
        let savedRemote = try await profiles.profile(id: remote.id)
        XCTAssertEqual(savedRemote, remote)
    }

    func testSessionFailureRetryCreatesAtMostOneNewIdentity() async throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let remote = profile(id: UUID(), name: "Mia")
        let profiles = InMemoryKidProfileRepository()
        try await profiles.save(remote)
        let settings = InMemoryPracticeSettingsRepository()
        let session = FailingOnceChildSessionRepository()
        let onboarding = try await pendingDiscoveryRepository(in: directory)
        let coordinator = creationCoordinator(
            profileRepository: profiles,
            settingsRepository: settings,
            childSessionRepository: session,
            onboardingRepository: onboarding,
            existingProfiles: [remote]
        )

        await assertThrowsErrorAsync {
            _ = try await coordinator.complete(
                profileID: remote.id,
                submission: self.newKidSubmission
            )
        }
        let pendingState = try await onboarding.state()
        let pendingID = try XCTUnwrap(pendingState?.pendingCreatedProfileID)
        let profileIDsAfterFailure = Set(
            try await profiles.profiles().map(\.id)
        )
        XCTAssertEqual(
            profileIDsAfterFailure,
            [remote.id, pendingID]
        )

        let completion = try await coordinator.complete(
            profileID: remote.id,
            submission: newKidSubmission
        )
        XCTAssertEqual(completion.selectedProfileID, pendingID)
        XCTAssertEqual(Set(completion.profiles.map(\.id)), [remote.id, pendingID])
        let savedRemote = try await profiles.profile(id: remote.id)
        XCTAssertEqual(savedRemote, remote)
    }

    func testCompletionMarkerFailureRetryCreatesAtMostOneNewIdentity()
        async throws
    {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let remote = profile(id: UUID(), name: "Mia")
        let profiles = InMemoryKidProfileRepository()
        try await profiles.save(remote)
        let settings = InMemoryPracticeSettingsRepository()
        let session = InMemoryChildSessionRepository()
        let baseOnboarding = try await pendingDiscoveryRepository(in: directory)
        let onboarding = FailingOnceOnboardingRepository(
            base: baseOnboarding,
            failure: .completion
        )
        let coordinator = creationCoordinator(
            profileRepository: profiles,
            settingsRepository: settings,
            childSessionRepository: session,
            onboardingRepository: onboarding,
            existingProfiles: [remote]
        )

        await assertThrowsErrorAsync {
            _ = try await coordinator.complete(
                profileID: remote.id,
                submission: self.newKidSubmission
            )
        }
        let pendingState = try await baseOnboarding.state()
        let pendingID = try XCTUnwrap(pendingState?.pendingCreatedProfileID)
        let selectedAfterFailure = try await session.lastSelectedProfileID()
        let profileIDsAfterFailure = Set(
            try await profiles.profiles().map(\.id)
        )
        XCTAssertEqual(selectedAfterFailure, pendingID)
        XCTAssertEqual(
            profileIDsAfterFailure,
            [remote.id, pendingID]
        )

        let completion = try await coordinator.complete(
            profileID: remote.id,
            submission: newKidSubmission
        )
        XCTAssertEqual(completion.selectedProfileID, pendingID)
        XCTAssertEqual(Set(completion.profiles.map(\.id)), [remote.id, pendingID])
        let completedState = try await baseOnboarding.state()
        let savedRemote = try await profiles.profile(id: remote.id)
        XCTAssertNil(completedState?.pendingCreatedProfileID)
        XCTAssertEqual(savedRemote, remote)
    }

    private var newKidSubmission: FirstRunOnboardingSubmission {
        FirstRunOnboardingSubmission(
            action: .createProfile(
                GuardianProfileDraft(
                    displayName: "Coco",
                    avatarAssetID: "owl",
                    selectedWorld: .buildItBay,
                    schoolGrade: .preK,
                    ageYears: 4
                )
            )
        )
    }

    private func pendingDiscoveryRepository(
        in directory: URL
    ) async throws -> LocalFirstRunOnboardingRepository {
        let repository = LocalFirstRunOnboardingRepository(
            snapshotURL: directory.appendingPathComponent("onboarding.json")
        )
        try await repository.markPending(
            startedAt: referenceDate,
            purpose: .fullSetup
        )
        try await repository.markDiscoveryIntent()
        return repository
    }

    private func creationCoordinator(
        profileRepository: any KidProfileRepository,
        settingsRepository: any PracticeSettingsRepository,
        childSessionRepository: any ChildSessionRepository,
        onboardingRepository: any FirstRunOnboardingPersisting,
        existingProfiles: [KidProfile]
    ) -> FirstRunOnboardingCoordinator {
        let guardianStore = RepositoryGuardianFamilyStore(
            profiles: existingProfiles,
            profileRepository: profileRepository,
            wordPoolRepository: InMemoryWordPoolRepository(),
            practiceSettingsRepository: settingsRepository,
            clock: AdoptionClock(now: referenceDate),
            timeZone: TimeZone(secondsFromGMT: 0) ?? .current
        )
        return FirstRunOnboardingCoordinator(
            profileRepository: profileRepository,
            childSessionRepository: childSessionRepository,
            onboardingRepository: onboardingRepository,
            guardianStore: guardianStore,
            clock: AdoptionClock(now: referenceDate)
        )
    }

    private func discovery(
        in environment: ProductionApplicationEnvironment
    ) -> FirstRunProfileDiscoveryCoordinator {
        FirstRunProfileDiscoveryCoordinator(
            familySyncCoordinator: environment.familySyncCoordinator,
            familySyncTransport: environment.familySyncTransport,
            profileRepository: environment.profileRepository,
            onboardingRepository: environment.firstRunOnboardingRepository
        )
    }

    private func onboarding(
        in environment: ProductionApplicationEnvironment
    ) -> FirstRunOnboardingCoordinator {
        FirstRunOnboardingCoordinator(
            profileRepository: environment.profileRepository,
            childSessionRepository: environment.childSessionRepository,
            onboardingRepository: environment.firstRunOnboardingRepository,
            guardianStore: environment.guardianStore,
            clock: AdoptionClock(now: referenceDate)
        )
    }

    private func bootstrap(
        in directory: URL,
        defaultProfile: KidProfile,
        transport: any FamilySyncTransport
    ) async throws -> ProductionApplicationEnvironment {
        try await ProductionApplicationBootstrapper(
            applicationSupportDirectory: { directory },
            defaultProfile: defaultProfile,
            clock: AdoptionClock(now: referenceDate),
            timeZone: TimeZone(secondsFromGMT: 0) ?? .current,
            familySyncTransport: transport
        ).bootstrap()
    }

    private func profile(
        id: UUID,
        name: String,
        world: WorldTheme = .moonpetalKingdom
    ) -> KidProfile {
        KidProfile(
            id: ProfileID(rawValue: id),
            displayName: name,
            avatar: .cartoonAnimal(assetID: "hare"),
            selectedWorld: world,
            starterWorld: world,
            schoolGrade: .preK,
            ageYears: 4,
            createdAt: referenceDate.addingTimeInterval(-86_400),
            updatedAt: referenceDate
        )
    }

    private func temporaryDirectory() throws -> URL {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(
            "TadaWordsSecondDevice-\(UUID().uuidString)",
            isDirectory: true
        )
        try FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true
        )
        return directory
    }

    private var referenceDate: Date {
        Date(timeIntervalSince1970: 1_768_464_000)
    }
}

private struct AdoptionClock: AppClock {
    let now: Date
}

private enum CreationInterruption: Error {
    case injected
}

private actor FailingOnceKidProfileRepository: KidProfileRepository {
    private var profilesByID: [ProfileID: KidProfile]
    private var shouldFailSave = true

    init(seed: [KidProfile]) {
        profilesByID = Dictionary(uniqueKeysWithValues: seed.map { ($0.id, $0) })
    }

    func profiles() async throws -> [KidProfile] {
        profilesByID.values.sorted { $0.id.description < $1.id.description }
    }

    func profile(id: ProfileID) async throws -> KidProfile? {
        profilesByID[id]
    }

    func save(_ profile: KidProfile) async throws {
        if shouldFailSave {
            shouldFailSave = false
            throw CreationInterruption.injected
        }
        profilesByID[profile.id] = profile
    }

    func delete(id: ProfileID) async throws {
        profilesByID[id] = nil
    }
}

private actor FailingOncePracticeSettingsRepository:
    PracticeSettingsRepository
{
    private var settingsByProfileID: [ProfileID: ProfilePracticeSettings] = [:]
    private var shouldFailSave = true

    func settings(
        for profileID: ProfileID
    ) async throws -> ProfilePracticeSettings? {
        settingsByProfileID[profileID]
    }

    func save(_ settings: ProfilePracticeSettings) async throws {
        if shouldFailSave {
            shouldFailSave = false
            throw CreationInterruption.injected
        }
        settingsByProfileID[settings.profileID] = settings
    }

    func delete(for profileID: ProfileID) async throws {
        settingsByProfileID[profileID] = nil
    }
}

private actor FailingOnceChildSessionRepository: ChildSessionRepository {
    private var selectedProfileID: ProfileID?
    private var shouldFailSave = true

    func lastSelectedProfileID() async throws -> ProfileID? {
        selectedProfileID
    }

    func saveLastSelectedProfileID(_ profileID: ProfileID) async throws {
        if shouldFailSave {
            shouldFailSave = false
            throw CreationInterruption.injected
        }
        selectedProfileID = profileID
    }

    func clearLastSelectedProfileID() async throws {
        selectedProfileID = nil
    }
}

private actor FailingOnceOnboardingRepository: FirstRunOnboardingPersisting {
    enum Failure {
        case beginCreation
        case completion
    }

    private let base: LocalFirstRunOnboardingRepository
    private let failure: Failure
    private var hasFailed = false

    init(
        base: LocalFirstRunOnboardingRepository,
        failure: Failure
    ) {
        self.base = base
        self.failure = failure
    }

    func markDiscoveryIntent() async throws {
        try await base.markDiscoveryIntent()
    }

    func beginProfileCreation(
        proposedProfileID: ProfileID?,
        startedAt: Date
    ) async throws -> ProfileID {
        if failure == .beginCreation, !hasFailed {
            hasFailed = true
            throw CreationInterruption.injected
        }
        return try await base.beginProfileCreation(
            proposedProfileID: proposedProfileID,
            startedAt: startedAt
        )
    }

    func markCompleted(
        profileID: ProfileID,
        completedAt: Date,
        consentVersion: Int?
    ) async throws {
        if failure == .completion, !hasFailed {
            hasFailed = true
            throw CreationInterruption.injected
        }
        try await base.markCompleted(
            profileID: profileID,
            completedAt: completedAt,
            consentVersion: consentVersion
        )
    }
}

private func assertThrowsErrorAsync<T>(
    _ expression: () async throws -> T,
    file: StaticString = #filePath,
    line: UInt = #line
) async {
    do {
        _ = try await expression()
        XCTFail("Expected an error to be thrown.", file: file, line: line)
    } catch {}
}

private actor DiscoveryTransport: FamilySyncTransport {
    nonisolated let capability = FamilySyncCapability.iCloud
    nonisolated let initialProfilePolicy =
        FamilySyncInitialProfilePolicy.discoverBeforeCreating

    private var availabilityValues: [FamilySyncAvailability]
    private let server: DiscoveryRemoteServer
    private var confirmationFailuresRemaining: Int
    private var confirmationCalls = 0

    init(
        availability: [FamilySyncAvailability],
        remoteProfiles: [KidProfile],
        confirmationFailures: Int = 0
    ) {
        self.init(
            availability: availability,
            server: DiscoveryRemoteServer(profiles: remoteProfiles),
            confirmationFailures: confirmationFailures
        )
    }

    init(
        availability: [FamilySyncAvailability],
        server: DiscoveryRemoteServer,
        confirmationFailures: Int = 0
    ) {
        precondition(!availability.isEmpty)
        availabilityValues = availability
        self.server = server
        confirmationFailuresRemaining = confirmationFailures
    }

    func availability() async -> FamilySyncAvailability {
        guard availabilityValues.count > 1 else {
            return availabilityValues[0]
        }
        return availabilityValues.removeFirst()
    }

    func prepareProfileZone(_ profileID: ProfileID) async throws {
        _ = profileID
    }

    func fetchRecords(
        for profileID: ProfileID
    ) async throws -> [FamilySyncRecord] {
        await server.records(for: profileID)
    }

    func fetchChanges(
        for profileIDs: [ProfileID]
    ) async throws -> FamilySyncTransportResult {
        _ = profileIDs
        return await server.fetchChanges()
    }

    func push(
        _ records: [FamilySyncRecord],
        for profileID: ProfileID
    ) async throws {
        _ = records
        _ = profileID
    }

    func acknowledgeFetchedChanges(receiptIDs: Set<UUID>) async throws {
        await server.acknowledge(receiptIDs)
    }

    func confirmCurrentAccount() async throws -> FamilySyncAccountChange? {
        confirmationCalls += 1
        guard confirmationFailuresRemaining > 0 else { return nil }
        confirmationFailuresRemaining -= 1
        throw DiscoveryTransportFailure.accountConfirmation
    }

    func confirmationCallCount() -> Int {
        confirmationCalls
    }

    func createShare(for profileID: ProfileID) async throws -> URL {
        _ = profileID
        return URL(string: "https://example.invalid/family")!
    }

    func acceptShare(at url: URL) async throws -> ProfileID {
        _ = url
        return ProfileID()
    }

    fileprivate nonisolated static func record(
        for profile: KidProfile
    ) -> FamilySyncRecord {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .secondsSince1970
        encoder.outputFormatting = [.sortedKeys]
        let payload = try! encoder.encode(FamilySyncProfilePayload(profile: profile))
        return FamilySyncRecord(
            recordName: "profile-\(profile.id)",
            profileID: profile.id,
            kind: .profile,
            payload: payload,
            updatedAt: profile.updatedAt,
            deviceID: "remote-family-device",
            logicalRevision: FamilySyncLogicalRevision(
                counter: 10,
                deviceID: "remote-family-device"
            )
        )
    }
}

private enum DiscoveryTransportFailure: Error {
    case accountConfirmation
}

private struct DiscoveryRemoteEntry: Sendable {
    let record: FamilySyncRecord
    let receipt: FamilySyncFetchedReceipt
}

private actor DiscoveryRemoteServer {
    private let entries: [DiscoveryRemoteEntry]
    private var acknowledgedReceiptIDs: Set<UUID> = []

    init(profiles: [KidProfile]) {
        entries = profiles.enumerated().map { index, profile in
            let record = DiscoveryTransport.record(for: profile)
            return DiscoveryRemoteEntry(
                record: record,
                receipt: FamilySyncFetchedReceipt(
                    id: Self.receiptID(index: index, profileID: profile.id),
                    key: FamilySyncChangeKey(
                        profileID: record.profileID,
                        recordName: record.recordName
                    ),
                    operation: .save,
                    revision: record.logicalRevision
                )
            )
        }
    }

    func records(for profileID: ProfileID) -> [FamilySyncRecord] {
        entries.map(\.record).filter { $0.profileID == profileID }
    }

    func fetchChanges() -> FamilySyncTransportResult {
        let pending = entries.filter {
            !acknowledgedReceiptIDs.contains($0.receipt.id)
        }
        return FamilySyncTransportResult(
            records: pending.map(\.record),
            receipts: pending.map(\.receipt)
        )
    }

    func acknowledge(_ receiptIDs: Set<UUID>) {
        acknowledgedReceiptIDs.formUnion(receiptIDs)
    }

    private nonisolated static func receiptID(
        index: Int,
        profileID: ProfileID
    ) -> UUID {
        var bytes = Array(profileID.rawValue.uuidString.utf8)
        bytes.append(UInt8(index & 0xFF))
        let checksum = FamilySyncRecord.checksum(for: Data(bytes))
        let hex = String(checksum.prefix(32))
        let value =
            "\(hex.prefix(8))-\(hex.dropFirst(8).prefix(4))-4\(hex.dropFirst(13).prefix(3))-a\(hex.dropFirst(17).prefix(3))-\(hex.dropFirst(20).prefix(12))"
        return UUID(uuidString: value) ?? UUID()
    }
}
