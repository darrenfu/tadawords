import SwiftUI
import TadaWordsDesignSystem
import TadaWordsDomain

#if os(iOS)
    import UIKit
#endif

struct ProfileChooserView: View {
    let profiles: [KidProfile]
    let lastPlayedProfileID: ProfileID?
    let onSelect: (KidProfile) -> Void
    let onCreateProfile: (String, Int?) async -> Bool
    let isCreatingProfile: Bool
    let creationError: String?
    let onDismissCreationError: () -> Void
    let onOpenGuardian: () -> Void

    @Environment(\.verticalSizeClass) private var verticalSizeClass
    @State private var isNewPlayerPresented = false

    private let grid = [
        GridItem(.adaptive(minimum: 172, maximum: 220), spacing: 18)
    ]

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [
                    TadaPrimitiveTokens.ColorValue.neutralSky,
                    TadaPrimitiveTokens.ColorValue.neutralPeach,
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()

            Circle()
                .fill(Color.white.opacity(0.42))
                .frame(width: 360)
                .blur(radius: 2)
                .offset(x: 310, y: -180)
                .accessibilityHidden(true)

            ProfileWorldBackdrop()
                .accessibilityHidden(true)

            switch ProfileChooserLayoutMode.resolve(
                hasCompactHeight: verticalSizeClass == .compact
            ) {
            case .standard:
                standardContent
            case .compactLandscape:
                compactLandscapeContent
            }
        }
        .sheet(isPresented: $isNewPlayerPresented) {
            NewPlayerView(
                isSaving: isCreatingProfile,
                errorMessage: creationError,
                onSubmit: onCreateProfile,
                onDismissError: onDismissCreationError,
                onClose: { isNewPlayerPresented = false }
            )
            .interactiveDismissDisabled(isCreatingProfile)
        }
    }

    private var standardContent: some View {
        ScrollView {
            VStack(spacing: TadaPrimitiveTokens.Spacing.large) {
                HStack {
                    Spacer()
                    guardianButton
                }
                .frame(maxWidth: 760)

                brand
                prompt

                LazyVGrid(columns: grid, spacing: 18) {
                    ForEach(profiles, id: \.id) { profile in
                        ProfileCard(
                            profile: profile,
                            density: .standard,
                            isLastPlayed: ProfileChooserPresentation.isLastPlayed(
                                profile.id,
                                rememberedProfileID: lastPlayedProfileID
                            )
                        ) {
                            onSelect(profile)
                        }
                    }
                    NewPlayerCard(isCompact: false) {
                        presentNewPlayer()
                    }
                }
                .frame(maxWidth: 760)
            }
            .frame(maxWidth: .infinity)
            .padding(.horizontal, TadaPrimitiveTokens.Spacing.large)
            .padding(.vertical, TadaPrimitiveTokens.Spacing.xLarge)
        }
    }

    private var compactLandscapeContent: some View {
        VStack(spacing: TadaPrimitiveTokens.Spacing.medium) {
            HStack(spacing: TadaPrimitiveTokens.Spacing.large) {
                brand

                Spacer(minLength: TadaPrimitiveTokens.Spacing.medium)

                prompt

                Spacer(minLength: TadaPrimitiveTokens.Spacing.medium)

                guardianButton
            }

            ViewThatFits(in: .horizontal) {
                HStack(spacing: 18) {
                    compactProfileCards
                    NewPlayerCard(isCompact: true) {
                        presentNewPlayer()
                    }
                }
                .frame(maxWidth: 760)

                VStack(spacing: TadaPrimitiveTokens.Spacing.small) {
                    ScrollView(.horizontal) {
                        LazyHStack(spacing: 18) {
                            compactProfileCards
                            NewPlayerCard(isCompact: true) {
                                presentNewPlayer()
                            }
                        }
                        .padding(.horizontal, TadaPrimitiveTokens.Spacing.small)
                    }
                    .scrollIndicators(.visible)

                    Image(systemName: "arrow.left.and.right")
                        .font(.system(.caption, design: .rounded, weight: .bold))
                        .foregroundStyle(TadaPrimitiveTokens.ColorValue.softInk)
                        .accessibilityLabel("Swipe to see more kids")
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .padding(.horizontal, TadaPrimitiveTokens.Spacing.large)
        .padding(.vertical, TadaPrimitiveTokens.Spacing.medium)
    }

    @ViewBuilder
    private var compactProfileCards: some View {
        ForEach(profiles, id: \.id) { profile in
            ProfileCard(
                profile: profile,
                density: .compact,
                isLastPlayed: ProfileChooserPresentation.isLastPlayed(
                    profile.id,
                    rememberedProfileID: lastPlayedProfileID
                )
            ) {
                onSelect(profile)
            }
        }
    }

    private var prompt: some View {
        Text("Who’s playing?")
            .font(.system(.largeTitle, design: .rounded, weight: .bold))
            .foregroundStyle(TadaPrimitiveTokens.ColorValue.ink)
            .multilineTextAlignment(.center)
    }

    private var guardianButton: some View {
        Button(action: onOpenGuardian) {
            Label("Parents", systemImage: "lock.fill")
                .font(.system(.subheadline, design: .rounded, weight: .bold))
                .padding(.horizontal, TadaPrimitiveTokens.Spacing.medium)
                .frame(minHeight: TadaPrimitiveTokens.TouchTarget.minimum)
                .background(
                    Color.white.opacity(0.84),
                    in: Capsule(style: .continuous)
                )
                .foregroundStyle(TadaPrimitiveTokens.ColorValue.ink)
                .contentShape(Capsule(style: .continuous))
        }
        .buttonStyle(.plain)
        .frame(minHeight: TadaPrimitiveTokens.TouchTarget.minimum)
        .accessibilityLabel("Parents")
        .accessibilityHint("Opens the Parent Gate")
        .accessibilityIdentifier("profile-chooser.grown-ups")
    }

    private var brand: some View {
        HStack(spacing: 11) {
            ZStack {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [
                                TadaWorldTheme.moonpetal.primary, TadaWorldTheme.buildItBay.primary,
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                Image(systemName: "sparkles")
                    .font(.system(size: 25, weight: .bold))
                    .foregroundStyle(Color.white)
            }
            .frame(width: 52, height: 52)
            .accessibilityHidden(true)

            Text("Tada Words")
                .font(.system(.title, design: .rounded, weight: .heavy))
                .foregroundStyle(TadaPrimitiveTokens.ColorValue.ink)
        }
        .accessibilityElement(children: .combine)
    }

    private func presentNewPlayer() {
        onDismissCreationError()
        isNewPlayerPresented = true
    }
}

enum ProfileChooserLayoutMode: Equatable {
    case standard
    case compactLandscape

    static func resolve(hasCompactHeight: Bool) -> ProfileChooserLayoutMode {
        hasCompactHeight ? .compactLandscape : .standard
    }
}

enum ProfileChooserPresentation {
    static func isLastPlayed(
        _ profileID: ProfileID,
        rememberedProfileID: ProfileID?
    ) -> Bool {
        profileID == rememberedProfileID
    }

    static func cardScale(isLastPlayed: Bool) -> CGFloat {
        isLastPlayed ? TadaChildScaleTokens.Profile.lastPlayedScale : 1
    }

    static func cardZIndex(isLastPlayed: Bool) -> Double {
        isLastPlayed ? 1 : 0
    }
}

private struct ProfileCard: View {
    enum Density {
        case standard
        case compact
    }

    let profile: KidProfile
    let density: Density
    let isLastPlayed: Bool
    let action: () -> Void

    private var theme: TadaWorldTheme {
        .from(profile.selectedWorld)
    }

    var body: some View {
        Button(action: action) {
            VStack(spacing: density == .compact ? 8 : 13) {
                ZStack {
                    Circle()
                        .fill(
                            LinearGradient(
                                colors: [theme.secondary, theme.accent],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                    Circle()
                        .strokeBorder(Color.white.opacity(0.82), lineWidth: 4)
                        .padding(6)
                    ProfileAvatarContent(
                        avatar: profile.displayAvatar,
                        symbolSize: density == .compact ? 42 : 54
                    )
                    .clipShape(Circle())
                    .padding(10)
                }
                .frame(
                    width: density == .compact ? 84 : 112,
                    height: density == .compact ? 84 : 112
                )

                Text(profile.displayName)
                    .font(
                        .system(
                            density == .compact ? .title3 : .title2,
                            design: .rounded,
                            weight: .bold
                        )
                    )
                    .foregroundStyle(theme.ink)
                    .lineLimit(1)

            }
            .frame(
                minWidth: density == .compact ? 172 : nil,
                maxWidth: density == .compact ? 220 : .infinity
            )
            .padding(.horizontal, 16)
            .padding(.vertical, density == .compact ? 12 : 20)
            .background(
                LinearGradient(
                    colors: [Color.white.opacity(0.92), theme.backgroundTop.opacity(0.90)],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                ),
                in: RoundedRectangle(
                    cornerRadius: TadaPrimitiveTokens.Radius.large,
                    style: .continuous
                )
            )
            .overlay {
                RoundedRectangle(
                    cornerRadius: TadaPrimitiveTokens.Radius.large,
                    style: .continuous
                )
                .strokeBorder(
                    isLastPlayed ? theme.primary : Color.white.opacity(0.76),
                    lineWidth: isLastPlayed ? 4 : 2
                )
            }
            .overlay(alignment: .bottom) {
                Capsule()
                    .fill(theme.primary.opacity(0.42))
                    .frame(height: TadaPrimitiveTokens.Depth.tactileLip)
                    .padding(.horizontal, TadaPrimitiveTokens.Spacing.large)
                    .offset(y: TadaPrimitiveTokens.Depth.tactileLip * 0.40)
            }
            .overlay(alignment: .topTrailing) {
                Image(systemName: isLastPlayed ? "sparkles" : theme.motifSymbol)
                    .font(.system(size: 18, weight: .heavy))
                    .foregroundStyle(theme.primary)
                    .frame(width: 36, height: 36)
                    .background(Color.white.opacity(0.94), in: Circle())
                    .padding(10)
                    .accessibilityHidden(true)
            }
            .shadow(color: theme.primary.opacity(0.16), radius: 18, y: 9)
        }
        .buttonStyle(TadaTactileCardButtonStyle())
        .scaleEffect(ProfileChooserPresentation.cardScale(isLastPlayed: isLastPlayed))
        .zIndex(ProfileChooserPresentation.cardZIndex(isLastPlayed: isLastPlayed))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityLabel)
        .accessibilityHint("Opens today’s Read and Write quests")
    }

    private var accessibilityLabel: String {
        let base = "Play as \(profile.displayName) in \(theme.name)"
        return isLastPlayed ? "\(base), last played" : base
    }
}

struct ProfileAvatarContent: View {
    let avatar: ProfileAvatar
    let symbolSize: CGFloat

    var body: some View {
        Group {
            #if os(iOS)
                if let data = avatar.embeddedPhotoData,
                    let image = UIImage(data: data)
                {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFill()
                } else {
                    fallback
                }
            #else
                fallback
            #endif
        }
        .accessibilityHidden(true)
    }

    private var fallback: some View {
        Image(systemName: avatar.presentationSymbol)
            .font(.system(size: symbolSize, weight: .bold))
            .foregroundStyle(Color.white)
    }
}

private struct ProfileWorldBackdrop: View {
    var body: some View {
        GeometryReader { proxy in
            TadaWorldMascot(theme: .moonpetal, size: min(120, proxy.size.height * 0.18))
                .position(x: proxy.size.width * 0.08, y: proxy.size.height * 0.82)
                .opacity(0.14)

            TadaWorldMascot(theme: .buildItBay, size: min(124, proxy.size.height * 0.19))
                .position(x: proxy.size.width * 0.90, y: proxy.size.height * 0.50)
                .opacity(0.12)

            TadaWorldMascot(theme: .pawsAndPines, size: min(112, proxy.size.height * 0.17))
                .position(x: proxy.size.width * 0.18, y: proxy.size.height * 0.22)
                .opacity(0.11)
        }
        .allowsHitTesting(false)
    }
}

private struct NewPlayerCard: View {
    let isCompact: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: isCompact ? 8 : 13) {
                ZStack {
                    Circle()
                        .fill(
                            LinearGradient(
                                colors: [
                                    TadaWorldTheme.pawsAndPines.secondary,
                                    TadaWorldTheme.moonpetal.accent,
                                ],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                    Circle()
                        .strokeBorder(Color.white.opacity(0.82), lineWidth: 4)
                        .padding(6)
                    Image(systemName: "plus")
                        .font(.system(size: isCompact ? 38 : 48, weight: .heavy))
                        .foregroundStyle(Color.white)
                }
                .frame(
                    width: isCompact ? 84 : 112,
                    height: isCompact ? 84 : 112
                )

                Text("New Kid")
                    .font(
                        .system(
                            isCompact ? .title3 : .title2,
                            design: .rounded,
                            weight: .bold
                        )
                    )
                    .foregroundStyle(TadaPrimitiveTokens.ColorValue.ink)
                    .lineLimit(1)

            }
            .frame(
                minWidth: isCompact ? 172 : nil,
                maxWidth: isCompact ? 220 : .infinity
            )
            .padding(.horizontal, 16)
            .padding(.vertical, isCompact ? 12 : 20)
            .background(
                Color.white.opacity(0.88),
                in: RoundedRectangle(
                    cornerRadius: TadaPrimitiveTokens.Radius.large,
                    style: .continuous
                )
            )
            .overlay {
                RoundedRectangle(
                    cornerRadius: TadaPrimitiveTokens.Radius.large,
                    style: .continuous
                )
                .strokeBorder(
                    TadaWorldTheme.pawsAndPines.primary.opacity(0.34),
                    style: StrokeStyle(lineWidth: 2, dash: [8, 6])
                )
            }
            .shadow(
                color: TadaWorldTheme.pawsAndPines.primary.opacity(0.13),
                radius: 18,
                y: 9
            )
        }
        .buttonStyle(TadaTactileCardButtonStyle())
        .accessibilityLabel("Create a new kid profile")
        .accessibilityHint("Enter a nickname and age, then get a surprise animal")
    }
}

private struct NewPlayerView: View {
    let isSaving: Bool
    let errorMessage: String?
    let onSubmit: (String, Int?) async -> Bool
    let onDismissError: () -> Void
    let onClose: () -> Void

    @State private var nickname = ""
    @State private var ageYears: Int?
    @FocusState private var isNicknameFocused: Bool
    @Environment(\.verticalSizeClass) private var verticalSizeClass

    private var cleanedNickname: String {
        nickname.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [
                    TadaPrimitiveTokens.ColorValue.neutralSky,
                    TadaPrimitiveTokens.ColorValue.neutralPeach,
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()

            GeometryReader { proxy in
                ScrollView {
                    HStack(spacing: TadaPrimitiveTokens.Spacing.xLarge) {
                        if layoutMode == .standard {
                            surpriseAnimal
                        }
                        form
                    }
                    .padding(layoutMode == .compactLandscape ? 16 : 32)
                    .frame(maxWidth: 820)
                    .frame(
                        maxWidth: .infinity,
                        minHeight: proxy.size.height,
                        alignment: .center
                    )
                }
                .scrollDismissesKeyboard(.interactively)
            }
        }
        .onAppear {
            isNicknameFocused = true
        }
        .onChange(of: errorMessage) { _, message in
            #if os(iOS)
                guard let message else { return }
                UIAccessibility.post(
                    notification: .announcement,
                    argument: message
                )
            #endif
        }
    }

    private var layoutMode: NewPlayerLayoutMode {
        .resolve(hasCompactHeight: verticalSizeClass == .compact)
    }

    private var form: some View {
        VStack(alignment: .leading, spacing: TadaPrimitiveTokens.Spacing.medium) {
            HStack {
                Text("Make Your Profile!")
                    .font(
                        .system(
                            layoutMode == .compactLandscape ? .title : .largeTitle,
                            design: .rounded,
                            weight: .heavy
                        )
                    )
                    .foregroundStyle(TadaPrimitiveTokens.ColorValue.ink)
                Spacer()
                Button(action: onClose) {
                    Image(systemName: "xmark")
                        .font(.system(size: 18, weight: .bold))
                        .frame(width: 44, height: 44)
                }
                .buttonStyle(.bordered)
                .disabled(isSaving)
                .accessibilityLabel("Close")
            }

            Text("What's your nickname?")
                .font(
                    .system(
                        layoutMode == .compactLandscape ? .title3 : .title2,
                        design: .rounded,
                        weight: .bold
                    )
                )
                .foregroundStyle(TadaPrimitiveTokens.ColorValue.softInk)

            TextField("My nickname", text: $nickname)
                .font(.system(.title2, design: .rounded, weight: .bold))
                .textFieldStyle(.plain)
                .modifier(NicknameInputPlatformModifier())
                .focused($isNicknameFocused)
                .padding(.horizontal, 20)
                .frame(height: layoutMode == .compactLandscape ? 54 : 62)
                .background(
                    Color.white.opacity(0.94),
                    in: RoundedRectangle(cornerRadius: 20, style: .continuous)
                )
                .overlay {
                    RoundedRectangle(cornerRadius: 20, style: .continuous)
                        .strokeBorder(
                            TadaWorldTheme.pawsAndPines.primary.opacity(0.45),
                            lineWidth: 3
                        )
                }
                .onSubmit(submit)
                .onChange(of: nickname) { _, _ in
                    onDismissError()
                }

            TadaAgePicker(
                selection: $ageYears,
                ages: ProfileAgePolicy.supportedAges,
                prompt: "How old are you?",
                tint: TadaWorldTheme.pawsAndPines.primary
            )

            if let ageYears,
                let suggestedGrade = ProfileAgePolicy.suggestedSchoolGrade(
                    for: ageYears
                )
            {
                Text(
                    "We’ll start at \(suggestedGrade.displayName). A parent can change your learning level later."
                )
                .font(.system(.caption, design: .rounded, weight: .semibold))
                .foregroundStyle(TadaPrimitiveTokens.ColorValue.softInk)
            }

            if let errorMessage {
                TadaInlineError(errorMessage)
            } else {
                Text("You'll get a surprise animal buddy!")
                    .font(.system(.subheadline, design: .rounded, weight: .semibold))
                    .foregroundStyle(TadaPrimitiveTokens.ColorValue.softInk)
            }

            Button(action: submit) {
                HStack(spacing: 10) {
                    if isSaving {
                        ProgressView()
                            .tint(.white)
                    } else {
                        Image(systemName: "sparkles")
                    }
                    Text(isSaving ? "Making your profile…" : "Let's Play!")
                }
                .font(.system(.title3, design: .rounded, weight: .heavy))
                .frame(maxWidth: .infinity)
            }
            .buttonStyle(
                TadaPrimaryButtonStyle(
                    fill: TadaWorldTheme.pawsAndPines.primary,
                    foreground: .white
                )
            )
            .disabled(
                cleanedNickname.isEmpty
                    || ageYears == nil
                    || isSaving
            )
            .accessibilityHint(
                ageYears == nil
                    ? "Choose your age before creating the profile"
                    : "Creates this kid profile"
            )
        }
        .frame(maxWidth: layoutMode == .compactLandscape ? 560 : 470)
    }

    private var surpriseAnimal: some View {
        VStack(spacing: 14) {
            ZStack {
                Circle()
                    .fill(
                        LinearGradient(
                            colors: [
                                TadaWorldTheme.pawsAndPines.secondary,
                                TadaWorldTheme.moonpetal.accent,
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                Image(systemName: "pawprint.fill")
                    .font(.system(size: 72, weight: .bold))
                    .foregroundStyle(.white)
                Image(systemName: "sparkles")
                    .font(.system(size: 28, weight: .bold))
                    .foregroundStyle(TadaWorldTheme.moonpetal.primary)
                    .offset(x: 70, y: -66)
            }
            .frame(width: 190, height: 190)

            Text("Surprise Buddy")
                .font(.system(.title3, design: .rounded, weight: .heavy))
                .foregroundStyle(TadaPrimitiveTokens.ColorValue.ink)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("A surprise animal buddy")
    }

    private func submit() {
        guard !cleanedNickname.isEmpty, let ageYears, !isSaving else { return }
        Task {
            if await onSubmit(cleanedNickname, ageYears) {
                onClose()
            }
        }
    }
}

enum NewPlayerLayoutMode: Equatable {
    case standard
    case compactLandscape

    static func resolve(hasCompactHeight: Bool) -> NewPlayerLayoutMode {
        hasCompactHeight ? .compactLandscape : .standard
    }
}

private struct NicknameInputPlatformModifier: ViewModifier {
    @ViewBuilder
    func body(content: Content) -> some View {
        #if os(iOS)
            content
                .textInputAutocapitalization(.words)
                .autocorrectionDisabled()
                .submitLabel(.done)
        #else
            content
        #endif
    }
}
