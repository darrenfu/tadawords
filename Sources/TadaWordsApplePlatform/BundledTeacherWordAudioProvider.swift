import Foundation
import TadaWordsDomain

public enum BundledTeacherWordAudioProviderError: Error, Equatable, Sendable {
    case missingManifest
    case invalidManifest
}

/// Reads the versioned canonical teacher pack from the Swift package resource
/// bundle.
/// Only isolated alphabetic entries listed in the manifest are accepted;
/// everything else fails closed so the canonical remote/cache pipeline can
/// prepare the exact same voice contract.
public struct BundledTeacherWordAudioProvider: TeacherWordAudioProviding {
    private static let productionRelativePath =
        "Audio/TeacherWords/ElevenLabs-Teacher-500-v1"

    private let resourceRoot: URL
    private let words: Set<String>
    private let directories: [TeacherWordAudioUsage: String]
    private let fileExtension: String

    var bundledWordCount: Int { words.count }

    public init(resourceRoot: URL) throws {
        try self.init(
            resourceRoot: resourceRoot,
            requiresCanonicalContract: false
        )
    }

    init(
        resourceRoot: URL,
        requiresCanonicalContract: Bool
    ) throws {
        let manifestURL = resourceRoot.appendingPathComponent("manifest.json")
        guard FileManager.default.fileExists(atPath: manifestURL.path) else {
            throw BundledTeacherWordAudioProviderError.missingManifest
        }

        let manifest: Manifest
        do {
            manifest = try JSONDecoder().decode(
                Manifest.self,
                from: Data(contentsOf: manifestURL)
            )
        } catch {
            throw BundledTeacherWordAudioProviderError.invalidManifest
        }

        let normalizedWords = manifest.words.map(Self.normalizedWord)
        guard
            normalizedWords.allSatisfy({ $0 != nil }),
            Set(normalizedWords.compactMap { $0 }).count == manifest.words.count,
            let readHint = manifest.variants[TeacherWordAudioUsage.readHint.rawValue],
            let writePrompt = manifest.variants[
                TeacherWordAudioUsage.writePrompt.rawValue
            ],
            !requiresCanonicalContract || manifest.isCanonicalTeacherContract,
            Self.isSafeDirectory(readHint.directory),
            Self.isSafeDirectory(writePrompt.directory),
            let fileExtension = Self.fileExtension(
                for: manifest.audioFormat?.container
            )
        else {
            throw BundledTeacherWordAudioProviderError.invalidManifest
        }

        self.resourceRoot = resourceRoot
        words = Set(normalizedWords.compactMap { $0 })
        self.fileExtension = fileExtension
        directories = [
            .readHint: readHint.directory,
            .writePrompt: writePrompt.directory,
        ]
    }

    public static func production() -> Self? {
        guard let resourceURL = Bundle.module.resourceURL else { return nil }
        return try? Self(
            resourceRoot: resourceURL.appendingPathComponent(
                productionRelativePath,
                isDirectory: true
            ),
            requiresCanonicalContract: true
        )
    }

    public func audio(
        for request: TeacherWordAudioRequest
    ) async throws -> TeacherWordAudioClip {
        guard
            request.pronunciationKey == nil,
            let word = Self.normalizedWord(request.spokenText),
            words.contains(word),
            let directory = directories[request.usage]
        else {
            throw TeacherWordAudioError.unavailableOfflineClip
        }

        let fileURL =
            resourceRoot
            .appendingPathComponent(directory, isDirectory: true)
            .appendingPathComponent(word)
            .appendingPathExtension(fileExtension)
        guard FileManager.default.fileExists(atPath: fileURL.path) else {
            throw TeacherWordAudioError.unavailableOfflineClip
        }

        return try TeacherWordAudioClip(
            audioData: Data(contentsOf: fileURL, options: .mappedIfSafe)
        )
    }

    private static func normalizedWord(_ text: String) -> String? {
        let normalized = text.trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
        guard
            !normalized.isEmpty,
            normalized.unicodeScalars.allSatisfy({
                CharacterSet.lowercaseLetters.contains($0)
            })
        else { return nil }
        return normalized
    }

    private static func isSafeDirectory(_ directory: String) -> Bool {
        !directory.isEmpty
            && !directory.contains("/")
            && !directory.contains("..")
    }

    private static func fileExtension(for container: String?) -> String? {
        switch container?.lowercased() {
        case nil, "m4a":
            "m4a"
        case "mp3":
            "mp3"
        default:
            nil
        }
    }

    private struct Manifest: Decodable {
        let vendor: String?
        let model: String?
        let voice: Voice?
        let seed: Int?
        let providerSpeed: Double?
        let providerSentenceBoundary: String?
        let providerTailBreakSeconds: Double?
        let releasePostProcessing: ReleasePostProcessing?
        let clientPlaybackRate: Double?
        let pronunciationDictionary: PronunciationDictionary?
        let words: [String]
        let variants: [String: Variant]
        let audioFormat: AudioFormat?

        private enum CodingKeys: String, CodingKey {
            case vendor
            case model
            case voice
            case seed
            case providerSpeed = "provider_speed"
            case providerSentenceBoundary = "provider_sentence_boundary"
            case providerTailBreakSeconds = "provider_tail_break_seconds"
            case releasePostProcessing = "release_post_processing"
            case clientPlaybackRate = "client_playback_rate"
            case pronunciationDictionary = "pronunciation_dictionary"
            case words
            case variants
            case audioFormat = "audio_format"
        }

        var isCanonicalTeacherContract: Bool {
            vendor == "ElevenLabs"
                && model == "eleven_multilingual_v2"
                && voice?.id == "hpp4J3VqNfWAUOO0d1Us"
                && voice?.approval == "approved"
                && seed == 20_260_725
                && providerSpeed == 0.70
                && providerSentenceBoundary == ""
                && providerTailBreakSeconds == 0
                && releasePostProcessing?.peakDBFS == -3
                && releasePostProcessing?.tailPaddingSeconds == 0.12
                && releasePostProcessing?.encoder == "libmp3lame"
                && clientPlaybackRate.map {
                    abs($0 - TeacherWordAudioRequest.clientPlaybackRate) < 0.000_001
                } == true
                && pronunciationDictionary?.id == "jlikgZytU86rmsPnDwrK"
                && pronunciationDictionary?.versionID
                    == "E2NROj7X6ZT7VcK11GgH"
                && pronunciationDictionary?.rulesSHA256
                    == "422ff6c9b6571fd4f3ab80a1a4d52411cc91effb946de476d668863fc747b537"
                && audioFormat?.container == "mp3"
                && audioFormat?.providerOutputFormat == "mp3_44100_128"
                && audioFormat?.bitrateKbps == 128
                && audioFormat?.sampleRateHz == 44_100
                && audioFormat?.channels == 1
        }
    }

    private struct Variant: Decodable {
        let directory: String
    }

    private struct Voice: Decodable {
        let id: String
        let approval: String
    }

    private struct ReleasePostProcessing: Decodable {
        let peakDBFS: Double
        let tailPaddingSeconds: Double
        let encoder: String

        private enum CodingKeys: String, CodingKey {
            case peakDBFS = "peak_dbfs"
            case tailPaddingSeconds = "tail_padding_seconds"
            case encoder
        }
    }

    private struct PronunciationDictionary: Decodable {
        let id: String
        let versionID: String
        let rulesSHA256: String

        private enum CodingKeys: String, CodingKey {
            case id
            case versionID = "version_id"
            case rulesSHA256 = "rules_sha256"
        }
    }

    private struct AudioFormat: Decodable {
        let container: String
        let providerOutputFormat: String?
        let bitrateKbps: Int?
        let sampleRateHz: Int?
        let channels: Int?

        private enum CodingKeys: String, CodingKey {
            case container
            case providerOutputFormat = "provider_output_format"
            case bitrateKbps = "bitrate_kbps"
            case sampleRateHz = "sample_rate_hz"
            case channels
        }
    }
}
