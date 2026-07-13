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

    func testExistingInstallMigratesWithoutInterruptingChildHome() async throws {
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

        XCTAssertFalse(environment.requiresFirstRunOnboarding)
        XCTAssertEqual(state?.status, .completed)
        XCTAssertEqual(state?.profileID, existing.id)
    }

    func testCompletionPersistsProfileStarterWorldLevelAndLaunchSelection()
        async throws
    {
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

        let completion = try await coordinator.complete(
            profileID: defaultProfile.id,
            submission: FirstRunOnboardingSubmission(
                profileDraft: GuardianProfileDraft(
                    displayName: "  Coco  ",
                    avatarAssetID: "owl",
                    selectedWorld: .buildItBay,
                    schoolGrade: .kindergarten,
                    ageYears: 4
                ),
                readWords: "the, cat, THE",
                writeWords: "can, look"
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
        XCTAssertEqual(readEntries.map(\.prompt.normalizedText), ["the", "cat"])
        XCTAssertEqual(writeEntries.map(\.prompt.normalizedText), ["can", "look"])

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
                    profileDraft: GuardianProfileDraft(
                        displayName: "   ",
                        avatarAssetID: "hare",
                        selectedWorld: .moonpetalKingdom
                    ),
                    readWords: "",
                    writeWords: ""
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

    private func bootstrap(
        in directory: URL
    ) async throws -> ProductionApplicationEnvironment {
        try await ProductionApplicationBootstrapper(
            applicationSupportDirectory: { directory },
            defaultProfile: defaultProfile,
            clock: OnboardingClock(now: testDate),
            timeZone: TimeZone(secondsFromGMT: 0) ?? .current
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
