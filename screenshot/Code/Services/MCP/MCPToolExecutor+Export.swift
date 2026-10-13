#if os(macOS)
import AppKit
import Foundation
import MCP

extension MCPToolExecutor {

    struct ExportResult: Encodable {
        let folder: String
        let files: [String]
        /// Resources that composited to a hole. Empty on a clean export; present so an agent is
        /// told rather than handed a folder of blank device frames with a success message.
        let unrenderable: [String]
    }

    func exportProject(_ args: MCPArguments) async throws -> CallTool.Result {
        let checkout = try await requireCheckout(args)
        defer { checkout.dispose() }
        guard !checkout.rows.isEmpty else {
            throw MCPToolError.expected("Project has no rows to export")
        }

        let format: ExportImageFormat = switch args.string("format") {
        case nil, "png": .png
        case "jpeg", "jpg": .jpeg
        case let other?: throw MCPToolError.invalidArgument("format", "expected png or jpeg, got \(other)")
        }

        let continuous = args.string("layout") == "continuous"
        if continuous, args.string("naming") == ExportNamingScheme.fastlane.rawValue {
            throw MCPToolError.invalidArgument("naming", "fastlane naming is per screenshot, not with continuous layout")
        }

        if let locale = args.string("locale"),
           !checkout.localeState.locales.contains(where: { $0.code == locale }) {
            throw MCPToolError.notFound("Locale \(locale)")
        }

        let rows = try requireRowIds(args, among: checkout.rows).map { ids in checkout.rows.filter { ids.contains($0.id) } } ?? checkout.rows
        let destination: URL
        if let folderPath = args.string("folder_path") {
            destination = URL(fileURLWithPath: (folderPath as NSString).expandingTildeInPath, isDirectory: true)
            do {
                try FileManager.default.createDirectory(at: destination, withIntermediateDirectories: true)
            } catch {
                // Same class as `unreadableFiles`: a sandbox denial on a client-supplied path, and
                // the message names it, so it must stay off Sentry too.
                throw MCPToolError.unreadableFiles("Cannot write to \(destination.path) (sandbox) — omit folder_path to export to a temp folder and copy the files from there")
            }
        } else {
            destination = try ExportService.makeTempExportFolder()
        }

        do {
            let result: (folderURL: URL, fileURLs: [URL], unrenderable: [String])
            if continuous {
                result = try await exportContinuousRows(
                    rows, checkout: checkout, to: destination, format: format,
                    suffix: args.string("file_suffix") ?? "", localeFilter: args.string("locale")
                )
            } else {
                result = try await ExportService.exportAll(
                    rows: rows,
                    projectName: checkout.projectName,
                    to: destination,
                    format: format,
                    source: checkout,
                    localeFilter: args.string("locale"),
                    customSuffix: args.string("file_suffix") ?? "",
                    namingScheme: try args.enumValue("naming", ExportNamingScheme.self) ?? .standard,
                    variants: checkout.document.variants.active
                )
            }
            return try MCPResultEncoding.result(ExportResult(
                folder: result.folderURL.path,
                files: result.fileURLs.map(\.path).sorted(),
                unrenderable: result.unrenderable
            ))
        } catch is CancellationError {
            // Rethrown as-is (not wrapped in .failed) so `call()` can keep it off Sentry.
            throw CancellationError()
        } catch {
            throw MCPToolError.failed("Export failed: \(error.localizedDescription)")
        }
    }

    /// One stitched image per row and locale — the editor's Export Row ▸ Continuous. Row-outer like
    /// `exportAll`, so a blurred row's composed background is built once and reused across locales.
    private func exportContinuousRows(
        _ rows: [ScreenshotRow],
        checkout: ProjectCheckout,
        to destination: URL,
        format: ExportImageFormat,
        suffix: String,
        localeFilter: String?
    ) async throws -> (folderURL: URL, fileURLs: [URL], unrenderable: [String]) {
        let root = ExportFileNaming.uniqueFolder(named: ExportFileNaming.sanitizedRootFolderName(checkout.projectName), in: destination)
        let allLocales = checkout.localeState.locales.map(\.code)
        let locales = allLocales.filter { localeFilter == nil || $0 == localeFilter }
        var fileURLs: [URL] = []
        var unrenderable = Set<String>()
        for (index, row) in rows.enumerated() {
            var imageCache: [String: NSImage] = [:]
            var contexts: [RowRenderContext] = []
            let baseName = (ExportCoordinator.rowFileName(row, index: index) as NSString).deletingPathExtension + suffix
            for locale in locales {
                try Task.checkCancellation()
                // Nested by the project's full locale set, as `exportAll` does, not by the filter.
                let folder = allLocales.count > 1 ? root.appendingPathComponent(locale) : root
                try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
                let context = await RowRenderContext.load(
                    row: row, localeCode: locale, from: checkout, label: "mcp row export",
                    cache: &imageCache, reusing: &contexts
                )
                unrenderable.formUnion(context.unrenderableImageFileNames)
                let image = await context.stitchedRowImage()
                let data = format == .png
                    ? await ExportImageEncoder.opaquePNGDataOffMain(from: image)
                    : ExportImageEncoder.encode(image, format: format)
                guard let data else { throw ExportRenderError.encodingFailed(rowIndex: index) }
                let url = folder.appendingPathComponent(baseName).appendingPathExtension(format.fileExtension)
                try data.write(to: url)
                fileURLs.append(url)
            }
        }
        return (root, fileURLs, unrenderable.sorted())
    }
}
#endif
