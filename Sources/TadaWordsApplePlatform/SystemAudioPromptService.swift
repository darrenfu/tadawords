import AVFoundation
import Foundation
import TadaWordsDomain

/// Apple-platform text-to-speech adapter. Feature code depends only on
/// `AudioPromptService`, so recorded human audio can replace this implementation
/// without changing a quest view.
public actor SystemAudioPromptService: AudioPromptService {
    private let synthesizer: AVSpeechSynthesizer
    private let playbackDelegate: SpeechPlaybackDelegate
    private let audioPlaybackDelegate: AudioClipPlaybackDelegate
    private let audioExperienceService: any AudioExperienceService
    private let teacherWordAudioProvider: (any TeacherWordAudioProviding)?
    private let fallbackVoice: AVSpeechSynthesisVoice?
    private var audioPlayer: AVAudioPlayer?

    public init(
        audioExperienceService: any AudioExperienceService =
            SilentAudioExperienceService(),
        teacherWordAudioProvider: (any TeacherWordAudioProviding)? = nil
    ) {
        synthesizer = AVSpeechSynthesizer()
        playbackDelegate = SpeechPlaybackDelegate()
        audioPlaybackDelegate = AudioClipPlaybackDelegate()
        self.audioExperienceService = audioExperienceService
        self.teacherWordAudioProvider = teacherWordAudioProvider
        fallbackVoice = SystemSpeechVoiceResolver.preferredVoice()
        synthesizer.delegate = playbackDelegate
    }

    public func play(_ prompt: WordPrompt, for profileID: ProfileID) async throws {
        _ = profileID
        guard await audioExperienceService.prepareForVoicePrompt() else { return }
        do {
            let spokenText = prompt.audioCue.spokenContext ?? prompt.displayText
            let role: SpokenAudioRole =
                prompt.learningMode == .write ? .writeLearning : .learning
            try await playTeacherAudioOrFallback(
                request: TeacherWordAudioRequest(prompt: prompt),
                fallbackText: spokenText,
                fallbackRole: role
            )
            await audioExperienceService.finishVoicePrompt()
        } catch {
            await audioExperienceService.finishVoicePrompt()
            throw error
        }
    }

    public func playVoiceSetupSentence(
        _ sentence: String,
        for profileID: ProfileID
    ) async throws {
        _ = profileID
        let normalized = sentence.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalized.isEmpty else { return }
        guard await audioExperienceService.prepareForVoicePrompt() else { return }
        do {
            try await playPreparedText(normalized, role: .voiceEnrollment)
            await audioExperienceService.finishVoicePrompt()
        } catch {
            await audioExperienceService.finishVoicePrompt()
            throw error
        }
    }

    private func playTeacherAudioOrFallback(
        request: TeacherWordAudioRequest,
        fallbackText: String,
        fallbackRole: SpokenAudioRole
    ) async throws {
        if let teacherWordAudioProvider {
            do {
                let clip = try await teacherWordAudioProvider.audio(for: request)
                try await playAudioClip(clip)
                return
            } catch {
                if error is CancellationError {
                    throw error
                }
                // A missing endpoint, offline device, or remote playback
                // failure must not block a child's quest. This is explicitly
                // the single Apple system-voice fallback, not ElevenLabs.
            }
        }

        try await playPreparedText(fallbackText, role: fallbackRole)
    }

    private func playPreparedText(
        _ text: String,
        role: SpokenAudioRole
    ) async throws {
        cancelCurrentAudioClip()
        if synthesizer.isSpeaking {
            synthesizer.stopSpeaking(at: .immediate)
        }

        let design = SpeechUtteranceDesignPolicy.design(text: text, role: role)
        let utterance = SpeechUtteranceFactory.make(design: design)
        utterance.voice = fallbackVoice
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

    private func playAudioClip(_ clip: TeacherWordAudioClip) async throws {
        if synthesizer.isSpeaking {
            synthesizer.stopSpeaking(at: .immediate)
        }
        cancelCurrentAudioClip()

        let player = try AVAudioPlayer(data: clip.audioData)
        player.delegate = audioPlaybackDelegate
        player.prepareToPlay()
        audioPlayer = player
        let cancellationToken = SendableAudioPlayer(player)

        do {
            try await withTaskCancellationHandler {
                try await withCheckedThrowingContinuation { continuation in
                    audioPlaybackDelegate.register(
                        continuation: continuation,
                        for: player
                    )
                    guard player.play() else {
                        audioPlaybackDelegate.cancel(
                            player,
                            error: AudioClipPlaybackError.couldNotStart
                        )
                        return
                    }
                }
            } onCancel: {
                Task {
                    await self.cancelAudioPlayback(
                        for: cancellationToken.player
                    )
                }
            }
            audioPlayer = nil
        } catch {
            audioPlayer = nil
            throw error
        }
    }

    private func cancelPlayback(for utterance: AVSpeechUtterance) {
        if synthesizer.isSpeaking {
            synthesizer.stopSpeaking(at: .immediate)
        }
        playbackDelegate.cancel(utterance)
    }

    private func cancelAudioPlayback(for player: AVAudioPlayer) {
        player.stop()
        audioPlaybackDelegate.cancel(player, error: CancellationError())
        if audioPlayer === player {
            audioPlayer = nil
        }
    }

    private func cancelCurrentAudioClip() {
        guard let audioPlayer else { return }
        cancelAudioPlayback(for: audioPlayer)
    }
}

enum SpeechUtteranceFactory {
    static func make(design: SpeechUtteranceDesign) -> AVSpeechUtterance {
        let synthesisText =
            design.addsSentenceBoundary
            ? design.text + "."
            : design.text
        guard let ipaPronunciation = design.ipaPronunciation else {
            return AVSpeechUtterance(string: synthesisText)
        }

        let attributedText = NSMutableAttributedString(string: synthesisText)
        attributedText.addAttribute(
            NSAttributedString.Key(AVSpeechSynthesisIPANotationAttribute),
            value: ipaPronunciation,
            range: NSRange(location: 0, length: (design.text as NSString).length)
        )
        return AVSpeechUtterance(attributedString: attributedText)
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

private struct SendableAudioPlayer: @unchecked Sendable {
    let player: AVAudioPlayer

    init(_ player: AVAudioPlayer) {
        self.player = player
    }
}

private enum AudioClipPlaybackError: Error {
    case couldNotStart
    case decodeFailed
    case playbackFailed
}

private final class AudioClipPlaybackDelegate: NSObject,
    AVAudioPlayerDelegate,
    @unchecked Sendable
{
    private let lock = NSLock()
    private var continuations: [ObjectIdentifier: CheckedContinuation<Void, any Error>] = [:]

    func register(
        continuation: CheckedContinuation<Void, any Error>,
        for player: AVAudioPlayer
    ) {
        let identifier = ObjectIdentifier(player)
        let replacedContinuation = lock.withLock {
            continuations.updateValue(continuation, forKey: identifier)
        }
        replacedContinuation?.resume(throwing: CancellationError())
    }

    func cancel(_ player: AVAudioPlayer, error: any Error) {
        finish(player, result: .failure(error))
    }

    func audioPlayerDidFinishPlaying(
        _ player: AVAudioPlayer,
        successfully flag: Bool
    ) {
        finish(
            player,
            result: flag
                ? .success(())
                : .failure(AudioClipPlaybackError.playbackFailed)
        )
    }

    func audioPlayerDecodeErrorDidOccur(
        _ player: AVAudioPlayer,
        error: (any Error)?
    ) {
        finish(
            player,
            result: .failure(error ?? AudioClipPlaybackError.decodeFailed)
        )
    }

    private func finish(
        _ player: AVAudioPlayer,
        result: Result<Void, any Error>
    ) {
        let continuation = lock.withLock {
            continuations.removeValue(forKey: ObjectIdentifier(player))
        }
        continuation?.resume(with: result)
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
