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
        // Track the previous encoding task so we can pipeline:
        // render template N on main while encoding template N-1 in background.
        var previousEncodeTask: Task<Void, any Error>?

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
                    let cachedBlur = renderBlurredSpanningBackground(row: row, screenshotImages: rowImages)
                    for (index, _) in row.templates.enumerated() {
                        try Task.checkCancellation()

                        // Render on main (ImageRenderer requirement) — runs concurrently
                        // with the previous template's background encoding.
                        let image = renderTemplateImage(
                            index: index,
                            row: row,
                            screenshotImages: rowImages,
                            localeCode: locale.code,
                            localeState: localeState,
                            availableFontFamilies: availableFontFamilies,
                            blurredSpanningBackground: cachedBlur
                        )

                        // Await the previous encoding before starting a new one
                        try await previousEncodeTask?.value
                        try Task.checkCancellation()

                        let padded = String(format: "%02d", index + 1)
                        let filename = "\(padded)_screenshot.\(format.fileExtension)"
                        let fileURL = destFolder.appendingPathComponent(filename)

                        // Offload encoding + file write to background
                        let fmt = format
                        previousEncodeTask = Task.detached {
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

            // Await the final encoding task
            try await previousEncodeTask?.value
        } catch {
            previousEncodeTask?.cancel()
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
    static func renderRowImage(row: ScreenshotRow, screenshotImages: [String: NSImage] = [:], localeCode: String? = nil, localeState: LocaleState = .default) -> NSImage {
        let count = row.templates.count
        guard count > 0 else {
            return NSImage(size: NSSize(width: 1, height: 1))
        }

        let totalWidth = row.templateWidth * CGFloat(count)
        let height = row.templateHeight
        let pixelW = Int(totalWidth)
        let pixelH = Int(height)

        let colorSpace = CGColorSpaceCreateDeviceRGB()
        guard let ctx = CGContext(
            data: nil, width: pixelW, height: pixelH,
            bitsPerComponent: 8, bytesPerRow: pixelW * 4,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else {
            return NSImage(size: NSSize(width: totalWidth, height: height))
        }

        // Render each template and draw immediately so intermediate images are freed
        let cachedBlur = renderBlurredSpanningBackground(row: row, screenshotImages: screenshotImages)
        for i in 0..<count {
            let img = renderTemplateImage(index: i, row: row, screenshotImages: screenshotImages, localeCode: localeCode, localeState: localeState, blurredSpanningBackground: cachedBlur)
            guard let cgImg = img.cgImage(forProposedRect: nil, context: nil, hints: nil) else { continue }
            let x = CGFloat(i) * row.templateWidth
            ctx.draw(cgImg, in: CGRect(x: x, y: 0, width: CGFloat(cgImg.width), height: CGFloat(cgImg.height)))
        }

        guard let composited = ctx.makeImage() else {
            return NSImage(size: NSSize(width: totalWidth, height: height))
        }
        return NSImage(cgImage: composited, size: NSSize(width: totalWidth, height: height))
    }

    // MARK: - Shared Rendering

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

    static func encodeImage(_ image: NSImage, format: ExportImageFormat) -> Data? {
        switch format {
        case .png:
            return opaquePNGData(from: image)
        case .jpeg:
            return opaqueJPEGData(from: image)
        }
    }

    /// Pre-renders the blurred spanning background for a row.
    /// Call once per row and pass the result to each `renderTemplateImage` call to avoid redundant work.
    @MainActor
    static func renderBlurredSpanningBackground(row: ScreenshotRow, screenshotImages: [String: NSImage]) -> NSImage? {
        guard row.backgroundBlur > 0, row.isSpanningBackground else { return nil }
        let totalWidth = row.templateWidth * CGFloat(row.templates.count)
        let spanSize = CGSize(width: totalWidth, height: row.templateHeight)
        let spanView = row.resolvedBackgroundView(screenshotImages: screenshotImages, modelSize: spanSize)
            .frame(width: totalWidth, height: row.templateHeight)
        return renderBlurredViewToImage(
            spanView,
            width: totalWidth,
            height: row.templateHeight,
            radius: row.backgroundBlur,
            label: "blur spanning bg"
        )
    }

    @MainActor
    static func renderTemplateImage(index: Int, row: ScreenshotRow, screenshotImages: [String: NSImage] = [:], localeCode: String? = nil, localeState: LocaleState = .default, availableFontFamilies: Set<String>? = nil, blurredSpanningBackground: NSImage? = nil) -> NSImage {
        let tLeft = CGFloat(index) * row.templateWidth
        let rawShapes = row.visibleShapes(forTemplateAt: index)
        let resolvedShapes: [CanvasShapeModel]
        if let localeCode {
            resolvedShapes = rawShapes.map { LocaleService.resolveShape($0, localeCode: localeCode, localeState: localeState) }
        } else {
            resolvedShapes = rawShapes
        }
        let visibleShapes = resolvedShapes.map { normalizeDeviceAspectIfNeeded($0) }

        let template = row.templates[index]
        let needsBlur = row.backgroundBlur > 0 && !template.overrideBackground
        let blurredBgImage: NSImage? = needsBlur
            ? renderBlurredBackground(
                index: index,
                row: row,
                screenshotImages: screenshotImages,
                cachedSpanningBlur: blurredSpanningBackground
            )
            : nil
        let templateSize = CGSize(width: row.templateWidth, height: row.templateHeight)
        let view = ZStack(alignment: .topLeading) {
            // Background
            if let blurredBgImage {
                Image(nsImage: blurredBgImage)
                    .interpolation(.high)
                    .frame(width: row.templateWidth, height: row.templateHeight)
            } else if template.overrideBackground {
                template.resolvedBackgroundView(screenshotImages: screenshotImages, modelSize: templateSize)
                    .frame(width: row.templateWidth, height: row.templateHeight)
            } else {
                rowBackgroundView(index: index, row: row, screenshotImages: screenshotImages)
            }
            ForEach(visibleShapes) { shape in
                CanvasShapeView(
                    shape: shape.duplicated(offsetX: -tLeft),
                    displayScale: 1.0,
                    isSelected: false,
                    screenshotImage: shape.displayImageFileName.flatMap { screenshotImages[$0] },
                    fillImage: shape.fillImageConfig?.fileName.flatMap { screenshotImages[$0] },
                    defaultDeviceBodyColor: row.defaultDeviceBodyColor,

                    showsEditorHelpers: false,
                    onSelect: {},
                    onUpdate: { _ in },
                    onDelete: {},
                    availableFontFamilies: availableFontFamilies ?? Set(NSFontManager.shared.availableFontFamilies)
                )
            }
        }
        .frame(width: row.templateWidth, height: row.templateHeight, alignment: .topLeading)
        .clipped()

        return renderViewToImage(view, width: row.templateWidth, height: row.templateHeight, label: "template \(index) in row '\(row.label)'")
    }

    /// Returns the row background view for a single template slot (spanning or per-template).
    @MainActor @ViewBuilder
    private static func rowBackgroundView(index: Int, row: ScreenshotRow, screenshotImages: [String: NSImage]) -> some View {
        if row.isSpanningBackground {
            let tLeft = CGFloat(index) * row.templateWidth
            let totalWidth = row.templateWidth * CGFloat(row.templates.count)
            let spanSize = CGSize(width: totalWidth, height: row.templateHeight)
            Color.clear
                .frame(width: row.templateWidth, height: row.templateHeight)
                .overlay(alignment: .topLeading) {
                    row.resolvedBackgroundView(screenshotImages: screenshotImages, modelSize: spanSize)
                        .frame(width: totalWidth, height: row.templateHeight)
                        .offset(x: -tLeft)
                }
                .clipped()
        } else {
            let templateSize = CGSize(width: row.templateWidth, height: row.templateHeight)
            row.resolvedBackgroundView(screenshotImages: screenshotImages, modelSize: templateSize)
                .frame(width: row.templateWidth, height: row.templateHeight)
        }
    }

    /// Renders the background for a single template slot, applies CIGaussianBlur, and returns the result cropped to template bounds.
    /// Pass `cachedSpanningBlur` (from `renderBlurredSpanningBackground`) to avoid re-rendering the full-width image per template.
    @MainActor
    private static func renderBlurredBackground(index: Int, row: ScreenshotRow, screenshotImages: [String: NSImage], cachedSpanningBlur: NSImage? = nil) -> NSImage {
        if row.isSpanningBackground {
            let blurred = cachedSpanningBlur ?? {
                let totalWidth = row.templateWidth * CGFloat(row.templates.count)
                let spanSize = CGSize(width: totalWidth, height: row.templateHeight)
                let spanView = row.resolvedBackgroundView(screenshotImages: screenshotImages, modelSize: spanSize)
                    .frame(width: totalWidth, height: row.templateHeight)
                return renderBlurredViewToImage(
                    spanView,
                    width: totalWidth,
                    height: row.templateHeight,
                    radius: row.backgroundBlur,
                    label: "blur spanning bg"
                )
            }()
            return cropImage(
                blurred,
                x: CGFloat(index) * row.templateWidth,
                width: row.templateWidth,
                height: row.templateHeight
            )
        }

        let bgView = rowBackgroundView(index: index, row: row, screenshotImages: screenshotImages)
        return renderBlurredViewToImage(
            bgView,
            width: row.templateWidth,
            height: row.templateHeight,
            radius: row.backgroundBlur,
            label: "blur bg"
        )
    }

    private static let ciContext = CIContext()

    /// Applies CIGaussianBlur and crops the result back to the original image bounds.
    /// Uses CIAffineClamp to extend edge pixels so the blur kernel doesn't sample transparent pixels.
    private static func applyGaussianBlur(to image: NSImage, radius: Double) -> NSImage {
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

        let cropRect = CGRect(
            x: max(0, floor(x)),
            y: 0,
            width: min(CGFloat(cgImage.width) - max(0, floor(x)), ceil(width)),
            height: min(CGFloat(cgImage.height), ceil(height))
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
    private static func renderViewToImage<V: View>(_ view: V, width: CGFloat, height: CGFloat, label: String) -> NSImage {
        // Use NSHostingView + layer rendering instead of ImageRenderer.
        // ImageRenderer can produce slightly different text glyph metrics than
        // on-screen rendering, causing line-break differences in export.
        // NSHostingView uses the same AppKit/CoreText pipeline as the editor.
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
        hostingView.layoutSubtreeIfNeeded()
        hostingView.displayIfNeeded()

        guard let bitmapRep = hostingView.bitmapImageRepForCachingDisplay(in: rect) else {
            print("[ExportService] Warning: Failed to create bitmap rep for \(label)")
            return NSImage(size: NSSize(width: width, height: height))
        }
        hostingView.cacheDisplay(in: rect, to: bitmapRep)

        let image = NSImage(size: NSSize(width: width, height: height))
        image.addRepresentation(bitmapRep)
        return image
    }

    /// Composites the blurred image over the original rendered background to remove edge alpha fringes.
    @MainActor
    private static func flattenImage(_ image: NSImage, over background: NSImage, width: CGFloat, height: CGFloat) -> NSImage {
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
    static func opaquePNGData(from image: NSImage) -> Data? {
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
