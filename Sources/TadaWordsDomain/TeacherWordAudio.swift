import Foundation

public enum TeacherWordAudioUsage: String, Codable, Hashable, Sendable {
    case readHint = "read_hint"
    case writePrompt = "write_prompt"
}

/// The only word-pronunciation contract exposed by the app. It contains one
/// normalized isolated word and never carries the prompt's sentence context.
/// The version freezes the server-owned voice, model, dictionary, encoding,
/// vendor speed, and client playback rate as one indivisible contract.
public struct TeacherWordAudioRequest: Hashable, Sendable {
    public static let contractVersion = "elevenlabs-teacher-v1"
    public static let vendorSpeed = 0.70
    public static let clientPlaybackRate = 20.0 / 21.0
    public static let practiceSpeed = 2.0 / 3.0

    public let spokenText: String
    public let pronunciationKey: String?
    public let usage: TeacherWordAudioUsage

    public var speed: Double {
        Self.practiceSpeed
    }
    public var voiceContractVersion: String { Self.contractVersion }

    public init(prompt: WordPrompt) {
        spokenText = Self.normalize(prompt.displayText)
        pronunciationKey = prompt.audioCue.pronunciationKey
        usage = prompt.learningMode == .write ? .writePrompt : .readHint
    }

    public init(
        spokenText: String,
        pronunciationKey: String? = nil,
        usage: TeacherWordAudioUsage = .readHint
    ) throws {
        let normalizedText = Self.normalize(spokenText)
        guard !normalizedText.isEmpty else {
            throw TeacherWordAudioError.emptySpokenText
        }
        guard Self.isSupportedIsolatedWord(normalizedText) else {
            throw TeacherWordAudioError.invalidIsolatedWord
        }

        self.spokenText = normalizedText
        self.pronunciationKey = pronunciationKey?.trimmingCharacters(
            in: .whitespacesAndNewlines
        )
        self.usage = usage
    }

    private static func normalize(_ value: String) -> String {
        value
            .precomposedStringWithCanonicalMapping
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased(with: Locale(identifier: "en-US"))
    }

    private static func isSupportedIsolatedWord(_ value: String) -> Bool {
        guard !value.isEmpty, value.count <= 32 else { return false }
        return value.range(
            of: #"^[a-z]+(?:['-][a-z]+)*$"#,
            options: .regularExpression
        ) != nil
    }
}

public struct TeacherWordAudioClip: Equatable, Sendable {
    public static let maximumByteCount = 2 * 1_024 * 1_024

    public let audioData: Data

    public init(audioData: Data) throws {
        guard !audioData.isEmpty else {
            throw TeacherWordAudioError.emptyAudio
        }
        guard audioData.count <= Self.maximumByteCount else {
            throw TeacherWordAudioError.responseTooLarge(
                maximumByteCount: Self.maximumByteCount
            )
        }
        self.audioData = audioData
    }
}

public enum TeacherWordAudioError: Error, Equatable, Sendable {
    case emptySpokenText
    case invalidIsolatedWord
    case unconfiguredEndpoint
    case invalidEndpoint
    case invalidResponse
    case emptyAudio
    case responseTooLarge(maximumByteCount: Int)
    case serverRejected(statusCode: Int)
    case unsupportedContentType(String?)
    case unavailableOfflineClip
    case catalogMissAppleFallback
    case persistentCacheUnavailable
    case appAttestUnavailable
    case invalidAudioChecksum
    case mismatchedAudioContract
}

public protocol TeacherWordAudioProviding: Sendable {
    func audio(
        for request: TeacherWordAudioRequest
    ) async throws -> TeacherWordAudioClip
}

/// Parent flows may fetch clips, while child Quest planning may only verify
/// that the exact local clip is already present. Neither operation receives a
/// Profile identifier.
public protocol TeacherWordAudioPreparing: Sendable {
    func prepare(_ prompts: [WordPrompt]) async throws
    func requirePrepared(_ prompts: [WordPrompt]) async throws
}

public protocol TeacherWordAudioCaching: Sendable {
    func clip(
        for request: TeacherWordAudioRequest
    ) async throws -> TeacherWordAudioClip?

    func store(
        _ clip: TeacherWordAudioClip,
        for request: TeacherWordAudioRequest
    ) async throws
}

/// Resolves from the exact local cache or downloads and durably stores the
/// canonical clip before reporting success. A failed store stays visible to
/// callers; parent import flows may treat preparation as best effort so any
/// valid word remains addable and playback can use Apple speech fallback.
public actor CachingTeacherWordAudioProvider: TeacherWordAudioProviding {
    private let upstream: any TeacherWordAudioProviding
    private let cache: any TeacherWordAudioCaching

    public init(
        upstream: any TeacherWordAudioProviding,
        cache: any TeacherWordAudioCaching
    ) {
        self.upstream = upstream
        self.cache = cache
    }

    public func audio(
        for request: TeacherWordAudioRequest
    ) async throws -> TeacherWordAudioClip {
        if let cached = try? await cache.clip(for: request) {
            return cached
        }

        let downloaded = try await upstream.audio(for: request)
        try await cache.store(downloaded, for: request)
        return downloaded
    }
}

/// Uses the next provider only for a genuine pack miss. Corrupt clips, network
/// failures, authentication failures, and provider rejection are surfaced
/// instead of silently changing the child's teacher voice.
public actor FirstAvailableTeacherWordAudioProvider: TeacherWordAudioProviding {
    private let providers: [any TeacherWordAudioProviding]

    public init(providers: [any TeacherWordAudioProviding]) {
        precondition(!providers.isEmpty)
        self.providers = providers
    }

    public func audio(
        for request: TeacherWordAudioRequest
    ) async throws -> TeacherWordAudioClip {
        for provider in providers {
            do {
                return try await provider.audio(for: request)
            } catch is CancellationError {
                throw CancellationError()
            } catch TeacherWordAudioError.unavailableOfflineClip {
                continue
            }
        }
        throw TeacherWordAudioError.unavailableOfflineClip
    }
}
