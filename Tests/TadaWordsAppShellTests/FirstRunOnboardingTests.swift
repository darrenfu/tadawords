import Foundation
import TadaWordsContent
import TadaWordsDomain
import TadaWordsGuardianFeatures
import XCTest

@testable import TadaWordsAppShell

final class FirstRunOnboardingTests: XCTestCase {
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
