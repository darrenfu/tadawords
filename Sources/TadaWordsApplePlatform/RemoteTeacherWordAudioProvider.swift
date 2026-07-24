import CryptoKit
@preconcurrency import Foundation
import TadaWordsDomain

/// Calls a Tada Words-owned audio endpoint. The endpoint is responsible for
/// holding any provider credential and canonical voice ID; neither value is
/// represented by this client API or sent from the iOS app.
public struct RemoteTeacherWordAudioProvider: TeacherWordAudioProviding {
    typealias DataLoader = @Sendable (URLRequest) async throws -> (Data, URLResponse)

    private let endpoint: URL?
    private let dataLoader: DataLoader
    private let authorizer: (any TeacherAudioRequestAuthorizing)?

    public init(endpoint: URL?) {
        self.endpoint = endpoint
        dataLoader = { request in
            try await URLSession.shared.data(for: request)
        }
        authorizer = endpoint.map {
            AppAttestTeacherAudioAuthorizer(endpoint: $0)
        }
    }

    init(
        endpoint: URL?,
        authorizer: (any TeacherAudioRequestAuthorizing)? = nil,
        dataLoader: @escaping DataLoader
    ) {
        self.endpoint = endpoint
        self.authorizer = authorizer
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
        guard let authorizer else {
            throw TeacherWordAudioError.appAttestUnavailable
        }

        var (data, rawResponse) = try await perform(
            request,
            endpoint: endpoint,
            authorizer: authorizer
        )
        guard let initialResponse = rawResponse as? HTTPURLResponse else {
            throw TeacherWordAudioError.invalidResponse
        }
        if initialResponse.statusCode == 401 {
            await authorizer.resetRegistration()
            (data, rawResponse) = try await perform(
                request,
                endpoint: endpoint,
                authorizer: authorizer
            )
        }
        guard let response = rawResponse as? HTTPURLResponse else {
            throw TeacherWordAudioError.invalidResponse
        }
        guard (200...299).contains(response.statusCode) else {
            throw TeacherWordAudioError.serverRejected(
                statusCode: response.statusCode
            )
        }
        let maximumByteCount = TeacherWordAudioClip.maximumByteCount
        guard
            response.expectedContentLength <= Int64(maximumByteCount),
            data.count <= maximumByteCount
        else {
            throw TeacherWordAudioError.responseTooLarge(
                maximumByteCount: maximumByteCount
            )
        }

        let contentType = response.value(forHTTPHeaderField: "Content-Type")
        guard Self.isMPEGAudio(contentType) else {
            throw TeacherWordAudioError.unsupportedContentType(contentType)
        }
        guard
            response.value(
                forHTTPHeaderField: "X-PawGoo-Audio-Contract"
            ) == request.voiceContractVersion
        else {
            throw TeacherWordAudioError.mismatchedAudioContract
        }
        let expectedChecksum = response.value(
            forHTTPHeaderField: "X-PawGoo-Audio-Checksum"
        )
        let checksum = SHA256.hash(data: data)
            .map { String(format: "%02x", $0) }
            .joined()
        guard expectedChecksum == checksum else {
            throw TeacherWordAudioError.invalidAudioChecksum
        }
        return try TeacherWordAudioClip(audioData: data)
    }

    private func perform(
        _ request: TeacherWordAudioRequest,
        endpoint: URL,
        authorizer: any TeacherAudioRequestAuthorizing
    ) async throws -> (Data, URLResponse) {
        let authorized = try await authorizer.authorize { challenge in
            try Self.canonicalBody(request: request, challenge: challenge)
        }
        var components = URLComponents(
            url: endpoint,
            resolvingAgainstBaseURL: false
        )
        components?.path = "/v1/teacher-audio"
        components?.query = nil
        components?.fragment = nil
        guard let requestURL = components?.url else {
            throw TeacherWordAudioError.invalidEndpoint
        }
        var urlRequest = URLRequest(url: requestURL)
        urlRequest.httpMethod = "POST"
        urlRequest.timeoutInterval = 15
        urlRequest.cachePolicy = .reloadIgnoringLocalCacheData
        urlRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
        urlRequest.setValue("audio/mpeg", forHTTPHeaderField: "Accept")
        urlRequest.setValue(
            authorized.appAttestHeader,
            forHTTPHeaderField: "X-PawGoo-App-Attest"
        )
        urlRequest.httpBody = authorized.body
        return try await dataLoader(urlRequest)
    }

    private static func isMPEGAudio(_ contentType: String?) -> Bool {
        let mediaType = contentType?
            .split(separator: ";", maxSplits: 1)
            .first?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
        return mediaType == "audio/mpeg" || mediaType == "audio/mp3"
    }

    private static func canonicalBody(
        request: TeacherWordAudioRequest,
        challenge: String
    ) throws -> Data {
        func jsonString(_ value: String) throws -> String {
            String(
                decoding: try JSONEncoder().encode(value),
                as: UTF8.self
            )
        }
        let pronunciationKey =
            try request.pronunciationKey
            .map(jsonString) ?? "null"
        let json = try """
        {"word":\(jsonString(request.spokenText)),"usage":\(jsonString(request.usage.rawValue)),"locale":"en-US","pronunciationKey":\(pronunciationKey),"contractVersion":\(jsonString(request.voiceContractVersion)),"challenge":\(jsonString(challenge))}
        """
        return Data(json.utf8)
    }
}

/// Stores canonical MP3 responses in private Application Support. The
/// directory is excluded from device backup; each file name is a one-way hash
/// of the pronunciation request and contains no profile data.
public actor FileTeacherWordAudioCache: TeacherWordAudioCaching {
    private let directory: URL?
    private let fileManager: FileManager

    public init(
        directory: URL?,
        fileManager: FileManager = .default
    ) {
        self.directory = directory
        self.fileManager = fileManager
    }

    public func clip(
        for request: TeacherWordAudioRequest
    ) async throws -> TeacherWordAudioClip? {
        guard directory != nil else {
            throw TeacherWordAudioError.persistentCacheUnavailable
        }
        let fileURL = fileURL(for: request)
        let checksumURL = checksumURL(for: request)
        guard
            fileManager.fileExists(atPath: fileURL.path),
            fileManager.fileExists(atPath: checksumURL.path)
        else {
            try? fileManager.removeItem(at: fileURL)
            try? fileManager.removeItem(at: checksumURL)
            return nil
        }

        do {
            let data = try Data(contentsOf: fileURL)
            let expectedChecksum = try String(
                contentsOf: checksumURL,
                encoding: .utf8
            )
            guard expectedChecksum == Self.checksum(data) else {
                throw TeacherWordAudioError.invalidAudioChecksum
            }
            return try TeacherWordAudioClip(audioData: data)
        } catch {
            try? fileManager.removeItem(at: fileURL)
            try? fileManager.removeItem(at: checksumURL)
            return nil
        }
    }

    public func store(
        _ clip: TeacherWordAudioClip,
        for request: TeacherWordAudioRequest
    ) async throws {
        guard let directory else {
            throw TeacherWordAudioError.persistentCacheUnavailable
        }
        try fileManager.createDirectory(
            at: directory,
            withIntermediateDirectories: true
        )
        var protectedDirectory = directory
        var resourceValues = URLResourceValues()
        resourceValues.isExcludedFromBackup = true
        try protectedDirectory.setResourceValues(resourceValues)
        let fileURL = fileURL(for: request)
        let checksumURL = checksumURL(for: request)
        let checksum = Self.checksum(clip.audioData)
        if let existingData = try? Data(contentsOf: fileURL),
            let existingChecksum = try? String(
                contentsOf: checksumURL,
                encoding: .utf8
            )
        {
            guard
                existingChecksum == checksum,
                Self.checksum(existingData) == checksum
            else {
                throw TeacherWordAudioError.invalidAudioChecksum
            }
            return
        }

        do {
            try clip.audioData.write(to: fileURL, options: .atomic)
            try Data(checksum.utf8).write(to: checksumURL, options: .atomic)
        } catch {
            try? fileManager.removeItem(at: fileURL)
            try? fileManager.removeItem(at: checksumURL)
            throw error
        }
    }

    private func fileURL(for request: TeacherWordAudioRequest) -> URL {
        guard let directory else {
            preconditionFailure("A cache URL requires a persistent directory")
        }
        let identity = [
            request.voiceContractVersion,
            request.spokenText,
            request.pronunciationKey ?? "",
            request.usage.rawValue,
            "en-US",
        ].joined(separator: "\u{1F}")
        let digest = SHA256.hash(data: Data(identity.utf8))
        let filename = digest.map { String(format: "%02x", $0) }.joined()
        return directory.appendingPathComponent(
            "\(filename).mp3",
            isDirectory: false
        )
    }

    private func checksumURL(for request: TeacherWordAudioRequest) -> URL {
        fileURL(for: request).appendingPathExtension("sha256")
    }

    private static func checksum(_ data: Data) -> String {
        SHA256.hash(data: data)
            .map { String(format: "%02x", $0) }
            .joined()
    }
}
