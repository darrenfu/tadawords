import Foundation
import TadaWordsContent
import TadaWordsDomain
import XCTest

final class RepositoryChildProfileCreatorTests: XCTestCase {
    func testCreationPersistsTrimmedProfileAndIsolatedDefaultSettings()
        async throws
    {
        let profiles = InMemoryKidProfileRepository()
        let settings = InMemoryPracticeSettingsRepository()
        let existing = makeProfile(name: "Mia")
        try await profiles.save(existing)
        let existingSettings = ProfilePracticeSettings(
            profileID: existing.id,
            read: LearningRouteSettings(
                newWordLimit: 9,
                reviewWordLimit: 2,
                contentOrder: .reviewThenNew,
                emergencyAfterSeconds: 222
            )
        )
        try await settings.save(existingSettings)
        let creator = RepositoryChildProfileCreator(
            profileRepository: profiles,
            practiceSettingsRepository: settings,
            clock: CreatorTestClock()
        )

        let created = try await creator.createProfile(
            displayName: "  Coco  ",
            existingProfiles: [existing]
        )

        XCTAssertEqual(created.displayName, "Coco")
        XCTAssertEqual(created.avatar, .cartoonAnimal(assetID: "fox"))
        XCTAssertEqual(created.selectedWorld, .buildItBay)
        XCTAssertEqual(created.createdAt, CreatorTestClock.testDate)
        let persistedProfile = try await profiles.profile(id: created.id)
        let createdSettings = try await settings.settings(for: created.id)
        let persistedExistingSettings = try await settings.settings(for: existing.id)
        XCTAssertEqual(persistedProfile, created)
        XCTAssertEqual(
            createdSettings,
            .defaults(for: created.id)
        )
        XCTAssertEqual(
            persistedExistingSettings,
            existingSettings,
            "A child-created profile must never reuse or overwrite a sibling's settings."
        )
    }

    func testSettingsFailureDoesNotPublishProfile() async throws {
        let profiles = InMemoryKidProfileRepository()
        let creator = RepositoryChildProfileCreator(
            profileRepository: profiles,
            practiceSettingsRepository: FailingSaveSettingsRepository(),
            clock: CreatorTestClock()
        )

        do {
            _ = try await creator.createProfile(
                displayName: "Coco",
                existingProfiles: []
            )
            XCTFail("Expected settings persistence to fail.")
        } catch let error as ChildProfileCreationError {
            XCTAssertEqual(error, .settingsPersistenceFailed)
        }
        let persistedProfiles = try await profiles.profiles()
        XCTAssertTrue(persistedProfiles.isEmpty)
    }

    func testProfileFailureRollsBackPreparedSettings() async throws {
        let settings = InMemoryPracticeSettingsRepository()
        let profiles = FailingSaveProfileRepository()
        let creator = RepositoryChildProfileCreator(
            profileRepository: profiles,
            practiceSettingsRepository: settings,
            clock: CreatorTestClock()
        )

        do {
            _ = try await creator.createProfile(
                displayName: "Coco",
                existingProfiles: []
            )
            XCTFail("Expected profile persistence to fail.")
        } catch let error as ChildProfileCreationError {
            XCTAssertEqual(error, .profilePersistenceFailed)
        }
        let attemptedProfileID = await profiles.lastAttemptedProfileID
        let preparedProfileID = try XCTUnwrap(attemptedProfileID)
        let rolledBackSettings = try await settings.settings(for: preparedProfileID)
        XCTAssertNil(rolledBackSettings)
    }

    private func makeProfile(name: String) -> KidProfile {
        KidProfile(
            displayName: name,
            avatar: .cartoonAnimal(assetID: "hare"),
            selectedWorld: .moonpetalKingdom,
            createdAt: CreatorTestClock.testDate.addingTimeInterval(-10)
        )
    }
}

private struct CreatorTestClock: AppClock {
    static let testDate = Date(timeIntervalSince1970: 1_750_000_000)
    let now = Self.testDate
}

private enum CreatorTestFailure: Error {
    case expected
}

private actor FailingSaveSettingsRepository: PracticeSettingsRepository {
    func settings(for profileID: ProfileID) async throws -> ProfilePracticeSettings? {
        _ = profileID
        return nil
    }

    func save(_ settings: ProfilePracticeSettings) async throws {
        _ = settings
        throw CreatorTestFailure.expected
    }

    func delete(for profileID: ProfileID) async throws {
        _ = profileID
    }
}

private actor FailingSaveProfileRepository: KidProfileRepository {
    private(set) var lastAttemptedProfileID: ProfileID?

    func profiles() async throws -> [KidProfile] { [] }

    func profile(id: ProfileID) async throws -> KidProfile? {
        _ = id
        return nil
    }

    func save(_ profile: KidProfile) async throws {
        lastAttemptedProfileID = profile.id
        throw CreatorTestFailure.expected
    }

    func delete(id: ProfileID) async throws {
        _ = id
    }
}
