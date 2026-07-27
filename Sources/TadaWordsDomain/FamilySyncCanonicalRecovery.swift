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
    public let generationID: String
    public let previousGenerationID: String?
    public let verifiedRemoteFingerprint: FamilySyncRecordSetFingerprint
    public let recoveredRecordCount: Int

    public init(
        generationID: String = "",
        previousGenerationID: String? = nil,
        verifiedRemoteFingerprint: FamilySyncRecordSetFingerprint,
        recoveredRecordCount: Int
    ) {
        self.generationID = generationID
        self.previousGenerationID = previousGenerationID
        self.verifiedRemoteFingerprint = verifiedRemoteFingerprint
        self.recoveredRecordCount = recoveredRecordCount
    }
}

/// An immutable, fully verified Family Sync snapshot selected by one tiny
/// control-plane pointer. Clients must adopt it before they may upload normal
/// profile-zone changes.
public struct FamilySyncCanonicalGenerationSnapshot: Equatable, Sendable {
    public let generationID: String
    public let previousGenerationID: String?
    public let sourceInstallationID: String
    public let createdAt: Date
    public let records: [FamilySyncRecord]
    public let recordSetFingerprint: FamilySyncRecordSetFingerprint

    public init(
        generationID: String,
        previousGenerationID: String?,
        sourceInstallationID: String,
        createdAt: Date,
        records: [FamilySyncRecord]
    ) {
        self.generationID = generationID.trimmingCharacters(
            in: .whitespacesAndNewlines
        )
        self.previousGenerationID = previousGenerationID
        self.sourceInstallationID = sourceInstallationID.trimmingCharacters(
            in: .whitespacesAndNewlines
        )
        self.createdAt = createdAt
        self.records = records.sorted(by: Self.recordOrder)
        recordSetFingerprint = FamilySyncRecordSetFingerprint(records: records)
    }

    public var profileIDs: [ProfileID] {
        Array(Set(records.map(\.profileID))).sorted {
            $0.description < $1.description
        }
    }

    public func validate() throws {
        let recordKeys = records.map {
            "\($0.profileID.description)|\($0.recordName)"
        }
        let profileRecords = Dictionary(
            grouping: records.filter {
                $0.kind == .profile && !$0.isDeleted
            },
            by: \.profileID
        )
        guard !generationID.isEmpty, generationID.count <= 64,
            generationID.allSatisfy({
                $0.isLowercase || $0.isNumber || $0 == "-"
            }),
            previousGenerationID != generationID,
            !sourceInstallationID.isEmpty,
            !records.isEmpty,
            Set(recordKeys).count == recordKeys.count,
            !records.contains(where: {
                $0.kind == .profileDeletion || $0.isDeleted
            }),
            profileIDs.allSatisfy({
                profileRecords[$0]?.count == 1
            })
        else {
            throw FamilySyncCanonicalRecoveryError.invalidGeneration
        }
        for record in records { try record.validateCompatibility() }
        guard
            FamilySyncRecordSetFingerprint(records: records)
                == recordSetFingerprint
        else {
            throw FamilySyncCanonicalRecoveryError.remoteVerificationFailed
        }
    }

    private static func recordOrder(
        _ lhs: FamilySyncRecord,
        _ rhs: FamilySyncRecord
    ) -> Bool {
        if lhs.profileID != rhs.profileID {
            return lhs.profileID.description < rhs.profileID.description
        }
        if lhs.recordName != rhs.recordName {
            return lhs.recordName < rhs.recordName
        }
        return lhs.kind.rawValue < rhs.kind.rawValue
    }
}

public enum FamilySyncCanonicalRecoveryError: Error, Equatable, Sendable {
    case unavailable
    case invalidBackupDigest
    case invalidGeneration
    case profileSetChanged
    case localSnapshotChanged
    case installationMismatch
    case remoteVerificationFailed
}

/// Canonical publication is deliberately outside ordinary reconciliation.
/// Only an explicitly authorized, exact local snapshot can enter this API.
public protocol FamilySyncCanonicalRecoveryTransport: FamilySyncTransport {
    /// Compatibility seam for pre-generation test transports. Production
    /// CloudKit implementations publish generations instead.
    func replaceRemoteWithCanonicalRecords(
        _ records: [FamilySyncRecord],
        authorization: FamilySyncCanonicalRecoveryAuthorization
    ) async throws -> FamilySyncCanonicalRecoveryReceipt

    func publishCanonicalGeneration(
        _ records: [FamilySyncRecord],
        authorization: FamilySyncCanonicalRecoveryAuthorization
    ) async throws -> FamilySyncCanonicalRecoveryReceipt

    /// Returns nil when no canonical pointer exists or this device already
    /// applied it. A returned generation is manifest- and fingerprint-verified.
    func activeCanonicalGeneration() async throws
        -> FamilySyncCanonicalGenerationSnapshot?

    /// Persists the local adoption fence only after repository and journal
    /// replacement both complete.
    func markCanonicalGenerationApplied(_ generationID: String) async throws

    func isCanonicalGenerationApplied(_ generationID: String) async throws
        -> Bool
}

extension FamilySyncCanonicalRecoveryTransport {
    public func replaceRemoteWithCanonicalRecords(
        _ records: [FamilySyncRecord],
        authorization: FamilySyncCanonicalRecoveryAuthorization
    ) async throws -> FamilySyncCanonicalRecoveryReceipt {
        throw FamilySyncCanonicalRecoveryError.unavailable
    }

    public func publishCanonicalGeneration(
        _ records: [FamilySyncRecord],
        authorization: FamilySyncCanonicalRecoveryAuthorization
    ) async throws -> FamilySyncCanonicalRecoveryReceipt {
        try await replaceRemoteWithCanonicalRecords(
            records,
            authorization: authorization
        )
    }

    public func activeCanonicalGeneration() async throws
        -> FamilySyncCanonicalGenerationSnapshot?
    {
        nil
    }

    public func markCanonicalGenerationApplied(
        _ generationID: String
    ) async throws {
        _ = generationID
    }

    public func isCanonicalGenerationApplied(
        _ generationID: String
    ) async throws -> Bool {
        _ = generationID
        return false
    }
}

public protocol FamilySyncCanonicalRecoveryProviding: Sendable {
    func canonicalRecoveryPlan() async throws -> FamilySyncCanonicalRecoveryPlan

    func recoverCanonicalLocalData(
        authorization: FamilySyncCanonicalRecoveryAuthorization
    ) async throws -> FamilySyncCanonicalRecoveryReceipt
}
