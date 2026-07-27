import Foundation
import TadaWordsDomain

public actor CanonicalFamilySyncRecoveryCoordinator:
    FamilySyncCanonicalRecoveryProviding
{
    private let store: any FamilySyncRecordStore
    private let transport: any FamilySyncTransport
    private let journal: any FamilySyncJournalRepository
    private let installationID: String
    private let clock: any AppClock

    public init(
        store: any FamilySyncRecordStore,
        transport: any FamilySyncTransport,
        journal: any FamilySyncJournalRepository,
        installationID: String,
        clock: any AppClock = SystemAppClock()
    ) {
        self.store = store
        self.transport = transport
        self.journal = journal
        self.installationID = installationID.trimmingCharacters(
            in: .whitespacesAndNewlines
        )
        self.clock = clock
    }

    public func canonicalRecoveryPlan() async throws
        -> FamilySyncCanonicalRecoveryPlan
    {
        let snapshot = try await localSnapshot()
        return Self.plan(records: snapshot, installationID: installationID)
    }

    public func recoverCanonicalLocalData(
        authorization: FamilySyncCanonicalRecoveryAuthorization
    ) async throws -> FamilySyncCanonicalRecoveryReceipt {
        guard Self.isSHA256(authorization.verifiedBackupSHA256) else {
            throw FamilySyncCanonicalRecoveryError.invalidBackupDigest
        }
        let before = try await localSnapshot()
        let actualPlan = Self.plan(
            records: before,
            installationID: installationID
        )
        guard actualPlan.installationID == authorization.expectedPlan.installationID
        else {
            throw FamilySyncCanonicalRecoveryError.installationMismatch
        }
        guard actualPlan.profileIDs == authorization.expectedPlan.profileIDs else {
            throw FamilySyncCanonicalRecoveryError.profileSetChanged
        }
        guard actualPlan == authorization.expectedPlan else {
            throw FamilySyncCanonicalRecoveryError.localSnapshotChanged
        }
        guard
            let recoveryTransport =
                transport as? any FamilySyncCanonicalRecoveryTransport
        else {
            throw FamilySyncCanonicalRecoveryError.unavailable
        }

        let receipt = try await recoveryTransport.replaceRemoteWithCanonicalRecords(
            before,
            authorization: authorization
        )
        let after = try await localSnapshot()
        guard
            Self.plan(records: after, installationID: installationID)
                == authorization.expectedPlan
        else {
            throw FamilySyncCanonicalRecoveryError.localSnapshotChanged
        }
        guard
            receipt.recoveredRecordCount == before.count,
            receipt.verifiedRemoteFingerprint
                == authorization.expectedPlan.recordSetFingerprint
        else {
            throw FamilySyncCanonicalRecoveryError.remoteVerificationFailed
        }

        let acknowledgements = Set(
            before.map {
                FamilySyncChangeAcknowledgement(
                    operation: .save($0)
                )
            }
        )
        try await journal.recordTransportResult(
            acknowledged: acknowledgements,
            failures: [],
            at: clock.now
        )
        return receipt
    }

    private func localSnapshot() async throws -> [FamilySyncRecord] {
        let profileIDs = try await store.profileIDsForSync().sorted {
            $0.description < $1.description
        }
        var records: [FamilySyncRecord] = []
        for profileID in profileIDs {
            let profileRecords = try await store.records(for: profileID)
            try await store.validate(profileRecords, for: profileID)
            records.append(contentsOf: profileRecords)
        }
        return records.sorted(by: Self.recordOrder)
    }

    private static func plan(
        records: [FamilySyncRecord],
        installationID: String
    ) -> FamilySyncCanonicalRecoveryPlan {
        FamilySyncCanonicalRecoveryPlan(
            profileIDs: Array(Set(records.map(\.profileID))),
            recordCount: records.count,
            recordCountsByKind: Dictionary(
                grouping: records,
                by: \.kind
            ).mapValues(\.count),
            recordSetFingerprint: FamilySyncRecordSetFingerprint(records: records),
            installationID: installationID
        )
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

    private static func isSHA256(_ value: String) -> Bool {
        value.count == 64
            && value.allSatisfy {
                $0.isNumber || ("a"..."f").contains($0.lowercased())
            }
    }
}
