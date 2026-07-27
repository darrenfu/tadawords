import Foundation

public struct FamilySyncCanonicalRecoveryPlan: Equatable, Sendable {
    public let profileIDs: [ProfileID]
    public let recordCount: Int
    public let recordCountsByKind: [FamilySyncRecordKind: Int]
    public let recordSetFingerprint: FamilySyncRecordSetFingerprint
    public let installationID: String

    public init(
        profileIDs: [ProfileID],
        recordCount: Int,
        recordCountsByKind: [FamilySyncRecordKind: Int] = [:],
        recordSetFingerprint: FamilySyncRecordSetFingerprint,
        installationID: String
    ) {
        self.profileIDs = profileIDs.sorted {
            $0.description < $1.description
        }
        self.recordCount = recordCount
        self.recordCountsByKind = recordCountsByKind
        self.recordSetFingerprint = recordSetFingerprint
        self.installationID = installationID.trimmingCharacters(
            in: .whitespacesAndNewlines
        )
    }
}

public struct FamilySyncCanonicalRecoveryAuthorization: Equatable, Sendable {
    public let expectedPlan: FamilySyncCanonicalRecoveryPlan
    public let verifiedBackupSHA256: String

    public init(
        expectedPlan: FamilySyncCanonicalRecoveryPlan,
        verifiedBackupSHA256: String
    ) {
        self.expectedPlan = expectedPlan
        self.verifiedBackupSHA256 = verifiedBackupSHA256.lowercased()
    }
}

public struct FamilySyncCanonicalRecoveryReceipt: Equatable, Sendable {
    public let verifiedRemoteFingerprint: FamilySyncRecordSetFingerprint
    public let recoveredRecordCount: Int

    public init(
        verifiedRemoteFingerprint: FamilySyncRecordSetFingerprint,
        recoveredRecordCount: Int
    ) {
        self.verifiedRemoteFingerprint = verifiedRemoteFingerprint
        self.recoveredRecordCount = recoveredRecordCount
    }
}

public enum FamilySyncCanonicalRecoveryError: Error, Equatable, Sendable {
    case unavailable
    case invalidBackupDigest
    case profileSetChanged
    case localSnapshotChanged
    case installationMismatch
    case remoteVerificationFailed
}

/// Destructive replacement is deliberately outside ordinary reconciliation.
/// Only an explicitly authorized, exact local snapshot can enter this API.
public protocol FamilySyncCanonicalRecoveryTransport: FamilySyncTransport {
    func replaceRemoteWithCanonicalRecords(
        _ records: [FamilySyncRecord],
        authorization: FamilySyncCanonicalRecoveryAuthorization
    ) async throws -> FamilySyncCanonicalRecoveryReceipt
}

public protocol FamilySyncCanonicalRecoveryProviding: Sendable {
    func canonicalRecoveryPlan() async throws -> FamilySyncCanonicalRecoveryPlan

    func recoverCanonicalLocalData(
        authorization: FamilySyncCanonicalRecoveryAuthorization
    ) async throws -> FamilySyncCanonicalRecoveryReceipt
}
