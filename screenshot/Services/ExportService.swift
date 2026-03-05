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

            for (index, template) in row.templates.enumerated() {
                let image = renderTemplate(template: template, row: row)
                let filename = "screenshot-\(index + 1).png"
                let fileURL = destFolder.appendingPathComponent(filename)
                try savePNG(image: image, to: fileURL)
            }
        }
    }

    private static func exportFolderName(for row: ScreenshotRow) -> String {
        let name = "\(row.label) — \(Int(row.templateWidth))x\(Int(row.templateHeight))"
        return name.replacingOccurrences(of: "/", with: "-")
            .replacingOccurrences(of: "\\", with: "-")
    }

    @MainActor
    private static func renderTemplate(template: ScreenshotTemplate, row: ScreenshotRow) -> NSImage {
        let view = ScreenshotTemplateView(
            template: template,
            displayWidth: row.templateWidth,
            displayHeight: row.templateHeight,
            bgColor: row.bgColor,
            onDelete: nil
        )

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

    private static func savePNG(image: NSImage, to url: URL) throws {
        guard let tiffData = image.tiffRepresentation,
              let bitmap = NSBitmapImageRep(data: tiffData),
              let pngData = bitmap.representation(using: .png, properties: [:]) else {
            throw ExportError.renderFailed
        }
        try pngData.write(to: url)
    }
}

enum ExportError: LocalizedError {
    case renderFailed
    case noFolder

    var errorDescription: String? {
        switch self {
        case .renderFailed: "Failed to render screenshot"
        case .noFolder: "No export folder selected"
        }
    }
}
