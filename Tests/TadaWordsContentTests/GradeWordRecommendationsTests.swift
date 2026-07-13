import Foundation
import TadaWordsContent
import TadaWordsDomain
import XCTest

final class GradeWordRecommendationsTests: XCTestCase {
    func testFallbackFillsOnlyShortageAndDeduplicatesManualWords() async throws {
        let profile = KidProfile(
            displayName: "Kid",
            avatar: .cartoonAnimal(assetID: "hare"),
            selectedWorld: .moonpetalKingdom,
            schoolGrade: .kindergarten,
            createdAt: Date(timeIntervalSince1970: 1)
        )
        let repository = InMemoryWordPoolRepository()
        _ = try await repository.upsert([
            WordPoolEntryDraft(
                profileID: profile.id,
                prompt: try WordPrompt(learningMode: .read, text: "all"),
                addedAt: Date(timeIntervalSince1970: 10),
                source: .guardianManual,
                positionInBatch: 0
            )
        ])
        let recommender = RepositoryGradeWordRecommender(
            repository: repository,
            clock: FixedRecommendationClock(
                now: Date(timeIntervalSince1970: 100_000)
            )
        )
        let settings = ProfilePracticeSettings(
            profileID: profile.id,
            read: LearningRouteSettings(
                newWordLimit: 3,
                reviewWordLimit: 0,
                contentOrder: .newThenReview,
                emergencyAfterSeconds: 180
            )
        )

        try await recommender.refillIfNeeded(
            profile: profile,
            learningMode: .read,
            settings: settings
        )
        let entries = try await repository.entries(
            for: profile.id,
            learningMode: .read,
            includingInactive: true
        )

        XCTAssertEqual(entries.count, 3)
        XCTAssertEqual(entries.filter { $0.normalizedText == "all" }.count, 1)
        XCTAssertEqual(entries.filter { $0.source == .gradeRecommendation }.count, 2)
    }

    func testManualOnlyNeverInventsWords() async throws {
        let profile = KidProfile(
            displayName: "Kid",
            avatar: .cartoonAnimal(assetID: "hare"),
            selectedWorld: .moonpetalKingdom,
            createdAt: Date(timeIntervalSince1970: 1)
        )
        let repository = InMemoryWordPoolRepository()
        let recommender = RepositoryGradeWordRecommender(repository: repository)
        let settings = ProfilePracticeSettings(
            profileID: profile.id,
            wordRecommendationMode: .manualOnly
        )

        try await recommender.refillIfNeeded(
            profile: profile,
            learningMode: .read,
            settings: settings
        )

        let entries = try await repository.entries(
            for: profile.id,
            learningMode: .read,
            includingInactive: true
        )
        XCTAssertTrue(entries.isEmpty)
    }
}

private struct FixedRecommendationClock: AppClock {
    let now: Date
}
