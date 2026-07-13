import Foundation

public protocol ChildProfileCreating: Sendable {
    func createProfile(
        displayName: String,
        existingProfiles: [KidProfile]
    ) async throws -> KidProfile
}

public enum ChildProfileCreationError: Error, Equatable, Sendable {
    case emptyDisplayName
    case displayNameTooLong(maximumCharacterCount: Int)
    case settingsPersistenceFailed
    case profilePersistenceFailed
    case rollbackFailed
}
