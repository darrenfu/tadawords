import Foundation
import TadaWordsDomain

public enum BundledTeacherWordAudioProviderError: Error, Equatable, Sendable {
    case missingManifest
    case invalidManifest
}

/// Reads the versioned Katie pack from the Swift package resource bundle.
/// Only isolated alphabetic entries listed in the manifest are accepted;
/// everything else fails closed so the caller can use its Apple TTS fallback.
public struct BundledTeacherWordAudioProvider: TeacherWordAudioProviding {
    private static let productionRelativePath =
        "Audio/TeacherWords/Katie-500-v1"

    private let resourceRoot: URL
    private let words: Set<String>
    private let directories: [TeacherWordAudioUsage: String]

    var bundledWordCount: Int { words.count }

    public init(resourceRoot: URL) throws {
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
            Self.isSafeDirectory(readHint.directory),
            Self.isSafeDirectory(writePrompt.directory)
        else {
            throw BundledTeacherWordAudioProviderError.invalidManifest
        }

        self.resourceRoot = resourceRoot
        words = Set(normalizedWords.compactMap { $0 })
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
            )
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
            .appendingPathExtension("m4a")
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

    private struct Manifest: Decodable {
        let words: [String]
        let variants: [String: Variant]
    }

    private struct Variant: Decodable {
        let directory: String
    }
}
