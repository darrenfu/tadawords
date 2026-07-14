import SwiftUI
import TadaWordsContent
import TadaWordsDesignSystem
import TadaWordsDomain

/// Parent-driven browsing for the local preset catalog. Opening a list never
/// changes either pool; only the final Add action submits explicitly selected
/// words.
struct GuardianPresetWordsView: View {
    let profile: KidProfile
    let catalog: PresetWordCatalog
    let readWords: [WordPrompt]
    let writeWords: [WordPrompt]
    let onBack: () -> Void
    let onSubmit:
        @MainActor (ProfileID, GuardianWordImportRequest) async
            -> GuardianWordImportReport?
    let onRollback: @MainActor (GuardianPresetRollbackRequest) async -> Bool

    @State private var selectedListID: String?
    @State private var selectedCategoryPath: [String] = []
    @State private var selectedNormalizedWords = Set<String>()
    @State private var destination: PresetWordPoolDestination = .read
    @State private var searchText = ""
    @State private var isAdding = false
    @State private var feedback: PresetImportFeedback?

    private var browser: GuardianPresetCatalogBrowserModel {
        GuardianPresetCatalogBrowserModel(catalog: catalog, profile: profile)
    }

    private var selectedRecommendation: PresetWordRecommendation? {
        guard let selectedListID else { return nil }
        return browser.recommendation(listID: selectedListID)
    }

    private var selectedCategory: PresetWordCategory? {
        browser.category(at: selectedCategoryPath)
    }

    var body: some View {
        Group {
            if let selectedRecommendation {
                listDetail(selectedRecommendation)
            } else if let selectedCategory {
                categoryOverview(selectedCategory)
            } else {
                catalogOverview
            }
        }
        .onChange(of: destination) {
            feedback = nil
        }
    }

    private var catalogOverview: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: GuardianPrimitiveTokens.Spacing.large) {
                GuardianNavigationHeader(title: "Preset words", onBack: onBack)
                recommendationContext

                if catalog.isEmpty {
                    GuardianCard {
                        ContentUnavailableView(
                            "Preset lists are not installed",
                            systemImage: "books.vertical",
                            description: Text(
                                "You can still type or scan words in Manage Words."
                            )
                        )
                    }
                } else {
                    searchField

                    if normalizedSearchText.isEmpty {
                        recommendationSection(
                            title: "Suggested first",
                            subtitle: suggestionSubtitle,
                            emptyTitle: "No exact suggestions yet",
                            recommendations: browser.suggestedRecommendations
                        )
                        categorySection(
                            title: "Browse by category",
                            categories: browser.browsableRoots
                        )
                    } else {
                        let matches = browser.matchingRecommendations(query: searchText)
                        recommendationSection(
                            title: "Search results",
                            subtitle: matches.isEmpty
                                ? "No preset lists match “\(normalizedSearchText)”."
                                : "\(matches.count) matching \(matches.count == 1 ? "list" : "lists")",
                            recommendations: matches
                        )
                    }
                }
            }
            .frame(maxWidth: 920, alignment: .leading)
            .padding(.horizontal, GuardianPrimitiveTokens.Spacing.medium)
            .padding(.vertical, GuardianPrimitiveTokens.Spacing.large)
            .frame(maxWidth: .infinity)
        }
        .scrollDismissesKeyboard(.immediately)
        .scrollIndicators(.hidden)
    }

    private var recommendationContext: some View {
        GuardianCard {
            HStack(spacing: GuardianPrimitiveTokens.Spacing.medium) {
                Image(systemName: "person.crop.circle.badge.checkmark")
                    .font(.system(.title, design: .rounded, weight: .bold))
                    .foregroundStyle(GuardianSemanticTokens.primary)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 3) {
                    Text("For \(profile.displayName)")
                        .font(.system(.title3, design: .rounded, weight: .bold))
                    Text(profileLearningLevel)
                        .font(.system(.subheadline, design: .rounded, weight: .medium))
                        .foregroundStyle(GuardianSemanticTokens.secondaryForeground)
                }
                Spacer()
            }
        }
        .accessibilityElement(children: .combine)
    }

    private var profileLearningLevel: String {
        let age = profile.ageYears.map { "Age \($0) · " } ?? ""
        return "\(age)\(profile.schoolGrade.displayName)"
    }

    private var searchField: some View {
        HStack(spacing: GuardianPrimitiveTokens.Spacing.small) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(GuardianSemanticTokens.secondaryForeground)
            TextField("Search categories or words", text: $searchText)
                .autocorrectionDisabled()
            if !searchText.isEmpty {
                Button {
                    searchText = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                }
                .buttonStyle(.plain)
                .foregroundStyle(GuardianSemanticTokens.secondaryForeground)
                .accessibilityLabel("Clear preset search")
            }
        }
        .padding(.horizontal, GuardianPrimitiveTokens.Spacing.medium)
        .frame(minHeight: 48)
        .background(
            GuardianSemanticTokens.surface,
            in: RoundedRectangle(
                cornerRadius: GuardianPrimitiveTokens.Radius.small,
                style: .continuous
            )
        )
    }

    private var normalizedSearchText: String {
        searchText.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var suggestionSubtitle: String {
        if browser.suggestedRecommendations.isEmpty {
            return "No exact age or grade match yet. Browse every category below."
        }
        return "Matched to \(profileLearningLevel). Nothing is added automatically."
    }

    @ViewBuilder
    private func recommendationSection(
        title: String,
        subtitle: String? = nil,
        emptyTitle: String = "No matching lists",
        recommendations: [PresetWordRecommendation]
    ) -> some View {
        VStack(alignment: .leading, spacing: GuardianPrimitiveTokens.Spacing.small) {
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.system(.title3, design: .rounded, weight: .bold))
                if let subtitle {
                    Text(subtitle)
                        .font(.system(.caption, design: .rounded, weight: .medium))
                        .foregroundStyle(GuardianSemanticTokens.secondaryForeground)
                }
            }

            if recommendations.isEmpty {
                GuardianCard {
                    ContentUnavailableView(
                        emptyTitle,
                        systemImage: "magnifyingglass",
                        description: Text(subtitle ?? "Try another category or search.")
                    )
                }
            } else {
                LazyVStack(spacing: GuardianPrimitiveTokens.Spacing.small) {
                    ForEach(recommendations) { recommendation in
                        recommendationButton(recommendation)
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func categorySection(
        title: String,
        categories: [PresetWordCategory]
    ) -> some View {
        let visibleCategories = categories.filter { browser.listCount(in: $0) > 0 }
        if !visibleCategories.isEmpty {
            VStack(alignment: .leading, spacing: GuardianPrimitiveTokens.Spacing.small) {
                Text(title)
                    .font(.system(.title3, design: .rounded, weight: .bold))

                LazyVGrid(
                    columns: [GridItem(.adaptive(minimum: 260), spacing: 12)],
                    spacing: 12
                ) {
                    ForEach(visibleCategories) { category in
                        categoryButton(category)
                    }
                }
            }
        }
    }

    private func categoryButton(_ category: PresetWordCategory) -> some View {
        let count = browser.listCount(in: category)
        return Button {
            selectedCategoryPath.append(category.id)
            searchText = ""
            feedback = nil
        } label: {
            GuardianCard {
                HStack(spacing: GuardianPrimitiveTokens.Spacing.medium) {
                    Image(systemName: symbol(for: category))
                        .font(.system(.title2, design: .rounded, weight: .bold))
                        .foregroundStyle(GuardianSemanticTokens.primary)
                        .frame(width: 48, height: 48)
                        .background(
                            GuardianSemanticTokens.primary.opacity(0.10),
                            in: RoundedRectangle(
                                cornerRadius: GuardianPrimitiveTokens.Radius.small,
                                style: .continuous
                            )
                        )
                        .accessibilityHidden(true)

                    VStack(alignment: .leading, spacing: 4) {
                        Text(category.title)
                            .font(.system(.headline, design: .rounded, weight: .bold))
                        if let summary = category.summary, !summary.isEmpty {
                            Text(summary)
                                .font(.system(.caption, design: .rounded, weight: .medium))
                                .foregroundStyle(GuardianSemanticTokens.secondaryForeground)
                                .lineLimit(2)
                        }
                        Text("\(count) \(count == 1 ? "list" : "lists")")
                            .font(.system(.caption, design: .rounded, weight: .bold))
                            .foregroundStyle(GuardianSemanticTokens.primary)
                    }

                    Spacer()
                    Image(systemName: "chevron.right")
                        .foregroundStyle(GuardianSemanticTokens.secondaryForeground)
                        .accessibilityHidden(true)
                }
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(category.title), \(count) preset lists")
        .accessibilityHint("Opens this category without adding any words")
    }

    private func categoryOverview(_ category: PresetWordCategory) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: GuardianPrimitiveTokens.Spacing.large) {
                GuardianNavigationHeader(
                    title: category.title,
                    onBack: navigateBackOneCategory
                )

                GuardianCard {
                    VStack(alignment: .leading, spacing: GuardianPrimitiveTokens.Spacing.small) {
                        Text(categoryBreadcrumb)
                            .font(.system(.caption, design: .rounded, weight: .bold))
                            .foregroundStyle(GuardianSemanticTokens.primary)
                        if let summary = category.summary, !summary.isEmpty {
                            Text(summary)
                                .font(.system(.body, design: .rounded, weight: .medium))
                        }
                        Text(
                            "\(browser.listCount(in: category)) preset \(browser.listCount(in: category) == 1 ? "list" : "lists") in this category"
                        )
                        .font(.system(.caption, design: .rounded, weight: .semibold))
                        .foregroundStyle(GuardianSemanticTokens.secondaryForeground)
                    }
                }

                categorySection(title: "Explore", categories: category.children)

                let localRecommendations = category.lists.compactMap {
                    browser.recommendation(listID: $0.id)
                }
                if !localRecommendations.isEmpty {
                    recommendationSection(
                        title: category.children.isEmpty ? "Choose a list" : "Lists here",
                        recommendations: localRecommendations
                    )
                }
            }
            .frame(maxWidth: 920, alignment: .leading)
            .padding(.horizontal, GuardianPrimitiveTokens.Spacing.medium)
            .padding(.vertical, GuardianPrimitiveTokens.Spacing.large)
            .frame(maxWidth: .infinity)
        }
        .scrollIndicators(.hidden)
    }

    private var categoryBreadcrumb: String {
        browser.categories(along: selectedCategoryPath)
            .map(\.title)
            .joined(separator: " › ")
    }

    private func navigateBackOneCategory() {
        if selectedCategoryPath.isEmpty {
            onBack()
        } else {
            selectedCategoryPath.removeLast()
        }
        selectedNormalizedWords = []
        feedback = nil
    }

    private func recommendationButton(
        _ recommendation: PresetWordRecommendation
    ) -> some View {
        Button {
            selectedNormalizedWords = []
            feedback = nil
            selectedListID = recommendation.id
        } label: {
            GuardianCard {
                HStack(spacing: GuardianPrimitiveTokens.Spacing.medium) {
                    Image(systemName: symbol(for: recommendation.categoryPath.first?.id))
                        .font(.system(.title2, design: .rounded, weight: .bold))
                        .foregroundStyle(GuardianSemanticTokens.primary)
                        .frame(width: 48, height: 48)
                        .background(
                            GuardianSemanticTokens.primary.opacity(0.10),
                            in: RoundedRectangle(
                                cornerRadius: GuardianPrimitiveTokens.Radius.small,
                                style: .continuous
                            )
                        )
                        .accessibilityHidden(true)

                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Text(recommendation.list.title)
                                .font(.system(.headline, design: .rounded, weight: .bold))
                            if recommendation.relevance != .browse {
                                Text(relevanceTitle(recommendation.relevance))
                                    .font(.system(.caption2, design: .rounded, weight: .bold))
                                    .foregroundStyle(GuardianSemanticTokens.primary)
                                    .padding(.horizontal, 7)
                                    .padding(.vertical, 3)
                                    .background(
                                        GuardianSemanticTokens.primary.opacity(0.10),
                                        in: Capsule()
                                    )
                            }
                        }
                        Text(recommendation.categoryPath.map(\.title).joined(separator: " › "))
                            .font(.system(.caption, design: .rounded, weight: .semibold))
                            .foregroundStyle(GuardianSemanticTokens.primary)
                        Text(recommendation.list.summary)
                            .font(.system(.subheadline, design: .rounded, weight: .medium))
                            .foregroundStyle(GuardianSemanticTokens.secondaryForeground)
                            .lineLimit(2)
                    }

                    Spacer()

                    VStack(alignment: .trailing, spacing: 4) {
                        Text("\(recommendation.list.words.count)")
                            .font(.system(.title3, design: .rounded, weight: .bold))
                            .monospacedDigit()
                        Text("words")
                            .font(.system(.caption, design: .rounded, weight: .medium))
                            .foregroundStyle(GuardianSemanticTokens.secondaryForeground)
                    }
                    Image(systemName: "chevron.right")
                        .foregroundStyle(GuardianSemanticTokens.secondaryForeground)
                        .accessibilityHidden(true)
                }
            }
        }
        .buttonStyle(.plain)
        .accessibilityHint("Opens this preset list without adding any words")
    }

    private func listDetail(
        _ recommendation: PresetWordRecommendation
    ) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: GuardianPrimitiveTokens.Spacing.large) {
                GuardianNavigationHeader(
                    title: recommendation.list.title,
                    onBack: {
                        selectedListID = nil
                        selectedNormalizedWords = []
                        feedback = nil
                    }
                )

                GuardianCard {
                    VStack(alignment: .leading, spacing: GuardianPrimitiveTokens.Spacing.small) {
                        Text(
                            recommendation.categoryPath.map(\.title).joined(separator: " › ")
                        )
                        .font(.system(.caption, design: .rounded, weight: .bold))
                        .foregroundStyle(GuardianSemanticTokens.primary)
                        Text(recommendation.list.summary)
                            .font(.system(.body, design: .rounded, weight: .medium))
                        Text("Nothing is added until you select words and tap Add.")
                            .font(.system(.caption, design: .rounded, weight: .semibold))
                            .foregroundStyle(GuardianSemanticTokens.secondaryForeground)
                    }
                }

                destinationPicker
                selectionControls(for: recommendation.list)
                wordGrid(for: recommendation.list)
                sourceSection(for: recommendation.list)

                if let feedback {
                    Label(feedback.message, systemImage: feedback.symbol)
                        .font(.system(.subheadline, design: .rounded, weight: .semibold))
                        .foregroundStyle(feedback.color)
                        .accessibilityLabel(feedback.message)
                }

                addButton(for: recommendation.list)
            }
            .frame(maxWidth: 920, alignment: .leading)
            .padding(.horizontal, GuardianPrimitiveTokens.Spacing.medium)
            .padding(.vertical, GuardianPrimitiveTokens.Spacing.large)
            .frame(maxWidth: .infinity)
        }
        .scrollIndicators(.hidden)
    }

    private var destinationPicker: some View {
        GuardianCard {
            VStack(alignment: .leading, spacing: GuardianPrimitiveTokens.Spacing.small) {
                Text("Add selected words to")
                    .font(.system(.headline, design: .rounded, weight: .bold))
                Picker("Destination pools", selection: $destination) {
                    ForEach(PresetWordPoolDestination.allCases, id: \.self) { destination in
                        Text(destination.guardianTitle).tag(destination)
                    }
                }
                .pickerStyle(.segmented)
            }
        }
    }

    private func selectionControls(for list: PresetWordList) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text("Choose words")
                    .font(.system(.title3, design: .rounded, weight: .bold))
                Text("\(selectedNormalizedWords.count) selected")
                    .font(.system(.caption, design: .rounded, weight: .medium))
                    .foregroundStyle(GuardianSemanticTokens.secondaryForeground)
                    .monospacedDigit()
            }
            Spacer()
            Button("Clear") {
                selectedNormalizedWords = []
                feedback = nil
            }
            .buttonStyle(.bordered)
            .disabled(selectedNormalizedWords.isEmpty)
            Button("Select all") {
                selectedNormalizedWords = Set(
                    list.words.compactMap { try? EnglishWordNormalizer.normalize($0) }
                )
                feedback = nil
            }
            .buttonStyle(.borderedProminent)
        }
    }

    private func wordGrid(for list: PresetWordList) -> some View {
        LazyVGrid(
            columns: [GridItem(.adaptive(minimum: 118), spacing: 10)],
            spacing: 10
        ) {
            ForEach(Array(list.words.enumerated()), id: \.offset) { _, word in
                let normalized = try? EnglishWordNormalizer.normalize(word)
                let isSelected = normalized.map(selectedNormalizedWords.contains) ?? false
                Button {
                    guard let normalized else { return }
                    if !selectedNormalizedWords.insert(normalized).inserted {
                        selectedNormalizedWords.remove(normalized)
                    }
                    feedback = nil
                } label: {
                    VStack(spacing: 4) {
                        HStack(spacing: 6) {
                            Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                            Text(word)
                                .lineLimit(1)
                        }
                        .font(.system(.body, design: .rounded, weight: .bold))
                        let status = membershipStatus(for: normalized)
                        if !status.isEmpty {
                            Text(status)
                                .font(.system(.caption2, design: .rounded, weight: .semibold))
                                .foregroundStyle(GuardianSemanticTokens.secondaryForeground)
                        }
                    }
                    .frame(maxWidth: .infinity, minHeight: 54)
                }
                .buttonStyle(.bordered)
                .tint(
                    isSelected
                        ? GuardianSemanticTokens.primary
                        : GuardianSemanticTokens.secondaryForeground
                )
                .disabled(normalized == nil)
                .accessibilityAddTraits(isSelected ? .isSelected : [])
            }
        }
    }

    @ViewBuilder
    private func sourceSection(for list: PresetWordList) -> some View {
        let sources = catalog.sources.filter { list.sourceIDs.contains($0.id) }
        if !sources.isEmpty {
            DisclosureGroup("Sources") {
                VStack(alignment: .leading, spacing: GuardianPrimitiveTokens.Spacing.small) {
                    ForEach(sources) { source in
                        Link(destination: source.url) {
                            Label(source.title, systemImage: "arrow.up.right.square")
                        }
                        .font(.system(.caption, design: .rounded, weight: .semibold))
                    }
                }
                .padding(.top, GuardianPrimitiveTokens.Spacing.small)
            }
            .font(.system(.subheadline, design: .rounded, weight: .bold))
        }
    }

    private func addButton(for list: PresetWordList) -> some View {
        Button {
            addSelectedWords(from: list)
        } label: {
            Label(
                isAdding
                    ? "Adding…"
                    : "Add \(selectedNormalizedWords.count) selected words",
                systemImage: "plus.circle.fill"
            )
            .frame(maxWidth: .infinity)
        }
        .buttonStyle(GuardianPrimaryButtonStyle())
        .disabled(isAdding || selectedNormalizedWords.isEmpty)
    }

    private func addSelectedWords(from list: PresetWordList) {
        guard !isAdding else { return }
        let selectedWords = list.words.filter { word in
            guard let normalized = try? EnglishWordNormalizer.normalize(word) else {
                return false
            }
            return selectedNormalizedWords.contains(normalized)
        }
        let plan = PresetWordSelectionPlanner().plan(
            selectedWords: selectedWords,
            destination: destination,
            existingReadWords: readWords,
            existingWriteWords: writeWords
        )

        guard !plan.additions.isEmpty else {
            feedback = .info("Those words are already in the selected pool or pools.")
            return
        }

        isAdding = true
        feedback = nil
        Task {
            let outcome = await GuardianPresetImportCoordinator().execute(
                profileID: profile.id,
                plan: plan,
                submit: onSubmit,
                rollback: onRollback
            )
            isAdding = false
            switch outcome {
            case .success(let summary):
                selectedNormalizedWords = []
                feedback = .success(summary.message)
            case .failure(let failure):
                feedback = .error(failure.message)
            }
        }
    }

    private func membershipStatus(for normalizedWord: String?) -> String {
        guard let normalizedWord else { return "Invalid" }
        let isInRead = readWords.contains { $0.normalizedText == normalizedWord }
        let isInWrite = writeWords.contains { $0.normalizedText == normalizedWord }
        switch destination {
        case .read:
            return isInRead ? "In Read" : ""
        case .write:
            return isInWrite ? "In Write" : ""
        case .both:
            if isInRead && isInWrite { return "In both" }
            if isInRead { return "In Read" }
            if isInWrite { return "In Write" }
            return ""
        }
    }

    private func relevanceTitle(_ relevance: PresetWordRelevance) -> String {
        switch relevance {
        case .recommended:
            "Best match"
        case .gradeMatch:
            "Grade match"
        case .ageMatch:
            "Age match"
        case .browse:
            ""
        }
    }

    private func symbol(for category: PresetWordCategory) -> String {
        let searchableText = "\(category.id) \(category.title)".lowercased()
        if searchableText.contains("dinosaur") { return "lizard.fill" }
        if searchableText.contains("animal") { return "pawprint.fill" }
        if searchableText.contains("vehicle") || searchableText.contains("car") {
            return "car.fill"
        }
        if searchableText.contains("city") { return "building.2.fill" }
        if searchableText.contains("country") || searchableText.contains("world") {
            return "globe.americas.fill"
        }
        if searchableText.contains("emotion") || searchableText.contains("feeling") {
            return "face.smiling.fill"
        }
        return symbol(for: category.id)
    }

    private func symbol(for rootCategoryID: String?) -> String {
        switch rootCategoryID {
        case "sight-words":
            "eye.fill"
        case "phonics", "phonics-and-spelling":
            "text.book.closed.fill"
        case "nouns":
            "shippingbox.fill"
        case "verbs":
            "figure.run"
        case "adjectives":
            "paintpalette.fill"
        case "social-language":
            "bubble.left.and.bubble.right.fill"
        default:
            "books.vertical.fill"
        }
    }
}

extension PresetWordPoolDestination {
    fileprivate var guardianTitle: String {
        switch self {
        case .read:
            "Read"
        case .write:
            "Write"
        case .both:
            "Both"
        }
    }
}

private enum PresetImportFeedback: Equatable {
    case success(String)
    case info(String)
    case error(String)

    var message: String {
        switch self {
        case .success(let message), .info(let message), .error(let message):
            message
        }
    }

    var symbol: String {
        switch self {
        case .success:
            "checkmark.circle.fill"
        case .info:
            "info.circle.fill"
        case .error:
            "exclamationmark.triangle.fill"
        }
    }

    var color: Color {
        switch self {
        case .success:
            GuardianSemanticTokens.success
        case .info:
            GuardianSemanticTokens.primary
        case .error:
            .red
        }
    }
}
