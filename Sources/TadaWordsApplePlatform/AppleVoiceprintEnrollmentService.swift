@preconcurrency import AVFoundation
import Foundation
import TadaWordsDomain

public enum AppleVoiceprintEnrollmentError: Error, Equatable, Sendable {
    case permissionDenied
    case sessionNotStarted
    case sessionNotReady
    case audioUnavailable
}

struct VoiceprintRecordingAudioCoordinator: Sendable {
    let audioExperienceService: any AudioExperienceService

    func capture<Value: Sendable>(
        _ operation: @escaping @Sendable () async throws -> Value
    ) async throws -> Value {
        await audioExperienceService.prepareForRecording()
        do {
            let value = try await operation()
            await audioExperienceService.finishRecording()
            return value
        } catch {
            await audioExperienceService.finishRecording()
            throw error
        }
    }
}

public actor AppleVoiceprintEnrollmentService: DeviceVoiceprintEnrolling {
    private static let captureDuration: Duration = .milliseconds(3_400)

    private let repository: any DeviceVoiceprintRepository
    private let extractor: any VoiceprintEmbeddingExtracting
    private let permissionChecker: any AppleSpeechPermissionChecking
    private let clock: any AppClock
    private let recordingAudioCoordinator: VoiceprintRecordingAudioCoordinator

    private var session: VoiceprintEnrollmentSession?

    public init(
        repository: any DeviceVoiceprintRepository,
        extractor: any VoiceprintEmbeddingExtracting = AppleVoiceprintFeatureExtractor(),
        permissionChecker: any AppleSpeechPermissionChecking =
            SystemAppleSpeechPermissionChecker(),
        clock: any AppClock = SystemAppClock(),
        audioExperienceService: any AudioExperienceService =
            SilentAudioExperienceService()
    ) {
        self.repository = repository
        self.extractor = extractor
        self.permissionChecker = permissionChecker
        self.clock = clock
        recordingAudioCoordinator = VoiceprintRecordingAudioCoordinator(
            audioExperienceService: audioExperienceService
        )
    }

    public func begin(
        profileID: ProfileID
    ) async throws -> VoiceprintEnrollmentProgress {
        guard permissionChecker.currentState().isAuthorized else {
            throw AppleVoiceprintEnrollmentError.permissionDenied
        }
        let enrollment = try VoiceprintEnrollmentSession(
            profileID: profileID,
            modelIdentifier: extractor.modelIdentifier,
            policy: .oneMinuteRegistration
        )
        session = enrollment
        return enrollment.progress
    }

    public func captureSegment() async throws -> VoiceprintEnrollmentStepResult {
        guard var session else {
            throw AppleVoiceprintEnrollmentError.sessionNotStarted
        }

        let captured: SpeechCapturedAudio
        do {
            captured = try await recordingAudioCoordinator.capture {
                try await self.captureAudio()
            }
        } catch {
            if error is CancellationError {
                throw error
            }
            throw AppleVoiceprintEnrollmentError.audioUnavailable
        }
        let duration = ElapsedTime(
            seconds: Double(captured.samples.count) / captured.sampleRate
        )
        let rejection: VoiceprintSegmentRejectionReason?
        do {
            let embedding = try extractor.embedding(
                from: captured.samples,
                sampleRate: captured.sampleRate
            )
            rejection = session.accept(
                embedding: embedding,
                speechDuration: duration
            )
        } catch AppleVoiceprintFeatureExtractorError.insufficientSpeech {
            rejection = session.reject(.noSpeech)
        } catch {
            rejection = session.reject(.technicalFailure)
        }
        self.session = session
        return VoiceprintEnrollmentStepResult(
            progress: session.progress,
            rejectionReason: rejection
        )
    }

    public func finalize() async throws -> DeviceVoiceprintTemplate {
        guard let session else {
            throw AppleVoiceprintEnrollmentError.sessionNotStarted
        }
        guard session.progress.isReadyToFinalize else {
            throw AppleVoiceprintEnrollmentError.sessionNotReady
        }
        let template = try session.makeTemplate(enrolledAt: clock.now)
        try await repository.save(template)
        self.session = nil
        return template
    }

    public func cancel() async {
        session = nil
    }

    private func captureAudio() async throws -> SpeechCapturedAudio {
        #if os(iOS)
            // Configure and activate the session before asking AVAudioEngine
            // for an input format. Reversing this order can yield a zero-rate
            // format after ambient music or TTS owned the previous session.
            let audioSession = AVAudioSession.sharedInstance()
            try audioSession.setCategory(
                .playAndRecord,
                mode: .voiceChat,
                options: [.duckOthers, .allowBluetoothHFP, .defaultToSpeaker]
            )
            try audioSession.setPreferredSampleRate(44_100)
            try audioSession.setPreferredIOBufferDuration(0.012)
            try audioSession.setActive(true)
        #endif

        let engine = AVAudioEngine()
        let input = engine.inputNode
        var voiceProcessingEnabled = false
        #if os(iOS)
            do {
                try input.setVoiceProcessingEnabled(true)
                voiceProcessingEnabled = input.isVoiceProcessingEnabled
            } catch {
                // Some Bluetooth routes do not expose the voice-processing
                // input unit. Enrollment can still use their raw PCM.
            }
        #endif
        let format = input.outputFormat(forBus: 0)
        guard format.sampleRate > 0, format.channelCount > 0 else {
            #if os(iOS)
                try? AVAudioSession.sharedInstance().setActive(
                    false,
                    options: .notifyOthersOnDeactivation
                )
            #endif
            throw AppleVoiceprintEnrollmentError.audioUnavailable
        }
        let collector = VoiceprintPCMCollector(
            sampleRate: format.sampleRate,
            maximumDuration: 5
        )

        input.installTap(
            onBus: 0,
            bufferSize: 1_024,
            format: format
        ) { buffer, _ in
            collector.append(buffer)
        }
        defer {
            input.removeTap(onBus: 0)
            engine.stop()
            #if os(iOS)
                if voiceProcessingEnabled {
                    try? input.setVoiceProcessingEnabled(false)
                }
                try? AVAudioSession.sharedInstance().setActive(
                    false,
                    options: .notifyOthersOnDeactivation
                )
            #endif
        }

        engine.prepare()
        try engine.start()
        try await Task.sleep(for: Self.captureDuration)
        try Task.checkCancellation()
        return collector.snapshot()
    }
}

private final class VoiceprintPCMCollector: @unchecked Sendable {
    private let lock = NSLock()
    private let sampleRate: Double
    private let maximumSampleCount: Int
    private var samples: [Float] = []

    init(sampleRate: Double, maximumDuration: Double) {
        self.sampleRate = sampleRate
        maximumSampleCount = Int(sampleRate * maximumDuration)
        samples.reserveCapacity(maximumSampleCount)
    }

    func append(_ buffer: AVAudioPCMBuffer) {
        lock.withLock {
            guard let channels = buffer.floatChannelData else { return }
            let remaining = maximumSampleCount - samples.count
            guard remaining > 0 else { return }
            let count = min(Int(buffer.frameLength), remaining)
            samples.append(
                contentsOf: UnsafeBufferPointer(start: channels[0], count: count)
            )
        }
    }

    func snapshot() -> SpeechCapturedAudio {
        lock.withLock {
            SpeechCapturedAudio(samples: samples, sampleRate: sampleRate)
        }
    }
}
