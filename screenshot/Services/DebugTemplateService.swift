#if DEBUG
import AppKit
import Foundation

enum DebugTemplateService {
    private static let bookmarkKey = "debugTemplatesBundleBookmark"

    /// Source path hint for the NSOpenPanel.
    /// Relies on this file being at screenshot/Services/DebugTemplateService.swift
    /// and Templates.bundle being at screenshot/Templates.bundle.
    static var sourceTemplatesBundleURL: URL {
        let thisFile = URL(fileURLWithPath: #filePath)
        return thisFile
            .deletingLastPathComponent()  // Services/
            .deletingLastPathComponent()  // screenshot/
            .appendingPathComponent("Templates.bundle", isDirectory: true)
    }

    static func resolveBookmark() -> URL? {
        guard let data = UserDefaults.standard.data(forKey: bookmarkKey) else { return nil }
        var isStale = false
        guard let url = try? URL(resolvingBookmarkData: data, options: [.withSecurityScope], relativeTo: nil, bookmarkDataIsStale: &isStale) else { return nil }
        if isStale {
            if let fresh = try? url.bookmarkData(options: [.withSecurityScope], includingResourceValuesForKeys: nil, relativeTo: nil) {
                UserDefaults.standard.set(fresh, forKey: bookmarkKey)
            }
        }
        return url
    }

    @MainActor
    static func pickTemplatesBundleFolder() -> URL? {
        let panel = NSOpenPanel()
        panel.title = "Select Templates.bundle folder"
        panel.message = "Grant access to the Templates.bundle folder in the source tree so templates can be saved there."
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.treatsFilePackagesAsDirectories = true
        panel.directoryURL = sourceTemplatesBundleURL.deletingLastPathComponent()
        panel.prompt = "Select"

        guard panel.runModal() == .OK, let url = panel.url else { return nil }

        if let bookmark = try? url.bookmarkData(options: [.withSecurityScope], includingResourceValuesForKeys: nil, relativeTo: nil) {
            UserDefaults.standard.set(bookmark, forKey: bookmarkKey)
        }
        return url
    }

    @MainActor
    static func getTemplatesBundleURL() -> URL? {
        resolveBookmark() ?? pickTemplatesBundleFolder()
    }

    static func existingTemplateNames(at bundleURL: URL) -> [String] {
        let fm = FileManager.default
        guard let contents = try? fm.contentsOfDirectory(
            at: bundleURL,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        ) else { return [] }
        return contents
            .filter { url in
                (try? url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true
            }
            .map { $0.lastPathComponent }
            .sorted()
    }

    static func saveProjectAsTemplate(projectId: UUID, templateName: String, bundleURL: URL) throws {
        let fm = FileManager.default
        try fm.createDirectory(at: bundleURL, withIntermediateDirectories: true)

        let destURL = bundleURL.appendingPathComponent(templateName, isDirectory: true)
        if fm.fileExists(atPath: destURL.path) {
            try fm.removeItem(at: destURL)
        }

        let sourceURL = PersistenceService.projectDataURL(projectId).deletingLastPathComponent()
        try fm.copyItem(at: sourceURL, to: destURL)

        print("[DebugTemplateService] Saved template '\(templateName)' to \(destURL.path)")
    }
}
#endif
