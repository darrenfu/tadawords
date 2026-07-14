@preconcurrency import Foundation
import TadaWordsDomain

/// Downloads only the catalogued Twemoji asset for a concrete word and keeps
/// the tiny PNG in the app's private cache. No child/profile identifier or
/// learning history is sent with the request.
public actor AppleWordPictureHintService: WordPictureHintProviding {
    static let attribution =
        "Twemoji graphics by X Corp. and contributors, licensed CC-BY 4.0."
    static let maximumAssetSize = 128 * 1_024

    typealias DataLoader = @Sendable (URLRequest) async throws -> (Data, URLResponse)

    private let cacheDirectory: URL
    private let dataLoader: DataLoader

    public init(
        cacheDirectory: URL,
        session: URLSession = .shared
    ) {
        self.cacheDirectory = cacheDirectory
        dataLoader = { request in
            try await session.data(for: request)
        }
    }

    init(
        cacheDirectory: URL,
        dataLoader: @escaping DataLoader
    ) {
        self.cacheDirectory = cacheDirectory
        self.dataLoader = dataLoader
    }

    public func hint(for rawWord: String) async -> WordPictureHintAsset? {
        guard let descriptor = WordPictureHintCatalog.descriptor(for: rawWord) else {
            return nil
        }

        let fileURL = cacheDirectory.appendingPathComponent(
            "\(descriptor.assetCode).png",
            isDirectory: false
        )
        if let data = Self.validPNG(at: fileURL) {
            return Self.asset(data: data, descriptor: descriptor)
        }

        guard let remoteURL = Self.remoteURL(assetCode: descriptor.assetCode) else {
            return nil
        }
        var request = URLRequest(url: remoteURL)
        request.timeoutInterval = 12
        request.cachePolicy = .returnCacheDataElseLoad
        request.setValue("image/png", forHTTPHeaderField: "Accept")

        do {
            let (data, response) = try await dataLoader(request)
            guard Self.isAccepted(response: response, data: data) else { return nil }
            try FileManager.default.createDirectory(
                at: cacheDirectory,
                withIntermediateDirectories: true
            )
            try data.write(to: fileURL, options: .atomic)
            return Self.asset(data: data, descriptor: descriptor)
        } catch {
            // A picture is optional assistance. Offline/network failures must
            // never block adding a word or starting a quest.
            return nil
        }
    }

    private static func asset(
        data: Data,
        descriptor: WordPictureHintDescriptor
    ) -> WordPictureHintAsset {
        WordPictureHintAsset(
            imageData: data,
            accessibilityLabel: descriptor.accessibilityLabel,
            attribution: attribution
        )
    }

    private static func remoteURL(assetCode: String) -> URL? {
        URL(
            string:
                "https://cdn.jsdelivr.net/gh/jdecked/twemoji@17.0.3/assets/72x72/\(assetCode).png"
        )
    }

    private static func validPNG(at fileURL: URL) -> Data? {
        guard let data = try? Data(contentsOf: fileURL), isPNG(data) else {
            return nil
        }
        return data
    }

    private static func isAccepted(response: URLResponse, data: Data) -> Bool {
        guard let response = response as? HTTPURLResponse,
            response.statusCode == 200,
            data.count <= maximumAssetSize,
            isPNG(data)
        else {
            return false
        }
        return true
    }

    private static func isPNG(_ data: Data) -> Bool {
        let signature: [UInt8] = [0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A]
        return data.count >= signature.count
            && Array(data.prefix(signature.count)) == signature
    }
}
