#if os(macOS)
import AppKit
#else
import UIKit
#endif
import Foundation

nonisolated struct ProjectTemplate: Identifiable {
    let id: String
    let name: String
    let url: URL
    let previewImage: NSImage?
    let menuIcon: NSImage?
    var isIncludedInReleaseBuild: Bool = false
}

nonisolated struct ProjectTemplateMetadata: Codable, Equatable {
    var includeInReleaseBuild: Bool

    init(includeInReleaseBuild: Bool = false) {
        self.includeInReleaseBuild = includeInReleaseBuild
    }
}

enum TemplateService {
    /// Relative path for shared fonts within any Templates.bundle root.
    nonisolated static let sharedFontsSubpath = "shared/fonts"
    nonisolated static let metadataFileName = "template.json"
    nonisolated static let previewFileName = "preview.png"

    /// URL of the shared fonts directory inside the app's Templates.bundle.
    nonisolated static var sharedFontsURL: URL? {
        Bundle.main.url(forResource: "Templates", withExtension: "bundle")?
            .appendingPathComponent(sharedFontsSubpath, isDirectory: true)
    }

    private static var cachedTemplates: [ProjectTemplate]?
    private static var templateLoadTask: Task<[ProjectTemplate], Never>?

    /// Bundle.main is immutable per launch — scan once, off-main (the uncached scan
    /// does ~35 directory reads + preview file loads). Concurrent first callers
    /// (editor, onboarding, new-project window) coalesce onto one load task.
    static func availableTemplatesAsync() async -> [ProjectTemplate] {
        if let cachedTemplates { return cachedTemplates }
        let task = templateLoadTask ?? Task.detached(priority: .userInitiated) {
            loadAvailableTemplates()
        }
        templateLoadTask = task
        let templates = await task.value
        cachedTemplates = templates
        return templates
    }

    private nonisolated static func loadAvailableTemplates() -> [ProjectTemplate] {
        guard let bundleURL = Bundle.main.url(forResource: "Templates", withExtension: "bundle") else {
            return []
        }
        let fm = FileManager.default
        guard let contents = try? fm.contentsOfDirectory(
            at: bundleURL,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        ) else {
            return []
        }
        let all = contents
            .filter { url in
                var isDir: ObjCBool = false
                fm.fileExists(atPath: url.path, isDirectory: &isDir)
                return isDir.boolValue && fm.fileExists(atPath: url.appendingPathComponent("project.json").path)
            }
            .map { url in
                let dirName = url.lastPathComponent
                let displayName = dirName
                    .replacing("_", with: " ")
                    .replacing("-", with: " ")
                    .localizedCapitalized
                let previewImage = NSImage(contentsOf: url.appendingPathComponent(previewFileName))
                let menuIcon = previewImage.flatMap { img -> NSImage? in
                    #if os(macOS)
                    return NSImage(size: NSSize(width: 64, height: 32), flipped: false) { rect in
                        img.draw(in: rect)
                        return true
                    }
                    #else
                    return PlatformImageRenderer.image(size: CGSize(width: 64, height: 32)) {
                        img.draw(in: CGRect(x: 0, y: 0, width: 64, height: 32))
                    }
                    #endif
                }
                let metadata = loadMetadata(at: url)
                return ProjectTemplate(
                    id: dirName,
                    name: displayName,
                    url: url,
                    previewImage: previewImage,
                    menuIcon: menuIcon,
                    isIncludedInReleaseBuild: metadata.includeInReleaseBuild
                )
            }
            .sorted { (a: ProjectTemplate, b: ProjectTemplate) in
                if a.isIncludedInReleaseBuild != b.isIncludedInReleaseBuild {
                    return a.isIncludedInReleaseBuild
                }
                return a.name.localizedStandardCompare(b.name) == .orderedAscending
            }
        #if DEBUG
        return all
        #else
        return all.filter(\.isIncludedInReleaseBuild)
        #endif
    }

    nonisolated static func metadataURL(for templateURL: URL) -> URL {
        templateURL.appendingPathComponent(metadataFileName)
    }

    /// Removes template-only sidecar files (preview image, metadata) from a project directory
    /// after a template has been instantiated as a user project.
    nonisolated static func stripTemplateArtifacts(in projectDir: URL) {
        let fm = FileManager.default
        try? fm.removeItem(at: projectDir.appendingPathComponent(previewFileName))
        try? fm.removeItem(at: projectDir.appendingPathComponent(metadataFileName))
    }

    nonisolated static func loadMetadata(at templateURL: URL) -> ProjectTemplateMetadata {
        let metadataURL = metadataURL(for: templateURL)
        guard let data = try? Data(contentsOf: metadataURL),
              let metadata = try? JSONDecoder().decode(ProjectTemplateMetadata.self, from: data) else {
            return ProjectTemplateMetadata()
        }
        return metadata
    }
}
