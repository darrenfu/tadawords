import CryptoKit
@preconcurrency import Foundation
import TadaWordsDomain

/// Calls a Tada Words-owned audio endpoint. The endpoint is responsible for
/// holding the ElevenLabs API key and canonical voice ID; neither value is
/// represented by this client API or sent from the iOS app.
public struct RemoteTeacherWordAudioProvider: TeacherWordAudioProviding {
    typealias DataLoader = @Sendable (URLRequest) async throws -> (Data, URLResponse)

    private let endpoint: URL?
    private let dataLoader: DataLoader

    public init(endpoint: URL?) {
        self.endpoint = endpoint
        dataLoader = { request in
            try await URLSession.shared.data(for: request)
        }
    }

    init(
        endpoint: URL?,
        dataLoader: @escaping DataLoader
    ) {
        self.endpoint = endpoint
        self.dataLoader = dataLoader
    }

    public func audio(
        for request: TeacherWordAudioRequest
    ) async throws -> TeacherWordAudioClip {
        guard let endpoint else {
            throw TeacherWordAudioError.unconfiguredEndpoint
        }
        guard endpoint.scheme?.lowercased() == "https" else {
            throw TeacherWordAudioError.invalidEndpoint
        }

        var urlRequest = URLRequest(url: endpoint)
        urlRequest.httpMethod = "POST"
        urlRequest.timeoutInterval = 15
        urlRequest.cachePolicy = .reloadIgnoringLocalCacheData
        urlRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
        urlRequest.setValue("audio/mpeg", forHTTPHeaderField: "Accept")
        urlRequest.httpBody = try JSONEncoder().encode(
            RequestPayload(request: request)
        )

        let (data, response) = try await dataLoader(urlRequest)
        guard let response = response as? HTTPURLResponse else {
            throw TeacherWordAudioError.invalidResponse
        }
        guard (200...299).contains(response.statusCode) else {
            throw TeacherWordAudioError.serverRejected(
                statusCode: response.statusCode
            )
        }

        let contentType = response.value(forHTTPHeaderField: "Content-Type")
        guard Self.isMPEGAudio(contentType) else {
            throw TeacherWordAudioError.unsupportedContentType(contentType)
        }
        return try TeacherWordAudioClip(audioData: data)
    }

    private static func isMPEGAudio(_ contentType: String?) -> Bool {
        let mediaType = contentType?
            .split(separator: ";", maxSplits: 1)
            .first?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
        return mediaType == "audio/mpeg" || mediaType == "audio/mp3"
    }

    private struct RequestPayload: Encodable {
        let spokenText: String
        let pronunciationKey: String?
        let speed: Double
        let contractVersion: String

        init(request: TeacherWordAudioRequest) {
            spokenText = request.spokenText
            pronunciationKey = request.pronunciationKey
            speed = request.speed
            contractVersion = request.voiceContractVersion
        }
    }
}

/// Stores canonical MP3 responses in the app's private cache. The file name is
/// a one-way hash of the pronunciation request and contains no profile data.
public actor FileTeacherWordAudioCache: TeacherWordAudioCaching {
    private let directory: URL
    private let fileManager: FileManager

    public init(
        directory: URL,
        fileManager: FileManager = .default
    ) {
        self.directory = directory
        self.fileManager = fileManager
    }

    public func clip(
        for request: TeacherWordAudioRequest
    ) async throws -> TeacherWordAudioClip? {
        let fileURL = fileURL(for: request)
        guard fileManager.fileExists(atPath: fileURL.path) else { return nil }

        do {
            return try TeacherWordAudioClip(
                audioData: Data(contentsOf: fileURL)
            )
        } catch {
            try? fileManager.removeItem(at: fileURL)
            return nil
        }
    }

    public func store(
        _ clip: TeacherWordAudioClip,
        for request: TeacherWordAudioRequest
    ) async throws {
        try fileManager.createDirectory(
            at: directory,
            withIntermediateDirectories: true
        )
        try clip.audioData.write(
            to: fileURL(for: request),
            options: .atomic
        )
    }

    private func fileURL(for request: TeacherWordAudioRequest) -> URL {
        let identity = [
            request.voiceContractVersion,
            String(request.speed),
            request.spokenText,
            request.pronunciationKey ?? "",
        ].joined(separator: "\u{1F}")
        let digest = SHA256.hash(data: Data(identity.utf8))
        let filename = digest.map { String(format: "%02x", $0) }.joined()
        return directory.appendingPathComponent(
            "\(filename).mp3",
            isDirectory: false
        )
    }
}
