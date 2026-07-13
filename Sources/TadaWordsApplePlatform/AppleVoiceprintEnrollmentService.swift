@preconcurrency import AVFoundation
import Foundation
import TadaWordsDomain

public enum AppleVoiceprintEnrollmentError: Error, Equatable, Sendable {
    case permissionDenied
    case sessionNotStarted
    case sessionNotReady
    case audioUnavailable
}

public actor AppleVoiceprintEnrollmentService: DeviceVoiceprintEnrolling {
    private static let captureDuration: Duration = .milliseconds(2_700)

    private let repository: any DeviceVoiceprintRepository
    private let extractor: any VoiceprintEmbeddingExtracting
    private let permissionChecker: any AppleSpeechPermissionChecking
    private let clock: any AppClock

    private var session: VoiceprintEnrollmentSession?

    public init(
        repository: any DeviceVoiceprintRepository,
        extractor: any VoiceprintEmbeddingExtracting = AppleVoiceprintFeatureExtractor(),
        permissionChecker: any AppleSpeechPermissionChecking =
            SystemAppleSpeechPermissionChecker(),
        clock: any AppClock = SystemAppClock()
    ) {
        self.repository = repository
        self.extractor = extractor
        self.permissionChecker = permissionChecker
        self.clock = clock
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

        let captured = try await captureAudio()
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
        let engine = AVAudioEngine()
        let input = engine.inputNode
        let format = input.outputFormat(forBus: 0)
        guard format.sampleRate > 0, format.channelCount > 0 else {
            throw AppleVoiceprintEnrollmentError.audioUnavailable
        }
        let collector = VoiceprintPCMCollector(
            sampleRate: format.sampleRate,
            maximumDuration: 5
        )

        #if os(iOS)
            let audioSession = AVAudioSession.sharedInstance()
            try audioSession.setCategory(
                .record,
                mode: .measurement,
                options: [.duckOthers]
            )
            try audioSession.setActive(true)
        #endif

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
