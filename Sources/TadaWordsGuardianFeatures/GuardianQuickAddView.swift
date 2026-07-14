import Foundation
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
    let practiceFrequencyByWordID: [WordPromptID: Int]
    let undoWordsByMode: [LearningMode: [WordPrompt]]
    let isUpdatingWordPool: Bool
    let imageTextRecognitionService: any ImageTextRecognizing
    let onBack: () -> Void
    let onSubmit:
        @MainActor (GuardianWordImportRequest) async
            -> GuardianWordImportReport?
    let onPlay: (WordPrompt) -> Void
    let onSetWordsActive: @MainActor ([WordPrompt], Bool) async -> Bool
    @Binding var hasConfirmedRemovalThisSession: Bool

    @State private var selectedMode: LearningMode
    @State private var typedWord = ""
    @State private var feedback: GuardianWordManagerFeedback?
    @State private var isSubmitting = false
    @State private var isRecognizing = false
    @State private var isSelecting = false
    @State private var selectedWordIDs = Set<WordPromptID>()
    @State private var pendingRemoval: [WordPrompt] = []
    @State private var showsRemovalConfirmation = false
    @State private var ocrWords: [GuardianEditableOCRWord] = []
    @State private var showsOCRPreview = false
    @State private var poolSearchText = ""
    @State private var poolSortOrder: GuardianWordSortOrder = .addedOrder
    @FocusState private var managerInputIsFocused: Bool

    #if os(iOS)
        @State private var selectedPhotoItems: [PhotosPickerItem] = []
        @State private var additionalPhotoItems: [PhotosPickerItem] = []
        @State private var isCameraPresented = false
        @State private var appendsNextCameraPhoto = false
    #endif

    init(
        initialMode: LearningMode,
        readWords: [WordPrompt],
        writeWords: [WordPrompt],
        practiceFrequencyByWordID: [WordPromptID: Int],
        undoWordsByMode: [LearningMode: [WordPrompt]],
        isUpdatingWordPool: Bool,
        imageTextRecognitionService: any ImageTextRecognizing,
        hasConfirmedRemovalThisSession: Binding<Bool>,
        onBack: @escaping () -> Void,
        onSubmit:
            @escaping @MainActor (GuardianWordImportRequest) async
            -> GuardianWordImportReport?,
        onPlay: @escaping (WordPrompt) -> Void,
        onSetWordsActive: @escaping @MainActor ([WordPrompt], Bool) async -> Bool
    ) {
        self.readWords = readWords
        self.writeWords = writeWords
        self.practiceFrequencyByWordID = practiceFrequencyByWordID
        self.undoWordsByMode = undoWordsByMode
        self.isUpdatingWordPool = isUpdatingWordPool
        self.imageTextRecognitionService = imageTextRecognitionService
        self.onBack = onBack
        self.onSubmit = onSubmit
        self.onPlay = onPlay
        self.onSetWordsActive = onSetWordsActive
        _hasConfirmedRemovalThisSession = hasConfirmedRemovalThisSession
        _selectedMode = State(initialValue: initialMode)
    }

    private var currentWords: [WordPrompt] {
        selectedMode == .read ? readWords : writeWords
    }

    private var presentedWords: [WordPrompt] {
        GuardianWordListPresentation.prompts(
            currentWords,
            sortOrder: poolSortOrder,
            searchText: poolSearchText,
            practiceFrequencyByWordID: practiceFrequencyByWordID
        )
    }

    private var practiceFrequencyByNormalizedWord: [String: Int] {
        Dictionary(
            uniqueKeysWithValues: currentWords.map { prompt in
                (
                    prompt.normalizedText,
                    practiceFrequencyByWordID[prompt.id, default: 0]
                )
            }
        )
    }

    private var undoWords: [WordPrompt] {
        undoWordsByMode[selectedMode, default: []]
    }

    #if DEBUG
        private var isDebugOCRFixtureEnabled: Bool {
            let arguments = ProcessInfo.processInfo.arguments
            return arguments.contains("--demo-mode")
                && arguments.contains("--ui-testing")
                && arguments.contains("--ui-testing-ocr-fixture")
        }
    #endif

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
            .scrollDismissesKeyboard(.immediately)
        }
        .onChange(of: selectedMode) {
            isSelecting = false
            selectedWordIDs = []
            feedback = nil
            poolSearchText = ""
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
            ocrPreview
        }
        #if os(iOS)
            .onChange(of: selectedPhotoItems) { _, items in
                guard !items.isEmpty else { return }
                Task {
                    await recognizeWords(in: items, appending: false)
                    selectedPhotoItems = []
                }
            }
            .onChange(of: additionalPhotoItems) { _, items in
                guard !items.isEmpty else { return }
                Task {
                    await recognizeWords(in: items, appending: true)
                    additionalPhotoItems = []
                }
            }
            .fullScreenCover(isPresented: $isCameraPresented) {
                GuardianWordSheetCameraPicker { data in
                    isCameraPresented = false
                    let appending = appendsNextCameraPhoto
                    appendsNextCameraPhoto = false
                    Task { await recognizeWords(in: [data], appending: appending) }
                } onCancel: {
                    isCameraPresented = false
                    if appendsNextCameraPhoto {
                        appendsNextCameraPhoto = false
                        showsOCRPreview = true
                    }
                }
            }
        #endif
    }

    @ViewBuilder
    private var ocrPreview: some View {
        #if os(iOS)
            GuardianOCRPreviewView(
                mode: selectedMode,
                existingWords: currentWords,
                practiceFrequencyByNormalizedWord: practiceFrequencyByNormalizedWord,
                words: $ocrWords,
                isRecognizingAdditionalPhotos: isRecognizing,
                recognitionFeedbackMessage: feedback?.message,
                additionalPhotoItems: $additionalPhotoItems,
                onCancel: { showsOCRPreview = false },
                onTakeAnotherPhoto: prepareToTakeAnotherPhoto,
                onAdd: addOCRWords
            )
        #else
            GuardianOCRPreviewView(
                mode: selectedMode,
                existingWords: currentWords,
                practiceFrequencyByNormalizedWord: practiceFrequencyByNormalizedWord,
                words: $ocrWords,
                isRecognizingAdditionalPhotos: isRecognizing,
                recognitionFeedbackMessage: feedback?.message,
                onCancel: { showsOCRPreview = false },
                onTakeAnotherPhoto: prepareToTakeAnotherPhoto,
                onAdd: addOCRWords
            )
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
                        .focused($managerInputIsFocused)
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

            #if DEBUG
                if isDebugOCRFixtureEnabled {
                    Button {
                        Task {
                            await recognizeWords(
                                in: [Data("ui-testing-ocr-fixture".utf8)],
                                appending: false
                            )
                        }
                    } label: {
                        Label("Import test word sheet", systemImage: "doc.text.viewfinder")
                            .frame(maxWidth: .infinity, minHeight: 44)
                    }
                    .buttonStyle(.bordered)
                    .disabled(isRecognizing)
                    .accessibilityIdentifier("guardian.ocr-fixture")
                }
            #endif
        #else
            Text("Photo import is available on iPhone and iPad.")
                .foregroundStyle(GuardianSemanticTokens.secondaryForeground)
        #endif
    }

    #if os(iOS)
        private var photoLibraryButton: some View {
            PhotosPicker(
                selection: $selectedPhotoItems,
                maxSelectionCount: nil,
                matching: .images
            ) {
                Label("Choose Photos", systemImage: "photo.on.rectangle.angled")
                    .frame(maxWidth: .infinity, minHeight: 44)
            }
            .buttonStyle(.bordered)
            .disabled(isRecognizing)
        }

        private var cameraButton: some View {
            Button {
                appendsNextCameraPhoto = false
                isCameraPresented = true
            } label: {
                Label("Take Photo", systemImage: "camera.fill")
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

                poolSearchAndSortControls

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
                            .disabled(isUpdatingWordPool)
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
                } else if presentedWords.isEmpty {
                    VStack(spacing: GuardianPrimitiveTokens.Spacing.small) {
                        Image(systemName: "magnifyingglass")
                            .font(.system(size: 28, weight: .semibold))
                            .foregroundStyle(GuardianSemanticTokens.secondaryForeground)
                        Text("No matching words")
                            .font(.system(.headline, design: .rounded, weight: .bold))
                        Text("Try another spelling or clear the search.")
                            .font(.system(.caption, design: .rounded, weight: .medium))
                            .foregroundStyle(GuardianSemanticTokens.secondaryForeground)
                    }
                    .frame(maxWidth: .infinity, minHeight: 120)
                } else {
                    LazyVStack(spacing: 0) {
                        ForEach(presentedWords, id: \.id) { prompt in
                            managerRow(prompt)
                            if prompt.id != presentedWords.last?.id { Divider() }
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
                    .disabled(isUpdatingWordPool)
                }
            }
        }
    }

    private var poolSearchAndSortControls: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: GuardianPrimitiveTokens.Spacing.small) {
                poolSearchField
                poolSortMenu
            }
            VStack(spacing: GuardianPrimitiveTokens.Spacing.small) {
                poolSearchField
                poolSortMenu
                    .frame(maxWidth: .infinity, alignment: .trailing)
            }
        }
    }

    private var poolSearchField: some View {
        HStack(spacing: 6) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(GuardianSemanticTokens.secondaryForeground)
            TextField("Search words", text: $poolSearchText)
                .autocorrectionDisabled()
                .focused($managerInputIsFocused)
            if !poolSearchText.isEmpty {
                Button {
                    poolSearchText = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(GuardianSemanticTokens.secondaryForeground)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Clear word search")
            }
        }
        .padding(.horizontal, 12)
        .frame(minHeight: 44)
        .background(
            GuardianSemanticTokens.background,
            in: RoundedRectangle(
                cornerRadius: GuardianPrimitiveTokens.Radius.small,
                style: .continuous
            )
        )
    }

    private var poolSortMenu: some View {
        Menu {
            Picker("Sort words", selection: $poolSortOrder) {
                ForEach(GuardianWordSortOrder.allCases, id: \.self) { order in
                    Label(order.title, systemImage: order.symbol)
                        .tag(order)
                }
            }
        } label: {
            Label(poolSortOrder.title, systemImage: "arrow.up.arrow.down")
                .frame(minHeight: 44)
        }
        .buttonStyle(.bordered)
        .accessibilityLabel("Sort words by \(poolSortOrder.title)")
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

            practiceFrequencyBadge(
                practiceFrequencyByWordID[prompt.id, default: 0]
            )
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
                .disabled(isUpdatingWordPool)
                .accessibilityLabel("Remove \(prompt.displayText)")
            }
        }
        .padding(.vertical, 6)
    }

    private func practiceFrequencyBadge(_ count: Int) -> some View {
        Label("\(count)", systemImage: "repeat")
            .font(.system(.caption2, design: .rounded, weight: .bold))
            .foregroundStyle(GuardianSemanticTokens.secondaryForeground)
            .padding(.horizontal, 7)
            .padding(.vertical, 4)
            .background(
                GuardianSemanticTokens.background,
                in: Capsule()
            )
            .accessibilityLabel("Practiced \(count) \(count == 1 ? "time" : "times")")
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
        submit(
            GuardianWordImportRequest(
                rawText: source,
                learningMode: selectedMode
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
                managerInputIsFocused = true
            }
        }
    }

    #if os(iOS)
        private func recognizeWords(
            in photoItems: [PhotosPickerItem],
            appending: Bool
        ) async {
            var imageData: [Data] = []
            for item in photoItems {
                guard let data = try? await item.loadTransferable(type: Data.self) else {
                    feedback = .error(
                        "One selected photo could not be opened. Choose the photos again."
                    )
                    return
                }
                imageData.append(data)
            }
            await recognizeWords(in: imageData, appending: appending)
        }
    #endif

    private func recognizeWords(in imageData: [Data], appending: Bool) async {
        guard !isRecognizing else { return }
        isRecognizing = true
        feedback = .progress(
            imageData.count == 1
                ? "Reading the photo…"
                : "Reading \(imageData.count) photos…"
        )
        defer { isRecognizing = false }

        do {
            var additions: [GuardianEditableOCRWord] = []
            for (photoIndex, data) in imageData.enumerated() {
                let fragments = try await imageTextRecognitionService.recognizeText(
                    in: data
                )
                let parseResult = RecognizedEnglishWordParser().parseResult(fragments)
                do {
                    try GuardianOCRPhotoWordLimitPolicy().validate(
                        recognizedWordCount: parseResult.recognizedWordCount
                    )
                } catch let error as GuardianOCRPhotoWordLimitError {
                    guard
                        case .tooManyWords(let recognizedCount, let maximum) = error
                    else { throw error }
                    let photoName =
                        imageData.count == 1
                        ? "This photo"
                        : "Photo \(photoIndex + 1)"
                    feedback = .error(
                        "\(photoName) contains \(recognizedCount) words. Each photo can contain at most \(maximum). Choose a shorter word sheet."
                    )
                    if appending { showsOCRPreview = true }
                    return
                }
                let parsedWords = parseResult.uniqueWords
                guard !parsedWords.isEmpty else {
                    feedback = .error(
                        imageData.count == 1
                            ? "No English words were found. Try a clearer photo."
                            : "Photo \(photoIndex + 1) has no English words. Replace that photo and try again."
                    )
                    if appending { showsOCRPreview = true }
                    return
                }
                additions = GuardianOCRBatchAccumulator.appending(
                    parsedWords,
                    to: additions
                )
            }
            guard !additions.isEmpty else {
                feedback = .error("No English words were found. Try a clearer photo.")
                if appending { showsOCRPreview = true }
                return
            }
            ocrWords = GuardianOCRBatchAccumulator.appending(
                additions.map(\.text),
                to: appending ? ocrWords : []
            )
            feedback = nil
            showsOCRPreview = true
        } catch is CancellationError {
            feedback = nil
            if appending { showsOCRPreview = true }
        } catch let error as GuardianOCRPhotoWordLimitError {
            switch error {
            case .tooManyWords(let recognizedCount, let maximum):
                feedback = .error(
                    "This photo contains \(recognizedCount) words. Each photo can contain at most \(maximum). Choose a shorter word sheet."
                )
            }
            if appending { showsOCRPreview = true }
        } catch {
            feedback = .error(
                "The words could not be read. Try a brighter, flatter photo."
            )
            if appending { showsOCRPreview = true }
        }
    }

    private func prepareToTakeAnotherPhoto() {
        #if os(iOS)
            guard !isRecognizing else { return }
            appendsNextCameraPhoto = true
            showsOCRPreview = false
            Task { @MainActor in
                // Let the review sheet finish dismissing before presenting the camera again.
                // Presenting two sheets in the same run-loop turn is unreliable on device.
                try? await Task.sleep(for: .milliseconds(350))
                isCameraPresented = true
            }
        #endif
    }

    @MainActor
    private func addOCRWords(_ words: [String]) async -> Bool {
        guard !words.isEmpty else { return false }
        guard
            let report = await onSubmit(
                GuardianWordImportRequest(
                    rawText: words.joined(separator: "\n"),
                    learningMode: selectedMode
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
        if hasConfirmedRemovalThisSession {
            removePendingWords()
        } else {
            showsRemovalConfirmation = true
        }
    }

    private func removePendingWords() {
        hasConfirmedRemovalThisSession = true
        let prompts = pendingRemoval
        pendingRemoval = []
        Task {
            guard await onSetWordsActive(prompts, false) else { return }
            selectedWordIDs = []
            isSelecting = false
        }
    }

    private func restoreLastRemoval() {
        let prompts = undoWords
        Task {
            _ = await onSetWordsActive(prompts, true)
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

}

private struct GuardianOCRPreviewView: View {
    let mode: LearningMode
    let existingWords: [WordPrompt]
    let practiceFrequencyByNormalizedWord: [String: Int]
    @Binding var words: [GuardianEditableOCRWord]
    let isRecognizingAdditionalPhotos: Bool
    let recognitionFeedbackMessage: String?
    #if os(iOS)
        @Binding var additionalPhotoItems: [PhotosPickerItem]
    #endif
    let onCancel: () -> Void
    let onTakeAnotherPhoto: () -> Void
    let onAdd: @MainActor ([String]) async -> Bool

    @State private var isAdding = false
    @State private var sortOrder: GuardianWordSortOrder = .addedOrder
    @State private var submissionError: String?
    @FocusState private var inputIsFocused: Bool

    private let topAnchor = "guardian-ocr-top"
    private let bottomAnchor = "guardian-ocr-bottom"

    private var analysis: GuardianOCRPreviewAnalysis {
        GuardianOCRPreviewAnalysis(
            words: words,
            existingNormalizedWords: Set(existingWords.map(\.normalizedText))
        )
    }

    private var presentedWords: [GuardianEditableOCRWord] {
        GuardianWordListPresentation.recognizedWords(
            words,
            sortOrder: sortOrder,
            practiceFrequencyByNormalizedWord: practiceFrequencyByNormalizedWord
        )
    }

    var body: some View {
        ScrollViewReader { proxy in
            ZStack {
                GuardianSemanticTokens.background.ignoresSafeArea()
                ScrollView {
                    VStack(
                        alignment: .leading,
                        spacing: GuardianPrimitiveTokens.Spacing.medium
                    ) {
                        Color.clear
                            .frame(height: 1)
                            .id(topAnchor)

                        Text(
                            "Edit mistakes or remove anything that is not part of the school list. Duplicates are skipped automatically."
                        )
                        .font(.system(.subheadline, design: .rounded, weight: .medium))
                        .foregroundStyle(GuardianSemanticTokens.secondaryForeground)

                        reviewControls

                        if isRecognizingAdditionalPhotos {
                            Label("Reading the additional photos…", systemImage: "text.viewfinder")
                                .font(.system(.subheadline, design: .rounded, weight: .semibold))
                                .foregroundStyle(GuardianSemanticTokens.secondaryForeground)
                            ProgressView()
                                .frame(maxWidth: .infinity)
                        } else if let recognitionFeedbackMessage {
                            Label(
                                recognitionFeedbackMessage,
                                systemImage: "exclamationmark.triangle.fill"
                            )
                            .font(.system(.caption, design: .rounded, weight: .semibold))
                            .foregroundStyle(.red)
                        }

                        GuardianCard {
                            LazyVStack(spacing: 0) {
                                ForEach(presentedWords) { word in
                                    HStack(spacing: GuardianPrimitiveTokens.Spacing.small) {
                                        Text("\(word.sourceOrdinal).")
                                            .font(
                                                .system(
                                                    .caption,
                                                    design: .rounded,
                                                    weight: .bold
                                                )
                                            )
                                            .foregroundStyle(
                                                GuardianSemanticTokens.secondaryForeground
                                            )
                                            .frame(width: 34, alignment: .trailing)
                                            .monospacedDigit()

                                        TextField("Word", text: textBinding(for: word.id))
                                            .textFieldStyle(.roundedBorder)
                                            .font(
                                                .system(.body, design: .rounded, weight: .semibold)
                                            )
                                            .focused($inputIsFocused)
                                        previewState(for: word)
                                        practiceFrequencyBadge(for: word)
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
                                    if word.id != presentedWords.last?.id { Divider() }
                                }
                            }
                        }

                        Color.clear
                            .frame(height: 1)
                            .id(bottomAnchor)
                    }
                    .frame(maxWidth: 820, alignment: .leading)
                    .padding(GuardianPrimitiveTokens.Spacing.large)
                    .frame(maxWidth: .infinity)
                }
                .scrollDismissesKeyboard(.immediately)
            }
            .safeAreaInset(edge: .top, spacing: 0) {
                navigationBar(proxy: proxy)
            }
            .safeAreaInset(edge: .bottom, spacing: 0) {
                addAllBar
            }
        }
        .foregroundStyle(GuardianSemanticTokens.foreground)
    }

    private func navigationBar(proxy: ScrollViewProxy) -> some View {
        HStack(spacing: GuardianPrimitiveTokens.Spacing.small) {
            Button(action: onCancel) {
                Label("Back", systemImage: "chevron.left")
                    .frame(minHeight: 44)
            }
            .buttonStyle(.bordered)

            Spacer()
            Text("Review scanned words")
                .font(.system(.title3, design: .rounded, weight: .bold))
                .lineLimit(1)
            Spacer()

            Button {
                inputIsFocused = false
                withAnimation { proxy.scrollTo(topAnchor, anchor: .top) }
            } label: {
                Image(systemName: "arrow.up")
                    .frame(width: 44, height: 44)
            }
            .buttonStyle(.bordered)
            .accessibilityLabel("Scroll to top")

            Button {
                inputIsFocused = false
                withAnimation { proxy.scrollTo(bottomAnchor, anchor: .bottom) }
            } label: {
                Image(systemName: "arrow.down")
                    .frame(width: 44, height: 44)
            }
            .buttonStyle(.bordered)
            .accessibilityLabel("Scroll to bottom")
        }
        .padding(.horizontal, GuardianPrimitiveTokens.Spacing.medium)
        .padding(.vertical, GuardianPrimitiveTokens.Spacing.small)
        .background(.regularMaterial)
    }

    private var reviewControls: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: GuardianPrimitiveTokens.Spacing.small) {
                sortMenu
                Spacer()
                photoButtons
            }
            VStack(alignment: .leading, spacing: GuardianPrimitiveTokens.Spacing.small) {
                sortMenu
                photoButtons
            }
        }
    }

    private var sortMenu: some View {
        Menu {
            Picker("Sort scanned words", selection: $sortOrder) {
                ForEach(GuardianWordSortOrder.allCases, id: \.self) { order in
                    Label(order.title, systemImage: order.symbol)
                        .tag(order)
                }
            }
        } label: {
            Label(sortOrder.title, systemImage: "arrow.up.arrow.down")
                .frame(minHeight: 44)
        }
        .buttonStyle(.bordered)
    }

    @ViewBuilder
    private var photoButtons: some View {
        #if os(iOS)
            HStack(spacing: GuardianPrimitiveTokens.Spacing.small) {
                PhotosPicker(
                    selection: $additionalPhotoItems,
                    maxSelectionCount: nil,
                    matching: .images
                ) {
                    Label("Add photos", systemImage: "photo.badge.plus")
                        .frame(minHeight: 44)
                }
                .buttonStyle(.bordered)
                .disabled(isAdding || isRecognizingAdditionalPhotos)

                Button(action: onTakeAnotherPhoto) {
                    Label("Take another", systemImage: "camera.fill")
                        .frame(minHeight: 44)
                }
                .buttonStyle(.bordered)
                .disabled(
                    isAdding
                        || isRecognizingAdditionalPhotos
                        || !UIImagePickerController.isSourceTypeAvailable(.camera)
                )
            }
        #else
            EmptyView()
        #endif
    }

    private var addAllBar: some View {
        VStack(alignment: .leading, spacing: GuardianPrimitiveTokens.Spacing.small) {
            if let submissionError {
                Label(submissionError, systemImage: "exclamationmark.triangle.fill")
                    .font(.system(.caption, design: .rounded, weight: .semibold))
                    .foregroundStyle(.red)
            }
            Button {
                inputIsFocused = false
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
                !GuardianOCRSubmissionPolicy.canSubmit(
                    addableWords: analysis.addableWords,
                    isAdding: isAdding,
                    isRecognizingAdditionalPhotos: isRecognizingAdditionalPhotos
                )
            )
        }
        .frame(maxWidth: 820)
        .padding(.horizontal, GuardianPrimitiveTokens.Spacing.large)
        .padding(.vertical, GuardianPrimitiveTokens.Spacing.small)
        .frame(maxWidth: .infinity)
        .background(.regularMaterial)
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

    private func practiceFrequencyBadge(for word: GuardianEditableOCRWord) -> some View {
        let count = GuardianWordListPresentation.recognizedFrequency(
            for: word,
            in: practiceFrequencyByNormalizedWord
        )
        return Label("\(count)", systemImage: "repeat")
            .font(.system(.caption2, design: .rounded, weight: .bold))
            .foregroundStyle(GuardianSemanticTokens.secondaryForeground)
            .accessibilityLabel("Practiced \(count) \(count == 1 ? "time" : "times")")
    }

    private func textBinding(for id: UUID) -> Binding<String> {
        Binding(
            get: {
                words.first(where: { $0.id == id })?.text ?? ""
            },
            set: { newValue in
                guard let index = words.firstIndex(where: { $0.id == id }) else {
                    return
                }
                words[index].text = newValue
            }
        )
    }

    private func addAll() {
        guard !isAdding else { return }
        isAdding = true
        submissionError = nil
        Task {
            defer { isAdding = false }
            if await onAdd(analysis.addableWords) {
                onCancel()
            } else {
                submissionError =
                    "The words were not added. Check the highlighted entries and try again."
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
