import Foundation
import TadaWordsDomain

public protocol FamilySyncRecordStore: Sendable {
    func profileIDsForSync() async throws -> [ProfileID]

    func records(for profileID: ProfileID) async throws -> [FamilySyncRecord]

    func apply(_ records: [FamilySyncRecord], for profileID: ProfileID) async throws
}

/// Keeps the learning path local-first: sync is an explicit side effect that
/// runs after durable local writes and never participates in a quest commit.
public actor LocalFirstFamilySyncCoordinator: FamilySyncCoordinating {
    private let store: any FamilySyncRecordStore
    private let transport: any FamilySyncTransport
    private let preferenceRepository: any FamilySyncPreferenceRepository
    private let clock: any AppClock
    private var currentStatus: FamilySyncStatus = .idle

    public init(
        store: any FamilySyncRecordStore,
        transport: any FamilySyncTransport,
        preferenceRepository: any FamilySyncPreferenceRepository =
            InMemoryFamilySyncPreferenceRepository(),
        clock: any AppClock = SystemAppClock()
    ) {
        self.store = store
        self.transport = transport
        self.preferenceRepository = preferenceRepository
        self.clock = clock
    }

    public func isEnabled() async -> Bool {
        guard transport.capability == .iCloud else { return false }
        return (try? await preferenceRepository.isEnabled()) ?? false
    }

    public func setEnabled(_ isEnabled: Bool) async throws -> FamilySyncStatus {
        guard transport.capability == .iCloud else {
            if isEnabled {
                throw FamilySyncConsentError.deviceOnly
            }
            currentStatus = Self.deviceOnlyStatus
            return currentStatus
        }

        try await preferenceRepository.setEnabled(isEnabled, updatedAt: clock.now)
        guard isEnabled else {
            currentStatus = Self.optedOutStatus
            return currentStatus
        }
        return await synchronize()
    }

    public func synchronize() async -> FamilySyncStatus {
        guard transport.capability == .iCloud else {
            currentStatus = Self.deviceOnlyStatus
            return currentStatus
        }
        guard await isEnabled() else {
            currentStatus = Self.optedOutStatus
            return currentStatus
        }

        currentStatus = .syncing
        let availability = await transport.availability()
        guard availability == .available else {
            switch availability {
            case .available:
                break
            case .deviceOnly:
                currentStatus = Self.deviceOnlyStatus
            case .temporarilyUnavailable:
                currentStatus = .pendingOffline
            case .noAccount, .restricted:
                currentStatus = .iCloudUnavailable(
                    message: Self.message(for: availability)
                )
            }
            return currentStatus
        }

        do {
            let profileIDs = try await store.profileIDsForSync()
            for profileID in profileIDs {
                try await synchronize(profileID: profileID)
            }
            currentStatus = .synced(at: clock.now)
        } catch {
            currentStatus = .failed(message: Self.privacySafeMessage(for: error))
        }
        return currentStatus
    }

    public func status() async -> FamilySyncStatus {
        guard transport.capability == .iCloud else {
            currentStatus = Self.deviceOnlyStatus
            return currentStatus
        }
        guard await isEnabled() else {
            currentStatus = Self.optedOutStatus
            return currentStatus
        }
        return currentStatus
    }

    public func createShare(for profileID: ProfileID) async throws -> URL {
        guard transport.capability == .iCloud else {
            throw FamilySyncConsentError.deviceOnly
        }
        guard await isEnabled() else {
            throw FamilySyncConsentError.optInRequired
        }
        return try await transport.createShare(for: profileID)
    }

    public func acceptShare(at url: URL) async throws {
        guard transport.capability == .iCloud else {
            throw FamilySyncConsentError.deviceOnly
        }
        guard await isEnabled() else {
            throw FamilySyncConsentError.optInRequired
        }
        let profileID = try await transport.acceptShare(at: url)
        currentStatus = .syncing
        do {
            try await synchronize(profileID: profileID)
            currentStatus = .synced(at: clock.now)
        } catch {
            currentStatus = .failed(message: Self.privacySafeMessage(for: error))
            throw error
        }
    }

    private func synchronize(profileID: ProfileID) async throws {
        async let localRecords = store.records(for: profileID)
        async let remoteRecords = transport.fetchRecords(for: profileID)
        let local = try await localRecords
        let remote = try await remoteRecords

        let localByName = Dictionary(
            uniqueKeysWithValues: local.map {
                ($0.recordName, $0)
            })
        let remoteByName = Dictionary(
            uniqueKeysWithValues: remote.map {
                ($0.recordName, $0)
            })
        let names = Set(localByName.keys).union(remoteByName.keys)
        let resolved = names.compactMap { name in
            FamilySyncConflictResolver.resolved(
                local: localByName[name],
                remote: remoteByName[name]
            )
        }.sorted { $0.recordName < $1.recordName }

        let recordsToApply = resolved.filter { resolvedRecord in
            localByName[resolvedRecord.recordName] != resolvedRecord
        }
        if !recordsToApply.isEmpty {
            try await store.apply(recordsToApply, for: profileID)
        }
        try await transport.push(resolved, for: profileID)
    }

    private static func message(for availability: FamilySyncAvailability) -> String {
        switch availability {
        case .available:
            "Sync is available."
        case .deviceOnly:
            "This version keeps learning data on this device."
        case .noAccount:
            "Sign in to iCloud to sync Tada Words."
        case .restricted:
            "iCloud sync is restricted on this device."
        case .temporarilyUnavailable:
            "Sync will retry when iCloud is available."
        }
    }

    private static func privacySafeMessage(for error: Error) -> String {
        _ = error
        return "Sync could not finish. Local learning data is safe and will retry."
    }

    private static let optedOutStatus = FamilySyncStatus.optedOut(
        message:
            "Family sync is off. Learning data stays on this device until a parent turns it on."
    )

    private static let deviceOnlyStatus = FamilySyncStatus.deviceOnly(
        message:
            "This version keeps learning data on this device. Family sync and invitations are unavailable."
    )
}
