import Foundation
import LocalAuthentication
import TadaWordsDomain

public actor AppleSensitiveGuardianActionAuthorizer:
    SensitiveGuardianActionAuthorizing
{
    public init() {}

    public func authorize(_ action: SensitiveGuardianAction) async -> Bool {
        let context = LAContext()
        context.localizedCancelTitle = "Cancel"
        var error: NSError?
        guard context.canEvaluatePolicy(.deviceOwnerAuthentication, error: &error) else {
            return false
        }
        do {
            return try await context.evaluatePolicy(
                .deviceOwnerAuthentication,
                localizedReason: reason(for: action)
            )
        } catch {
            return false
        }
    }

    private func reason(for action: SensitiveGuardianAction) -> String {
        switch action {
        case .deleteProfile:
            "Confirm deletion of this Tada Words profile and its learning data."
        case .exportLearningData:
            "Confirm export of Tada Words learning data."
        case .enableFamilySync:
            "Confirm changes to family sync."
        case .manageGuardians:
            "Confirm changes to family access."
        case .replaceFamilySyncData:
            "Confirm replacing iCloud Family Sync data with this iPad’s verified local backup."
        }
    }
}
