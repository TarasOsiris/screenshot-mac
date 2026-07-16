#if os(macOS)
import Foundation
import MCP
import SwiftUI

extension MCPToolExecutor {

    struct ImportResult: Encodable {
        let imported: Int
        let failures: [String]
        let row: MCPRowSnapshot
    }

    func importScreenshots(_ args: MCPArguments) throws -> CallTool.Result {
        let rowIndex = try requireRowIndex(args)
        guard let paths = args.stringArray("paths"), !paths.isEmpty else {
            throw MCPToolError.missingArgument("paths")
        }

        var images: [NSImage] = []
        var failures: [String] = []
        for path in paths {
            if let image = NSImage(contentsOfFile: path) {
                images.append(image)
            } else {
                failures.append("Could not load \(path)")
            }
        }
        guard !images.isEmpty else {
            throw MCPToolError.failed("No images could be loaded: \(failures.joined(separator: "; "))")
        }

        let rowId = state.rows[rowIndex].id
        let imported = state.batchImportImages(images, into: rowId, maxTemplatesPerRow: args.int("max_templates_per_row"))
        if imported < images.count {
            failures.append("\(images.count - imported) image(s) were not imported (column cap reached?)")
        }

        return try MCPResultEncoding.result(ImportResult(
            imported: imported,
            failures: failures,
            row: MCPSnapshotBuilder.rowSnapshot(state.rows[rowIndex], index: rowIndex, localeState: state.localeState)
        ))
    }

    func renderPreview(_ args: MCPArguments) throws -> CallTool.Result {
        let rowIndex = try requireRowIndex(args)
        let row = state.rows[rowIndex]
        guard !row.templates.isEmpty else {
            throw MCPToolError.failed("Row has no template columns")
        }

        let localeCode = args.string("locale") ?? state.localeState.activeLocaleCode
        if args.has("locale"), !state.localeState.locales.contains(where: { $0.code == localeCode }) {
            throw MCPToolError.notFound("Locale \(localeCode)")
        }

        let maxDimension = CGFloat(min(max(args.int("max_dimension") ?? 700, 100), 1200))
        let images = state.loadFullResolutionImages(forRow: row, localeCode: localeCode)

        let image: NSImage
        if let templateIndex = args.int("template_index") {
            guard row.templates.indices.contains(templateIndex) else {
                throw MCPToolError.invalidArgument("template_index", "row has \(row.templates.count) columns")
            }
            let scale = min(1, maxDimension / max(row.templateWidth, row.templateHeight))
            image = ExportService.renderSingleTemplateImage(
                index: templateIndex,
                row: row,
                screenshotImages: images,
                localeCode: localeCode,
                localeState: state.localeState,
                availableFontFamilies: state.availableFontFamilySet,
                displayScale: scale
            )
        } else {
            let totalWidth = row.templateWidth * CGFloat(row.templates.count)
            let scale = min(1, maxDimension / max(totalWidth, row.templateHeight))
            image = ExportService.renderRowImage(
                row: row,
                screenshotImages: images,
                localeCode: localeCode,
                localeState: state.localeState,
                availableFontFamilies: state.availableFontFamilySet,
                displayScale: scale
            )
        }

        guard let png = ExportService.pngData(from: image) else {
            throw MCPToolError.failed("Preview rendering produced no image data")
        }

        let pixelSize = "\(Int(image.size.width))x\(Int(image.size.height))"
        return CallTool.Result(content: [
            .image(data: png.base64EncodedString(), mimeType: "image/png"),
            .text("Rendered row \(rowIndex) (\(row.displayLabel)) at \(pixelSize), locale \(localeCode)"),
        ])
    }
}
#endif
