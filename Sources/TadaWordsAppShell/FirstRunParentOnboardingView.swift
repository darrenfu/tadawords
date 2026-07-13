import SwiftUI
import TadaWordsDesignSystem
import TadaWordsDomain
import TadaWordsGuardianFeatures

@MainActor
struct FirstRunParentOnboardingView: View {
    private enum Step: Int, CaseIterable {
        case welcome
        case profile
        case words

        var title: String {
            switch self {
            case .welcome:
                "Welcome"
            case .profile:
                "Your learner"
            case .words:
                "Two quest paths"
            }
        }
    }

    let initialProfile: KidProfile
    let onFinish: @MainActor (FirstRunOnboardingSubmission) async throws -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var step: Step = .welcome
    @State private var displayName: String
    @State private var avatarAssetID: String
    @State private var schoolGrade: ProfileSchoolGrade
    @State private var selectedWorld: WorldTheme
    @State private var hasAcceptedConsent = false
    @State private var readWords = ""
    @State private var writeWords = ""
    @State private var isSaving = false
    @State private var errorMessage: String?
    @FocusState private var nicknameIsFocused: Bool
    @AccessibilityFocusState private var stepHeadingIsFocused: Bool

    init(
        initialProfile: KidProfile,
        onFinish: @escaping @MainActor (FirstRunOnboardingSubmission) async throws -> Void
    ) {
        self.initialProfile = initialProfile
        self.onFinish = onFinish
        _displayName = State(
            initialValue: initialProfile.displayName == "My Kid"
                ? ""
                : initialProfile.displayName
        )
        _avatarAssetID = State(
            initialValue: initialProfile.avatar.cartoonAnimalAssetID ?? "hare"
        )
        _schoolGrade = State(initialValue: initialProfile.schoolGrade)
        _selectedWorld = State(initialValue: initialProfile.selectedWorld)
    }

    var body: some View {
        TadaWorldBackground(theme: theme, sceneStyle: .lobby) {
            VStack(spacing: 0) {
                header
                ScrollView {
                    stepContent
                        .frame(maxWidth: 1_080)
                        .padding(.horizontal, TadaPrimitiveTokens.Spacing.large)
                        .padding(.vertical, 12)
                        .frame(maxWidth: .infinity)
                }
                .scrollDismissesKeyboard(.interactively)
                .scrollIndicators(.hidden)
                footer
            }
            .background(Color.white.opacity(0.12))
        }
        .foregroundStyle(theme.ink)
        .preferredColorScheme(.light)
        .disabled(isSaving)
        .overlay {
            if isSaving {
                savingOverlay
            }
        }
        .alert(
            "Setup couldn’t save",
            isPresented: Binding(
                get: { errorMessage != nil },
                set: { if !$0 { errorMessage = nil } }
            )
        ) {
            Button("OK", role: .cancel) {
                errorMessage = nil
            }
        } message: {
            Text(errorMessage ?? "Please try again.")
        }
        .onChange(of: step) { _, newStep in
            stepHeadingIsFocused = true
            if newStep == .profile {
                nicknameIsFocused = true
            }
        }
    }

    private var theme: TadaWorldTheme {
        switch selectedWorld {
        case .moonpetalKingdom:
            .moonpetal
        case .buildItBay:
            .buildItBay
        case .pawsAndPines:
            .pawsAndPines
        }
    }

    private var normalizedName: String {
        displayName.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var canContinue: Bool {
        switch step {
        case .welcome:
            hasAcceptedConsent
        case .profile:
            !normalizedName.isEmpty
                && normalizedName.count
                    <= FirstRunOnboardingCoordinator.maximumDisplayNameCharacterCount
        case .words:
            true
        }
    }

    private var header: some View {
        HStack(spacing: TadaPrimitiveTokens.Spacing.medium) {
            Label("Tada Words", systemImage: "sparkles")
                .font(.system(.title3, design: .rounded, weight: .black))
                .foregroundStyle(theme.primary)

            Text("Parent setup")
                .font(.system(.caption, design: .rounded, weight: .bold))
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(theme.primary.opacity(0.10), in: Capsule())

            Spacer()

            HStack(spacing: 7) {
                ForEach(Step.allCases, id: \.rawValue) { item in
                    Capsule()
                        .fill(
                            item.rawValue <= step.rawValue
                                ? theme.primary
                                : theme.ink.opacity(0.16)
                        )
                        .frame(
                            width: item == step ? 30 : 12,
                            height: 10
                        )
                }
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Setup progress")
            .accessibilityValue("Step \(step.rawValue + 1) of \(Step.allCases.count)")
        }
        .padding(.horizontal, TadaPrimitiveTokens.Spacing.large)
        .frame(minHeight: 54)
        .background(Color.white.opacity(0.78))
        .overlay(alignment: .bottom) {
            Divider().opacity(0.35)
        }
    }

    @ViewBuilder
    private var stepContent: some View {
        switch step {
        case .welcome:
            welcomeStep
        case .profile:
            profileStep
        case .words:
            wordsStep
        }
    }

    private var welcomeStep: some View {
        HStack(alignment: .center, spacing: TadaPrimitiveTokens.Spacing.xLarge) {
            VStack(spacing: 8) {
                TadaWorldMascot(theme: theme, pose: .cheering, size: 116)
                TadaRewardShelf(
                    theme: theme,
                    highlightedCount: 2,
                    isCompact: true,
                    visibleLimit: 5
                )
            }
            .frame(minWidth: 210)

            VStack(alignment: .leading, spacing: TadaPrimitiveTokens.Spacing.medium) {
                stepHeading(
                    eyebrow: "A small daily ritual",
                    title: "Hear it. Say it. Write it. Tada!",
                    message:
                        "Tada Words turns the exact sight words from school into two short, playful quests. Progress and review timing stay with each child profile."
                )

                HStack(spacing: 12) {
                    welcomeFeature(
                        symbol: "mic.fill",
                        title: "Read Quest",
                        detail: "See a word and say it aloud.",
                        tint: theme.primary
                    )
                    welcomeFeature(
                        symbol: "pencil.line",
                        title: "Write Quest",
                        detail: "Hear a word and write it independently.",
                        tint: theme.secondary
                    )
                }

                Toggle(isOn: $hasAcceptedConsent) {
                    VStack(alignment: .leading, spacing: 3) {
                        Text("I understand and want to continue")
                            .font(.system(.subheadline, design: .rounded, weight: .bold))
                        Text(
                            "Raw voice recordings are not saved. A voice template stays on this device. Learning data sync is optional through iCloud. A profile deletion may sync to family devices and cannot be undone."
                        )
                        .font(.system(.caption, design: .rounded, weight: .medium))
                        .foregroundStyle(theme.ink.opacity(0.70))
                    }
                }
                .toggleStyle(.switch)
                .tint(theme.primary)
                .padding(12)
                .background(
                    Color.white.opacity(0.82),
                    in: RoundedRectangle(cornerRadius: 16, style: .continuous)
                )
                .accessibilityHint("Required to continue parent setup")
            }
        }
        .padding(.vertical, 8)
    }

    private var profileStep: some View {
        VStack(alignment: .leading, spacing: 12) {
            stepHeading(
                eyebrow: "One profile, one learning history",
                title: "Who is playing?",
                message: "Choose a nickname, animal friend, level, and starter world."
            )

            LazyVGrid(
                columns: [GridItem(.adaptive(minimum: 330), spacing: 16)],
                alignment: .leading,
                spacing: 16
            ) {
                onboardingCard {
                    VStack(alignment: .leading, spacing: 12) {
                        Label("Nickname & avatar", systemImage: "person.crop.circle.fill")
                            .font(.system(.headline, design: .rounded, weight: .bold))

                        TextField("Child’s nickname", text: $displayName)
                            .textFieldStyle(.roundedBorder)
                            .focused($nicknameIsFocused)
                            .submitLabel(.done)
                            .accessibilityHint("Up to 24 characters")

                        HStack(spacing: 8) {
                            ForEach(GuardianAnimalAvatar.available) { option in
                                Button {
                                    avatarAssetID = option.id
                                } label: {
                                    VStack(spacing: 3) {
                                        Image(systemName: option.symbol)
                                            .font(.system(size: 22, weight: .bold))
                                        Text(option.name)
                                            .font(
                                                .system(
                                                    .caption2,
                                                    design: .rounded,
                                                    weight: .bold
                                                )
                                            )
                                            .lineLimit(1)
                                    }
                                    .frame(maxWidth: .infinity, minHeight: 52)
                                }
                                .buttonStyle(.plain)
                                .foregroundStyle(
                                    avatarAssetID == option.id
                                        ? Color.white
                                        : theme.primary
                                )
                                .background(
                                    avatarAssetID == option.id
                                        ? theme.primary
                                        : theme.primary.opacity(0.09),
                                    in: RoundedRectangle(
                                        cornerRadius: 12,
                                        style: .continuous
                                    )
                                )
                                .accessibilityAddTraits(
                                    avatarAssetID == option.id ? .isSelected : []
                                )
                            }
                        }

                        Text(
                            "A photo can be added later from Grown-ups. No photo permission is asked now."
                        )
                        .font(.system(.caption, design: .rounded, weight: .medium))
                        .foregroundStyle(theme.ink.opacity(0.68))
                    }
                }

                onboardingCard {
                    VStack(alignment: .leading, spacing: 12) {
                        Label("Level & starter world", systemImage: "map.fill")
                            .font(.system(.headline, design: .rounded, weight: .bold))

                        Picker("School level", selection: $schoolGrade) {
                            ForEach(ProfileSchoolGrade.allCases, id: \.self) { grade in
                                Text(grade.displayName).tag(grade)
                            }
                        }
                        .pickerStyle(.menu)

                        HStack(spacing: 8) {
                            ForEach(WorldTheme.allCases, id: \.self) { world in
                                worldButton(world)
                            }
                        }
                    }
                }
            }
        }
    }

    private var wordsStep: some View {
        VStack(alignment: .leading, spacing: 12) {
            stepHeading(
                eyebrow: "Keep school lists separate",
                title: "Read and Write are two different pools",
                message:
                    "The same word can be in both pools, but it does not have to be. Each pool gets its own Today Quest button and review schedule."
            )

            HStack(alignment: .top, spacing: 14) {
                modeExplanation(
                    mode: .read,
                    symbol: "mic.fill",
                    title: "Read Pool",
                    detail: "Words the child should see and read aloud.",
                    tint: theme.primary,
                    words: $readWords,
                    placeholder: "e.g. the, said, look"
                )
                modeExplanation(
                    mode: .write,
                    symbol: "pencil.line",
                    title: "Write Pool",
                    detail: "Sight words the child should hear, then write on blank lines.",
                    tint: theme.secondary,
                    words: $writeWords,
                    placeholder: "e.g. can, look, play"
                )
                onboardingCard {
                    VStack(alignment: .leading, spacing: 9) {
                        Label("Parent Quick Add", systemImage: "plus.circle.fill")
                            .font(.system(.headline, design: .rounded, weight: .bold))
                            .foregroundStyle(theme.accent)
                        Text(
                            "Open Grown-ups → Quick Add, choose Read or Write, then type or paste this week’s school words."
                        )
                        .font(.system(.subheadline, design: .rounded, weight: .medium))
                        Text("Duplicates are removed automatically.")
                            .font(.system(.caption, design: .rounded, weight: .bold))
                            .foregroundStyle(theme.ink.opacity(0.68))
                        Text("Both boxes are optional. Empty pools can be filled later.")
                            .font(.system(.caption, design: .rounded, weight: .medium))
                            .foregroundStyle(theme.ink.opacity(0.68))
                    }
                }
            }

            VStack(alignment: .leading, spacing: 4) {
                Label(
                    "Next: Grown-ups can run the one-minute Voice Setup and choose reminders.",
                    systemImage: "waveform.badge.mic"
                )
                Text(
                    "Microphone and speech access are requested only when a Read Quest or Voice Setup needs them. Notifications remain off until a parent enables them."
                )
            }
            .font(.system(.caption, design: .rounded, weight: .semibold))
            .foregroundStyle(theme.ink.opacity(0.70))
            .padding(.horizontal, 4)
        }
    }

    private func stepHeading(
        eyebrow: String,
        title: String,
        message: String
    ) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(eyebrow.uppercased())
                .font(.system(.caption, design: .rounded, weight: .black))
                .tracking(1.1)
                .foregroundStyle(theme.primary)
            Text(title)
                .font(.system(.title2, design: .rounded, weight: .black))
                .accessibilityFocused($stepHeadingIsFocused)
            Text(message)
                .font(.system(.subheadline, design: .rounded, weight: .medium))
                .foregroundStyle(theme.ink.opacity(0.72))
                .fixedSize(horizontal: false, vertical: true)
        }
        .accessibilityElement(children: .combine)
    }

    private func welcomeFeature(
        symbol: String,
        title: String,
        detail: String,
        tint: Color
    ) -> some View {
        HStack(spacing: 10) {
            Image(systemName: symbol)
                .font(.system(size: 22, weight: .bold))
                .foregroundStyle(Color.white)
                .frame(width: 44, height: 44)
                .background(tint, in: Circle())
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(.headline, design: .rounded, weight: .bold))
                Text(detail)
                    .font(.system(.caption, design: .rounded, weight: .medium))
                    .foregroundStyle(theme.ink.opacity(0.68))
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(Color.white.opacity(0.76), in: RoundedRectangle(cornerRadius: 16))
    }

    private func worldButton(_ world: WorldTheme) -> some View {
        let selected = selectedWorld == world
        return Button {
            selectedWorld = world
        } label: {
            VStack(spacing: 5) {
                Image(systemName: world.symbol)
                    .font(.system(size: 23, weight: .bold))
                Text(world.shortName)
                    .font(.system(.caption, design: .rounded, weight: .bold))
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
            }
            .frame(maxWidth: .infinity, minHeight: 64)
        }
        .buttonStyle(.plain)
        .foregroundStyle(selected ? Color.white : theme.primary)
        .background(
            selected ? theme.primary : theme.primary.opacity(0.09),
            in: RoundedRectangle(cornerRadius: 14, style: .continuous)
        )
        .accessibilityLabel(world.displayName)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    private func modeExplanation(
        mode: LearningMode,
        symbol: String,
        title: String,
        detail: String,
        tint: Color,
        words: Binding<String>,
        placeholder: String
    ) -> some View {
        onboardingCard {
            VStack(alignment: .leading, spacing: 8) {
                Image(systemName: symbol)
                    .font(.system(size: 23, weight: .bold))
                    .foregroundStyle(Color.white)
                    .frame(width: 44, height: 44)
                    .background(tint, in: Circle())
                Text(title)
                    .font(.system(.headline, design: .rounded, weight: .bold))
                Text(detail)
                    .font(.system(.subheadline, design: .rounded, weight: .medium))
                    .foregroundStyle(theme.ink.opacity(0.70))
                TextField(placeholder, text: words, axis: .vertical)
                    .textFieldStyle(.roundedBorder)
                    .lineLimit(2...3)
                    .accessibilityLabel("Optional \(title) words")
            }
        }
    }

    private func onboardingCard<Content: View>(
        @ViewBuilder content: () -> Content
    ) -> some View {
        content()
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(16)
            .background(
                Color.white.opacity(0.88),
                in: RoundedRectangle(cornerRadius: 20, style: .continuous)
            )
            .overlay {
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .strokeBorder(Color.white.opacity(0.72), lineWidth: 1)
            }
    }

    private var footer: some View {
        HStack(spacing: 12) {
            if step != .welcome {
                Button("Back") {
                    move(to: Step(rawValue: step.rawValue - 1) ?? .welcome)
                }
                .buttonStyle(.bordered)
                .controlSize(.large)
            }

            Spacer()

            Button {
                continueTapped()
            } label: {
                Label(
                    step == .words ? "Save & Start" : "Continue",
                    systemImage: step == .words ? "sparkles" : "arrow.right"
                )
            }
            .buttonStyle(TadaPrimaryButtonStyle(fill: theme.primary, isCompact: true))
            .disabled(!canContinue)
            .accessibilityHint(
                !canContinue
                    ? step == .welcome
                        ? "Accept the parent consent summary to continue"
                        : "Enter a nickname to continue"
                    : ""
            )
        }
        .padding(.horizontal, TadaPrimitiveTokens.Spacing.large)
        .padding(.vertical, 9)
        .background(Color.white.opacity(0.86))
        .overlay(alignment: .top) {
            Divider().opacity(0.35)
        }
    }

    private var savingOverlay: some View {
        ZStack {
            Color.black.opacity(0.14).ignoresSafeArea()
            ProgressView("Saving \(normalizedName)’s profile…")
                .font(.system(.headline, design: .rounded, weight: .bold))
                .padding(22)
                .background(Color.white, in: RoundedRectangle(cornerRadius: 20))
                .tint(theme.primary)
        }
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.updatesFrequently)
    }

    private func continueTapped() {
        guard canContinue else { return }
        if step != .words {
            move(to: Step(rawValue: step.rawValue + 1) ?? .words)
            return
        }

        isSaving = true
        Task { @MainActor in
            defer { isSaving = false }
            do {
                try await onFinish(
                    FirstRunOnboardingSubmission(
                        profileDraft: GuardianProfileDraft(
                            displayName: normalizedName,
                            avatar: .cartoonAnimal(assetID: avatarAssetID),
                            selectedWorld: selectedWorld,
                            schoolGrade: schoolGrade,
                            ageYears: initialProfile.ageYears ?? schoolGrade.suggestedAge,
                            guardianUnlockedWorlds: [selectedWorld]
                        ),
                        readWords: readWords,
                        writeWords: writeWords
                    )
                )
            } catch {
                errorMessage = Self.message(for: error)
            }
        }
    }

    private func move(to newStep: Step) {
        withAnimation(
            reduceMotion
                ? .linear(duration: 0.01)
                : .easeInOut(duration: TadaPrimitiveTokens.Motion.standard)
        ) {
            step = newStep
        }
    }

    private static func message(for error: any Error) -> String {
        switch error {
        case FirstRunOnboardingError.emptyDisplayName:
            "Enter a nickname, then try again."
        case FirstRunOnboardingError.displayNameTooLong(let maximum):
            "Use a nickname with \(maximum) characters or fewer."
        default:
            "Your child’s setup is still here. Check that storage is available, then try again."
        }
    }
}

extension ProfileAvatar {
    fileprivate var cartoonAnimalAssetID: String? {
        guard case .cartoonAnimal(let assetID) = self else { return nil }
        return assetID
    }
}

extension WorldTheme {
    fileprivate var symbol: String {
        switch self {
        case .moonpetalKingdom:
            "crown.fill"
        case .buildItBay:
            "truck.box.fill"
        case .pawsAndPines:
            "pawprint.fill"
        }
    }

    fileprivate var shortName: String {
        switch self {
        case .moonpetalKingdom:
            "Princess"
        case .buildItBay:
            "Build"
        case .pawsAndPines:
            "Animals"
        }
    }
}

extension ProfileSchoolGrade {
    fileprivate var suggestedAge: Int {
        switch self {
        case .preK:
            4
        case .kindergarten:
            5
        case .grade1:
            6
        case .grade2:
            7
        case .grade3:
            8
        }
    }
}
