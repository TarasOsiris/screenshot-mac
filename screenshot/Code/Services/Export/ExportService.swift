#if os(macOS)
import AppKit
#else
import UIKit
#endif
import OSLog
import UniformTypeIdentifiers

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
        localeFilter: String? = nil,
        customSuffix: String = "",
        availableFontFamilies: Set<String>? = nil,
        onProgress: (@MainActor (Int) -> Void)? = nil
    ) async throws -> (folderURL: URL, fileURLs: [URL]) {
        let rootName = ExportFileNaming.sanitizedRootFolderName(projectName)
        let rootFolder = ExportFileNaming.uniqueFolder(named: rootName, in: folderURL)
        try FileManager.default.createDirectory(at: rootFolder, withIntermediateDirectories: true)

        // Folder layout is determined by the project's full locale set, not the filter,
        // so a single-locale export still nests under its locale subfolder when the
        // project has multiple locales configured.
        let multiLocale = localeState.locales.count > 1
        let allLocales = localeState.locales.isEmpty
            ? [LocaleDefinition(code: "en", label: "English")]
            : localeState.locales
        let localesToExport: [LocaleDefinition]
        if let localeFilter, let match = allLocales.first(where: { $0.code == localeFilter }) {
            localesToExport = [match]
        } else {
            localesToExport = allLocales
        }

        var completed = 0
        var writtenFileURLs: [URL] = []

        let startedAt = Date()
        CrashReportingService.breadcrumb(.export, "Export started", data: [
            "rows": rows.count,
            "locales": localesToExport.count,
            "templates": rows.reduce(0) { $0 + $1.templates.count },
            "format": format.rawValue,
        ])

        do {
            var localeFolders: [String: URL] = [:]
            for locale in localesToExport {
                let folder = multiLocale ? rootFolder.appendingPathComponent(locale.code) : rootFolder
                if multiLocale {
                    try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
                }
                localeFolders[locale.code] = folder
            }

            // Row subfolder names are deduped per locale folder; rows iterate in the
            // same order for every locale, so the numbering is computed once.
            let multiRow = rows.count > 1
            var usedFolderNames: [String: Int] = [:]
            let rowFolderNames: [String] = rows.map { row in
                let baseName = ExportFileNaming.exportFolderName(for: row)
                let count = usedFolderNames[baseName, default: 0]
                usedFolderNames[baseName] = count + 1
                return count == 0 ? baseName : "\(baseName) (\(count + 1))"
            }

            // Row-outer, locale-inner: locales whose overrides don't touch a row form
            // one group sharing a single render (encoded once, bytes cloned into each
            // locale's folder); each genuinely localized locale is its own group.
            // Backgrounds are locale-independent, so the (blur-only) precomposed row
            // strip is shared across every group of the row.
            for (rowIndex, row) in rows.enumerated() {
                var neutralLocales: [LocaleDefinition] = []
                var localeGroups: [[LocaleDefinition]] = []
                for locale in localesToExport {
                    if LocaleService.rowIsLocaleNeutral(row: row, localeCode: locale.code, localeState: localeState) {
                        neutralLocales.append(locale)
                    } else {
                        localeGroups.append([locale])
                    }
                }
                if !neutralLocales.isEmpty {
                    localeGroups.insert(neutralLocales, at: 0)
                }

                // Every (row, locale) folder receives files, so create them all up
                // front — destFolder stays pure URL construction on the hot path.
                var rowDestFolders: [String: URL] = [:]
                for locale in localesToExport {
                    let base = localeFolders[locale.code] ?? rootFolder
                    let folder = multiRow ? base.appendingPathComponent(rowFolderNames[rowIndex]) : base
                    if multiRow {
                        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
                    }
                    rowDestFolders[locale.code] = folder
                }
                func destFolder(for localeCode: String) -> URL {
                    rowDestFolders[localeCode] ?? rootFolder
                }

                CrashReportingService.breadcrumb(.export, "Exporting row \(rowIndex + 1)/\(rows.count)", data: [
                    "templates": row.templates.count,
                    "locale_groups": localeGroups.count,
                    "pixels": Int(row.templateWidth * row.templateHeight),
                ])

                var context: RowRenderContext?
                for group in localeGroups {
                    let renderCode = group[0].code
                    let images = imageProvider(row, renderCode)
                    // The first group builds the context (and the precomposed background when the
                    // row is blurred); later locales reuse it against their own images.
                    let rowContext = context?.withLocale(renderCode, images: images)
                        ?? RowRenderContext(
                            row: row,
                            images: images,
                            localeCode: renderCode,
                            localeState: localeState,
                            availableFontFamilies: availableFontFamilies ?? PlatformFonts.familyNameSet,
                            label: "export row"
                        )
                    context = rowContext

                    // Encode all templates of this group concurrently, then await
                    // before the next group to bound memory usage.
                    try await withThrowingTaskGroup(of: Int.self) { taskGroup in
                        for index in rowContext.templateIndices {
                            try Task.checkCancellation()

                            let image = rowContext.templateImage(at: index)
                            let fileURLs: [URL] = group.map { locale in
                                let filename = ExportFileNaming.screenshotFileName(row: row, localeCode: locale.code, index: index, customSuffix: customSuffix, format: format)
                                return destFolder(for: locale.code).appendingPathComponent(filename)
                            }
                            writtenFileURLs.append(contentsOf: fileURLs)

                            let fmt = format
                            taskGroup.addTask {
                                guard let imageData = encodeImage(image, format: fmt) else {
                                    throw ExportError.renderFailed
                                }
                                try imageData.write(to: fileURLs[0])
                                // Clone the encoded file into the remaining neutral
                                // locales' folders (APFS makes copies nearly free).
                                for fileURL in fileURLs.dropFirst() {
                                    try FileManager.default.copyItem(at: fileURLs[0], to: fileURL)
                                }
                                return fileURLs.count
                            }

                            // `addTask` doesn't suspend, so without this the whole group's
                            // renders run as one uninterrupted main-actor job — the app-hang
                            // shape of SCREENSHOT-BRO-3. The yielded continuation lands in the
                            // next run-loop pass, giving AppKit a full turn between templates.
                            await Task.yield()
                        }

                        // Report progress as each encode/write actually finishes,
                        // not when it's merely scheduled.
                        for try await written in taskGroup {
                            completed += written
                            onProgress?(completed)
                        }
                    }
                }
            }
        } catch {
            CrashReportingService.breadcrumb(.export, "Export failed", data: [
                "written": completed,
                "elapsed_ms": Int(Date().timeIntervalSince(startedAt) * 1000),
                "cancelled": error is CancellationError,
            ], level: .warning)
            try? FileManager.default.removeItem(at: rootFolder)
            throw error
        }

        CrashReportingService.breadcrumb(.export, "Export finished", data: [
            "files": writtenFileURLs.count,
            "elapsed_ms": Int(Date().timeIntervalSince(startedAt) * 1000),
        ])
        return (rootFolder, writtenFileURLs)
    }

    nonisolated static func encodeImage(_ image: NSImage, format: ExportImageFormat) -> Data? {
        ExportImageEncoder.encode(image, format: format)
    }

    /// Defensive fallback for any export-to-folder path that isn't reachable on iPad (the iPad
    /// menus route through the share sheet instead). Reports clearly rather than silently no-op.
    static let exportUnavailableMessage = String(localized: "Exporting to a folder isn't available on iPad — use the share sheet export instead.")

    /// Creates a unique temporary directory to stage an iPad export before handing it to the
    /// share sheet. The OS reclaims the temp directory, so callers don't clean it up.
    static func makeTempExportFolder() throws -> URL {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("Export-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    /// Saves a single PNG. macOS uses a save panel; iPad writes to a temp file and presents the
    /// system share sheet (Save to Files / AirDrop), since there's no Finder or save panel.
    /// Returns an error message on failure, nil on success or user cancellation.
    @MainActor
    static func savePNGDataViaPanel(defaultName: String, data: () -> Data?) -> String? {
        let safeName = defaultName.isEmpty ? "image" : ExportFileNaming.sanitizedFileName(defaultName)
        #if os(macOS)
        let panel = NSSavePanel()
        panel.nameFieldStringValue = "\(safeName).png"
        panel.allowedContentTypes = [.png]
        guard panel.runModal() == .OK, let url = panel.url else { return nil }
        let didAccess = url.startAccessingSecurityScopedResource()
        defer { if didAccess { url.stopAccessingSecurityScopedResource() } }

        guard let pngData = data() else {
            return ExportError.renderFailed.localizedDescription
        }
        do {
            try pngData.write(to: url)
            return nil
        } catch {
            return error.localizedDescription
        }
        #else
        guard let pngData = data() else {
            return ExportError.renderFailed.localizedDescription
        }
        do {
            let folder = try makeTempExportFolder()
            let fileURL = folder.appendingPathComponent("\(safeName).png")
            try pngData.write(to: fileURL)
            PlatformShare.present(urls: [fileURL]) { _ in
                try? FileManager.default.removeItem(at: folder)
            }
            return nil
        } catch {
            return error.localizedDescription
        }
        #endif
    }

    @MainActor
    static func saveRowImageViaPanel(defaultName: String, render: () -> NSImage) -> String? {
        savePNGDataViaPanel(defaultName: defaultName.isEmpty ? "row" : defaultName) {
            encodeImage(render(), format: .png)
        }
    }

    static func pngData(from image: NSImage) -> Data? {
        ExportImageEncoder.pngData(from: image)
    }

    /// Encode PNG with no alpha channel by flattening onto an opaque white background.
    nonisolated static func opaquePNGData(from image: NSImage) -> Data? {
        ExportImageEncoder.opaquePNGData(from: image)
    }

    /// Encode JPEG from an opaque bitmap so transparent pixels are composited consistently.
    nonisolated static func opaqueJPEGData(from image: NSImage, compression: CGFloat = 0.9) -> Data? {
        ExportImageEncoder.opaqueJPEGData(from: image, compression: compression)
    }
}
