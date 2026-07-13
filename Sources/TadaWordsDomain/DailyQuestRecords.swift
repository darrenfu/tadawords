import Foundation

public struct DailyQuestCompletionID: RawRepresentable, Codable, Hashable,
    Sendable, CustomStringConvertible
{
    public let rawValue: UUID

    public init(rawValue: UUID = UUID()) {
        self.rawValue = rawValue
    }

    public var description: String { rawValue.uuidString }
}

public struct RewardGrantID: RawRepresentable, Codable, Hashable, Sendable,
    CustomStringConvertible
{
    public let rawValue: UUID

    public init(rawValue: UUID = UUID()) {
        self.rawValue = rawValue
    }

    public var description: String { rawValue.uuidString }
}

public struct RewardItemID: RawRepresentable, Codable, Hashable, Sendable,
    CustomStringConvertible
{
    public let rawValue: String

    public init(rawValue: String) {
        self.rawValue = rawValue
    }

    public var description: String { rawValue }
}

public struct LocalDay: Codable, Hashable, Sendable, Comparable,
    CustomStringConvertible
{
    public let year: Int
    public let month: Int
    public let day: Int

    public init(year: Int, month: Int, day: Int) throws {
        guard Self.isValid(year: year, month: month, day: day) else {
            throw LocalDayError.invalidDate(year: year, month: month, day: day)
        }
        self.year = year
        self.month = month
        self.day = day
    }

    public init(date: Date, timeZone: TimeZone) {
        var calendar = Calendar(identifier: .gregorian)
        calendar.locale = Locale(identifier: "en_US_POSIX")
        calendar.timeZone = timeZone
        let components = calendar.dateComponents([.year, .month, .day], from: date)
        year = components.year!
        month = components.month!
        day = components.day!
    }

    public var description: String {
        String(format: "%04d-%02d-%02d", year, month, day)
    }

    public static func < (left: LocalDay, right: LocalDay) -> Bool {
        (left.year, left.month, left.day) < (right.year, right.month, right.day)
    }

    public init(from decoder: any Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        let year = try values.decode(Int.self, forKey: .year)
        let month = try values.decode(Int.self, forKey: .month)
        let day = try values.decode(Int.self, forKey: .day)
        try self.init(year: year, month: month, day: day)
    }

    private enum CodingKeys: String, CodingKey {
        case year
        case month
        case day
    }

    private static func isValid(year: Int, month: Int, day: Int) -> Bool {
        var calendar = Calendar(identifier: .gregorian)
        calendar.locale = Locale(identifier: "en_US_POSIX")
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let components = DateComponents(
            calendar: calendar,
            timeZone: calendar.timeZone,
            year: year,
            month: month,
            day: day
        )
        guard let date = calendar.date(from: components) else { return false }
        let roundTrip = calendar.dateComponents([.year, .month, .day], from: date)
        return roundTrip.year == year
            && roundTrip.month == month
            && roundTrip.day == day
    }
}

public enum LocalDayError: Error, Equatable, Sendable {
    case invalidDate(year: Int, month: Int, day: Int)
}

/// A Gregorian calendar month in the device's local calendar. Keeping this as
/// year/month components avoids converting a stored local day back through an
/// absolute `Date`, which could move it across a boundary in another time zone.
public struct LocalMonth: Hashable, Sendable, Comparable, CustomStringConvertible {
    public let year: Int
    public let month: Int

    public init(year: Int, month: Int) throws {
        guard (1...12).contains(month) else {
            throw LocalMonthError.invalidMonth(year: year, month: month)
        }
        self.year = year
        self.month = month
    }

    public init(date: Date, timeZone: TimeZone) {
        let localDay = LocalDay(date: date, timeZone: timeZone)
        year = localDay.year
        month = localDay.month
    }

    public var description: String {
        String(format: "%04d-%02d", year, month)
    }

    public func contains(_ localDay: LocalDay) -> Bool {
        localDay.year == year && localDay.month == month
    }

    public static func < (left: LocalMonth, right: LocalMonth) -> Bool {
        (left.year, left.month) < (right.year, right.month)
    }
}

public enum LocalMonthError: Error, Equatable, Sendable {
    case invalidMonth(year: Int, month: Int)
}

/// Read model for one profile's completed quest runs in a local month.
/// Every persisted completion counts once, including Practice Again.
public struct DailyQuestMonthSummary: Equatable, Sendable {
    public let profileID: ProfileID
    public let month: LocalMonth
    public let completionCountByDay: [LocalDay: Int]

    public init(
        profileID: ProfileID,
        month: LocalMonth,
        completions: [DailyQuestCompletion]
    ) {
        self.profileID = profileID
        self.month = month
        completionCountByDay = completions.reduce(into: [:]) { counts, completion in
            guard completion.profileID == profileID,
                month.contains(completion.localDay)
            else { return }
            counts[completion.localDay, default: 0] += 1
        }
    }

    public static func empty(
        profileID: ProfileID,
        month: LocalMonth
    ) -> DailyQuestMonthSummary {
        DailyQuestMonthSummary(
            profileID: profileID,
            month: month,
            completions: []
        )
    }

    public func completionCount(on localDay: LocalDay) -> Int {
        completionCountByDay[localDay, default: 0]
    }
}

public struct DailyQuestKey: Codable, Hashable, Sendable {
    public let profileID: ProfileID
    public let learningMode: LearningMode
    public let localDay: LocalDay

    public init(
        profileID: ProfileID,
        learningMode: LearningMode,
        localDay: LocalDay
    ) {
        self.profileID = profileID
        self.learningMode = learningMode
        self.localDay = localDay
    }
}

public struct DailyQuestPlan: Codable, Hashable, Sendable {
    public let localDay: LocalDay
    public let questPlan: QuestPlan

    public init(localDay: LocalDay, questPlan: QuestPlan) {
        self.localDay = localDay
        self.questPlan = questPlan
    }

    public var id: QuestID { questPlan.id }

    public var key: DailyQuestKey {
        DailyQuestKey(
            profileID: questPlan.profileID,
            learningMode: questPlan.configuration.learningMode,
            localDay: localDay
        )
    }
}

public enum DailyQuestRunKind: String, Codable, CaseIterable, Hashable, Sendable {
    case today
    case practiceAgain
}

public struct DailyQuestCompletion: Codable, Hashable, Sendable {
    public let id: DailyQuestCompletionID
    public let dailyPlanID: QuestID
    public let runQuestID: QuestID
    public let profileID: ProfileID
    public let learningMode: LearningMode
    public let localDay: LocalDay
    public let runKind: DailyQuestRunKind
    public let points: Int
    public let stars: QuestStars
    public let completedAt: Date

    public init(
        id: DailyQuestCompletionID = DailyQuestCompletionID(),
        dailyPlanID: QuestID,
        runQuestID: QuestID,
        profileID: ProfileID,
        learningMode: LearningMode,
        localDay: LocalDay,
        runKind: DailyQuestRunKind,
        points: Int,
        stars: QuestStars,
        completedAt: Date
    ) {
        self.id = id
        self.dailyPlanID = dailyPlanID
        self.runQuestID = runQuestID
        self.profileID = profileID
        self.learningMode = learningMode
        self.localDay = localDay
        self.runKind = runKind
        self.points = max(0, points)
        self.stars = stars
        self.completedAt = completedAt
    }

    public var key: DailyQuestKey {
        DailyQuestKey(
            profileID: profileID,
            learningMode: learningMode,
            localDay: localDay
        )
    }
}

public struct RewardCatalogItem: Codable, Hashable, Sendable {
    public let id: RewardItemID
    public let world: WorldTheme
    public let displayName: String
    public let tier: RewardTier
    /// Milestones are derived from the number of completed Today quests in
    /// this world. Small collectibles leave this value nil.
    public let requiredTodayQuestCount: Int?

    public init(
        id: RewardItemID,
        world: WorldTheme,
        displayName: String,
        tier: RewardTier = .smallCollectible,
        requiredTodayQuestCount: Int? = nil
    ) {
        self.id = id
        self.world = world
        self.displayName = displayName
        self.tier = tier
        self.requiredTodayQuestCount =
            tier == .milestone
            ? max(1, requiredTodayQuestCount ?? 1)
            : nil
    }

    private enum CodingKeys: String, CodingKey {
        case id
        case world
        case displayName
        case tier
        case requiredTodayQuestCount
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            id: try container.decode(RewardItemID.self, forKey: .id),
            world: try container.decode(WorldTheme.self, forKey: .world),
            displayName: try container.decode(String.self, forKey: .displayName),
            tier: try container.decodeIfPresent(RewardTier.self, forKey: .tier)
                ?? .smallCollectible,
            requiredTodayQuestCount: try container.decodeIfPresent(
                Int.self,
                forKey: .requiredTodayQuestCount
            )
        )
    }
}

public enum RewardTier: String, Codable, CaseIterable, Hashable, Sendable {
    case smallCollectible
    case milestone
}

public struct RewardGrantKey: Codable, Hashable, Sendable {
    public let profileID: ProfileID
    public let world: WorldTheme
    public let localDay: LocalDay
    public let learningMode: LearningMode

    public init(
        profileID: ProfileID,
        world: WorldTheme,
        localDay: LocalDay,
        learningMode: LearningMode
    ) {
        self.profileID = profileID
        self.world = world
        self.localDay = localDay
        self.learningMode = learningMode
    }
}

public struct RewardGrant: Codable, Hashable, Sendable {
    public let id: RewardGrantID
    public let key: RewardGrantKey
    public let dailyPlanID: QuestID
    public let completionID: DailyQuestCompletionID
    public let item: RewardCatalogItem
    public let grantedAt: Date

    public init(
        id: RewardGrantID = RewardGrantID(),
        key: RewardGrantKey,
        dailyPlanID: QuestID,
        completionID: DailyQuestCompletionID,
        item: RewardCatalogItem,
        grantedAt: Date
    ) {
        self.id = id
        self.key = key
        self.dailyPlanID = dailyPlanID
        self.completionID = completionID
        self.item = item
        self.grantedAt = grantedAt
    }
}

public struct DailyQuestState: Hashable, Sendable {
    public let plan: DailyQuestPlan?
    public let todayCompletion: DailyQuestCompletion?
    public let rewardGrant: RewardGrant?

    public init(
        plan: DailyQuestPlan?,
        todayCompletion: DailyQuestCompletion?,
        rewardGrant: RewardGrant?
    ) {
        self.plan = plan
        self.todayCompletion = todayCompletion
        self.rewardGrant = rewardGrant
    }
}

public struct DailyQuestCompletionWriteResult: Hashable, Sendable {
    public let completion: DailyQuestCompletion
    public let rewardGrant: RewardGrant?
    public let insertedCompletion: Bool
    public let grantedReward: Bool

    public init(
        completion: DailyQuestCompletion,
        rewardGrant: RewardGrant?,
        insertedCompletion: Bool,
        grantedReward: Bool
    ) {
        self.completion = completion
        self.rewardGrant = rewardGrant
        self.insertedCompletion = insertedCompletion
        self.grantedReward = grantedReward
    }
}

public protocol DailyQuestRepository: Sendable {
    func state(for key: DailyQuestKey) async throws -> DailyQuestState

    /// Returns the existing plan when the key is already present. This is the
    /// idempotency boundary that keeps today's content stable across restarts.
    func createPlanIfAbsent(_ plan: DailyQuestPlan) async throws -> DailyQuestPlan

    func completions(for key: DailyQuestKey) async throws -> [DailyQuestCompletion]

    /// Returns only this profile's persisted runs in the requested local
    /// month. Implementations must fail closed when their durable snapshot is
    /// unreadable rather than presenting an invented empty month.
    func completions(
        for profileID: ProfileID,
        in month: LocalMonth
    ) async throws -> [DailyQuestCompletion]

    /// Completion and its first-Today reward are committed atomically.
    func recordCompletion(
        _ completion: DailyQuestCompletion,
        proposedRewardGrant: RewardGrant?
    ) async throws -> DailyQuestCompletionWriteResult
}

/// Extended local-history operations used by Collection, reports, and profile
/// lifecycle management. Keeping this separate preserves lightweight quest
/// test doubles that only implement the daily runtime contract.
public protocol DailyQuestHistoryRepository: DailyQuestRepository {
    func allPlans(for profileID: ProfileID) async throws -> [DailyQuestPlan]

    func allCompletions(
        for profileID: ProfileID
    ) async throws -> [DailyQuestCompletion]

    func rewardGrants(
        for profileID: ProfileID
    ) async throws -> [RewardGrant]

    func deleteHistory(for profileID: ProfileID) async throws
}

extension DailyQuestHistoryRepository {
    public func allPlans(for profileID: ProfileID) async throws -> [DailyQuestPlan] {
        _ = profileID
        return []
    }
}
