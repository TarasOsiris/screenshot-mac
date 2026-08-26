#if os(macOS)
import AppKit
#else
import UIKit
#endif
import Foundation
import Observation

/// What an export needs from the open document. `RowRenderSource` already covers the rendering
/// half; this adds the two things the export loop reads directly, so `ExportFlowModel` can run
/// against a fixture instead of a live `AppState`.
@MainActor
protocol ExportDocument: RowRenderSource {
    var rows: [ScreenshotRow] { get }
    var activeProjectName: String { get }
}

/// The editor's export flow: progress, cancellation, destination routing, temp-folder lifetime and
/// the transient success state behind the toolbar button.
///
/// All of this used to be 8 `@State` properties on `ContentView` plus 23 functions in an extension
/// on it, which meant none of it could be tested and the temp-folder cleanup was hand-repeated at
/// six call sites. `ContentView` now owns one of these and reads its state.
@MainActor
@Observable
final class ExportFlowModel {
    private(set) var isExporting = false
    private(set) var exportSuccess = false
    private(set) var progress = 0
    private(set) var total = 0
    var errorMessage: String?

    /// Rendered output held while the destination action sheet is on screen (iPad only — macOS
    /// picks the folder up front).
    var pendingExport: PendingExport?

    @ObservationIgnored private var successTimer: Task<Void, Never>?
    @ObservationIgnored private var task: Task<Void, Never>?
    @ObservationIgnored private let defaults: UserDefaults
    @ObservationIgnored private let review: ReviewPromptPolicy

    /// Presents the system review prompt. Injected because it comes from a SwiftUI environment
    /// value the model can't read, and because a test must be able to observe it without one.
    @ObservationIgnored var requestReview: () -> Void = {}

    init(defaults: UserDefaults = .standard, review: ReviewPromptPolicy? = nil) {
        self.defaults = defaults
        self.review = review ?? ReviewPromptPolicy(defaults: defaults)
    }

    // MARK: - Settings

    private var format: ExportImageFormat {
        ExportImageFormat(rawValue: (defaults.string(forKey: AppSettingsKeys.exportFormat) ?? AppSettingsKeys.Default.exportFormat).lowercased()) ?? .png
    }

    private var customSuffix: String { defaults.string(forKey: AppSettingsKeys.exportCustomSuffix) ?? "" }

    private var revealAfterExport: Bool {
        defaults.object(forKey: AppSettingsKeys.openExportFolderOnSuccess) as? Bool ?? AppSettingsKeys.Default.openExportFolderOnSuccess
    }

    var bookmark: ExportFolderBookmark { ExportFolderBookmark(defaults: defaults) }

    // MARK: - Lifecycle

    func cancel() { task?.cancel() }

    /// Resets progress and takes ownership of the run. There is no re-entrancy guard — the
    /// toolbar disables on `isExporting`, but a second overlapping run would clobber this one's
    /// progress and task handle.
    private func beginRun(total: Int) {
        successTimer?.cancel()
        isExporting = true
        exportSuccess = false
        errorMessage = nil
        progress = 0
        self.total = total
    }

    /// Runs `body` as the export task, clearing `isExporting` however it ends and swallowing
    /// cancellation (the user asked for it). `cleanup` runs on failure or cancellation only —
    /// success paths hand the folder on to a destination that owns it from there.
    private func run(cleanup: URL? = nil, _ body: @escaping @MainActor () async throws -> Void) {
        task = Task {
            defer {
                isExporting = false
                task = nil
            }
            do {
                try await body()
            } catch is CancellationError {
                if let cleanup { try? FileManager.default.removeItem(at: cleanup) }
            } catch {
                if let cleanup { try? FileManager.default.removeItem(at: cleanup) }
                errorMessage = error.localizedDescription
                NotificationService.notify(title: String(localized: "Export failed"), body: error.localizedDescription)
            }
        }
    }

    /// `destination` is the only thing the render layer never learns — `ExportService` knows what
    /// was rendered, this is the one place that knows where it went.
    func showSuccess(projectName: String, destination: String) {
        AnalyticsService.capture(.exportRouted, [.destination: destination])
        successTimer?.cancel()
        exportSuccess = true
        successTimer = .delayed(2) { [weak self] in self?.exportSuccess = false }

        let noun = total == 1 ? String(localized: "screenshot") : String(localized: "screenshots")
        let body = projectName.isEmpty
            ? String(localized: "\(total) \(noun) exported")
            : String(localized: "\(total) \(noun) exported · \(projectName)")
        NotificationService.notify(title: String(localized: "Export complete"), body: body)

        if review.recordExportAndCheck() {
            _ = Task.delayed(2.5) { [requestReview] in requestReview() }
        }
    }

    // MARK: - Full export (all rows × locales)

    /// Exports to the remembered folder, or reports that one must be chosen first.
    func exportAll(document: some ExportDocument, to url: URL, localeFilter: String? = nil) {
        guard url.startAccessingSecurityScopedResource() else {
            // Permission lost — forget the destination so the caller can ask again.
            bookmark.clear()
            errorMessage = String(localized: "Lost access to the export folder. Choose it again.")
            return
        }

        let localeCount = localeFilter == nil ? max(1, document.localeState.locales.count) : 1
        beginRun(total: localeCount * document.rows.reduce(0) { $0 + $1.templates.count })

        run {
            defer { url.stopAccessingSecurityScopedResource() }
            let export = try await self.renderAll(document: document, to: url, localeFilter: localeFilter)
            self.showSuccess(projectName: document.activeProjectName, destination: "folder")
            if self.revealAfterExport {
                PlatformReveal.inFileViewer([export.folderURL])
            }
        }
    }

    private func renderAll(
        document: some ExportDocument,
        to url: URL,
        localeFilter: String?
    ) async throws -> (folderURL: URL, fileURLs: [URL]) {
        var imageCache: [String: NSImage] = [:]
        return try await ExportService.exportAll(
            rows: document.rows,
            projectName: document.activeProjectName,
            to: url,
            format: format,
            imageProvider: { row, localeCode in
                let fileNames = document.referencedImageFileNames(forRow: row, localeCode: localeCode)
                return document.loadFullResolutionImages(fileNames: fileNames, cache: &imageCache)
            },
            localeState: document.localeState,
            localeFilter: localeFilter,
            customSuffix: customSuffix,
            availableFontFamilies: document.availableFontFamilySet,
            onProgress: { [weak self] completed in self?.progress = completed }
        )
    }

    // MARK: - Row-level export (one image per row)

    /// What happens to the rendered files once they exist.
    enum Delivery {
        /// macOS: they are already in the folder the user picked; optionally reveal it.
        case revealInPlace
        /// iPad editor export: stage them so the destination action sheet can present.
        case stageDestination
        #if os(iOS)
        /// iPad showcase export: the user chose the destination before the render, so go straight
        /// there and leave the showcase sheet open.
        case route(ExportDestination)
        #endif

        /// Whether a failure leaves a temp folder behind that only we can clean up.
        var ownsTempFolder: Bool {
            if case .revealInPlace = self { return false }
            return true
        }
    }

    /// Renders one image per row into a uniquely-named subfolder of `baseURL`, then delivers them.
    func exportRows(
        document: some ExportDocument,
        into baseURL: URL,
        folderName: String,
        rows: [ScreenshotRow]? = nil,
        seedImages: [String: NSImage] = [:],
        delivery: Delivery,
        render: @MainActor @escaping (RowRenderContext) async -> NSImage
    ) {
        let rowsToExport = rows ?? document.rows
        guard !rowsToExport.isEmpty else { return }
        beginRun(total: rowsToExport.count)

        run(cleanup: delivery.ownsTempFolder ? baseURL : nil) {
            let destDir = ExportFileNaming.uniqueFolder(named: folderName, in: baseURL)
            try FileManager.default.createDirectory(at: destDir, withIntermediateDirectories: true)
            var imageCache: [String: NSImage] = [:]
            let fileURLs = try await ExportCoordinator.renderRows(
                rowsToExport,
                into: destDir,
                source: document,
                imageCache: &imageCache,
                seedImages: seedImages,
                onProgress: { [weak self] in self?.progress = $0 },
                render: render
            )
            let staged = PendingExport(fileURLs: fileURLs, folderURL: destDir, cleanupBaseURL: baseURL)
            switch delivery {
            case .revealInPlace:
                if self.revealAfterExport {
                    PlatformReveal.inFileViewer([destDir])
                }
                self.showSuccess(projectName: document.activeProjectName, destination: "folder")
            case .stageDestination:
                self.stage(staged)
            #if os(iOS)
            case .route(let destination):
                guard !fileURLs.isEmpty else {
                    try? FileManager.default.removeItem(at: baseURL)
                    return
                }
                self.routeStaged(staged, to: destination, projectName: document.activeProjectName)
            #endif
            }
        }
    }

    // MARK: - iPad destination routing

    /// Renders to a temp folder, then presents the destination action sheet (no Finder on iPad).
    func exportAllToTempFolder(document: some ExportDocument, localeFilter: String? = nil) {
        guard !document.rows.isEmpty else { return }

        let localeCount = localeFilter == nil ? max(1, document.localeState.locales.count) : 1
        beginRun(total: localeCount * document.rows.reduce(0) { $0 + $1.templates.count })

        run {
            let tempBase = try ExportService.makeTempExportFolder()
            let export = try await self.renderAll(document: document, to: tempBase, localeFilter: localeFilter)
            self.stage(PendingExport(
                fileURLs: export.fileURLs,
                folderURL: export.folderURL,
                cleanupBaseURL: tempBase
            ))
        }
    }

    /// Stashes rendered output so the destination action sheet can present. Routing and cleanup
    /// happen from `route(_:projectName:)` / `discardPendingExport()`.
    private func stage(_ staged: PendingExport) {
        guard !staged.fileURLs.isEmpty else {
            try? FileManager.default.removeItem(at: staged.cleanupBaseURL)
            return
        }
        pendingExport = staged
    }

    /// Dismissal without a chosen destination (Cancel / tap-outside): discard the rendered files.
    /// A destination tap clears `pendingExport` first, so this no-ops in that case.
    func discardPendingExport() {
        guard let pending = pendingExport else { return }
        try? FileManager.default.removeItem(at: pending.cleanupBaseURL)
        pendingExport = nil
        AnalyticsService.capture(.exportAbandoned)
    }

    #if os(iOS)
    /// Hands the staged files to `destination` and cleans up the temp folder once that flow
    /// finishes. Photos and Share take the individual files; Files takes the whole folder so the
    /// multi-locale subfolder structure survives.
    func route(_ destination: ExportDestination, projectName: String) {
        guard let pending = pendingExport else { return }
        pendingExport = nil
        routeStaged(pending, to: destination, projectName: projectName)
    }

    private func routeStaged(_ pending: PendingExport, to destination: ExportDestination, projectName: String) {
        let finish: (Bool) -> Void = { [weak self] completed in
            try? FileManager.default.removeItem(at: pending.cleanupBaseURL)
            if completed { self?.showSuccess(projectName: projectName, destination: destination.rawValue) }
        }
        switch destination {
        case .share:
            PlatformShare.present(urls: pending.fileURLs, completion: finish)
        case .files:
            PlatformDocumentExport.present(urls: [pending.folderURL], completion: finish)
        case .photos:
            PlatformPhotoLibrary.save(fileURLs: pending.fileURLs) { [weak self] success, error in
                try? FileManager.default.removeItem(at: pending.cleanupBaseURL)
                if let error {
                    self?.errorMessage = error.localizedDescription
                } else if success {
                    self?.showSuccess(projectName: projectName, destination: destination.rawValue)
                }
            }
        }
    }
    #endif
}
