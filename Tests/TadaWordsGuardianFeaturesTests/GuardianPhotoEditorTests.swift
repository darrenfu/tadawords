#if os(iOS)
    import CoreGraphics
    import TadaWordsDomain
    import UIKit
    import XCTest

    @testable import TadaWordsGuardianFeatures

    @MainActor
    final class GuardianPhotoEditorTests: XCTestCase {
        func testAspectFitCoordinateMappingIsStableAcrossDisplayScaleAndOrientation() throws {
            let landscape = GuardianImageGeometry.aspectFitRect(
                imageSize: CGSize(width: 1_200, height: 800),
                viewportSize: CGSize(width: 300, height: 500)
            )
            XCTAssertEqual(landscape, CGRect(x: 0, y: 150, width: 300, height: 200))
            XCTAssertEqual(
                GuardianImageGeometry.normalizedPoint(
                    CGPoint(x: 75, y: 200),
                    in: landscape
                ),
                CGPoint(x: 0.25, y: 0.25)
            )

            let zoomedPortrait = GuardianImageGeometry.aspectFitRect(
                imageSize: CGSize(width: 800, height: 1_200),
                viewportSize: CGSize(width: 500, height: 300),
                zoomScale: 2
            )
            let normalized = try XCTUnwrap(
                GuardianImageGeometry.normalizedPoint(
                    GuardianImageGeometry.displayPoint(
                        CGPoint(x: 0.72, y: 0.38),
                        in: zoomedPortrait
                    ),
                    in: zoomedPortrait
                )
            )
            XCTAssertEqual(normalized.x, 0.72, accuracy: 0.000_001)
            XCTAssertEqual(normalized.y, 0.38, accuracy: 0.000_001)

            let handleSafe = GuardianImageGeometry.aspectFitRect(
                imageSize: CGSize(width: 1_200, height: 800),
                viewportSize: CGSize(width: 300, height: 500),
                contentInset: 26
            )
            XCTAssertEqual(handleSafe.minX, 26, accuracy: 0.000_001)
            XCTAssertEqual(handleSafe.maxX, 274, accuracy: 0.000_001)
            XCTAssertGreaterThanOrEqual(handleSafe.minY, 26)
            XCTAssertLessThanOrEqual(handleSafe.maxY, 474)
        }

        func testRendererNormalizesRightOrientedImageBeforeCropMapping() throws {
            let source = try XCTUnwrap(solidImage(size: CGSize(width: 40, height: 20)).cgImage)
            let rotated = UIImage(cgImage: source, scale: 1, orientation: .right)
            let normalized = try XCTUnwrap(
                GuardianPhotoEditorRenderer.normalizedImage(rotated)
            )
            XCTAssertEqual(normalized.imageOrientation, .up)
            XCTAssertEqual(normalized.size, CGSize(width: 20, height: 40))

            let cropped = try XCTUnwrap(
                GuardianPhotoEditorRenderer.flattenedImage(
                    source: rotated,
                    snapshot: GuardianPhotoEditSnapshot(
                        crop: CGRect(x: 0, y: 0, width: 0.5, height: 1),
                        strokes: []
                    )
                )
            )
            XCTAssertEqual(cropped.size, CGSize(width: 10, height: 40))
        }

        func testMaskRasterizationUsesNormalizedWidthAcrossDisplayScalesAndClipsToCrop() throws {
            let source = solidImage(size: CGSize(width: 200, height: 100), color: .white)
            let crop = CGRect(x: 0.25, y: 0, width: 0.5, height: 1)
            let smallDisplayWidth: CGFloat = 100
            let largeDisplayWidth: CGFloat = 300
            let smallSnapshot = GuardianPhotoEditSnapshot(
                crop: crop,
                strokes: [
                    GuardianMaskStroke(
                        points: [CGPoint(x: 0.1, y: 0.5), CGPoint(x: 0.9, y: 0.5)],
                        widthFraction: 10 / smallDisplayWidth
                    )
                ]
            )
            let largeSnapshot = GuardianPhotoEditSnapshot(
                crop: crop,
                strokes: [
                    GuardianMaskStroke(
                        points: [CGPoint(x: 0.1, y: 0.5), CGPoint(x: 0.9, y: 0.5)],
                        widthFraction: 30 / largeDisplayWidth
                    )
                ]
            )
            let small = try XCTUnwrap(
                GuardianPhotoEditorRenderer.flattenedImage(
                    source: source,
                    snapshot: smallSnapshot
                )
            )
            let large = try XCTUnwrap(
                GuardianPhotoEditorRenderer.flattenedImage(
                    source: source,
                    snapshot: largeSnapshot
                )
            )
            XCTAssertEqual(small.size, CGSize(width: 100, height: 100))
            XCTAssertEqual(small.pngData(), large.pngData())
            XCTAssertTrue(isDark(small, at: CGPoint(x: 50, y: 50)))
            XCTAssertFalse(isDark(small, at: CGPoint(x: 50, y: 5)))
        }

        func testUndoRemovesLatestMaskThenCropAndResetRestoresOriginal() {
            let model = GuardianPhotoEditorModel()
            model.beginCropEdit()
            model.updateCrop(corner: .topLeft, to: CGPoint(x: 0.2, y: 0.1))
            model.endCropEdit()
            let cropped = model.snapshot.crop

            model.beginStroke(at: CGPoint(x: 0.4, y: 0.4), widthFraction: 0.05)
            model.appendStrokePoint(CGPoint(x: 0.6, y: 0.6))
            model.endStroke()
            XCTAssertEqual(model.snapshot.strokes.count, 1)

            model.undo()
            XCTAssertEqual(model.snapshot.crop, cropped)
            XCTAssertTrue(model.snapshot.strokes.isEmpty)
            model.undo()
            XCTAssertEqual(model.snapshot, GuardianPhotoEditSnapshot())

            model.beginStroke(at: CGPoint(x: 0.5, y: 0.5), widthFraction: 0.1)
            model.endStroke()
            model.reset()
            XCTAssertEqual(model.snapshot, GuardianPhotoEditSnapshot())
            XCTAssertFalse(model.canUndo)
        }

        func testEditedBytesAreHandedUnchangedToOCRBoundary() async throws {
            let recognizer = CapturingRecognizer()
            let handoff = GuardianEditedPhotoOCRHandoff(recognizer: recognizer)
            let editedData = Data([0, 1, 2, 3, 250, 251, 252])

            let fragments = try await handoff.recognize(editedData: editedData)

            XCTAssertEqual(fragments, ["edited-only"])
            let received = await recognizer.receivedData
            XCTAssertEqual(received, [editedData])
        }

        private func solidImage(
            size: CGSize,
            color: UIColor = .systemBlue
        ) -> UIImage {
            let format = UIGraphicsImageRendererFormat()
            format.scale = 1
            format.opaque = true
            return UIGraphicsImageRenderer(size: size, format: format).image { context in
                color.setFill()
                context.fill(CGRect(origin: .zero, size: size))
            }
        }

        private func isDark(_ image: UIImage, at point: CGPoint) -> Bool {
            guard let cgImage = image.cgImage,
                let provider = cgImage.dataProvider,
                let data = provider.data,
                let bytes = CFDataGetBytePtr(data)
            else { return false }
            let x = min(max(Int(point.x), 0), cgImage.width - 1)
            let y = min(max(Int(point.y), 0), cgImage.height - 1)
            let offset = y * cgImage.bytesPerRow + x * max(cgImage.bitsPerPixel / 8, 1)
            return bytes[offset] < 80 && bytes[offset + 1] < 80 && bytes[offset + 2] < 80
        }
    }

    private actor CapturingRecognizer: ImageTextRecognizing {
        private(set) var receivedData: [Data] = []

        func recognizeText(in imageData: Data) async throws -> [String] {
            receivedData.append(imageData)
            return ["edited-only"]
        }
    }
#endif
