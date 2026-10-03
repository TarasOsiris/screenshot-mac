import Foundation
#if os(macOS)
import AppKit
#else
import UIKit
#endif

nonisolated extension Data {
    /// The bytes behind a picked, security-scoped URL. A picked file can live on iCloud Drive or a
    /// network volume, where the read blocks in `read(2)` until it materializes — on the main actor
    /// that is an app hang (SCREENSHOT-BRO-1C). `@concurrent` is load-bearing, see CLAUDE.md.
    @concurrent static func fromSecurityScopedURLOffMain(_ url: URL) async -> Data? {
        let didAccess = url.startAccessingSecurityScopedResource()
        defer { if didAccess { url.stopAccessingSecurityScopedResource() } }
        return try? Data(contentsOf: url)
    }
}

nonisolated extension NSImage {
    /// Load an image from a security-scoped URL (e.g., from file importers). Call only from off the
    /// main actor — on it, use `fromSecurityScopedURLOffMain`.
    static func fromSecurityScopedURL(_ url: URL) -> NSImage? {
        let didAccess = url.startAccessingSecurityScopedResource()
        defer { if didAccess { url.stopAccessingSecurityScopedResource() } }
        return NSImage(contentsOf: url)
    }

    /// The same, for main-actor callers: only the file read leaves the main actor.
    @MainActor static func fromSecurityScopedURLOffMain(_ url: URL) async -> NSImage? {
        guard let data = await Data.fromSecurityScopedURLOffMain(url) else { return nil }
        return NSImage(data: data)
    }
}
