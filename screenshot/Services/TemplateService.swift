import Foundation

struct ProjectTemplate: Identifiable {
    let id: String
    let name: String
    let url: URL
}

enum TemplateService {
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
        return contents
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
                return ProjectTemplate(id: dirName, name: displayName, url: url)
            }
            .sorted { $0.name < $1.name }
    }
}
