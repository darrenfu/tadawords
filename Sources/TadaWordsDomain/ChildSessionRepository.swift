public protocol ChildSessionRepository: Sendable {
    func lastSelectedProfileID() async throws -> ProfileID?

    func saveLastSelectedProfileID(_ profileID: ProfileID) async throws

    func clearLastSelectedProfileID() async throws
}
