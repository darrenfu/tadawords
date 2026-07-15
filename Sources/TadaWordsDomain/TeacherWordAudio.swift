import Foundation

public enum TeacherWordAudioUsage: String, Codable, Hashable, Sendable {
    case readHint = "read_hint"
    case writePrompt = "write_prompt"
}

/// The only word-pronunciation contract exposed by the app. The bundled pack
/// owns the canonical Cartesia voice; a child profile cannot select or override
/// it. The usage keeps Read and Write pacing explicit without leaking a vendor
/// API into feature code. Read and Write retain separate resource variants even
/// though v3 intentionally gives both the same one-and-a-half-times-slower pace.
public struct TeacherWordAudioRequest: Hashable, Sendable {
    public static let contractVersion = "canonical-teacher-v3"
    public static let practiceSpeed = 0.67

    public let spokenText: String
    public let pronunciationKey: String?
    public let usage: TeacherWordAudioUsage

    public var speed: Double {
        Self.practiceSpeed
    }
    public var voiceContractVersion: String { Self.contractVersion }

    public init(prompt: WordPrompt) {
        spokenText = prompt.audioCue.spokenContext ?? prompt.displayText
        pronunciationKey = prompt.audioCue.pronunciationKey
        usage = prompt.learningMode == .write ? .writePrompt : .readHint
    }

    public init(
        spokenText: String,
        pronunciationKey: String? = nil,
        usage: TeacherWordAudioUsage = .readHint
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
        self.usage = usage
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
    case unavailableOfflineClip
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

/// Tries providers in priority order. This keeps the app offline-first while
/// preserving the existing optional Tada Words backend before Apple TTS takes
/// over. Provider-specific failures are intentionally hidden from the child.
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
            } catch {
                continue
            }
        }
        throw TeacherWordAudioError.unavailableOfflineClip
    }
}
