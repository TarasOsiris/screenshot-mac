import SwiftUI
#if os(macOS)
import AppKit
#else
import UIKit
#endif

struct EditorBlurBackgroundRenderKey: Equatable {
    let rowID: UUID
    let templateWidth: CGFloat
    let templateHeight: CGFloat
    let templateCount: Int
    // NB: deliberately excludes displayScale — the cached image is rendered at model
    // resolution (renderScale = 1.0), so zoom changing displayScale must not invalidate it.
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
        let blur: Double
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

/// One row's rasterized blur, held outside the view so it survives the editor's LazyVStack
/// recycling the row off-screen and back. Class-boxed because the key is only `Equatable`, not
/// `Hashable` — the cache is keyed by row id and the key rides along for the freshness check.
final class EditorBlurRaster {
    let key: EditorBlurBackgroundRenderKey
    let image: NSImage

    init(key: EditorBlurBackgroundRenderKey, image: NSImage) {
        self.key = key
        self.image = image
    }
}

/// Rasterized row blurs, shared across row views so one survives the editor's LazyVStack recycling
/// a row off-screen and back. Without it that row repainted the live `.blur` path and then re-ran a
/// main-actor, model-resolution `ImageRenderer` + `CIGaussianBlur` — the shape `ViewRasterizer`
/// already calls "an app-hang report waiting to happen". Bounded by bytes as well as count:
/// `countLimit` alone can pin a lot of memory for wide rows.
enum EditorBlurRasterCache {
    private static let cache: NSCache<NSUUID, EditorBlurRaster> = {
        let cache = NSCache<NSUUID, EditorBlurRaster>()
        cache.countLimit = 24
        cache.totalCostLimit = 256 * 1024 * 1024
        return cache
    }()

    static func raster(for rowID: UUID, key: EditorBlurBackgroundRenderKey) -> NSImage? {
        guard let entry = cache.object(forKey: rowID as NSUUID), entry.key == key else { return nil }
        return entry.image
    }

    static func store(_ image: NSImage, for rowID: UUID, key: EditorBlurBackgroundRenderKey) {
        let cost = Int(image.size.width * image.size.height) * 4
        cache.setObject(EditorBlurRaster(key: key, image: image), forKey: rowID as NSUUID, cost: cost)
    }

    static func remove(_ rowID: UUID) {
        cache.removeObject(forKey: rowID as NSUUID)
    }

    /// Called when a different project is applied — the outgoing project's rows will never be
    /// asked for again, and their model-resolution rasters are the largest thing here.
    ///
    /// Gated on the id because the *same* project is re-applied on every iCloud reload, where the
    /// row views are still alive and their rasters still correct; purging there would re-run a
    /// main-actor, model-resolution `ImageRenderer` + `CIGaussianBlur` for every blurred row.
    static func purgeIfProjectChanged(to projectId: UUID) {
        guard loadedProjectId != projectId else { return }
        loadedProjectId = projectId
        cache.removeAllObjects()
    }

    private static var loadedProjectId: UUID?

    static func purgeAll() {
        loadedProjectId = nil
        cache.removeAllObjects()
    }
}

struct EditorRasterizedBackgroundView: View {
    private static let exactRenderDebounce: Duration = .milliseconds(120)

    let row: ScreenshotRow
    let screenshotImages: [String: NSImage]
    let displayScale: CGFloat

    /// The raster this row is currently showing. A strong reference on purpose: the shared cache can
    /// evict under memory pressure, and `.task(id:)` would not re-fire for an on-screen row whose
    /// key hasn't changed — it would fall back to the live `.blur` path for good, which blurs an
    /// already-downsampled raster and so stops matching export. The cache is what survives the
    /// LazyVStack recycling the row; this is what survives eviction while it is on screen.
    @State private var raster: NSImage?
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
            backgroundBlur: row.backgroundBlur,
            spanBackgroundAcrossRow: row.spanBackgroundAcrossRow,
            rowBackgroundDescriptor: .init(
                style: row.backgroundStyle,
                color: row.backgroundColorData,
                gradient: row.gradientConfig,
                image: row.backgroundImageConfig,
                blur: row.backgroundBlur
            ),
            templateBackgroundDescriptors: row.templates.map {
                .init(
                    id: $0.id,
                    overrideBackground: $0.overrideBackground,
                    background: .init(
                        style: $0.backgroundStyle,
                        color: $0.backgroundColor,
                        gradient: $0.gradientConfig,
                        image: $0.backgroundImageConfig,
                        blur: $0.backgroundBlur
                    )
                )
            },
            imageTokens: imageTokens
        )
    }

    var body: some View {
        // Compute the (allocation-heavy) render key once per body evaluation and
        // reuse it for the cache comparison and the `.task` id/body.
        let key = renderKey
        // Prefer the view's own raster, then the shared cache — a recycled row has lost the former
        // but can still paint immediately from the latter.
        let image = (renderedKey == key ? raster : nil) ?? EditorBlurRasterCache.raster(for: row.id, key: key)
        return Group {
            if row.hasBlurredBackground, let image {
                Image(nsImage: image)
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
        .task(id: key) {
            guard row.hasBlurredBackground else {
                EditorBlurRasterCache.remove(row.id)
                raster = nil
                renderedKey = nil
                return
            }
            // A row that just scrolled back in already has its raster in the shared cache; adopt it
            // rather than re-rendering, which is the whole point of the cache outliving the view.
            if let cached = EditorBlurRasterCache.raster(for: row.id, key: key) {
                PerfSignpost.event("EditorBlurRaster.adopted")
                raster = cached
                renderedKey = key
                return
            }
            try? await Task.sleep(for: Self.exactRenderDebounce)
            guard !Task.isCancelled else { return }
            // Blur the background at model resolution, then downscale for the editor.
            // This avoids edge artifacts from blurring an already downsampled tile/image raster.
            let image = RowRenderer.renderComposedBackgroundImage(
                row: row,
                screenshotImages: screenshotImages,
                displayScale: renderScale,
                labelPrefix: "editor"
            )
            guard !Task.isCancelled else { return }
            EditorBlurRasterCache.store(image, for: row.id, key: key)
            raster = image
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
        let templateModelSize = row.templateSize

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
                    ForEach(Array(row.templates.enumerated()), id: \.element.id) { index, template in
                        // Skip slots an opaque override will cover: stacking two layers with
                        // coincident antialiased edges lets the row color bleed through as a
                        // hairline ring around the template at fractional display scales.
                        if !(template.overrideBackground && template.backgroundFullyCovers) {
                            row.resolvedBackgroundView(screenshotImages: screenshotImages, modelSize: templateModelSize)
                                .frame(width: displayTemplateWidth, height: displayTemplateHeight)
                                .offset(x: CGFloat(index) * displayTemplateWidth, y: 0)
                        }
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

    private var templateModelSize: CGSize { row.templateSize }

    var body: some View {
        HStack(spacing: 0) {
            ForEach(row.templates) { template in
                if template.overrideBackground {
                    if template.backgroundBlur > 0 {
                        BackgroundBlurView(
                            width: displayTemplateWidth,
                            height: displayTemplateHeight,
                            blurRadius: template.backgroundBlur * displayScale
                        ) {
                            template.resolvedBackgroundView(screenshotImages: screenshotImages, modelSize: templateModelSize)
                                .frame(width: displayTemplateWidth, height: displayTemplateHeight)
                        }
                    } else {
                        template.resolvedBackgroundView(screenshotImages: screenshotImages, modelSize: templateModelSize)
                            .frame(width: displayTemplateWidth, height: displayTemplateHeight)
                    }
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
