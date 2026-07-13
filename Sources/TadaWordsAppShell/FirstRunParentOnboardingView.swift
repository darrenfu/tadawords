import SwiftUI
import TadaWordsDesignSystem
import TadaWordsDomain
import TadaWordsGuardianFeatures

enum FirstRunPrivacyDisclosure {
    static func message(for capability: FamilySyncCapability) -> String {
        switch capability {
        case .deviceOnly:
            "Raw voice recordings are not saved. A voice template and learning data stay on this device. Deleting a profile removes its local learning data and cannot be undone."
        case .iCloud:
            "Raw voice recordings are not saved. A voice template stays on this device. iCloud learning-data sync is off by default and can be enabled later by a parent. Deleting a profile may affect family devices and cannot be undone."
        }
    }
}

@MainActor
struct FirstRunParentOnboardingView: View {
    let initialProfile: KidProfile
    let purpose: FirstRunOnboardingPurpose
    let familySyncCapability: FamilySyncCapability
    let onFinish: @MainActor (FirstRunOnboardingSubmission) async throws -> Void

    @State private var displayName: String
    @State private var avatarAssetID: String
    @State private var schoolGrade: ProfileSchoolGrade
    @State private var selectedWorld: WorldTheme
    @State private var hasAcceptedConsent = false
    @State private var isSaving = false
    @State private var errorMessage: String?
    @FocusState private var nicknameIsFocused: Bool

    init(
        initialProfile: KidProfile,
        purpose: FirstRunOnboardingPurpose,
        familySyncCapability: FamilySyncCapability,
        onFinish: @escaping @MainActor (FirstRunOnboardingSubmission) async throws -> Void
    ) {
        self.initialProfile = initialProfile
        self.purpose = purpose
        self.familySyncCapability = familySyncCapability
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
                    content
                        .frame(maxWidth: 980)
                        .padding(.horizontal, TadaPrimitiveTokens.Spacing.large)
                        .padding(.vertical, TadaPrimitiveTokens.Spacing.medium)
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
        .task {
            guard purpose == .fullSetup else { return }
            nicknameIsFocused = true
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
        case .dinoDiscovery:
            .dinoDiscovery
        case .firehouseHeroes:
            .firehouseHeroes
        case .brickworkCity:
            .brickworkCity
        case .frostlightWorld:
            .frostlightWorld
        case .coasterCarnival:
            .coasterCarnival
        }
    }

    private var normalizedName: String {
        displayName.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var canFinish: Bool {
        guard hasAcceptedConsent else { return false }
        guard purpose == .fullSetup else { return true }
        return !normalizedName.isEmpty
            && normalizedName.count
                <= FirstRunOnboardingCoordinator.maximumDisplayNameCharacterCount
    }

    private var header: some View {
        HStack(spacing: TadaPrimitiveTokens.Spacing.medium) {
            Label("Tada Words", systemImage: "sparkles")
                .font(.system(.title3, design: .rounded, weight: .black))
                .foregroundStyle(theme.primary)

            Text(purpose == .fullSetup ? "New kid" : "Privacy check")
                .font(.system(.caption, design: .rounded, weight: .bold))
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(theme.primary.opacity(0.10), in: Capsule())

            Spacer()
        }
        .padding(.horizontal, TadaPrimitiveTokens.Spacing.large)
        .frame(minHeight: 54)
        .background(Color.white.opacity(0.78))
        .overlay(alignment: .bottom) {
            Divider().opacity(0.35)
        }
    }

    @ViewBuilder
    private var content: some View {
        switch purpose {
        case .fullSetup:
            profileCreationContent
        case .consentRefresh:
            existingProfileContent
        }
    }

    private var profileCreationContent: some View {
        VStack(alignment: .leading, spacing: TadaPrimitiveTokens.Spacing.medium) {
            heading(
                eyebrow: "Kid profile",
                title: "Who is playing?",
                message:
                    "Create a kid profile first. A parent can add this week’s Read and Write words later from Parents."
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
                                avatarButton(option)
                            }
                        }

                        Text(
                            "A photo can be added later from Parents. No photo permission is asked now."
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

                        LazyVGrid(
                            columns: [
                                GridItem(.adaptive(minimum: 88), spacing: 8)
                            ],
                            spacing: 8
                        ) {
                            ForEach(WorldTheme.allCases, id: \.self) { world in
                                worldButton(world)
                            }
                        }
                    }
                }
            }

            privacyConfirmation
        }
    }

    private var existingProfileContent: some View {
        VStack(alignment: .leading, spacing: TadaPrimitiveTokens.Spacing.medium) {
            heading(
                eyebrow: "Profiles are ready",
                title: "Continue where you left off",
                message:
                    "Your kids and learning history will not be changed. After this quick privacy confirmation, Tada Words opens the last kid profile you used—or the kid chooser if no choice was saved."
            )

            onboardingCard {
                HStack(spacing: 14) {
                    Image(systemName: initialProfile.avatar.onboardingSymbol)
                        .font(.system(size: 34, weight: .bold))
                        .foregroundStyle(Color.white)
                        .frame(width: 68, height: 68)
                        .background(theme.primary, in: Circle())

                    VStack(alignment: .leading, spacing: 4) {
                        Text(initialProfile.displayName)
                            .font(.system(.title2, design: .rounded, weight: .black))
                        Text("Existing profile • \(initialProfile.schoolGrade.displayName)")
                            .font(.system(.subheadline, design: .rounded, weight: .semibold))
                            .foregroundStyle(theme.ink.opacity(0.68))
                    }
                    Spacer()
                    Image(systemName: "checkmark.seal.fill")
                        .font(.system(size: 28, weight: .bold))
                        .foregroundStyle(theme.primary)
                        .accessibilityHidden(true)
                }
                .accessibilityElement(children: .combine)
            }

            privacyConfirmation
        }
    }

    private var privacyConfirmation: some View {
        Toggle(isOn: $hasAcceptedConsent) {
            VStack(alignment: .leading, spacing: 5) {
                Text("Parent privacy confirmation")
                    .font(.system(.headline, design: .rounded, weight: .bold))
                Text(FirstRunPrivacyDisclosure.message(for: familySyncCapability))
                    .font(.system(.caption, design: .rounded, weight: .medium))
                    .foregroundStyle(theme.ink.opacity(0.72))
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .toggleStyle(.switch)
        .tint(theme.primary)
        .padding(16)
        .background(
            Color.white.opacity(0.90),
            in: RoundedRectangle(cornerRadius: 20, style: .continuous)
        )
        .accessibilityHint("Required before continuing")
    }

    private func heading(
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
            Text(message)
                .font(.system(.subheadline, design: .rounded, weight: .medium))
                .foregroundStyle(theme.ink.opacity(0.72))
                .fixedSize(horizontal: false, vertical: true)
        }
        .accessibilityElement(children: .combine)
    }

    private func avatarButton(_ option: GuardianAnimalAvatar) -> some View {
        Button {
            avatarAssetID = option.id
        } label: {
            VStack(spacing: 3) {
                Image(systemName: option.symbol)
                    .font(.system(size: 22, weight: .bold))
                Text(option.name)
                    .font(.system(.caption2, design: .rounded, weight: .bold))
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity, minHeight: 52)
        }
        .buttonStyle(.plain)
        .foregroundStyle(avatarAssetID == option.id ? Color.white : theme.primary)
        .background(
            avatarAssetID == option.id ? theme.primary : theme.primary.opacity(0.09),
            in: RoundedRectangle(cornerRadius: 12, style: .continuous)
        )
        .accessibilityAddTraits(avatarAssetID == option.id ? .isSelected : [])
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
        HStack {
            Text(
                purpose == .fullSetup
                    ? "Words come later in Parents."
                    : "No profile data will be rewritten."
            )
            .font(.system(.caption, design: .rounded, weight: .semibold))
            .foregroundStyle(theme.ink.opacity(0.68))

            Spacer()

            Button {
                finishOnboarding()
            } label: {
                Label(
                    purpose == .fullSetup ? "Create & Play" : "Accept & Continue",
                    systemImage: "sparkles"
                )
            }
            .buttonStyle(TadaPrimaryButtonStyle(fill: theme.primary, isCompact: true))
            .disabled(!canFinish)
            .accessibilityHint(
                canFinish
                    ? ""
                    : purpose == .fullSetup && normalizedName.isEmpty
                        ? "Enter a nickname and accept the privacy summary"
                        : "Accept the privacy summary to continue"
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
            ProgressView(
                purpose == .consentRefresh
                    ? "Saving your privacy choice…"
                    : "Creating (normalizedName)’s profile…"
            )
            .font(.system(.headline, design: .rounded, weight: .bold))
            .padding(22)
            .background(Color.white, in: RoundedRectangle(cornerRadius: 20))
            .tint(theme.primary)
        }
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.updatesFrequently)
    }

    private func finishOnboarding() {
        guard canFinish else { return }
        isSaving = true
        Task { @MainActor in
            defer { isSaving = false }
            do {
                try await onFinish(
                    FirstRunOnboardingSubmission(action: submissionAction)
                )
            } catch {
                errorMessage = Self.message(for: error)
            }
        }
    }

    private var submissionAction: FirstRunOnboardingSubmission.Action {
        switch purpose {
        case .fullSetup:
            .createProfile(
                GuardianProfileDraft(
                    displayName: normalizedName,
                    avatar: .cartoonAnimal(assetID: avatarAssetID),
                    selectedWorld: selectedWorld,
                    schoolGrade: schoolGrade,
                    ageYears: initialProfile.ageYears ?? schoolGrade.suggestedAge,
                    guardianUnlockedWorlds: [selectedWorld]
                )
            )
        case .consentRefresh:
            .confirmExistingProfiles
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

    fileprivate var onboardingSymbol: String {
        guard let assetID = cartoonAnimalAssetID else {
            return "person.crop.circle.fill"
        }
        return GuardianAnimalAvatar.option(for: assetID)?.symbol ?? "pawprint.fill"
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
        case .dinoDiscovery:
            "lizard.fill"
        case .firehouseHeroes:
            "firetruck.fill"
        case .brickworkCity:
            "square.grid.3x3.fill"
        case .frostlightWorld:
            "snowflake"
        case .coasterCarnival:
            "ticket.fill"
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
        case .dinoDiscovery:
            "Dinos"
        case .firehouseHeroes:
            "Firehouse"
        case .brickworkCity:
            "Blocks"
        case .frostlightWorld:
            "Frostlight"
        case .coasterCarnival:
            "Coaster"
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
