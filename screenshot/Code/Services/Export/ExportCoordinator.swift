#if os(macOS)
import AppKit
#else
import UIKit
#endif
import Foundation

enum ExportRenderError: LocalizedError {
    case encodingFailed(rowIndex: Int)
    nonisolated var errorDescription: String? {
        switch self {
        case .encodingFailed(let index):
            return String(localized: "Failed to render row \(index + 1)")
        }
    }
}

/// Rendered export output held while the destination action sheet (Photos / Files / Share) is on
/// screen, so the user can choose where it goes. iPad only — macOS picks the folder up front.
struct PendingExport: Identifiable {
    let id = UUID()
    let fileURLs: [URL]
    let folderURL: URL
    let cleanupBaseURL: URL
}

/// Remembers the folder the user last exported to, as a security-scoped bookmark.
///
/// The bookmark and its display path were `@AppStorage` on `ContentView`, which made resolving,
/// refreshing and invalidating them view-only code that no test could reach.
@MainActor
struct ExportFolderBookmark {
    static let bookmarkKey = "lastExportFolderBookmark"
    static let pathKey = "lastExportFolderPath"

    let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    var bookmarkData: Data { defaults.data(forKey: Self.bookmarkKey) ?? Data() }
    var displayPath: String { defaults.string(forKey: Self.pathKey) ?? "" }
    var hasDestination: Bool { !bookmarkData.isEmpty }

    /// Resolves the stored bookmark, refreshing it when the OS hands back a renewed one and
    /// clearing it when it no longer resolves (folder deleted, permission revoked). Both keys go
    /// together — a lingering display path would advertise a destination that can't be exported to.
    func resolve() -> URL? {
        let stored = bookmarkData
        guard let result = ExportFolderService.resolveBookmark(stored) else {
            if !stored.isEmpty { clear() }
            return nil
        }
        if let refreshed = result.refreshedBookmark {
            defaults.set(refreshed, forKey: Self.bookmarkKey)
        }
        return result.url
    }

    /// Stores `url` as the remembered destination. Returns false when a bookmark can't be made,
    /// so the caller can surface it.
    @discardableResult
    func save(_ url: URL) -> Bool {
        guard let result = ExportFolderService.saveBookmark(for: url) else { return false }
        defaults.set(result.bookmark, forKey: Self.bookmarkKey)
        defaults.set(result.path, forKey: Self.pathKey)
        return true
    }

    func clear() {
        defaults.removeObject(forKey: Self.bookmarkKey)
        defaults.removeObject(forKey: Self.pathKey)
    }
}

@MainActor
enum ExportCoordinator {
    /// The row-level export loop: render each row, encode off the main actor, write a
    /// zero-padded file. Shared by the row/showcase exports and the iPad share-sheet path so
    /// numbering and naming stay in one place.
    ///
    /// The encode must not run on the main actor — showcase rows are the largest images the app
    /// produces and their PNG deflate is where SCREENSHOT-BRO-2 hung. The per-row
    /// `await Task.yield()` is required for the same reason.
    static func renderRows(
        _ rows: [ScreenshotRow],
        into destDir: URL,
        source: some RowRenderSource,
        imageCache: inout [String: NSImage],
        seedImages: [String: NSImage] = [:],
        onProgress: ((Int) -> Void)? = nil,
        render: @MainActor (RowRenderContext) async -> NSImage
    ) async throws -> [URL] {
        let localeCode = source.localeState.activeLocaleCode
        var fileURLs: [URL] = []
        for (index, row) in rows.enumerated() {
            try Task.checkCancellation()
            let context = RowRenderContext.load(
                row: row,
                localeCode: localeCode,
                from: source,
                label: "row export",
                cache: &imageCache,
                seedImages: seedImages
            )
            guard let data = await ExportImageEncoder.opaquePNGDataOffMain(from: render(context)) else {
                throw ExportRenderError.encodingFailed(rowIndex: index)
            }
            let url = destDir.appendingPathComponent(rowFileName(row, index: index))
            try data.write(to: url)
            fileURLs.append(url)
            onProgress?(index + 1)
            await Task.yield()
        }
        return fileURLs
    }

    /// `01.png`, or `01_Row Label.png` when the row is named.
    static func rowFileName(_ row: ScreenshotRow, index: Int) -> String {
        let padded = String(format: "%02d", index + 1)
        return row.label.isEmpty ? "\(padded).png" : "\(padded)_\(row.label).png"
    }
}
