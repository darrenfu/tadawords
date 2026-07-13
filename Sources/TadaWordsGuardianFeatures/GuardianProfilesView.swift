import SwiftUI
import TadaWordsDomain

#if os(iOS)
    import PhotosUI
    import UIKit
#endif

struct GuardianProfilesView: View {
    let family: GuardianFamilySnapshot
    let onBack: () -> Void
    let onSelect: (KidProfile) -> Void
    let onEdit: (KidProfile) -> Void
    let onVoiceprint: (KidProfile) -> Void
    let onAdd: () -> Void

    private let columns = [
        GridItem(.adaptive(minimum: 280), spacing: GuardianPrimitiveTokens.Spacing.medium)
    ]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: GuardianPrimitiveTokens.Spacing.large) {
                GuardianNavigationHeader(title: "Child profiles", onBack: onBack)

                Text("Choose whose words and practice settings you want to manage.")
                    .font(.system(.body, design: .rounded, weight: .medium))
                    .foregroundStyle(GuardianSemanticTokens.secondaryForeground)

                LazyVGrid(columns: columns, spacing: GuardianPrimitiveTokens.Spacing.medium) {
                    ForEach(family.profiles, id: \.id) { profile in
                        GuardianProfileManagementCard(
                            profile: profile,
                            isSelected: profile.id == family.selectedProfileID,
                            onSelect: { onSelect(profile) },
                            onEdit: { onEdit(profile) },
                            onVoiceprint: { onVoiceprint(profile) }
                        )
                    }
                }

                Button(action: onAdd) {
                    Label("Add a child", systemImage: "person.crop.circle.badge.plus")
                }
                .buttonStyle(GuardianPrimaryButtonStyle())
            }
            .frame(maxWidth: 960, alignment: .leading)
            .padding(.horizontal, GuardianPrimitiveTokens.Spacing.medium)
            .padding(.vertical, GuardianPrimitiveTokens.Spacing.large)
            .frame(maxWidth: .infinity)
        }
        .scrollIndicators(.hidden)
    }
}

private struct GuardianProfileManagementCard: View {
    let profile: KidProfile
    let isSelected: Bool
    let onSelect: () -> Void
    let onEdit: () -> Void
    let onVoiceprint: () -> Void

    var body: some View {
        GuardianCard {
            VStack(alignment: .leading, spacing: GuardianPrimitiveTokens.Spacing.medium) {
                HStack(spacing: GuardianPrimitiveTokens.Spacing.medium) {
                    ZStack {
                        Circle()
                            .fill(GuardianSemanticTokens.primary.opacity(0.12))
                        GuardianProfileAvatarView(avatar: profile.avatar)
                            .padding(7)
                    }
                    .frame(width: 64, height: 64)
                    .accessibilityHidden(true)

                    VStack(alignment: .leading, spacing: 3) {
                        Text(profile.displayName)
                            .font(.system(.title3, design: .rounded, weight: .bold))
                            .lineLimit(1)
                        Text(profile.selectedWorld.displayName)
                            .font(.system(.subheadline, design: .rounded, weight: .medium))
                            .foregroundStyle(GuardianSemanticTokens.secondaryForeground)
                            .lineLimit(2)
                    }

                    Spacer()

                    if isSelected {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.system(.title2, design: .rounded, weight: .bold))
                            .foregroundStyle(GuardianSemanticTokens.success)
                            .accessibilityLabel("Currently selected")
                    }
                }

                HStack(spacing: GuardianPrimitiveTokens.Spacing.small) {
                    Button(isSelected ? "Selected" : "Manage", action: onSelect)
                        .buttonStyle(.borderedProminent)
                        .disabled(isSelected)
                    Button("Edit", action: onEdit)
                        .buttonStyle(.bordered)
                    Button(action: onVoiceprint) {
                        Label(voiceprintTitle, systemImage: "waveform.badge.mic")
                    }
                    .buttonStyle(.bordered)
                }
                .controlSize(.large)
            }
        }
    }

    private var voiceprintTitle: String {
        switch profile.voiceprintStatus {
        case .notEnrolled:
            "Set up voice"
        case .enrolled:
            "Voice ready"
        case .needsRefresh:
            "Refresh voice"
        }
    }
}

struct GuardianProfileEditorView: View {
    let existingProfile: KidProfile?
    let onBack: () -> Void
    let onSave: (GuardianProfileDraft) -> Void
    let onDelete: (() -> Void)?

    @State private var displayName: String
    @State private var avatar: ProfileAvatar
    @State private var selectedWorld: WorldTheme
    @State private var schoolGrade: ProfileSchoolGrade
    @State private var ageYears: Int
    @State private var guardianUnlockedWorlds: Set<WorldTheme>
    @State private var confirmsDeletion = false
    #if os(iOS)
        @State private var selectedPhotoItem: PhotosPickerItem?
        @State private var isCameraPresented = false
    #endif

    init(
        existingProfile: KidProfile?,
        onBack: @escaping () -> Void,
        onSave: @escaping (GuardianProfileDraft) -> Void,
        onDelete: (() -> Void)? = nil
    ) {
        self.existingProfile = existingProfile
        self.onBack = onBack
        self.onSave = onSave
        self.onDelete = onDelete
        _displayName = State(initialValue: existingProfile?.displayName ?? "")
        _avatar = State(
            initialValue: existingProfile?.avatar ?? .cartoonAnimal(assetID: "hare")
        )
        _selectedWorld = State(
            initialValue: existingProfile?.selectedWorld ?? .moonpetalKingdom
        )
        _schoolGrade = State(initialValue: existingProfile?.schoolGrade ?? .preK)
        _ageYears = State(initialValue: existingProfile?.ageYears ?? 4)
        _guardianUnlockedWorlds = State(
            initialValue: existingProfile?.guardianUnlockedWorlds ?? []
        )
    }

    private var normalizedName: String {
        displayName.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: GuardianPrimitiveTokens.Spacing.large) {
                GuardianNavigationHeader(
                    title: existingProfile == nil ? "Add a child" : "Edit profile",
                    onBack: onBack
                )

                GuardianCard {
                    VStack(alignment: .leading, spacing: GuardianPrimitiveTokens.Spacing.medium) {
                        Text("Nickname")
                            .font(.system(.headline, design: .rounded, weight: .bold))
                        TextField("Child’s nickname", text: $displayName)
                            .textFieldStyle(.roundedBorder)
                        Text(
                            "Up to \(RepositoryGuardianFamilyStore.maximumDisplayNameCharacterCount) characters"
                        )
                        .font(.system(.caption, design: .rounded, weight: .medium))
                        .foregroundStyle(GuardianSemanticTokens.secondaryForeground)
                    }
                }

                avatarSection
                learningLevelSection
                worldSection

                Button(action: save) {
                    Label(
                        existingProfile == nil ? "Create profile" : "Save changes",
                        systemImage: "checkmark.circle.fill"
                    )
                }
                .buttonStyle(GuardianPrimaryButtonStyle())
                .disabled(
                    normalizedName.isEmpty
                        || normalizedName.count
                            > RepositoryGuardianFamilyStore.maximumDisplayNameCharacterCount
                )

                if existingProfile != nil {
                    deletionSection
                }
            }
            .frame(maxWidth: 760, alignment: .leading)
            .padding(.horizontal, GuardianPrimitiveTokens.Spacing.medium)
            .padding(.vertical, GuardianPrimitiveTokens.Spacing.large)
            .frame(maxWidth: .infinity)
        }
        .scrollDismissesKeyboard(.interactively)
        .scrollIndicators(.hidden)
        .alert("Delete this profile?", isPresented: $confirmsDeletion) {
            Button("Cancel", role: .cancel) {}
            Button("Delete profile", role: .destructive) {
                onDelete?()
            }
        } message: {
            Text(
                "Words, settings, quest history, rewards, and learning records for this child will be removed from this device."
            )
        }
        #if os(iOS)
            .fullScreenCover(isPresented: $isCameraPresented) {
                GuardianCameraPicker { data in
                    avatar = .embeddedPhoto(data: data, source: .camera)
                    isCameraPresented = false
                } onCancel: {
                    isCameraPresented = false
                }
            }
        #endif
    }

    private var avatarSection: some View {
        VStack(alignment: .leading, spacing: GuardianPrimitiveTokens.Spacing.medium) {
            Text("Picture")
                .font(.system(.title3, design: .rounded, weight: .bold))

            HStack(spacing: GuardianPrimitiveTokens.Spacing.medium) {
                GuardianProfileAvatarView(avatar: avatar)
                    .frame(width: 84, height: 84)
                    .clipShape(Circle())

                #if os(iOS)
                    PhotosPicker(selection: $selectedPhotoItem, matching: .images) {
                        Label("Photo Library", systemImage: "photo.on.rectangle")
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.large)
                    .onChange(of: selectedPhotoItem) { _, item in
                        guard let item else { return }
                        Task {
                            guard let data = try? await item.loadTransferable(type: Data.self),
                                let prepared = ProfilePhotoPreparation.prepare(data)
                            else { return }
                            avatar = .embeddedPhoto(
                                data: prepared,
                                source: .photoLibrary
                            )
                        }
                    }

                    Button {
                        isCameraPresented = true
                    } label: {
                        Label("Camera", systemImage: "camera.fill")
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.large)
                    .disabled(!UIImagePickerController.isSourceTypeAvailable(.camera))
                #endif
            }

            Text("Or choose an animal icon")
                .font(.system(.subheadline, design: .rounded, weight: .semibold))
                .foregroundStyle(GuardianSemanticTokens.secondaryForeground)

            LazyVGrid(
                columns: [GridItem(.adaptive(minimum: 92))],
                spacing: GuardianPrimitiveTokens.Spacing.small
            ) {
                ForEach(GuardianAnimalAvatar.available) { avatar in
                    Button {
                        self.avatar = .cartoonAnimal(assetID: avatar.id)
                    } label: {
                        VStack(spacing: 7) {
                            Image(systemName: avatar.symbol)
                                .font(.system(size: 28, weight: .bold))
                            Text(avatar.name)
                                .font(.system(.caption, design: .rounded, weight: .bold))
                        }
                        .frame(maxWidth: .infinity, minHeight: 76)
                    }
                    .buttonStyle(.bordered)
                    .tint(
                        self.avatar.cartoonAnimalAssetID == avatar.id
                            ? GuardianSemanticTokens.primary
                            : GuardianSemanticTokens.secondaryForeground
                    )
                    .accessibilityAddTraits(
                        self.avatar.cartoonAnimalAssetID == avatar.id ? .isSelected : []
                    )
                }
            }
        }
    }

    private var learningLevelSection: some View {
        GuardianCard {
            VStack(alignment: .leading, spacing: GuardianPrimitiveTokens.Spacing.medium) {
                Text("Learning level")
                    .font(.system(.title3, design: .rounded, weight: .bold))
                Picker("Grade", selection: $schoolGrade) {
                    ForEach(ProfileSchoolGrade.allCases, id: \.self) { grade in
                        Text(grade.displayName).tag(grade)
                    }
                }
                .pickerStyle(.menu)
                Stepper("Age \(ageYears)", value: $ageYears, in: 2...18)
                    .font(.system(.headline, design: .rounded, weight: .semibold))
            }
        }
    }

    private var worldSection: some View {
        VStack(alignment: .leading, spacing: GuardianPrimitiveTokens.Spacing.medium) {
            Text("World theme")
                .font(.system(.title3, design: .rounded, weight: .bold))

            ForEach(WorldTheme.allCases, id: \.self) { world in
                Button {
                    selectedWorld = world
                    guardianUnlockedWorlds.insert(world)
                } label: {
                    HStack {
                        Image(systemName: world.guardianSymbol)
                            .frame(width: 28)
                        Text(world.displayName)
                            .font(.system(.headline, design: .rounded, weight: .semibold))
                        Spacer()
                        Image(
                            systemName: selectedWorld == world
                                ? "checkmark.circle.fill"
                                : "circle"
                        )
                    }
                    .padding(GuardianPrimitiveTokens.Spacing.medium)
                    .background(
                        GuardianSemanticTokens.surface,
                        in: RoundedRectangle(
                            cornerRadius: GuardianPrimitiveTokens.Radius.medium,
                            style: .continuous
                        )
                    )
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(selectedWorld == world ? .isSelected : [])
            }

            Text("Guardian unlocks")
                .font(.system(.subheadline, design: .rounded, weight: .bold))
            ForEach(WorldTheme.allCases, id: \.self) { world in
                Toggle(
                    world.displayName,
                    isOn: Binding(
                        get: {
                            world == existingProfile?.starterWorld
                                || guardianUnlockedWorlds.contains(world)
                        },
                        set: { isUnlocked in
                            guard world != existingProfile?.starterWorld else { return }
                            if isUnlocked {
                                guardianUnlockedWorlds.insert(world)
                            } else {
                                guardianUnlockedWorlds.remove(world)
                            }
                        }
                    )
                )
                .disabled(world == existingProfile?.starterWorld)
            }
        }
    }

    private var deletionSection: some View {
        VStack(alignment: .leading, spacing: GuardianPrimitiveTokens.Spacing.small) {
            Button("Delete profile", role: .destructive) {
                confirmsDeletion = true
            }
            .buttonStyle(.bordered)
            Text(
                "Deletes this child’s related local data together. At least one profile must remain."
            )
            .font(.system(.caption, design: .rounded, weight: .medium))
            .foregroundStyle(GuardianSemanticTokens.secondaryForeground)
        }
    }

    private func save() {
        onSave(
            GuardianProfileDraft(
                displayName: normalizedName,
                avatar: avatar,
                selectedWorld: selectedWorld,
                schoolGrade: schoolGrade,
                ageYears: ageYears,
                guardianUnlockedWorlds: guardianUnlockedWorlds
            )
        )
    }
}

struct GuardianProfileAvatarView: View {
    let avatar: ProfileAvatar

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
        Image(systemName: avatar.guardianPresentationSymbol)
            .resizable()
            .scaledToFit()
            .foregroundStyle(GuardianSemanticTokens.primary)
            .padding(8)
    }
}

extension ProfileAvatar {
    var cartoonAnimalAssetID: String? {
        guard case .cartoonAnimal(let assetID) = self else { return nil }
        return assetID
    }

}

#if os(iOS)
    private enum ProfilePhotoPreparation {
        static func prepare(_ data: Data) -> Data? {
            guard let image = UIImage(data: data) else { return nil }
            let maximumDimension: CGFloat = 512
            let scale = min(1, maximumDimension / max(image.size.width, image.size.height))
            let size = CGSize(
                width: max(1, image.size.width * scale),
                height: max(1, image.size.height * scale)
            )
            let renderer = UIGraphicsImageRenderer(size: size)
            let resized = renderer.image { _ in
                image.draw(in: CGRect(origin: .zero, size: size))
            }
            return resized.jpegData(compressionQuality: 0.78)
        }
    }

    private struct GuardianCameraPicker: UIViewControllerRepresentable {
        let onImage: (Data) -> Void
        let onCancel: () -> Void

        func makeCoordinator() -> Coordinator {
            Coordinator(onImage: onImage, onCancel: onCancel)
        }

        func makeUIViewController(context: Context) -> UIImagePickerController {
            let controller = UIImagePickerController()
            controller.sourceType = .camera
            controller.cameraCaptureMode = .photo
            controller.delegate = context.coordinator
            return controller
        }

        func updateUIViewController(
            _ uiViewController: UIImagePickerController,
            context: Context
        ) {}

        final class Coordinator: NSObject, UINavigationControllerDelegate,
            UIImagePickerControllerDelegate
        {
            let onImage: (Data) -> Void
            let onCancel: () -> Void

            init(onImage: @escaping (Data) -> Void, onCancel: @escaping () -> Void) {
                self.onImage = onImage
                self.onCancel = onCancel
            }

            func imagePickerController(
                _ picker: UIImagePickerController,
                didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]
            ) {
                guard let image = info[.originalImage] as? UIImage,
                    let source = image.jpegData(compressionQuality: 0.9),
                    let prepared = ProfilePhotoPreparation.prepare(source)
                else {
                    onCancel()
                    return
                }
                onImage(prepared)
            }

            func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
                onCancel()
            }
        }
    }
#endif

extension WorldTheme {
    fileprivate var guardianSymbol: String {
        switch self {
        case .moonpetalKingdom:
            "crown.fill"
        case .buildItBay:
            "truck.box.fill"
        case .pawsAndPines:
            "pawprint.fill"
        }
    }
}
