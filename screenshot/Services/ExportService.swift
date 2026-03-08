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
    @MainActor
    static func exportAll(
        rows: [ScreenshotRow],
        projectName: String,
        to folderURL: URL,
        format: ExportImageFormat = .png,
        scale: CGFloat = 1.0,
        screenshotImages: [String: NSImage] = [:]
    ) throws -> URL {
        let rootName = sanitizedRootFolderName(projectName)
        let rootFolder = folderURL.appendingPathComponent(rootName)
        try FileManager.default.createDirectory(at: rootFolder, withIntermediateDirectories: true)

        let multiRow = rows.count > 1
        var usedFolderNames: [String: Int] = [:]
        let exportScale = max(0.1, scale)

        for row in rows {
            let destFolder: URL
            if multiRow {
                let baseName = exportFolderName(for: row)
                let count = usedFolderNames[baseName, default: 0]
                usedFolderNames[baseName] = count + 1
                let folderName = count == 0 ? baseName : "\(baseName) (\(count + 1))"
                destFolder = rootFolder.appendingPathComponent(folderName)
                try FileManager.default.createDirectory(at: destFolder, withIntermediateDirectories: true)
            } else {
                destFolder = rootFolder
            }

            for (index, _) in row.templates.enumerated() {
                guard let imageData = renderTemplateData(
                    index: index,
                    row: row,
                    format: format,
                    scale: exportScale,
                    screenshotImages: screenshotImages
                ) else {
                    throw ExportError.renderFailed
                }
                let filename = "screenshot-\(index + 1).\(format.fileExtension)"
                let fileURL = destFolder.appendingPathComponent(filename)
                try imageData.write(to: fileURL)
            }
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

    // MARK: - Shared Rendering

    @MainActor
    static func renderTemplatePNG(index: Int, row: ScreenshotRow, screenshotImages: [String: NSImage] = [:]) -> Data? {
        let image = renderTemplateImage(index: index, row: row, screenshotImages: screenshotImages)
        return pngData(from: image)
    }

    @MainActor
    static func renderTemplateData(
        index: Int,
        row: ScreenshotRow,
        format: ExportImageFormat,
        scale: CGFloat,
        screenshotImages: [String: NSImage] = [:]
    ) -> Data? {
        let image = renderTemplateImage(index: index, row: row, scale: scale, screenshotImages: screenshotImages)
        switch format {
        case .png:
            return pngData(from: image)
        case .jpeg:
            return jpegData(from: image)
        }
    }

    @MainActor
    static func renderTemplateImage(index: Int, row: ScreenshotRow, scale: CGFloat = 1.0, screenshotImages: [String: NSImage] = [:]) -> NSImage {
        let tLeft = CGFloat(index) * row.templateWidth
        let visibleShapes = row.visibleShapes(forTemplateAt: index)
            .map { normalizeDeviceAspectIfNeeded($0) }

        let view = ZStack {
            row.effectiveBackgroundFill(forTemplateAt: index)
            ForEach(visibleShapes) { shape in
                CanvasShapeView(
                    shape: shape.duplicated(offsetX: -tLeft),
                    displayScale: 1.0,
                    isSelected: false,
                    screenshotImage: shape.displayImageFileName.flatMap { screenshotImages[$0] },

                    showsEditorHelpers: false,
                    onSelect: {},
                    onUpdate: { _ in },
                    onDelete: {}
                )
            }
        }
        .frame(width: row.templateWidth, height: row.templateHeight)
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

        let category = shape.deviceCategory ?? .iphone
        let base = category.baseDimensions
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

    static func jpegData(from image: NSImage, compression: CGFloat = 0.9) -> Data? {
        guard let tiffData = image.tiffRepresentation,
              let bitmap = NSBitmapImageRep(data: tiffData) else { return nil }
        let properties: [NSBitmapImageRep.PropertyKey: Any] = [.compressionFactor: compression]
        return bitmap.representation(using: .jpeg, properties: properties)
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
