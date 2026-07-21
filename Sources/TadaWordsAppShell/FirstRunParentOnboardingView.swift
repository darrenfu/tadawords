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
            "Raw voice recordings are not saved. A voice template stays on this device. iCloud learning-data sync is off by default and turns on only when a parent chooses Find my kid or enables it later. Deleting a profile may affect family devices and cannot be undone."
        }
    }
}

@MainActor
struct FirstRunParentOnboardingView: View {
    private enum FullSetupRoute: Equatable {
        case choose
        case create
        case discover
    }

    private enum DiscoveryState: Equatable {
        case idle
        case searching
        case results
        case failed(FirstRunProfileDiscoveryError)
    }

    let purpose: FirstRunOnboardingPurpose
    let familySyncCapability: FamilySyncCapability
    let onDiscoverProfiles: @MainActor () async throws -> [KidProfile]
    let onFinish: @MainActor (FirstRunOnboardingSubmission) async throws -> Void
    private let presentationProfile: KidProfile

    @State private var fullSetupRoute: FullSetupRoute
    @State private var discoveryState = DiscoveryState.idle
    @State private var discoveredProfiles: [KidProfile] = []
    @State private var selectedDiscoveredProfileID: ProfileID?
    @State private var displayName: String
    @State private var avatarAssetID: String
    @State private var schoolGrade: ProfileSchoolGrade
    @State private var ageYears: Int?
    @State private var selectedWorld: WorldTheme
    @State private var hasAcceptedConsent = false
    @State private var isSaving = false
    @State private var errorMessage: String?
    @FocusState private var nicknameIsFocused: Bool

    init(
        initialProfile: KidProfile?,
        purpose: FirstRunOnboardingPurpose,
        familySyncCapability: FamilySyncCapability,
        onDiscoverProfiles: @escaping @MainActor () async throws -> [KidProfile],
        onFinish: @escaping @MainActor (FirstRunOnboardingSubmission) async throws -> Void
    ) {
        let presentationProfile =
            initialProfile
            ?? KidProfile(
                displayName: "My Kid",
                avatar: .cartoonAnimal(assetID: "rat"),
                selectedWorld: .moonpetalKingdom,
                schoolGrade: .preK,
                createdAt: .distantPast
            )
        self.presentationProfile = presentationProfile
        self.purpose = purpose
        self.familySyncCapability = familySyncCapability
        self.onDiscoverProfiles = onDiscoverProfiles
        self.onFinish = onFinish
        _fullSetupRoute = State(
            initialValue: purpose == .fullSetup
                && familySyncCapability == .iCloud
                && initialProfile == nil
                ? .choose
                : .create
        )
        _displayName = State(
            initialValue: presentationProfile.displayName == "My Kid"
                ? ""
                : presentationProfile.displayName
        )
        _avatarAssetID = State(
            initialValue: presentationProfile.avatar.cartoonAnimalAssetID ?? "rat"
        )
        _schoolGrade = State(initialValue: presentationProfile.schoolGrade)
        _ageYears = State(
            initialValue: purpose == .fullSetup ? nil : presentationProfile.ageYears
        )
        _selectedWorld = State(initialValue: presentationProfile.selectedWorld)
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
        .disabled(isSaving || discoveryState == .searching)
        .overlay {
            if isSaving || discoveryState == .searching {
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
            guard purpose == .fullSetup, fullSetupRoute == .create else { return }
            nicknameIsFocused = true
        }
    }

    private var theme: TadaWorldTheme {
        let world =
            discoveredProfiles.first(where: {
                $0.id == selectedDiscoveredProfileID
            })?.selectedWorld ?? selectedWorld
        return switch world {
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
        guard !discoveryResetMustRetry else { return false }
        switch fullSetupRoute {
        case .choose:
            return false
        case .discover:
            return selectedDiscoveredProfileID != nil
        case .create:
            return !normalizedName.isEmpty
                && normalizedName.count
                    <= FirstRunOnboardingCoordinator.maximumDisplayNameCharacterCount
                && ageYears.map(ProfileAgePolicy.isSupported) == true
        }
    }

    private var header: some View {
        HStack(spacing: TadaPrimitiveTokens.Spacing.medium) {
            Label("Tada Words", systemImage: "sparkles")
                .font(.system(.title3, design: .rounded, weight: .black))
                .foregroundStyle(theme.primary)

            Text(headerBadgeTitle)
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
            switch fullSetupRoute {
            case .choose:
                setupChoiceContent
            case .create:
                profileCreationContent
            case .discover:
                profileDiscoveryContent
            }
        case .consentRefresh:
            existingProfileContent
        }
    }

    private var headerBadgeTitle: String {
        guard purpose == .fullSetup else { return "Privacy check" }
        return switch fullSetupRoute {
        case .choose:
            "Add this device"
        case .create:
            "New kid"
        case .discover:
            "Find my kid"
        }
    }

    private var setupChoiceContent: some View {
        VStack(alignment: .leading, spacing: TadaPrimitiveTokens.Spacing.medium) {
            heading(
                eyebrow: "Kid profile",
                title: "Who is playing?",
                message:
                    "If your kid already plays Tada Words on another device, find that exact profile before creating a new one."
            )

            privacyConfirmation

            if case .failed(let error) = discoveryState {
                discoveryFailureCard(error)
            }

            LazyVGrid(
                columns: [GridItem(.adaptive(minimum: 330), spacing: 16)],
                alignment: .leading,
                spacing: 16
            ) {
                setupRouteButton(
                    title: "Find my kid",
                    message: "Use an existing profile from this family’s iCloud.",
                    symbol: "icloud.and.arrow.down.fill",
                    accessibilityID: "first-run.find-existing"
                ) {
                    discoverProfiles()
                }
                .disabled(!hasAcceptedConsent)

                setupRouteButton(
                    title: "Create a new kid",
                    message:
                        "Start a separate profile on this device, even when iCloud is offline.",
                    symbol: "person.crop.circle.badge.plus",
                    accessibilityID: "first-run.create-new"
                ) {
                    fullSetupRoute = .create
                    nicknameIsFocused = true
                }
                .disabled(discoveryResetMustRetry)
            }
        }
    }

    private var profileDiscoveryContent: some View {
        VStack(alignment: .leading, spacing: TadaPrimitiveTokens.Spacing.medium) {
            heading(
                eyebrow: "Found in iCloud",
                title: discoveredProfiles.isEmpty
                    ? "No kid profiles found"
                    : "Choose the exact profile",
                message: discoveredProfiles.isEmpty
                    ? "Nothing was changed. Retry, or explicitly create a separate new profile."
                    : "Profiles stay separate by their unique identity—even when two kids use the same nickname."
            )

            if discoveredProfiles.isEmpty {
                onboardingCard {
                    VStack(alignment: .leading, spacing: 12) {
                        Label("No profiles yet", systemImage: "icloud.slash")
                            .font(.system(.headline, design: .rounded, weight: .bold))
                        Text(
                            "Make sure Family Sync finished on the other device, then try again."
                        )
                        .font(.system(.subheadline, design: .rounded, weight: .medium))
                        .foregroundStyle(theme.ink.opacity(0.72))

                        discoveryAlternativeButtons
                    }
                }
            } else {
                VStack(spacing: 12) {
                    ForEach(discoveredProfiles, id: \.id) { profile in
                        discoveredProfileButton(profile)
                    }
                }
                discoveryAlternativeButtons
            }
        }
    }

    private var discoveryAlternativeButtons: some View {
        LazyVGrid(
            columns: [GridItem(.adaptive(minimum: 140), spacing: 12)],
            spacing: 12
        ) {
            Button("Back") {
                selectedDiscoveredProfileID = nil
                fullSetupRoute = .choose
            }
            .buttonStyle(.bordered)

            Button("Try Again") {
                discoverProfiles()
            }
            .buttonStyle(.bordered)
            .accessibilityIdentifier("first-run.discovery.retry")

            Button("Create a New Kid") {
                selectedDiscoveredProfileID = nil
                fullSetupRoute = .create
                nicknameIsFocused = true
            }
            .buttonStyle(.bordered)
            .disabled(discoveryResetMustRetry)
            .accessibilityIdentifier("first-run.discovery.create-new")
        }
        .font(.system(.subheadline, design: .rounded, weight: .bold))
    }

    private func setupRouteButton(
        title: String,
        message: String,
        symbol: String,
        accessibilityID: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            onboardingCard {
                HStack(spacing: 14) {
                    Image(systemName: symbol)
                        .font(.system(size: 28, weight: .bold))
                        .foregroundStyle(Color.white)
                        .frame(width: 58, height: 58)
                        .background(theme.primary, in: Circle())
                    VStack(alignment: .leading, spacing: 4) {
                        Text(title)
                            .font(.system(.title3, design: .rounded, weight: .black))
                        Text(message)
                            .font(.system(.subheadline, design: .rounded, weight: .medium))
                            .foregroundStyle(theme.ink.opacity(0.72))
                            .multilineTextAlignment(.leading)
                    }
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.system(.headline, weight: .black))
                        .foregroundStyle(theme.primary)
                }
            }
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier(accessibilityID)
    }

    private func discoveredProfileButton(_ profile: KidProfile) -> some View {
        let isSelected = selectedDiscoveredProfileID == profile.id
        return Button {
            selectedDiscoveredProfileID = profile.id
        } label: {
            HStack(spacing: 14) {
                OnboardingProfileAvatarArtwork(
                    avatar: profile.avatar,
                    symbolSize: 28,
                    symbolColor: isSelected ? Color.white : theme.primary
                )
                .padding(5)
                .frame(width: 60, height: 60)
                .background(
                    isSelected ? theme.primary : theme.primary.opacity(0.10),
                    in: Circle()
                )
                VStack(alignment: .leading, spacing: 3) {
                    Text(profile.displayName)
                        .font(.system(.title3, design: .rounded, weight: .black))
                    Text(profileDistinguishingLabel(profile))
                        .font(.system(.caption, design: .rounded, weight: .semibold))
                        .foregroundStyle(theme.ink.opacity(0.68))
                }
                Spacer()
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 25, weight: .bold))
                    .foregroundStyle(theme.primary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(16)
            .background(
                Color.white.opacity(isSelected ? 0.98 : 0.86),
                in: RoundedRectangle(cornerRadius: 20, style: .continuous)
            )
            .overlay {
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .strokeBorder(
                        theme.primary.opacity(isSelected ? 0.75 : 0.18),
                        lineWidth: isSelected ? 3 : 1
                    )
            }
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("first-run.discovery.profile.\(profile.id)")
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    private func profileDistinguishingLabel(_ profile: KidProfile) -> String {
        let profileCode = profile.id.description.suffix(4).uppercased()
        return
            "\(profile.schoolGrade.displayName) • \(profile.selectedWorld.displayName) • Profile \(profileCode)"
    }

    private func discoveryFailureCard(
        _ error: FirstRunProfileDiscoveryError
    ) -> some View {
        onboardingCard {
            VStack(alignment: .leading, spacing: 10) {
                Label(discoveryFailureTitle(error), systemImage: "exclamationmark.icloud.fill")
                    .font(.system(.headline, design: .rounded, weight: .bold))
                Text(discoveryFailureMessage(error))
                    .font(.system(.subheadline, design: .rounded, weight: .medium))
                    .foregroundStyle(theme.ink.opacity(0.72))
                Button("Try Again") {
                    discoverProfiles()
                }
                .buttonStyle(.bordered)
                .accessibilityIdentifier("first-run.discovery.retry")
            }
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

            if familySyncCapability == .iCloud && purpose == .fullSetup {
                VStack(alignment: .leading, spacing: 6) {
                    Button("Discard setup & find an existing profile") {
                        nicknameIsFocused = false
                        fullSetupRoute = .choose
                    }
                    .buttonStyle(.bordered)
                    .font(.system(.subheadline, design: .rounded, weight: .bold))
                    .accessibilityIdentifier("first-run.create.back-to-find")

                    Text(
                        "This unfinished profile will be removed from this device and won’t be added to iCloud."
                    )
                    .font(.system(.caption, design: .rounded, weight: .medium))
                    .foregroundStyle(theme.ink.opacity(0.68))
                }
            }

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

                        LazyVGrid(
                            columns: Array(
                                repeating: GridItem(.flexible(minimum: 0), spacing: 8),
                                count: StarterProfileAvatar.pickerColumnCount
                            ),
                            spacing: 8
                        ) {
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

                        TadaAgePicker(
                            selection: $ageYears,
                            ages: ProfileAgePolicy.supportedAges,
                            prompt: "How old is your child?",
                            tint: theme.primary
                        )

                        Text(
                            "Age helps Tada Words show suitable preset lists. School level stays under your control."
                        )
                        .font(.system(.caption, design: .rounded, weight: .medium))
                        .foregroundStyle(theme.ink.opacity(0.68))

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
                    OnboardingProfileAvatarArtwork(
                        avatar: presentationProfile.avatar,
                        symbolSize: 34,
                        symbolColor: Color.white
                    )
                    .padding(5)
                    .frame(width: 68, height: 68)
                    .background(theme.primary, in: Circle())

                    VStack(alignment: .leading, spacing: 4) {
                        Text(presentationProfile.displayName)
                            .font(.system(.title2, design: .rounded, weight: .black))
                        Text("Existing profile • \(presentationProfile.schoolGrade.displayName)")
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
        .accessibilityIdentifier("first-run.privacy-consent")
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
            VStack(spacing: 4) {
                if let imageAssetName = option.imageAssetName {
                    Image(imageAssetName)
                        .resizable()
                        .scaledToFit()
                        .clipShape(Circle())
                        .frame(width: 44, height: 44)
                } else {
                    Image(systemName: option.symbol)
                        .font(.system(size: 22, weight: .bold))
                }
                Text(option.name)
                    .font(.system(.caption2, design: .rounded, weight: .bold))
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity, minHeight: 78)
        }
        .buttonStyle(.plain)
        .foregroundStyle(avatarAssetID == option.id ? Color.white : theme.primary)
        .background(
            avatarAssetID == option.id ? theme.primary : theme.primary.opacity(0.09),
            in: RoundedRectangle(cornerRadius: 12, style: .continuous)
        )
        .accessibilityLabel(option.name)
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

    @ViewBuilder
    private var footer: some View {
        if purpose == .consentRefresh || fullSetupRoute != .choose {
            HStack {
                Text(footerNote)
                    .font(.system(.caption, design: .rounded, weight: .semibold))
                    .foregroundStyle(theme.ink.opacity(0.68))

                Spacer()

                Button {
                    finishOnboarding()
                } label: {
                    Label(footerButtonTitle, systemImage: "sparkles")
                }
                .buttonStyle(
                    TadaPrimaryButtonStyle(fill: theme.primary, isCompact: true)
                )
                .disabled(!canFinish)
                .accessibilityHint(finishAccessibilityHint)
                .accessibilityIdentifier("first-run.finish")
            }
            .padding(.horizontal, TadaPrimitiveTokens.Spacing.large)
            .padding(.vertical, 9)
            .background(Color.white.opacity(0.86))
            .overlay(alignment: .top) {
                Divider().opacity(0.35)
            }
        }
    }

    private var footerNote: String {
        if purpose == .consentRefresh {
            return "No profile data will be rewritten."
        }
        if fullSetupRoute == .discover {
            return "This keeps the exact profile and learning history."
        }
        return "Words come later in Parents."
    }

    private var footerButtonTitle: String {
        if purpose == .consentRefresh { return "Accept & Continue" }
        return fullSetupRoute == .discover ? "Use This Profile" : "Create & Play"
    }

    private var finishAccessibilityHint: String {
        if canFinish { return "" }
        if purpose == .consentRefresh {
            return "Accept the privacy summary to continue"
        }
        if fullSetupRoute == .discover {
            return "Choose a kid profile to continue"
        }
        if normalizedName.isEmpty {
            return "Enter a nickname and accept the privacy summary"
        }
        if ageYears == nil {
            return "Choose your child’s age and accept the privacy summary"
        }
        return "Accept the privacy summary to continue"
    }

    private var savingOverlay: some View {
        ZStack {
            Color.black.opacity(0.14).ignoresSafeArea()
            ProgressView(savingMessage)
                .font(.system(.headline, design: .rounded, weight: .bold))
                .padding(22)
                .background(Color.white, in: RoundedRectangle(cornerRadius: 20))
                .tint(theme.primary)
        }
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.updatesFrequently)
    }

    private var savingMessage: String {
        if discoveryState == .searching { return "Looking for your kid in iCloud…" }
        if purpose == .consentRefresh { return "Saving your privacy choice…" }
        if fullSetupRoute == .discover { return "Opening the saved profile…" }
        return "Creating \(normalizedName)’s profile…"
    }

    private func finishOnboarding() {
        guard canFinish, let submissionAction else { return }
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

    private var submissionAction: FirstRunOnboardingSubmission.Action? {
        switch purpose {
        case .fullSetup:
            switch fullSetupRoute {
            case .choose:
                nil
            case .discover:
                selectedDiscoveredProfileID.map {
                    .adoptExistingProfile($0)
                }
            case .create:
                .createProfile(
                    GuardianProfileDraft(
                        displayName: normalizedName,
                        avatar: .cartoonAnimal(assetID: avatarAssetID),
                        selectedWorld: selectedWorld,
                        schoolGrade: schoolGrade,
                        ageYears: ageYears,
                        guardianUnlockedWorlds: [selectedWorld]
                    )
                )
            }
        case .consentRefresh:
            .confirmExistingProfiles
        }
    }

    private func discoverProfiles() {
        guard hasAcceptedConsent else { return }
        // A retry may confirm a different iCloud account. Never keep the
        // previous account's candidates interactive while its cache is being
        // fenced and replaced.
        discoveredProfiles = []
        selectedDiscoveredProfileID = nil
        discoveryState = .searching
        Task { @MainActor in
            do {
                let profiles = try await onDiscoverProfiles()
                discoveredProfiles = profiles
                selectedDiscoveredProfileID =
                    profiles.count == 1
                    ? profiles.first?.id
                    : nil
                discoveryState = .results
                fullSetupRoute = .discover
            } catch let error as FirstRunProfileDiscoveryError {
                discoveryState = .failed(error)
            } catch {
                discoveryState = .failed(.failed)
            }
        }
    }

    private var discoveryResetMustRetry: Bool {
        guard case .failed(let error) = discoveryState else { return false }
        return error == .resetRequired
    }

    private func discoveryFailureTitle(
        _ error: FirstRunProfileDiscoveryError
    ) -> String {
        switch error {
        case .offline:
            "Can’t reach iCloud yet"
        case .iCloudUnavailable:
            "iCloud isn’t available"
        case .resetRequired:
            "Finish checking this device"
        case .failed:
            "Couldn’t check iCloud"
        }
    }

    private func discoveryFailureMessage(
        _ error: FirstRunProfileDiscoveryError
    ) -> String {
        switch error {
        case .offline:
            "Your local data is safe. Check the connection and try again, or explicitly create a new kid."
        case .iCloudUnavailable:
            "Sign in to iCloud, then try again. You can still explicitly create a new kid offline."
        case .resetRequired:
            "Try Find again before creating or opening a profile. This keeps another iCloud account’s data separate."
        case .failed:
            "No new profile was created. Try again, or explicitly create a new kid."
        }
    }

    private static func message(for error: any Error) -> String {
        switch error {
        case FirstRunOnboardingError.emptyDisplayName:
            "Enter a nickname, then try again."
        case FirstRunOnboardingError.displayNameTooLong(let maximum):
            "Use a nickname with \(maximum) characters or fewer."
        case FirstRunOnboardingError.invalidAge:
            "Choose your child’s age, then try again."
        case FirstRunOnboardingRepositoryError.discoveryResetRequired:
            "Tap Find my kid again before creating or opening a profile."
        default:
            "Your child’s setup is still here. Check that storage is available, then try again."
        }
    }
}

private struct OnboardingProfileAvatarArtwork: View {
    let avatar: ProfileAvatar
    let symbolSize: CGFloat
    let symbolColor: Color

    var body: some View {
        Group {
            if let imageAssetName = avatar.starterProfileAvatar?.imageAssetName {
                Image(imageAssetName)
                    .resizable()
                    .scaledToFit()
                    .clipShape(Circle())
            } else {
                Image(systemName: avatar.onboardingSymbol)
                    .font(.system(size: symbolSize, weight: .bold))
                    .foregroundStyle(symbolColor)
            }
        }
        .accessibilityHidden(true)
    }
}

extension ProfileAvatar {
    fileprivate var cartoonAnimalAssetID: String? {
        guard case .cartoonAnimal(let assetID) = self else { return nil }
        return assetID
    }

    fileprivate var onboardingSymbol: String {
        guard cartoonAnimalAssetID != nil else {
            return "person.crop.circle.fill"
        }
        return starterProfileAvatar?.fallbackSystemImageName ?? "pawprint.fill"
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
            "truck.box.fill"
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
