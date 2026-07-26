import Foundation
import TadaWordsDomain

/// One canonical teacher-audio route shared by Parent preparation, Quest
/// readiness checks, and playback. Network access occurs only in `prepare`;
/// child playback and `requirePrepared` are strictly local.
public actor TeacherWordAudioPipeline:
    TeacherWordAudioProviding,
    TeacherWordAudioPreparing
{
    private let bundled: BundledTeacherWordAudioProvider?
    private let remote: RemoteTeacherWordAudioProvider?
    private let cache: FileTeacherWordAudioCache

    public init(
        endpoint: URL?,
        cacheDirectory: URL?,
        bundled: BundledTeacherWordAudioProvider? =
            BundledTeacherWordAudioProvider.production()
    ) {
        self.bundled = bundled
        remote = endpoint.map(RemoteTeacherWordAudioProvider.init(endpoint:))
        cache = FileTeacherWordAudioCache(directory: cacheDirectory)
    }

    init(
        bundled: BundledTeacherWordAudioProvider?,
        remote: RemoteTeacherWordAudioProvider?,
        cache: FileTeacherWordAudioCache
    ) {
        self.bundled = bundled
        self.remote = remote
        self.cache = cache
    }

    public func audio(
        for request: TeacherWordAudioRequest
    ) async throws -> TeacherWordAudioClip {
        if let bundled {
            do {
                return try await bundled.audio(for: request)
            } catch TeacherWordAudioError.unavailableOfflineClip {
                // A true bundle miss may use the same immutable voice contract
                // from PawGoo. Every other bundle failure remains visible.
            }
        }
        if let cached = try await cache.clip(for: request) {
            return cached
        }
        if await cache.isCatalogMiss(for: request) {
            throw TeacherWordAudioError.catalogMissAppleFallback
        }
        throw TeacherWordAudioError.unavailableOfflineClip
    }

    public func prepare(_ prompts: [WordPrompt]) async throws {
        var firstFailure: (any Error)?
        for prompt in uniquePrompts(prompts) {
            do {
                try await prepare(prompt)
            } catch is CancellationError {
                throw CancellationError()
            } catch {
                // Keep preparing the remaining independent prompts so one
                // transient or corrupt word cannot starve the rest of a Quest.
                if firstFailure == nil {
                    firstFailure = error
                }
            }
        }
        if let firstFailure {
            throw firstFailure
        }
    }

    private func prepare(_ prompt: WordPrompt) async throws {
        let request = TeacherWordAudioRequest(prompt: prompt)
        do {
            _ = try await audio(for: request)
        } catch TeacherWordAudioError.catalogMissAppleFallback {
            return
        } catch TeacherWordAudioError.unavailableOfflineClip {
            guard let remote else {
                throw TeacherWordAudioError.unconfiguredEndpoint
            }
            do {
                let clip = try await remote.audio(for: request)
                try await cache.store(clip, for: request)
            } catch TeacherWordAudioError.serverRejected(statusCode: 422) {
                // PawGoo has authoritatively confirmed that this valid
                // isolated word is outside the online Bella catalog.
                // The word may still be committed; playback will use the
                // device-local Apple English voice.
                try await cache.markCatalogMiss(for: request)
            }
        }
    }

    public func requirePrepared(_ prompts: [WordPrompt]) async throws {
        for prompt in uniquePrompts(prompts) {
            let request = TeacherWordAudioRequest(prompt: prompt)
            if let bundled {
                do {
                    _ = try await bundled.audio(for: request)
                    continue
                } catch TeacherWordAudioError.unavailableOfflineClip {
                    // Check only the device-local immutable cache next.
                }
            }
            if try await cache.clip(for: request) != nil {
                continue
            }
            guard await cache.isCatalogMiss(for: request) else {
                throw TeacherWordAudioError.unavailableOfflineClip
            }
        }
    }

    private func uniquePrompts(_ prompts: [WordPrompt]) -> [WordPrompt] {
        var seen: Set<TeacherWordAudioRequest> = []
        return prompts.filter { prompt in
            seen.insert(TeacherWordAudioRequest(prompt: prompt)).inserted
        }
    }
}
