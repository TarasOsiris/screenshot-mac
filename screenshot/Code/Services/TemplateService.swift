#if os(macOS)
import AppKit
#else
import UIKit
#endif
import Foundation

struct ProjectTemplate: Identifiable {
    let id: String
    let name: String
    let url: URL
    let previewImage: NSImage?
    let menuIcon: NSImage?
    var isIncludedInReleaseBuild: Bool = false
}

struct ProjectTemplateMetadata: Codable, Equatable {
    var includeInReleaseBuild: Bool

    init(includeInReleaseBuild: Bool = false) {
        self.includeInReleaseBuild = includeInReleaseBuild
    }
}

enum TemplateService {
    /// Relative path for shared fonts within any Templates.bundle root.
    static let sharedFontsSubpath = "shared/fonts"
    static let metadataFileName = "template.json"
    static let previewFileName = "preview.png"

    /// URL of the shared fonts directory inside the app's Templates.bundle.
    static var sharedFontsURL: URL? {
        Bundle.main.url(forResource: "Templates", withExtension: "bundle")?
            .appendingPathComponent(sharedFontsSubpath, isDirectory: true)
    }

    private static var cachedTemplates: [ProjectTemplate]?

    /// Bundle.main is immutable per launch — scan once, reuse for every caller.
    static func availableTemplates() -> [ProjectTemplate] {
        if let cachedTemplates { return cachedTemplates }
        let templates = loadAvailableTemplates()
        cachedTemplates = templates
        return templates
    }

    /// Off-main variant for first-open UI call sites: the uncached scan does ~35
    /// directory reads + preview file loads. The cache stays main-actor-owned.
    static func availableTemplatesAsync() async -> [ProjectTemplate] {
        if let cachedTemplates { return cachedTemplates }
        let templates = await Task.detached(priority: .userInitiated) {
            loadAvailableTemplates()
        }.value
        cachedTemplates = templates
        return templates
    }

    private static func loadAvailableTemplates() -> [ProjectTemplate] {
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

    static func metadataURL(for templateURL: URL) -> URL {
        templateURL.appendingPathComponent(metadataFileName)
    }

    /// Removes template-only sidecar files (preview image, metadata) from a project directory
    /// after a template has been instantiated as a user project.
    static func stripTemplateArtifacts(in projectDir: URL) {
        let fm = FileManager.default
        try? fm.removeItem(at: projectDir.appendingPathComponent(previewFileName))
        try? fm.removeItem(at: projectDir.appendingPathComponent(metadataFileName))
    }

    static func loadMetadata(at templateURL: URL) -> ProjectTemplateMetadata {
        let metadataURL = metadataURL(for: templateURL)
        guard let data = try? Data(contentsOf: metadataURL),
              let metadata = try? JSONDecoder().decode(ProjectTemplateMetadata.self, from: data) else {
            return ProjectTemplateMetadata()
        }
        return metadata
    }
}
