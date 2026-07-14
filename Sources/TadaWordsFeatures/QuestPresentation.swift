import Foundation
import TadaWordsContent
import TadaWordsDomain

enum QuestBlockReason: Equatable {
    case emptyPool
    case microphoneDenied
    case recognitionUnavailable
    case audioUnavailable
    case storageUnavailable
    case noReviewDue

    var title: String {
        switch self {
        case .emptyPool:
            "No words yet"
        case .microphoneDenied:
            "Microphone is off"
        case .recognitionUnavailable:
            "Listening is taking a break"
        case .audioUnavailable:
            "Sound is taking a break"
        case .storageUnavailable:
            "Progress needs a moment"
        case .noReviewDue:
            "Reviews are all caught up"
        }
    }

    var message: String {
        switch self {
        case .emptyPool:
            "Ask a parent to add a few words."
        case .microphoneDenied:
            "A parent can turn on the microphone in Settings."
        case .recognitionUnavailable:
            "Your work is safe. Take a short break, then try again."
        case .audioUnavailable:
            "The word could not play. Your work is safe."
        case .storageUnavailable:
            "Nothing was counted or rewarded. A parent can safely try again."
        case .noReviewDue:
            "Nice work. Try new words today."
        }
    }

    var symbol: String {
        switch self {
        case .emptyPool:
            "tray"
        case .microphoneDenied:
            "mic.slash.fill"
        case .recognitionUnavailable:
            "waveform.slash"
        case .audioUnavailable:
            "speaker.slash.fill"
        case .storageUnavailable:
            "externaldrive.badge.exclamationmark"
        case .noReviewDue:
            "checkmark.seal.fill"
        }
    }

    var recoveryTitle: String {
        switch self {
        case .recognitionUnavailable, .storageUnavailable:
            "Try again"
        case .audioUnavailable, .noReviewDue:
            "Back to quests"
        case .emptyPool, .microphoneDenied:
            "Got it"
        }
    }
}

enum QuestLoadingPhase: Equatable {
    case preparing
    case saving(currentItem: Int, totalItems: Int)

    var message: String {
        switch self {
        case .preparing:
            "Getting today’s words ready…"
        case .saving(let currentItem, let totalItems):
            "Saving word \(currentItem) of \(totalItems)…"
        }
    }

    var allowsBackNavigation: Bool {
        self == .preparing
    }
}

enum QuestAvailability: Equatable {
    case available
    case blocked(QuestBlockReason)
}

struct QuestSession: Identifiable {
    let id: QuestID
    let profileID: ProfileID
    let mode: LearningMode
    let prompt: WordPrompt
    let source: QuestItemSource
    let currentItem: Int
    let totalItems: Int
    let timer: QuestTimerModel
    let interfacePreferences: PracticeInterfacePreferences
}

enum ReadPermissionTimingPolicy {
    static func shouldResetResponseClock(
        hasRequestedPermission: Bool,
        wasPreviouslyDenied: Bool
    ) -> Bool {
        !hasRequestedPermission || wasPreviouslyDenied
    }
}

enum TodayQuestRouteAction: Equatable {
    case startToday
    case practiceAgain
}

struct TodayQuestRouteStatus: Equatable {
    let action: TodayQuestRouteAction
    let completedPoints: Int?
    let completedStars: QuestStars?

    static let ready = TodayQuestRouteStatus(
        action: .startToday,
        completedPoints: nil,
        completedStars: nil
    )

    init(state: DailyQuestState) {
        guard let completion = state.todayCompletion else {
            self = .ready
            return
        }
        self.init(completion: completion)
    }

    init(completion: DailyQuestCompletion) {
        action = .practiceAgain
        completedPoints = completion.points
        completedStars = completion.stars
    }

    private init(
        action: TodayQuestRouteAction,
        completedPoints: Int?,
        completedStars: QuestStars?
    ) {
        self.action = action
        self.completedPoints = completedPoints
        self.completedStars = completedStars
    }
}

struct QuestResultViewState {
    let mode: LearningMode
    let score: QuestScore
    let runKind: DailyQuestRunKind
    let rewardGrant: RewardGrant?

    init(
        mode: LearningMode,
        score: QuestScore,
        runKind: DailyQuestRunKind = .today,
        rewardGrant: RewardGrant? = nil
    ) {
        self.mode = mode
        self.score = score
        self.runKind = runKind
        self.rewardGrant = rewardGrant
    }

    var earnedStarCount: Int {
        score.stars.count
    }

    var points: Int {
        score.points
    }

    var showsNewCollectible: Bool {
        runKind == .today && rewardGrant != nil
    }

    var showsReplayAction: Bool {
        !showsNewCollectible
    }

    var firstTryAccuracyPercentage: Int? {
        score.firstIndependentAccuracy.map { accuracy in
            Int((accuracy * 100).rounded())
        }
    }

    var paceLabel: String {
        switch score.personalPaceAssessment {
        case .withinPersonalBand:
            "Your pace"
        case .calibrating:
            "Learning your pace"
        case .outsidePersonalBand:
            "Try a comfy pace"
        case .unavailable:
            "Pace comes later"
        }
    }
}

enum AppDestination {
    case profileChooser
    case lobby
    case loading(mode: LearningMode, phase: QuestLoadingPhase)
    case quest(QuestSession)
    case blocked(mode: LearningMode, reason: QuestBlockReason)
    case result(QuestResultViewState)
}
