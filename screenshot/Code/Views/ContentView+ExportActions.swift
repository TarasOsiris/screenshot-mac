#if os(macOS)
import AppKit
#else
import UIKit
#endif
import StoreKit
import SwiftUI

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
        ) { config, backgroundImage, selectedRowIds, excludedTemplateIds in
            showcasePresentation = nil
            runShowcaseExport(
                presentation: presentation,
                config: config,
                backgroundImage: backgroundImage,
                selectedRowIds: selectedRowIds,
                excludedTemplateIds: excludedTemplateIds
            )
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

                let localeCode = state.localeState.activeLocaleCode
                var imageCache: [String: NSImage] = seedCache
                for (index, row) in rowsToExport.enumerated() {
                    try Task.checkCancellation()
                    let fileNames = state.referencedImageFileNames(forRow: row, localeCode: localeCode)
                    let rowImages = state.loadFullResolutionImages(fileNames: fileNames, cache: &imageCache)
                    let image = render(row, rowImages, localeCode, state.localeState)
                    guard let data = ExportService.encodeImage(image, format: .png) else {
                        exportError = String(localized: "Failed to render row \(index + 1)")
                        return
                    }
                    let paddedIndex = String(format: "%02d", index + 1)
                    let fileName = row.label.isEmpty ? "\(paddedIndex).png" : "\(paddedIndex)_\(row.label).png"
                    try data.write(to: destDir.appendingPathComponent(fileName))
                    exportProgress = index + 1
                    await Task.yield()
                }

                #if os(iOS)
                PlatformShare.present(urls: [destDir]) { completed in
                    try? FileManager.default.removeItem(at: baseURL)
                    if completed { showExportSuccess() }
                }
                #else
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
                let destinationFolderURL = try await ExportService.exportAll(
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
                    PlatformReveal.inFileViewer([destinationFolderURL])
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
    /// iPad export: renders to a temp folder via the shared `exportAll` path, then hands the
    /// folder to the system share sheet (Save to Files / AirDrop) since there's no Finder.
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
                let folderURL = try await ExportService.exportAll(
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
                PlatformShare.present(urls: [folderURL]) { completed in
                    try? FileManager.default.removeItem(at: tempBase)
                    if completed { showExportSuccess() }
                }
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
