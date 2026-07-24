import Foundation
import Speech
import TadaWordsDomain
import XCTest

@testable import TadaWordsApplePlatform

final class AppleSpeechAdapterTests: XCTestCase {
    func testPermissionStateRequiresBothAuthorizations() {
        XCTAssertTrue(
            AppleSpeechPermissionState(
                speechRecognition: .authorized,
                microphone: .authorized
            ).isAuthorized
        )
        XCTAssertFalse(
            AppleSpeechPermissionState(
                speechRecognition: .authorized,
                microphone: .notDetermined
            ).isAuthorized
        )
        XCTAssertFalse(
            AppleSpeechPermissionState(
                speechRecognition: .denied,
                microphone: .authorized
            ).isAuthorized
        )
    }

    func testPermissionRequestPlanHandlesSpeechAndMicrophoneSeparately() {
        XCTAssertEqual(
            AppleSpeechPermissionRequestPlan(
                state: AppleSpeechPermissionState(
                    speechRecognition: .notDetermined,
                    microphone: .authorized
                )
            ),
            AppleSpeechPermissionRequestPlan(
                requestsSpeechRecognition: true,
                requestsMicrophone: false
            )
        )
        XCTAssertEqual(
            AppleSpeechPermissionRequestPlan(
                state: AppleSpeechPermissionState(
                    speechRecognition: .denied,
                    microphone: .notDetermined
                )
            ),
            AppleSpeechPermissionRequestPlan(
                requestsSpeechRecognition: false,
                requestsMicrophone: true
            )
        )
        XCTAssertEqual(
            AppleSpeechPermissionRequestPlan(
                state: AppleSpeechPermissionState(
                    speechRecognition: .authorized,
                    microphone: .authorized
                )
            ),
            AppleSpeechPermissionRequestPlan(
                requestsSpeechRecognition: false,
                requestsMicrophone: false
            )
        )
        XCTAssertEqual(
            AppleSpeechPermissionRequestPlan(
                state: AppleSpeechPermissionState(
                    speechRecognition: .denied,
                    microphone: .restricted
                )
            ),
            AppleSpeechPermissionRequestPlan(
                requestsSpeechRecognition: false,
                requestsMicrophone: false
            ),
            "Denied or restricted access must never cause a repeated iOS prompt."
        )
    }

    func testPermissionControllerRequestsSpeechThenMicrophone() async {
        let recorder = PermissionPromptRecorder()
        let controller = AppleSpeechPermissionController(
            checker: StubPermissionChecker(
                state: AppleSpeechPermissionState(
                    speechRecognition: .notDetermined,
                    microphone: .notDetermined
                )
            ),
            speechRecognitionRequest: {
                await recorder.record("speech")
                return .authorized
            },
            microphoneRequest: {
                await recorder.record("microphone")
                return .authorized
            }
        )

        _ = await controller.requestPermissions()

        let events = await recorder.events
        XCTAssertEqual(events, ["speech", "microphone"])
    }

    func testPermissionControllerRejectsOverlappingRequestSequences() async {
        let recorder = PermissionPromptRecorder(delay: .milliseconds(40))
        let controller = AppleSpeechPermissionController(
            checker: StubPermissionChecker(
                state: AppleSpeechPermissionState(
                    speechRecognition: .notDetermined,
                    microphone: .notDetermined
                )
            ),
            speechRecognitionRequest: {
                await recorder.record("speech")
                return .authorized
            },
            microphoneRequest: {
                await recorder.record("microphone")
                return .authorized
            }
        )

        let first = Task { await controller.requestPermissions() }
        while await recorder.events.isEmpty {
            await Task.yield()
        }
        let overlapping = Task { await controller.requestPermissions() }
        _ = await overlapping.value
        _ = await first.value

        let events = await recorder.events
        XCTAssertEqual(events, ["speech", "microphone"])
    }

    func testCancellationAfterFirstPromptPreventsSecondPrompt() async {
        let recorder = PermissionPromptRecorder(delay: .milliseconds(100))
        let controller = AppleSpeechPermissionController(
            checker: StubPermissionChecker(
                state: AppleSpeechPermissionState(
                    speechRecognition: .notDetermined,
                    microphone: .notDetermined
                )
            ),
            speechRecognitionRequest: {
                await recorder.record("speech")
                return .authorized
            },
            microphoneRequest: {
                await recorder.record("microphone")
                return .authorized
            }
        )

        let request = Task { await controller.requestPermissions() }
        while await recorder.events.isEmpty {
            await Task.yield()
        }
        request.cancel()
        _ = await request.value

        let events = await recorder.events
        XCTAssertEqual(events, ["speech"])
    }

    func testSpeechConfigurationReplacesZeroMaximumDuration() {
        let configuration = AppleSpeechRecognitionConfiguration(
            maximumAllowedRecordingDuration: .zero,
            partialResultStabilityDuration: .zero
        )

        XCTAssertEqual(configuration.maximumAllowedRecordingDuration.seconds, 15)
        XCTAssertTrue(configuration.requiresOnDeviceRecognition)
        XCTAssertEqual(
            configuration.partialResultStabilityDuration,
            .milliseconds(1_200)
        )
    }

    func testContextualStringsAlwaysBiasTargetWord() throws {
        let prompt = try WordPrompt(learningMode: .read, text: "two")

        XCTAssertEqual(
            AppleSpeechContextualStringPolicy.strings(for: prompt),
            ["two"]
        )
    }

    func testContextualStringsIncludeValidatedPromptContext() throws {
        let prompt = try WordPrompt(
            learningMode: .read,
            text: "read",
            audioCue: .contextual("Please read this book.")
        )

        XCTAssertEqual(
            AppleSpeechContextualStringPolicy.strings(for: prompt),
            ["read", "Please read this book."]
        )
    }

    func testContextualStringsRejectUnrelatedOrControlCharacterContext() throws {
        let unrelated = try WordPrompt(
            learningMode: .read,
            text: "look",
            audioCue: .contextual("See this book.")
        )
        let controlCharacter = try WordPrompt(
            learningMode: .read,
            text: "look",
            audioCue: .contextual("Please look\nnow.")
        )

        XCTAssertEqual(
            AppleSpeechContextualStringPolicy.strings(for: unrelated),
            ["look"]
        )
        XCTAssertEqual(
            AppleSpeechContextualStringPolicy.strings(for: controlCharacter),
            ["look"]
        )
    }

    func testSpeechServiceFailsClosedWithoutRequestingPermission() async throws {
        let service = AppleSpeechRecognitionService(
            permissionChecker: StubPermissionChecker(
                state: AppleSpeechPermissionState(
                    speechRecognition: .notDetermined,
                    microphone: .authorized
                )
            )
        )
        let prompt = try WordPrompt(learningMode: .read, text: "look")

        let result = try await service.recognize(
            SpeechRecognitionRequest(
                profileID: ProfileID(),
                prompt: prompt,
                maximumRecordingDuration: ElapsedTime(seconds: 2)
            )
        )

        XCTAssertEqual(result.decision, .technicalFailure(.permissionDenied))
        XCTAssertEqual(result.targetSpeakerAssessment, .unavailable)
    }

    func testSpeechErrorsMapToTypedTechnicalFailures() {
        let noAudio = NSError(
            domain: SFSpeechErrorDomain,
            code: SFSpeechError.Code.audioReadFailed.rawValue
        )
        let timeout = NSError(
            domain: SFSpeechErrorDomain,
            code: SFSpeechError.Code.timeout.rawValue
        )
        let malformed = NSError(
            domain: SFSpeechErrorDomain,
            code: SFSpeechError.Code.missingParameter.rawValue
        )
        let unknown = NSError(domain: "example", code: 1)

        XCTAssertEqual(
            AppleSpeechErrorMapper.technicalFailureReason(for: noAudio),
            .noUsableAudio
        )
        XCTAssertEqual(
            AppleSpeechErrorMapper.technicalFailureReason(for: timeout),
            .timedOut
        )
        XCTAssertEqual(
            AppleSpeechErrorMapper.technicalFailureReason(for: malformed),
            .corruptedInput
        )
        XCTAssertEqual(
            AppleSpeechErrorMapper.technicalFailureReason(for: unknown),
            .serviceUnavailable
        )
    }

    func testCommonAppleRuntimeErrorsMapToActionableFailuresAndKeepDiagnostics() {
        let noSpeech = NSError(domain: "kAFAssistantErrorDomain", code: 1110)
        let unauthorized = NSError(domain: "kAFAssistantErrorDomain", code: 1700)
        let interrupted = NSError(domain: "kAFAssistantErrorDomain", code: 1107)
        let missingAssets = NSError(domain: "kLSRErrorDomain", code: 102)

        let noSpeechMapping = AppleSpeechErrorMapper.mapping(for: noSpeech)
        XCTAssertEqual(noSpeechMapping.reason, .noUsableAudio)
        XCTAssertEqual(
            noSpeechMapping.diagnostic,
            AppleSpeechErrorDiagnostic(
                domain: "kAFAssistantErrorDomain",
                code: 1110
            )
        )
        XCTAssertTrue(noSpeechMapping.allowsTranscriptFallback)
        XCTAssertFalse(
            AppleSpeechErrorMapper.mapping(for: unauthorized).allowsTranscriptFallback
        )
        XCTAssertFalse(
            AppleSpeechErrorMapper.mapping(for: missingAssets).allowsTranscriptFallback
        )
        XCTAssertEqual(
            AppleSpeechErrorMapper.technicalFailureReason(for: unauthorized),
            .permissionDenied
        )
        XCTAssertEqual(
            AppleSpeechErrorMapper.technicalFailureReason(for: interrupted),
            .serviceUnavailable
        )
        XCTAssertEqual(
            AppleSpeechErrorMapper.technicalFailureReason(for: missingAssets),
            .onDeviceRecognitionUnavailable
        )
    }

    func testOnDeviceCapabilityFailsClosedInSimulatorOrUnsupportedHardware() {
        XCTAssertEqual(
            AppleSpeechCapabilityPolicy.failureReason(
                requiresOnDeviceRecognition: true,
                isSimulator: true,
                supportsOnDeviceRecognition: true
            ),
            .onDeviceRecognitionUnavailable
        )
        XCTAssertEqual(
            AppleSpeechCapabilityPolicy.failureReason(
                requiresOnDeviceRecognition: true,
                isSimulator: false,
                supportsOnDeviceRecognition: false
            ),
            .onDeviceRecognitionUnavailable
        )
        XCTAssertNil(
            AppleSpeechCapabilityPolicy.failureReason(
                requiresOnDeviceRecognition: true,
                isSimulator: false,
                supportsOnDeviceRecognition: true
            )
        )
        XCTAssertNil(
            AppleSpeechCapabilityPolicy.failureReason(
                requiresOnDeviceRecognition: false,
                isSimulator: true,
                supportsOnDeviceRecognition: false
            )
        )
    }

    func testLatestPartialSupersedesOlderDebounceAndEndsAudioOnce() {
        var endpoint = SpeechRecognitionEndpointStateMachine()
        let first = SpeechTranscriptSnapshot(
            text: "lo",
            confidence: RecognitionConfidence(0.30)
        )
        let latest = SpeechTranscriptSnapshot(
            text: "look",
            confidence: RecognitionConfidence(0.94)
        )

        let firstPartial = endpoint.receive(first, isFinal: false)
        let latestPartial = endpoint.receive(latest, isFinal: false)

        XCTAssertEqual(firstPartial.stabilityGeneration, 1)
        XCTAssertEqual(latestPartial.stabilityGeneration, 2)
        XCTAssertEqual(
            endpoint.stabilityReached(generation: 1),
            .none
        )

        let stable = endpoint.stabilityReached(generation: 2)
        XCTAssertTrue(stable.shouldFinishAudio)
        XCTAssertNil(stable.completion)

        let newerAfterAudioEnded = SpeechTranscriptSnapshot(
            text: "Look",
            confidence: RecognitionConfidence(0.95)
        )
        XCTAssertEqual(
            endpoint.receive(newerAfterAudioEnded, isFinal: false),
            .none
        )

        let final = endpoint.receive(newerAfterAudioEnded, isFinal: true)
        XCTAssertFalse(final.shouldFinishAudio)
        XCTAssertEqual(final.completion, .transcript(newerAfterAudioEnded))
        XCTAssertEqual(endpoint.finishAudioIfNeeded(), .none)
        XCTAssertEqual(
            endpoint.deadlineReached(receivedUsableAudio: true),
            .none
        )
    }

    func testEmptyAndPunctuationOnlyPartialsDoNotArmAutomaticEndpointing() {
        var endpoint = SpeechRecognitionEndpointStateMachine()

        XCTAssertEqual(
            endpoint.receive(
                SpeechTranscriptSnapshot(
                    text: "  …  ",
                    confidence: RecognitionConfidence(0.99)
                ),
                isFinal: false
            ),
            .none
        )
        XCTAssertNil(endpoint.latestTranscript)
        XCTAssertNil(endpoint.activeStabilityGeneration)
        XCTAssertEqual(
            endpoint.deadlineReached(receivedUsableAudio: false),
            SpeechRecognitionEndpointTransition(
                shouldFinishAudio: true,
                completion: .technicalFailure(.noUsableAudio),
                stabilityGeneration: nil
            )
        )
    }

    func testErrorCanFinishWithMeaningfulPartialInsteadOfDiscardingIt() {
        var endpoint = SpeechRecognitionEndpointStateMachine()
        let partial = SpeechTranscriptSnapshot(
            text: "look",
            confidence: RecognitionConfidence(0.91)
        )
        _ = endpoint.receive(partial, isFinal: false)

        let transition = endpoint.fail(
            with: .serviceUnavailable,
            allowingLatestTranscriptFallback: true
        )

        XCTAssertTrue(transition.shouldFinishAudio)
        XCTAssertEqual(transition.completion, .transcript(partial))
    }

    func testDeadlineUsesLatestPartialAndLowConfidenceRemainsUncertain() throws {
        var endpoint = SpeechRecognitionEndpointStateMachine()
        let latest = SpeechTranscriptSnapshot(
            text: "look",
            confidence: RecognitionConfidence(0.30)
        )
        _ = endpoint.receive(latest, isFinal: false)

        let deadline = endpoint.deadlineReached(receivedUsableAudio: true)

        XCTAssertTrue(deadline.shouldFinishAudio)
        XCTAssertEqual(deadline.completion, .transcript(latest))

        let prompt = try WordPrompt(learningMode: .read, text: "look")
        let decision = AppleRecognitionDecisionPolicy(
            thresholds: .speech
        ).evaluate(
            transcript: latest.text,
            confidence: latest.confidence,
            target: prompt
        )
        XCTAssertEqual(decision.decision, .uncertain)
    }

    func testDeadlineDistinguishesNoAudioFromUnrecognizedAudio() {
        var noAudioEndpoint = SpeechRecognitionEndpointStateMachine()
        var unrecognizedAudioEndpoint = SpeechRecognitionEndpointStateMachine()

        XCTAssertEqual(
            noAudioEndpoint.deadlineReached(receivedUsableAudio: false),
            SpeechRecognitionEndpointTransition(
                shouldFinishAudio: true,
                completion: .technicalFailure(.noUsableAudio),
                stabilityGeneration: nil
            )
        )
        XCTAssertEqual(
            unrecognizedAudioEndpoint.deadlineReached(receivedUsableAudio: true),
            SpeechRecognitionEndpointTransition(
                shouldFinishAudio: true,
                completion: .technicalFailure(.timedOut),
                stabilityGeneration: nil
            )
        )
    }

    func testCancellationCompletesOnceAndIgnoresLateCallbacks() {
        var endpoint = SpeechRecognitionEndpointStateMachine()

        let cancelled = endpoint.cancel()

        XCTAssertTrue(cancelled.shouldFinishAudio)
        XCTAssertEqual(cancelled.completion, .cancelled)
        XCTAssertEqual(endpoint.cancel(), .none)
        XCTAssertEqual(
            endpoint.receive(
                SpeechTranscriptSnapshot(
                    text: "late",
                    confidence: RecognitionConfidence(1)
                ),
                isFinal: true
            ),
            .none
        )
    }

    func testCallbackBridgeDeliversFinalAndFinishesAudioExactlyOnce() async {
        let counter = LockedCounter()
        let completionBox = SpeechRecognitionCompletionBox(
            stabilityDelay: .milliseconds(600),
            finishAudio: {
                counter.increment()
            }
        )
        let snapshot = SpeechTranscriptSnapshot(
            text: "look",
            confidence: RecognitionConfidence(0.95)
        )
        let waiter = Task {
            await withCheckedContinuation { continuation in
                completionBox.install(continuation)
            }
        }

        completionBox.receive(snapshot, isFinal: true)
        let completion = await waiter.value
        completionBox.deadlineReached(receivedUsableAudio: true)
        completionBox.finishAudioIfNeeded()

        XCTAssertEqual(completion, .transcript(snapshot))
        XCTAssertEqual(counter.value, 1)
    }

    func testErrorOnlyCallbackUsesPreviouslyReceivedPartialWhenFallbackIsSafe() async {
        let counter = LockedCounter()
        let completionBox = SpeechRecognitionCompletionBox(
            stabilityDelay: .seconds(1),
            finishAudio: {
                counter.increment()
            }
        )
        let partial = SpeechTranscriptSnapshot(
            text: "look",
            confidence: RecognitionConfidence(0.92)
        )
        let waiter = Task {
            await withCheckedContinuation { continuation in
                completionBox.install(continuation)
            }
        }

        completionBox.receive(partial, isFinal: false)
        completionBox.fail(
            with: AppleSpeechErrorMapping(
                reason: .serviceUnavailable,
                diagnostic: AppleSpeechErrorDiagnostic(
                    domain: "kAFAssistantErrorDomain",
                    code: 1107
                )
            )
        )

        let completion = await waiter.value
        XCTAssertEqual(completion, .transcript(partial))
        XCTAssertEqual(counter.value, 1)
    }

    func testStartupSequenceStartsAudioBeforeRecognitionCanCallback() {
        var events: [String] = []

        let taskValue = SpeechRecognitionStartupSequence.start(
            startAudio: {
                events.append("audio")
            },
            startRecognitionTask: {
                events.append("recognition")
                return 42
            }
        )

        XCTAssertEqual(taskValue, 42)
        XCTAssertEqual(events, ["audio", "recognition"])
    }

    func testSpeechActivityGateRejectsSilenceAndAllowsBriefSightWordSpeech() {
        let thresholds = AppleSpeechActivityThresholds.childSightWord
        let silence = SpeechCapturedAudio(
            samples: [Float](repeating: 0, count: 8_000),
            sampleRate: 16_000
        )
        let lowNoise = SpeechCapturedAudio(
            samples: [Float](repeating: 0.002, count: 8_000),
            sampleRate: 16_000
        )
        let tooBrief = voicedAudio(duration: 0.06)
        let briefSightWord = voicedAudio(duration: 0.12)
        let fragmentedNoise = fragmentedVoicedAudio(
            activeFrameDuration: 0.02,
            silenceFrameDuration: 0.02,
            repetitions: 8
        )

        XCTAssertFalse(
            SpeechActivityEvidencePolicy.evaluate(
                silence,
                thresholds: thresholds
            ).hasUsableSpeech
        )
        XCTAssertFalse(
            SpeechActivityEvidencePolicy.evaluate(
                lowNoise,
                thresholds: thresholds
            ).hasUsableSpeech
        )
        XCTAssertFalse(
            SpeechActivityEvidencePolicy.evaluate(
                tooBrief,
                thresholds: thresholds
            ).hasUsableSpeech
        )
        XCTAssertFalse(
            SpeechActivityEvidencePolicy.evaluate(
                fragmentedNoise,
                thresholds: thresholds
            ).hasUsableSpeech
        )
        XCTAssertTrue(
            SpeechActivityEvidencePolicy.evaluate(
                briefSightWord,
                thresholds: thresholds
            ).hasUsableSpeech
        )
    }

    func testMatchingTranscriptNeedsSpeechEvidenceButAcceptsShortWord() throws {
        let resolver = AppleSpeechRecognitionResultResolver(
            decisionPolicy: AppleRecognitionDecisionPolicy(
                thresholds: .speech,
                matchPolicy: .sightWordPronunciation
            ),
            activityThresholds: .childSightWord
        )
        let target = try WordPrompt(learningMode: .read, text: "a")
        let snapshot = SpeechTranscriptSnapshot(
            text: "a",
            confidence: RecognitionConfidence(0.95)
        )

        let silenceResult = resolver.resolve(
            snapshot: snapshot,
            target: target,
            capturedAudio: SpeechCapturedAudio(
                samples: [Float](repeating: 0, count: 8_000),
                sampleRate: 16_000
            ),
            speakerAssessment: .unavailable
        )
        let voicedResult = resolver.resolve(
            snapshot: snapshot,
            target: target,
            capturedAudio: voicedAudio(duration: 0.12),
            speakerAssessment: .unavailable
        )

        XCTAssertEqual(silenceResult.decision, .technicalFailure(.noUsableAudio))
        XCTAssertEqual(voicedResult.decision, .matched)
        XCTAssertEqual(voicedResult.recognizedText, "a")
    }
}

private actor PermissionPromptRecorder {
    private(set) var events: [String] = []
    private let delay: Duration

    init(delay: Duration = .zero) {
        self.delay = delay
    }

    func record(_ event: String) async {
        events.append(event)
        if delay > .zero {
            try? await Task.sleep(for: delay)
        }
    }
}

private func voicedAudio(
    duration: Double,
    amplitude: Float = 0.05,
    sampleRate: Double = 16_000
) -> SpeechCapturedAudio {
    let samples = (0..<Int(duration * sampleRate)).map { index in
        amplitude
            * Float(sin(2 * Double.pi * 220 * Double(index) / sampleRate))
    }
    return SpeechCapturedAudio(samples: samples, sampleRate: sampleRate)
}

private func fragmentedVoicedAudio(
    activeFrameDuration: Double,
    silenceFrameDuration: Double,
    repetitions: Int,
    sampleRate: Double = 16_000
) -> SpeechCapturedAudio {
    let active = voicedAudio(
        duration: activeFrameDuration,
        sampleRate: sampleRate
    ).samples
    let silence = [Float](
        repeating: 0,
        count: Int(silenceFrameDuration * sampleRate)
    )
    let samples = (0..<repetitions).flatMap { _ in active + silence }
    return SpeechCapturedAudio(samples: samples, sampleRate: sampleRate)
}

private struct StubPermissionChecker: AppleSpeechPermissionChecking {
    let state: AppleSpeechPermissionState

    func currentState() -> AppleSpeechPermissionState {
        state
    }
}

private final class LockedCounter: @unchecked Sendable {
    private let lock = NSLock()
    private var count = 0

    var value: Int {
        lock.withLock { count }
    }

    func increment() {
        lock.withLock { count += 1 }
    }
}
