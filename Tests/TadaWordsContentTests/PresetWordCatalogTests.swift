import Foundation
import TadaWordsContent
import TadaWordsDomain
import XCTest

final class PresetWordCatalogTests: XCTestCase {
    func testBundledProductionCatalogIsPopulatedAndPassesContentAudit() {
        let catalog = BundledPresetWordCatalog.catalog
        let profile = KidProfile(
            displayName: "Catalog QA",
            avatar: .cartoonAnimal(assetID: "hare"),
            selectedWorld: .moonpetalKingdom,
            schoolGrade: .preK,
            ageYears: 4,
            createdAt: Date(timeIntervalSince1970: 1)
        )

        XCTAssertFalse(catalog.isEmpty)
        XCTAssertEqual(catalog.recommendations(for: profile).count, 34)
        XCTAssertEqual(catalog.sources.count, 7)
        XCTAssertTrue(PresetWordCatalogAuditor().issues(in: catalog).isEmpty)
    }

    func testBundledCatalogHasRecommendedGradeThreeContentForAgeEight() {
        let profile = KidProfile(
            displayName: "Catalog QA",
            avatar: .cartoonAnimal(assetID: "hare"),
            selectedWorld: .moonpetalKingdom,
            schoolGrade: .grade3,
            ageYears: 8,
            createdAt: Date(timeIntervalSince1970: 1)
        )

        let recommendedIDs = BundledPresetWordCatalog.catalog
            .recommendations(for: profile)
            .filter { $0.relevance == .recommended }
            .map(\.list.id)

        XCTAssertTrue(recommendedIDs.contains("sight-grade-3-fluency"))
        XCTAssertTrue(recommendedIDs.contains("phonics-grade-3-morphology"))
    }

    func testRecommendationsRankAgeAndGradeWithoutSelectingWords() {
        let profile = KidProfile(
            displayName: "Mia",
            avatar: .cartoonAnimal(assetID: "hare"),
            selectedWorld: .moonpetalKingdom,
            schoolGrade: .preK,
            ageYears: 4,
            createdAt: Date(timeIntervalSince1970: 1)
        )
        let catalog = PresetWordCatalog(
            roots: [
                PresetWordCategory(
                    id: "words",
                    title: "Words",
                    lists: [
                        list(
                            id: "browse",
                            audience: PresetWordAudience(
                                grades: [.grade1],
                                minimumAge: 6,
                                maximumAge: 7
                            )
                        ),
                        list(
                            id: "age",
                            audience: PresetWordAudience(
                                grades: [.grade1],
                                minimumAge: 4,
                                maximumAge: 5
                            )
                        ),
                        list(
                            id: "grade",
                            audience: PresetWordAudience(
                                grades: [.preK],
                                minimumAge: 6,
                                maximumAge: 7
                            )
                        ),
                        list(
                            id: "best",
                            audience: PresetWordAudience(
                                grades: [.preK],
                                minimumAge: 4,
                                maximumAge: 5
                            )
                        ),
                    ]
                )
            ]
        )

        let recommendations = catalog.recommendations(for: profile)

        XCTAssertEqual(recommendations.map(\.list.id), ["best", "grade", "age", "browse"])
        XCTAssertEqual(
            recommendations.map(\.relevance),
            [.recommended, .gradeMatch, .ageMatch, .browse]
        )
    }

    func testNestedCategoryPathAndLookupStayStable() throws {
        let dinosaurs = list(
            id: "dinosaurs",
            audience: PresetWordAudience(grades: [.preK])
        )
        let catalog = PresetWordCatalog(
            roots: [
                PresetWordCategory(
                    id: "nouns",
                    title: "Nouns",
                    children: [
                        PresetWordCategory(
                            id: "animals",
                            title: "Animals",
                            lists: [dinosaurs]
                        )
                    ]
                )
            ]
        )
        let profile = KidProfile(
            displayName: "Mia",
            avatar: .cartoonAnimal(assetID: "hare"),
            selectedWorld: .moonpetalKingdom,
            createdAt: Date(timeIntervalSince1970: 1)
        )

        XCTAssertEqual(catalog.list(id: "dinosaurs"), dinosaurs)
        XCTAssertEqual(
            catalog.recommendations(for: profile).first?.categoryPath.map(\.title),
            ["Nouns", "Animals"]
        )
    }

    func testCatalogAuditorAcceptsAValidSmallFixture() throws {
        let source = PresetWordSource(
            id: "source",
            title: "Source",
            url: try XCTUnwrap(URL(string: "https://example.com/words"))
        )
        let catalog = PresetWordCatalog(
            roots: [
                PresetWordCategory(
                    id: "sight-words",
                    title: "Sight words",
                    lists: [
                        PresetWordList(
                            id: "starter",
                            title: "Starter",
                            summary: "Small test fixture",
                            audience: PresetWordAudience(grades: [.preK]),
                            words: ["a", "the", "go"],
                            sourceIDs: [source.id]
                        )
                    ]
                )
            ],
            sources: [source]
        )

        XCTAssertTrue(
            PresetWordCatalogAuditor(expectedWordsPerList: 2...4)
                .issues(in: catalog)
                .isEmpty
        )
    }

    func testSelectionPlannerDeduplicatesPerDestinationPool() throws {
        let planner = PresetWordSelectionPlanner()
        let existingRead = [try WordPrompt(learningMode: .read, text: "dog")]
        let existingWrite = [try WordPrompt(learningMode: .write, text: "cat")]

        let plan = planner.plan(
            selectedWords: ["Dog", "dog", "CAT", "bird", "bad!"],
            destination: .both,
            existingReadWords: existingRead,
            existingWriteWords: existingWrite
        )

        XCTAssertEqual(plan.alreadyPresentMembershipCount, 2)
        XCTAssertEqual(plan.invalidWords, ["bad!"])
        XCTAssertEqual(
            plan.additions,
            [
                PresetWordPoolAddition(
                    learningMode: .read,
                    words: ["CAT", "bird"]
                ),
                PresetWordPoolAddition(
                    learningMode: .write,
                    words: ["Dog", "bird"]
                ),
            ]
        )
    }

    private func list(
        id: String,
        audience: PresetWordAudience
    ) -> PresetWordList {
        PresetWordList(
            id: id,
            title: id.capitalized,
            summary: "Test list",
            audience: audience,
            words: ["cat", "dog"]
        )
    }
}
