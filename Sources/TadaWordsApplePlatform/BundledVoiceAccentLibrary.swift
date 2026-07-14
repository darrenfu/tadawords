import Foundation
import TadaWordsDomain

enum SpokenAccentPolicy {
    static func allows(
        _ cue: FunctionalAudioCue,
        preferences: AudioPreferences
    ) -> Bool {
        guard preferences.voiceEnabled, !preferences.reducedSoundEnabled else {
            return false
        }
        return switch cue {
        case .correct, .reward: true
        case .click, .validRetry, .technicalRetry, .star, .writing: false
        }
    }
}

struct BundledVoiceAccentLibrary: Sendable {
    private static let productionRelativePath =
        "Audio/VoiceAccents/Aurora-v1"

    let launch: URL?
    let correct: [URL]
    let questComplete: URL?

    static func production() -> Self {
        guard let resourceURL = Bundle.module.resourceURL else {
            return Self(launch: nil, correct: [], questComplete: nil)
        }
        return Self(
            resourceRoot: resourceURL.appendingPathComponent(
                productionRelativePath,
                isDirectory: true
            )
        )
    }

    init(resourceRoot: URL) {
        let manifestURL = resourceRoot.appendingPathComponent("manifest.json")
        guard
            let data = try? Data(contentsOf: manifestURL),
            let manifest = try? JSONDecoder().decode(Manifest.self, from: data)
        else {
            self.init(launch: nil, correct: [], questComplete: nil)
            return
        }

        let launch = Self.validURL(for: manifest.launch.file, under: resourceRoot)
        let correct = manifest.correct.compactMap {
            Self.validURL(for: $0.file, under: resourceRoot)
        }
        let questComplete = Self.validURL(
            for: manifest.questComplete.file,
            under: resourceRoot
        )
        self.init(
            launch: launch,
            correct: correct,
            questComplete: questComplete
        )
    }

    init(launch: URL?, correct: [URL], questComplete: URL?) {
        self.launch = launch
        self.correct = correct
        self.questComplete = questComplete
    }

    private static func validURL(
        for relativePath: String,
        under root: URL
    ) -> URL? {
        guard
            !relativePath.isEmpty,
            !relativePath.hasPrefix("/"),
            !relativePath.split(separator: "/").contains("..")
        else { return nil }
        let url = root.appendingPathComponent(relativePath)
        guard FileManager.default.fileExists(atPath: url.path) else { return nil }
        return url
    }

    private struct Manifest: Decodable {
        let launch: Clip
        let correct: [Clip]
        let questComplete: Clip

        private enum CodingKeys: String, CodingKey {
            case launch
            case correct
            case questComplete = "quest_complete"
        }
    }

    private struct Clip: Decodable {
        let file: String
    }
}
