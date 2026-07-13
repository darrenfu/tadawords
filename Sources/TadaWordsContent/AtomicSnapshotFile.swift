import Foundation

/// Shared mechanics only. Each repository maps raw file/codec failures to its
/// own public, domain-specific error type.
struct AtomicSnapshotFile {
    let snapshotURL: URL
    let fileManager: FileManager

    func readIfPresent() throws -> Data? {
        do {
            _ = try fileManager.attributesOfItem(atPath: snapshotURL.path)
        } catch {
            let cocoaError = error as NSError
            if cocoaError.domain == NSCocoaErrorDomain,
                cocoaError.code == NSFileNoSuchFileError
                    || cocoaError.code == NSFileReadNoSuchFileError
            {
                return nil
            }
            throw error
        }

        return try Data(contentsOf: snapshotURL)
    }

    func write(_ data: Data) throws {
        let directoryURL = snapshotURL.deletingLastPathComponent()
        try fileManager.createDirectory(
            at: directoryURL,
            withIntermediateDirectories: true
        )

        let temporaryURL = directoryURL.appendingPathComponent(
            ".\(snapshotURL.lastPathComponent).\(UUID().uuidString).tmp",
            isDirectory: false
        )

        do {
            try data.write(to: temporaryURL)
            let handle = try FileHandle(forWritingTo: temporaryURL)
            try handle.synchronize()
            try handle.close()

            if fileManager.fileExists(atPath: snapshotURL.path) {
                _ = try fileManager.replaceItemAt(
                    snapshotURL,
                    withItemAt: temporaryURL
                )
            } else {
                try fileManager.moveItem(at: temporaryURL, to: snapshotURL)
            }
        } catch {
            try? fileManager.removeItem(at: temporaryURL)
            throw error
        }
    }
}

enum InspectableSnapshotJSONCodec {
    static func makeEncoder() -> JSONEncoder {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .secondsSince1970
        encoder.outputFormatting = [
            .prettyPrinted,
            .sortedKeys,
            .withoutEscapingSlashes,
        ]
        return encoder
    }

    static func makeDecoder() -> JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .secondsSince1970
        return decoder
    }
}
