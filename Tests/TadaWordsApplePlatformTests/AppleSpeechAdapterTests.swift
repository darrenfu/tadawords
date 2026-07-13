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

    func testSpeechConfigurationReplacesZeroMaximumDuration() {
        let configuration = AppleSpeechRecognitionConfiguration(
            maximumAllowedRecordingDuration: .zero,
            partialResultStabilityDuration: .zero
        )

        XCTAssertEqual(configuration.maximumAllowedRecordingDuration.seconds, 15)
        XCTAssertTrue(configuration.requiresOnDeviceRecognition)
        XCTAssertEqual(
            configuration.partialResultStabilityDuration,
            .milliseconds(600)
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
            endpoint.deadlineReached(receivedAudioBuffer: true),
            .none
        )
    }

    func testDeadlineUsesLatestPartialAndLowConfidenceRemainsUncertain() throws {
        var endpoint = SpeechRecognitionEndpointStateMachine()
        let latest = SpeechTranscriptSnapshot(
            text: "look",
            confidence: RecognitionConfidence(0.30)
        )
        _ = endpoint.receive(latest, isFinal: false)

        let deadline = endpoint.deadlineReached(receivedAudioBuffer: true)

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
            noAudioEndpoint.deadlineReached(receivedAudioBuffer: false),
            SpeechRecognitionEndpointTransition(
                shouldFinishAudio: true,
                completion: .technicalFailure(.noUsableAudio),
                stabilityGeneration: nil
            )
        )
        XCTAssertEqual(
            unrecognizedAudioEndpoint.deadlineReached(receivedAudioBuffer: true),
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
        completionBox.deadlineReached(receivedAudioBuffer: true)
        completionBox.finishAudioIfNeeded()

        XCTAssertEqual(completion, .transcript(snapshot))
        XCTAssertEqual(counter.value, 1)
    }
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
