import AppKit
import Foundation

struct ProjectTemplate: Identifiable {
    let id: String
    let name: String
    let url: URL
    let previewImage: NSImage?
    let menuIcon: NSImage?
}

enum TemplateService {
    /// Relative path for shared fonts within any Templates.bundle root.
    static let sharedFontsSubpath = "shared/fonts"

    /// URL of the shared fonts directory inside the app's Templates.bundle.
    static var sharedFontsURL: URL? {
        Bundle.main.url(forResource: "Templates", withExtension: "bundle")?
            .appendingPathComponent(sharedFontsSubpath, isDirectory: true)
    }

    static func availableTemplates() -> [ProjectTemplate] {
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
                    .replacingOccurrences(of: "_", with: " ")
                    .replacingOccurrences(of: "-", with: " ")
                    .localizedCapitalized
                let previewImage = NSImage(contentsOf: url.appendingPathComponent("preview.png"))
                let menuIcon = previewImage.flatMap { img in
                    NSImage(size: NSSize(width: 64, height: 32), flipped: false) { rect in
                        img.draw(in: rect)
                        return true
                    }
                }
                return ProjectTemplate(id: dirName, name: displayName, url: url, previewImage: previewImage, menuIcon: menuIcon)
            }
            .sorted { (a: ProjectTemplate, b: ProjectTemplate) in a.name.localizedStandardCompare(b.name) == .orderedAscending }
        #if DEBUG
        return all
        #else
        return Array(all.prefix(8))
        #endif
    }
}
