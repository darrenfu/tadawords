import Foundation
import TadaWordsDomain

/// A sourced, local-first catalog that parents can browse without allowing the
/// app to place words into a child's pool automatically.
public struct PresetWordCatalog: Codable, Equatable, Sendable {
    public let roots: [PresetWordCategory]
    public let sources: [PresetWordSource]

    public init(
        roots: [PresetWordCategory],
        sources: [PresetWordSource] = []
    ) {
        self.roots = roots
        self.sources = sources
    }

    public static let empty = PresetWordCatalog(roots: [])

    public var isEmpty: Bool {
        !roots.contains(where: \.containsLists)
    }

    /// Returns every list in stable catalog order, ranked for the selected
    /// child's saved age and grade. Nothing is selected or imported here.
    public func recommendations(
        for profile: KidProfile
    ) -> [PresetWordRecommendation] {
        var flattened: [PresetWordRecommendation] = []
        for root in roots {
            root.appendRecommendations(
                for: profile,
                ancestors: [],
                to: &flattened
            )
        }
        return flattened.enumerated().sorted { left, right in
            let leftRank = left.element.relevance.sortRank
            let rightRank = right.element.relevance.sortRank
            return leftRank == rightRank
                ? left.offset < right.offset
                : leftRank < rightRank
        }.map(\.element)
    }

    public func list(id: String) -> PresetWordList? {
        for root in roots {
            if let list = root.list(id: id) { return list }
        }
        return nil
    }
}

public struct PresetWordCategory: Codable, Equatable, Identifiable, Sendable {
    public let id: String
    public let title: String
    public let summary: String?
    public let lists: [PresetWordList]
    public let children: [PresetWordCategory]

    public init(
        id: String,
        title: String,
        summary: String? = nil,
        lists: [PresetWordList] = [],
        children: [PresetWordCategory] = []
    ) {
        self.id = id
        self.title = title
        self.summary = summary
        self.lists = lists
        self.children = children
    }

    fileprivate func appendRecommendations(
        for profile: KidProfile,
        ancestors: [PresetWordCategoryBreadcrumb],
        to recommendations: inout [PresetWordRecommendation]
    ) {
        let path = ancestors + [PresetWordCategoryBreadcrumb(id: id, title: title)]
        recommendations += lists.map { list in
            PresetWordRecommendation(
                list: list,
                categoryPath: path,
                relevance: list.audience.relevance(for: profile)
            )
        }
        for child in children {
            child.appendRecommendations(
                for: profile,
                ancestors: path,
                to: &recommendations
            )
        }
    }

    fileprivate func list(id: String) -> PresetWordList? {
        if let local = lists.first(where: { $0.id == id }) { return local }
        for child in children {
            if let nested = child.list(id: id) { return nested }
        }
        return nil
    }

    fileprivate var containsLists: Bool {
        !lists.isEmpty || children.contains(where: \.containsLists)
    }
}

public struct PresetWordCategoryBreadcrumb: Codable, Equatable, Sendable {
    public let id: String
    public let title: String

    public init(id: String, title: String) {
        self.id = id
        self.title = title
    }
}

public struct PresetWordList: Codable, Equatable, Identifiable, Sendable {
    public let id: String
    public let title: String
    public let summary: String
    public let audience: PresetWordAudience
    public let words: [String]
    public let sourceIDs: [String]

    public init(
        id: String,
        title: String,
        summary: String,
        audience: PresetWordAudience,
        words: [String],
        sourceIDs: [String] = []
    ) {
        self.id = id
        self.title = title
        self.summary = summary
        self.audience = audience
        self.words = words
        self.sourceIDs = sourceIDs
    }
}

public struct PresetWordAudience: Codable, Equatable, Sendable {
    public let grades: [ProfileSchoolGrade]
    public let minimumAge: Int?
    public let maximumAge: Int?

    public init(
        grades: [ProfileSchoolGrade],
        minimumAge: Int? = nil,
        maximumAge: Int? = nil
    ) {
        self.grades = grades
        self.minimumAge = minimumAge
        self.maximumAge = maximumAge
    }

    public func relevance(for profile: KidProfile) -> PresetWordRelevance {
        let hasGradeTarget = !grades.isEmpty
        let hasAgeTarget = minimumAge != nil || maximumAge != nil
        let gradeMatches = !hasGradeTarget || grades.contains(profile.schoolGrade)
        let ageMatches = profile.ageYears.map { age in
            (minimumAge.map { age >= $0 } ?? true)
                && (maximumAge.map { age <= $0 } ?? true)
        }

        if gradeMatches && (!hasAgeTarget || ageMatches == true) {
            return .recommended
        }
        if hasGradeTarget && gradeMatches {
            return .gradeMatch
        }
        if hasAgeTarget && ageMatches == true {
            return .ageMatch
        }
        return .browse
    }
}

public enum PresetWordRelevance: String, Codable, Equatable, Sendable {
    case recommended
    case gradeMatch
    case ageMatch
    case browse

    fileprivate var sortRank: Int {
        switch self {
        case .recommended:
            0
        case .gradeMatch:
            1
        case .ageMatch:
            2
        case .browse:
            3
        }
    }
}

public struct PresetWordRecommendation: Equatable, Identifiable, Sendable {
    public let list: PresetWordList
    public let categoryPath: [PresetWordCategoryBreadcrumb]
    public let relevance: PresetWordRelevance

    public var id: String { list.id }

    public init(
        list: PresetWordList,
        categoryPath: [PresetWordCategoryBreadcrumb],
        relevance: PresetWordRelevance
    ) {
        self.list = list
        self.categoryPath = categoryPath
        self.relevance = relevance
    }
}

public struct PresetWordSource: Codable, Equatable, Identifiable, Sendable {
    public let id: String
    public let title: String
    public let url: URL
    public let note: String?

    public init(id: String, title: String, url: URL, note: String? = nil) {
        self.id = id
        self.title = title
        self.url = url
        self.note = note
    }
}

public enum PresetWordCatalogIssue: Equatable, Sendable {
    case duplicateCategoryID(String)
    case duplicateListID(String)
    case duplicateSourceID(String)
    case unknownSourceID(listID: String, sourceID: String)
    case invalidWord(listID: String, word: String)
    case duplicateWord(listID: String, normalizedWord: String)
    case wordCountOutsideExpectedRange(listID: String, count: Int)
}

/// Keeps content QA independent from runtime browsing. The production catalog
/// can enforce 30...50 words per leaf list while unit tests use small fixtures.
public struct PresetWordCatalogAuditor: Sendable {
    public let expectedWordsPerList: ClosedRange<Int>

    public init(expectedWordsPerList: ClosedRange<Int> = 30...50) {
        self.expectedWordsPerList = expectedWordsPerList
    }

    public func issues(in catalog: PresetWordCatalog) -> [PresetWordCatalogIssue] {
        var issues: [PresetWordCatalogIssue] = []
        var categoryIDs = Set<String>()
        var listIDs = Set<String>()
        var sourceIDs = Set<String>()

        for source in catalog.sources where !sourceIDs.insert(source.id).inserted {
            issues.append(.duplicateSourceID(source.id))
        }

        func audit(_ category: PresetWordCategory) {
            if !categoryIDs.insert(category.id).inserted {
                issues.append(.duplicateCategoryID(category.id))
            }
            for list in category.lists {
                if !listIDs.insert(list.id).inserted {
                    issues.append(.duplicateListID(list.id))
                }
                if !expectedWordsPerList.contains(list.words.count) {
                    issues.append(
                        .wordCountOutsideExpectedRange(
                            listID: list.id,
                            count: list.words.count
                        )
                    )
                }
                var words = Set<String>()
                for word in list.words {
                    guard let normalized = try? EnglishWordNormalizer.normalize(word) else {
                        issues.append(.invalidWord(listID: list.id, word: word))
                        continue
                    }
                    if !words.insert(normalized).inserted {
                        issues.append(
                            .duplicateWord(
                                listID: list.id,
                                normalizedWord: normalized
                            )
                        )
                    }
                }
                for sourceID in list.sourceIDs where !sourceIDs.contains(sourceID) {
                    issues.append(
                        .unknownSourceID(listID: list.id, sourceID: sourceID)
                    )
                }
            }
            category.children.forEach(audit)
        }

        catalog.roots.forEach(audit)
        return issues
    }
}

public enum PresetWordPoolDestination: String, CaseIterable, Codable, Sendable {
    case read
    case write
    case both

    public var learningModes: [LearningMode] {
        switch self {
        case .read:
            [.read]
        case .write:
            [.write]
        case .both:
            [.read, .write]
        }
    }
}

public struct PresetWordPoolAddition: Equatable, Sendable {
    public let learningMode: LearningMode
    public let words: [String]

    public init(learningMode: LearningMode, words: [String]) {
        self.learningMode = learningMode
        self.words = words
    }
}

public struct PresetWordSelectionPlan: Equatable, Sendable {
    public let additions: [PresetWordPoolAddition]
    /// A word already present in both targeted pools counts twice because no
    /// write occurs for either pool membership.
    public let alreadyPresentMembershipCount: Int
    public let invalidWords: [String]

    public init(
        additions: [PresetWordPoolAddition],
        alreadyPresentMembershipCount: Int,
        invalidWords: [String]
    ) {
        self.additions = additions
        self.alreadyPresentMembershipCount = max(0, alreadyPresentMembershipCount)
        self.invalidWords = invalidWords
    }
}

/// Produces explicit parent-approved writes and performs case-insensitive
/// de-duplication both inside the selection and against each destination pool.
public struct PresetWordSelectionPlanner: Sendable {
    public init() {}

    public func plan(
        selectedWords: [String],
        destination: PresetWordPoolDestination,
        existingReadWords: [WordPrompt],
        existingWriteWords: [WordPrompt]
    ) -> PresetWordSelectionPlan {
        var normalizedSelection: [(display: String, normalized: String)] = []
        var invalidWords: [String] = []
        var seen = Set<String>()

        for word in selectedWords {
            guard let normalized = try? EnglishWordNormalizer.normalize(word) else {
                invalidWords.append(word)
                continue
            }
            guard seen.insert(normalized).inserted else { continue }
            normalizedSelection.append((display: word, normalized: normalized))
        }

        let existingByMode: [LearningMode: Set<String>] = [
            .read: Set(existingReadWords.map(\.normalizedText)),
            .write: Set(existingWriteWords.map(\.normalizedText)),
        ]
        var alreadyPresentMembershipCount = 0
        let additions = destination.learningModes.compactMap { mode in
            let existing = existingByMode[mode, default: []]
            let missing = normalizedSelection.compactMap { word -> String? in
                guard !existing.contains(word.normalized) else {
                    alreadyPresentMembershipCount += 1
                    return nil
                }
                return word.display
            }
            return missing.isEmpty
                ? nil
                : PresetWordPoolAddition(learningMode: mode, words: missing)
        }

        return PresetWordSelectionPlan(
            additions: additions,
            alreadyPresentMembershipCount: alreadyPresentMembershipCount,
            invalidWords: invalidWords
        )
    }
}
