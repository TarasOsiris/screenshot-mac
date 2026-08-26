#if os(macOS)
import AppKit
#else
import UIKit
#endif
import SwiftUI

extension View {
    /// Presents the shared "Export Failed" alert bound to `message`. Applied at the editor root and
    /// again inside the iPad showcase full-screen cover: an alert on the covered editor can't
    /// present over a full-screen cover, so the still-open showcase sheet needs its own.
    @ViewBuilder
    func exportFailedAlert(_ message: Binding<String?>) -> some View {
        alert("Export Failed", isPresented: message.isPresent()) {
            Button("OK") { message.wrappedValue = nil }
        } message: {
            Text(message.wrappedValue ?? "")
        }
    }
}

// The export *flow* — progress, cancellation, destination routing, temp-folder lifetime — lives in
// `ExportFlowModel`. What stays here is the part that is genuinely view work: choosing a folder
// through a panel, deciding which rows the current selection means, and building the showcase sheet.
extension ContentView {
    var hasLastExportDestination: Bool {
        !lastExportFolderPath.isEmpty
    }

    var lastExportFolderName: String {
        ExportFolderService.folderName(for: lastExportFolderPath)
    }

    var exportButtonText: LocalizedStringKey {
        if exportFlow.isExporting { return "Exporting..." }
        if exportFlow.exportSuccess { return "Exported" }
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
        state.zoom.set(editorViewportHeight / baseHeight)
    }

    func exportScreenshots(localeFilter: String? = nil) {
        if let savedURL = exportFlow.bookmark.resolve() {
            exportFlow.exportAll(document: state, to: savedURL, localeFilter: localeFilter)
        } else {
            exportScreenshotsAs(localeFilter: localeFilter)
        }
    }

    func exportScreenshotsAs(localeFilter: String? = nil) {
        guard let url = resolvedExportBaseURL() else { return }
        if !exportFlow.bookmark.save(url) {
            exportFlow.errorMessage = String(localized: "Failed to remember export folder")
        }
        exportFlow.exportAll(document: state, to: url, localeFilter: localeFilter)
    }

    /// Resolves a destination folder for export. On iPad, folder export is deferred, so this
    /// reports a clear message and returns nil (rather than silently doing nothing).
    func resolvedExportBaseURL() -> URL? {
        #if os(iOS)
        exportFlow.errorMessage = ExportService.exportUnavailableMessage
        return nil
        #else
        return ExportFolderService.chooseFolder()
        #endif
    }

    func exportRowImages() {
        exportRowLevel(folderName: "rows") { context in
            context.rowImage()
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

    /// A showcase background chosen in the sheet but not yet saved to the project lives only in
    /// memory, so it has to be seeded into the render cache under its transient key.
    func showcaseSeedCache(config: ShowcaseExportConfig, backgroundImage: NSImage?) -> [String: NSImage] {
        guard let backgroundImage,
              config.backgroundStyle == .image,
              config.backgroundImageConfig.fileName == ShowcaseExportConfig.transientBackgroundKey
        else { return [:] }
        return [ShowcaseExportConfig.transientBackgroundKey: backgroundImage]
    }

    func showcaseRows(selectedRowIds: Set<UUID>, excludedTemplateIds: Set<UUID>) -> [ScreenshotRow] {
        state.rows
            .filter { selectedRowIds.contains($0.id) }
            .compactMap { $0.filtering(excluding: excludedTemplateIds) }
    }

    func runShowcaseExport(
        presentation: ShowcasePresentation,
        config: ShowcaseExportConfig,
        backgroundImage: NSImage?,
        selectedRowIds: Set<UUID>,
        excludedTemplateIds: Set<UUID>
    ) {
        guard !selectedRowIds.isEmpty else { return }
        let seedCache = showcaseSeedCache(config: config, backgroundImage: backgroundImage)

        switch presentation.mode {
        case .allRows:
            let rowsToExport = showcaseRows(selectedRowIds: selectedRowIds, excludedTemplateIds: excludedTemplateIds)
            guard !rowsToExport.isEmpty else { return }
            exportRowLevel(folderName: "showcase", rows: rowsToExport, seedImages: seedCache) { context in
                await context.showcaseImage(config: config)
            }
        case .singleRow:
            guard let rowId = selectedRowIds.first,
                  let baseRow = state.rows.first(where: { $0.id == rowId }),
                  let row = baseRow.filtering(excluding: excludedTemplateIds) else { return }
            let localeCode = state.localeState.activeLocaleCode
            Task {
                if let message = await ExportService.saveRowImageViaPanel(defaultName: row.label, render: {
                    var cache: [String: NSImage] = [:]
                    let context = RowRenderContext.load(
                        row: row,
                        localeCode: localeCode,
                        from: state,
                        label: "showcase row export",
                        cache: &cache,
                        seedImages: seedCache
                    )
                    return await context.showcaseImage(config: config)
                }) {
                    exportFlow.errorMessage = String(localized: "Could not export row image: \(message)")
                }
            }
        }
    }

    /// Picks the destination folder — a temp one on iPad, where the destination is chosen after the
    /// render — and hands the rest to the flow model.
    func exportRowLevel(
        folderName: String,
        rows: [ScreenshotRow]? = nil,
        seedImages: [String: NSImage] = [:],
        render: @MainActor @escaping (RowRenderContext) async -> NSImage
    ) {
        #if os(iOS)
        guard let baseURL = tempExportFolder() else { return }
        let delivery = ExportFlowModel.Delivery.stageDestination
        #else
        guard let baseURL = resolvedExportBaseURL() else { return }
        let delivery = ExportFlowModel.Delivery.revealInPlace
        #endif

        exportFlow.exportRows(
            document: state,
            into: baseURL,
            folderName: folderName,
            rows: rows,
            seedImages: seedImages,
            delivery: delivery,
            render: render
        )
    }

    /// Reports the failure and returns nil, so callers can `guard let` instead of repeating the
    /// do/catch at every temp-folder site.
    func tempExportFolder() -> URL? {
        do {
            return try ExportService.makeTempExportFolder()
        } catch {
            exportFlow.errorMessage = error.localizedDescription
            return nil
        }
    }

    func openLastExportFolder() {
        guard let url = exportFlow.bookmark.resolve() else { return }
        PlatformReveal.inFileViewer([url])
    }
}

#if os(iOS)
extension ContentView {
    var pendingExportTitle: String {
        guard let count = exportFlow.pendingExport?.fileURLs.count else { return "" }
        return count == 1
            ? String(localized: "Export 1 screenshot to…")
            : String(localized: "Export \(count) screenshots to…")
    }

    /// iPad showcase export: renders the selected rows to PNGs in a temp folder, then routes them
    /// straight to the chosen destination. The showcase sheet stays open so the user can export
    /// again elsewhere, which is why this routes immediately instead of staging a sheet.
    func runShowcaseExportIPad(
        config: ShowcaseExportConfig,
        backgroundImage: NSImage?,
        selectedRowIds: Set<UUID>,
        excludedTemplateIds: Set<UUID>,
        destination: ExportDestination
    ) {
        let rowsToExport = showcaseRows(selectedRowIds: selectedRowIds, excludedTemplateIds: excludedTemplateIds)
        guard !rowsToExport.isEmpty, let baseURL = tempExportFolder() else { return }

        exportFlow.exportRows(
            document: state,
            into: baseURL,
            folderName: "showcase",
            rows: rowsToExport,
            seedImages: showcaseSeedCache(config: config, backgroundImage: backgroundImage),
            delivery: .route(destination),
            render: { context in await context.showcaseImage(config: config) }
        )
    }

    func exportScreenshotsForIPad(localeFilter: String? = nil) {
        exportFlow.exportAllToTempFolder(document: state, localeFilter: localeFilter)
    }

    func runPendingExport(to destination: ExportDestination) {
        exportFlow.route(destination, projectName: state.activeProjectName)
    }

    func discardPendingExport() {
        exportFlow.discardPendingExport()
    }
}
#endif
