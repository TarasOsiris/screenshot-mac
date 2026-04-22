import AppKit

enum ExportFolderService {
    static func chooseFolder() -> URL? {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.canCreateDirectories = true
        panel.allowsMultipleSelection = false
        panel.prompt = String(localized: "Select")
        panel.message = String(localized: "Choose a folder for exported screenshots")
        guard panel.runModal() == .OK else { return nil }
        return panel.url
    }

    static func saveBookmark(for url: URL) -> (bookmark: Data, path: String)? {
        guard let data = try? url.bookmarkData(
            options: .withSecurityScope,
            includingResourceValuesForKeys: nil,
            relativeTo: nil
        ) else { return nil }
        return (data, url.path)
    }

    static func resolveBookmark(_ data: Data) -> (url: URL, refreshedBookmark: Data?)? {
        guard !data.isEmpty else { return nil }
        var isStale = false
        guard let url = try? URL(
            resolvingBookmarkData: data,
            options: [.withSecurityScope, .withoutUI],
            relativeTo: nil,
            bookmarkDataIsStale: &isStale
        ) else { return nil }
        let refreshed: Data? = isStale ? (try? url.bookmarkData(
            options: .withSecurityScope,
            includingResourceValuesForKeys: nil,
            relativeTo: nil
        )) : nil
        return (url, refreshed)
    }

    static func folderName(for path: String) -> String {
        guard !path.isEmpty else { return String(localized: "selected folder") }
        return URL(fileURLWithPath: path).lastPathComponent
    }
}
