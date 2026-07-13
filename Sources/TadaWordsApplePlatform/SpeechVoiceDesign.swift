import AVFoundation
import Foundation

/// Platform-neutral metadata used to choose a voice deterministically. Keeping
/// the ranking free of AVFoundation objects makes the fallback behavior easy to
/// test on machines that do not have every optional Apple voice installed.
struct SpeechVoiceCandidate: Hashable, Sendable {
    enum Gender: Hashable, Sendable {
        case female
        case male
        case unspecified
    }

    enum Quality: Int, Hashable, Sendable {
        case standard = 0
        case enhanced = 1
        case premium = 2
    }

    let identifier: String
    let name: String
    let language: String
    let gender: Gender
    let quality: Quality
}

/// Chooses the most expressive suitable system voice without making an
/// optional downloaded voice a launch or practice requirement.
struct VoiceSelectionPolicy: Sendable {
    private let targetLanguage: String
    private let preferredIdentifiers: [String]
    private let preferredNames: [String]

    static let brightAmericanEnglish = VoiceSelectionPolicy(
        targetLanguage: "en-US",
        preferredIdentifiers: [
            "com.apple.voice.premium.en-US.Ava",
            "com.apple.voice.enhanced.en-US.Ava",
            "com.apple.voice.premium.en-US.Samantha",
            "com.apple.voice.enhanced.en-US.Samantha",
            "com.apple.voice.super-compact.en-US.Samantha",
            "com.apple.voice.compact.en-US.Samantha",
        ],
        preferredNames: ["Ava", "Samantha", "Zoe", "Allison", "Nicky", "Susan"]
    )

    init(
        targetLanguage: String,
        preferredIdentifiers: [String],
        preferredNames: [String]
    ) {
        self.targetLanguage = targetLanguage
        self.preferredIdentifiers = preferredIdentifiers
        self.preferredNames = preferredNames
    }

    func select(from candidates: [SpeechVoiceCandidate]) -> SpeechVoiceCandidate? {
        candidates.min { lhs, rhs in
            selectionRank(for: lhs) < selectionRank(for: rhs)
        }
    }

    private func selectionRank(for candidate: SpeechVoiceCandidate) -> SelectionRank {
        let language = normalized(candidate.language)
        let exactLanguage = language == normalized(targetLanguage)
        let englishLanguage = language.hasPrefix("en-") || language == "en"
        let inferredFemale =
            candidate.gender == .female
            || preferredNameRank(candidate.name) < preferredNames.count
        let naturalVoice = !Self.noveltyVoiceNames.contains(
            candidate.name.lowercased(with: Locale(identifier: "en_US_POSIX"))
        )

        let suitabilityRank: Int
        switch (exactLanguage, englishLanguage, inferredFemale, naturalVoice) {
        case (true, _, true, true): suitabilityRank = 0
        case (true, _, _, true): suitabilityRank = 1
        case (true, _, _, false): suitabilityRank = 2
        case (_, true, true, true): suitabilityRank = 3
        case (_, true, _, true): suitabilityRank = 4
        case (_, true, _, false): suitabilityRank = 5
        case (_, _, true, true): suitabilityRank = 6
        case (_, _, _, true): suitabilityRank = 7
        default: suitabilityRank = 8
        }

        return SelectionRank(
            suitability: suitabilityRank,
            quality: 2 - candidate.quality.rawValue,
            identifierPreference: preferredIdentifierRank(candidate.identifier),
            namePreference: preferredNameRank(candidate.name),
            stableIdentifier: candidate.identifier.lowercased(
                with: Locale(identifier: "en_US_POSIX")
            )
        )
    }

    private func preferredIdentifierRank(_ identifier: String) -> Int {
        preferredIdentifiers.firstIndex(of: identifier) ?? preferredIdentifiers.count
    }

    private func preferredNameRank(_ name: String) -> Int {
        preferredNames.firstIndex {
            $0.compare(name, options: [.caseInsensitive, .diacriticInsensitive]) == .orderedSame
        } ?? preferredNames.count
    }

    private func normalized(_ language: String) -> String {
        language.replacingOccurrences(of: "_", with: "-").lowercased()
    }

    private static let noveltyVoiceNames: Set<String> = [
        "albert", "bad news", "bahh", "bells", "boing", "bubbles",
        "cellos", "good news", "jester", "organ", "superstar",
        "trinoids", "whisper", "wobble", "zarvox",
    ]

    private struct SelectionRank: Comparable {
        let suitability: Int
        let quality: Int
        let identifierPreference: Int
        let namePreference: Int
        let stableIdentifier: String

        static func < (lhs: SelectionRank, rhs: SelectionRank) -> Bool {
            if lhs.suitability != rhs.suitability {
                return lhs.suitability < rhs.suitability
            }
            if lhs.quality != rhs.quality {
                return lhs.quality < rhs.quality
            }
            if lhs.identifierPreference != rhs.identifierPreference {
                return lhs.identifierPreference < rhs.identifierPreference
            }
            if lhs.namePreference != rhs.namePreference {
                return lhs.namePreference < rhs.namePreference
            }
            return lhs.stableIdentifier < rhs.stableIdentifier
        }
    }
}

enum SpokenAudioRole: Hashable, Sendable {
    case brand
    case learning
}

/// A pure description of delivery. The learning role deliberately keeps the
/// supplied word or context byte-for-byte intact so voice styling cannot change
/// what the child is asked to hear or learn.
struct SpeechUtteranceDesign: Equatable, Sendable {
    let text: String
    let rate: Float
    let pitchMultiplier: Float
    let volume: Float
    let preUtteranceDelay: TimeInterval
    let postUtteranceDelay: TimeInterval
}

enum SpeechUtteranceDesignPolicy {
    static func design(text: String, role: SpokenAudioRole) -> SpeechUtteranceDesign {
        switch role {
        case .brand:
            SpeechUtteranceDesign(
                text: text,
                rate: 0.54,
                pitchMultiplier: 1.16,
                volume: 0.84,
                preUtteranceDelay: 0.025,
                postUtteranceDelay: 0.055
            )
        case .learning:
            SpeechUtteranceDesign(
                text: text,
                rate: 0.46,
                pitchMultiplier: 1.08,
                volume: 0.82,
                preUtteranceDelay: 0.045,
                postUtteranceDelay: 0.075
            )
        }
    }
}

enum SystemSpeechVoiceResolver {
    static func preferredVoice(
        policy: VoiceSelectionPolicy = .brightAmericanEnglish
    ) -> AVSpeechSynthesisVoice? {
        var voicesByIdentifier: [String: AVSpeechSynthesisVoice] = [:]
        for voice in AVSpeechSynthesisVoice.speechVoices() {
            voicesByIdentifier[voice.identifier] = voice
        }
        let candidates = voicesByIdentifier.values.map {
            SpeechVoiceCandidate(voice: $0)
        }

        if let choice = policy.select(from: candidates),
            let voice = voicesByIdentifier[choice.identifier]
        {
            return voice
        }

        // A missing enhanced/premium download is expected. Asking the OS for
        // its language default still produces speech, and a nil voice lets the
        // utterance use the device-wide default rather than failing playback.
        return AVSpeechSynthesisVoice(language: "en-US")
    }
}

extension SpeechVoiceCandidate {
    fileprivate init(voice: AVSpeechSynthesisVoice) {
        let gender: Gender
        switch voice.gender {
        case .female: gender = .female
        case .male: gender = .male
        default: gender = .unspecified
        }

        let quality: Quality
        switch voice.quality.rawValue {
        case 3...: quality = .premium
        case 2: quality = .enhanced
        default: quality = .standard
        }

        self.init(
            identifier: voice.identifier,
            name: voice.name,
            language: voice.language,
            gender: gender,
            quality: quality
        )
    }
}
