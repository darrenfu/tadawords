import Foundation
import TadaWordsDomain

public enum GuardianWordStoreError: Error, Equatable, Sendable {
    case profileMismatch(expected: ProfileID, received: ProfileID)
    case wordNotFound(WordPromptID)
}

public enum GuardianFamilyStoreError: Error, Equatable, Sendable {
    case profileNotFound(ProfileID)
    case emptyDisplayName
    case displayNameTooLong(maximumCharacterCount: Int)
    case unsupportedAvatar(String)
    case invalidAge
    case cannotDeleteOnlyProfile
    case learningHistoryUnavailable
}

public struct GuardianFamilySnapshot: Equatable, Sendable {
    public let profiles: [KidProfile]
    public let selectedProfileID: ProfileID

    public init(profiles: [KidProfile], selectedProfileID: ProfileID) {
        self.profiles = profiles
        self.selectedProfileID = selectedProfileID
    }

    public var selectedProfile: KidProfile? {
        profiles.first(where: { $0.id == selectedProfileID })
    }
}

public struct GuardianProfileDeletionResult: Sendable {
    public let dashboard: GuardianDashboardSnapshot
    public let tombstone: ProfileDeletionTombstone

    public init(
        dashboard: GuardianDashboardSnapshot,
        tombstone: ProfileDeletionTombstone
    ) {
        self.dashboard = dashboard
        self.tombstone = tombstone
    }
}

public struct GuardianProfileDraft: Equatable, Sendable {
    public let displayName: String
    public let avatar: ProfileAvatar
    public let selectedWorld: WorldTheme
    public let schoolGrade: ProfileSchoolGrade
    public let ageYears: Int?
    public let guardianUnlockedWorlds: Set<WorldTheme>

    public var avatarAssetID: String {
        switch avatar {
        case .cartoonAnimal(let assetID), .photo(let assetID, _):
            assetID
        case .treasure(_, let iconAssetID):
            iconAssetID
        }
    }

    public init(
        displayName: String,
        avatarAssetID: String,
        selectedWorld: WorldTheme,
        schoolGrade: ProfileSchoolGrade = .preK,
        ageYears: Int? = nil,
        guardianUnlockedWorlds: Set<WorldTheme> = []
    ) {
        self.init(
            displayName: displayName,
            avatar: .cartoonAnimal(assetID: avatarAssetID),
            selectedWorld: selectedWorld,
            schoolGrade: schoolGrade,
            ageYears: ageYears,
            guardianUnlockedWorlds: guardianUnlockedWorlds
        )
    }

    public init(
        displayName: String,
        avatar: ProfileAvatar,
        selectedWorld: WorldTheme,
        schoolGrade: ProfileSchoolGrade = .preK,
        ageYears: Int? = nil,
        guardianUnlockedWorlds: Set<WorldTheme> = []
    ) {
        self.displayName = displayName
        self.avatar = avatar
        self.selectedWorld = selectedWorld
        self.schoolGrade = schoolGrade
        self.ageYears = ageYears
        self.guardianUnlockedWorlds = guardianUnlockedWorlds
    }
}

public struct GuardianAnimalAvatar: Identifiable, Equatable, Sendable {
    public static let available: [GuardianAnimalAvatar] = [
        GuardianAnimalAvatar(id: "hare", name: "Bunny", symbol: "hare.fill"),
        GuardianAnimalAvatar(id: "fox", name: "Fox", symbol: "pawprint.fill"),
        GuardianAnimalAvatar(id: "bear", name: "Bear", symbol: "teddybear.fill"),
        GuardianAnimalAvatar(id: "owl", name: "Owl", symbol: "bird.fill"),
        GuardianAnimalAvatar(id: "cat", name: "Cat", symbol: "cat.fill"),
        GuardianAnimalAvatar(id: "dog", name: "Dog", symbol: "dog.fill"),
    ]

    public let id: String
    public let name: String
    public let symbol: String

    public init(id: String, name: String, symbol: String) {
        self.id = id
        self.name = name
        self.symbol = symbol
    }

    public static func option(for assetID: String) -> GuardianAnimalAvatar? {
        available.first(where: { $0.id == assetID })
    }
}

public struct GuardianAttentionItem: Identifiable, Codable, Equatable, Sendable {
    public enum Reason: String, Codable, CaseIterable, Sendable {
        case missedOften
        case takingExtraTime
        case reviewDue

        public var title: String {
            switch self {
            case .missedOften:
                "Needs another try"
            case .takingExtraTime:
                "Taking extra time"
            case .reviewDue:
                "Review is due"
            }
        }

        public var symbol: String {
            switch self {
            case .missedOften:
                "arrow.counterclockwise.circle.fill"
            case .takingExtraTime:
                "clock.fill"
            case .reviewDue:
                "calendar.badge.clock"
            }
        }
    }

    public let id: UUID
    public let prompt: WordPrompt
    public let reason: Reason
    public let whyNow: String

    public init(
        id: UUID? = nil,
        prompt: WordPrompt,
        reason: Reason,
        whyNow: String
    ) {
        self.id = id ?? prompt.id.rawValue
        self.prompt = prompt
        self.reason = reason
        self.whyNow = whyNow
    }
}

public struct GuardianDashboardSnapshot: Sendable {
    public let profile: KidProfile
    public let readPool: [WordPrompt]
    public let writePool: [WordPrompt]
    public let needsAttention: [GuardianAttentionItem]
    public let practiceSettings: ProfilePracticeSettings
    public let questCalendar: DailyQuestMonthSummary
    public let today: LocalDay
    public let todaySummary: GuardianTodaySummary
    public let worldProgression: WorldProgression
    public let collections: [WorldTheme: RewardCollection]

    public init(
        profile: KidProfile,
        readPool: [WordPrompt],
        writePool: [WordPrompt],
        needsAttention: [GuardianAttentionItem],
        practiceSettings: ProfilePracticeSettings,
        questCalendar: DailyQuestMonthSummary,
        today: LocalDay,
        todaySummary: GuardianTodaySummary? = nil,
        worldProgression: WorldProgression? = nil,
        collections: [WorldTheme: RewardCollection] = [:]
    ) {
        self.profile = profile
        self.readPool = readPool.filter { $0.learningMode == .read }
        self.writePool = writePool.filter { $0.learningMode == .write }
        self.needsAttention = needsAttention
        self.practiceSettings = practiceSettings
        precondition(
            questCalendar.profileID == profile.id,
            "Quest calendar must belong to the dashboard profile."
        )
        self.questCalendar = questCalendar
        self.today = today
        self.todaySummary = todaySummary ?? .empty(profileID: profile.id)
        self.worldProgression =
            worldProgression
            ?? WorldProgression(
                profile: profile,
                completions: [],
                currentLocalDay: today
            )
        self.collections = collections
    }

    public func pool(for mode: LearningMode) -> [WordPrompt] {
        switch mode {
        case .read:
            readPool
        case .write:
            writePool
        }
    }
}

public enum GuardianSyncState: String, Equatable, Sendable {
    case thisDeviceOnly
    case off
    case upToDate
    case pending
    case failed

    public var title: String {
        switch self {
        case .thisDeviceOnly:
            "Saved on this device"
        case .off:
            "Sync off"
        case .upToDate:
            "Synced"
        case .pending:
            "Sync pending"
        case .failed:
            "Sync needs attention"
        }
    }
}

public struct GuardianTodayRouteSummary: Equatable, Sendable {
    public let learningMode: LearningMode
    public let newWordsAddedToday: Int
    public let waitingPoolCount: Int
    public let dueReviewCount: Int
    public let completedToday: Bool
    public let points: Int?
    public let stars: QuestStars?

    public init(
        learningMode: LearningMode,
        newWordsAddedToday: Int,
        waitingPoolCount: Int,
        dueReviewCount: Int,
        completedToday: Bool,
        points: Int?,
        stars: QuestStars?
    ) {
        self.learningMode = learningMode
        self.newWordsAddedToday = max(0, newWordsAddedToday)
        self.waitingPoolCount = max(0, waitingPoolCount)
        self.dueReviewCount = max(0, dueReviewCount)
        self.completedToday = completedToday
        self.points = points
        self.stars = stars
    }
}

public struct GuardianTodaySummary: Equatable, Sendable {
    public let profileID: ProfileID
    public let read: GuardianTodayRouteSummary
    public let write: GuardianTodayRouteSummary
    public let completedQuestCount: Int
    public let totalPoints: Int
    public let totalStars: Int
    public let syncState: GuardianSyncState

    public init(
        profileID: ProfileID,
        read: GuardianTodayRouteSummary,
        write: GuardianTodayRouteSummary,
        completedQuestCount: Int,
        totalPoints: Int,
        totalStars: Int,
        syncState: GuardianSyncState
    ) {
        self.profileID = profileID
        self.read = read
        self.write = write
        self.completedQuestCount = max(0, completedQuestCount)
        self.totalPoints = max(0, totalPoints)
        self.totalStars = max(0, totalStars)
        self.syncState = syncState
    }

    public func route(_ mode: LearningMode) -> GuardianTodayRouteSummary {
        mode == .read ? read : write
    }

    public static func empty(profileID: ProfileID) -> GuardianTodaySummary {
        GuardianTodaySummary(
            profileID: profileID,
            read: GuardianTodayRouteSummary(
                learningMode: .read,
                newWordsAddedToday: 0,
                waitingPoolCount: 0,
                dueReviewCount: 0,
                completedToday: false,
                points: nil,
                stars: nil
            ),
            write: GuardianTodayRouteSummary(
                learningMode: .write,
                newWordsAddedToday: 0,
                waitingPoolCount: 0,
                dueReviewCount: 0,
                completedToday: false,
                points: nil,
                stars: nil
            ),
            completedQuestCount: 0,
            totalPoints: 0,
            totalStars: 0,
            syncState: .thisDeviceOnly
        )
    }
}

public enum GuardianReportPeriod: Int, CaseIterable, Equatable, Sendable {
    case sevenDays = 7
    case thirtyDays = 30

    public var title: String { "\(rawValue) days" }
}

public struct GuardianReportTrend: Equatable, Sendable {
    public let currentAccuracy: Double?
    public let previousAccuracy: Double?
    public let accuracyChange: Double?
    public let currentIndependentAttemptCount: Int
    public let previousIndependentAttemptCount: Int
}

public struct GuardianAttemptDetail: Identifiable, Equatable, Sendable {
    public let id: AttemptID
    public let occurredAt: Date
    public let originalOutcome: AttemptOutcome
    public let effectiveOutcome: AttemptOutcome
    public let responseTime: ElapsedTime?
    public let wasCorrected: Bool
}

public struct GuardianWordReport: Identifiable, Equatable, Sendable {
    public var id: WordPromptID { prompt.id }
    public let prompt: WordPrompt
    public let independentAttemptCount: Int
    public let correctCount: Int
    public let accuracy: Double?
    public let meanResponseTime: ElapsedTime?
    public let recentAttempts: [GuardianAttemptDetail]
}

public struct GuardianLearningReport: Equatable, Sendable {
    public let profile: KidProfile
    public let period: GuardianReportPeriod
    public let startedAt: Date
    public let endedAt: Date
    public let completedQuestCount: Int
    public let totalPoints: Int
    public let totalStars: Int
    public let trend: GuardianReportTrend
    public let words: [GuardianWordReport]

    public var csv: String {
        var rows = [
            "word,mode,first_attempts,correct,accuracy,mean_seconds"
        ]
        rows += words.map { word in
            let accuracy = word.accuracy.map { String(format: "%.3f", $0) } ?? ""
            let seconds =
                word.meanResponseTime.map {
                    String(format: "%.2f", $0.seconds)
                } ?? ""
            return [
                Self.csvField(word.prompt.displayText),
                word.prompt.learningMode.rawValue,
                String(word.independentAttemptCount),
                String(word.correctCount),
                accuracy,
                seconds,
            ].joined(separator: ",")
        }
        return rows.joined(separator: "\n") + "\n"
    }

    private static func csvField(_ value: String) -> String {
        "\"\(value.replacingOccurrences(of: "\"", with: "\"\""))\""
    }
}

public struct GuardianWordImportRequest: Equatable, Sendable {
    public let rawText: String
    public let learningMode: LearningMode
    public let spokenContextsByNormalizedWord: [String: String]

    public init(
        rawText: String,
        learningMode: LearningMode,
        spokenContextsByNormalizedWord: [String: String] = [:]
    ) {
        self.rawText = rawText
        self.learningMode = learningMode
        self.spokenContextsByNormalizedWord = spokenContextsByNormalizedWord
    }
}

public struct GuardianRejectedWord: Identifiable, Equatable, Sendable {
    public let id: UUID
    public let sourceText: String
    public let reason: String

    public init(id: UUID = UUID(), sourceText: String, reason: String) {
        self.id = id
        self.sourceText = sourceText
        self.reason = reason
    }
}

public struct GuardianWordImportReport: Equatable, Sendable {
    public let learningMode: LearningMode
    public let accepted: [String]
    public let duplicates: [String]
    public let rejected: [GuardianRejectedWord]

    public init(
        learningMode: LearningMode,
        accepted: [String],
        duplicates: [String],
        rejected: [GuardianRejectedWord]
    ) {
        self.learningMode = learningMode
        self.accepted = accepted
        self.duplicates = duplicates
        self.rejected = rejected
    }

    public var processedCount: Int {
        accepted.count + duplicates.count + rejected.count
    }
}

struct GuardianEditableOCRWord: Identifiable, Equatable {
    let id: UUID
    var text: String

    init(id: UUID = UUID(), text: String) {
        self.id = id
        self.text = text
    }
}

enum GuardianOCRWordState: Equatable {
    case ready(normalizedWord: String)
    case alreadyInPool
    case duplicateInPreview
    case invalid
}

struct GuardianOCRPreviewAnalysis: Equatable {
    let stateByID: [UUID: GuardianOCRWordState]
    let addableWords: [String]

    init(
        words: [GuardianEditableOCRWord],
        existingNormalizedWords: Set<String>
    ) {
        var seen = Set<String>()
        var stateByID: [UUID: GuardianOCRWordState] = [:]
        var addableWords: [String] = []

        for word in words {
            guard let normalized = try? EnglishWordNormalizer.normalize(word.text) else {
                stateByID[word.id] = .invalid
                continue
            }
            guard seen.insert(normalized).inserted else {
                stateByID[word.id] = .duplicateInPreview
                continue
            }
            guard !existingNormalizedWords.contains(normalized) else {
                stateByID[word.id] = .alreadyInPool
                continue
            }
            stateByID[word.id] = .ready(normalizedWord: normalized)
            addableWords.append(normalized)
        }

        self.stateByID = stateByID
        self.addableWords = addableWords
    }
}

public protocol GuardianWordStore: Sendable {
    func dashboardSnapshot() async throws -> GuardianDashboardSnapshot
    func importWords(_ request: GuardianWordImportRequest) async throws -> GuardianWordImportReport
    func deactivateWord(
        id: WordPromptID,
        learningMode: LearningMode
    ) async throws -> GuardianDashboardSnapshot
    func setWordsActive(
        ids: [WordPromptID],
        learningMode: LearningMode,
        isActive: Bool
    ) async throws -> GuardianDashboardSnapshot
    func updatePracticeSettings(
        _ settings: ProfilePracticeSettings
    ) async throws -> GuardianDashboardSnapshot
    func report(for period: GuardianReportPeriod) async throws
        -> GuardianLearningReport
    func correctAttempt(
        id: AttemptID,
        to outcome: AttemptOutcome
    ) async throws -> GuardianLearningReport
}

public protocol GuardianFamilyStore: GuardianWordStore {
    func familySnapshot() async throws -> GuardianFamilySnapshot

    func selectProfile(id: ProfileID) async throws -> GuardianDashboardSnapshot

    func createProfile(
        from draft: GuardianProfileDraft
    ) async throws -> GuardianDashboardSnapshot

    func updateProfile(
        id: ProfileID,
        from draft: GuardianProfileDraft
    ) async throws -> GuardianDashboardSnapshot

    func updateVoiceprintStatus(
        profileID: ProfileID,
        status: VoiceprintEnrollmentStatus
    ) async throws -> GuardianDashboardSnapshot

    func deleteProfile(id: ProfileID) async throws -> GuardianProfileDeletionResult
}
