import Foundation
import TadaWordsDomain
import XCTest

@testable import TadaWordsApplePlatform

final class AppleWordPictureHintServiceTests: XCTestCase {
    func testProductionPackExactlyMatchesCatalogAndLoadsOffline() async throws {
        let root = try XCTUnwrap(
            AppleWordPictureHintService.productionResourceRoot()
        )
        let manifestData = try Data(
            contentsOf: root.appendingPathComponent("manifest.json")
        )
        let manifest = try JSONDecoder().decode(
            PictureHintManifest.self,
            from: manifestData
        )
        let manifestCodes = Set(manifest.assetCodes)

        XCTAssertEqual(manifest.name, "Twemoji")
        XCTAssertEqual(manifest.version, "17.0.3")
        XCTAssertEqual(
            manifest.sourceCommit,
            "b6b55fef1e8636b540a6d016a4729ca8cdf2e60b"
        )
        XCTAssertEqual(manifest.license, "CC-BY-4.0")
        XCTAssertEqual(manifest.assetCodes.count, manifestCodes.count)
        XCTAssertEqual(manifestCodes, WordPictureHintCatalog.assetCodes)
        XCTAssertEqual(manifestCodes.count, 74)

        let bundledPNGs = try FileManager.default.contentsOfDirectory(
            at: root,
            includingPropertiesForKeys: nil
        ).filter { $0.pathExtension == "png" }
        XCTAssertEqual(
            Set(
                bundledPNGs.map {
                    $0.deletingPathExtension().lastPathComponent
                }
            ),
            manifestCodes
        )

        for code in manifest.assetCodes {
            let data = try Data(
                contentsOf: root.appendingPathComponent("\(code).png"),
                options: .mappedIfSafe
            )
            XCTAssertLessThanOrEqual(
                data.count,
                AppleWordPictureHintService.maximumAssetSize,
                code
            )
            XCTAssertTrue(
                AppleWordPictureHintService.isAcceptedAsset(data),
                code
            )
        }

        let service = AppleWordPictureHintService()
        let hint = await service.hint(for: "Dog")
        XCTAssertNotNil(hint)
        XCTAssertEqual(hint?.accessibilityLabel, "a dog")
        XCTAssertEqual(
            hint?.attribution,
            "Twemoji graphics by X Corp. and contributors, licensed CC-BY 4.0."
        )
    }

    func testMissingAssetFallsBackToNoPicture() async throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let service = AppleWordPictureHintService(resourceRoot: fixture.root)

        let hint = await service.hint(for: "dog")
        XCTAssertNil(hint)
    }

    func testCorruptAssetFallsBackToNoPicture() async throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        try Self.pngSignatureOnly.write(
            to: fixture.root.appendingPathComponent("1f436.png")
        )
        let service = AppleWordPictureHintService(resourceRoot: fixture.root)

        let hint = await service.hint(for: "dog")
        XCTAssertNil(hint)
    }

    func testAssetOverMaximumSizeFallsBackToNoPicture() async throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        var oversized = Data(
            repeating: 0,
            count: AppleWordPictureHintService.maximumAssetSize + 1
        )
        oversized.replaceSubrange(
            0..<Self.pngSignatureOnly.count,
            with: Self.pngSignatureOnly
        )
        try oversized.write(
            to: fixture.root.appendingPathComponent("1f436.png")
        )
        let service = AppleWordPictureHintService(resourceRoot: fixture.root)

        XCTAssertFalse(AppleWordPictureHintService.isAcceptedAsset(oversized))
        let hint = await service.hint(for: "dog")
        XCTAssertNil(hint)
    }

    func testAbstractWordReturnsNilWithoutReadingAnAsset() async throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        try Data("not an image".utf8).write(
            to: fixture.root.appendingPathComponent("the.png")
        )
        let service = AppleWordPictureHintService(resourceRoot: fixture.root)

        let hint = await service.hint(for: "the")
        XCTAssertNil(hint)
    }

    private static let pngSignatureOnly = Data([
        0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A,
    ])

    private struct Fixture {
        let root: URL

        init() throws {
            root = FileManager.default.temporaryDirectory.appendingPathComponent(
                "TadaWordsPictureTests-\(UUID().uuidString)",
                isDirectory: true
            )
            try FileManager.default.createDirectory(
                at: root,
                withIntermediateDirectories: true
            )
        }

        func remove() {
            try? FileManager.default.removeItem(at: root)
        }
    }

    private struct PictureHintManifest: Decodable {
        let name: String
        let version: String
        let sourceCommit: String
        let license: String
        let assetCodes: [String]

        private enum CodingKeys: String, CodingKey {
            case name
            case version
            case sourceCommit = "source_commit"
            case license
            case assetCodes = "asset_codes"
        }
    }
}
