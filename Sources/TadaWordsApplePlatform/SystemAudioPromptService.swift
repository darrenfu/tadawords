import AVFoundation
import Foundation
import TadaWordsDomain

/// Apple-platform text-to-speech adapter. Feature code depends only on
/// `AudioPromptService`, so recorded human audio can replace this implementation
/// without changing a quest view.
public actor SystemAudioPromptService: AudioPromptService {
    private let synthesizer: AVSpeechSynthesizer
    private let playbackDelegate: SpeechPlaybackDelegate
    private let audioExperienceService: any AudioExperienceService
    private let voice: AVSpeechSynthesisVoice?

    public init(
        audioExperienceService: any AudioExperienceService =
            SilentAudioExperienceService()
    ) {
        synthesizer = AVSpeechSynthesizer()
        playbackDelegate = SpeechPlaybackDelegate()
        self.audioExperienceService = audioExperienceService
        voice = SystemSpeechVoiceResolver.preferredVoice()
        synthesizer.delegate = playbackDelegate
    }

    public func play(_ prompt: WordPrompt, for profileID: ProfileID) async throws {
        _ = profileID
        guard await audioExperienceService.prepareForVoicePrompt() else { return }
        do {
            try await playPreparedPrompt(prompt)
            await audioExperienceService.finishVoicePrompt()
        } catch {
            await audioExperienceService.finishVoicePrompt()
            throw error
        }
    }

    private func playPreparedPrompt(_ prompt: WordPrompt) async throws {
        if synthesizer.isSpeaking {
            synthesizer.stopSpeaking(at: .immediate)
        }

        let spokenText = prompt.audioCue.spokenContext ?? prompt.displayText
        let role: SpokenAudioRole =
            prompt.learningMode == .write ? .writeLearning : .learning
        let design = SpeechUtteranceDesignPolicy.design(
            text: spokenText,
            role: role
        )
        let utterance = AVSpeechUtterance(string: design.text)
        utterance.voice = voice
        utterance.rate = design.rate
        utterance.pitchMultiplier = design.pitchMultiplier
        utterance.volume = design.volume
        utterance.preUtteranceDelay = design.preUtteranceDelay
        utterance.postUtteranceDelay = design.postUtteranceDelay
        let cancellationToken = SendableSpeechUtterance(utterance)

        try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                playbackDelegate.register(
                    continuation: continuation,
                    for: utterance
                )
                synthesizer.speak(utterance)
            }
        } onCancel: {
            Task {
                await self.cancelPlayback(for: cancellationToken.utterance)
            }
        }
    }

    private func cancelPlayback(for utterance: AVSpeechUtterance) {
        if synthesizer.isSpeaking {
            synthesizer.stopSpeaking(at: .immediate)
        }
        playbackDelegate.cancel(utterance)
    }
}

/// AVSpeechUtterance is immutable for the lifetime of one playback after its
/// configuration is complete. This wrapper carries that identity only across
/// the cancellation callback back into the owning actor.
private struct SendableSpeechUtterance: @unchecked Sendable {
    let utterance: AVSpeechUtterance

    init(_ utterance: AVSpeechUtterance) {
        self.utterance = utterance
    }
}

/// Bridges Objective-C speech callbacks into structured concurrency. The lock
/// protects only continuation ownership; playback policy remains actor-owned.
private final class SpeechPlaybackDelegate: NSObject,
    AVSpeechSynthesizerDelegate,
    @unchecked Sendable
{
    private let lock = NSLock()
    private var continuations: [ObjectIdentifier: CheckedContinuation<Void, any Error>] = [:]

    func register(
        continuation: CheckedContinuation<Void, any Error>,
        for utterance: AVSpeechUtterance
    ) {
        let identifier = ObjectIdentifier(utterance)
        let replacedContinuation = lock.withLock {
            continuations.updateValue(continuation, forKey: identifier)
        }
        replacedContinuation?.resume(throwing: CancellationError())
    }

    func cancel(_ utterance: AVSpeechUtterance) {
        finish(utterance, result: .failure(CancellationError()))
    }

    func speechSynthesizer(
        _ synthesizer: AVSpeechSynthesizer,
        didFinish utterance: AVSpeechUtterance
    ) {
        _ = synthesizer
        finish(utterance, result: .success(()))
    }

    func speechSynthesizer(
        _ synthesizer: AVSpeechSynthesizer,
        didCancel utterance: AVSpeechUtterance
    ) {
        _ = synthesizer
        finish(utterance, result: .failure(CancellationError()))
    }

    private func finish(
        _ utterance: AVSpeechUtterance,
        result: Result<Void, any Error>
    ) {
        let continuation = lock.withLock {
            continuations.removeValue(forKey: ObjectIdentifier(utterance))
        }
        continuation?.resume(with: result)
    }
}
