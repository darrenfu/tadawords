import Foundation

public protocol ChildProfileCreating: Sendable {
    func createProfile(
        displayName: String,
        ageYears: Int,
        existingProfiles: [KidProfile]
    ) async throws -> KidProfile
}

public enum ChildProfileCreationError: Error, Equatable, Sendable {
    case emptyDisplayName
    case displayNameTooLong(maximumCharacterCount: Int)
    case invalidAge
    case settingsPersistenceFailed
    case profilePersistenceFailed
    case rollbackFailed
}
