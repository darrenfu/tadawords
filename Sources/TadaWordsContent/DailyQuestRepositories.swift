import Foundation
import TadaWordsDomain

/// Local repositories can atomically replace one canonical day plan when a
/// parent raises its limits. The stable plan ID keeps attempts, completion,
/// and reward references intact.
protocol DailyQuestPlanReconcilingRepository: DailyQuestRepository {
    func reconcileExpandedPlan(_ plan: DailyQuestPlan) async throws
        -> DailyQuestPlan
}

public enum DailyQuestRepositoryError: Error, Equatable, Sendable {
    case conflictingPlanID(QuestID)
    case conflictingCompletionID(DailyQuestCompletionID)
    case planNotFound(QuestID)
    case completionDoesNotMatchPlan(DailyQuestCompletionID)
    case todayAlreadyCompleted(DailyQuestCompletionID)
    case missingTodayReward(DailyQuestCompletionID)
    case practiceAgainCannotGrantReward
    case conflictingRewardGrantID(RewardGrantID)
    case rewardAlreadyGranted(RewardGrantKey)
    case rewardDoesNotMatchCompletion(RewardGrantID)
    case conflictingCanonicalPlan(DailyQuestKey)
    case conflictingCanonicalTodayCompletion(DailyQuestKey)
    case conflictingCanonicalReward(DailyQuestKey)
    case incompleteCanonicalToday(DailyQuestKey)
    case canonicalPlanNotFound(DailyQuestKey)
}

public struct DailyQuestSnapshot: Codable, Equatable, Sendable {
    public static let currentSchemaVersion = 3
    public static let currentCanonicalBusinessKeyVersion = 1

    public let schemaVersion: Int
    public let canonicalBusinessKeyVersion: Int
    public let plans: [DailyQuestPlan]
    public let completions: [DailyQuestCompletion]
    public let rewardGrants: [RewardGrant]
    /// Sync deliveries are not dependency-atomic. These durable staging sets
    /// hold otherwise-valid facts until their plan/completion/reward chain is
    /// complete, including across process termination.
    public let pendingCompletions: [DailyQuestCompletion]
    public let pendingRewardGrants: [RewardGrant]

    public init(
        schemaVersion: Int = Self.currentSchemaVersion,
        canonicalBusinessKeyVersion: Int? = nil,
        plans: [DailyQuestPlan],
        completions: [DailyQuestCompletion],
        rewardGrants: [RewardGrant],
        pendingCompletions: [DailyQuestCompletion] = [],
        pendingRewardGrants: [RewardGrant] = []
    ) {
        self.schemaVersion = schemaVersion
        self.canonicalBusinessKeyVersion =
            canonicalBusinessKeyVersion
            ?? (schemaVersion == Self.currentSchemaVersion
                ? Self.currentCanonicalBusinessKeyVersion
                : 0)
        self.plans = plans
        self.completions = completions
        self.rewardGrants = rewardGrants
        self.pendingCompletions = pendingCompletions
        self.pendingRewardGrants = pendingRewardGrants
    }

    private enum CodingKeys: String, CodingKey {
        case schemaVersion
        case canonicalBusinessKeyVersion
        case plans
        case completions
        case rewardGrants
        case pendingCompletions
        case pendingRewardGrants
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let schemaVersion = try container.decode(
            Int.self,
            forKey: .schemaVersion
        )
        self.init(
            schemaVersion: schemaVersion,
            canonicalBusinessKeyVersion: try container.decodeIfPresent(
                Int.self,
                forKey: .canonicalBusinessKeyVersion
            ) ?? 0,
            plans: try container.decode(
                [DailyQuestPlan].self,
                forKey: .plans
            ),
            completions: try container.decode(
                [DailyQuestCompletion].self,
                forKey: .completions
            ),
            rewardGrants: try container.decode(
                [RewardGrant].self,
                forKey: .rewardGrants
            ),
            pendingCompletions: try container.decodeIfPresent(
                [DailyQuestCompletion].self,
                forKey: .pendingCompletions
            ) ?? [],
            pendingRewardGrants: try container.decodeIfPresent(
                [RewardGrant].self,
                forKey: .pendingRewardGrants
            ) ?? []
        )
    }
}

/// Family-sync delivery can split a Daily plan, completion, and reward across
/// separate CKSyncEngine batches. This protocol is deliberately separate from
/// the app's dependency-closed `mergeCanonical` API so local quest completion
/// still commits its reward atomically.
public protocol CausallyStagedDailyQuestHistoryRepository: Sendable {
    func stageCanonical(
        _ batch: DailyQuestCanonicalMergeBatch
    ) async throws -> DailyQuestCanonicalMergeResult
}

public enum DailyQuestSnapshotValidationIssue: Equatable, Sendable {
    case duplicatePlanID(QuestID)
    case duplicatePlanKey(DailyQuestKey)
    case duplicateCompletionID(DailyQuestCompletionID)
    case duplicateTodayCompletion(dailyPlanID: QuestID)
    case orphanCompletion(
        completionID: DailyQuestCompletionID,
        dailyPlanID: QuestID
    )
    case completionDoesNotMatchPlan(DailyQuestCompletionID)
    case duplicateRewardGrantID(RewardGrantID)
    case duplicateRewardGrantKey(RewardGrantKey)
    case orphanRewardGrant(
        rewardGrantID: RewardGrantID,
        completionID: DailyQuestCompletionID
    )
    case duplicateRewardForCompletion(DailyQuestCompletionID)
    case missingRewardForTodayCompletion(DailyQuestCompletionID)
    case rewardGrantDoesNotMatchCompletion(RewardGrantID)
}

public enum LocalDailyQuestRepositoryError: Error, Equatable, Sendable {
    case readFailed(snapshotURL: URL, details: String)
    case invalidJSON(snapshotURL: URL, details: String)
    case unsupportedSchemaVersion(
        snapshotURL: URL,
        found: Int,
        supported: Int
    )
    case unsupportedCanonicalBusinessKeyVersion(
        snapshotURL: URL,
        found: Int,
        supported: Int
    )
    case invalidSnapshot(
        snapshotURL: URL,
        issue: DailyQuestSnapshotValidationIssue
    )
    case writeFailed(snapshotURL: URL, details: String)
}

public actor InMemoryDailyQuestRepository: DailyQuestHistoryRepository,
    CausallyStagedDailyQuestHistoryRepository,
    DailyQuestPlanReconcilingRepository
{
    private var storage = DailyQuestStorage()

    public init() {}

    public func state(for key: DailyQuestKey) async throws -> DailyQuestState {
        storage.state(for: key)
    }

    public func createPlanIfAbsent(
        _ plan: DailyQuestPlan
    ) async throws -> DailyQuestPlan {
        try storage.createPlanIfAbsent(plan).plan
    }

    func reconcileExpandedPlan(_ plan: DailyQuestPlan) async throws
        -> DailyQuestPlan
    {
        try storage.reconcileExpandedPlan(plan).plan
    }

    public func completions(
        for key: DailyQuestKey
    ) async throws -> [DailyQuestCompletion] {
        storage.completions(for: key)
    }

    public func completions(
        for profileID: ProfileID,
        in month: LocalMonth
    ) async throws -> [DailyQuestCompletion] {
        storage.completions(for: profileID, in: month)
    }

    public func recordCompletion(
        _ completion: DailyQuestCompletion,
        proposedRewardGrant: RewardGrant?
    ) async throws -> DailyQuestCompletionWriteResult {
        try storage.recordCompletion(
            completion,
            proposedRewardGrant: proposedRewardGrant
        )
    }

    public func allCompletions(
        for profileID: ProfileID
    ) async throws -> [DailyQuestCompletion] {
        storage.allCompletions(for: profileID)
    }

    public func allPlans(
        for profileID: ProfileID
    ) async throws -> [DailyQuestPlan] {
        storage.allPlans(for: profileID)
    }

    public func rewardGrants(
        for profileID: ProfileID
    ) async throws -> [RewardGrant] {
        storage.rewardGrants(for: profileID)
    }

    public func mergeCanonical(
        _ batch: DailyQuestCanonicalMergeBatch
    ) async throws -> DailyQuestCanonicalMergeResult {
        guard !batch.isEmpty else {
            return DailyQuestCanonicalMergeResult(
                didChange: false,
                affectedKeys: []
            )
        }
        var candidate = storage
        let result = try candidate.mergeCanonical(batch)
        storage = candidate
        return result
    }

    public func stageCanonical(
        _ batch: DailyQuestCanonicalMergeBatch
    ) async throws -> DailyQuestCanonicalMergeResult {
        guard !batch.isEmpty else {
            return DailyQuestCanonicalMergeResult(
                didChange: false,
                affectedKeys: []
            )
        }
        var candidate = storage
        let result = try candidate.stageCanonical(batch)
        storage = candidate
        return result
    }

    public func deleteHistory(for profileID: ProfileID) async throws {
        _ = try storage.deleteHistory(for: profileID)
    }
}

/// Durable, local-only Daily Quest source of truth. One actor instance should
/// be shared per snapshot URL so all read-modify-write operations are serialized.
public actor LocalJSONDailyQuestRepository: DailyQuestHistoryRepository,
    CausallyStagedDailyQuestHistoryRepository,
    DailyQuestPlanReconcilingRepository
{
    public nonisolated let snapshotURL: URL

    private let fileManager: FileManager
    private let mutationGate: ProfileScopedMutationGate?
    private var storage: DailyQuestStorage?
    private var loadFailure: LocalDailyQuestRepositoryError?

    public init(
        snapshotURL: URL,
        fileManager: FileManager = .default,
        mutationGate: ProfileScopedMutationGate? = nil
    ) {
        self.snapshotURL = snapshotURL
        self.fileManager = fileManager
        self.mutationGate = mutationGate
    }

    public func state(for key: DailyQuestKey) async throws -> DailyQuestState {
        try loadedStorage().state(for: key)
    }

    public func createPlanIfAbsent(
        _ plan: DailyQuestPlan
    ) async throws -> DailyQuestPlan {
        try await withMutationLeases(for: [plan.key.profileID]) {
            var candidate = try loadedStorage()
            let result = try candidate.createPlanIfAbsent(plan)
            guard result.inserted else { return result.plan }
            try persist(candidate)
            storage = candidate
            return result.plan
        }
    }

    func reconcileExpandedPlan(_ plan: DailyQuestPlan) async throws
        -> DailyQuestPlan
    {
        try await withMutationLeases(for: [plan.key.profileID]) {
            var candidate = try loadedStorage()
            let result = try candidate.reconcileExpandedPlan(plan)
            guard result.didChange else { return result.plan }
            try persist(candidate)
            storage = candidate
            return result.plan
        }
    }

    public func completions(
        for key: DailyQuestKey
    ) async throws -> [DailyQuestCompletion] {
        try loadedStorage().completions(for: key)
    }

    public func completions(
        for profileID: ProfileID,
        in month: LocalMonth
    ) async throws -> [DailyQuestCompletion] {
        try loadedStorage().completions(for: profileID, in: month)
    }

    public func recordCompletion(
        _ completion: DailyQuestCompletion,
        proposedRewardGrant: RewardGrant?
    ) async throws -> DailyQuestCompletionWriteResult {
        try await withMutationLeases(for: [completion.profileID]) {
            var candidate = try loadedStorage()
            let result = try candidate.recordCompletion(
                completion,
                proposedRewardGrant: proposedRewardGrant
            )
            guard result.insertedCompletion || result.grantedReward else {
                return result
            }
            try persist(candidate)
            storage = candidate
            return result
        }
    }

    public func allCompletions(
        for profileID: ProfileID
    ) async throws -> [DailyQuestCompletion] {
        try loadedStorage().allCompletions(for: profileID)
    }

    public func allPlans(
        for profileID: ProfileID
    ) async throws -> [DailyQuestPlan] {
        try loadedStorage().allPlans(for: profileID)
    }

    public func rewardGrants(
        for profileID: ProfileID
    ) async throws -> [RewardGrant] {
        try loadedStorage().rewardGrants(for: profileID)
    }

    public func mergeCanonical(
        _ batch: DailyQuestCanonicalMergeBatch
    ) async throws -> DailyQuestCanonicalMergeResult {
        guard !batch.isEmpty else {
            return DailyQuestCanonicalMergeResult(
                didChange: false,
                affectedKeys: []
            )
        }
        let profileIDs = Set(batch.plans.map { $0.key.profileID })
            .union(batch.completions.map(\.profileID))
            .union(batch.rewardGrants.map { $0.key.profileID })
        return try await withMutationLeases(for: profileIDs) {
            var candidate = try loadedStorage()
            let result = try candidate.mergeCanonical(batch)
            guard result.didChange else { return result }
            try persist(candidate)
            storage = candidate
            return result
        }
    }

    public func stageCanonical(
        _ batch: DailyQuestCanonicalMergeBatch
    ) async throws -> DailyQuestCanonicalMergeResult {
        guard !batch.isEmpty else {
            return DailyQuestCanonicalMergeResult(
                didChange: false,
                affectedKeys: []
            )
        }
        let profileIDs = Set(batch.plans.map { $0.key.profileID })
            .union(batch.completions.map(\.profileID))
            .union(batch.rewardGrants.map { $0.key.profileID })
        return try await withMutationLeases(for: profileIDs) {
            var candidate = try loadedStorage()
            let result = try candidate.stageCanonical(batch)
            guard result.didChange else { return result }
            try persist(candidate)
            storage = candidate
            return result
        }
    }

    public func deleteHistory(for profileID: ProfileID) async throws {
        try await withMutationLeases(for: [profileID]) {
            var candidate = try loadedStorage()
            guard try candidate.deleteHistory(for: profileID) else { return }
            try persist(candidate)
            storage = candidate
        }
    }

    private func withMutationLeases<Value>(
        for profileIDs: Set<ProfileID>,
        _ operation: () throws -> Value
    ) async throws -> Value {
        guard let mutationGate else { return try operation() }
        let ids =
            profileIDs
            .filter { ProfileScopedMutationLeaseContext.profileID != $0 }
            .sorted { $0.description < $1.description }
        var acquiredIDs: [ProfileID] = []
        do {
            for id in ids {
                try await mutationGate.acquire(id)
                acquiredIDs.append(id)
            }
            let value = try operation()
            for id in acquiredIDs.reversed() { await mutationGate.release(id) }
            return value
        } catch {
            for id in acquiredIDs.reversed() { await mutationGate.release(id) }
            throw error
        }
    }

    /// Retries only after the caller repairs or restores the snapshot. A
    /// corrupt file remains preserved and latched until this explicit action.
    public func reloadFromDisk() throws {
        storage = nil
        loadFailure = nil
        _ = try loadedStorage()
    }

    private func loadedStorage() throws -> DailyQuestStorage {
        if let loadFailure { throw loadFailure }
        if let storage { return storage }

        do {
            let loaded = try readStorage()
            storage = loaded
            return loaded
        } catch let error as LocalDailyQuestRepositoryError {
            loadFailure = error
            throw error
        } catch {
            let wrapped = LocalDailyQuestRepositoryError.readFailed(
                snapshotURL: snapshotURL,
                details: String(describing: error)
            )
            loadFailure = wrapped
            throw wrapped
        }
    }

    private func readStorage() throws -> DailyQuestStorage {
        let data: Data?
        do {
            data = try snapshotFile.readIfPresent()
        } catch {
            throw LocalDailyQuestRepositoryError.readFailed(
                snapshotURL: snapshotURL,
                details: String(describing: error)
            )
        }
        guard let data else { return DailyQuestStorage() }

        let snapshot: DailyQuestSnapshot
        do {
            snapshot = try InspectableSnapshotJSONCodec.makeDecoder().decode(
                DailyQuestSnapshot.self,
                from: data
            )
        } catch {
            throw LocalDailyQuestRepositoryError.invalidJSON(
                snapshotURL: snapshotURL,
                details: String(describing: error)
            )
        }
        guard
            (1...DailyQuestSnapshot.currentSchemaVersion).contains(
                snapshot.schemaVersion
            )
        else {
            throw LocalDailyQuestRepositoryError.unsupportedSchemaVersion(
                snapshotURL: snapshotURL,
                found: snapshot.schemaVersion,
                supported: DailyQuestSnapshot.currentSchemaVersion
            )
        }

        do {
            let loaded = try DailyQuestStorage(snapshot: snapshot)
            if snapshot.schemaVersion < DailyQuestSnapshot.currentSchemaVersion {
                try persist(loaded)
                return loaded
            }
            guard
                snapshot.canonicalBusinessKeyVersion
                    == DailyQuestSnapshot.currentCanonicalBusinessKeyVersion
            else {
                throw
                    LocalDailyQuestRepositoryError
                    .unsupportedCanonicalBusinessKeyVersion(
                        snapshotURL: snapshotURL,
                        found: snapshot.canonicalBusinessKeyVersion,
                        supported:
                            DailyQuestSnapshot.currentCanonicalBusinessKeyVersion
                    )
            }
            return loaded
        } catch let error as DailyQuestStorageValidationError {
            throw LocalDailyQuestRepositoryError.invalidSnapshot(
                snapshotURL: snapshotURL,
                issue: Self.publicIssue(for: error)
            )
        }
    }

    private func persist(_ storage: DailyQuestStorage) throws {
        let data: Data
        do {
            data = try InspectableSnapshotJSONCodec.makeEncoder().encode(
                storage.snapshot
            )
        } catch {
            throw LocalDailyQuestRepositoryError.writeFailed(
                snapshotURL: snapshotURL,
                details: "Could not encode snapshot: \(error)"
            )
        }
        do {
            try snapshotFile.write(data)
        } catch {
            throw LocalDailyQuestRepositoryError.writeFailed(
                snapshotURL: snapshotURL,
                details: String(describing: error)
            )
        }
    }

    private var snapshotFile: AtomicSnapshotFile {
        AtomicSnapshotFile(
            snapshotURL: snapshotURL,
            fileManager: fileManager
        )
    }

    private static func publicIssue(
        for error: DailyQuestStorageValidationError
    ) -> DailyQuestSnapshotValidationIssue {
        switch error {
        case .duplicatePlanID(let id):
            .duplicatePlanID(id)
        case .duplicatePlanKey(let key):
            .duplicatePlanKey(key)
        case .duplicateCompletionID(let id):
            .duplicateCompletionID(id)
        case .duplicateTodayCompletion(let planID):
            .duplicateTodayCompletion(dailyPlanID: planID)
        case .orphanCompletion(let completionID, let planID):
            .orphanCompletion(
                completionID: completionID,
                dailyPlanID: planID
            )
        case .completionDoesNotMatchPlan(let id):
            .completionDoesNotMatchPlan(id)
        case .duplicateRewardGrantID(let id):
            .duplicateRewardGrantID(id)
        case .duplicateRewardGrantKey(let key):
            .duplicateRewardGrantKey(key)
        case .orphanRewardGrant(let grantID, let completionID):
            .orphanRewardGrant(
                rewardGrantID: grantID,
                completionID: completionID
            )
        case .duplicateRewardForCompletion(let completionID):
            .duplicateRewardForCompletion(completionID)
        case .missingRewardForTodayCompletion(let completionID):
            .missingRewardForTodayCompletion(completionID)
        case .rewardGrantDoesNotMatchCompletion(let id):
            .rewardGrantDoesNotMatchCompletion(id)
        }
    }
}
