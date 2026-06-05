#if os(macOS)
import AppKit
#else
import UIKit
#endif
import StoreKit
import SwiftUI

private enum ExportRenderError: LocalizedError {
    case encodingFailed(rowIndex: Int)
    nonisolated var errorDescription: String? {
        switch self {
        case .encodingFailed(let index):
            return String(localized: "Failed to render row \(index + 1)")
        }
    }
}

extension View {
    /// Presents the shared "Export Failed" alert bound to `message`. Applied at the editor root and
    /// again inside the iPad showcase full-screen cover: an alert on the covered editor can't
    /// present over a full-screen cover, so the still-open showcase sheet needs its own.
    @ViewBuilder
    func exportFailedAlert(_ message: Binding<String?>) -> some View {
        alert("Export Failed", isPresented: Binding(
            get: { message.wrappedValue != nil },
            set: { if !$0 { message.wrappedValue = nil } }
        )) {
            Button("OK") { message.wrappedValue = nil }
        } message: {
            Text(message.wrappedValue ?? "")
        }
    }
}

extension ContentView {
    var hasLastExportDestination: Bool {
        !lastExportFolderBookmark.isEmpty
    }

    var lastExportFolderName: String {
        ExportFolderService.folderName(for: lastExportFolderPath)
    }

    var exportButtonText: LocalizedStringKey {
        if isExporting { return "Exporting..." }
        if exportSuccess { return "Exported" }
        return hasLastExportDestination ? "Export" : "Export..."
    }

    var exportHelpText: LocalizedStringKey {
        if hasLastExportDestination {
            return "Export screenshots to \(lastExportFolderName) (\u{2318}E)"
        }
        return "Choose a folder and export screenshots (\u{2318}E)"
    }

    var fitZoomHelpText: LocalizedStringKey {
        if let row = currentExportRow {
            return "Fit \(row.displayLabel) to the editor"
        }
        return "Fit the selected row to the editor"
    }

    var currentExportRow: ScreenshotRow? {
        if let selectedRowId = state.selectedRowId {
            return state.rows.first(where: { $0.id == selectedRowId })
        }
        return state.rows.first
    }

    func fitZoomToWindow() {
        guard let row = currentExportRow, editorViewportHeight > 0 else { return }
        let baseHeight = row.displayHeight(zoom: 1.0)
        guard baseHeight > 0 else { return }
        state.setZoomLevel(editorViewportHeight / baseHeight)
    }

    func exportScreenshots(localeFilter: String? = nil) {
        if let savedURL = lastExportFolderURL() {
            exportScreenshots(to: savedURL, localeFilter: localeFilter)
        } else {
            exportScreenshotsAs(localeFilter: localeFilter)
        }
    }

    func exportScreenshotsAs(localeFilter: String? = nil) {
        guard let url = resolvedExportBaseURL() else { return }
        saveLastExportFolder(url)
        exportScreenshots(to: url, localeFilter: localeFilter)
    }

    /// Resolves a destination folder for export. On iPad, folder export is deferred, so this
    /// reports a clear message and returns nil (rather than silently doing nothing).
    func resolvedExportBaseURL() -> URL? {
        #if os(iOS)
        exportError = ExportService.exportUnavailableMessage
        return nil
        #else
        return chooseExportDestination()
        #endif
    }

    func exportRowImages() {
        exportRowLevel(folderName: "rows") { row, images, locale, localeState in
            ExportService.renderRowImage(row: row, screenshotImages: images, localeCode: locale, localeState: localeState)
        }
    }

    func exportShowcaseImages() {
        guard let row = state.rows.first else { return }
        presentShowcaseSheet(for: row, mode: .allRows)
    }

    @ViewBuilder
    func showcaseExportScreen(for presentation: ShowcasePresentation) -> some View {
        ShowcaseExportSheet(
            candidateRows: presentation.candidateRows,
            loadImages: { row in
                state.loadFullResolutionImages(
                    forRow: row,
                    localeCode: state.localeState.activeLocaleCode
                )
            },
            localeCode: state.localeState.activeLocaleCode,
            localeState: state.localeState,
            availableFontFamilies: state.availableFontFamilySet
        ) { config, backgroundImage, selectedRowIds, excludedTemplateIds, destination in
            #if os(iOS)
            // Keep the showcase sheet open; the chosen destination (Photos/Files/Share)
            // presents over it so the user can pick another destination afterwards.
            runShowcaseExportIPad(
                config: config,
                backgroundImage: backgroundImage,
                selectedRowIds: selectedRowIds,
                excludedTemplateIds: excludedTemplateIds,
                destination: destination
            )
            #else
            showcasePresentation = nil
            runShowcaseExport(
                presentation: presentation,
                config: config,
                backgroundImage: backgroundImage,
                selectedRowIds: selectedRowIds,
                excludedTemplateIds: excludedTemplateIds
            )
            #endif
        }
    }

    func presentShowcaseSheet(for row: ScreenshotRow, mode: ShowcaseExportMode) {
        let candidates: [ScreenshotRow]
        switch mode {
        case .allRows:
            candidates = state.rows
        case .singleRow:
            candidates = [row]
        }
        showcasePresentation = ShowcasePresentation(
            mode: mode,
            candidateRows: candidates
        )
    }

    func runShowcaseExport(
        presentation: ShowcasePresentation,
        config: ShowcaseExportConfig,
        backgroundImage: NSImage?,
        selectedRowIds: Set<UUID>,
        excludedTemplateIds: Set<UUID>
    ) {
        guard !selectedRowIds.isEmpty else { return }

        var seedCache: [String: NSImage] = [:]
        if let backgroundImage,
           config.backgroundStyle == .image,
           config.backgroundImageConfig.fileName == ShowcaseExportConfig.transientBackgroundKey {
            seedCache[ShowcaseExportConfig.transientBackgroundKey] = backgroundImage
        }

        switch presentation.mode {
        case .allRows:
            let rowsToExport = state.rows
                .filter { selectedRowIds.contains($0.id) }
                .compactMap { $0.filtering(excluding: excludedTemplateIds) }
            guard !rowsToExport.isEmpty else { return }
            exportRowLevel(folderName: "showcase", rows: rowsToExport, imageCache: seedCache) { row, images, locale, localeState in
                ExportService.renderShowcaseRowImage(row: row, screenshotImages: images, localeCode: locale, localeState: localeState, config: config)
            }
        case .singleRow:
            guard let rowId = selectedRowIds.first,
                  let baseRow = state.rows.first(where: { $0.id == rowId }),
                  let row = baseRow.filtering(excluding: excludedTemplateIds) else { return }
            let localeCode = state.localeState.activeLocaleCode
            if let message = ExportService.saveRowImageViaPanel(defaultName: row.label, render: {
                var images = state.loadFullResolutionImages(forRow: row, localeCode: localeCode)
                images.merge(seedCache, uniquingKeysWith: { _, new in new })
                return ExportService.renderShowcaseRowImage(
                    row: row, screenshotImages: images,
                    localeCode: localeCode, localeState: state.localeState,
                    config: config
                )
            }) {
                exportError = String(localized: "Could not export row image: \(message)")
            }
        }
    }

    /// Renders each row to a zero-padded PNG in `destDir`, updating `exportProgress`, and returns
    /// the written file URLs in order. Throws `CancellationError` or `ExportRenderError`. Shared by
    /// `exportRowLevel` and the iPad showcase export so numbering/naming stay in one place.
    func renderRows(
        _ rows: [ScreenshotRow],
        into destDir: URL,
        imageCache: inout [String: NSImage],
        render: @MainActor (ScreenshotRow, [String: NSImage], String?, LocaleState) -> NSImage
    ) async throws -> [URL] {
        let localeCode = state.localeState.activeLocaleCode
        var fileURLs: [URL] = []
        for (index, row) in rows.enumerated() {
            try Task.checkCancellation()
            let fileNames = state.referencedImageFileNames(forRow: row, localeCode: localeCode)
            let rowImages = state.loadFullResolutionImages(fileNames: fileNames, cache: &imageCache)
            let image = render(row, rowImages, localeCode, state.localeState)
            guard let data = ExportService.encodeImage(image, format: .png) else {
                throw ExportRenderError.encodingFailed(rowIndex: index)
            }
            let paddedIndex = String(format: "%02d", index + 1)
            let fileName = row.label.isEmpty ? "\(paddedIndex).png" : "\(paddedIndex)_\(row.label).png"
            let url = destDir.appendingPathComponent(fileName)
            try data.write(to: url)
            fileURLs.append(url)
            exportProgress = index + 1
            await Task.yield()
        }
        return fileURLs
    }

    func exportRowLevel(
        folderName: String,
        rows: [ScreenshotRow]? = nil,
        imageCache seedCache: [String: NSImage] = [:],
        render: @MainActor @escaping (ScreenshotRow, [String: NSImage], String?, LocaleState) -> NSImage
    ) {
        let rowsToExport = rows ?? state.rows
        guard !rowsToExport.isEmpty else { return }
        #if os(iOS)
        let baseURL: URL
        do {
            baseURL = try ExportService.makeTempExportFolder()
        } catch {
            exportError = error.localizedDescription
            return
        }
        #else
        guard let baseURL = resolvedExportBaseURL() else { return }
        #endif

        exportSuccessTimer?.cancel()
        isExporting = true
        exportSuccess = false
        exportError = nil
        exportProgress = 0
        exportTotal = rowsToExport.count

        exportTask = Task {
            defer {
                isExporting = false
                exportTask = nil
            }
            do {
                let destDir = ExportService.uniqueFolder(named: folderName, in: baseURL)
                try FileManager.default.createDirectory(at: destDir, withIntermediateDirectories: true)
                var imageCache: [String: NSImage] = seedCache
                let fileURLs = try await renderRows(rowsToExport, into: destDir, imageCache: &imageCache, render: render)

                #if os(iOS)
                presentExportDestinations(fileURLs: fileURLs, folderURL: destDir, cleanup: baseURL)
                #else
                _ = fileURLs
                if openExportFolderOnSuccess {
                    PlatformReveal.inFileViewer([destDir])
                }
                showExportSuccess()
                #endif
            } catch is CancellationError {
                // User cancelled
            } catch {
                exportError = error.localizedDescription
                NotificationService.notify(title: String(localized: "Export failed"), body: error.localizedDescription)
            }
        }
    }

    func showExportSuccess() {
        exportSuccessTimer?.cancel()
        exportSuccess = true
        let timer = DispatchWorkItem { exportSuccess = false }
        exportSuccessTimer = timer
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.0, execute: timer)

        let count = exportTotal
        let noun = count == 1 ? String(localized: "screenshot") : String(localized: "screenshots")
        let projectName = state.activeProject?.name ?? ""
        let body = projectName.isEmpty
            ? String(localized: "\(count) \(noun) exported")
            : String(localized: "\(count) \(noun) exported · \(projectName)")
        NotificationService.notify(title: String(localized: "Export complete"), body: body)

        maybeRequestReview()
    }

    static let reviewMinExportCount = 3
    static let reviewMinDaysSinceFirstExport: TimeInterval = 14 * 86400
    static let reviewMinDaysBetweenPrompts: TimeInterval = 120 * 86400

    func maybeRequestReview() {
        let currentVersion = Bundle.main.shortVersion
        guard !currentVersion.isEmpty, currentVersion != reviewLastPromptedVersion else { return }

        let now = Date().timeIntervalSinceReferenceDate
        if reviewFirstExportDate == 0 {
            reviewFirstExportDate = now
        }
        reviewExportCount += 1

        guard reviewExportCount >= Self.reviewMinExportCount,
              now - reviewFirstExportDate >= Self.reviewMinDaysSinceFirstExport,
              now - reviewLastPromptDate >= Self.reviewMinDaysBetweenPrompts
        else { return }

        reviewLastPromptedVersion = currentVersion
        reviewLastPromptDate = now
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) {
            requestReview()
        }
    }

    func chooseExportDestination() -> URL? {
        ExportFolderService.chooseFolder()
    }

    func exportScreenshots(to url: URL, localeFilter: String? = nil) {
        let didAccess = url.startAccessingSecurityScopedResource()
        guard didAccess else {
            // Permission lost — clear stale bookmark and ask user to pick again
            lastExportFolderBookmark = Data()
            lastExportFolderPath = ""
            exportScreenshotsAs()
            return
        }

        exportSuccessTimer?.cancel()
        isExporting = true
        exportSuccess = false
        exportError = nil
        exportProgress = 0

        let localeCount = localeFilter == nil ? max(1, state.localeState.locales.count) : 1
        exportTotal = localeCount * state.rows.reduce(0) { $0 + $1.templates.count }

        exportTask = Task {
            defer {
                url.stopAccessingSecurityScopedResource()
                isExporting = false
                exportTask = nil
            }
            do {
                let projectName = state.activeProject?.name ?? ""
                let format = ExportImageFormat(rawValue: exportFormat.lowercased()) ?? .png
                var imageCache: [String: NSImage] = [:]
                let export = try await ExportService.exportAll(
                    rows: state.rows,
                    projectName: projectName,
                    to: url,
                    format: format,
                    imageProvider: { [state] row, localeCode in
                        let fileNames = state.referencedImageFileNames(forRow: row, localeCode: localeCode)
                        return state.loadFullResolutionImages(fileNames: fileNames, cache: &imageCache)
                    },
                    localeState: state.localeState,
                    localeFilter: localeFilter,
                    customSuffix: exportCustomSuffix,
                    availableFontFamilies: state.availableFontFamilySet,
                    onProgress: { completed in
                        exportProgress = completed
                    }
                )
                showExportSuccess()
                if openExportFolderOnSuccess {
                    PlatformReveal.inFileViewer([export.folderURL])
                }
            } catch is CancellationError {
                // User cancelled — no error to show
            } catch {
                exportError = error.localizedDescription
                NotificationService.notify(title: String(localized: "Export failed"), body: error.localizedDescription)
            }
        }
    }

    #if os(iOS)
    /// iPad showcase export: renders the selected rows to PNGs in a temp folder, then routes them
    /// to the chosen destination (Photos / Files / Share). The showcase sheet stays open so the
    /// user can export again to another destination; temp files are cleaned up once the
    /// destination flow finishes.
    func runShowcaseExportIPad(
        config: ShowcaseExportConfig,
        backgroundImage: NSImage?,
        selectedRowIds: Set<UUID>,
        excludedTemplateIds: Set<UUID>,
        destination: ExportDestination
    ) {
        let rowsToExport = state.rows
            .filter { selectedRowIds.contains($0.id) }
            .compactMap { $0.filtering(excluding: excludedTemplateIds) }
        guard !rowsToExport.isEmpty else { return }

        var seedCache: [String: NSImage] = [:]
        if let backgroundImage,
           config.backgroundStyle == .image,
           config.backgroundImageConfig.fileName == ShowcaseExportConfig.transientBackgroundKey {
            seedCache[ShowcaseExportConfig.transientBackgroundKey] = backgroundImage
        }

        let baseURL: URL
        do {
            baseURL = try ExportService.makeTempExportFolder()
        } catch {
            exportError = error.localizedDescription
            return
        }

        exportSuccessTimer?.cancel()
        isExporting = true
        exportSuccess = false
        exportError = nil
        exportProgress = 0
        exportTotal = rowsToExport.count

        exportTask = Task {
            defer {
                isExporting = false
                exportTask = nil
            }
            do {
                let destDir = ExportService.uniqueFolder(named: "showcase", in: baseURL)
                try FileManager.default.createDirectory(at: destDir, withIntermediateDirectories: true)
                var imageCache: [String: NSImage] = seedCache
                let fileURLs = try await renderRows(rowsToExport, into: destDir, imageCache: &imageCache) { row, images, locale, localeState in
                    ExportService.renderShowcaseRowImage(
                        row: row, screenshotImages: images,
                        localeCode: locale, localeState: localeState, config: config
                    )
                }
                route(destination: destination, fileURLs: fileURLs, folderURL: destDir, cleanup: baseURL)
            } catch is CancellationError {
                try? FileManager.default.removeItem(at: baseURL)
            } catch {
                try? FileManager.default.removeItem(at: baseURL)
                exportError = error.localizedDescription
                NotificationService.notify(title: String(localized: "Export failed"), body: error.localizedDescription)
            }
        }
    }

    /// Hands rendered files to the chosen destination and cleans up the temp folder once the flow
    /// completes (or is cancelled). Photos/Share receive the individual image files; Files receives
    /// the whole folder so multi-locale / multi-row subfolder structure is preserved on disk.
    func route(destination: ExportDestination, fileURLs: [URL], folderURL: URL, cleanup baseURL: URL) {
        let finish: (Bool) -> Void = { completed in
            try? FileManager.default.removeItem(at: baseURL)
            if completed { showExportSuccess() }
        }
        switch destination {
        case .share:
            PlatformShare.present(urls: fileURLs, completion: finish)
        case .files:
            PlatformDocumentExport.present(urls: [folderURL], completion: finish)
        case .photos:
            PlatformPhotoLibrary.save(fileURLs: fileURLs) { success, error in
                try? FileManager.default.removeItem(at: baseURL)
                if let error {
                    exportError = error.localizedDescription
                } else if success {
                    showExportSuccess()
                }
            }
        }
    }

    /// Stashes rendered output so the editor's destination action sheet can present. The user then
    /// picks Photos / Files / Share; routing and temp-folder cleanup happen from there.
    func presentExportDestinations(fileURLs: [URL], folderURL: URL, cleanup baseURL: URL) {
        guard !fileURLs.isEmpty else {
            try? FileManager.default.removeItem(at: baseURL)
            return
        }
        pendingExport = PendingExport(fileURLs: fileURLs, folderURL: folderURL, cleanupBaseURL: baseURL)
    }

    /// iPad export: renders to a temp folder via the shared `exportAll` path, then presents the
    /// destination action sheet (Save to Photos / Save to Files / Share) since there's no Finder.
    func exportScreenshotsForIPad(localeFilter: String? = nil) {
        guard !state.rows.isEmpty else { return }

        exportSuccessTimer?.cancel()
        isExporting = true
        exportSuccess = false
        exportError = nil
        exportProgress = 0

        let localeCount = localeFilter == nil ? max(1, state.localeState.locales.count) : 1
        exportTotal = localeCount * state.rows.reduce(0) { $0 + $1.templates.count }

        exportTask = Task {
            defer {
                isExporting = false
                exportTask = nil
            }
            do {
                let projectName = state.activeProject?.name ?? ""
                let format = ExportImageFormat(rawValue: exportFormat.lowercased()) ?? .png
                let tempBase = try ExportService.makeTempExportFolder()

                var imageCache: [String: NSImage] = [:]
                let export = try await ExportService.exportAll(
                    rows: state.rows,
                    projectName: projectName,
                    to: tempBase,
                    format: format,
                    imageProvider: { [state] row, localeCode in
                        let fileNames = state.referencedImageFileNames(forRow: row, localeCode: localeCode)
                        return state.loadFullResolutionImages(fileNames: fileNames, cache: &imageCache)
                    },
                    localeState: state.localeState,
                    localeFilter: localeFilter,
                    customSuffix: exportCustomSuffix,
                    availableFontFamilies: state.availableFontFamilySet,
                    onProgress: { completed in
                        exportProgress = completed
                    }
                )
                presentExportDestinations(fileURLs: export.fileURLs, folderURL: export.folderURL, cleanup: tempBase)
            } catch is CancellationError {
                // User cancelled — no error to show
            } catch {
                exportError = error.localizedDescription
                NotificationService.notify(title: String(localized: "Export failed"), body: error.localizedDescription)
            }
        }
    }
    #endif

    func lastExportFolderURL() -> URL? {
        guard let result = ExportFolderService.resolveBookmark(lastExportFolderBookmark) else {
            if !lastExportFolderBookmark.isEmpty {
                lastExportFolderBookmark = Data()
            }
            return nil
        }
        if let refreshed = result.refreshedBookmark {
            lastExportFolderBookmark = refreshed
        }
        return result.url
    }

    func saveLastExportFolder(_ url: URL) {
        guard let result = ExportFolderService.saveBookmark(for: url) else {
            exportError = String(localized: "Failed to remember export folder")
            return
        }
        lastExportFolderBookmark = result.bookmark
        lastExportFolderPath = result.path
    }

    func openLastExportFolder() {
        guard let url = lastExportFolderURL() else { return }
        PlatformReveal.inFileViewer([url])
    }

}

#if os(iOS)
/// Rendered iPad export output, held while the destination action sheet (Photos / Files / Share)
/// is on screen so the user can choose where it goes.
struct PendingExport: Identifiable {
    let id = UUID()
    let fileURLs: [URL]
    let folderURL: URL
    let cleanupBaseURL: URL
}

extension ContentView {
    var pendingExportTitle: String {
        guard let count = pendingExport?.fileURLs.count else { return "" }
        return count == 1
            ? String(localized: "Export 1 screenshot to…")
            : String(localized: "Export \(count) screenshots to…")
    }

    func runPendingExport(to destination: ExportDestination) {
        guard let pending = pendingExport else { return }
        pendingExport = nil
        route(destination: destination, fileURLs: pending.fileURLs, folderURL: pending.folderURL, cleanup: pending.cleanupBaseURL)
    }

    /// Dismissal without a chosen destination (Cancel / tap-outside): discard the rendered temp files.
    /// A destination tap clears `pendingExport` first, so this no-ops in that case.
    func discardPendingExport() {
        guard let pending = pendingExport else { return }
        try? FileManager.default.removeItem(at: pending.cleanupBaseURL)
        pendingExport = nil
    }
}
#endif
