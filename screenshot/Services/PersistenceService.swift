import Foundation

struct PersistenceService {
    private static let rootDirectoryOverrideKey = "SCREENSHOT_DATA_DIR"

    private static let encoder: JSONEncoder = {
        let e = JSONEncoder()
        e.outputFormatting = [.prettyPrinted, .sortedKeys]
        return e
    }()

    private static let decoder = JSONDecoder()

    static var rootURL: URL {
        if let override = ProcessInfo.processInfo.environment[rootDirectoryOverrideKey], !override.isEmpty {
            return URL(fileURLWithPath: override, isDirectory: true)
        }
        return FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("screenshot", isDirectory: true)
    }

    private static var projectsDir: URL {
        rootURL.appendingPathComponent("projects", isDirectory: true)
    }

    private static var indexURL: URL {
        rootURL.appendingPathComponent("projects.json")
    }

    private static func projectDir(_ id: UUID) -> URL {
        projectsDir.appendingPathComponent(id.uuidString, isDirectory: true)
    }

    private static func projectDataURL(_ id: UUID) -> URL {
        projectDir(id).appendingPathComponent("project.json")
    }

    static func resourcesDir(_ id: UUID) -> URL {
        projectDir(id).appendingPathComponent("resources", isDirectory: true)
    }

    // MARK: - Setup

    static func ensureDirectories() {
        let fm = FileManager.default
        try? fm.createDirectory(at: rootURL, withIntermediateDirectories: true)
        try? fm.createDirectory(at: projectsDir, withIntermediateDirectories: true)
    }

    static func ensureProjectDirs(_ id: UUID) {
        let fm = FileManager.default
        try? fm.createDirectory(at: projectDir(id), withIntermediateDirectories: true)
        try? fm.createDirectory(at: resourcesDir(id), withIntermediateDirectories: true)
    }

    // MARK: - Project index

    static func loadIndex() -> ProjectIndex? {
        guard let data = try? Data(contentsOf: indexURL) else { return nil }
        return try? decoder.decode(ProjectIndex.self, from: data)
    }

    static func saveIndex(_ index: ProjectIndex) {
        guard let data = try? encoder.encode(index) else { return }
        try? data.write(to: indexURL, options: .atomic)
    }

    // MARK: - Project data

    static func loadProject(_ id: UUID) -> ProjectData? {
        let url = projectDataURL(id)
        guard let data = try? Data(contentsOf: url) else { return nil }
        return try? decoder.decode(ProjectData.self, from: data)
    }

    static func saveProject(_ id: UUID, data: ProjectData) {
        guard let jsonData = try? encoder.encode(data) else { return }
        try? jsonData.write(to: projectDataURL(id), options: .atomic)
    }

    static func copyProject(from sourceId: UUID, to destId: UUID) {
        let fm = FileManager.default
        let src = projectDir(sourceId)
        let dst = projectDir(destId)
        try? fm.copyItem(at: src, to: dst)
    }

    static func deleteProject(_ id: UUID) {
        try? FileManager.default.removeItem(at: projectDir(id))
    }
}
