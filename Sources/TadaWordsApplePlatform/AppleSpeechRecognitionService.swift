@preconcurrency import AVFoundation
import Foundation
@preconcurrency import Speech
import TadaWordsDomain

public struct AppleSpeechRecognitionConfiguration: Equatable, Sendable {
    public let localeIdentifier: String
    public let maximumAllowedRecordingDuration: ElapsedTime
    public let requiresOnDeviceRecognition: Bool
    public let partialResultStabilityDuration: Duration
    public let decisionThresholds: AppleRecognitionThresholds

    public init(
        localeIdentifier: String = "en-US",
        maximumAllowedRecordingDuration: ElapsedTime = ElapsedTime(seconds: 15),
        requiresOnDeviceRecognition: Bool = true,
        partialResultStabilityDuration: Duration = .milliseconds(600),
        decisionThresholds: AppleRecognitionThresholds = .speech
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
            : .milliseconds(600)
        self.decisionThresholds = decisionThresholds
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
    private let decisionPolicy: AppleRecognitionDecisionPolicy
    private let voiceprintVerifier: AppleVoiceprintVerifier?

    private var isRecognizing = false

    public init(
        configuration: AppleSpeechRecognitionConfiguration = .default,
        permissionChecker: any AppleSpeechPermissionChecking =
            SystemAppleSpeechPermissionChecker(),
        voiceprintVerifier: AppleVoiceprintVerifier? = nil
    ) {
        self.configuration = configuration
        self.permissionChecker = permissionChecker
        self.decisionPolicy = AppleRecognitionDecisionPolicy(
            thresholds: configuration.decisionThresholds,
            matchPolicy: .sightWordPronunciation
        )
        self.voiceprintVerifier = voiceprintVerifier
    }

    public func recognize(
        _ request: SpeechRecognitionRequest
    ) async throws -> RecognitionResult {
        try Task.checkCancellation()

        guard !isRecognizing else {
            return decisionPolicy.technicalFailure(.serviceUnavailable)
        }

        if let reason = AppleSpeechCapabilityPolicy.failureReason(
            requiresOnDeviceRecognition: configuration.requiresOnDeviceRecognition,
            isSimulator: Self.isSimulator,
            supportsOnDeviceRecognition: true
        ) {
            return decisionPolicy.technicalFailure(reason)
        }

        guard permissionChecker.currentState().isAuthorized else {
            return decisionPolicy.technicalFailure(.permissionDenied)
        }

        let duration = min(
            request.maximumRecordingDuration.seconds,
            configuration.maximumAllowedRecordingDuration.seconds
        )
        guard duration > 0 else {
            return decisionPolicy.technicalFailure(.timedOut)
        }

        let locale = Locale(identifier: configuration.localeIdentifier)
        guard let recognizer = SFSpeechRecognizer(locale: locale),
            recognizer.isAvailable
        else {
            return decisionPolicy.technicalFailure(.serviceUnavailable)
        }
        if let reason = AppleSpeechCapabilityPolicy.failureReason(
            requiresOnDeviceRecognition: configuration.requiresOnDeviceRecognition,
            isSimulator: Self.isSimulator,
            supportsOnDeviceRecognition: recognizer.supportsOnDeviceRecognition
        ) {
            return decisionPolicy.technicalFailure(reason)
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
                return decisionPolicy.technicalFailure(.noUsableAudio)
            }

            audioCapture.installTap(format: recordingFormat)

            recognitionTask = recognizer.recognitionTask(with: speechRequest) {
                result,
                error in
                if let result {
                    completionBox.receive(
                        SpeechTranscriptSnapshot(result: result),
                        isFinal: result.isFinal
                    )
                }
                if let error {
                    completionBox.fail(
                        with: AppleSpeechErrorMapper.technicalFailureReason(for: error)
                    )
                }
            }

            try audioCapture.start()

            let deadlineTask = Task {
                try? await Task.sleep(for: .milliseconds(Int64(duration * 1_000)))
                guard !Task.isCancelled else { return }
                completionBox.deadlineReached(
                    receivedAudioBuffer: audioCapture.hasReceivedAudioBuffer
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
                let decision = decisionPolicy.evaluate(
                    transcript: snapshot.text,
                    confidence: snapshot.confidence,
                    target: request.prompt
                )
                let speakerAssessment = await assessSpeaker(
                    for: request,
                    capturedAudio: audioCapture.sampleSnapshot()
                )
                return RecognitionResult(
                    decision: decision.decision,
                    recognizedText: decision.recognizedText,
                    confidence: decision.confidence,
                    targetSpeakerAssessment: speakerAssessment
                )
            case .technicalFailure(let reason):
                return decisionPolicy.technicalFailure(reason)
            case .cancelled:
                throw CancellationError()
            }
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            return decisionPolicy.technicalFailure(
                AppleSpeechErrorMapper.technicalFailureReason(for: error)
            )
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

enum SpeechRecognitionCompletion: Equatable, Sendable {
    case transcript(SpeechTranscriptSnapshot)
    case technicalFailure(TechnicalFailureReason)
    case cancelled
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
        isFinal: Bool
    ) -> SpeechRecognitionEndpointTransition {
        guard !isCompleted else { return .none }
        latestTranscript = transcript

        if isFinal {
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
        return finishAudioTransition()
    }

    mutating func fail(
        with reason: TechnicalFailureReason
    ) -> SpeechRecognitionEndpointTransition {
        guard !isCompleted else { return .none }
        return complete(with: .technicalFailure(reason))
    }

    mutating func deadlineReached(
        receivedAudioBuffer: Bool
    ) -> SpeechRecognitionEndpointTransition {
        guard !isCompleted else { return .none }

        if let latestTranscript {
            return complete(with: .transcript(latestTranscript))
        }
        return complete(
            with: .technicalFailure(
                receivedAudioBuffer ? .timedOut : .noUsableAudio
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

    func receive(_ transcript: SpeechTranscriptSnapshot, isFinal: Bool) {
        let transition = lock.withLock {
            state.receive(transcript, isFinal: isFinal)
        }
        perform(transition)
    }

    func fail(with reason: TechnicalFailureReason) {
        let transition = lock.withLock {
            state.fail(with: reason)
        }
        perform(transition)
    }

    func deadlineReached(receivedAudioBuffer: Bool) {
        let transition = lock.withLock {
            state.deadlineReached(receivedAudioBuffer: receivedAudioBuffer)
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

    private var receivedAudioBuffer = false
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

    var hasReceivedAudioBuffer: Bool {
        lock.withLock { receivedAudioBuffer }
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
            receivedAudioBuffer = true
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

enum AppleSpeechErrorMapper {
    static func technicalFailureReason(for error: Error) -> TechnicalFailureReason {
        let nsError = error as NSError
        guard nsError.domain == SFSpeechErrorDomain else {
            return .serviceUnavailable
        }

        switch nsError.code {
        case SFSpeechError.Code.audioReadFailed.rawValue:
            return .noUsableAudio
        case SFSpeechError.Code.timeout.rawValue:
            return .timedOut
        case SFSpeechError.Code.missingParameter.rawValue:
            return .corruptedInput
        default:
            return .serviceUnavailable
        }
    }
}
