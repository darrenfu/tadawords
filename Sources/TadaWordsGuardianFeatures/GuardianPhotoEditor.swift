#if os(iOS)
    import CoreGraphics
    import SwiftUI
    import TadaWordsDomain
    import UIKit

    enum GuardianMaskBrushWidth: String, CaseIterable, Identifiable {
        case thin
        case medium
        case thick

        var id: Self { self }

        var title: String { rawValue.capitalized }

        var displayPoints: CGFloat {
            switch self {
            case .thin: 8
            case .medium: 18
            case .thick: 34
            }
        }
    }

    struct GuardianMaskStroke: Equatable, Sendable {
        var points: [CGPoint]
        let widthFraction: CGFloat
    }

    struct GuardianPhotoEditSnapshot: Equatable, Sendable {
        var crop: CGRect = CGRect(x: 0, y: 0, width: 1, height: 1)
        var strokes: [GuardianMaskStroke] = []
    }

    enum GuardianCropCorner: CaseIterable {
        case topLeft
        case topRight
        case bottomLeft
        case bottomRight
    }

    enum GuardianPhotoEditorTool: String, CaseIterable, Identifiable {
        case crop = "Crop"
        case mask = "Mask"

        var id: Self { self }
    }

    enum GuardianImageGeometry {
        static func aspectFitRect(
            imageSize: CGSize,
            viewportSize: CGSize,
            zoomScale: CGFloat = 1
        ) -> CGRect {
            guard imageSize.width > 0, imageSize.height > 0,
                viewportSize.width > 0, viewportSize.height > 0
            else { return .zero }
            let fitScale = min(
                viewportSize.width / imageSize.width,
                viewportSize.height / imageSize.height
            )
            let size = CGSize(
                width: imageSize.width * fitScale * zoomScale,
                height: imageSize.height * fitScale * zoomScale
            )
            return CGRect(
                x: (viewportSize.width - size.width) / 2,
                y: (viewportSize.height - size.height) / 2,
                width: size.width,
                height: size.height
            )
        }

        static func normalizedPoint(_ point: CGPoint, in displayRect: CGRect) -> CGPoint? {
            guard displayRect.width > 0, displayRect.height > 0,
                displayRect.contains(point)
            else { return nil }
            return CGPoint(
                x: (point.x - displayRect.minX) / displayRect.width,
                y: (point.y - displayRect.minY) / displayRect.height
            )
        }

        static func displayPoint(_ point: CGPoint, in displayRect: CGRect) -> CGPoint {
            CGPoint(
                x: displayRect.minX + point.x * displayRect.width,
                y: displayRect.minY + point.y * displayRect.height
            )
        }

        static func displayRect(_ normalizedRect: CGRect, in displayRect: CGRect) -> CGRect {
            CGRect(
                x: displayRect.minX + normalizedRect.minX * displayRect.width,
                y: displayRect.minY + normalizedRect.minY * displayRect.height,
                width: normalizedRect.width * displayRect.width,
                height: normalizedRect.height * displayRect.height
            )
        }
    }

    @MainActor
    final class GuardianPhotoEditorModel: ObservableObject {
        @Published private(set) var snapshot = GuardianPhotoEditSnapshot()
        @Published private(set) var canUndo = false

        private var history: [GuardianPhotoEditSnapshot] = []
        private var cropEditStart: GuardianPhotoEditSnapshot?
        private var isDrawingStroke = false

        func beginCropEdit() {
            guard cropEditStart == nil else { return }
            cropEditStart = snapshot
        }

        func updateCrop(corner: GuardianCropCorner, to point: CGPoint) {
            let point = CGPoint(
                x: min(max(point.x, 0), 1),
                y: min(max(point.y, 0), 1)
            )
            let minimumDimension: CGFloat = 0.08
            var crop = snapshot.crop
            switch corner {
            case .topLeft:
                crop.origin.x = min(point.x, crop.maxX - minimumDimension)
                crop.origin.y = min(point.y, crop.maxY - minimumDimension)
                crop.size.width = snapshot.crop.maxX - crop.minX
                crop.size.height = snapshot.crop.maxY - crop.minY
            case .topRight:
                crop.origin.y = min(point.y, crop.maxY - minimumDimension)
                crop.size.width = max(point.x - crop.minX, minimumDimension)
                crop.size.height = snapshot.crop.maxY - crop.minY
            case .bottomLeft:
                crop.origin.x = min(point.x, crop.maxX - minimumDimension)
                crop.size.width = snapshot.crop.maxX - crop.minX
                crop.size.height = max(point.y - crop.minY, minimumDimension)
            case .bottomRight:
                crop.size.width = max(point.x - crop.minX, minimumDimension)
                crop.size.height = max(point.y - crop.minY, minimumDimension)
            }
            crop.size.width = min(crop.width, 1 - crop.minX)
            crop.size.height = min(crop.height, 1 - crop.minY)
            snapshot.crop = crop.standardized
        }

        func endCropEdit() {
            guard let start = cropEditStart else { return }
            cropEditStart = nil
            guard start != snapshot else { return }
            history.append(start)
            canUndo = true
        }

        func beginStroke(at point: CGPoint, widthFraction: CGFloat) {
            guard !isDrawingStroke else { return }
            history.append(snapshot)
            snapshot.strokes.append(
                GuardianMaskStroke(
                    points: [clamped(point)],
                    widthFraction: max(widthFraction, 0.001)
                )
            )
            isDrawingStroke = true
            canUndo = true
        }

        func appendStrokePoint(_ point: CGPoint) {
            guard isDrawingStroke, !snapshot.strokes.isEmpty else { return }
            snapshot.strokes[snapshot.strokes.index(before: snapshot.strokes.endIndex)]
                .points.append(clamped(point))
        }

        func endStroke() {
            isDrawingStroke = false
        }

        func undo() {
            guard let prior = history.popLast() else { return }
            snapshot = prior
            cropEditStart = nil
            isDrawingStroke = false
            canUndo = !history.isEmpty
        }

        func reset() {
            snapshot = GuardianPhotoEditSnapshot()
            history = []
            cropEditStart = nil
            isDrawingStroke = false
            canUndo = false
        }

        private func clamped(_ point: CGPoint) -> CGPoint {
            CGPoint(
                x: min(max(point.x, 0), 1),
                y: min(max(point.y, 0), 1)
            )
        }
    }

    enum GuardianPhotoEditorRenderer {
        static func normalizedImage(from data: Data) -> UIImage? {
            guard let image = UIImage(data: data) else { return nil }
            return normalizedImage(image)
        }

        static func normalizedImage(_ image: UIImage) -> UIImage? {
            let sourcePixelSize = CGSize(
                width: CGFloat(image.cgImage?.width ?? Int(image.size.width * image.scale)),
                height: CGFloat(image.cgImage?.height ?? Int(image.size.height * image.scale))
            )
            let swapsAxes: Bool
            switch image.imageOrientation {
            case .left, .leftMirrored, .right, .rightMirrored:
                swapsAxes = true
            default:
                swapsAxes = false
            }
            let outputSize =
                swapsAxes
                ? CGSize(width: sourcePixelSize.height, height: sourcePixelSize.width)
                : sourcePixelSize
            guard outputSize.width > 0, outputSize.height > 0 else { return nil }

            let format = UIGraphicsImageRendererFormat()
            format.scale = 1
            format.opaque = true
            return UIGraphicsImageRenderer(size: outputSize, format: format).image { _ in
                image.draw(in: CGRect(origin: .zero, size: outputSize))
            }
        }

        static func flattenedImage(
            source image: UIImage,
            snapshot: GuardianPhotoEditSnapshot
        ) -> UIImage? {
            guard let normalized = normalizedImage(image) else { return nil }
            let pixelSize = normalized.size
            let unit = CGRect(x: 0, y: 0, width: 1, height: 1)
            let crop = snapshot.crop.standardized.intersection(unit)
            guard crop.width > 0, crop.height > 0 else { return nil }
            let outputSize = CGSize(
                width: max((crop.width * pixelSize.width).rounded(), 1),
                height: max((crop.height * pixelSize.height).rounded(), 1)
            )
            let format = UIGraphicsImageRendererFormat()
            format.scale = 1
            format.opaque = true
            return UIGraphicsImageRenderer(size: outputSize, format: format).image { context in
                normalized.draw(
                    in: CGRect(
                        x: -crop.minX * pixelSize.width,
                        y: -crop.minY * pixelSize.height,
                        width: pixelSize.width,
                        height: pixelSize.height
                    )
                )
                let graphics = context.cgContext
                graphics.setStrokeColor(UIColor.black.cgColor)
                graphics.setFillColor(UIColor.black.cgColor)
                graphics.setLineCap(.round)
                graphics.setLineJoin(.round)
                for stroke in snapshot.strokes where !stroke.points.isEmpty {
                    let points = stroke.points.map { point in
                        CGPoint(
                            x: (point.x - crop.minX) * pixelSize.width,
                            y: (point.y - crop.minY) * pixelSize.height
                        )
                    }
                    let lineWidth = max(stroke.widthFraction * pixelSize.width, 1)
                    graphics.setLineWidth(lineWidth)
                    if points.count == 1, let point = points.first {
                        graphics.fillEllipse(
                            in: CGRect(
                                x: point.x - lineWidth / 2,
                                y: point.y - lineWidth / 2,
                                width: lineWidth,
                                height: lineWidth
                            )
                        )
                    } else if let first = points.first {
                        graphics.beginPath()
                        graphics.move(to: first)
                        for point in points.dropFirst() { graphics.addLine(to: point) }
                        graphics.strokePath()
                    }
                }
            }
        }

        static func flattenedJPEGData(
            source image: UIImage,
            snapshot: GuardianPhotoEditSnapshot
        ) -> Data? {
            autoreleasepool {
                flattenedImage(source: image, snapshot: snapshot)?
                    .jpegData(compressionQuality: 0.94)
            }
        }

        static func flattenedJPEGData(
            sourceData: Data,
            snapshot: GuardianPhotoEditSnapshot
        ) -> Data? {
            autoreleasepool {
                guard let image = UIImage(data: sourceData) else { return nil }
                return flattenedImage(source: image, snapshot: snapshot)?
                    .jpegData(compressionQuality: 0.94)
            }
        }

        static func uiTestingFixtureData() -> Data? {
            let format = UIGraphicsImageRendererFormat()
            format.scale = 1
            format.opaque = true
            let image = UIGraphicsImageRenderer(
                size: CGSize(width: 1_200, height: 800),
                format: format
            ).image { context in
                UIColor.white.setFill()
                context.fill(CGRect(x: 0, y: 0, width: 1_200, height: 800))
                let attributes: [NSAttributedString.Key: Any] = [
                    .font: UIFont.systemFont(ofSize: 96, weight: .bold),
                    .foregroundColor: UIColor.black,
                ]
                NSString(string: "cat   moon   read").draw(
                    at: CGPoint(x: 90, y: 310),
                    withAttributes: attributes
                )
            }
            return image.jpegData(compressionQuality: 0.9)
        }
    }

    struct GuardianEditedPhotoOCRHandoff: Sendable {
        let recognizer: any ImageTextRecognizing

        func recognize(editedData: Data) async throws -> [String] {
            try await recognizer.recognizeText(in: editedData)
        }
    }

    struct GuardianPhotoEditorView: View {
        private let sourceImage: UIImage
        private let sourceData: Data
        let onCancel: () -> Void
        let onRetake: () -> Void
        let onUsePhoto: (Data) -> Void

        @StateObject private var model = GuardianPhotoEditorModel()
        @State private var tool: GuardianPhotoEditorTool = .crop
        @State private var brushWidth: GuardianMaskBrushWidth = .medium
        @State private var zoomScale: CGFloat = 1
        @State private var isRendering = false
        @State private var renderingFailed = false
        @State private var renderTask: Task<Void, Never>?

        private let canvasCoordinateSpace = "guardian-photo-editor-canvas-space"

        init?(
            imageData: Data,
            onCancel: @escaping () -> Void,
            onRetake: @escaping () -> Void,
            onUsePhoto: @escaping (Data) -> Void
        ) {
            guard let image = GuardianPhotoEditorRenderer.normalizedImage(from: imageData) else {
                return nil
            }
            sourceImage = image
            sourceData = imageData
            self.onCancel = onCancel
            self.onRetake = onRetake
            self.onUsePhoto = onUsePhoto
        }

        var body: some View {
            ZStack {
                Color.black.ignoresSafeArea()
                GeometryReader { proxy in
                    VStack(spacing: 12) {
                        navigationBar
                        if proxy.size.width > proxy.size.height {
                            HStack(spacing: 12) {
                                editingCanvas
                                VStack(spacing: 12) {
                                    toolControls
                                    Spacer(minLength: 0)
                                    usePhotoButton
                                }
                                .frame(width: min(370, proxy.size.width * 0.42))
                            }
                        } else {
                            editingCanvas
                            toolControls
                            usePhotoButton
                        }
                    }
                }
                .padding(.horizontal, 12)
                .padding(.bottom, 8)
            }
            .foregroundStyle(.white)
            .statusBarHidden()
            .alert("Photo could not be prepared", isPresented: $renderingFailed) {
                Button("OK", role: .cancel) {}
            } message: {
                Text("Reset the edits or retake the photo, then try again.")
            }
            .onDisappear {
                renderTask?.cancel()
                renderTask = nil
                isRendering = false
            }
            .accessibilityIdentifier("guardian.photo-editor")
        }

        private var navigationBar: some View {
            HStack(spacing: 8) {
                Button("Cancel", action: onCancel)
                    .frame(minWidth: 60, minHeight: 44)
                    .disabled(isRendering)
                    .accessibilityHint("Returns to the Word Pool without recognizing this photo")
                    .accessibilityIdentifier("guardian.photo-editor.cancel")
                Spacer()
                Text("Edit Photo")
                    .font(.system(.headline, design: .rounded, weight: .bold))
                Spacer()
                Button("Retake", action: onRetake)
                    .frame(minWidth: 60, minHeight: 44)
                    .disabled(isRendering)
                    .accessibilityHint("Discards this photo and opens the camera again")
                    .accessibilityIdentifier("guardian.photo-editor.retake")
            }
            .buttonStyle(.bordered)
            .tint(.white)
        }

        private var editingCanvas: some View {
            GeometryReader { proxy in
                let viewport = CGRect(origin: .zero, size: proxy.size)
                let imageRect = GuardianImageGeometry.aspectFitRect(
                    imageSize: sourceImage.size,
                    viewportSize: proxy.size,
                    zoomScale: zoomScale
                )
                ZStack {
                    Image(uiImage: sourceImage)
                        .resizable()
                        .frame(width: imageRect.width, height: imageRect.height)
                        .position(x: imageRect.midX, y: imageRect.midY)

                    maskOverlay(imageRect: imageRect)

                    cropOverlay(viewport: viewport, imageRect: imageRect)

                    if tool == .mask {
                        Color.clear
                            .contentShape(Rectangle())
                            .gesture(maskGesture(imageRect: imageRect))
                            .accessibilityLabel("Photo masking canvas")
                            .accessibilityHint("Draw over words to cover them with black")
                    }
                }
                .clipped()
                .coordinateSpace(name: canvasCoordinateSpace)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color(white: 0.12))
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            .allowsHitTesting(!isRendering)
            .accessibilityIdentifier("guardian.photo-editor.canvas")
        }

        private func maskOverlay(imageRect: CGRect) -> some View {
            Canvas { context, _ in
                context.clip(
                    to: Path(
                        GuardianImageGeometry.displayRect(model.snapshot.crop, in: imageRect)
                    )
                )
                for stroke in model.snapshot.strokes where !stroke.points.isEmpty {
                    let points = stroke.points.map {
                        GuardianImageGeometry.displayPoint($0, in: imageRect)
                    }
                    let width = max(stroke.widthFraction * imageRect.width, 1)
                    if points.count == 1, let point = points.first {
                        context.fill(
                            Path(
                                ellipseIn: CGRect(
                                    x: point.x - width / 2,
                                    y: point.y - width / 2,
                                    width: width,
                                    height: width
                                )
                            ),
                            with: .color(.black)
                        )
                    } else if let first = points.first {
                        var path = Path()
                        path.move(to: first)
                        for point in points.dropFirst() { path.addLine(to: point) }
                        context.stroke(
                            path,
                            with: .color(.black),
                            style: StrokeStyle(
                                lineWidth: width,
                                lineCap: .round,
                                lineJoin: .round
                            )
                        )
                    }
                }
            }
            .allowsHitTesting(false)
        }

        @ViewBuilder
        private func cropOverlay(viewport: CGRect, imageRect: CGRect) -> some View {
            let cropRect = GuardianImageGeometry.displayRect(model.snapshot.crop, in: imageRect)
            Canvas { context, _ in
                var dim = Path()
                dim.addRect(viewport)
                dim.addRect(cropRect)
                context.fill(dim, with: .color(.black.opacity(0.48)), style: .init(eoFill: true))
                context.stroke(
                    Path(cropRect),
                    with: .color(.white),
                    style: StrokeStyle(lineWidth: 2, dash: [8, 5])
                )
            }
            .allowsHitTesting(false)

            if tool == .crop {
                ForEach(Array(GuardianCropCorner.allCases.enumerated()), id: \.offset) {
                    _, corner in
                    cropHandle(corner: corner, cropRect: cropRect, imageRect: imageRect)
                }
            }
        }

        private func cropHandle(
            corner: GuardianCropCorner,
            cropRect: CGRect,
            imageRect: CGRect
        ) -> some View {
            let position =
                switch corner {
                case .topLeft: CGPoint(x: cropRect.minX, y: cropRect.minY)
                case .topRight: CGPoint(x: cropRect.maxX, y: cropRect.minY)
                case .bottomLeft: CGPoint(x: cropRect.minX, y: cropRect.maxY)
                case .bottomRight: CGPoint(x: cropRect.maxX, y: cropRect.maxY)
                }
            return Circle()
                .fill(.white)
                .stroke(.black.opacity(0.7), lineWidth: 2)
                .frame(width: 24, height: 24)
                .frame(width: 44, height: 44)
                .position(position)
                .gesture(
                    DragGesture(
                        minimumDistance: 0,
                        coordinateSpace: .named(canvasCoordinateSpace)
                    )
                    .onChanged { value in
                        model.beginCropEdit()
                        let normalized = CGPoint(
                            x: (value.location.x - imageRect.minX) / imageRect.width,
                            y: (value.location.y - imageRect.minY) / imageRect.height
                        )
                        model.updateCrop(corner: corner, to: normalized)
                    }
                    .onEnded { _ in model.endCropEdit() }
                )
                .accessibilityLabel("Crop \(cropCornerName(corner)) corner")
                .accessibilityHint("Drag to resize the retained photo area")
        }

        private func maskGesture(imageRect: CGRect) -> some Gesture {
            DragGesture(
                minimumDistance: 0,
                coordinateSpace: .named(canvasCoordinateSpace)
            )
            .onChanged { value in
                guard
                    let normalized = GuardianImageGeometry.normalizedPoint(
                        value.location,
                        in: imageRect
                    )
                else { return }
                let widthFraction = brushWidth.displayPoints / imageRect.width
                model.beginStroke(at: normalized, widthFraction: widthFraction)
                model.appendStrokePoint(normalized)
            }
            .onEnded { _ in model.endStroke() }
        }

        private var toolControls: some View {
            VStack(spacing: 8) {
                HStack(spacing: 8) {
                    Picker("Editing tool", selection: $tool) {
                        ForEach(GuardianPhotoEditorTool.allCases) { tool in
                            Text(tool.rawValue).tag(tool)
                        }
                    }
                    .pickerStyle(.segmented)
                    .frame(maxWidth: 260)

                    Spacer()

                    Button {
                        zoomScale = max(1, zoomScale - 0.5)
                    } label: {
                        Image(systemName: "minus.magnifyingglass")
                            .frame(width: 44, height: 44)
                    }
                    .disabled(zoomScale <= 1)
                    .accessibilityLabel("Zoom out")

                    Button {
                        zoomScale = min(3, zoomScale + 0.5)
                    } label: {
                        Image(systemName: "plus.magnifyingglass")
                            .frame(width: 44, height: 44)
                    }
                    .disabled(zoomScale >= 3)
                    .accessibilityLabel("Zoom in")
                }

                HStack(spacing: 8) {
                    if tool == .mask {
                        ForEach(GuardianMaskBrushWidth.allCases) { width in
                            Button {
                                brushWidth = width
                            } label: {
                                Circle()
                                    .fill(.black)
                                    .stroke(.white, lineWidth: brushWidth == width ? 3 : 1)
                                    .frame(
                                        width: width.displayPoints,
                                        height: width.displayPoints
                                    )
                                    .frame(minWidth: 44, minHeight: 44)
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel("\(width.title) mask brush")
                            .accessibilityValue(brushWidth == width ? "Selected" : "Not selected")
                            .accessibilityIdentifier(
                                "guardian.photo-editor.brush.\(width.rawValue)")
                        }
                    }

                    Spacer()

                    Button {
                        model.undo()
                    } label: {
                        Label("Undo", systemImage: "arrow.uturn.backward")
                            .frame(minHeight: 44)
                    }
                    .disabled(!model.canUndo)
                    .accessibilityHint("Removes the most recent crop or mask edit")
                    .accessibilityIdentifier("guardian.photo-editor.undo")

                    Button {
                        model.reset()
                        zoomScale = 1
                    } label: {
                        Label("Reset", systemImage: "arrow.counterclockwise")
                            .frame(minHeight: 44)
                    }
                    .accessibilityHint("Restores the original uncropped photo")
                    .accessibilityIdentifier("guardian.photo-editor.reset")
                }
            }
            .buttonStyle(.bordered)
            .tint(.white)
            .disabled(isRendering)
        }

        private var usePhotoButton: some View {
            Button {
                guard !isRendering else { return }
                isRendering = true
                let snapshot = model.snapshot
                let sourceData = sourceData
                renderTask = Task { @MainActor in
                    let data = await Task.detached(priority: .userInitiated) {
                        GuardianPhotoEditorRenderer.flattenedJPEGData(
                            sourceData: sourceData,
                            snapshot: snapshot
                        )
                    }.value
                    guard !Task.isCancelled, isRendering else { return }
                    isRendering = false
                    renderTask = nil
                    if let data {
                        onUsePhoto(data)
                    } else {
                        renderingFailed = true
                    }
                }
            } label: {
                HStack {
                    if isRendering { ProgressView().tint(.black) }
                    Label("Use Photo", systemImage: "checkmark.circle.fill")
                }
                .font(.system(.headline, design: .rounded, weight: .bold))
                .foregroundStyle(.black)
                .frame(maxWidth: .infinity, minHeight: 50)
                .background(.white, in: Capsule())
            }
            .buttonStyle(.plain)
            .disabled(isRendering)
            .accessibilityHint(
                "Flattens the crop and black mask, then starts on-device recognition"
            )
            .accessibilityIdentifier("guardian.photo-editor.use-photo")
        }

        private func cropCornerName(_ corner: GuardianCropCorner) -> String {
            switch corner {
            case .topLeft: "top left"
            case .topRight: "top right"
            case .bottomLeft: "bottom left"
            case .bottomRight: "bottom right"
            }
        }
    }
#endif
