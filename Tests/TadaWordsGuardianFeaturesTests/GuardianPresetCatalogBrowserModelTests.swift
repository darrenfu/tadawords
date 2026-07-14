import Foundation
import TadaWordsContent
import TadaWordsDomain
import XCTest

@testable import TadaWordsGuardianFeatures

final class GuardianPresetCatalogBrowserModelTests: XCTestCase {
    func testSuggestionsAreRelevantLimitedAndNeverSelectWords() {
        let model = GuardianPresetCatalogBrowserModel(
            catalog: catalog,
            profile: profile,
            suggestionLimit: 2
        )

        XCTAssertEqual(
            model.suggestedRecommendations.map(\.list.id),
            ["pets", "dinosaurs"]
        )
        XCTAssertEqual(model.browsableRoots.map(\.id), ["nouns", "verbs"])
    }

    func testCategoryPathResolvesOneLevelAtATimeAndCountsNestedLists() throws {
        let model = GuardianPresetCatalogBrowserModel(catalog: catalog, profile: profile)
        let nouns = try XCTUnwrap(model.category(at: ["nouns"]))

        XCTAssertEqual(model.listCount(in: nouns), 3)
        XCTAssertEqual(
            model.category(at: ["nouns", "animals"])?.title,
            "Animals"
        )
        XCTAssertNil(model.category(at: ["nouns", "movement"]))
        XCTAssertEqual(
            model.categories(along: ["nouns", "animals"]).map(\.title),
            ["Nouns", "Animals"]
        )
    }

    func testSearchFindsAListByNestedCategoryAndWordWithoutChangingHierarchy() {
        let model = GuardianPresetCatalogBrowserModel(catalog: catalog, profile: profile)

        XCTAssertEqual(
            model.matchingRecommendations(query: "dinosaur").map(\.list.id),
            ["dinosaurs"]
        )
        XCTAssertEqual(
            model.matchingRecommendations(query: "poodle").map(\.list.id),
            ["pets"]
        )
        XCTAssertTrue(model.matchingRecommendations(query: "  ").isEmpty)
        XCTAssertEqual(model.browsableRoots.first?.children.first?.title, "Animals")
    }

    private var profile: KidProfile {
        KidProfile(
            displayName: "Mia",
            avatar: .cartoonAnimal(assetID: "hare"),
            selectedWorld: .moonpetalKingdom,
            schoolGrade: .preK,
            ageYears: 4,
            createdAt: Date(timeIntervalSince1970: 1)
        )
    }

    private var catalog: PresetWordCatalog {
        PresetWordCatalog(
            roots: [
                PresetWordCategory(
                    id: "nouns",
                    title: "Nouns",
                    children: [
                        PresetWordCategory(
                            id: "animals",
                            title: "Animals",
                            lists: [
                                list(id: "pets", title: "Pets", word: "poodle"),
                                list(
                                    id: "dinosaurs",
                                    title: "Dinosaurs",
                                    word: "stegosaurus"
                                ),
                            ]
                        ),
                        PresetWordCategory(
                            id: "places",
                            title: "Places",
                            lists: [list(id: "city", title: "City", word: "library")]
                        ),
                    ]
                ),
                PresetWordCategory(
                    id: "verbs",
                    title: "Verbs",
                    children: [
                        PresetWordCategory(
                            id: "movement",
                            title: "Movement",
                            lists: [
                                list(
                                    id: "movement-list",
                                    title: "Move and play",
                                    word: "jump",
                                    grades: [.grade2],
                                    minimumAge: 7,
                                    maximumAge: 8
                                )
                            ]
                        )
                    ]
                ),
            ]
        )
    }

    private func list(
        id: String,
        title: String,
        word: String,
        grades: [ProfileSchoolGrade] = [.preK],
        minimumAge: Int = 4,
        maximumAge: Int = 5
    ) -> PresetWordList {
        PresetWordList(
            id: id,
            title: title,
            summary: "Test list",
            audience: PresetWordAudience(
                grades: grades,
                minimumAge: minimumAge,
                maximumAge: maximumAge
            ),
            words: [word]
        )
    }
}
