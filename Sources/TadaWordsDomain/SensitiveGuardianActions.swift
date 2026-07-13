public enum SensitiveGuardianAction: String, Codable, CaseIterable, Hashable,
    Sendable
{
    case deleteProfile
    case exportLearningData
    case enableFamilySync
    case manageGuardians
}

public protocol SensitiveGuardianActionAuthorizing: Sendable {
    func authorize(_ action: SensitiveGuardianAction) async -> Bool
}

public struct AllowSensitiveGuardianActions: SensitiveGuardianActionAuthorizing {
    public init() {}

    public func authorize(_ action: SensitiveGuardianAction) async -> Bool {
        _ = action
        return true
    }
}
