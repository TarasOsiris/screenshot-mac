#if os(macOS)
import Foundation
import MCP
import SwiftUI

extension MCPToolExecutor {

    struct ImportResult: Encodable {
        let imported: Int
        /// The locale the images were actually written into, omitted when nothing was written.
        /// Present so a caller can assert on it instead of trusting that the app window happened
        /// to be on the locale it meant.
        let locale: String?
        let failures: [String]
        let row: MCPRowSnapshot
    }

    func importScreenshots(_ args: MCPArguments) async throws -> CallTool.Result {
        let rowIndex = try requireRowIndex(args)
        guard let paths = args.stringArray("paths"), !paths.isEmpty else {
            throw MCPToolError.missingArgument("paths")
        }

        var sources: [ImageImportSource] = []
        var failures: [String] = []
        for path in paths {
            // The NSImage is still needed for size/device detection, but it reads header metadata
            // only — the source URL lets the import copy already-PNG bytes instead of re-encoding.
            if let image = NSImage(contentsOfFile: path) {
                sources.append(ImageImportSource(image: image, sourceURL: URL(fileURLWithPath: path)))
            } else {
                failures.append("Could not load \(path)")
            }
        }
        guard !sources.isEmpty else {
            throw MCPToolError.unreadableFiles(
                "No images could be loaded: \(failures.joined(separator: "; ")). \(MCPToolCatalog.screenshotStagingHint)"
            )
        }

        // Without an explicit locale this falls back to whatever the window is showing, which is
        // invisible to an MCP caller — the reason a locale sweep used to file every language's
        // screenshots under one locale and report success for all of them. A present-but-unusable
        // value has to fail rather than fall back, or it reintroduces exactly that.
        let targetLocale: ImageImportLocale
        let writtenLocale: String
        if args.has("locale") {
            guard let requested = args.string("locale"), !requested.isEmpty else {
                throw MCPToolError.invalidArgument("locale", "expected a locale code such as \"de-DE\"")
            }
            guard state.localeState.locales.contains(where: { $0.code == requested })
                    || requested == state.localeState.baseLocaleCode else {
                throw MCPToolError.notFound("Locale \(requested)")
            }
            targetLocale = .locale(requested)
            writtenLocale = requested
        } else {
            targetLocale = .active
            writtenLocale = state.localeState.activeLocaleCode
        }

        let rowId = state.rows[rowIndex].id
        let imported = await state.batchImportImages(sources, into: rowId,
                                                     maxTemplatesPerRow: args.int("max_templates_per_row"),
                                                     source: .mcp, targetLocale: targetLocale)
        if imported < sources.count {
            failures.append("\(sources.count - imported) image(s) were not imported (column cap reached?)")
        }

        return try MCPResultEncoding.result(ImportResult(
            imported: imported,
            locale: imported > 0 ? writtenLocale : nil,
            failures: failures,
            row: MCPSnapshotBuilder.rowSnapshot(state.rows[rowIndex], index: rowIndex, localeState: state.localeState)
        ))
    }

    func renderPreview(_ args: MCPArguments) async throws -> CallTool.Result {
        let checkout = try await requireCheckout(args)
        defer { checkout.dispose() }
        let rowId = try args.uuid("row_id")
        guard let rowIndex = checkout.rows.firstIndex(where: { $0.id == rowId }) else {
            throw MCPToolError.notFound("Row \(rowId.uuidString)")
        }
        let row = checkout.rows[rowIndex]
        guard !row.templates.isEmpty else {
            throw MCPToolError.failed("Row has no template columns")
        }

        let localeCode = args.string("locale") ?? checkout.localeState.activeLocaleCode
        if args.has("locale"), !checkout.localeState.locales.contains(where: { $0.code == localeCode }) {
            throw MCPToolError.notFound("Locale \(localeCode)")
        }

        let maxDimension = CGFloat(min(max(args.int("max_dimension") ?? 700, 100), 1200))
        let templateIndex = args.int("template_index")
        if let templateIndex, !row.templates.indices.contains(templateIndex) {
            throw MCPToolError.invalidArgument("template_index", "row has \(row.templates.count) columns")
        }
        let fullWidth = templateIndex == nil ? row.templateWidth * CGFloat(row.templates.count) : row.templateWidth
        var imageCache: [String: NSImage] = [:]
        let context = RowRenderContext.load(
            row: row,
            localeCode: localeCode,
            from: checkout,
            displayScale: min(1, maxDimension / max(fullWidth, row.templateHeight)),
            label: "mcp preview",
            cache: &imageCache
        )
        let image = templateIndex.map(context.templateImage(at:)) ?? context.rowImage()

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
