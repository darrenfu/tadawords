import Foundation
import TadaWordsContent
import TadaWordsDomain

/// Read-only presentation logic for the parent preset browser. It keeps age
/// and grade suggestions intentionally small while leaving the complete
/// catalog available through its authored category hierarchy and search.
struct GuardianPresetCatalogBrowserModel {
    let catalog: PresetWordCatalog
    let recommendations: [PresetWordRecommendation]
    let suggestionLimit: Int

    init(
        catalog: PresetWordCatalog,
        profile: KidProfile,
        suggestionLimit: Int = 6
    ) {
        self.catalog = catalog
        recommendations = catalog.recommendations(for: profile)
        self.suggestionLimit = max(0, suggestionLimit)
    }

    var suggestedRecommendations: [PresetWordRecommendation] {
        Array(
            recommendations
                .filter { $0.relevance != .browse }
                .prefix(suggestionLimit)
        )
    }

    var browsableRoots: [PresetWordCategory] {
        catalog.roots.filter { listCount(in: $0) > 0 }
    }

    func recommendation(listID: String) -> PresetWordRecommendation? {
        recommendations.first { $0.id == listID }
    }

    func matchingRecommendations(query rawQuery: String) -> [PresetWordRecommendation] {
        let query = rawQuery.trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
        guard !query.isEmpty else { return [] }

        return recommendations.filter { recommendation in
            recommendation.list.title.lowercased().contains(query)
                || recommendation.list.summary.lowercased().contains(query)
                || recommendation.categoryPath.contains {
                    $0.title.lowercased().contains(query)
                }
                || recommendation.list.words.contains {
                    $0.lowercased().contains(query)
                }
        }
    }

    /// Resolves a path one hierarchy level at a time. Treating the IDs as a
    /// path instead of a global lookup prevents a malformed catalog from
    /// jumping into an unrelated branch.
    func category(at path: [String]) -> PresetWordCategory? {
        guard !path.isEmpty else { return nil }
        var candidates = catalog.roots
        var resolved: PresetWordCategory?

        for categoryID in path {
            guard let category = candidates.first(where: { $0.id == categoryID }) else {
                return nil
            }
            resolved = category
            candidates = category.children
        }
        return resolved
    }

    func categories(along path: [String]) -> [PresetWordCategory] {
        var candidates = catalog.roots
        var resolved: [PresetWordCategory] = []

        for categoryID in path {
            guard let category = candidates.first(where: { $0.id == categoryID }) else {
                return []
            }
            resolved.append(category)
            candidates = category.children
        }
        return resolved
    }

    func listCount(in category: PresetWordCategory) -> Int {
        category.lists.count
            + category.children.reduce(0) { result, child in
                result + listCount(in: child)
            }
    }
}
