import Foundation

enum AmbientMixPolicy {
    static let normalVolume: Float = 0.105
    static let duckedVolume: Float = 0.018
    static let crossfadeDuration = 0.72
    static let fadeInDuration = 0.42
    static let recordingFadeDuration = 0.10
    static let transitionSteps = 12
    static let recordingFadeSteps = 6

    static func baseVolume(isVoicePromptActive: Bool) -> Float {
        isVoicePromptActive ? duckedVolume : normalVolume
    }

    static func crossfadeGains(progress: Double) -> (outgoing: Float, incoming: Float) {
        let clamped = Float(max(0, min(1, progress)))
        return (1 - clamped, clamped)
    }

    static func activationDecision(
        shouldPlay: Bool,
        scoreChanged: Bool,
        musicWasEnabled: Bool,
        activePlayerIsPlaying: Bool
    ) -> AmbientActivationDecision {
        guard shouldPlay else { return .stop }
        guard musicWasEnabled, activePlayerIsPlaying else {
            return .transition(duration: fadeInDuration)
        }
        if scoreChanged {
            return .transition(duration: crossfadeDuration)
        }
        return .updateVolume
    }

    static func configurationDecision(
        ambientIsClaimedByChildSession: Bool
    ) -> AmbientConfigurationDecision {
        ambientIsClaimedByChildSession ? .preserveActiveSession : .apply
    }
}

enum AmbientActivationDecision: Equatable, Sendable {
    case stop
    case transition(duration: Double)
    case updateVolume
}

enum AmbientConfigurationDecision: Equatable, Sendable {
    case apply
    case preserveActiveSession
}

/// A tiny generation gate prevents an older async fade from writing volumes
/// after a newer world/emergency/recording transition has superseded it.
struct AmbientTransitionGate: Sendable {
    private(set) var generation = 0

    mutating func begin() -> Int {
        generation += 1
        return generation
    }

    mutating func cancel() {
        generation += 1
    }

    func accepts(_ candidate: Int) -> Bool {
        candidate == generation
    }
}
