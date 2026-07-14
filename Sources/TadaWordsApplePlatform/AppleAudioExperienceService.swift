@preconcurrency import AVFoundation
import Foundation
import TadaWordsDomain

struct WritingCueThrottle {
    /// Longer than the longest writing texture, so accepted cues never queue
    /// or cut one another off while a finger is moving quickly.
    static let minimumInterval: TimeInterval = 0.11

    private(set) var lastAcceptedTime: TimeInterval?

    mutating func accepts(at time: TimeInterval) -> Bool {
        guard let lastAcceptedTime else {
            self.lastAcceptedTime = time
            return true
        }
        guard time >= lastAcceptedTime else {
            self.lastAcceptedTime = time
            return true
        }
        guard time - lastAcceptedTime >= Self.minimumInterval else { return false }
        self.lastAcceptedTime = time
        return true
    }

    mutating func reset() {
        lastAcceptedTime = nil
    }
}

struct AppAudioSessionPolicy: Equatable, Sendable {
    enum Category: Equatable, Sendable {
        case ambient
        case playback
    }

    enum Mode: Equatable, Sendable {
        case defaultMode
        case spokenAudio
    }

    struct Options: OptionSet, Sendable {
        let rawValue: Int

        static let mixesWithOthers = Options(rawValue: 1 << 0)
        static let ducksOthers = Options(rawValue: 1 << 1)
    }

    let category: Category
    let mode: Mode
    let options: Options

    static let ambientMix = AppAudioSessionPolicy(
        category: .ambient,
        mode: .defaultMode,
        options: [.mixesWithOthers]
    )

    static let spokenPrompt = AppAudioSessionPolicy(
        category: .playback,
        mode: .spokenAudio,
        options: [.mixesWithOthers, .ducksOthers]
    )
}

struct VoicePromptAudioSessionState {
    private(set) var depth = 0

    var isActive: Bool { depth > 0 }

    mutating func begin() -> AppAudioSessionPolicy? {
        let policy = depth == 0 ? AppAudioSessionPolicy.spokenPrompt : nil
        depth += 1
        return policy
    }

    mutating func finish() -> AppAudioSessionPolicy? {
        guard depth > 0 else { return nil }
        depth -= 1
        return depth == 0 ? .ambientMix : nil
    }
}

/// Hybrid audio layer. Original world scores and effects remain synthesized in
/// memory; the launch mark and brief transition voices come from the versioned
/// Aurora bundle and never require a runtime network request.
public actor AppleAudioExperienceService: AudioExperienceService {
    private static let sampleRate = 44_100.0

    private let engine = AVAudioEngine()
    private let ambientPlayerA = AVAudioPlayerNode()
    private let ambientPlayerB = AVAudioPlayerNode()
    private let effectPlayer = AVAudioPlayerNode()
    private let writingPlayer = AVAudioPlayerNode()
    private let launchVoice = AVSpeechSynthesizer()
    private let spokenVoice = SystemSpeechVoiceResolver.preferredVoice()
    private let voiceAccentLibrary: BundledVoiceAccentLibrary

    private var world: WorldTheme = .moonpetalKingdom
    private var preferences = AudioPreferences.default
    private var didPlayLaunchSignature = false
    private var isApplicationActive = true
    private var wantsAmbientAudio = false
    private var isEmergencyMode = false
    private var voicePromptAudioSessionState = VoicePromptAudioSessionState()
    private var recordingDepth = 0
    private var activeAmbientIndex = 0
    private var ambientMixFactors: [Float] = [0, 0]
    private var ambientTransitionTask: Task<Void, Never>?
    private var transitionGate = AmbientTransitionGate()
    private var ambientBufferCache = AmbientBufferCache<AVAudioPCMBuffer>()
    private var writingCueThrottle = WritingCueThrottle()
    private var writingBuffers: [HandwritingTool: AVAudioPCMBuffer] = [:]
    private var spokenAccentPlayer: AVAudioPlayer?
    private var spokenAccentGeneration = 0
    private var spokenAccentOwnsVoicePrompt = false
    private var correctAccentIndex = 0

    public init() {
        voiceAccentLibrary = .production()
        engine.attach(ambientPlayerA)
        engine.attach(ambientPlayerB)
        engine.attach(effectPlayer)
        engine.attach(writingPlayer)
        let format = AVAudioFormat(
            standardFormatWithSampleRate: Self.sampleRate,
            channels: 2
        )
        engine.connect(ambientPlayerA, to: engine.mainMixerNode, format: format)
        engine.connect(ambientPlayerB, to: engine.mainMixerNode, format: format)
        engine.connect(effectPlayer, to: engine.mainMixerNode, format: format)
        engine.connect(writingPlayer, to: engine.mainMixerNode, format: format)
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
            if let launch = voiceAccentLibrary.launch,
                await playSpokenAccent(at: launch)
            {
                return
            }

            // Apple TTS is a fail-safe for a damaged or unavailable bundle,
            // not the normal launch voice.
            beginVoicePrompt()
            let design = LaunchVoiceDesignPolicy.utterance
            let utterance =
                AVSpeechUtterance(
                    ssmlRepresentation: LaunchVoiceDesignPolicy.ssmlRepresentation
                ) ?? AVSpeechUtterance(string: design.text)
            utterance.voice = spokenVoice
            utterance.rate = design.rate
            utterance.pitchMultiplier = design.pitchMultiplier
            utterance.volume = design.volume
            utterance.preUtteranceDelay = design.preUtteranceDelay
            utterance.postUtteranceDelay = design.postUtteranceDelay
            launchVoice.speak(utterance)
            try? await Task.sleep(for: .milliseconds(1_600))
            endVoicePrompt()
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
        stopWritingAudio()
        stopSpokenAccent()
    }

    public func play(_ cue: FunctionalAudioCue) async {
        guard recordingDepth == 0,
            isApplicationActive
        else {
            return
        }
        if case .writing(let tool) = cue {
            guard AudioPreferencePolicy.shouldPlay(cue, preferences: preferences)
            else { return }
            playWritingCue(for: tool)
            return
        }

        if AudioPreferencePolicy.shouldPlay(cue, preferences: preferences),
            startEngineIfNeeded()
        {
            stopWritingAudio()
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

        guard let accentURL = spokenAccentURL(for: cue) else { return }
        _ = await playSpokenAccent(at: accentURL)
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
        stopWritingAudio()
        beginVoicePrompt()
        return true
    }

    public func finishVoicePrompt() async {
        endVoicePrompt()
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
        stopWritingAudio()
        stopSpokenAccent()
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
            stopWritingAudio()
            stopSpokenAccent()
        }
    }

    private func spokenAccentURL(for cue: FunctionalAudioCue) -> URL? {
        guard SpokenAccentPolicy.allows(cue, preferences: preferences) else {
            return nil
        }

        switch cue {
        case .correct:
            guard !voiceAccentLibrary.correct.isEmpty else { return nil }
            let url = voiceAccentLibrary.correct[
                correctAccentIndex % voiceAccentLibrary.correct.count
            ]
            correctAccentIndex =
                (correctAccentIndex + 1)
                % voiceAccentLibrary.correct.count
            return url
        case .reward:
            return voiceAccentLibrary.questComplete
        case .click, .validRetry, .technicalRetry, .star, .writing:
            return nil
        }
    }

    @discardableResult
    private func playSpokenAccent(at url: URL) async -> Bool {
        stopSpokenAccent()
        guard let player = try? AVAudioPlayer(contentsOf: url) else { return false }
        player.volume = adjustedVolume(0.84)
        player.prepareToPlay()

        spokenAccentGeneration += 1
        let generation = spokenAccentGeneration
        spokenAccentPlayer = player
        beginVoicePrompt()
        spokenAccentOwnsVoicePrompt = true

        guard player.play() else {
            stopSpokenAccent()
            return false
        }

        let duration = max(0.1, player.duration + 0.05)
        try? await Task.sleep(for: .seconds(duration))
        guard generation == spokenAccentGeneration else { return true }
        stopSpokenAccent()
        return true
    }

    private func stopSpokenAccent() {
        spokenAccentGeneration += 1
        spokenAccentPlayer?.stop()
        spokenAccentPlayer = nil
        if spokenAccentOwnsVoicePrompt {
            spokenAccentOwnsVoicePrompt = false
            endVoicePrompt()
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
                AmbientMixPolicy.baseVolume(
                    isVoicePromptActive: voicePromptAudioSessionState.isActive
                )
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
        if !preferences.voiceEnabled || preferences.reducedSoundEnabled {
            stopSpokenAccent()
        }
        if !preferences.soundEffectsEnabled {
            effectPlayer.stop()
        }
        if !AudioPreferencePolicy.shouldPlay(
            .writing(tool: .pencil),
            preferences: preferences
        ) {
            stopWritingAudio()
        }
    }

    private func stopWritingAudio() {
        writingPlayer.stop()
        writingCueThrottle.reset()
    }

    private func playWritingCue(for tool: HandwritingTool) {
        guard !voicePromptAudioSessionState.isActive else { return }
        guard
            writingCueThrottle.accepts(
                at: ProcessInfo.processInfo.systemUptime
            )
        else { return }
        guard startEngineIfNeeded() else { return }

        writingPlayer.volume = adjustedVolume(0.18)
        let buffer: AVAudioPCMBuffer
        if let cached = writingBuffers[tool] {
            buffer = cached
        } else {
            let rendered = ProceduralAudioFactory.writingEffect(
                tool: tool,
                sampleRate: Self.sampleRate
            )
            writingBuffers[tool] = rendered
            buffer = rendered
        }
        writingPlayer.scheduleBuffer(
            buffer,
            at: nil,
            options: [],
            completionCallbackType: .dataConsumed,
            completionHandler: nil
        )
        if !writingPlayer.isPlaying {
            writingPlayer.play()
        }
    }

    private func adjustedVolume(_ volume: Float) -> Float {
        preferences.reducedSoundEnabled ? volume * 0.55 : volume
    }

    private func beginVoicePrompt() {
        let policy = voicePromptAudioSessionState.begin()
        applyAmbientVolume()
        if let policy, recordingDepth == 0 {
            // A route or category failure must never prevent the prompt from
            // reaching AVSpeechSynthesizer or AVAudioPlayer.
            try? applyAudioSessionPolicy(policy)
        }
    }

    private func endVoicePrompt() {
        let policy = voicePromptAudioSessionState.finish()
        if let policy, recordingDepth == 0 {
            // Restore the app's normal mixable score only after the outermost
            // prompt. An active recorder owns the session until it finishes.
            // Keep teardown best-effort for the same reason as setup.
            try? applyAudioSessionPolicy(policy)
        }
        applyAmbientVolume()
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
        let policy: AppAudioSessionPolicy =
            voicePromptAudioSessionState.isActive ? .spokenPrompt : .ambientMix
        try applyAudioSessionPolicy(policy)
    }

    private func applyAudioSessionPolicy(_ policy: AppAudioSessionPolicy) throws {
        #if os(iOS)
            let session = AVAudioSession.sharedInstance()
            let category: AVAudioSession.Category =
                switch policy.category {
                case .ambient: .ambient
                case .playback: .playback
                }
            let mode: AVAudioSession.Mode =
                switch policy.mode {
                case .defaultMode: .default
                case .spokenAudio: .spokenAudio
                }
            var options: AVAudioSession.CategoryOptions = []
            if policy.options.contains(.mixesWithOthers) {
                options.insert(.mixWithOthers)
            }
            if policy.options.contains(.ducksOthers) {
                options.insert(.duckOthers)
            }
            try session.setCategory(category, mode: mode, options: options)
            try session.setActive(true)
        #else
            _ = policy
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
