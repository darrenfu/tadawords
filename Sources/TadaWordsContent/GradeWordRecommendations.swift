import Foundation
import TadaWordsDomain

public protocol GradeWordRecommending: Sendable {
    func refillIfNeeded(
        profile: KidProfile,
        learningMode: LearningMode,
        settings: ProfilePracticeSettings
    ) async throws
}

/// A compact built-in high-frequency starter catalog. Common Core specifies
/// the grade-level skill but does not publish a required word list, so these
/// entries are product recommendations rather than a claim of official scope.
public enum GradeWordRecommendationCatalog {
    public static let standardsReference =
        "CCSS RF.K.3.c, RF.1.3.g, RF.2.3.f, RF.3.3.d"

    public static func words(
        for grade: ProfileSchoolGrade,
        learningMode: LearningMode
    ) -> [String] {
        let read = readWords(for: grade)
        switch learningMode {
        case .read:
            return read
        case .write:
            return writeWords(for: grade).filter(read.contains)
        }
    }

    private static func readWords(for grade: ProfileSchoolGrade) -> [String] {
        switch grade {
        case .preK:
            [
                "a", "I", "am", "at", "can", "go", "in", "is", "it", "me",
                "my", "no", "on", "see", "the", "to", "up", "we", "you",
                "yes", "and", "big", "come", "help", "here", "like", "look",
                "play", "said", "want",
            ]
        case .kindergarten:
            [
                "all", "are", "be", "black", "brown", "but", "came", "did",
                "do", "eat", "four", "get", "good", "have", "he", "into",
                "must", "new", "now", "of", "our", "out", "please", "pretty",
                "ran", "ride", "saw", "say", "she", "soon", "that", "there",
                "they", "this", "too", "under", "was", "well", "went", "what",
                "white", "who", "will", "with",
            ]
        case .grade1:
            [
                "after", "again", "an", "any", "ask", "as", "by", "could",
                "every", "fly", "from", "give", "going", "had", "has", "her",
                "him", "his", "how", "just", "know", "let", "live", "may",
                "old", "once", "open", "over", "put", "round", "some", "stop",
                "take", "thank", "them", "then", "think", "walk", "when",
                "where", "why",
            ]
        case .grade2:
            [
                "always", "around", "because", "been", "before", "best", "both",
                "buy", "call", "cold", "fast", "first", "five", "found", "gave",
                "goes", "green", "its", "made", "many", "off", "or", "pull",
                "right", "sing", "sit", "sleep", "tell", "their", "these", "those",
                "upon", "us", "use", "very", "wash", "which", "work", "would",
                "write", "your",
            ]
        case .grade3:
            [
                "about", "better", "bring", "carry", "clean", "cut", "done",
                "draw", "drink", "eight", "fall", "far", "full", "grow", "hold",
                "hot", "hurt", "if", "keep", "kind", "laugh", "light", "long",
                "much", "myself", "never", "only", "own", "pick", "seven", "shall",
                "show", "six", "small", "start", "ten", "today", "together", "try",
                "warm",
            ]
        }
    }

    private static func writeWords(for grade: ProfileSchoolGrade) -> [String] {
        switch grade {
        case .preK:
            [
                "a", "I", "am", "at", "can", "go", "in", "is", "it", "me", "my", "on", "the", "up",
                "we", "yes",
            ]
        case .kindergarten:
            [
                "all", "are", "but", "came", "did", "do", "eat", "get", "good", "have", "he", "now",
                "of", "out", "ran", "saw", "say", "she", "that", "this", "was", "well", "went",
                "will", "with",
            ]
        case .grade1:
            [
                "after", "again", "an", "any", "ask", "as", "could", "every", "from", "give",
                "going", "had", "has", "her", "him", "his", "how", "just", "let", "may", "old",
                "once", "open", "over", "put", "some", "stop", "take", "thank", "them", "then",
                "think", "walk", "when", "where", "why",
            ]
        case .grade2:
            [
                "always", "around", "because", "been", "before", "best", "both", "call", "cold",
                "fast", "first", "five", "found", "gave", "goes", "green", "its", "made", "many",
                "off", "or", "pull", "sing", "sit", "sleep", "tell", "these", "those", "upon", "us",
                "use", "very", "wash", "work", "would", "your",
            ]
        case .grade3:
            [
                "about", "better", "bring", "carry", "clean", "cut", "done", "draw", "drink",
                "eight", "fall", "far", "full", "grow", "hold", "hot", "hurt", "if", "keep", "kind",
                "laugh", "light", "long", "much", "myself", "never", "only", "own", "pick", "seven",
                "shall", "show", "six", "small", "start", "ten", "today", "together", "try", "warm",
            ]
        }
    }
}

public actor RepositoryGradeWordRecommender: GradeWordRecommending {
    public init(
        repository: any WordPoolRepository,
        clock: any AppClock = SystemAppClock()
    ) {
        _ = repository
        _ = clock
    }

    public func refillIfNeeded(
        profile: KidProfile,
        learningMode: LearningMode,
        settings: ProfilePracticeSettings
    ) async throws {
        // Kept as an API-compatible no-op so older app snapshots and call
        // sites cannot write recommended words into a pool.
        _ = profile
        _ = learningMode
        _ = settings
    }
}
