#if os(macOS)
import AppKit
#else
import UIKit
#endif

enum ExportFolderService {
    // Security-scoped bookmarks are a macOS sandbox concept; iOS uses plain bookmarks.
    #if os(macOS)
    private static let bookmarkCreateOptions: URL.BookmarkCreationOptions = .withSecurityScope
    static let bookmarkResolveOptions: URL.BookmarkResolutionOptions = [.withSecurityScope, .withoutUI, .withoutMounting]
    #else
    private static let bookmarkCreateOptions: URL.BookmarkCreationOptions = []
    static let bookmarkResolveOptions: URL.BookmarkResolutionOptions = []
    #endif

    static func chooseFolder() -> URL? {
        #if os(macOS)
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.canCreateDirectories = true
        panel.allowsMultipleSelection = false
        panel.prompt = String(localized: "Select")
        panel.message = String(localized: "Choose a folder for exported screenshots")
        guard CrashReportingService.withAppHangTrackingPaused({ panel.runModal() }) == .OK else { return nil }
        return panel.url
        #else
        // iPad: folder selection via UIDocumentPicker is deferred to a follow-up.
        return nil
        #endif
    }

    static func saveBookmark(for url: URL) -> (bookmark: Data, path: String)? {
        do {
            let data = try url.bookmarkData(
                options: bookmarkCreateOptions,
                includingResourceValuesForKeys: nil,
                relativeTo: nil
            )
            return (data, url.path)
        } catch {
            // The user's export folder is silently forgotten and re-prompted for.
            CrashReportingService.report(.exportFolderBookmarkFailed, error: error, extra: ["stage": "create"])
            return nil
        }
    }

    enum BookmarkResolution: Equatable {
        case resolved(URL, refreshedBookmark: Data?)
        /// The folder's volume isn't mounted; the bookmark may resolve again once it is.
        case unavailable
        case invalid
    }

    static func resolveBookmark(_ data: Data, path: String) -> BookmarkResolution {
        guard !data.isEmpty else { return .invalid }
        var isStale = false
        let url: URL
        do {
            url = try URL(
                resolvingBookmarkData: data,
                options: bookmarkResolveOptions,
                relativeTo: nil,
                bookmarkDataIsStale: &isStale
            )
        } catch {
            if !path.isEmpty, isOnUnmountedVolume(path) {
                CrashReportingService.breadcrumb(.export, "Saved export folder's volume is not mounted")
                return .unavailable
            }
            // A sandboxed resolve of a deleted folder can report a bare 259, the same code as
            // garbage bytes, so whether the folder is gone is asked of the bookmark, not the error.
            if isExpectedResolveFailure(error) || bookmarkTargetIsGone(data) {
                CrashReportingService.breadcrumb(.export, "Saved export folder no longer resolves")
            } else {
                CrashReportingService.report(.exportFolderBookmarkFailed, error: error, extra: ["stage": "resolve"])
            }
            return .invalid
        }
        // Bookmarks follow moves, so a folder deleted in Finder resolves into the Trash.
        if isInTrash(url) {
            CrashReportingService.breadcrumb(.export, "Saved export folder is in the Trash")
            return .invalid
        }
        let refreshed: Data? = isStale ? (try? url.bookmarkData(
            options: bookmarkCreateOptions,
            includingResourceValuesForKeys: nil,
            relativeTo: nil
        )) : nil
        return .resolved(url, refreshedBookmark: refreshed)
    }

    /// Deleted, or access revoked — the user's doing, not our bug.
    static func isExpectedResolveFailure(_ error: Error) -> Bool {
        switch error {
        case CocoaError.fileNoSuchFile, CocoaError.fileReadNoSuchFile, CocoaError.fileReadNoPermission:
            return true
        default:
            return ((error as NSError).userInfo[NSUnderlyingErrorKey] as? Error).map(isExpectedResolveFailure) ?? false
        }
    }

    /// The bookmark still parses and names a path that no longer exists. Unparseable bytes are our
    /// bug, and so is a path the sandbox merely won't let us stat — `fileExists` can't tell those apart.
    static func bookmarkTargetIsGone(_ bookmark: Data) -> Bool {
        guard let path = URL.resourceValues(forKeys: [.pathKey], fromBookmarkData: bookmark)?.path else { return false }
        do {
            _ = try FileManager.default.attributesOfItem(atPath: path)
            return false
        } catch CocoaError.fileNoSuchFile, CocoaError.fileReadNoSuchFile {
            return true
        } catch {
            return false
        }
    }

    static func isInTrash(_ url: URL) -> Bool {
        url.standardizedFileURL.pathComponents.contains { $0 == ".Trash" || $0 == ".Trashes" }
    }

    static func isOnUnmountedVolume(_ path: String) -> Bool {
        let components = URL(fileURLWithPath: path).standardizedFileURL.pathComponents
        guard components.count > 2, components[1] == "Volumes" else { return false }
        return !FileManager.default.fileExists(atPath: "/Volumes/\(components[2])")
    }

    static func folderName(for path: String) -> String {
        guard !path.isEmpty else { return String(localized: "selected folder") }
        return URL(fileURLWithPath: path).lastPathComponent
    }
}
