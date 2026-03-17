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
        scale: CGFloat = 1.0,
        screenshotImages: [String: NSImage] = [:],
        localeState: LocaleState = .default,
        onProgress: (@MainActor (Int) -> Void)? = nil
    ) async throws -> URL {
        let rootName = sanitizedRootFolderName(projectName)
        let rootFolder = uniqueFolder(named: rootName, in: folderURL)
        try FileManager.default.createDirectory(at: rootFolder, withIntermediateDirectories: true)

        let multiLocale = localeState.locales.count > 1
        let localesToExport = multiLocale ? localeState.locales : [localeState.locales.first ?? LocaleDefinition(code: "en", label: "English")]
        let exportScale = max(0.1, scale)

        var completed = 0
        // Track the previous encoding task so we can pipeline:
        // render template N on main while encoding template N-1 in background.
        var previousEncodeTask: Task<Void, any Error>?

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

                for (index, _) in row.templates.enumerated() {
                    // Render on main (ImageRenderer requirement) — runs concurrently
                    // with the previous template's background encoding.
                    let image = renderTemplateImage(
                        index: index,
                        row: row,
                        scale: exportScale,
                        screenshotImages: screenshotImages,
                        localeCode: locale.code,
                        localeState: localeState
                    )

                    // Await the previous encoding before starting a new one
                    try await previousEncodeTask?.value

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

    private static func uniqueFolder(named baseName: String, in parent: URL) -> URL {
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
        scale: CGFloat,
        screenshotImages: [String: NSImage] = [:],
        localeCode: String? = nil,
        localeState: LocaleState = .default
    ) -> Data? {
        let image = renderTemplateImage(index: index, row: row, scale: scale, screenshotImages: screenshotImages, localeCode: localeCode, localeState: localeState)
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

    @MainActor
    static func renderTemplateImage(index: Int, row: ScreenshotRow, scale: CGFloat = 1.0, screenshotImages: [String: NSImage] = [:], localeCode: String? = nil, localeState: LocaleState = .default) -> NSImage {
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

        let templateSize = CGSize(width: row.templateWidth, height: row.templateHeight)
        let view = ZStack(alignment: .topLeading) {
            // Background
            if row.isSpanningBackground && !template.overrideBackground {
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
            } else if template.overrideBackground {
                template.resolvedBackgroundView(screenshotImages: screenshotImages, modelSize: templateSize)
                    .frame(width: row.templateWidth, height: row.templateHeight)
            } else {
                row.resolvedBackgroundView(screenshotImages: screenshotImages, modelSize: templateSize)
                    .frame(width: row.templateWidth, height: row.templateHeight)
            }
            ForEach(visibleShapes) { shape in
                CanvasShapeView(
                    shape: shape.duplicated(offsetX: -tLeft),
                    displayScale: 1.0,
                    isSelected: false,
                    screenshotImage: shape.displayImageFileName.flatMap { screenshotImages[$0] },
                    defaultDeviceBodyColor: row.defaultDeviceBodyColor,

                    showsEditorHelpers: false,
                    onSelect: {},
                    onUpdate: { _ in },
                    onDelete: {}
                )
            }
        }
        .frame(width: row.templateWidth, height: row.templateHeight, alignment: .topLeading)
        .clipped()

        let renderer = ImageRenderer(content: view)
        renderer.scale = max(0.1, scale)
        renderer.proposedSize = ProposedViewSize(
            width: row.templateWidth,
            height: row.templateHeight
        )

        if let cgImage = renderer.cgImage {
            return NSImage(cgImage: cgImage, size: NSSize(width: row.templateWidth, height: row.templateHeight))
        }
        return NSImage(size: NSSize(width: row.templateWidth, height: row.templateHeight))
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
