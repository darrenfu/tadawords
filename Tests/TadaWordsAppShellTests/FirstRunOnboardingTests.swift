import Foundation
import TadaWordsContent
import TadaWordsDomain
import TadaWordsGuardianFeatures
import XCTest

@testable import TadaWordsAppShell

final class FirstRunOnboardingTests: XCTestCase {
    func testStaleForegroundGenerationCannotReopenAdmission() throws {
        let gate = FirstRunDiscoveryAdmissionGate()
        let first = gate.closeForAccountRevalidation()
        let second = gate.closeForAccountRevalidation()

        XCTAssertFalse(gate.reopen(ifCurrent: first))
        XCTAssertTrue(gate.admissionIsClosed())
        XCTAssertThrowsError(try gate.requireAdmissionAllowed())

        XCTAssertTrue(gate.reopen(ifCurrent: second))
        XCTAssertFalse(gate.admissionIsClosed())
        XCTAssertNoThrow(try gate.requireAdmissionAllowed())
    }

    func testFutureSchemaFailsClosedWithoutRewritingExactBytes() async throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let snapshotURL = directory.appendingPathComponent("first-run.json")
        let original = Data(
            "{\"schemaVersion\":4,\"status\":\"pending\",\"startedAt\":0,\"future\":true}"
                .utf8
        )
        try original.write(to: snapshotURL)
        let repository = LocalFirstRunOnboardingRepository(
            snapshotURL: snapshotURL
        )

        for _ in 0..<2 {
            do {
                _ = try await repository.state()
                XCTFail("A future onboarding schema must fail closed.")
            } catch {
                XCTAssertEqual(
                    error as? FirstRunOnboardingRepositoryError,
                    .unsupportedSchemaVersion(
                        found: 4,
                        supported: FirstRunOnboardingState.currentSchemaVersion
                    )
                )
            }
            XCTAssertEqual(try Data(contentsOf: snapshotURL), original)
        }
    }

    func testLegacyFullSetupDiscoveryMigratesToDurableResetGateBeforeAdmission()
        async throws
    {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let snapshotURL = directory.appendingPathComponent("first-run.json")
        let legacy = FirstRunOnboardingState(
            schemaVersion: 2,
            status: .pending,
            startedAt: testDate,
            completedAt: nil,
            profileID: nil,
            consentVersion: nil,
            consentedAt: nil,
            purpose: .fullSetup,
            profileIntent: .discoverExisting
        )
        try JSONEncoder().encode(legacy).write(to: snapshotURL, options: .atomic)

        let first = LocalFirstRunOnboardingRepository(snapshotURL: snapshotURL)
        let migrated = try await first.state()
        XCTAssertEqual(
            migrated?.schemaVersion,
            FirstRunOnboardingState.currentSchemaVersion
        )
        XCTAssertEqual(migrated?.discoveryResetPhase, .required)

        let restarted = LocalFirstRunOnboardingRepository(
            snapshotURL: snapshotURL
        )
        try await restarted.markPending(
            startedAt: testDate.addingTimeInterval(30),
            purpose: .fullSetup
        )
        do {
            _ = try await restarted.beginProfileCreation(
                proposedProfileID: nil,
                startedAt: testDate
            )
            XCTFail("Legacy discovery must fail closed before Create.")
        } catch {
            XCTAssertEqual(
                error as? FirstRunOnboardingRepositoryError,
                .discoveryResetRequired
            )
        }
    }

    func testLegacyConsentRefreshDiscoveryDoesNotGainDestructiveResetGate()
        async throws
    {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let snapshotURL = directory.appendingPathComponent("first-run.json")
        let legacy = FirstRunOnboardingState(
            schemaVersion: 2,
            status: .pending,
            startedAt: testDate,
            completedAt: nil,
            profileID: defaultProfile.id,
            consentVersion: nil,
            consentedAt: nil,
            purpose: .consentRefresh,
            profileIntent: .discoverExisting
        )
        try JSONEncoder().encode(legacy).write(to: snapshotURL, options: .atomic)

        let repository = LocalFirstRunOnboardingRepository(
            snapshotURL: snapshotURL
        )
        let decoded = try await repository.state()
        try await repository.requireDiscoveryResetCompleted()

        XCTAssertEqual(decoded, legacy)
        XCTAssertNil(decoded?.discoveryResetPhase)
    }

    func testFullSetupDiscoveryResetGatePersistsAcrossRelaunchUntilFinished()
        async throws
    {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let snapshotURL = directory.appendingPathComponent("first-run.json")
        let first = LocalFirstRunOnboardingRepository(snapshotURL: snapshotURL)
        try await first.markPending(
            startedAt: testDate,
            purpose: .fullSetup
        )

        _ = try await first.prepareForProfileDiscovery()
        let fencedState = try await first.state()
        XCTAssertEqual(
            fencedState?.schemaVersion,
            FirstRunOnboardingState.currentSchemaVersion
        )
        XCTAssertEqual(fencedState?.discoveryResetPhase, .required)

        let restarted = LocalFirstRunOnboardingRepository(
            snapshotURL: snapshotURL
        )
        do {
            _ = try await restarted.beginProfileCreation(
                proposedProfileID: nil,
                startedAt: testDate
            )
            XCTFail("Create must remain blocked after a reset interruption.")
        } catch {
            XCTAssertEqual(
                error as? FirstRunOnboardingRepositoryError,
                .discoveryResetRequired
            )
        }
        do {
            try await restarted.requireDiscoveryResetCompleted()
            XCTFail("Adoption/completion must share the durable reset gate.")
        } catch {
            XCTAssertEqual(
                error as? FirstRunOnboardingRepositoryError,
                .discoveryResetRequired
            )
        }

        try await restarted.finishDiscoveryReset()
        try await restarted.requireProfileCreationAllowed()
        do {
            try await restarted.requireDiscoveryResetCompleted()
            XCTFail("Adoption must wait for an account-bound fetch.")
        } catch {
            XCTAssertEqual(
                error as? FirstRunOnboardingRepositoryError,
                .discoveryResetRequired
            )
        }
        try await restarted.beginAccountBoundDiscovery()
        try await restarted.finishProfileDiscovery()
        try await restarted.requireDiscoveryResetCompleted()
        let createdID = try await restarted.beginProfileCreation(
            proposedProfileID: nil,
            startedAt: testDate
        )
        let completedResetState = try await restarted.state()
        XCTAssertEqual(completedResetState?.profileIntent, .createNew)
        XCTAssertEqual(completedResetState?.pendingCreatedProfileID, createdID)
        XCTAssertNil(completedResetState?.discoveryResetPhase)
    }

    func testDiscoveryResetCannotFinishUntilPendingCreateContainmentCommits()
        async throws
    {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let repository = LocalFirstRunOnboardingRepository(
            snapshotURL: directory.appendingPathComponent("first-run.json")
        )
        try await repository.markPending(
            startedAt: testDate,
            purpose: .fullSetup
        )
        let pendingID = try await repository.beginProfileCreation(
            proposedProfileID: nil,
            startedAt: testDate
        )
        let preparedID = try await repository.prepareForProfileDiscovery()
        XCTAssertEqual(preparedID, pendingID)

        do {
            try await repository.finishDiscoveryReset()
            XCTFail("The reset fence must retain the exact pending identity.")
        } catch {
            XCTAssertEqual(
                error as? FirstRunOnboardingRepositoryError,
                .pendingProfileCreationChanged
            )
        }

        try await repository.finishPendingProfileContainment(
            profileID: pendingID
        )
        try await repository.finishDiscoveryReset()
        try await repository.beginAccountBoundDiscovery()
        try await repository.finishProfileDiscovery()
        try await repository.requireDiscoveryResetCompleted()
    }

    func testForegroundRearmsSuccessfulPendingDiscoveryBeforeAccountCanChange()
        async throws
    {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let repository = LocalFirstRunOnboardingRepository(
            snapshotURL: directory.appendingPathComponent("first-run.json")
        )
        try await repository.markPending(
            startedAt: testDate,
            purpose: .fullSetup
        )
        _ = try await repository.prepareForProfileDiscovery()
        try await repository.finishDiscoveryReset()
        try await repository.beginAccountBoundDiscovery()
        try await repository.finishProfileDiscovery()
        try await repository.requireDiscoveryResetCompleted()

        let didRearm = try await repository.rearmPendingDiscoveryReset()
        XCTAssertTrue(didRearm)
        do {
            try await repository.requireProfileCreationAllowed()
            XCTFail("Foreground reentry must require another explicit Find.")
        } catch {
            XCTAssertEqual(
                error as? FirstRunOnboardingRepositoryError,
                .discoveryResetRequired
            )
        }
    }

    func testFailedResetFenceWritePreservesPriorDurableBytesAcrossRelaunch()
        async throws
    {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let snapshotURL = directory.appendingPathComponent("first-run.json")
        let repository = LocalFirstRunOnboardingRepository(
            snapshotURL: snapshotURL
        )
        try await repository.markPending(
            startedAt: testDate,
            purpose: .fullSetup
        )
        _ = try await repository.prepareForProfileDiscovery()
        let fencedBytes = try Data(contentsOf: snapshotURL)

        try FileManager.default.setAttributes(
            [.posixPermissions: 0o500],
            ofItemAtPath: directory.path
        )
        do {
            try await repository.finishDiscoveryReset()
            XCTFail("An unwritable directory must reject reset completion.")
        } catch {
            // The raw file-system error is intentionally propagated.
        }
        try FileManager.default.setAttributes(
            [.posixPermissions: 0o700],
            ofItemAtPath: directory.path
        )

        XCTAssertEqual(try Data(contentsOf: snapshotURL), fencedBytes)
        let restarted = LocalFirstRunOnboardingRepository(
            snapshotURL: snapshotURL
        )
        let restartedState = try await restarted.state()
        XCTAssertEqual(restartedState?.discoveryResetPhase, .required)
    }

    func testPresentationIdentitySurvivesPendingCreateContainmentReceipt()
        throws
    {
        let pendingProfileID = ProfileID()

        let beforeContainment = FirstRunOnboardingPresentationIdentity.value(
            purpose: .fullSetup,
            onboardingProfileID: pendingProfileID
        )
        let afterRemoteReceipt = FirstRunOnboardingPresentationIdentity.value(
            purpose: .fullSetup,
            onboardingProfileID: nil
        )

        XCTAssertEqual(
            beforeContainment,
            afterRemoteReceipt,
            "A committed receipt must not recreate the onboarding view and discard one-tap Find results."
        )
    }

    func testFreshInstallStaysPendingAcrossRestartUntilParentFinishes() async throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }

        let first = try await bootstrap(in: directory)
        let restarted = try await bootstrap(in: directory)
        let restartedState = try await restarted.firstRunOnboardingRepository.state()

        XCTAssertTrue(first.requiresFirstRunOnboarding)
        XCTAssertTrue(restarted.requiresFirstRunOnboarding)
        XCTAssertEqual(restartedState?.status, .pending)
    }

    func testExistingInstallRequiresConsentWithoutMutatingProfile() async throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let paths = ApplicationDataPaths(applicationSupportDirectory: directory)
        let existing = KidProfile(
            displayName: "Coco",
            avatar: .cartoonAnimal(assetID: "fox"),
            selectedWorld: .pawsAndPines,
            createdAt: testDate.addingTimeInterval(-100)
        )
        try await LocalJSONKidProfileRepository(
            snapshotURL: paths.profilesSnapshot
        ).save(existing)

        let environment = try await bootstrap(in: directory)
        let state = try await environment.firstRunOnboardingRepository.state()

        XCTAssertTrue(environment.requiresFirstRunOnboarding)
        XCTAssertEqual(environment.firstRunOnboardingPurpose, .consentRefresh)
        XCTAssertEqual(state?.status, .pending)
        let profileBeforeConsent = try await environment.profileRepository.profile(
            id: existing.id
        )
        XCTAssertEqual(profileBeforeConsent, existing)

        let coordinator = FirstRunOnboardingCoordinator(
            profileRepository: environment.profileRepository,
            childSessionRepository: environment.childSessionRepository,
            onboardingRepository: environment.firstRunOnboardingRepository,
            guardianStore: environment.guardianStore,
            clock: OnboardingClock(now: testDate)
        )
        _ = try await coordinator.complete(
            profileID: existing.id,
            submission: FirstRunOnboardingSubmission(
                action: .confirmExistingProfiles
            )
        )

        let profileAfterConsent = try await environment.profileRepository.profile(
            id: existing.id
        )
        let completedState = try await environment.firstRunOnboardingRepository.state()
        XCTAssertEqual(profileAfterConsent, existing)
        XCTAssertEqual(
            completedState?.consentVersion,
            FirstRunOnboardingSubmission.currentConsentVersion
        )
    }

    func testDefaultNamedExistingInstallRefreshesConsentWithoutMutatingWordPools()
        async throws
    {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let paths = ApplicationDataPaths(applicationSupportDirectory: directory)
        let existing = KidProfile(
            id: defaultProfile.id,
            displayName: defaultProfile.displayName,
            avatar: .cartoonAnimal(assetID: "owl"),
            selectedWorld: .buildItBay,
            schoolGrade: .kindergarten,
            ageYears: 4,
            createdAt: testDate.addingTimeInterval(-86_400)
        )
        try await LocalJSONKidProfileRepository(
            snapshotURL: paths.profilesSnapshot
        ).save(existing)
        let words = LocalJSONWordPoolRepository(snapshotURL: paths.wordPoolSnapshot)
        let importer = ManualWordPoolImporter(repository: words)
        _ = try await importer.importBatch(
            "cat",
            profileID: existing.id,
            learningMode: .read,
            addedAt: testDate.addingTimeInterval(-60)
        )
        _ = try await importer.importBatch(
            "look",
            profileID: existing.id,
            learningMode: .write,
            addedAt: testDate.addingTimeInterval(-30)
        )
        let readBefore = try await words.entries(
            for: existing.id,
            learningMode: .read,
            includingInactive: true
        )
        let writeBefore = try await words.entries(
            for: existing.id,
            learningMode: .write,
            includingInactive: true
        )

        let environment = try await bootstrap(in: directory)
        XCTAssertEqual(environment.firstRunOnboardingPurpose, .consentRefresh)

        let coordinator = FirstRunOnboardingCoordinator(
            profileRepository: environment.profileRepository,
            childSessionRepository: environment.childSessionRepository,
            onboardingRepository: environment.firstRunOnboardingRepository,
            guardianStore: environment.guardianStore,
            clock: OnboardingClock(now: testDate)
        )
        _ = try await coordinator.complete(
            profileID: existing.id,
            submission: FirstRunOnboardingSubmission(
                action: .confirmExistingProfiles
            )
        )

        let profileAfterConsent = try await environment.profileRepository.profile(
            id: existing.id
        )
        let readAfter = try await environment.wordPoolRepository.entries(
            for: existing.id,
            learningMode: .read,
            includingInactive: true
        )
        let writeAfter = try await environment.wordPoolRepository.entries(
            for: existing.id,
            learningMode: .write,
            includingInactive: true
        )
        XCTAssertEqual(profileAfterConsent, existing)
        XCTAssertEqual(readAfter, readBefore)
        XCTAssertEqual(writeAfter, writeBefore)
    }

    func testLegacyPendingMarkerWithoutPurposeRemainsFullSetup() async throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let paths = ApplicationDataPaths(applicationSupportDirectory: directory)
        try FileManager.default.createDirectory(
            at: paths.dataDirectory,
            withIntermediateDirectories: true
        )
        let legacyState = FirstRunOnboardingState(
            schemaVersion: 1,
            status: .pending,
            startedAt: testDate.addingTimeInterval(-100),
            completedAt: nil,
            profileID: nil,
            consentVersion: nil,
            consentedAt: nil,
            purpose: nil
        )
        try JSONEncoder().encode(legacyState).write(
            to: paths.firstRunOnboardingSnapshot,
            options: .atomic
        )

        let environment = try await bootstrap(in: directory)
        let migratedState = try await environment.firstRunOnboardingRepository.state()

        XCTAssertEqual(environment.firstRunOnboardingPurpose, .fullSetup)
        XCTAssertEqual(migratedState?.purpose, .fullSetup)
        XCTAssertEqual(migratedState?.startedAt, legacyState.startedAt)
    }

    func testLiveEmptyFamilyNormalizesPendingConsentRefreshToFullSetup()
        async throws
    {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let repository = LocalFirstRunOnboardingRepository(
            snapshotURL: directory.appendingPathComponent("first-run.json")
        )
        try await repository.markPending(
            startedAt: testDate.addingTimeInterval(-30),
            purpose: .consentRefresh
        )

        let resolvedPurpose =
            FirstRunOnboardingProfileSelection.resolvedPurpose(
                .consentRefresh,
                in: []
            )
        try await repository.normalizePendingPurpose(
            resolvedPurpose
        )

        let state = try await repository.state()
        XCTAssertEqual(resolvedPurpose, .fullSetup)
        XCTAssertEqual(state?.purpose, .fullSetup)
        XCTAssertEqual(
            state?.startedAt,
            testDate.addingTimeInterval(-30),
            "Normalizing a live receipt must not restart the consent clock"
        )
    }

    func testRestartAfterRemoteFinalProfileDeletionCreatesFreshProfile()
        async throws
    {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let paths = ApplicationDataPaths(applicationSupportDirectory: directory)
        let deletedProfile = KidProfile(
            displayName: "Mia",
            avatar: .cartoonAnimal(assetID: "hare"),
            selectedWorld: .moonpetalKingdom,
            createdAt: testDate.addingTimeInterval(-100)
        )
        try await LocalJSONKidProfileRepository(
            snapshotURL: paths.profilesSnapshot
        ).save(deletedProfile)
        let onboarding = LocalFirstRunOnboardingRepository(
            snapshotURL: paths.firstRunOnboardingSnapshot
        )
        try await onboarding.markPending(
            startedAt: testDate.addingTimeInterval(-50),
            purpose: .consentRefresh
        )
        let tombstones = LocalJSONProfileDeletionTombstoneRepository(
            snapshotURL: paths.profileDeletionTombstonesSnapshot
        )
        try await tombstones.save(
            ProfileDeletionTombstone(
                profileID: deletedProfile.id,
                deletedAt: testDate
            )
        )

        let environment = try await bootstrap(in: directory)
        let pendingState = try await environment.firstRunOnboardingRepository
            .state()
        XCTAssertTrue(environment.profiles.isEmpty)
        XCTAssertTrue(environment.requiresFirstRunOnboarding)
        XCTAssertEqual(environment.firstRunOnboardingPurpose, .fullSetup)
        XCTAssertEqual(pendingState?.purpose, .fullSetup)

        let coordinator = FirstRunOnboardingCoordinator(
            profileRepository: environment.profileRepository,
            childSessionRepository: environment.childSessionRepository,
            onboardingRepository: environment.firstRunOnboardingRepository,
            guardianStore: environment.guardianStore,
            clock: OnboardingClock(now: testDate.addingTimeInterval(10))
        )
        let completion = try await coordinator.complete(
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
        XCTAssertNotEqual(created.id, deletedProfile.id)
        XCTAssertEqual(completion.selectedProfileID, created.id)

        let restarted = try await bootstrap(in: directory)
        XCTAssertFalse(restarted.requiresFirstRunOnboarding)
        XCTAssertEqual(restarted.profiles.map(\.id), [created.id])
        XCTAssertEqual(restarted.lastSelectedProfileID, created.id)
    }

    func testConsentRefreshPreservesLastSelectedProfileAcrossMultipleProfiles()
        async throws
    {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let paths = ApplicationDataPaths(applicationSupportDirectory: directory)
        let first = defaultProfile
        let lastSelected = KidProfile(
            displayName: "Coco",
            avatar: .cartoonAnimal(assetID: "fox"),
            selectedWorld: .pawsAndPines,
            createdAt: testDate.addingTimeInterval(-50)
        )
        let profiles = LocalJSONKidProfileRepository(snapshotURL: paths.profilesSnapshot)
        try await profiles.save(first)
        try await profiles.save(lastSelected)
        let session = LocalJSONChildSessionRepository(
            snapshotURL: paths.childSessionSnapshot
        )
        try await session.saveLastSelectedProfileID(lastSelected.id)

        let environment = try await bootstrap(in: directory)
        let displayedProfile = FirstRunOnboardingProfileSelection.profile(
            in: environment.profiles,
            purpose: .consentRefresh,
            lastSelectedProfileID: environment.lastSelectedProfileID
        )
        XCTAssertEqual(displayedProfile?.id, lastSelected.id)

        let coordinator = FirstRunOnboardingCoordinator(
            profileRepository: environment.profileRepository,
            childSessionRepository: environment.childSessionRepository,
            onboardingRepository: environment.firstRunOnboardingRepository,
            guardianStore: environment.guardianStore,
            clock: OnboardingClock(now: testDate)
        )
        let completion = try await coordinator.complete(
            profileID: first.id,
            submission: FirstRunOnboardingSubmission(
                action: .confirmExistingProfiles
            )
        )
        let completedState = try await environment.firstRunOnboardingRepository.state()
        let persistedSelection = try await environment.childSessionRepository
            .lastSelectedProfileID()
        let persistedProfiles = try await environment.profileRepository.profiles()

        XCTAssertEqual(completion.selectedProfileID, lastSelected.id)
        XCTAssertEqual(persistedSelection, lastSelected.id)
        XCTAssertEqual(completedState?.profileID, lastSelected.id)
        XCTAssertEqual(persistedProfiles, environment.profiles)
    }

    func testConsentRefreshWithoutRememberedProfileRoutesToChooser() async throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let paths = ApplicationDataPaths(applicationSupportDirectory: directory)
        let first = defaultProfile
        let second = KidProfile(
            displayName: "Coco",
            avatar: .cartoonAnimal(assetID: "fox"),
            selectedWorld: .pawsAndPines,
            createdAt: testDate.addingTimeInterval(-50)
        )
        let profiles = LocalJSONKidProfileRepository(snapshotURL: paths.profilesSnapshot)
        try await profiles.save(first)
        try await profiles.save(second)

        let environment = try await bootstrap(in: directory)
        let coordinator = FirstRunOnboardingCoordinator(
            profileRepository: environment.profileRepository,
            childSessionRepository: environment.childSessionRepository,
            onboardingRepository: environment.firstRunOnboardingRepository,
            guardianStore: environment.guardianStore,
            clock: OnboardingClock(now: testDate)
        )

        let completion = try await coordinator.complete(
            profileID: first.id,
            submission: FirstRunOnboardingSubmission(
                action: .confirmExistingProfiles
            )
        )
        let completedState = try await environment.firstRunOnboardingRepository.state()
        let persistedSelection = try await environment.childSessionRepository
            .lastSelectedProfileID()

        XCTAssertNil(completion.selectedProfileID)
        XCTAssertNil(persistedSelection)
        XCTAssertEqual(completedState?.profileID, first.id)
        XCTAssertEqual(completion.profiles, environment.profiles)
    }

    func testCompletionPersistsProfileWithoutAddingWordsAndLaunchesIt()
        async throws
    {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let environment = try await bootstrap(
            in: directory,
            familySyncTransport: OnboardingSyncTransport()
        )
        let coordinator = FirstRunOnboardingCoordinator(
            profileRepository: environment.profileRepository,
            childSessionRepository: environment.childSessionRepository,
            onboardingRepository: environment.firstRunOnboardingRepository,
            guardianStore: environment.guardianStore,
            clock: OnboardingClock(now: testDate.addingTimeInterval(50))
        )

        let completion = try await coordinator.complete(
            profileID: defaultProfile.id,
            submission: FirstRunOnboardingSubmission(
                action: .createProfile(
                    GuardianProfileDraft(
                        displayName: "  Coco  ",
                        avatarAssetID: "owl",
                        selectedWorld: .buildItBay,
                        schoolGrade: .kindergarten,
                        ageYears: 4
                    )
                )
            )
        )
        let storedProfile = try await environment.profileRepository.profile(
            id: defaultProfile.id
        )
        let saved = try XCTUnwrap(storedProfile)
        let state = try await environment.firstRunOnboardingRepository.state()
        let selectedProfileID = try await environment.childSessionRepository
            .lastSelectedProfileID()
        let readEntries = try await environment.wordPoolRepository.entries(
            for: defaultProfile.id,
            learningMode: .read,
            includingInactive: true
        )
        let writeEntries = try await environment.wordPoolRepository.entries(
            for: defaultProfile.id,
            learningMode: .write,
            includingInactive: true
        )

        XCTAssertEqual(completion.selectedProfileID, defaultProfile.id)
        XCTAssertEqual(saved.displayName, "Coco")
        XCTAssertEqual(saved.avatar, .cartoonAnimal(assetID: "owl"))
        XCTAssertEqual(saved.schoolGrade, .kindergarten)
        XCTAssertEqual(saved.ageYears, 4)
        XCTAssertEqual(saved.selectedWorld, .buildItBay)
        XCTAssertEqual(saved.starterWorld, .buildItBay)
        XCTAssertEqual(saved.guardianUnlockedWorlds, [.buildItBay])
        XCTAssertEqual(selectedProfileID, defaultProfile.id)
        XCTAssertEqual(state?.status, .completed)
        XCTAssertEqual(state?.profileID, defaultProfile.id)
        XCTAssertEqual(
            state?.consentVersion,
            FirstRunOnboardingSubmission.currentConsentVersion
        )
        XCTAssertEqual(state?.consentedAt, testDate.addingTimeInterval(50))
        let isFamilySyncEnabled = await environment.familySyncCoordinator.isEnabled()
        XCTAssertFalse(isFamilySyncEnabled)
        XCTAssertTrue(readEntries.isEmpty)
        XCTAssertTrue(writeEntries.isEmpty)

        let restarted = try await bootstrap(in: directory)
        XCTAssertFalse(restarted.requiresFirstRunOnboarding)
        XCTAssertEqual(restarted.lastSelectedProfileID, defaultProfile.id)
        XCTAssertEqual(restarted.profiles.first?.displayName, "Coco")
    }

    func testCompletionRejectsBlankNameWithoutCompletingMarker() async throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let environment = try await bootstrap(in: directory)
        let coordinator = FirstRunOnboardingCoordinator(
            profileRepository: environment.profileRepository,
            childSessionRepository: environment.childSessionRepository,
            onboardingRepository: environment.firstRunOnboardingRepository,
            guardianStore: environment.guardianStore,
            clock: OnboardingClock(now: testDate.addingTimeInterval(50))
        )

        do {
            _ = try await coordinator.complete(
                profileID: defaultProfile.id,
                submission: FirstRunOnboardingSubmission(
                    action: .createProfile(
                        GuardianProfileDraft(
                            displayName: "   ",
                            avatarAssetID: "hare",
                            selectedWorld: .moonpetalKingdom
                        )
                    )
                )
            )
            XCTFail("Expected a blank nickname to be rejected")
        } catch {
            XCTAssertEqual(error as? FirstRunOnboardingError, .emptyDisplayName)
        }

        let state = try await environment.firstRunOnboardingRepository.state()
        let selectedProfileID = try await environment.childSessionRepository
            .lastSelectedProfileID()
        XCTAssertEqual(state?.status, .pending)
        XCTAssertNil(selectedProfileID)
    }

    func testCompletionRequiresAgeWithoutOverwritingSelectedGrade() async throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let environment = try await bootstrap(in: directory)
        let coordinator = FirstRunOnboardingCoordinator(
            profileRepository: environment.profileRepository,
            childSessionRepository: environment.childSessionRepository,
            onboardingRepository: environment.firstRunOnboardingRepository,
            guardianStore: environment.guardianStore,
            clock: OnboardingClock(now: testDate.addingTimeInterval(50))
        )

        do {
            _ = try await coordinator.complete(
                profileID: defaultProfile.id,
                submission: FirstRunOnboardingSubmission(
                    action: .createProfile(
                        GuardianProfileDraft(
                            displayName: "Coco",
                            avatarAssetID: "hare",
                            selectedWorld: .moonpetalKingdom,
                            schoolGrade: .grade1
                        )
                    )
                )
            )
            XCTFail("Expected age to be required")
        } catch {
            XCTAssertEqual(error as? FirstRunOnboardingError, .invalidAge)
        }

        let persisted = try await environment.profileRepository.profile(
            id: defaultProfile.id
        )
        XCTAssertEqual(persisted?.schoolGrade, defaultProfile.schoolGrade)
        XCTAssertNil(persisted?.ageYears)
    }

    func testCompletionRejectsStaleConsentBeforeMutatingProfile() async throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let environment = try await bootstrap(in: directory)
        let original = try await environment.profileRepository.profile(id: defaultProfile.id)
        let coordinator = FirstRunOnboardingCoordinator(
            profileRepository: environment.profileRepository,
            childSessionRepository: environment.childSessionRepository,
            onboardingRepository: environment.firstRunOnboardingRepository,
            guardianStore: environment.guardianStore,
            clock: OnboardingClock(now: testDate.addingTimeInterval(50))
        )

        do {
            _ = try await coordinator.complete(
                profileID: defaultProfile.id,
                submission: FirstRunOnboardingSubmission(
                    action: .createProfile(
                        GuardianProfileDraft(
                            displayName: "Changed",
                            avatarAssetID: "owl",
                            selectedWorld: .buildItBay
                        )
                    ),
                    consentVersion: 0
                )
            )
            XCTFail("Expected stale consent to be rejected")
        } catch {
            XCTAssertEqual(error as? FirstRunOnboardingError, .consentRequired)
        }

        let profileAfterRejection = try await environment.profileRepository.profile(
            id: defaultProfile.id
        )
        let stateAfterRejection = try await environment.firstRunOnboardingRepository.state()
        let readEntries = try await environment.wordPoolRepository.entries(
            for: defaultProfile.id,
            learningMode: .read,
            includingInactive: true
        )
        XCTAssertEqual(profileAfterRejection, original)
        XCTAssertEqual(stateAfterRejection?.status, .pending)
        XCTAssertTrue(readEntries.isEmpty)
    }

    func testPrivacyDisclosureSeparatesLocalStorageFromOptionalICloud() {
        let local = FirstRunPrivacyDisclosure.message(for: .deviceOnly)
        let cloud = FirstRunPrivacyDisclosure.message(for: .iCloud)

        XCTAssertFalse(local.localizedCaseInsensitiveContains("icloud"))
        XCTAssertTrue(local.localizedCaseInsensitiveContains("this device"))
        XCTAssertTrue(cloud.localizedCaseInsensitiveContains("icloud"))
        XCTAssertTrue(cloud.localizedCaseInsensitiveContains("off by default"))
    }

    private func bootstrap(
        in directory: URL,
        familySyncTransport: any FamilySyncTransport = LocalOnlyFamilySyncTransport()
    ) async throws -> ProductionApplicationEnvironment {
        try await ProductionApplicationBootstrapper(
            applicationSupportDirectory: { directory },
            defaultProfile: defaultProfile,
            clock: OnboardingClock(now: testDate),
            timeZone: TimeZone(secondsFromGMT: 0) ?? .current,
            familySyncTransport: familySyncTransport
        ).bootstrap()
    }

    private func temporaryDirectory() throws -> URL {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(
            "TadaWordsOnboarding-\(UUID().uuidString)",
            isDirectory: true
        )
        try FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true
        )
        return directory
    }

    private var testDate: Date {
        Date(timeIntervalSince1970: 1_735_689_600)
    }

    private var defaultProfile: KidProfile {
        KidProfile(
            id: ProfileID(
                rawValue: UUID(
                    uuidString: "3B20FEF0-7E43-4B70-8F89-D37AD55454A1"
                )!
            ),
            displayName: "My Kid",
            avatar: .cartoonAnimal(assetID: "hare"),
            selectedWorld: .moonpetalKingdom,
            createdAt: testDate
        )
    }
}

private struct OnboardingClock: AppClock {
    let now: Date
}

private actor OnboardingSyncTransport: FamilySyncTransport {
    nonisolated let capability = FamilySyncCapability.iCloud

    func availability() async -> FamilySyncAvailability { .available }
    func prepareProfileZone(_ profileID: ProfileID) async throws {}
    func fetchRecords(for profileID: ProfileID) async throws -> [FamilySyncRecord] { [] }
    func push(_ records: [FamilySyncRecord], for profileID: ProfileID) async throws {}
    func createShare(for profileID: ProfileID) async throws -> URL {
        URL(string: "https://example.invalid/share")!
    }
    func acceptShare(at url: URL) async throws -> ProfileID { ProfileID() }
}
