import SwiftUI
import AppKit

enum ExportImageFormat: String {
    case png
    case jpeg

    var fileExtension: String {
        switch self {
        case .png: return "png"
        case .jpeg: return "jpeg"
        }
    }
}

struct ExportService {
    /// Async export that yields between templates so the UI stays responsive.
    /// Rendering happens on @MainActor (required by ImageRenderer);
    /// image encoding and file I/O are pipelined on a background thread.
    @MainActor
    static func exportAll(
        rows: [ScreenshotRow],
        projectName: String,
        to folderURL: URL,
        format: ExportImageFormat = .png,
        imageProvider: (_ row: ScreenshotRow, _ localeCode: String) -> [String: NSImage],
        localeState: LocaleState = .default,
        availableFontFamilies: Set<String>? = nil,
        onProgress: (@MainActor (Int) -> Void)? = nil
    ) async throws -> URL {
        let rootName = sanitizedRootFolderName(projectName)
        let rootFolder = uniqueFolder(named: rootName, in: folderURL)
        try FileManager.default.createDirectory(at: rootFolder, withIntermediateDirectories: true)

        let multiLocale = localeState.locales.count > 1
        let localesToExport = multiLocale ? localeState.locales : [localeState.locales.first ?? LocaleDefinition(code: "en", label: "English")]

        var completed = 0

        do {
            for locale in localesToExport {
                let localeFolder: URL
                if multiLocale {
                    localeFolder = rootFolder.appendingPathComponent(locale.code)
                    try FileManager.default.createDirectory(at: localeFolder, withIntermediateDirectories: true)
                } else {
                    localeFolder = rootFolder
                }

                let multiRow = rows.count > 1
                var usedFolderNames: [String: Int] = [:]

                for row in rows {
                    let destFolder: URL
                    if multiRow {
                        let baseName = exportFolderName(for: row)
                        let count = usedFolderNames[baseName, default: 0]
                        usedFolderNames[baseName] = count + 1
                        let folderName = count == 0 ? baseName : "\(baseName) (\(count + 1))"
                        destFolder = localeFolder.appendingPathComponent(folderName)
                        try FileManager.default.createDirectory(at: destFolder, withIntermediateDirectories: true)
                    } else {
                        destFolder = localeFolder
                    }

                    let rowImages = imageProvider(row, locale.code)
                    let rowImage = renderRowImage(
                        row: row,
                        screenshotImages: rowImages,
                        localeCode: locale.code,
                        localeState: localeState,
                        availableFontFamilies: availableFontFamilies
                    )

                    // Encode all templates in this row concurrently, then await
                    // before the next row to bound memory usage.
                    try await withThrowingTaskGroup(of: Void.self) { group in
                        for (index, _) in row.templates.enumerated() {
                            try Task.checkCancellation()

                            let image = cropTemplateImage(rowImage, index: index, row: row)

                            let padded = String(format: "%02d", index + 1)
                            let filename = "\(padded)_screenshot.\(format.fileExtension)"
                            let fileURL = destFolder.appendingPathComponent(filename)

                            let fmt = format
                            group.addTask {
                                guard let imageData = encodeImage(image, format: fmt) else {
                                    throw ExportError.renderFailed
                                }
                                try imageData.write(to: fileURL)
                            }

                            completed += 1
                            onProgress?(completed)
                        }
                    }
                }
            }
        } catch {
            try? FileManager.default.removeItem(at: rootFolder)
            throw error
        }

        return rootFolder
    }

    private static func exportFolderName(for row: ScreenshotRow) -> String {
        let name = "\(row.label) — \(Int(row.templateWidth))x\(Int(row.templateHeight))"
        return name.replacingOccurrences(of: "/", with: "-")
            .replacingOccurrences(of: "\\", with: "-")
    }

    private static func sanitizedRootFolderName(_ projectName: String) -> String {
        let trimmed = projectName.trimmingCharacters(in: .whitespacesAndNewlines)
        let candidate = trimmed.isEmpty ? "Screenshots" : trimmed
        let sanitized = candidate
            .replacingOccurrences(of: "/", with: "-")
            .replacingOccurrences(of: "\\", with: "-")
        return sanitized.isEmpty ? "Screenshots" : sanitized
    }

    static func uniqueFolder(named baseName: String, in parent: URL) -> URL {
        let fm = FileManager.default
        let candidate = parent.appendingPathComponent(baseName)
        if !fm.fileExists(atPath: candidate.path) { return candidate }
        var counter = 1
        while true {
            counter += 1
            let numbered = parent.appendingPathComponent("\(baseName) (\(counter))")
            if !fm.fileExists(atPath: numbered.path) { return numbered }
        }
    }

    // MARK: - Row-level rendering (single demo image)

    @MainActor
    static func renderRowImage(
        row: ScreenshotRow,
        screenshotImages: [String: NSImage] = [:],
        localeCode: String? = nil,
        localeState: LocaleState = .default,
        availableFontFamilies: Set<String>? = nil
    ) -> NSImage {
        let count = row.templates.count
        guard count > 0 else {
            return NSImage(size: NSSize(width: 1, height: 1))
        }

        let totalWidth = row.templateWidth * CGFloat(count)
        let resolvedShapes = resolvedExportShapes(row: row, localeCode: localeCode, localeState: localeState)
        let fontFamilies = availableFontFamilies ?? Set(NSFontManager.shared.availableFontFamilies)
        let composedBackground = renderComposedBackgroundImage(
            row: row,
            screenshotImages: screenshotImages,
            displayScale: 1.0,
            labelPrefix: "row"
        )

        let shapesView = RowCanvasShapeLayerView(
            row: row,
            shapes: resolvedShapes,
            displayScale: 1.0,
            shapeContent: { shape, clipRect in
                CanvasShapeView(
                    shape: shape,
                    displayScale: 1.0,
                    isSelected: false,
                    screenshotImage: shape.displayImageFileName.flatMap { screenshotImages[$0] },
                    fillImage: shape.fillImageConfig?.fileName.flatMap { screenshotImages[$0] },
                    defaultDeviceBodyColor: row.defaultDeviceBodyColor,
                    clipBounds: clipRect,
                    showsEditorHelpers: false,
                    onSelect: {},
                    onUpdate: { _ in },
                    onDelete: {},
                    availableFontFamilies: fontFamilies
                )
            }
        )
        let shapesImage = renderViewToImage(
            shapesView,
            width: totalWidth,
            height: row.templateHeight,
            label: "row shapes '\(row.label)'"
        )
        return flattenImage(
            shapesImage,
            over: composedBackground,
            width: totalWidth,
            height: row.templateHeight
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
        let templateModelSize = CGSize(width: row.templateWidth, height: row.templateHeight)

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
    static func renderTemplatePNG(index: Int, row: ScreenshotRow, screenshotImages: [String: NSImage] = [:], localeState: LocaleState = .default) -> Data? {
        let image = renderTemplateImage(index: index, row: row, screenshotImages: screenshotImages, localeCode: localeState.activeLocaleCode, localeState: localeState)
        return opaquePNGData(from: image)
    }

@MainActor
    static func renderTemplateData(
        index: Int,
        row: ScreenshotRow,
        format: ExportImageFormat,
        screenshotImages: [String: NSImage] = [:],
        localeCode: String? = nil,
        localeState: LocaleState = .default
    ) -> Data? {
        let image = renderTemplateImage(index: index, row: row, screenshotImages: screenshotImages, localeCode: localeCode, localeState: localeState)
        return encodeImage(image, format: format)
    }

    nonisolated static func encodeImage(_ image: NSImage, format: ExportImageFormat) -> Data? {
        switch format {
        case .png:
            return opaquePNGData(from: image)
        case .jpeg:
            return opaqueJPEGData(from: image)
        }
    }

    nonisolated private static func drawImage(
        _ image: NSImage,
        into background: NSImage,
        at origin: CGPoint,
        canvasSize: NSSize
    ) -> NSImage {
        let output = NSImage(size: canvasSize)
        output.lockFocus()
        background.draw(in: NSRect(origin: .zero, size: canvasSize))
        image.draw(
            in: NSRect(origin: origin, size: image.size),
            from: NSRect(origin: .zero, size: image.size),
            operation: .sourceOver,
            fraction: 1
        )
        output.unlockFocus()
        return output
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
    @MainActor
    static func renderSingleTemplateImage(
        index: Int,
        row: ScreenshotRow,
        screenshotImages: [String: NSImage] = [:],
        localeCode: String? = nil,
        localeState: LocaleState = .default,
        availableFontFamilies: Set<String>? = nil
    ) -> NSImage {
        let templateWidth = row.templateWidth
        let templateHeight = row.templateHeight
        let templateModelSize = CGSize(width: templateWidth, height: templateHeight)
        let resolvedShapes = resolvedExportShapes(row: row, localeCode: localeCode, localeState: localeState)
        let fontFamilies = availableFontFamilies ?? Set(NSFontManager.shared.availableFontFamilies)

        // --- Background ---
        let template = row.templates[index]
        let backgroundView: AnyView
        if template.overrideBackground {
            backgroundView = AnyView(
                template.resolvedBackgroundView(screenshotImages: screenshotImages, modelSize: templateModelSize)
                    .frame(width: templateWidth, height: templateHeight)
            )
        } else if row.isSpanningBackground {
            // Spanning: render the full-width background and offset to show this template's slice
            let spanModelSize = CGSize(
                width: templateWidth * CGFloat(row.templates.count),
                height: templateHeight
            )
            backgroundView = AnyView(
                row.resolvedBackgroundView(screenshotImages: screenshotImages, modelSize: spanModelSize)
                    .frame(width: spanModelSize.width, height: templateHeight)
                    .offset(x: -CGFloat(index) * templateWidth, y: 0)
                    .frame(width: templateWidth, height: templateHeight, alignment: .topLeading)
                    .clipped()
            )
        } else {
            backgroundView = AnyView(
                row.resolvedBackgroundView(screenshotImages: screenshotImages, modelSize: templateModelSize)
                    .frame(width: templateWidth, height: templateHeight)
            )
        }

        let baseBackgroundImage = renderViewToImage(backgroundView, width: templateWidth, height: templateHeight, label: "single template background [\(index)]")
        let backgroundImage: NSImage
        let blurRadius = template.overrideBackground ? template.backgroundBlur : row.backgroundBlur
        if blurRadius > 0 {
            let blurred = applyGaussianBlur(to: baseBackgroundImage, radius: blurRadius)
            backgroundImage = flattenImage(blurred, over: baseBackgroundImage, width: templateWidth, height: templateHeight)
        } else {
            backgroundImage = baseBackgroundImage
        }

        // --- Shapes ---
        // Filter resolved shapes to those visible in this template, then shift so template origin is at (0,0)
        let templateOriginX = CGFloat(index) * templateWidth
        let tRight = templateOriginX + templateWidth
        let visibleShapes = resolvedShapes.filter { s in
            if s.clipToTemplate == true {
                return row.owningTemplateIndex(for: s) == index
            }
            let bb = s.aabb
            return bb.maxX > templateOriginX && bb.minX < tRight
        }
        let shiftedShapes = visibleShapes.map { shape -> CanvasShapeModel in
            var s = shape
            s.x -= templateOriginX
            return s
        }
        // Build a single-template row for shape rendering
        let singleTemplateRow = ScreenshotRow(
            templates: [template],
            templateWidth: templateWidth,
            templateHeight: templateHeight
        )

        let shapesView = RowCanvasShapeLayerView(
            row: singleTemplateRow,
            shapes: shiftedShapes,
            displayScale: 1.0,
            shapeContent: { shape, clipRect in
                CanvasShapeView(
                    shape: shape,
                    displayScale: 1.0,
                    isSelected: false,
                    screenshotImage: shape.displayImageFileName.flatMap { screenshotImages[$0] },
                    fillImage: shape.fillImageConfig?.fileName.flatMap { screenshotImages[$0] },
                    defaultDeviceBodyColor: row.defaultDeviceBodyColor,
                    clipBounds: clipRect,
                    showsEditorHelpers: false,
                    onSelect: {},
                    onUpdate: { _ in },
                    onDelete: {},
                    availableFontFamilies: fontFamilies
                )
            }
        )
        let shapesImage = renderViewToImage(
            shapesView,
            width: templateWidth,
            height: templateHeight,
            label: "single template shapes [\(index)]"
        )

        return flattenImage(shapesImage, over: backgroundImage, width: templateWidth, height: templateHeight)
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

    private static let ciContext = CIContext()

    /// Applies CIGaussianBlur and crops the result back to the original image bounds.
    /// Uses CIAffineClamp to extend edge pixels so the blur kernel doesn't sample transparent pixels.
    static func applyGaussianBlur(to image: NSImage, radius: Double) -> NSImage {
        guard radius > 0,
              let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else { return image }

        let ciImage = CIImage(cgImage: cgImage)
        let originalExtent = ciImage.extent

        let clamp = CIFilter(name: "CIAffineClamp")!
        clamp.setValue(ciImage, forKey: kCIInputImageKey)
        clamp.setValue(CGAffineTransform.identity, forKey: kCIInputTransformKey)

        let blur = CIFilter(name: "CIGaussianBlur")!
        blur.setValue(clamp.outputImage, forKey: kCIInputImageKey)
        blur.setValue(radius, forKey: kCIInputRadiusKey)

        guard let output = blur.outputImage else { return image }

        let cropped = output.cropped(to: originalExtent)
        guard let blurredCG = ciContext.createCGImage(cropped, from: originalExtent) else { return image }

        return NSImage(cgImage: blurredCG, size: image.size)
    }

    /// Crops a rendered row background back to a single template slot.
    private static func cropImage(_ image: NSImage, x: CGFloat, width: CGFloat, height: CGFloat) -> NSImage {
        guard let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else { return image }

        // bitmapImageRepForCachingDisplay creates bitmaps at screen backing scale (2x on Retina),
        // so cgImage pixel dimensions may be larger than the NSImage logical size.
        let scaleX = CGFloat(cgImage.width) / image.size.width
        let scaleY = CGFloat(cgImage.height) / image.size.height

        let cropRect = CGRect(
            x: max(0, floor(x * scaleX)),
            y: 0,
            width: min(CGFloat(cgImage.width) - max(0, floor(x * scaleX)), ceil(width * scaleX)),
            height: min(CGFloat(cgImage.height), ceil(height * scaleY))
        ).integral

        guard cropRect.width > 0,
              cropRect.height > 0,
              let croppedCG = cgImage.cropping(to: cropRect) else {
            return image
        }

        return NSImage(cgImage: croppedCG, size: NSSize(width: width, height: height))
    }

    @MainActor
    static func renderBlurredViewToImage<V: View>(_ view: V, width: CGFloat, height: CGFloat, radius: Double, label: String) -> NSImage {
        let rendered = renderViewToImage(view, width: width, height: height, label: label)
        let blurred = applyGaussianBlur(to: rendered, radius: radius)
        return flattenImage(blurred, over: rendered, width: width, height: height)
    }

    @MainActor
    static func renderViewToImage<V: View>(_ view: V, width: CGFloat, height: CGFloat, label: String) -> NSImage {
        // Use NSHostingView + layer rendering into an explicit 1x CGContext.
        // bitmapImageRepForCachingDisplay implicitly scales by the screen's
        // backingScaleFactor, which breaks cropImage (it expects 1:1 pixel
        // dimensions matching model space). Rendering via CGContext with exact
        // pixel dimensions guarantees consistent output regardless of display.
        let pixelW = Int(ceil(width))
        let pixelH = Int(ceil(height))
        let rect = NSRect(x: 0, y: 0, width: pixelW, height: pixelH)
        let hostingView = NSHostingView(
            rootView: view
                .frame(width: CGFloat(pixelW), height: CGFloat(pixelH), alignment: .topLeading)
                .clipped()
        )
        hostingView.frame = rect
        hostingView.wantsLayer = true
        hostingView.layer?.contentsScale = 1.0
        hostingView.layoutSubtreeIfNeeded()
        hostingView.displayIfNeeded()

        let colorSpace = CGColorSpaceCreateDeviceRGB()
        guard let ctx = CGContext(
            data: nil, width: pixelW, height: pixelH,
            bitsPerComponent: 8, bytesPerRow: pixelW * 4,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else {
            print("[ExportService] Warning: Failed to create CGContext for \(label)")
            return NSImage(size: NSSize(width: width, height: height))
        }

        // Flip coordinate system — CGContext is bottom-up, AppKit layers are top-down
        ctx.translateBy(x: 0, y: CGFloat(pixelH))
        ctx.scaleBy(x: 1, y: -1)

        hostingView.layer!.render(in: ctx)

        guard let cgImage = ctx.makeImage() else {
            print("[ExportService] Warning: Failed to create image for \(label)")
            return NSImage(size: NSSize(width: width, height: height))
        }

        return NSImage(cgImage: cgImage, size: NSSize(width: width, height: height))
    }

    /// Composites the blurred image over the original rendered background to remove edge alpha fringes.
    @MainActor
    static func flattenImage(_ image: NSImage, over background: NSImage, width: CGFloat, height: CGFloat) -> NSImage {
        let flattened = NSImage(size: NSSize(width: width, height: height))
        flattened.lockFocus()
        let rect = NSRect(x: 0, y: 0, width: width, height: height)
        background.draw(in: rect)
        image.draw(in: rect, from: .zero, operation: .sourceOver, fraction: 1)
        flattened.unlockFocus()
        return flattened
    }

    private static func normalizeDeviceAspectIfNeeded(_ shape: CanvasShapeModel) -> CanvasShapeModel {
        guard shape.type == .device else { return shape }

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

    static func pngData(from image: NSImage) -> Data? {
        guard let tiffData = image.tiffRepresentation,
              let bitmap = NSBitmapImageRep(data: tiffData),
              let pngData = bitmap.representation(using: .png, properties: [:]) else { return nil }
        return pngData
    }

    /// Encode PNG with no alpha channel by flattening onto an opaque white background.
    nonisolated static func opaquePNGData(from image: NSImage) -> Data? {
        guard let bitmap = opaqueBitmap(from: image) else { return nil }
        return bitmap.representation(using: .png, properties: [:])
    }

    /// Encode JPEG from an opaque bitmap so transparent pixels are composited consistently.
    static func opaqueJPEGData(from image: NSImage, compression: CGFloat = 0.9) -> Data? {
        guard let bitmap = opaqueBitmap(from: image) else { return nil }
        let properties: [NSBitmapImageRep.PropertyKey: Any] = [.compressionFactor: compression]
        return bitmap.representation(using: .jpeg, properties: properties)
    }

    /// Composite onto white background via CGContext, returning an opaque NSBitmapImageRep directly.
    private static func opaqueBitmap(from image: NSImage) -> NSBitmapImageRep? {
        guard let source = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else { return nil }
        let w = source.width
        let h = source.height
        guard w > 0, h > 0 else { return nil }

        let colorSpace = CGColorSpaceCreateDeviceRGB()
        guard let ctx = CGContext(
            data: nil, width: w, height: h,
            bitsPerComponent: 8, bytesPerRow: w * 4,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue
        ) else { return nil }

        let rect = CGRect(x: 0, y: 0, width: w, height: h)
        ctx.setFillColor(CGColor.white)
        ctx.fill(rect)
        ctx.draw(source, in: rect)

        guard let opaqueRef = ctx.makeImage() else { return nil }
        return NSBitmapImageRep(cgImage: opaqueRef)
    }
}

enum ExportError: LocalizedError {
    case renderFailed

    var errorDescription: String? {
        switch self {
        case .renderFailed: "Failed to render screenshot"
        }
    }
}
