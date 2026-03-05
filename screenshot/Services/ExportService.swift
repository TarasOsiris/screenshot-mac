import SwiftUI
import AppKit

struct ExportService {
    static func exportAll(rows: [ScreenshotRow], projectName: String, to folderURL: URL) throws {
        let rootName = projectName.isEmpty ? "Screenshots" : projectName
        let rootFolder = folderURL.appendingPathComponent(rootName)
        try FileManager.default.createDirectory(at: rootFolder, withIntermediateDirectories: true)

        let multiRow = rows.count > 1
        var usedFolderNames: [String: Int] = [:]

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
                guard let pngData = renderTemplatePNG(index: index, row: row) else {
                    throw ExportError.renderFailed
                }
                let filename = "screenshot-\(index + 1).png"
                let fileURL = destFolder.appendingPathComponent(filename)
                try pngData.write(to: fileURL)
            }
        }
    }

    private static func exportFolderName(for row: ScreenshotRow) -> String {
        let name = "\(row.label) — \(Int(row.templateWidth))x\(Int(row.templateHeight))"
        return name.replacingOccurrences(of: "/", with: "-")
            .replacingOccurrences(of: "\\", with: "-")
    }

    // MARK: - Shared Rendering

    @MainActor
    static func renderTemplatePNG(index: Int, row: ScreenshotRow) -> Data? {
        let image = renderTemplateImage(index: index, row: row)
        return pngData(from: image)
    }

    @MainActor
    static func renderTemplateImage(index: Int, row: ScreenshotRow) -> NSImage {
        let tLeft = CGFloat(index) * row.templateWidth
        let visibleShapes = row.visibleShapes(forTemplateAt: index)

        let view = ZStack {
            Rectangle().fill(row.bgColor.gradient)
            ForEach(visibleShapes) { shape in
                CanvasShapeView(
                    shape: shape.duplicated(offsetX: -tLeft),
                    displayScale: 1.0,
                    isSelected: false,
                    onSelect: {},
                    onUpdate: { _ in },
                    onDelete: {}
                )
            }
        }
        .frame(width: row.templateWidth, height: row.templateHeight)
        .clipped()

        let renderer = ImageRenderer(content: view)
        renderer.scale = 1.0
        renderer.proposedSize = ProposedViewSize(
            width: row.templateWidth,
            height: row.templateHeight
        )

        if let cgImage = renderer.cgImage {
            return NSImage(cgImage: cgImage, size: NSSize(width: row.templateWidth, height: row.templateHeight))
        }
        return NSImage(size: NSSize(width: row.templateWidth, height: row.templateHeight))
    }

    static func pngData(from image: NSImage) -> Data? {
        guard let tiffData = image.tiffRepresentation,
              let bitmap = NSBitmapImageRep(data: tiffData),
              let pngData = bitmap.representation(using: .png, properties: [:]) else { return nil }
        return pngData
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
