import Foundation

/// The only word-pronunciation contract exposed by the app. The service owns
/// the canonical ElevenLabs voice and its credentials; a child profile cannot
/// select or override either one.
public struct TeacherWordAudioRequest: Hashable, Sendable {
    /// ElevenLabs currently accepts speeds from 0.7 through 1.2. The slowest
    /// supported value is closest to the requested 1.5x-slower delivery.
    public static let canonicalSpeed = 0.7
    public static let contractVersion = "canonical-teacher-v1"

    public let spokenText: String
    public let pronunciationKey: String?

    public var speed: Double { Self.canonicalSpeed }
    public var voiceContractVersion: String { Self.contractVersion }

    public init(prompt: WordPrompt) {
        spokenText = prompt.audioCue.spokenContext ?? prompt.displayText
        pronunciationKey = prompt.audioCue.pronunciationKey
    }

    public init(
        spokenText: String,
        pronunciationKey: String? = nil
    ) throws {
        let normalizedText = spokenText.trimmingCharacters(
            in: .whitespacesAndNewlines
        )
        guard !normalizedText.isEmpty else {
            throw TeacherWordAudioError.emptySpokenText
        }

        self.spokenText = normalizedText
        self.pronunciationKey = pronunciationKey?.trimmingCharacters(
            in: .whitespacesAndNewlines
        )
    }
}

public struct TeacherWordAudioClip: Equatable, Sendable {
    public static let maximumByteCount = 5 * 1_024 * 1_024

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
    case unconfiguredEndpoint
    case invalidEndpoint
    case invalidResponse
    case emptyAudio
    case responseTooLarge(maximumByteCount: Int)
    case serverRejected(statusCode: Int)
    case unsupportedContentType(String?)
}

public protocol TeacherWordAudioProviding: Sendable {
    func audio(
        for request: TeacherWordAudioRequest
    ) async throws -> TeacherWordAudioClip
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

/// Adds a best-effort cache without making a cache failure block practice.
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
        try? await cache.store(downloaded, for: request)
        return downloaded
    }
}
