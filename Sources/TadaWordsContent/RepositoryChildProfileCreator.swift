import Foundation
import TadaWordsDomain

/// Creates a child profile as one visible family operation. Settings are
/// persisted first, so a profile is never published without isolated defaults.
public actor RepositoryChildProfileCreator: ChildProfileCreating {
    public static let maximumDisplayNameCharacterCount = 24

    private static let avatarAssetIDs = StarterProfileAvatar.zodiac.map(\.id)
    private static let worlds = CosmeticProgressionCatalog.worlds

    private let profileRepository: any KidProfileRepository
    private let practiceSettingsRepository: any PracticeSettingsRepository
    private let clock: any AppClock

    public init(
        profileRepository: any KidProfileRepository,
        practiceSettingsRepository: any PracticeSettingsRepository,
        clock: any AppClock
    ) {
        self.profileRepository = profileRepository
        self.practiceSettingsRepository = practiceSettingsRepository
        self.clock = clock
    }

    public func createProfile(
        displayName: String,
        ageYears: Int,
        existingProfiles: [KidProfile]
    ) async throws -> KidProfile {
        let nickname = displayName.trimmingCharacters(
            in: .whitespacesAndNewlines
        )
        guard !nickname.isEmpty else {
            throw ChildProfileCreationError.emptyDisplayName
        }
        guard nickname.count <= Self.maximumDisplayNameCharacterCount else {
            throw ChildProfileCreationError.displayNameTooLong(
                maximumCharacterCount: Self.maximumDisplayNameCharacterCount
            )
        }
        guard
            let suggestedGrade = ProfileAgePolicy.suggestedSchoolGrade(
                for: ageYears
            )
        else {
            throw ChildProfileCreationError.invalidAge
        }

        let profile = makeProfile(
            nickname: nickname,
            ageYears: ageYears,
            schoolGrade: suggestedGrade,
            existingProfiles: existingProfiles
        )
        do {
            try await practiceSettingsRepository.save(.defaults(for: profile.id))
        } catch {
            throw ChildProfileCreationError.settingsPersistenceFailed
        }

        do {
            try await profileRepository.save(profile)
        } catch {
            do {
                try await practiceSettingsRepository.delete(for: profile.id)
            } catch {
                throw ChildProfileCreationError.rollbackFailed
            }
            throw ChildProfileCreationError.profilePersistenceFailed
        }
        return profile
    }

    private func makeProfile(
        nickname: String,
        ageYears: Int,
        schoolGrade: ProfileSchoolGrade,
        existingProfiles: [KidProfile]
    ) -> KidProfile {
        let nextIndex = existingProfiles.count
        return KidProfile(
            displayName: nickname,
            avatar: .cartoonAnimal(
                assetID: Self.avatarAssetIDs[nextIndex % Self.avatarAssetIDs.count]
            ),
            selectedWorld: Self.worlds[nextIndex % Self.worlds.count],
            schoolGrade: schoolGrade,
            ageYears: ageYears,
            createdAt: clock.now
        )
    }
}
