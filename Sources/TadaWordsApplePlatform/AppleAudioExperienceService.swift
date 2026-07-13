@preconcurrency import AVFoundation
import Foundation
import TadaWordsDomain

/// Original, programmatic sound layer. It uses no sampled or downloaded audio.
/// The three world scores and all effects are synthesized in memory.
public actor AppleAudioExperienceService: AudioExperienceService {
    private static let sampleRate = 44_100.0

    private let engine = AVAudioEngine()
    private let ambientPlayerA = AVAudioPlayerNode()
    private let ambientPlayerB = AVAudioPlayerNode()
    private let effectPlayer = AVAudioPlayerNode()
    private let launchVoice = AVSpeechSynthesizer()
    private let spokenVoice = SystemSpeechVoiceResolver.preferredVoice()

    private var world: WorldTheme = .moonpetalKingdom
    private var preferences = AudioPreferences.default
    private var didPlayLaunchSignature = false
    private var isApplicationActive = true
    private var wantsAmbientAudio = false
    private var isEmergencyMode = false
    private var voicePromptDepth = 0
    private var recordingDepth = 0
    private var activeAmbientIndex = 0
    private var ambientMixFactors: [Float] = [0, 0]
    private var ambientTransitionTask: Task<Void, Never>?
    private var transitionGate = AmbientTransitionGate()
    private var ambientBufferCache = AmbientBufferCache<AVAudioPCMBuffer>()

    public init() {
        engine.attach(ambientPlayerA)
        engine.attach(ambientPlayerB)
        engine.attach(effectPlayer)
        let format = AVAudioFormat(
            standardFormatWithSampleRate: Self.sampleRate,
            channels: 2
        )
        engine.connect(ambientPlayerA, to: engine.mainMixerNode, format: format)
        engine.connect(ambientPlayerB, to: engine.mainMixerNode, format: format)
        engine.connect(effectPlayer, to: engine.mainMixerNode, format: format)
        engine.mainMixerNode.outputVolume = 0.72
    }

    public func playLaunchSignature() async {
        guard !didPlayLaunchSignature else { return }
        didPlayLaunchSignature = true
        guard preferences.voiceEnabled || preferences.soundEffectsEnabled else { return }
        let shouldSpeakLaunchVoice = preferences.voiceEnabled

        if AudioPreferencePolicy.allowsDecorativeSoundEffects(
            preferences: preferences
        ), startEngineIfNeeded() {
            effectPlayer.stop()
            effectPlayer.volume = adjustedVolume(0.18)
            effectPlayer.scheduleBuffer(
                ProceduralAudioFactory.launchSignature(
                    world: world,
                    sampleRate: Self.sampleRate
                ),
                at: nil,
                options: [],
                completionCallbackType: .dataConsumed,
                completionHandler: nil
            )
            effectPlayer.play()
        }

        if shouldSpeakLaunchVoice {
            voicePromptDepth += 1
            applyAmbientVolume()
            let design = SpeechUtteranceDesignPolicy.design(
                text: "Tada Words!",
                role: .brand
            )
            let utterance = AVSpeechUtterance(string: design.text)
            utterance.voice = spokenVoice
            utterance.rate = design.rate
            utterance.pitchMultiplier = design.pitchMultiplier
            utterance.volume = design.volume
            utterance.preUtteranceDelay = design.preUtteranceDelay
            utterance.postUtteranceDelay = design.postUtteranceDelay
            launchVoice.speak(utterance)
        }

        try? await Task.sleep(for: .milliseconds(1_250))
        if shouldSpeakLaunchVoice {
            voicePromptDepth = max(0, voicePromptDepth - 1)
            applyAmbientVolume()
        }
    }

    public func configure(
        world: WorldTheme,
        preferences: AudioPreferences
    ) async {
        guard
            AmbientMixPolicy.configurationDecision(
                ambientIsClaimedByChildSession: wantsAmbientAudio
            ) == .apply
        else {
            // Root activation owns the live score. A slower launch task must
            // never overwrite or stop that remembered-profile session.
            return
        }
        ambientBufferCache.select(world: world)
        self.world = world
        self.preferences = preferences
        applyPreferenceSideEffects()
    }

    public func activate(
        world: WorldTheme,
        preferences: AudioPreferences
    ) async {
        let scoreChanged = self.world != world
        let musicWasEnabled = self.preferences.musicEnabled
        ambientBufferCache.select(world: world)
        self.world = world
        self.preferences = preferences
        wantsAmbientAudio = true
        applyPreferenceSideEffects()

        let decision = AmbientMixPolicy.activationDecision(
            shouldPlay: shouldPlayAmbient,
            scoreChanged: scoreChanged,
            musicWasEnabled: musicWasEnabled,
            activePlayerIsPlaying: activeAmbientPlayer.isPlaying
        )
        switch decision {
        case .stop:
            stopAllAmbientPlayers()
        case .transition(let duration):
            transitionToCurrentScore(duration: duration)
        case .updateVolume:
            applyAmbientVolume()
        }
    }

    public func stopAmbientAudio() async {
        wantsAmbientAudio = false
        isEmergencyMode = false
        stopAllAmbientPlayers()
    }

    public func play(_ cue: FunctionalAudioCue) async {
        guard AudioPreferencePolicy.shouldPlay(cue, preferences: preferences),
            recordingDepth == 0,
            isApplicationActive
        else {
            return
        }
        guard startEngineIfNeeded() else { return }
        effectPlayer.stop()
        effectPlayer.volume = adjustedVolume(0.20)
        effectPlayer.scheduleBuffer(
            ProceduralAudioFactory.effect(
                cue: cue,
                world: world,
                sampleRate: Self.sampleRate
            ),
            at: nil,
            options: [],
            completionCallbackType: .dataConsumed,
            completionHandler: nil
        )
        effectPlayer.play()
    }

    public func setEmergencyMode(_ isEnabled: Bool) async {
        let effectiveValue = AudioPreferencePolicy.emergencyLayerIsEnabled(
            requested: isEnabled,
            preferences: preferences
        )
        guard isEmergencyMode != effectiveValue else { return }
        isEmergencyMode = effectiveValue
        guard shouldPlayAmbient else { return }
        transitionToCurrentScore(duration: AmbientMixPolicy.crossfadeDuration)
    }

    public func prepareForVoicePrompt() async -> Bool {
        guard preferences.voiceEnabled else { return false }
        voicePromptDepth += 1
        applyAmbientVolume()
        return true
    }

    public func finishVoicePrompt() async {
        voicePromptDepth = max(0, voicePromptDepth - 1)
        applyAmbientVolume()
    }

    public func prepareForRecording() async {
        recordingDepth += 1
        guard recordingDepth == 1 else { return }
        cancelAmbientTransition()

        let starts = ambientMixFactors
        for step in 1...AmbientMixPolicy.recordingFadeSteps {
            let remaining = 1 - Float(step) / Float(AmbientMixPolicy.recordingFadeSteps)
            ambientMixFactors = starts.map { $0 * remaining }
            applyAmbientVolume()
            try? await Task.sleep(
                for: .seconds(
                    AmbientMixPolicy.recordingFadeDuration
                        / Double(AmbientMixPolicy.recordingFadeSteps)
                )
            )
        }
        stopAllAmbientPlayers()
        effectPlayer.stop()
        engine.stop()
        deactivateAudioSession()
    }

    public func finishRecording() async {
        recordingDepth = max(0, recordingDepth - 1)
        guard recordingDepth == 0, shouldPlayAmbient else { return }
        transitionToCurrentScore(duration: AmbientMixPolicy.fadeInDuration)
    }

    public func setApplicationActive(_ isActive: Bool) async {
        self.isApplicationActive = isActive
        if isActive, shouldPlayAmbient {
            transitionToCurrentScore(duration: AmbientMixPolicy.fadeInDuration)
        } else {
            stopAllAmbientPlayers()
            effectPlayer.stop()
        }
    }

    private var ambientPlayers: [AVAudioPlayerNode] {
        [ambientPlayerA, ambientPlayerB]
    }

    private var activeAmbientPlayer: AVAudioPlayerNode {
        ambientPlayers[activeAmbientIndex]
    }

    private var shouldPlayAmbient: Bool {
        isApplicationActive && wantsAmbientAudio && preferences.musicEnabled
            && recordingDepth == 0
    }

    private func transitionToCurrentScore(duration: Double) {
        guard shouldPlayAmbient else { return }
        guard startEngineIfNeeded() else {
            stopAllAmbientPlayers()
            return
        }

        let outgoingIndex = activeAmbientIndex
        let incomingIndex = 1 - outgoingIndex
        let outgoingStartFactor = ambientMixFactors[outgoingIndex]
        let incomingPlayer = ambientPlayers[incomingIndex]
        incomingPlayer.stop()
        let scoreKey = AmbientScoreKey(
            world: world,
            isEmergency: isEmergencyMode
        )
        let scoreBuffer = ambientBufferCache.value(for: scoreKey) {
            ProceduralAudioFactory.ambientLoop(
                world: scoreKey.world,
                sampleRate: Self.sampleRate,
                emergency: scoreKey.isEmergency
            )
        }
        incomingPlayer.scheduleBuffer(
            scoreBuffer,
            at: nil,
            options: .loops
        )
        ambientMixFactors[incomingIndex] = 0
        applyAmbientVolume()
        incomingPlayer.play()
        activeAmbientIndex = incomingIndex

        ambientTransitionTask?.cancel()
        let generation = transitionGate.begin()
        let stepCount = AmbientMixPolicy.transitionSteps
        let stepDuration = duration / Double(stepCount)
        ambientTransitionTask = Task { [weak self] in
            for step in 1...stepCount {
                do {
                    try await Task.sleep(for: .seconds(stepDuration))
                } catch {
                    return
                }
                await self?.applyTransitionStep(
                    step: step,
                    stepCount: stepCount,
                    outgoingIndex: outgoingIndex,
                    incomingIndex: incomingIndex,
                    outgoingStartFactor: outgoingStartFactor,
                    generation: generation
                )
            }
        }
    }

    private func applyTransitionStep(
        step: Int,
        stepCount: Int,
        outgoingIndex: Int,
        incomingIndex: Int,
        outgoingStartFactor: Float,
        generation: Int
    ) {
        guard transitionGate.accepts(generation), shouldPlayAmbient else { return }
        let gains = AmbientMixPolicy.crossfadeGains(
            progress: Double(step) / Double(stepCount)
        )
        ambientMixFactors[outgoingIndex] = outgoingStartFactor * gains.outgoing
        ambientMixFactors[incomingIndex] = gains.incoming
        applyAmbientVolume()
        if step == stepCount {
            ambientPlayers[outgoingIndex].stop()
            ambientMixFactors[outgoingIndex] = 0
            applyAmbientVolume()
        }
    }

    private func applyAmbientVolume() {
        let baseVolume =
            shouldPlayAmbient
            ? adjustedVolume(
                AmbientMixPolicy.baseVolume(isVoicePromptActive: voicePromptDepth > 0)
            )
            : 0
        for index in ambientPlayers.indices {
            ambientPlayers[index].volume = baseVolume * ambientMixFactors[index]
        }
    }

    private func cancelAmbientTransition() {
        ambientTransitionTask?.cancel()
        ambientTransitionTask = nil
        transitionGate.cancel()
    }

    private func stopAllAmbientPlayers() {
        cancelAmbientTransition()
        ambientPlayerA.stop()
        ambientPlayerB.stop()
        ambientMixFactors = [0, 0]
    }

    private func applyPreferenceSideEffects() {
        isEmergencyMode = AudioPreferencePolicy.emergencyLayerIsEnabled(
            requested: isEmergencyMode,
            preferences: preferences
        )
        if !preferences.voiceEnabled, launchVoice.isSpeaking {
            launchVoice.stopSpeaking(at: .immediate)
        }
        if !preferences.soundEffectsEnabled {
            effectPlayer.stop()
        }
    }

    private func adjustedVolume(_ volume: Float) -> Float {
        preferences.reducedSoundEnabled ? volume * 0.55 : volume
    }

    private func startEngineIfNeeded() -> Bool {
        guard !engine.isRunning else { return true }
        do {
            try activateAudioSession()
            engine.prepare()
            try engine.start()
            return engine.isRunning
        } catch {
            // Audio is supportive feedback. A route/session failure must never
            // block word practice. Leaving both players stopped also ensures
            // a later activation retries engine startup instead of mistaking
            // a scheduled-but-silent node for live music.
            return false
        }
    }

    private func activateAudioSession() throws {
        #if os(iOS)
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.ambient, mode: .default, options: [.mixWithOthers])
            try session.setActive(true)
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
}
