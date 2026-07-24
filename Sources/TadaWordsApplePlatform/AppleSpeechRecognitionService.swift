@preconcurrency import AVFoundation
import Foundation
import OSLog
@preconcurrency import Speech
import TadaWordsDomain

public struct AppleSpeechActivityThresholds: Equatable, Sendable {
    public let minimumActiveDuration: ElapsedTime
    public let analysisFrameDuration: ElapsedTime
    public let minimumFrameRootMeanSquare: Float
    public let minimumPeakAmplitude: Float

    public init(
        minimumActiveDuration: ElapsedTime = ElapsedTime(seconds: 0.10),
        analysisFrameDuration: ElapsedTime = ElapsedTime(seconds: 0.02),
        minimumFrameRootMeanSquare: Float = 0.004,
        minimumPeakAmplitude: Float = 0.012
    ) {
        self.minimumActiveDuration = ElapsedTime(
            seconds: max(0.04, minimumActiveDuration.seconds)
        )
        self.analysisFrameDuration = ElapsedTime(
            seconds: max(0.005, analysisFrameDuration.seconds)
        )
        self.minimumFrameRootMeanSquare = max(0.0001, minimumFrameRootMeanSquare)
        self.minimumPeakAmplitude = max(
            self.minimumFrameRootMeanSquare,
            minimumPeakAmplitude
        )
    }

    /// A deliberately short activity gate for isolated early sight words. It
    /// rejects empty microphone buffers without requiring a child to sustain
    /// words such as "a" or "I" for the voiceprint model's longer window.
    public static let childSightWord = AppleSpeechActivityThresholds()
}

public struct AppleSpeechRecognitionConfiguration: Equatable, Sendable {
    public let localeIdentifier: String
    public let maximumAllowedRecordingDuration: ElapsedTime
    public let requiresOnDeviceRecognition: Bool
    public let partialResultStabilityDuration: Duration
    public let decisionThresholds: AppleRecognitionThresholds
    public let speechActivityThresholds: AppleSpeechActivityThresholds

    public init(
        localeIdentifier: String = "en-US",
        maximumAllowedRecordingDuration: ElapsedTime = ElapsedTime(seconds: 15),
        requiresOnDeviceRecognition: Bool = true,
        partialResultStabilityDuration: Duration = .milliseconds(450),
        decisionThresholds: AppleRecognitionThresholds = .speech,
        speechActivityThresholds: AppleSpeechActivityThresholds = .childSightWord
    ) {
        self.localeIdentifier = localeIdentifier
        self.maximumAllowedRecordingDuration =
            maximumAllowedRecordingDuration.seconds > 0
            ? maximumAllowedRecordingDuration
            : ElapsedTime(seconds: 15)
        self.requiresOnDeviceRecognition = requiresOnDeviceRecognition
        self.partialResultStabilityDuration =
            partialResultStabilityDuration > .zero
            ? partialResultStabilityDuration
            : .milliseconds(450)
        self.decisionThresholds = decisionThresholds
        self.speechActivityThresholds = speechActivityThresholds
    }

    public static let `default` = AppleSpeechRecognitionConfiguration()
}

/// Captures one short utterance and evaluates its exact normalized word.
///
/// This service never requests permissions. When a device-local voiceprint
/// verifier is injected, it evaluates the same in-memory PCM used for speech
/// recognition and discards the samples at the end of the request.
public actor AppleSpeechRecognitionService: SpeechRecognitionService {
    private let configuration: AppleSpeechRecognitionConfiguration
    private let permissionChecker: any AppleSpeechPermissionChecking
    private let resultResolver: AppleSpeechRecognitionResultResolver
    private let voiceprintVerifier: AppleVoiceprintVerifier?
    private let diagnosticHandler: (@Sendable (AppleSpeechErrorDiagnostic) -> Void)?

    private var isRecognizing = false

    public init(
        configuration: AppleSpeechRecognitionConfiguration = .default,
        permissionChecker: any AppleSpeechPermissionChecking =
            SystemAppleSpeechPermissionChecker(),
        voiceprintVerifier: AppleVoiceprintVerifier? = nil,
        diagnosticHandler: (@Sendable (AppleSpeechErrorDiagnostic) -> Void)? = nil
    ) {
        self.configuration = configuration
        self.permissionChecker = permissionChecker
        self.resultResolver = AppleSpeechRecognitionResultResolver(
            decisionPolicy: AppleRecognitionDecisionPolicy(
                thresholds: configuration.decisionThresholds,
                matchPolicy: .sightWordPronunciation
            ),
            activityThresholds: configuration.speechActivityThresholds
        )
        self.voiceprintVerifier = voiceprintVerifier
        self.diagnosticHandler = diagnosticHandler
    }

    public func recognize(
        _ request: SpeechRecognitionRequest
    ) async throws -> RecognitionResult {
        try Task.checkCancellation()

        guard !isRecognizing else {
            return resultResolver.technicalFailure(.serviceUnavailable)
        }

        if let reason = AppleSpeechCapabilityPolicy.failureReason(
            requiresOnDeviceRecognition: configuration.requiresOnDeviceRecognition,
            isSimulator: Self.isSimulator,
            supportsOnDeviceRecognition: true
        ) {
            return resultResolver.technicalFailure(reason)
        }

        guard permissionChecker.currentState().isAuthorized else {
            return resultResolver.technicalFailure(.permissionDenied)
        }

        let duration = min(
            request.maximumRecordingDuration.seconds,
            configuration.maximumAllowedRecordingDuration.seconds
        )
        guard duration > 0 else {
            return resultResolver.technicalFailure(.timedOut)
        }

        let locale = Locale(identifier: configuration.localeIdentifier)
        guard let recognizer = SFSpeechRecognizer(locale: locale),
            recognizer.isAvailable
        else {
            return resultResolver.technicalFailure(.serviceUnavailable)
        }
        if let reason = AppleSpeechCapabilityPolicy.failureReason(
            requiresOnDeviceRecognition: configuration.requiresOnDeviceRecognition,
            isSimulator: Self.isSimulator,
            supportsOnDeviceRecognition: recognizer.supportsOnDeviceRecognition
        ) {
            return resultResolver.technicalFailure(reason)
        }

        isRecognizing = true
        defer { isRecognizing = false }

        let audioEngine = AVAudioEngine()
        let inputNode = audioEngine.inputNode
        let speechRequest = SFSpeechAudioBufferRecognitionRequest()
        speechRequest.shouldReportPartialResults = true
        speechRequest.addsPunctuation = false
        speechRequest.taskHint = .confirmation
        speechRequest.requiresOnDeviceRecognition =
            configuration.requiresOnDeviceRecognition
        speechRequest.contextualStrings = AppleSpeechContextualStringPolicy.strings(
            for: request.prompt
        )

        var voiceProcessingEnabled = false
        var recognitionTask: SFSpeechRecognitionTask?
        let audioCapture = SpeechAudioCapture(
            audioEngine: audioEngine,
            inputNode: inputNode,
            request: speechRequest
        )
        let completionBox = SpeechRecognitionCompletionBox(
            stabilityDelay: configuration.partialResultStabilityDuration,
            finishAudio: {
                audioCapture.finishAudio()
            }
        )

        defer {
            completionBox.finishAudioIfNeeded()
            recognitionTask?.cancel()
            if voiceProcessingEnabled {
                try? inputNode.setVoiceProcessingEnabled(false)
            }
            deactivateAudioSession()
        }

        do {
            try activateAudioSession(
                noiseSuppressionEnabled: request.noiseSuppressionEnabled
            )
            voiceProcessingEnabled = enableVoiceProcessingIfSupported(
                on: inputNode,
                requested: request.noiseSuppressionEnabled
            )

            let recordingFormat = inputNode.outputFormat(forBus: 0)
            guard recordingFormat.sampleRate > 0, recordingFormat.channelCount > 0 else {
                return resultResolver.technicalFailure(.noUsableAudio)
            }

            audioCapture.installTap(format: recordingFormat)

            let diagnosticHandler = self.diagnosticHandler
            let earlyMatchResolver = resultResolver
            recognitionTask = try SpeechRecognitionStartupSequence.start(
                startAudio: {
                    try audioCapture.start()
                },
                startRecognitionTask: {
                    recognizer.recognitionTask(with: speechRequest) {
                        result,
                        error in
                        if let result {
                            let snapshot = SpeechTranscriptSnapshot(result: result)
                            let acceptImmediately =
                                earlyMatchResolver.isHighConfidenceMatch(
                                    snapshot,
                                    target: request.prompt
                                )
                            completionBox.receive(
                                snapshot,
                                isFinal: result.isFinal,
                                acceptImmediately: acceptImmediately
                            )
                        }
                        if let error {
                            let mapping = AppleSpeechErrorMapper.mapping(for: error)
                            AppleSpeechDiagnosticLogger.report(mapping.diagnostic)
                            diagnosticHandler?(mapping.diagnostic)
                            completionBox.fail(with: mapping)
                        }
                    }
                }
            )

            let deadlineTask = Task {
                try? await Task.sleep(for: .milliseconds(Int64(duration * 1_000)))
                guard !Task.isCancelled else { return }
                completionBox.deadlineReached(
                    receivedUsableAudio: resultResolver.hasUsableSpeech(
                        audioCapture.sampleSnapshot()
                    )
                )
            }
            defer { deadlineTask.cancel() }

            let completion = await withTaskCancellationHandler {
                await withCheckedContinuation { continuation in
                    completionBox.install(continuation)
                }
            } onCancel: {
                completionBox.cancel()
            }

            switch completion {
            case .transcript(let snapshot):
                let capturedAudio = audioCapture.sampleSnapshot()
                guard resultResolver.hasUsableSpeech(capturedAudio) else {
                    return resultResolver.technicalFailure(.noUsableAudio)
                }
                let speakerAssessment = await assessSpeaker(
                    for: request,
                    capturedAudio: capturedAudio
                )
                try Task.checkCancellation()
                return resultResolver.resolve(
                    snapshot: snapshot,
                    target: request.prompt,
                    capturedAudio: capturedAudio,
                    speakerAssessment: speakerAssessment
                )
            case .technicalFailure(let reason):
                return resultResolver.technicalFailure(reason)
            case .cancelled:
                throw CancellationError()
            }
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            let mapping = AppleSpeechErrorMapper.mapping(for: error)
            AppleSpeechDiagnosticLogger.report(mapping.diagnostic)
            diagnosticHandler?(mapping.diagnostic)
            return resultResolver.technicalFailure(mapping.reason)
        }
    }

    private func assessSpeaker(
        for request: SpeechRecognitionRequest,
        capturedAudio: SpeechCapturedAudio
    ) async -> TargetSpeakerAssessment {
        guard request.speakerFilterPolicy == .useWhenAvailable,
            let voiceprintVerifier
        else {
            return .unavailable
        }
        return await voiceprintVerifier.assess(
            profileID: request.profileID,
            samples: capturedAudio.samples,
            sampleRate: capturedAudio.sampleRate
        )
    }

    private func enableVoiceProcessingIfSupported(
        on inputNode: AVAudioInputNode,
        requested: Bool
    ) -> Bool {
        guard requested else { return false }

        #if os(iOS)
            do {
                try inputNode.setVoiceProcessingEnabled(true)
                return inputNode.isVoiceProcessingEnabled
            } catch {
                // Voice processing is a best-effort enhancement. Raw microphone audio
                // remains valid input when a route does not support the voice I/O unit.
                return false
            }
        #else
            return false
        #endif
    }

    private func activateAudioSession(noiseSuppressionEnabled: Bool) throws {
        #if os(iOS)
            let audioSession = AVAudioSession.sharedInstance()
            let category: AVAudioSession.Category =
                noiseSuppressionEnabled ? .playAndRecord : .record
            let options: AVAudioSession.CategoryOptions =
                noiseSuppressionEnabled
                ? [.duckOthers, .allowBluetoothHFP, .defaultToSpeaker]
                : [.duckOthers]
            try audioSession.setCategory(
                category,
                mode: noiseSuppressionEnabled ? .voiceChat : .measurement,
                options: options
            )
            try audioSession.setActive(true)
        #endif
    }

    private func deactivateAudioSession() {
        #if os(iOS)
            try? AVAudioSession.sharedInstance().setActive(
                false,
                options: .notifyOthersOnDeactivation
            )
        #endif
    }

    private static var isSimulator: Bool {
        #if targetEnvironment(simulator)
            true
        #else
            false
        #endif
    }
}

enum AppleSpeechContextualStringPolicy {
    static func strings(for prompt: WordPrompt) -> [String] {
        var strings = [prompt.normalizedText]
        guard let context = safeContext(from: prompt) else { return strings }

        if context.caseInsensitiveCompare(prompt.normalizedText) != .orderedSame {
            strings.append(context)
        }
        return strings
    }

    private static func safeContext(from prompt: WordPrompt) -> String? {
        guard
            let context = prompt.audioCue.spokenContext?.trimmingCharacters(
                in: .whitespacesAndNewlines
            ),
            !context.isEmpty,
            context.count <= EnglishPromptSafetyPolicy.maximumContextCharacterCount,
            !context.unicodeScalars.contains(where: CharacterSet.controlCharacters.contains)
        else {
            return nil
        }

        let escapedTarget = NSRegularExpression.escapedPattern(
            for: prompt.normalizedText
        )
        let pattern = "(?<![a-z])\(escapedTarget)(?![a-z])"
        guard
            context.range(
                of: pattern,
                options: [.regularExpression, .caseInsensitive]
            ) != nil
        else {
            return nil
        }
        return context
    }
}

enum AppleSpeechCapabilityPolicy {
    static func failureReason(
        requiresOnDeviceRecognition: Bool,
        isSimulator: Bool,
        supportsOnDeviceRecognition: Bool
    ) -> TechnicalFailureReason? {
        guard requiresOnDeviceRecognition else { return nil }
        guard !isSimulator, supportsOnDeviceRecognition else {
            return .onDeviceRecognitionUnavailable
        }
        return nil
    }
}

struct SpeechTranscriptSnapshot: Equatable, Sendable {
    let text: String
    let confidence: RecognitionConfidence?

    init(text: String, confidence: RecognitionConfidence?) {
        self.text = text
        self.confidence = confidence
    }

    init(result: SFSpeechRecognitionResult) {
        let transcription = result.bestTranscription
        self.text = transcription.formattedString
        self.confidence = transcription.segments
            .map(\.confidence)
            .min()
            .map { RecognitionConfidence(Double($0)) }
    }
}

enum SpeechTranscriptValuePolicy {
    static func isMeaningful(_ transcript: SpeechTranscriptSnapshot) -> Bool {
        let trimmed = transcript.text.trimmingCharacters(
            in: .whitespacesAndNewlines
        )
        guard !trimmed.isEmpty else { return false }
        return trimmed.unicodeScalars.contains { scalar in
            CharacterSet.letters.contains(scalar)
        }
    }
}

enum SpeechRecognitionCompletion: Equatable, Sendable {
    case transcript(SpeechTranscriptSnapshot)
    case technicalFailure(TechnicalFailureReason)
    case cancelled
}

/// Starts capture before Speech can issue a terminal callback. Some Apple
/// recognizers report setup failures synchronously from task creation; keeping
/// the ordering in one testable seam prevents a finished request from starting
/// its audio engine afterward.
enum SpeechRecognitionStartupSequence {
    static func start<TaskType>(
        startAudio: () throws -> Void,
        startRecognitionTask: () -> TaskType
    ) rethrows -> TaskType {
        try startAudio()
        return startRecognitionTask()
    }
}

struct SpeechRecognitionEndpointTransition: Equatable, Sendable {
    let shouldFinishAudio: Bool
    let completion: SpeechRecognitionCompletion?
    let stabilityGeneration: Int?

    static let none = SpeechRecognitionEndpointTransition(
        shouldFinishAudio: false,
        completion: nil,
        stabilityGeneration: nil
    )
}

/// Pure endpoint state. Keeping deadline, final-result, cancellation, and
/// partial-stability races here makes the callback adapter deterministic and
/// independently testable.
struct SpeechRecognitionEndpointStateMachine: Sendable {
    private(set) var latestTranscript: SpeechTranscriptSnapshot?
    private(set) var activeStabilityGeneration: Int?
    private(set) var isAudioFinished = false
    private(set) var isCompleted = false

    private var generation = 0

    mutating func receive(
        _ transcript: SpeechTranscriptSnapshot,
        isFinal: Bool,
        acceptImmediately: Bool = false
    ) -> SpeechRecognitionEndpointTransition {
        guard !isCompleted else { return .none }

        if isFinal {
            latestTranscript = transcript
            return complete(with: .transcript(transcript))
        }

        // Speech can emit empty or punctuation-only hypotheses while the
        // recognizer warms up. They are not evidence that a child has started
        // or finished a word, so they must never arm automatic endpointing.
        guard SpeechTranscriptValuePolicy.isMeaningful(transcript) else {
            return .none
        }
        latestTranscript = transcript

        // A high-confidence exact/pronunciation-equivalent target is already
        // enough evidence for an isolated sight-word prompt. Returning that
        // partial immediately avoids waiting for Apple's final-result pass.
        if acceptImmediately {
            return complete(with: .transcript(transcript))
        }

        // SFSpeech may emit one last partial while it is finalizing after
        // `endAudio()`. Keep the fresher text, but do not start another timer.
        guard !isAudioFinished else { return .none }

        generation += 1
        activeStabilityGeneration = generation
        return SpeechRecognitionEndpointTransition(
            shouldFinishAudio: false,
            completion: nil,
            stabilityGeneration: generation
        )
    }

    mutating func stabilityReached(
        generation: Int
    ) -> SpeechRecognitionEndpointTransition {
        guard
            !isCompleted,
            activeStabilityGeneration == generation
        else {
            return .none
        }
        activeStabilityGeneration = nil
        guard let latestTranscript else {
            return finishAudioTransition()
        }
        // Once the hypothesis has stopped changing, use it directly. Waiting
        // for a separate SFSpeech final callback adds another device-dependent
        // 1–2 seconds without improving the product-level decision.
        return complete(with: .transcript(latestTranscript))
    }

    mutating func fail(
        with reason: TechnicalFailureReason,
        allowingLatestTranscriptFallback: Bool = false
    ) -> SpeechRecognitionEndpointTransition {
        guard !isCompleted else { return .none }
        if allowingLatestTranscriptFallback, let latestTranscript {
            return complete(with: .transcript(latestTranscript))
        }
        return complete(with: .technicalFailure(reason))
    }

    mutating func deadlineReached(
        receivedUsableAudio: Bool
    ) -> SpeechRecognitionEndpointTransition {
        guard !isCompleted else { return .none }

        if let latestTranscript {
            return complete(with: .transcript(latestTranscript))
        }
        return complete(
            with: .technicalFailure(
                receivedUsableAudio ? .timedOut : .noUsableAudio
            )
        )
    }

    mutating func cancel() -> SpeechRecognitionEndpointTransition {
        guard !isCompleted else { return .none }
        return complete(with: .cancelled)
    }

    mutating func finishAudioIfNeeded() -> SpeechRecognitionEndpointTransition {
        finishAudioTransition()
    }

    private mutating func complete(
        with completion: SpeechRecognitionCompletion
    ) -> SpeechRecognitionEndpointTransition {
        isCompleted = true
        activeStabilityGeneration = nil
        let audioTransition = finishAudioTransition()
        return SpeechRecognitionEndpointTransition(
            shouldFinishAudio: audioTransition.shouldFinishAudio,
            completion: completion,
            stabilityGeneration: nil
        )
    }

    private mutating func finishAudioTransition() -> SpeechRecognitionEndpointTransition {
        guard !isAudioFinished else { return .none }
        isAudioFinished = true
        return SpeechRecognitionEndpointTransition(
            shouldFinishAudio: true,
            completion: nil,
            stabilityGeneration: nil
        )
    }
}

/// SFSpeech callbacks can race the deadline and structured cancellation.
/// NSLock is kept at this narrow callback bridge; product logic stays actor-safe.
final class SpeechRecognitionCompletionBox: @unchecked Sendable {
    private let lock = NSLock()
    private let stabilityDelay: Duration
    private let finishAudio: @Sendable () -> Void

    private var continuation: CheckedContinuation<SpeechRecognitionCompletion, Never>?
    private var pendingCompletion: SpeechRecognitionCompletion?
    private var state = SpeechRecognitionEndpointStateMachine()
    private var stabilityTask: Task<Void, Never>?

    init(
        stabilityDelay: Duration,
        finishAudio: @escaping @Sendable () -> Void
    ) {
        self.stabilityDelay = stabilityDelay
        self.finishAudio = finishAudio
    }

    func install(
        _ continuation: CheckedContinuation<SpeechRecognitionCompletion, Never>
    ) {
        let completionToResume: SpeechRecognitionCompletion? = lock.withLock {
            if let pendingCompletion {
                self.pendingCompletion = nil
                return pendingCompletion
            }
            self.continuation = continuation
            return nil
        }

        if let completionToResume {
            continuation.resume(returning: completionToResume)
        }
    }

    func receive(
        _ transcript: SpeechTranscriptSnapshot,
        isFinal: Bool,
        acceptImmediately: Bool = false
    ) {
        let transition = lock.withLock {
            state.receive(
                transcript,
                isFinal: isFinal,
                acceptImmediately: acceptImmediately
            )
        }
        perform(transition)
    }

    func fail(with mapping: AppleSpeechErrorMapping) {
        let transition = lock.withLock {
            state.fail(
                with: mapping.reason,
                allowingLatestTranscriptFallback: mapping.allowsTranscriptFallback
            )
        }
        perform(transition)
    }

    func deadlineReached(receivedUsableAudio: Bool) {
        let transition = lock.withLock {
            state.deadlineReached(receivedUsableAudio: receivedUsableAudio)
        }
        perform(transition)
    }

    func cancel() {
        let transition = lock.withLock {
            state.cancel()
        }
        perform(transition)
    }

    func finishAudioIfNeeded() {
        let transition = lock.withLock {
            state.finishAudioIfNeeded()
        }
        perform(transition)
    }

    private func perform(_ transition: SpeechRecognitionEndpointTransition) {
        if transition.shouldFinishAudio {
            finishAudio()
        }
        if let completion = transition.completion {
            cancelStabilityTask()
            deliver(completion)
        } else if let generation = transition.stabilityGeneration {
            scheduleStabilityCheck(generation: generation)
        }
    }

    private func scheduleStabilityCheck(generation: Int) {
        let delay = stabilityDelay
        let task = Task { [weak self] in
            do {
                try await Task.sleep(for: delay)
            } catch {
                return
            }
            guard !Task.isCancelled else { return }
            self?.stabilityReached(generation: generation)
        }

        var previousTask: Task<Void, Never>?
        let shouldKeepTask = lock.withLock {
            guard
                !state.isCompleted,
                state.activeStabilityGeneration == generation
            else {
                return false
            }
            previousTask = stabilityTask
            stabilityTask = task
            return true
        }

        if shouldKeepTask {
            previousTask?.cancel()
        } else {
            task.cancel()
        }
    }

    private func stabilityReached(generation: Int) {
        let transition = lock.withLock {
            state.stabilityReached(generation: generation)
        }
        perform(transition)
    }

    private func cancelStabilityTask() {
        let task = lock.withLock {
            let task = stabilityTask
            stabilityTask = nil
            return task
        }
        task?.cancel()
    }

    private func deliver(_ completion: SpeechRecognitionCompletion) {
        let continuationToResume: CheckedContinuation<SpeechRecognitionCompletion, Never>? =
            lock.withLock {
                guard let continuation else {
                    pendingCompletion = completion
                    return nil
                }
                self.continuation = nil
                return continuation
            }

        continuationToResume?.resume(returning: completion)
    }
}

private final class SpeechAudioCapture: @unchecked Sendable {
    private let audioEngine: AVAudioEngine
    private let inputNode: AVAudioInputNode
    private let request: SFSpeechAudioBufferRecognitionRequest
    private let lock = NSLock()

    private var tapInstalled = false
    private var audioFinished = false
    private var capturedSamples: [Float] = []
    private var sampleRate = 0.0

    init(
        audioEngine: AVAudioEngine,
        inputNode: AVAudioInputNode,
        request: SFSpeechAudioBufferRecognitionRequest
    ) {
        self.audioEngine = audioEngine
        self.inputNode = inputNode
        self.request = request
    }

    func sampleSnapshot() -> SpeechCapturedAudio {
        lock.withLock {
            SpeechCapturedAudio(
                samples: capturedSamples,
                sampleRate: sampleRate
            )
        }
    }

    func installTap(format: AVAudioFormat) {
        lock.withLock {
            sampleRate = format.sampleRate
        }
        inputNode.installTap(
            onBus: 0,
            bufferSize: 1_024,
            format: format
        ) { [weak self] buffer, _ in
            self?.append(buffer)
        }
        lock.withLock {
            tapInstalled = true
        }
    }

    func start() throws {
        audioEngine.prepare()
        try audioEngine.start()
    }

    func finishAudio() {
        let shouldRemoveTap = lock.withLock {
            guard !audioFinished else { return false }
            audioFinished = true
            return tapInstalled
        }

        if shouldRemoveTap {
            inputNode.removeTap(onBus: 0)
        }
        audioEngine.stop()
        request.endAudio()
    }

    private func append(_ buffer: AVAudioPCMBuffer) {
        lock.withLock {
            guard !audioFinished else { return }
            appendVoiceprintSamples(buffer)
            request.append(buffer)
        }
    }

    private func appendVoiceprintSamples(_ buffer: AVAudioPCMBuffer) {
        guard let channels = buffer.floatChannelData, sampleRate > 0 else { return }
        let maximumCount = Int(sampleRate * 15)
        let remainingCount = maximumCount - capturedSamples.count
        guard remainingCount > 0 else { return }
        let count = min(Int(buffer.frameLength), remainingCount)
        capturedSamples.append(contentsOf: UnsafeBufferPointer(start: channels[0], count: count))
    }
}

struct SpeechCapturedAudio: Equatable, Sendable {
    let samples: [Float]
    let sampleRate: Double
}

struct SpeechActivityEvidence: Equatable, Sendable {
    let longestActiveDuration: ElapsedTime
    let peakAmplitude: Float
    let hasUsableSpeech: Bool
}

enum SpeechActivityEvidencePolicy {
    static func evaluate(
        _ capturedAudio: SpeechCapturedAudio,
        thresholds: AppleSpeechActivityThresholds
    ) -> SpeechActivityEvidence {
        let samples = capturedAudio.samples
        let sampleRate = capturedAudio.sampleRate
        guard
            sampleRate.isFinite,
            sampleRate > 0,
            !samples.isEmpty,
            samples.allSatisfy(\.isFinite)
        else {
            return insufficientEvidence
        }

        let frameSampleCount = max(
            1,
            Int(sampleRate * thresholds.analysisFrameDuration.seconds)
        )
        var currentActiveSampleCount = 0
        var longestActiveSampleCount = 0
        var overallPeak: Float = 0

        for lowerBound in stride(
            from: samples.startIndex,
            to: samples.endIndex,
            by: frameSampleCount
        ) {
            let upperBound = min(samples.endIndex, lowerBound + frameSampleCount)
            let frame = samples[lowerBound..<upperBound]
            var squareSum = 0.0
            var framePeak: Float = 0
            for sample in frame {
                let magnitude = abs(sample)
                framePeak = max(framePeak, magnitude)
                squareSum += Double(sample * sample)
            }
            overallPeak = max(overallPeak, framePeak)
            let rootMeanSquare = Float(
                sqrt(squareSum / Double(max(1, frame.count)))
            )
            if rootMeanSquare >= thresholds.minimumFrameRootMeanSquare,
                framePeak >= thresholds.minimumPeakAmplitude
            {
                currentActiveSampleCount += frame.count
                longestActiveSampleCount = max(
                    longestActiveSampleCount,
                    currentActiveSampleCount
                )
            } else {
                currentActiveSampleCount = 0
            }
        }

        let longestActiveDuration = ElapsedTime(
            seconds: Double(longestActiveSampleCount) / sampleRate
        )
        return SpeechActivityEvidence(
            longestActiveDuration: longestActiveDuration,
            peakAmplitude: overallPeak,
            hasUsableSpeech: longestActiveDuration >= thresholds.minimumActiveDuration
                && overallPeak >= thresholds.minimumPeakAmplitude
        )
    }

    private static let insufficientEvidence = SpeechActivityEvidence(
        longestActiveDuration: .zero,
        peakAmplitude: 0,
        hasUsableSpeech: false
    )
}

struct AppleSpeechRecognitionResultResolver: Sendable {
    let decisionPolicy: AppleRecognitionDecisionPolicy
    let activityThresholds: AppleSpeechActivityThresholds

    func hasUsableSpeech(_ capturedAudio: SpeechCapturedAudio) -> Bool {
        SpeechActivityEvidencePolicy.evaluate(
            capturedAudio,
            thresholds: activityThresholds
        ).hasUsableSpeech
    }

    func isHighConfidenceMatch(
        _ snapshot: SpeechTranscriptSnapshot,
        target: WordPrompt
    ) -> Bool {
        guard
            let confidence = snapshot.confidence,
            confidence >= decisionPolicy.thresholds.minimumMismatchConfidence
        else {
            return false
        }
        return decisionPolicy.evaluate(
            transcript: snapshot.text,
            confidence: confidence,
            target: target
        ).decision == .matched
    }

    func resolve(
        snapshot: SpeechTranscriptSnapshot,
        target: WordPrompt,
        capturedAudio: SpeechCapturedAudio,
        speakerAssessment: TargetSpeakerAssessment
    ) -> RecognitionResult {
        guard hasUsableSpeech(capturedAudio) else {
            return technicalFailure(.noUsableAudio)
        }
        let decision = decisionPolicy.evaluate(
            transcript: snapshot.text,
            confidence: snapshot.confidence,
            target: target
        )
        return RecognitionResult(
            decision: decision.decision,
            recognizedText: decision.recognizedText,
            confidence: decision.confidence,
            targetSpeakerAssessment: speakerAssessment
        )
    }

    func technicalFailure(_ reason: TechnicalFailureReason) -> RecognitionResult {
        decisionPolicy.technicalFailure(reason)
    }
}

public struct AppleSpeechErrorDiagnostic: Equatable, Sendable {
    public let domain: String
    public let code: Int

    public init(domain: String, code: Int) {
        self.domain = domain
        self.code = code
    }
}

struct AppleSpeechErrorMapping: Equatable, Sendable {
    let reason: TechnicalFailureReason
    let diagnostic: AppleSpeechErrorDiagnostic

    var allowsTranscriptFallback: Bool {
        switch reason {
        case .noUsableAudio, .serviceUnavailable, .timedOut:
            true
        case .corruptedInput, .onDeviceRecognitionUnavailable, .permissionDenied,
            .wrongSpeaker:
            false
        }
    }
}

private enum AppleSpeechDiagnosticLogger {
    private static let logger = Logger(
        subsystem: Bundle.main.bundleIdentifier ?? "app.tadawords.app",
        category: "SpeechRecognition"
    )

    static func report(_ diagnostic: AppleSpeechErrorDiagnostic) {
        logger.error(
            "Speech recognition failed: domain=\(diagnostic.domain, privacy: .public) code=\(diagnostic.code, privacy: .public)"
        )
    }
}

enum AppleSpeechErrorMapper {
    static func mapping(for error: Error) -> AppleSpeechErrorMapping {
        let nsError = error as NSError
        return AppleSpeechErrorMapping(
            reason: technicalFailureReason(
                domain: nsError.domain,
                code: nsError.code
            ),
            diagnostic: AppleSpeechErrorDiagnostic(
                domain: nsError.domain,
                code: nsError.code
            )
        )
    }

    static func technicalFailureReason(for error: Error) -> TechnicalFailureReason {
        mapping(for: error).reason
    }

    private static func technicalFailureReason(
        domain: String,
        code: Int
    ) -> TechnicalFailureReason {
        switch domain {
        case SFSpeechErrorDomain:
            switch code {
            case SFSpeechError.Code.audioReadFailed.rawValue:
                .noUsableAudio
            case SFSpeechError.Code.timeout.rawValue:
                .timedOut
            case SFSpeechError.Code.missingParameter.rawValue,
                SFSpeechError.Code.undefinedTemplateClassName.rawValue,
                SFSpeechError.Code.malformedSupplementalModel.rawValue:
                .corruptedInput
            default:
                .serviceUnavailable
            }

        case "kAFAssistantErrorDomain":
            switch code {
            case 1110:
                .noUsableAudio
            case 1700:
                .permissionDenied
            default:
                .serviceUnavailable
            }

        case "kLSRErrorDomain":
            switch code {
            case 102, 201:
                .onDeviceRecognitionUnavailable
            default:
                .serviceUnavailable
            }

        default:
            .serviceUnavailable
        }
    }
}
