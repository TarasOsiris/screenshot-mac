import SwiftUI
import AppKit

private struct EditorBlurBackgroundRenderKey: Equatable {
    let rowID: UUID
    let templateWidth: CGFloat
    let templateHeight: CGFloat
    let templateCount: Int
    let displayScale: CGFloat
    let backgroundBlur: Double
    let spanBackgroundAcrossRow: Bool
    let rowBackgroundDescriptor: BackgroundDescriptor
    let templateBackgroundDescriptors: [TemplateBackgroundDescriptor]
    let imageTokens: [ImageToken]

    struct BackgroundDescriptor: Equatable {
        let style: BackgroundStyle
        let color: CodableColor
        let gradient: GradientConfig
        let image: BackgroundImageConfig
    }

    struct TemplateBackgroundDescriptor: Equatable {
        let id: UUID
        let overrideBackground: Bool
        let background: BackgroundDescriptor
    }

    struct ImageToken: Equatable {
        let fileName: String
        let identity: ObjectIdentifier
        let width: CGFloat
        let height: CGFloat
    }
}

struct EditorRasterizedBackgroundView: View {
    private static let exactRenderDebounceNanoseconds: UInt64 = 120_000_000

    let row: ScreenshotRow
    let screenshotImages: [String: NSImage]
    let displayScale: CGFloat

    @State private var cachedImage: NSImage?
    @State private var renderedKey: EditorBlurBackgroundRenderKey?

    private var displayTotalWidth: CGFloat {
        row.templateWidth * displayScale * CGFloat(row.templates.count)
    }

    private var displayTemplateHeight: CGFloat {
        row.templateHeight * displayScale
    }

    private var renderScale: CGFloat { 1.0 }
    private var previewBlurRadius: CGFloat { row.backgroundBlur * displayScale }

    private var renderKey: EditorBlurBackgroundRenderKey {
        let imageNames = Set(
            [row.backgroundImageConfig.fileName] +
            row.templates.compactMap { $0.overrideBackground ? $0.backgroundImageConfig.fileName : nil }
        )
        let imageTokens = imageNames.compactMap { fileName -> EditorBlurBackgroundRenderKey.ImageToken? in
            guard let fileName, let image = screenshotImages[fileName] else { return nil }
            return .init(
                fileName: fileName,
                identity: ObjectIdentifier(image),
                width: image.size.width,
                height: image.size.height
            )
        }
        .sorted { $0.fileName < $1.fileName }

        return EditorBlurBackgroundRenderKey(
            rowID: row.id,
            templateWidth: row.templateWidth,
            templateHeight: row.templateHeight,
            templateCount: row.templates.count,
            displayScale: displayScale,
            backgroundBlur: row.backgroundBlur,
            spanBackgroundAcrossRow: row.spanBackgroundAcrossRow,
            rowBackgroundDescriptor: .init(
                style: row.backgroundStyle,
                color: row.backgroundColorData,
                gradient: row.gradientConfig,
                image: row.backgroundImageConfig
            ),
            templateBackgroundDescriptors: row.templates.map {
                .init(
                    id: $0.id,
                    overrideBackground: $0.overrideBackground,
                    background: .init(
                        style: $0.backgroundStyle,
                        color: $0.backgroundColor,
                        gradient: $0.gradientConfig,
                        image: $0.backgroundImageConfig
                    )
                )
            },
            imageTokens: imageTokens
        )
    }

    var body: some View {
        Group {
            if row.backgroundBlur > 0, let cachedImage, renderedKey == renderKey {
                Image(nsImage: cachedImage)
                    .resizable()
                    .interpolation(.high)
                    .frame(width: displayTotalWidth, height: displayTemplateHeight)
            } else {
                RowCanvasBackgroundView(
                    row: row,
                    screenshotImages: screenshotImages,
                    displayScale: displayScale,
                    blurRadius: previewBlurRadius
                )
            }
        }
        .task(id: renderKey) {
            guard row.backgroundBlur > 0 else {
                cachedImage = nil
                renderedKey = nil
                return
            }
            let key = renderKey
            try? await Task.sleep(nanoseconds: Self.exactRenderDebounceNanoseconds)
            guard !Task.isCancelled else { return }
            // Blur the background at model resolution, then downscale for the editor.
            // This avoids edge artifacts from blurring an already downsampled tile/image raster.
            let image = ExportService.renderComposedBackgroundImage(
                row: row,
                screenshotImages: screenshotImages,
                displayScale: renderScale,
                labelPrefix: "editor"
            )
            guard !Task.isCancelled else { return }
            cachedImage = image
            renderedKey = key
        }
    }
}

struct RowCanvasBaseBackgroundView: View {
    let row: ScreenshotRow
    let screenshotImages: [String: NSImage]
    let displayScale: CGFloat

    private var displayTemplateWidth: CGFloat {
        row.templateWidth * displayScale
    }

    private var displayTemplateHeight: CGFloat {
        row.templateHeight * displayScale
    }

    private var displayTotalWidth: CGFloat {
        displayTemplateWidth * CGFloat(row.templates.count)
    }

    var body: some View {
        let templateModelSize = CGSize(width: row.templateWidth, height: row.templateHeight)

        Group {
            if row.isSpanningBackground {
                let spanModelSize = CGSize(
                    width: row.templateWidth * CGFloat(row.templates.count),
                    height: row.templateHeight
                )
                row.resolvedBackgroundView(screenshotImages: screenshotImages, modelSize: spanModelSize)
                    .frame(width: displayTotalWidth, height: displayTemplateHeight)
            } else {
                ZStack(alignment: .topLeading) {
                    ForEach(Array(row.templates.enumerated()), id: \.element.id) { index, _ in
                        row.resolvedBackgroundView(screenshotImages: screenshotImages, modelSize: templateModelSize)
                            .frame(width: displayTemplateWidth, height: displayTemplateHeight)
                            .offset(x: CGFloat(index) * displayTemplateWidth, y: 0)
                    }
                }
                .frame(width: displayTotalWidth, height: displayTemplateHeight, alignment: .topLeading)
            }
        }
        .frame(width: displayTotalWidth, height: displayTemplateHeight, alignment: .topLeading)
        .clipped()
    }
}

struct RowCanvasOverrideBackgroundView: View {
    let row: ScreenshotRow
    let screenshotImages: [String: NSImage]
    let displayScale: CGFloat

    private var displayTemplateWidth: CGFloat {
        row.templateWidth * displayScale
    }

    private var displayTemplateHeight: CGFloat {
        row.templateHeight * displayScale
    }

    private var templateModelSize: CGSize {
        CGSize(width: row.templateWidth, height: row.templateHeight)
    }

    var body: some View {
        HStack(spacing: 0) {
            ForEach(row.templates) { template in
                if template.overrideBackground {
                    template.resolvedBackgroundView(screenshotImages: screenshotImages, modelSize: templateModelSize)
                        .frame(width: displayTemplateWidth, height: displayTemplateHeight)
                } else {
                    Color.clear.frame(width: displayTemplateWidth, height: displayTemplateHeight)
                }
            }
        }
        .frame(
            width: displayTemplateWidth * CGFloat(row.templates.count),
            height: displayTemplateHeight,
            alignment: .topLeading
        )
    }
}

struct RowCanvasBackgroundView: View {
    let row: ScreenshotRow
    let screenshotImages: [String: NSImage]
    let displayScale: CGFloat
    let blurRadius: CGFloat

    private var displayTotalWidth: CGFloat {
        row.templateWidth * displayScale * CGFloat(row.templates.count)
    }

    private var displayTemplateHeight: CGFloat {
        row.templateHeight * displayScale
    }

    var body: some View {
        let baseLayer = RowCanvasBaseBackgroundView(
            row: row,
            screenshotImages: screenshotImages,
            displayScale: displayScale
        )

        ZStack(alignment: .topLeading) {
            if blurRadius > 0 {
                BackgroundBlurView(width: displayTotalWidth, height: displayTemplateHeight, blurRadius: blurRadius) {
                    baseLayer
                }
            } else {
                baseLayer
            }

            if row.templates.contains(where: \.overrideBackground) {
                RowCanvasOverrideBackgroundView(
                    row: row,
                    screenshotImages: screenshotImages,
                    displayScale: displayScale
                )
            }
        }
    }
}

struct RowCanvasShapeLayerView<ShapeContent: View>: View {
    let row: ScreenshotRow
    let shapes: [CanvasShapeModel]
    let displayScale: CGFloat
    let shapeContent: (CanvasShapeModel, CGRect?) -> ShapeContent

    init(
        row: ScreenshotRow,
        shapes: [CanvasShapeModel],
        displayScale: CGFloat,
        @ViewBuilder shapeContent: @escaping (CanvasShapeModel, CGRect?) -> ShapeContent
    ) {
        self.row = row
        self.shapes = shapes
        self.displayScale = displayScale
        self.shapeContent = shapeContent
    }

    private var displayTemplateWidth: CGFloat {
        row.templateWidth * displayScale
    }

    private var displayTemplateHeight: CGFloat {
        row.templateHeight * displayScale
    }

    private var displayTotalWidth: CGFloat {
        displayTemplateWidth * CGFloat(row.templates.count)
    }

    var body: some View {
        ZStack(alignment: .topLeading) {
            ForEach(shapes) { shape in
                shapeContent(shape, clipBounds(for: shape))
            }
        }
        .frame(width: displayTotalWidth, height: displayTemplateHeight, alignment: .topLeading)
        .clipped()
    }

    private func clipBounds(for shape: CanvasShapeModel) -> CGRect? {
        guard shape.clipToTemplate == true else { return nil }
        let templateIndex = row.owningTemplateIndex(for: shape)
        return CGRect(
            x: CGFloat(templateIndex) * displayTemplateWidth,
            y: 0,
            width: displayTemplateWidth,
            height: displayTemplateHeight
        )
    }
}
