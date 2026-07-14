import Foundation
import TadaWordsDomain
import XCTest

@testable import TadaWordsApplePlatform

final class AppleWordPictureHintServiceTests: XCTestCase {
    func testConcreteWordDownloadsOnceThenUsesDiskCache() async throws {
        let directory = temporaryDirectory()
        let counter = LockedCounter()
        let png = Self.pngData
        let service = AppleWordPictureHintService(
            cacheDirectory: directory,
            dataLoader: { request in
                counter.increment()
                let response = try XCTUnwrap(
                    HTTPURLResponse(
                        url: try XCTUnwrap(request.url),
                        statusCode: 200,
                        httpVersion: nil,
                        headerFields: ["Content-Type": "image/png"]
                    )
                )
                return (png, response)
            }
        )

        let first = await service.hint(for: "Dog")
        let second = await service.hint(for: "dog")

        XCTAssertEqual(first?.imageData, png)
        XCTAssertEqual(first?.accessibilityLabel, "a dog")
        XCTAssertEqual(second, first)
        XCTAssertEqual(counter.value, 1)
    }

    func testAbstractWordNeverMakesNetworkRequest() async {
        let counter = LockedCounter()
        let service = AppleWordPictureHintService(
            cacheDirectory: temporaryDirectory(),
            dataLoader: { _ in
                counter.increment()
                throw URLError(.badURL)
            }
        )

        let hint = await service.hint(for: "the")

        XCTAssertNil(hint)
        XCTAssertEqual(counter.value, 0)
    }

    private func temporaryDirectory() -> URL {
        FileManager.default.temporaryDirectory.appendingPathComponent(
            "TadaWordsPictureTests-\(UUID().uuidString)",
            isDirectory: true
        )
    }

    private static let pngData = Data([
        0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A,
        0x00, 0x00, 0x00, 0x00,
    ])
}

private final class LockedCounter: @unchecked Sendable {
    private let lock = NSLock()
    private var count = 0

    var value: Int {
        lock.withLock { count }
    }

    func increment() {
        lock.withLock { count += 1 }
    }
}
