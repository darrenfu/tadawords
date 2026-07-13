import Foundation
import TadaWordsDomain

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
}

public struct DailyQuestSnapshot: Codable, Equatable, Sendable {
    public static let currentSchemaVersion = 1

    public let schemaVersion: Int
    public let plans: [DailyQuestPlan]
    public let completions: [DailyQuestCompletion]
    public let rewardGrants: [RewardGrant]

    public init(
        schemaVersion: Int = Self.currentSchemaVersion,
        plans: [DailyQuestPlan],
        completions: [DailyQuestCompletion],
        rewardGrants: [RewardGrant]
    ) {
        self.schemaVersion = schemaVersion
        self.plans = plans
        self.completions = completions
        self.rewardGrants = rewardGrants
    }
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
    case invalidSnapshot(
        snapshotURL: URL,
        issue: DailyQuestSnapshotValidationIssue
    )
    case writeFailed(snapshotURL: URL, details: String)
}

public actor InMemoryDailyQuestRepository: DailyQuestHistoryRepository {
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

    public func deleteHistory(for profileID: ProfileID) async throws {
        _ = try storage.deleteHistory(for: profileID)
    }
}

/// Durable, local-only Daily Quest source of truth. One actor instance should
/// be shared per snapshot URL so all read-modify-write operations are serialized.
public actor LocalJSONDailyQuestRepository: DailyQuestHistoryRepository {
    public nonisolated let snapshotURL: URL

    private let fileManager: FileManager
    private var storage: DailyQuestStorage?
    private var loadFailure: LocalDailyQuestRepositoryError?

    public init(
        snapshotURL: URL,
        fileManager: FileManager = .default
    ) {
        self.snapshotURL = snapshotURL
        self.fileManager = fileManager
    }

    public func state(for key: DailyQuestKey) async throws -> DailyQuestState {
        try loadedStorage().state(for: key)
    }

    public func createPlanIfAbsent(
        _ plan: DailyQuestPlan
    ) async throws -> DailyQuestPlan {
        var candidate = try loadedStorage()
        let result = try candidate.createPlanIfAbsent(plan)
        guard result.inserted else { return result.plan }
        try persist(candidate)
        storage = candidate
        return result.plan
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

    public func deleteHistory(for profileID: ProfileID) async throws {
        var candidate = try loadedStorage()
        guard try candidate.deleteHistory(for: profileID) else { return }
        try persist(candidate)
        storage = candidate
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
        guard snapshot.schemaVersion == DailyQuestSnapshot.currentSchemaVersion else {
            throw LocalDailyQuestRepositoryError.unsupportedSchemaVersion(
                snapshotURL: snapshotURL,
                found: snapshot.schemaVersion,
                supported: DailyQuestSnapshot.currentSchemaVersion
            )
        }

        do {
            return try DailyQuestStorage(snapshot: snapshot)
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
