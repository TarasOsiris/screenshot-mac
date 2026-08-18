import SwiftUI
#if os(macOS)
import AppKit
#else
import UIKit
#endif

// Renders a row, a single template, or a showcase sheet to an image. Builds the same SwiftUI
// tree the editor draws (see Rendering/RowCanvasLayers) so export and preview cannot diverge.
extension ExportService {
    // Filename & folder-name construction moved to `ExportFileNaming`.

    // MARK: - Showcase rendering (gallery layout with spacing & rounded corners)

    @MainActor
    static func renderShowcaseRowImage(
        row: ScreenshotRow,
        screenshotImages: [String: NSImage] = [:],
        localeCode: String? = nil,
        localeState: LocaleState = .default,
        availableFontFamilies: Set<String>? = nil,
        config: ShowcaseExportConfig = .init()
    ) -> NSImage {
        let count = row.templates.count
        guard count > 0 else {
            return NSImage(size: NSSize(width: 1, height: 1))
        }

        let layout = ShowcaseLayout(row: row, config: config)

        let rowBackground = precomposedRowBackgroundIfNeeded(
            row: row,
            screenshotImages: screenshotImages,
            displayScale: 1.0,
            labelPrefix: "showcase row"
        )
        var templateImages: [NSImage] = []
        for index in 0..<count {
            templateImages.append(renderSingleTemplateImage(
                index: index,
                row: row,
                screenshotImages: screenshotImages,
                localeCode: localeCode,
                localeState: localeState,
                availableFontFamilies: availableFontFamilies,
                preRenderedRowBackground: rowBackground
            ))
        }

        let totalSize = CGSize(width: layout.totalWidth, height: layout.totalHeight)
        let outputScale = layout.outputScale(maxDimension: config.maxOutputDimension)
        let outputSize = layout.outputSize(maxDimension: config.maxOutputDimension)
        let showcaseView = ShowcaseRowView(
            templateImages: templateImages,
            templateWidth: row.templateWidth,
            templateHeight: row.templateHeight,
            layout: layout,
            background: config.resolvedBackgroundView(screenshotImages: screenshotImages, modelSize: totalSize)
                .frame(width: outputSize.width, height: outputSize.height),
            scale: outputScale
        )

        return renderViewToImage(
            showcaseView,
            width: outputSize.width,
            height: outputSize.height,
            label: "showcase row '\(row.label)'"
        )
    }

    // MARK: - Row-level rendering (single demo image)

    @MainActor
    static func renderRowImage(
        row: ScreenshotRow,
        screenshotImages: [String: NSImage] = [:],
        localeCode: String? = nil,
        localeState: LocaleState = .default,
        availableFontFamilies: Set<String>? = nil,
        displayScale: CGFloat = 1.0
    ) -> NSImage {
        let count = row.templates.count
        guard count > 0 else {
            return NSImage(size: NSSize(width: 1, height: 1))
        }

        let totalWidth = row.templateWidth * CGFloat(count)
        let renderWidth = totalWidth * displayScale
        let renderHeight = row.templateHeight * displayScale
        let resolvedShapes = resolvedExportShapes(row: row, localeCode: localeCode, localeState: localeState)
        let fontFamilies = availableFontFamilies ?? PlatformFonts.familyNameSet
        let composedBackground = renderComposedBackgroundImage(
            row: row,
            screenshotImages: screenshotImages,
            displayScale: displayScale,
            labelPrefix: "row"
        )

        let shapesView = RowCanvasShapeLayerView(
            row: row,
            shapes: resolvedShapes,
            displayScale: displayScale,
            shapeContent: { shape, clipRect in
                CanvasShapeView(
                    shape: shape,
                    displayScale: displayScale,
                    isSelected: false,
                    screenshotImage: shape.displayImageFileName.flatMap { screenshotImages[$0] },
                    screenshotImageIdentity: shape.displayImageFileName,
                    fillImage: shape.fillImageConfig?.fileName.flatMap { screenshotImages[$0] },
                    defaultDeviceBodyColor: row.defaultDeviceBodyColor,
                    clipBounds: clipRect,
                    showsEditorHelpers: false,
                    availableFontFamilies: fontFamilies
                )
            }
        )
        let shapesImage = renderViewToImage(
            shapesView,
            width: renderWidth,
            height: renderHeight,
            label: "row shapes '\(row.label)'"
        )
        return flattenImage(
            shapesImage,
            over: composedBackground,
            width: renderWidth,
            height: renderHeight
        )
    }

    // MARK: - Shared Rendering

    @MainActor
    static func renderComposedBackgroundImage(
        row: ScreenshotRow,
        screenshotImages: [String: NSImage] = [:],
        displayScale: CGFloat,
        labelPrefix: String
    ) -> NSImage {
        let totalWidth = row.templateWidth * displayScale * CGFloat(row.templates.count)
        let totalHeight = row.templateHeight * displayScale
        let baseBackgroundImage = renderViewToImage(
            RowCanvasBaseBackgroundView(
                row: row,
                screenshotImages: screenshotImages,
                displayScale: displayScale
            ),
            width: totalWidth,
            height: totalHeight,
            label: "\(labelPrefix) base background '\(row.label)'"
        )
        let backgroundImage: NSImage
        if row.backgroundBlur > 0 {
            let blurred = applyGaussianBlur(to: baseBackgroundImage, radius: row.backgroundBlur * displayScale)
            backgroundImage = flattenImage(
                blurred,
                over: baseBackgroundImage,
                width: totalWidth,
                height: totalHeight
            )
        } else {
            backgroundImage = baseBackgroundImage
        }

        return renderOverrideBackgroundImage(
            row: row,
            screenshotImages: screenshotImages,
            displayScale: displayScale,
            labelPrefix: labelPrefix,
            over: backgroundImage
        )
    }

    @MainActor
    private static func renderOverrideBackgroundImage(
        row: ScreenshotRow,
        screenshotImages: [String: NSImage],
        displayScale: CGFloat,
        labelPrefix: String,
        over backgroundImage: NSImage
    ) -> NSImage {
        let totalWidth = row.templateWidth * displayScale * CGFloat(row.templates.count)
        let totalHeight = row.templateHeight * displayScale

        guard row.templates.contains(where: \.overrideBackground) else {
            return backgroundImage
        }

        var composited = backgroundImage
        let templateWidth = row.templateWidth * displayScale
        let templateHeight = row.templateHeight * displayScale
        let templateModelSize = row.templateSize

        for (index, template) in row.templates.enumerated() where template.overrideBackground {
            let baseOverride = renderViewToImage(
                template.resolvedBackgroundView(screenshotImages: screenshotImages, modelSize: templateModelSize)
                    .frame(width: templateWidth, height: templateHeight),
                width: templateWidth,
                height: templateHeight,
                label: "\(labelPrefix) override background '\(row.label)' [\(index)]"
            )

            let overrideImage: NSImage
            if template.backgroundBlur > 0 {
                let blurred = applyGaussianBlur(to: baseOverride, radius: template.backgroundBlur * displayScale)
                overrideImage = flattenImage(
                    blurred,
                    over: baseOverride,
                    width: templateWidth,
                    height: templateHeight
                )
            } else {
                overrideImage = baseOverride
            }

            composited = drawImage(
                overrideImage,
                into: composited,
                at: CGPoint(x: CGFloat(index) * templateWidth, y: 0),
                canvasSize: NSSize(width: totalWidth, height: totalHeight)
            )
        }

        return composited
    }

    @MainActor
    static func renderTemplatePNG(
        index: Int,
        row: ScreenshotRow,
        screenshotImages: [String: NSImage] = [:],
        localeState: LocaleState = .default,
        availableFontFamilies: Set<String>? = nil
    ) -> Data? {
        // Per-template render (not the full-row strip) so wide rows export at full resolution
        // instead of being downscaled to fit the GPU texture limit.
        let image = renderSingleTemplateImage(
            index: index, row: row, screenshotImages: screenshotImages,
            localeCode: localeState.activeLocaleCode, localeState: localeState,
            availableFontFamilies: availableFontFamilies
        )
        return opaquePNGData(from: image)
    }

@MainActor
    static func renderTemplateData(
        index: Int,
        row: ScreenshotRow,
        format: ExportImageFormat,
        screenshotImages: [String: NSImage] = [:],
        localeCode: String? = nil,
        localeState: LocaleState = .default,
        availableFontFamilies: Set<String>? = nil
    ) -> Data? {
        let image = renderSingleTemplateImage(
            index: index, row: row, screenshotImages: screenshotImages,
            localeCode: localeCode, localeState: localeState,
            availableFontFamilies: availableFontFamilies
        )
        return encodeImage(image, format: format)
    }

    @MainActor
    static func renderTemplateImage(
        index: Int,
        row: ScreenshotRow,
        screenshotImages: [String: NSImage] = [:],
        localeCode: String? = nil,
        localeState: LocaleState = .default,
        availableFontFamilies: Set<String>? = nil
    ) -> NSImage {
        let rowImage = renderRowImage(
            row: row,
            screenshotImages: screenshotImages,
            localeCode: localeCode,
            localeState: localeState,
            availableFontFamilies: availableFontFamilies
        )
        return cropTemplateImage(rowImage, index: index, row: row)
    }

    /// Renders only the single template at `index` without rendering the full row.
    /// Faster than `renderTemplateImage` which renders all templates then crops.
    /// `displayScale` lets callers render at a fraction of model scale — previews pass a small
    /// scale so they render cheaply and never approach the GPU texture limit; export passes 1.0
    /// for full resolution. Shapes stay in model space (CanvasShapeView multiplies by the scale);
    /// the background crop and final composite work in display pixels (model × scale).
    @MainActor
    static func renderSingleTemplateImage(
        index: Int,
        row: ScreenshotRow,
        screenshotImages: [String: NSImage] = [:],
        localeCode: String? = nil,
        localeState: LocaleState = .default,
        availableFontFamilies: Set<String>? = nil,
        displayScale: CGFloat = 1.0,
        preRenderedRowBackground: NSImage? = nil
    ) -> NSImage {
        let templateWidth = row.templateWidth
        let templateHeight = row.templateHeight
        let pxWidth = templateWidth * displayScale
        let pxHeight = templateHeight * displayScale
        let resolvedShapes = resolvedExportShapes(row: row, localeCode: localeCode, localeState: localeState)
        let fontFamilies = availableFontFamilies ?? PlatformFonts.familyNameSet
        let backgroundImage = renderTemplateBackgroundImage(
            index: index,
            row: row,
            screenshotImages: screenshotImages,
            displayScale: displayScale,
            preRenderedRowBackground: preRenderedRowBackground,
            labelPrefix: "single template"
        )

        // --- Shapes ---
        // Filter resolved shapes to those visible in this template, then shift so template origin is at (0,0)
        let templateOriginX = CGFloat(index) * templateWidth
        let tRight = templateOriginX + templateWidth
        let visibleShapes = resolvedShapes.filter { shape in
            if shape.clipToTemplate == true {
                return row.owningTemplateIndex(for: shape) == index
            }
            let bb = shape.visualAABB
            return bb.maxX > templateOriginX && bb.minX < tRight
        }
        let shiftedShapes = visibleShapes.map { shape -> CanvasShapeModel in
            var s = shape
            s.x -= templateOriginX
            return s
        }
        // Build a single-template row for shape rendering
        let singleTemplateRow = ScreenshotRow(
            templates: [row.templates[index]],
            templateWidth: templateWidth,
            templateHeight: templateHeight
        )

        let shapesView = RowCanvasShapeLayerView(
            row: singleTemplateRow,
            shapes: shiftedShapes,
            displayScale: displayScale,
            shapeContent: { shape, clipRect in
                CanvasShapeView(
                    shape: shape,
                    displayScale: displayScale,
                    isSelected: false,
                    screenshotImage: shape.displayImageFileName.flatMap { screenshotImages[$0] },
                    screenshotImageIdentity: shape.displayImageFileName,
                    fillImage: shape.fillImageConfig?.fileName.flatMap { screenshotImages[$0] },
                    defaultDeviceBodyColor: row.defaultDeviceBodyColor,
                    clipBounds: clipRect,
                    showsEditorHelpers: false,
                    availableFontFamilies: fontFamilies
                )
            }
        )
        let shapesImage = renderViewToImage(
            shapesView,
            width: pxWidth,
            height: pxHeight,
            label: "single template shapes [\(index)]"
        )

        return flattenImage(shapesImage, over: backgroundImage, width: pxWidth, height: pxHeight)
    }

    /// Pre-renders the full-width composed row background only when it's actually needed —
    /// i.e. when the row background is blurred, where the blur must sample across template
    /// boundaries so per-template slicing can't reproduce it. For non-blurred rows this returns
    /// nil and each template renders its own slice (never building the oversized strip), so
    /// callers that loop `renderSingleTemplateImage` should pass the result straight through.
    @MainActor
    static func precomposedRowBackgroundIfNeeded(
        row: ScreenshotRow,
        screenshotImages: [String: NSImage],
        displayScale: CGFloat,
        labelPrefix: String
    ) -> NSImage? {
        guard row.backgroundBlur > 0 else { return nil }
        return renderComposedBackgroundImage(
            row: row,
            screenshotImages: screenshotImages,
            displayScale: displayScale,
            labelPrefix: labelPrefix
        )
    }

    /// Renders a single template's background at `displayScale`, sized to one template rather
    /// than the full-row strip — so wide multi-device rows never exceed the GPU texture limit
    /// (the limit applies to ImageRenderer/NSHostingView rasterization, not CPU compositing).
    /// The strip is only required when the row background is blurred (blur bleeds across template
    /// boundaries); that path renders/reuses the composed strip and crops this template's slice.
    @MainActor
    private static func renderTemplateBackgroundImage(
        index: Int,
        row: ScreenshotRow,
        screenshotImages: [String: NSImage],
        displayScale: CGFloat,
        preRenderedRowBackground: NSImage?,
        labelPrefix: String
    ) -> NSImage {
        let pxWidth = row.templateWidth * displayScale
        let pxHeight = row.templateHeight * displayScale

        // Blurred row background: keep editor/export parity by cropping the full-width composed
        // strip (reused via preRenderedRowBackground when the caller already built it).
        if row.backgroundBlur > 0 {
            let strip = preRenderedRowBackground ?? renderComposedBackgroundImage(
                row: row,
                screenshotImages: screenshotImages,
                displayScale: displayScale,
                labelPrefix: "\(labelPrefix) row"
            )
            return cropImage(strip, x: CGFloat(index) * pxWidth, width: pxWidth, height: pxHeight)
        }

        // Non-blurred: render just this template's slice. Spanning backgrounds render the
        // full-width view offset to this slot (exact same pixels as cropping the strip, but the
        // rasterization target is one template wide); non-spanning renders the row's own
        // background at template size.
        let base: NSImage
        if row.isSpanningBackground {
            let count = row.templates.count
            let spanModelSize = CGSize(width: row.templateWidth * CGFloat(count), height: row.templateHeight)
            let fullWidth = pxWidth * CGFloat(count)
            base = renderViewToImage(
                row.resolvedBackgroundView(screenshotImages: screenshotImages, modelSize: spanModelSize)
                    .frame(width: fullWidth, height: pxHeight)
                    .offset(x: -CGFloat(index) * pxWidth)
                    .frame(width: pxWidth, height: pxHeight, alignment: .topLeading)
                    .clipped(),
                width: pxWidth,
                height: pxHeight,
                label: "\(labelPrefix) span background '\(row.label)' [\(index)]"
            )
        } else {
            base = renderViewToImage(
                row.resolvedBackgroundView(screenshotImages: screenshotImages, modelSize: row.templateSize)
                    .frame(width: pxWidth, height: pxHeight),
                width: pxWidth,
                height: pxHeight,
                label: "\(labelPrefix) background '\(row.label)' [\(index)]"
            )
        }

        // Per-template override drawn over the base (matches renderOverrideBackgroundImage).
        // Override blur is per-template (single slot, no neighbor) so it stays exact here.
        let template = row.templates[index]
        guard template.overrideBackground else { return base }

        let overrideView = template
            .resolvedBackgroundView(screenshotImages: screenshotImages, modelSize: row.templateSize)
            .frame(width: pxWidth, height: pxHeight)
        let overrideLabel = "\(labelPrefix) override background '\(row.label)' [\(index)]"
        let overrideImage: NSImage
        if template.backgroundBlur > 0 {
            overrideImage = renderBlurredViewToImage(
                overrideView,
                width: pxWidth,
                height: pxHeight,
                radius: template.backgroundBlur * displayScale,
                label: overrideLabel
            )
        } else {
            overrideImage = renderViewToImage(overrideView, width: pxWidth, height: pxHeight, label: overrideLabel)
        }
        return flattenImage(overrideImage, over: base, width: pxWidth, height: pxHeight)
    }

    @MainActor
    private static func resolvedExportShapes(row: ScreenshotRow, localeCode: String?, localeState: LocaleState) -> [CanvasShapeModel] {
        let resolvedShapes: [CanvasShapeModel]
        if let localeCode {
            resolvedShapes = row.activeShapes.map {
                LocaleService.resolveShape($0, localeCode: localeCode, localeState: localeState)
            }
        } else {
            resolvedShapes = row.activeShapes
        }
        return resolvedShapes.map(normalizeDeviceAspectIfNeeded)
    }

    private static func cropTemplateImage(_ image: NSImage, index: Int, row: ScreenshotRow) -> NSImage {
        cropImage(
            image,
            x: CGFloat(index) * row.templateWidth,
            width: row.templateWidth,
            height: row.templateHeight
        )
    }

    private static func normalizeDeviceAspectIfNeeded(_ shape: CanvasShapeModel) -> CanvasShapeModel {
        guard shape.type == .device else { return shape }

        // Abstract frames (invisible / generic Android) have no fixed aspect — they flex to the
        // user's screenshot, so normalizing them back to a category aspect undoes that flex and
        // makes the export diverge from the editor.
        if shape.flexesToImageAspect { return shape }

        let base = shape.resolvedBaseDimensions
        let targetAspect = base.width / base.height

        guard shape.width > 0, shape.height > 0 else { return shape }

        var adjusted = shape
        let currentAspect = shape.width / shape.height

        if currentAspect > targetAspect {
            // Too wide: preserve height, reduce width, keep center.
            let newWidth = shape.height * targetAspect
            adjusted.x += (shape.width - newWidth) / 2
            adjusted.width = newWidth
        } else if currentAspect < targetAspect {
            // Too tall: preserve width, reduce height, keep center.
            let newHeight = shape.width / targetAspect
            adjusted.y += (shape.height - newHeight) / 2
            adjusted.height = newHeight
        }

        return adjusted
    }
}
