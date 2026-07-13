import Foundation

public enum FamilySyncRecordKind: String, Codable, CaseIterable, Hashable, Sendable {
    case profile
    case wordPoolEntry
    case practiceSettings
    case attempt
    case attemptCorrection
    case wordProgress
    case dailyPlan
    case dailyCompletion
    case rewardGrant
    case profileDeletion
}

public struct FamilySyncRecord: Codable, Hashable, Sendable {
    public let recordName: String
    public let profileID: ProfileID
    public let kind: FamilySyncRecordKind
    public let payload: Data
    public let updatedAt: Date
    public let deviceID: String
    public let isDeleted: Bool

    public init(
        recordName: String,
        profileID: ProfileID,
        kind: FamilySyncRecordKind,
        payload: Data,
        updatedAt: Date,
        deviceID: String,
        isDeleted: Bool = false
    ) {
        self.recordName =
            recordName
            .trimmingCharacters(in: .whitespacesAndNewlines)
        self.profileID = profileID
        self.kind = kind
        self.payload = payload
        self.updatedAt = updatedAt
        self.deviceID = deviceID
        self.isDeleted = isDeleted
    }
}

public enum FamilySyncCapability: Equatable, Sendable {
    case deviceOnly
    case iCloud
}

public enum FamilySyncAvailability: Equatable, Sendable {
    case available
    case deviceOnly
    case noAccount
    case restricted
    case temporarilyUnavailable
}

public enum FamilySyncStatus: Equatable, Sendable {
    case idle
    case optedOut(message: String)
    case deviceOnly(message: String)
    case syncing
    case synced(at: Date)
    case pendingOffline
    case iCloudUnavailable(message: String)
    case failed(message: String)
}

public enum FamilySyncConsentError: Error, Equatable, Sendable {
    case deviceOnly
    case optInRequired
}

public protocol FamilySyncTransport: Sendable {
    var capability: FamilySyncCapability { get }

    func availability() async -> FamilySyncAvailability

    func prepareProfileZone(_ profileID: ProfileID) async throws

    func fetchRecords(for profileID: ProfileID) async throws -> [FamilySyncRecord]

    func push(_ records: [FamilySyncRecord], for profileID: ProfileID) async throws

    func createShare(for profileID: ProfileID) async throws -> URL

    func acceptShare(at url: URL) async throws -> ProfileID
}

public protocol FamilySyncCoordinating: Sendable {
    func isEnabled() async -> Bool

    func setEnabled(_ isEnabled: Bool) async throws -> FamilySyncStatus

    func synchronize() async -> FamilySyncStatus

    func status() async -> FamilySyncStatus

    func createShare(for profileID: ProfileID) async throws -> URL

    func acceptShare(at url: URL) async throws
}

public enum FamilySyncConflictResolver {
    /// Immutable records union by stable ID. Mutable records use explicit
    /// revision timestamps and a deterministic device-ID tiebreaker.
    public static func resolved(
        local: FamilySyncRecord?,
        remote: FamilySyncRecord?
    ) -> FamilySyncRecord? {
        guard let local else { return remote }
        guard let remote else { return local }
        if local.updatedAt != remote.updatedAt {
            return local.updatedAt > remote.updatedAt ? local : remote
        }
        if local.isDeleted != remote.isDeleted {
            return local.isDeleted ? local : remote
        }
        if local.deviceID != remote.deviceID {
            return local.deviceID > remote.deviceID ? local : remote
        }
        return local.payload.lexicographicallyPrecedes(remote.payload) ? remote : local
    }
}
