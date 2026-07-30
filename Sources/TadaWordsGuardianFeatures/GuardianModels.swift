import Foundation
import NaturalLanguage
import TadaWordsContent
import TadaWordsDomain

public enum GuardianWordStoreError: Error, Equatable, Sendable {
    case profileMismatch(expected: ProfileID, received: ProfileID)
    case wordNotFound(WordPromptID)
    case membershipNotFound(WordPoolEntryID)
    case membershipCompensationFailed
}

public enum GuardianFamilyStoreError: Error, Equatable, Sendable {
    case profileNotFound(ProfileID)
    case noProfiles
    case emptyDisplayName
    case displayNameTooLong(maximumCharacterCount: Int)
    case unsupportedAvatar(String)
    case invalidAge
    case learningHistoryUnavailable
}

public struct GuardianFamilySnapshot: Equatable, Sendable {
    public let profiles: [KidProfile]
    public let selectedProfileID: ProfileID?

    public init(profiles: [KidProfile], selectedProfileID: ProfileID?) {
        self.profiles = profiles
        self.selectedProfileID =
            selectedProfileID.flatMap { candidate in
                profiles.contains(where: { $0.id == candidate }) ? candidate : nil
            } ?? profiles.first?.id
    }

    public var selectedProfile: KidProfile? {
        guard let selectedProfileID else { return nil }
        return profiles.first(where: { $0.id == selectedProfileID })
    }
}

public struct GuardianProfileDeletionResult: Sendable {
    public let family: GuardianFamilySnapshot
    /// The next child's dashboard, or nil when the family intentionally
    /// deleted its final Profile and should return to Profile creation.
    public let dashboard: GuardianDashboardSnapshot?
    public let tombstone: ProfileDeletionTombstone

    public init(
        family: GuardianFamilySnapshot,
        dashboard: GuardianDashboardSnapshot?,
        tombstone: ProfileDeletionTombstone
    ) {
        self.family = family
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
    public static let available = StarterProfileAvatar.zodiac.map(Self.init)

    public let id: String
    public let name: String
    public let symbol: String
    public let imageAssetName: String?

    public init(_ starter: StarterProfileAvatar) {
        id = starter.id
        name = starter.name
        symbol = starter.fallbackSystemImageName
        imageAssetName = starter.imageAssetName
    }

    public static func option(for assetID: String) -> GuardianAnimalAvatar? {
        StarterProfileAvatar.option(for: assetID).map(Self.init)
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
    /// Number of completed, independent practice encounters for each word.
    ///
    /// Technical retries and guided/helped attempts are intentionally excluded
    /// so a difficult recognition session cannot make a word look more
    /// frequently practiced than it really was.
    public let practiceFrequencyByWordID: [WordPromptID: Int]

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
        collections: [WorldTheme: RewardCollection] = [:],
        practiceFrequencyByWordID: [WordPromptID: Int] = [:]
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
        self.practiceFrequencyByWordID = practiceFrequencyByWordID.mapValues {
            max(0, $0)
        }
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

    public init(
        rawText: String,
        learningMode: LearningMode
    ) {
        self.rawText = rawText
        self.learningMode = learningMode
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

/// Exact, stable identity for one imported Read or Write pool membership.
///
/// Preset transactions keep these identities instead of looking words up again
/// by text. That makes rollback independent from a possibly stale dashboard and
/// prevents it from touching a same-spelled membership owned by another child.
public struct GuardianWordPoolMembership: Equatable, Sendable {
    public let entryID: WordPoolEntryID
    public let promptID: WordPromptID
    public let normalizedText: String

    public init(
        entryID: WordPoolEntryID,
        promptID: WordPromptID,
        normalizedText: String
    ) {
        self.entryID = entryID
        self.promptID = promptID
        self.normalizedText = normalizedText
    }

    init(entry: WordPoolEntry) {
        self.init(
            entryID: entry.id,
            promptID: entry.prompt.id,
            normalizedText: entry.normalizedText
        )
    }
}

public struct GuardianWordImportReport: Equatable, Sendable {
    public let profileID: ProfileID
    public let learningMode: LearningMode
    public let insertedMemberships: [GuardianWordPoolMembership]
    public let reactivatedMemberships: [GuardianWordPoolMembership]
    public let alreadyActiveMemberships: [GuardianWordPoolMembership]
    public let duplicateInputWords: [String]
    public let rejected: [GuardianRejectedWord]

    public init(
        profileID: ProfileID,
        learningMode: LearningMode,
        insertedMemberships: [GuardianWordPoolMembership],
        reactivatedMemberships: [GuardianWordPoolMembership],
        alreadyActiveMemberships: [GuardianWordPoolMembership],
        duplicateInputWords: [String] = [],
        rejected: [GuardianRejectedWord]
    ) {
        self.profileID = profileID
        self.learningMode = learningMode
        self.insertedMemberships = insertedMemberships
        self.reactivatedMemberships = reactivatedMemberships
        self.alreadyActiveMemberships = alreadyActiveMemberships
        self.duplicateInputWords = duplicateInputWords
        self.rejected = rejected
    }

    /// Compatibility projection used by existing Guardian import UI.
    public var accepted: [String] {
        insertedMemberships.map(\.normalizedText)
    }

    public var restored: [String] {
        reactivatedMemberships.map(\.normalizedText)
    }

    public var alreadyPresent: [String] {
        alreadyActiveMemberships.map(\.normalizedText) + duplicateInputWords
    }

    /// Compatibility projection: restored memberships historically appeared in
    /// the duplicate bucket. Transaction code must use the typed collections.
    public var duplicates: [String] {
        restored + alreadyPresent
    }

    public var changedMemberships: [GuardianWordPoolMembership] {
        insertedMemberships + reactivatedMemberships
    }

    public var processedCount: Int {
        insertedMemberships.count
            + reactivatedMemberships.count
            + alreadyActiveMemberships.count
            + duplicateInputWords.count
            + rejected.count
    }
}

struct GuardianOCRLemmaProposal: Equatable, Sendable {
    let candidates: [String]
    let requiresConfirmation: Bool

    static let unchanged = GuardianOCRLemmaProposal(
        candidates: [],
        requiresConfirmation: false
    )
}

struct GuardianEnglishLemmaSuggester: Sendable {
    func proposal(for source: String) -> GuardianOCRLemmaProposal {
        guard let normalized = try? EnglishWordNormalizer.normalize(source) else {
            return .unchanged
        }
        guard !Self.unchangedSuffixForms.contains(normalized) else {
            return .unchanged
        }

        if let candidates = Self.ambiguousForms[normalized] {
            return GuardianOCRLemmaProposal(
                candidates: validUniqueCandidates(candidates, excluding: normalized),
                requiresConfirmation: true
            )
        }

        if let irregular = Self.irregularForms[normalized] {
            return GuardianOCRLemmaProposal(
                candidates: validUniqueCandidates([irregular], excluding: normalized),
                requiresConfirmation: false
            )
        }

        var candidates: [String] = []
        if let systemCandidate = systemLemmaCandidate(for: normalized) {
            candidates.append(systemCandidate)
        }
        if let ruleCandidate = ruleBasedCandidate(for: normalized) {
            candidates.append(ruleCandidate)
        }
        candidates = validUniqueCandidates(candidates, excluding: normalized)

        return GuardianOCRLemmaProposal(
            candidates: candidates,
            requiresConfirmation: candidates.count > 1
        )
    }

    private func systemLemmaCandidate(for word: String) -> String? {
        let tagger = NLTagger(tagSchemes: [.lemma])
        tagger.string = word
        guard
            let candidate = tagger.tag(
                at: word.startIndex,
                unit: .word,
                scheme: .lemma
            ).0?.rawValue,
            candidate != word
        else { return nil }
        return candidate
    }

    private func ruleBasedCandidate(for word: String) -> String? {
        if word.hasSuffix("ied"), word.count > 3 {
            return String(word.dropLast(3)) + "y"
        }
        if word.hasSuffix("ies"), word.count > 3 {
            return String(word.dropLast(3)) + "y"
        }

        if word.hasSuffix("ing"), word.count > 4 {
            let stem = String(word.dropLast(3))
            return Self.restoredSilentEForms[word] ?? removingDoubledConsonant(from: stem)
        }

        if word.hasSuffix("ed"), word.count > 3 {
            let stem = String(word.dropLast(2))
            return Self.restoredSilentEForms[word] ?? removingDoubledConsonant(from: stem)
        }

        if word.hasSuffix("sses"), word.count > 4 {
            return String(word.dropLast(2))
        }
        if word.hasSuffix("ches") || word.hasSuffix("shes")
            || word.hasSuffix("xes") || word.hasSuffix("zzes")
        {
            return String(word.dropLast(2))
        }
        if word.hasSuffix("oes"), word.count > 4 {
            return String(word.dropLast(2))
        }
        if word.hasSuffix("s"), word.count > 3,
            !word.hasSuffix("ss"),
            !word.hasSuffix("us"),
            !word.hasSuffix("is"),
            !word.hasSuffix("ous")
        {
            return String(word.dropLast())
        }

        return nil
    }

    private func removingDoubledConsonant(from stem: String) -> String {
        guard
            stem.count >= 2,
            let last = stem.last,
            stem.dropLast().last == last,
            !"aeiou".contains(last)
        else { return stem }
        return String(stem.dropLast())
    }

    private func validUniqueCandidates(
        _ candidates: [String],
        excluding original: String
    ) -> [String] {
        var seen = Set<String>()
        return candidates.compactMap { candidate in
            guard
                let normalized = try? EnglishWordNormalizer.normalize(candidate),
                normalized != original,
                seen.insert(normalized).inserted
            else { return nil }
            return normalized
        }
    }

    private static let ambiguousForms: [String: [String]] = [
        "axes": ["ax", "axis"],
        "found": ["find"],
        "leaves": ["leaf", "leave"],
        "left": ["leave"],
        "lives": ["life", "live"],
        "rose": ["rise"],
        "saw": ["see"],
    ]

    private static let irregularForms: [String: String] = [
        "buses": "bus",
        "children": "child",
        "cookies": "cookie",
        "dies": "die",
        "died": "die",
        "feet": "foot",
        "gave": "give",
        "geese": "goose",
        "houses": "house",
        "knives": "knife",
        "lies": "lie",
        "lied": "lie",
        "made": "make",
        "men": "man",
        "mice": "mouse",
        "movies": "movie",
        "oxen": "ox",
        "people": "person",
        "pies": "pie",
        "rode": "ride",
        "shoes": "shoe",
        "teeth": "tooth",
        "ties": "tie",
        "tied": "tie",
        "tomatoes": "tomato",
        "wives": "wife",
        "wolves": "wolf",
        "women": "woman",
        "wrote": "write",
    ]

    private static let restoredSilentEForms: [String: String] = [
        "closed": "close",
        "closing": "close",
        "danced": "dance",
        "dancing": "dance",
        "hoped": "hope",
        "hoping": "hope",
        "loved": "love",
        "loving": "love",
        "making": "make",
        "moved": "move",
        "moving": "move",
        "riding": "ride",
        "smiled": "smile",
        "smiling": "smile",
        "taking": "take",
        "used": "use",
        "using": "use",
        "writing": "write",
    ]

    private static let unchangedSuffixForms: Set<String> = [
        "alias",
        "atlas",
        "bias",
        "business",
        "gas",
        "lens",
        "news",
        "series",
        "species",
        "this",
        "yes",
    ]
}

enum GuardianOCRWordSelection: Equatable, Sendable {
    case original
    case lemma(String)
    case edited
}

enum GuardianOCRWordFormRole: Equatable, Sendable {
    case lemma
    case original
}

struct GuardianOCRWordFormOption: Equatable, Sendable {
    let word: String
    let role: GuardianOCRWordFormRole
    let isSelected: Bool
    let isAlreadyInPool: Bool
}

struct GuardianEditableOCRWord: Identifiable, Equatable {
    let id: UUID
    /// Stable one-based position in the complete photo batch. This stays fixed
    /// while the parent changes the visible sort order for easier auditing.
    let sourceOrdinal: Int
    let originalText: String
    let lemmaCandidates: [String]
    let lemmaRequiresConfirmation: Bool
    var text: String
    var selection: GuardianOCRWordSelection
    private(set) var hasConfirmedLemmaSelection: Bool

    init(
        id: UUID = UUID(),
        sourceOrdinal: Int = 1,
        text: String,
        lemmaProposal: GuardianOCRLemmaProposal? = nil
    ) {
        let proposal = lemmaProposal ?? GuardianEnglishLemmaSuggester().proposal(for: text)
        let defaultLemma = proposal.candidates.first
        self.id = id
        self.sourceOrdinal = max(1, sourceOrdinal)
        self.originalText = text
        self.lemmaCandidates = proposal.candidates
        self.lemmaRequiresConfirmation = proposal.requiresConfirmation
        self.text = defaultLemma ?? text
        self.selection = defaultLemma.map(GuardianOCRWordSelection.lemma) ?? .original
        self.hasConfirmedLemmaSelection = !proposal.requiresConfirmation
    }

    var needsLemmaConfirmation: Bool {
        lemmaRequiresConfirmation && !hasConfirmedLemmaSelection
    }

    var hasLemmaSuggestion: Bool {
        !lemmaCandidates.isEmpty
    }

    mutating func selectOriginal() {
        text = originalText
        selection = .original
        hasConfirmedLemmaSelection = true
    }

    mutating func selectLemma(_ candidate: String) {
        guard lemmaCandidates.contains(candidate) else { return }
        text = candidate
        selection = .lemma(candidate)
        hasConfirmedLemmaSelection = true
    }

    mutating func applyManualEdit(_ editedText: String) {
        text = editedText
        selection = .edited
        hasConfirmedLemmaSelection = true
    }

    mutating func confirmCurrentSelection() {
        hasConfirmedLemmaSelection = true
    }

    func formOptions(
        existingNormalizedWords: Set<String>
    ) -> [GuardianOCRWordFormOption] {
        let lemmaOptions = lemmaCandidates.map { candidate in
            GuardianOCRWordFormOption(
                word: candidate,
                role: .lemma,
                isSelected: selection == .lemma(candidate),
                isAlreadyInPool: existingNormalizedWords.contains(candidate)
            )
        }
        let normalizedOriginal =
            (try? EnglishWordNormalizer.normalize(originalText)) ?? originalText
        let originalOption = GuardianOCRWordFormOption(
            word: originalText,
            role: .original,
            isSelected: selection == .original,
            isAlreadyInPool: existingNormalizedWords.contains(normalizedOriginal)
        )
        return lemmaOptions + [originalOption]
    }
}

enum GuardianOCRPhotoWordLimitError: Error, Equatable {
    case tooManyWords(recognizedCount: Int, maximum: Int)
}

struct GuardianOCRPhotoWordLimitPolicy: Equatable {
    static let defaultMaximum = 500

    let maximumWordsPerImage: Int

    init(maximumWordsPerImage: Int = Self.defaultMaximum) {
        self.maximumWordsPerImage = max(1, maximumWordsPerImage)
    }

    func validate(recognizedWordCount: Int) throws {
        guard recognizedWordCount <= maximumWordsPerImage else {
            throw GuardianOCRPhotoWordLimitError.tooManyWords(
                recognizedCount: recognizedWordCount,
                maximum: maximumWordsPerImage
            )
        }
    }
}

struct GuardianOCRBatchAccumulator {
    static func appending(
        _ recognizedWords: [String],
        to existing: [GuardianEditableOCRWord]
    ) -> [GuardianEditableOCRWord] {
        let firstOrdinal = (existing.map(\.sourceOrdinal).max() ?? 0) + 1
        let additions = recognizedWords.enumerated().map { offset, word in
            GuardianEditableOCRWord(
                sourceOrdinal: firstOrdinal + offset,
                text: word
            )
        }
        return existing + additions
    }
}

struct GuardianOCRSubmissionPolicy {
    static func canSubmit(
        addableWords: [String],
        isAdding: Bool,
        isRecognizingAdditionalPhotos: Bool,
        hasUnconfirmedLemmaSelections: Bool = false
    ) -> Bool {
        !addableWords.isEmpty
            && !isAdding
            && !isRecognizingAdditionalPhotos
            && !hasUnconfirmedLemmaSelections
    }
}

enum GuardianWordSortOrder: String, CaseIterable, Equatable, Sendable {
    case addedOrder
    case alphabetical
    case practiceFrequency

    var title: String {
        switch self {
        case .addedOrder:
            "Added order"
        case .alphabetical:
            "A–Z"
        case .practiceFrequency:
            "Most practiced"
        }
    }

    var symbol: String {
        switch self {
        case .addedOrder:
            "clock.arrow.circlepath"
        case .alphabetical:
            "textformat.abc"
        case .practiceFrequency:
            "chart.bar.fill"
        }
    }
}

struct GuardianWordListPresentation {
    static func prompts(
        _ prompts: [WordPrompt],
        sortOrder: GuardianWordSortOrder,
        searchText: String,
        practiceFrequencyByWordID: [WordPromptID: Int]
    ) -> [WordPrompt] {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
        let filtered =
            query.isEmpty
            ? prompts
            : prompts.filter {
                $0.normalizedText.localizedStandardContains(query)
                    || $0.displayText.lowercased().localizedStandardContains(query)
            }

        switch sortOrder {
        case .addedOrder:
            return filtered
        case .alphabetical:
            return filtered.sorted(by: promptAlphabeticalOrder)
        case .practiceFrequency:
            return filtered.sorted { left, right in
                let leftCount = practiceFrequencyByWordID[left.id, default: 0]
                let rightCount = practiceFrequencyByWordID[right.id, default: 0]
                if leftCount != rightCount { return leftCount > rightCount }
                return promptAlphabeticalOrder(left, right)
            }
        }
    }

    static func recognizedWords(
        _ words: [GuardianEditableOCRWord],
        sortOrder: GuardianWordSortOrder,
        practiceFrequencyByNormalizedWord: [String: Int]
    ) -> [GuardianEditableOCRWord] {
        switch sortOrder {
        case .addedOrder:
            return words.sorted { $0.sourceOrdinal < $1.sourceOrdinal }
        case .alphabetical:
            return words.sorted(by: recognizedWordAlphabeticalOrder)
        case .practiceFrequency:
            return words.sorted { left, right in
                let leftCount = recognizedFrequency(
                    for: left,
                    in: practiceFrequencyByNormalizedWord
                )
                let rightCount = recognizedFrequency(
                    for: right,
                    in: practiceFrequencyByNormalizedWord
                )
                if leftCount != rightCount { return leftCount > rightCount }
                return recognizedWordAlphabeticalOrder(left, right)
            }
        }
    }

    private static func promptAlphabeticalOrder(
        _ left: WordPrompt,
        _ right: WordPrompt
    ) -> Bool {
        if left.normalizedText != right.normalizedText {
            return left.normalizedText.localizedStandardCompare(right.normalizedText)
                == .orderedAscending
        }
        return left.id.rawValue.uuidString < right.id.rawValue.uuidString
    }

    private static func recognizedWordAlphabeticalOrder(
        _ left: GuardianEditableOCRWord,
        _ right: GuardianEditableOCRWord
    ) -> Bool {
        let leftText = normalizedText(for: left)
        let rightText = normalizedText(for: right)
        if leftText != rightText {
            return leftText.localizedStandardCompare(rightText) == .orderedAscending
        }
        return left.sourceOrdinal < right.sourceOrdinal
    }

    static func recognizedFrequency(
        for word: GuardianEditableOCRWord,
        in frequencies: [String: Int]
    ) -> Int {
        frequencies[normalizedText(for: word), default: 0]
    }

    private static func normalizedText(for word: GuardianEditableOCRWord) -> String {
        (try? EnglishWordNormalizer.normalize(word.text))
            ?? word.text.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }
}

enum GuardianOCRWordState: Equatable {
    case ready(normalizedWord: String)
    case needsConfirmation(suggestedWord: String)
    case alreadyInPool
    case duplicateInPreview
    case invalid
}

struct GuardianOCRPreviewAnalysis: Equatable {
    let stateByID: [UUID: GuardianOCRWordState]
    let addableWords: [String]
    let unconfirmedLemmaSelectionCount: Int

    init(
        words: [GuardianEditableOCRWord],
        existingNormalizedWords: Set<String>
    ) {
        var seen = Set<String>()
        var stateByID: [UUID: GuardianOCRWordState] = [:]
        var addableWords: [String] = []
        var unconfirmedLemmaSelectionCount = 0

        for word in words {
            guard let normalized = try? EnglishWordNormalizer.normalize(word.text) else {
                stateByID[word.id] = .invalid
                continue
            }
            guard !word.needsLemmaConfirmation else {
                stateByID[word.id] = .needsConfirmation(suggestedWord: normalized)
                unconfirmedLemmaSelectionCount += 1
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
        self.unconfirmedLemmaSelectionCount = unconfirmedLemmaSelectionCount
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

    /// Profile-bound variants are used by long-running parent operations. They
    /// must never consult a mutable "currently selected" pointer after awaiting.
    func dashboardSnapshot(
        for profileID: ProfileID
    ) async throws -> GuardianDashboardSnapshot

    func importWords(
        _ request: GuardianWordImportRequest,
        for profileID: ProfileID
    ) async throws -> GuardianWordImportReport

    func setWordsActive(
        ids: [WordPromptID],
        learningMode: LearningMode,
        isActive: Bool,
        for profileID: ProfileID
    ) async throws -> GuardianDashboardSnapshot

    func setMembershipsActive(
        ids: [WordPoolEntryID],
        learningMode: LearningMode,
        isActive: Bool,
        for profileID: ProfileID
    ) async throws

    func selectProfile(id: ProfileID) async throws -> GuardianDashboardSnapshot

    func createProfile(
        from draft: GuardianProfileDraft
    ) async throws -> GuardianDashboardSnapshot

    /// Creates a Profile with a caller-reserved identity. First-run onboarding
    /// uses this overload so interrupted retries cannot publish a second UUID.
    func createProfile(
        id: ProfileID,
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
