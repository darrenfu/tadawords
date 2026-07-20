import Foundation
import TadaWordsDomain

public enum ProfileMutationGatedDeviceVoiceprintRepositoryError:
    Error,
    Equatable,
    Sendable
{
    case freshInstallationResetUnsupported
}

/// Applies the same Profile terminal fence used by JSON repositories to the
/// device-local Keychain voiceprint adapter. A stale enrollment may finish
/// after a remote deletion, but it can never persist a template after the
/// deletion tombstone has sealed that Profile.
public struct ProfileMutationGatedDeviceVoiceprintRepository:
    DeviceVoiceprintRepository,
    FreshInstallationVoiceprintResetting,
    Sendable
{
    private let base: any DeviceVoiceprintRepository
    private let mutationGate: ProfileScopedMutationGate

    public init(
        base: any DeviceVoiceprintRepository,
        mutationGate: ProfileScopedMutationGate
    ) {
        self.base = base
        self.mutationGate = mutationGate
    }

    public func template(
        for profileID: ProfileID
    ) async throws -> DeviceVoiceprintTemplate? {
        try await withProfileScopedMutationLease(
            mutationGate,
            for: profileID,
            allowingTerminal: true,
            isolation: mutationGate
        ) {
            guard !(await mutationGate.isTerminal(profileID)) else {
                return nil
            }
            return try await base.template(for: profileID)
        }
    }

    public func save(_ template: DeviceVoiceprintTemplate) async throws {
        try await withProfileScopedMutationLease(
            mutationGate,
            for: template.profileID,
            isolation: mutationGate
        ) {
            try await base.save(template)
        }
    }

    public func delete(for profileID: ProfileID) async throws {
        try await withProfileScopedMutationLease(
            mutationGate,
            for: profileID,
            allowingTerminal: true,
            isolation: mutationGate
        ) {
            try await base.delete(for: profileID)
        }
    }

    public func resetVoiceprintsForFreshInstallation() async throws {
        guard
            let resetter = base as? any FreshInstallationVoiceprintResetting
        else {
            throw ProfileMutationGatedDeviceVoiceprintRepositoryError
                .freshInstallationResetUnsupported
        }
        try await resetter.resetVoiceprintsForFreshInstallation()
    }
}
