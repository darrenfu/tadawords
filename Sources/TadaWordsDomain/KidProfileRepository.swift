public protocol KidProfileRepository: Sendable {
    func profiles() async throws -> [KidProfile]

    func profile(id: ProfileID) async throws -> KidProfile?

    /// Creates a profile or updates the profile with the same identity.
    func save(_ profile: KidProfile) async throws

    func delete(id: ProfileID) async throws
}
