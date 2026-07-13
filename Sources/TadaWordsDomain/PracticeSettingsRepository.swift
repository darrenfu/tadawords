public protocol PracticeSettingsRepository: Sendable {
    func settings(
        for profileID: ProfileID
    ) async throws -> ProfilePracticeSettings?

    /// Creates settings or replaces the settings for the same profile.
    func save(_ settings: ProfilePracticeSettings) async throws

    func delete(for profileID: ProfileID) async throws
}
