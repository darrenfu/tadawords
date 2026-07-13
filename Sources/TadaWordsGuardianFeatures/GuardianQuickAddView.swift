import SwiftUI
import TadaWordsContent
import TadaWordsDesignSystem
import TadaWordsDomain

#if os(iOS)
    import PhotosUI
    import UIKit
#endif

/// One grown-up workspace for both manual and photo-based word management.
struct GuardianWordManagerView: View {
    let readWords: [WordPrompt]
    let writeWords: [WordPrompt]
    let imageTextRecognitionService: any ImageTextRecognizing
    let onBack: () -> Void
    let onSubmit:
        @MainActor (GuardianWordImportRequest) async
            -> GuardianWordImportReport?
    let onPlay: (WordPrompt) -> Void
    let onSetWordsActive: @MainActor ([WordPrompt], Bool) async -> Bool

    @State private var selectedMode: LearningMode
    @State private var typedWord = ""
    @State private var typedContextWord: String?
    @State private var typedSpokenContext = ""
    @State private var feedback: GuardianWordManagerFeedback?
    @State private var isSubmitting = false
    @State private var isRecognizing = false
    @State private var isSelecting = false
    @State private var selectedWordIDs = Set<WordPromptID>()
    @State private var pendingRemoval: [WordPrompt] = []
    @State private var showsRemovalConfirmation = false
    @State private var undoWords: [WordPrompt] = []
    @State private var ocrWords: [GuardianEditableOCRWord] = []
    @State private var ocrSpokenContexts: [String: String] = [:]
    @State private var showsOCRPreview = false
    @FocusState private var typedWordIsFocused: Bool

    #if os(iOS)
        @State private var selectedPhotoItem: PhotosPickerItem?
        @State private var isCameraPresented = false
    #endif

    init(
        initialMode: LearningMode,
        readWords: [WordPrompt],
        writeWords: [WordPrompt],
        imageTextRecognitionService: any ImageTextRecognizing,
        onBack: @escaping () -> Void,
        onSubmit:
            @escaping @MainActor (GuardianWordImportRequest) async
            -> GuardianWordImportReport?,
        onPlay: @escaping (WordPrompt) -> Void,
        onSetWordsActive: @escaping @MainActor ([WordPrompt], Bool) async -> Bool
    ) {
        self.readWords = readWords
        self.writeWords = writeWords
        self.imageTextRecognitionService = imageTextRecognitionService
        self.onBack = onBack
        self.onSubmit = onSubmit
        self.onPlay = onPlay
        self.onSetWordsActive = onSetWordsActive
        _selectedMode = State(initialValue: initialMode)
    }

    private var currentWords: [WordPrompt] {
        selectedMode == .read ? readWords : writeWords
    }

    var body: some View {
        GeometryReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: GuardianPrimitiveTokens.Spacing.medium) {
                    GuardianNavigationHeader(title: "Manage words", onBack: onBack)
                    modePicker

                    if proxy.size.width >= 700 {
                        HStack(alignment: .top, spacing: GuardianPrimitiveTokens.Spacing.medium) {
                            inputColumn
                                .frame(
                                    width: min(390, max(310, proxy.size.width * 0.39)),
                                    alignment: .top
                                )
                            poolColumn
                                .frame(maxWidth: .infinity, alignment: .top)
                        }
                    } else {
                        VStack(spacing: GuardianPrimitiveTokens.Spacing.medium) {
                            inputColumn
                            poolColumn
                        }
                    }
                }
                .frame(maxWidth: 1_100, alignment: .leading)
                .padding(.horizontal, GuardianPrimitiveTokens.Spacing.medium)
                .padding(.vertical, GuardianPrimitiveTokens.Spacing.medium)
                .frame(maxWidth: .infinity)
            }
            .scrollDismissesKeyboard(.interactively)
        }
        .onChange(of: selectedMode) {
            isSelecting = false
            selectedWordIDs = []
            typedContextWord = nil
            typedSpokenContext = ""
            feedback = nil
            undoWords = []
        }
        .alert(removalTitle, isPresented: $showsRemovalConfirmation) {
            Button("Cancel", role: .cancel) {
                pendingRemoval = []
            }
            Button("Remove", role: .destructive) {
                removePendingWords()
            }
        } message: {
            Text(removalMessage)
        }
        .sheet(isPresented: $showsOCRPreview) {
            GuardianOCRPreviewView(
                mode: selectedMode,
                existingWords: currentWords,
                words: $ocrWords,
                spokenContexts: $ocrSpokenContexts,
                onCancel: { showsOCRPreview = false },
                onAdd: addOCRWords
            )
        }
        #if os(iOS)
            .onChange(of: selectedPhotoItem) { _, item in
                guard let item else { return }
                Task {
                    defer { selectedPhotoItem = nil }
                    guard let data = try? await item.loadTransferable(type: Data.self) else {
                        feedback = .error("That photo could not be opened. Try another one.")
                        return
                    }
                    await recognizeWords(in: data)
                }
            }
            .fullScreenCover(isPresented: $isCameraPresented) {
                GuardianWordSheetCameraPicker { data in
                    isCameraPresented = false
                    Task { await recognizeWords(in: data) }
                } onCancel: {
                    isCameraPresented = false
                }
            }
        #endif
    }

    private var modePicker: some View {
        Picker("Word pool", selection: $selectedMode) {
            Text("Read · \(readWords.count)")
                .tag(LearningMode.read)
            Text("Write · \(writeWords.count)")
                .tag(LearningMode.write)
        }
        .pickerStyle(.segmented)
        .frame(maxWidth: 560)
        .accessibilityHint("Read and Write words are kept in separate pools")
    }

    private var inputColumn: some View {
        GuardianCard {
            VStack(alignment: .leading, spacing: GuardianPrimitiveTokens.Spacing.medium) {
                Label("Add to \(selectedMode.guardianTitle)", systemImage: "keyboard")
                    .font(.system(.title3, design: .rounded, weight: .bold))

                Text("Type one word, then press Return.")
                    .font(.system(.subheadline, design: .rounded, weight: .medium))
                    .foregroundStyle(GuardianSemanticTokens.secondaryForeground)

                HStack(spacing: GuardianPrimitiveTokens.Spacing.small) {
                    TextField("New word", text: $typedWord)
                        .textFieldStyle(.roundedBorder)
                        .font(.system(.title3, design: .rounded, weight: .semibold))
                        .submitLabel(.done)
                        .focused($typedWordIsFocused)
                        .onSubmit(commitTypedWord)
                        .accessibilityHint("Press Return to add this word immediately")

                    Button(action: commitTypedWord) {
                        Image(systemName: "plus")
                            .frame(
                                width: TadaPrimitiveTokens.TouchTarget.minimum,
                                height: TadaPrimitiveTokens.TouchTarget.minimum
                            )
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(GuardianSemanticTokens.accent(for: selectedMode))
                    .disabled(typedWord.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    .accessibilityLabel("Add word")
                }

                if let contextWord = typedContextWord {
                    typedContextEditor(for: contextWord)
                }

                if let feedback {
                    Label(feedback.message, systemImage: feedback.symbol)
                        .font(.system(.caption, design: .rounded, weight: .semibold))
                        .foregroundStyle(feedback.color)
                        .accessibilityLabel(feedback.message)
                }

                Divider()

                VStack(alignment: .leading, spacing: 6) {
                    Label("Scan a word sheet", systemImage: "text.viewfinder")
                        .font(.system(.headline, design: .rounded, weight: .bold))
                    Text("Review and edit every detected word before adding it.")
                        .font(.system(.caption, design: .rounded, weight: .medium))
                        .foregroundStyle(GuardianSemanticTokens.secondaryForeground)
                }

                imageSourceButtons

                Label(
                    "Text recognition happens on this device. Photos are not uploaded or saved.",
                    systemImage: "lock.shield.fill"
                )
                .font(.system(.caption2, design: .rounded, weight: .medium))
                .foregroundStyle(GuardianSemanticTokens.secondaryForeground)
            }
        }
    }

    @ViewBuilder
    private var imageSourceButtons: some View {
        #if os(iOS)
            ViewThatFits(in: .horizontal) {
                HStack(spacing: GuardianPrimitiveTokens.Spacing.small) {
                    photoLibraryButton
                    cameraButton
                }
                VStack(spacing: GuardianPrimitiveTokens.Spacing.small) {
                    photoLibraryButton
                    cameraButton
                }
            }
        #else
            Text("Photo import is available on iPhone and iPad.")
                .foregroundStyle(GuardianSemanticTokens.secondaryForeground)
        #endif
    }

    #if os(iOS)
        private var photoLibraryButton: some View {
            PhotosPicker(selection: $selectedPhotoItem, matching: .images) {
                Label("Choose Photo", systemImage: "photo.on.rectangle")
                    .frame(maxWidth: .infinity, minHeight: 44)
            }
            .buttonStyle(.bordered)
            .disabled(isRecognizing)
        }

        private var cameraButton: some View {
            Button {
                isCameraPresented = true
            } label: {
                Label("Camera", systemImage: "camera.fill")
                    .frame(maxWidth: .infinity, minHeight: 44)
            }
            .buttonStyle(.bordered)
            .disabled(
                isRecognizing
                    || !UIImagePickerController.isSourceTypeAvailable(.camera)
            )
        }
    #endif

    private var poolColumn: some View {
        GuardianCard {
            VStack(alignment: .leading, spacing: GuardianPrimitiveTokens.Spacing.small) {
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("\(selectedMode.guardianTitle) Pool")
                            .font(.system(.title3, design: .rounded, weight: .bold))
                        Text("Newest words appear first")
                            .font(.system(.caption, design: .rounded, weight: .medium))
                            .foregroundStyle(GuardianSemanticTokens.secondaryForeground)
                    }
                    Spacer()
                    if !currentWords.isEmpty {
                        Button(isSelecting ? "Done" : "Select") {
                            isSelecting.toggle()
                            if !isSelecting { selectedWordIDs = [] }
                        }
                        .frame(minWidth: 64, minHeight: 44)
                        .buttonStyle(.bordered)
                    }
                }

                if !undoWords.isEmpty {
                    HStack(spacing: GuardianPrimitiveTokens.Spacing.small) {
                        Label(
                            "Removed \(undoWords.count) \(undoWords.count == 1 ? "word" : "words")",
                            systemImage: "archivebox.fill"
                        )
                        .font(.system(.subheadline, design: .rounded, weight: .semibold))
                        Spacer()
                        Button("Undo") { restoreLastRemoval() }
                            .frame(minHeight: 44)
                            .buttonStyle(.borderedProminent)
                    }
                    .padding(.horizontal, 12)
                    .background(
                        GuardianSemanticTokens.accent(for: selectedMode).opacity(0.09),
                        in: RoundedRectangle(
                            cornerRadius: GuardianPrimitiveTokens.Radius.small,
                            style: .continuous
                        )
                    )
                }

                if currentWords.isEmpty {
                    VStack(spacing: GuardianPrimitiveTokens.Spacing.small) {
                        Image(systemName: "text.badge.plus")
                            .font(.system(size: 34, weight: .semibold))
                            .foregroundStyle(GuardianSemanticTokens.accent(for: selectedMode))
                        Text("No \(selectedMode.guardianTitle.lowercased()) words yet")
                            .font(.system(.headline, design: .rounded, weight: .bold))
                        Text("Type a word or scan this week’s school list.")
                            .font(.system(.subheadline, design: .rounded, weight: .medium))
                            .foregroundStyle(GuardianSemanticTokens.secondaryForeground)
                    }
                    .frame(maxWidth: .infinity, minHeight: 150)
                } else {
                    LazyVStack(spacing: 0) {
                        ForEach(currentWords, id: \.id) { prompt in
                            managerRow(prompt)
                            if prompt.id != currentWords.last?.id { Divider() }
                        }
                    }
                }

                if isSelecting, !selectedWordIDs.isEmpty {
                    Button(role: .destructive) {
                        requestRemoval(
                            currentWords.filter { selectedWordIDs.contains($0.id) }
                        )
                    } label: {
                        Label(
                            "Remove selected (\(selectedWordIDs.count))",
                            systemImage: "trash.fill"
                        )
                        .frame(maxWidth: .infinity, minHeight: 44)
                    }
                    .buttonStyle(.borderedProminent)
                }
            }
        }
    }

    private func managerRow(_ prompt: WordPrompt) -> some View {
        HStack(spacing: GuardianPrimitiveTokens.Spacing.small) {
            if isSelecting {
                Button {
                    toggleSelection(prompt.id)
                } label: {
                    Image(
                        systemName: selectedWordIDs.contains(prompt.id)
                            ? "checkmark.circle.fill"
                            : "circle"
                    )
                    .font(.system(size: 24, weight: .semibold))
                    .frame(width: 44, height: 44)
                }
                .buttonStyle(.plain)
                .foregroundStyle(GuardianSemanticTokens.accent(for: selectedMode))
                .accessibilityLabel(
                    selectedWordIDs.contains(prompt.id)
                        ? "Deselect \(prompt.displayText)"
                        : "Select \(prompt.displayText)"
                )
            }

            Text(prompt.displayText)
                .font(.system(.title3, design: .rounded, weight: .bold))
                .lineLimit(1)
            Spacer()

            Button {
                onPlay(prompt)
            } label: {
                Image(systemName: "speaker.wave.2.fill")
                    .frame(width: 44, height: 44)
            }
            .buttonStyle(.plain)
            .foregroundStyle(GuardianSemanticTokens.accent(for: selectedMode))
            .accessibilityLabel("Play \(prompt.displayText)")

            if !isSelecting {
                Button(role: .destructive) {
                    requestRemoval([prompt])
                } label: {
                    Image(systemName: "trash")
                        .frame(width: 44, height: 44)
                }
                .buttonStyle(.plain)
                .foregroundStyle(.red)
                .accessibilityLabel("Remove \(prompt.displayText)")
            }
        }
        .padding(.vertical, 6)
    }

    private func typedContextEditor(for word: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Add a short sentence so “\(word)” is spoken clearly.")
                .font(.system(.caption, design: .rounded, weight: .semibold))
            TextField(
                "Use “\(word)” in a sentence",
                text: $typedSpokenContext,
                axis: .vertical
            )
            .textFieldStyle(.roundedBorder)
            Button("Add word") { commitTypedContextWord(word) }
                .frame(minHeight: 44)
                .buttonStyle(.borderedProminent)
                .disabled(!contextIsValid(word, context: typedSpokenContext))
        }
    }

    private func commitTypedWord() {
        guard !isSubmitting else { return }
        let source = typedWord.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !source.isEmpty else { return }

        let parsed = ManualWordBatchParser().parse(
            source,
            learningMode: selectedMode
        )
        let tokenCount =
            parsed.accepted.count
            + parsed.rejected.filter {
                $0.reason != .emptyBatch
            }.count
        guard tokenCount == 1 else {
            feedback = .error("Enter one word at a time, then press Return.")
            return
        }
        if let contextWord = parsed.rejected.compactMap(\.requiredContextWord).first {
            typedContextWord = contextWord
            typedSpokenContext = ""
            feedback = nil
            return
        }

        submit(
            GuardianWordImportRequest(
                rawText: source,
                learningMode: selectedMode
            ),
            clearsTypedWordOnSuccess: true
        )
    }

    private func commitTypedContextWord(_ word: String) {
        guard contextIsValid(word, context: typedSpokenContext) else { return }
        submit(
            GuardianWordImportRequest(
                rawText: word,
                learningMode: selectedMode,
                spokenContextsByNormalizedWord: [
                    word: typedSpokenContext.trimmingCharacters(
                        in: .whitespacesAndNewlines
                    )
                ]
            ),
            clearsTypedWordOnSuccess: true
        )
    }

    private func submit(
        _ request: GuardianWordImportRequest,
        clearsTypedWordOnSuccess: Bool
    ) {
        guard !isSubmitting else { return }
        isSubmitting = true
        Task {
            defer { isSubmitting = false }
            guard let report = await onSubmit(request) else { return }
            feedback = GuardianWordManagerFeedback(report: report)
            if clearsTypedWordOnSuccess, !report.accepted.isEmpty || !report.duplicates.isEmpty {
                typedWord = ""
                typedContextWord = nil
                typedSpokenContext = ""
                typedWordIsFocused = true
            }
        }
    }

    private func recognizeWords(in imageData: Data) async {
        guard !isRecognizing else { return }
        isRecognizing = true
        feedback = .progress("Reading the photo…")
        defer { isRecognizing = false }

        do {
            let fragments = try await imageTextRecognitionService.recognizeText(
                in: imageData
            )
            let parsedWords = RecognizedEnglishWordParser().parse(fragments)
            guard !parsedWords.isEmpty else {
                feedback = .error("No English words were found. Try a clearer photo.")
                return
            }
            ocrWords = parsedWords.map { GuardianEditableOCRWord(text: $0) }
            ocrSpokenContexts = [:]
            feedback = nil
            showsOCRPreview = true
        } catch is CancellationError {
            feedback = nil
        } catch {
            feedback = .error("The words could not be read. Try a brighter, flatter photo.")
        }
    }

    @MainActor
    private func addOCRWords(
        _ words: [String],
        contexts: [String: String]
    ) async -> Bool {
        guard !words.isEmpty else { return false }
        guard
            let report = await onSubmit(
                GuardianWordImportRequest(
                    rawText: words.joined(separator: "\n"),
                    learningMode: selectedMode,
                    spokenContextsByNormalizedWord: contexts
                )
            )
        else {
            return false
        }
        feedback = GuardianWordManagerFeedback(report: report)
        return report.rejected.isEmpty
    }

    private func toggleSelection(_ id: WordPromptID) {
        if !selectedWordIDs.insert(id).inserted {
            selectedWordIDs.remove(id)
        }
    }

    private func requestRemoval(_ prompts: [WordPrompt]) {
        guard !prompts.isEmpty else { return }
        pendingRemoval = prompts
        showsRemovalConfirmation = true
    }

    private func removePendingWords() {
        let prompts = pendingRemoval
        pendingRemoval = []
        Task {
            guard await onSetWordsActive(prompts, false) else { return }
            undoWords = prompts
            selectedWordIDs = []
            isSelecting = false
        }
    }

    private func restoreLastRemoval() {
        let prompts = undoWords
        Task {
            guard await onSetWordsActive(prompts, true) else { return }
            undoWords = []
        }
    }

    private var removalTitle: String {
        pendingRemoval.count == 1 ? "Remove this word?" : "Remove selected words?"
    }

    private var removalMessage: String {
        let count = pendingRemoval.count
        return count == 1
            ? "It will leave future practice. Learning history stays available."
            : "These \(count) words will leave future practice. Learning history stays available."
    }

    private func contextIsValid(_ word: String, context: String) -> Bool {
        (try? WordPrompt(
            learningMode: selectedMode,
            text: word,
            audioCue: .contextual(context)
        )) != nil
    }
}

private struct GuardianOCRPreviewView: View {
    let mode: LearningMode
    let existingWords: [WordPrompt]
    @Binding var words: [GuardianEditableOCRWord]
    @Binding var spokenContexts: [String: String]
    let onCancel: () -> Void
    let onAdd: @MainActor ([String], [String: String]) async -> Bool

    @State private var isAdding = false

    private var analysis: GuardianOCRPreviewAnalysis {
        GuardianOCRPreviewAnalysis(
            words: words,
            existingNormalizedWords: Set(existingWords.map(\.normalizedText))
        )
    }

    private var requiredContextWords: [String] {
        ManualWordBatchParser().parse(
            analysis.addableWords.joined(separator: "\n"),
            learningMode: mode
        ).rejected.compactMap(\.requiredContextWord)
    }

    private var contextsAreValid: Bool {
        requiredContextWords.allSatisfy { word in
            guard let context = spokenContexts[word] else { return false }
            return
                (try? WordPrompt(
                    learningMode: mode,
                    text: word,
                    audioCue: .contextual(context)
                )) != nil
        }
    }

    var body: some View {
        ZStack {
            GuardianSemanticTokens.background.ignoresSafeArea()
            ScrollView {
                VStack(alignment: .leading, spacing: GuardianPrimitiveTokens.Spacing.medium) {
                    HStack {
                        Button("Cancel", action: onCancel)
                            .frame(minWidth: 72, minHeight: 44)
                        Spacer()
                        Text("Review scanned words")
                            .font(.system(.title2, design: .rounded, weight: .bold))
                        Spacer()
                        Color.clear.frame(width: 72, height: 44)
                    }

                    Text(
                        "Edit mistakes or remove anything that is not part of the school list. Duplicates are skipped automatically."
                    )
                    .font(.system(.subheadline, design: .rounded, weight: .medium))
                    .foregroundStyle(GuardianSemanticTokens.secondaryForeground)

                    GuardianCard {
                        LazyVStack(spacing: 0) {
                            ForEach($words) { $word in
                                HStack(spacing: GuardianPrimitiveTokens.Spacing.small) {
                                    TextField("Word", text: $word.text)
                                        .textFieldStyle(.roundedBorder)
                                        .font(.system(.body, design: .rounded, weight: .semibold))
                                    previewState(for: word)
                                    Button(role: .destructive) {
                                        words.removeAll { $0.id == word.id }
                                    } label: {
                                        Image(systemName: "trash")
                                            .frame(width: 44, height: 44)
                                    }
                                    .buttonStyle(.plain)
                                    .foregroundStyle(.red)
                                    .accessibilityLabel("Remove \(word.text)")
                                }
                                .padding(.vertical, 6)
                                if word.id != words.last?.id { Divider() }
                            }
                        }
                    }

                    if !requiredContextWords.isEmpty {
                        contextEditors
                    }

                    Button {
                        addAll()
                    } label: {
                        Label(
                            "Add all \(analysis.addableWords.count) to \(mode.guardianTitle)",
                            systemImage: "plus.circle.fill"
                        )
                        .frame(maxWidth: .infinity, minHeight: 44)
                    }
                    .buttonStyle(
                        GuardianPrimaryButtonStyle(
                            tint: GuardianSemanticTokens.accent(for: mode)
                        )
                    )
                    .disabled(
                        isAdding || analysis.addableWords.isEmpty || !contextsAreValid
                    )
                }
                .frame(maxWidth: 820, alignment: .leading)
                .padding(GuardianPrimitiveTokens.Spacing.large)
                .frame(maxWidth: .infinity)
            }
        }
        .foregroundStyle(GuardianSemanticTokens.foreground)
    }

    @ViewBuilder
    private func previewState(for word: GuardianEditableOCRWord) -> some View {
        switch analysis.stateByID[word.id] {
        case .ready:
            Image(systemName: "checkmark.circle.fill")
                .foregroundStyle(GuardianSemanticTokens.success)
                .accessibilityLabel("Ready to add")
        case .alreadyInPool:
            Text("In pool")
                .font(.system(.caption2, design: .rounded, weight: .bold))
                .foregroundStyle(GuardianSemanticTokens.secondaryForeground)
        case .duplicateInPreview:
            Text("Duplicate")
                .font(.system(.caption2, design: .rounded, weight: .bold))
                .foregroundStyle(.orange)
        case .invalid, .none:
            Text("Fix")
                .font(.system(.caption2, design: .rounded, weight: .bold))
                .foregroundStyle(.red)
        }
    }

    private var contextEditors: some View {
        GuardianCard {
            VStack(alignment: .leading, spacing: GuardianPrimitiveTokens.Spacing.small) {
                Text("Help with pronunciation")
                    .font(.system(.headline, design: .rounded, weight: .bold))
                ForEach(requiredContextWords, id: \.self) { word in
                    TextField(
                        "Use “\(word)” in a short sentence",
                        text: Binding(
                            get: { spokenContexts[word, default: ""] },
                            set: { spokenContexts[word] = $0 }
                        ),
                        axis: .vertical
                    )
                    .textFieldStyle(.roundedBorder)
                }
            }
        }
    }

    private func addAll() {
        guard !isAdding else { return }
        isAdding = true
        let contexts: [String: String] = Dictionary(
            uniqueKeysWithValues: requiredContextWords.compactMap { word in
                guard let context = spokenContexts[word] else { return nil }
                return (word, context.trimmingCharacters(in: .whitespacesAndNewlines))
            }
        )
        Task {
            defer { isAdding = false }
            if await onAdd(analysis.addableWords, contexts) {
                onCancel()
            }
        }
    }
}

private enum GuardianWordManagerFeedback: Equatable {
    case success(String)
    case error(String)
    case progress(String)

    init(report: GuardianWordImportReport) {
        if !report.accepted.isEmpty {
            let count = report.accepted.count
            self = .success("Added \(count) \(count == 1 ? "word" : "words")")
        } else if !report.duplicates.isEmpty {
            self = .success("Already in the \(report.learningMode.guardianTitle) Pool")
        } else {
            self = .error(report.rejected.first?.reason ?? "That word could not be added.")
        }
    }

    var message: String {
        switch self {
        case .success(let message), .error(let message), .progress(let message):
            message
        }
    }

    var symbol: String {
        switch self {
        case .success: "checkmark.circle.fill"
        case .error: "exclamationmark.triangle.fill"
        case .progress: "text.viewfinder"
        }
    }

    var color: Color {
        switch self {
        case .success: GuardianSemanticTokens.success
        case .error: .red
        case .progress: GuardianSemanticTokens.secondaryForeground
        }
    }
}

extension ManualWordRejection {
    fileprivate var requiredContextWord: String? {
        guard case .invalidPrompt(.contextRequired(let word, _)) = reason else {
            return nil
        }
        return word
    }
}

#if os(iOS)
    @MainActor
    private struct GuardianWordSheetCameraPicker: UIViewControllerRepresentable {
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
                    let data = image.jpegData(compressionQuality: 0.92)
                else {
                    onCancel()
                    return
                }
                onImage(data)
            }

            func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
                onCancel()
            }
        }
    }
#endif
