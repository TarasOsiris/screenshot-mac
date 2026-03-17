import Foundation

struct PersistenceService {
    private static let rootDirectoryOverrideKey = "SCREENSHOT_DATA_DIR"

    static let encoder: JSONEncoder = {
        let e = JSONEncoder()
        e.outputFormatting = [.prettyPrinted, .sortedKeys]
        return e
    }()

    static let decoder = JSONDecoder()

    /// Local Application Support path (used as fallback and migration source).
    static var localRootURL: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("screenshot", isDirectory: true)
    }

    static var rootURL: URL {
        if let override = ProcessInfo.processInfo.environment[rootDirectoryOverrideKey], !override.isEmpty {
            return URL(fileURLWithPath: override, isDirectory: true)
        }
        if let iCloudURL = ICloudSyncService.shared.iCloudContainerURL {
            return iCloudURL
        }
        return localRootURL
    }

    static var isUsingICloud: Bool {
        let hasOverride = ProcessInfo.processInfo.environment[rootDirectoryOverrideKey].map { !$0.isEmpty } ?? false
        return !hasOverride && ICloudSyncService.shared.isUsingICloud
    }

    private static var projectsDir: URL {
        rootURL.appendingPathComponent("projects", isDirectory: true)
    }

    static var indexURL: URL {
        rootURL.appendingPathComponent("projects.json")
    }

    private static var templatesDir: URL {
        rootURL.appendingPathComponent("templates", isDirectory: true)
    }

    private static var templateIndexURL: URL {
        rootURL.appendingPathComponent("templates.json")
    }

    private static func projectDir(_ id: UUID) -> URL {
        projectsDir.appendingPathComponent(id.uuidString, isDirectory: true)
    }

    static func projectDataURL(_ id: UUID) -> URL {
        projectDir(id).appendingPathComponent("project.json")
    }

    private static func templateDir(_ id: UUID) -> URL {
        templatesDir.appendingPathComponent(id.uuidString, isDirectory: true)
    }

    private static func templateDataURL(_ id: UUID) -> URL {
        templateDir(id).appendingPathComponent("project.json")
    }

    static func resourcesDir(_ id: UUID) -> URL {
        projectDir(id).appendingPathComponent("resources", isDirectory: true)
    }

    // MARK: - Setup

    static func ensureDirectories() {
        let fm = FileManager.default
        try? fm.createDirectory(at: rootURL, withIntermediateDirectories: true)
        try? fm.createDirectory(at: projectsDir, withIntermediateDirectories: true)
        try? fm.createDirectory(at: templatesDir, withIntermediateDirectories: true)
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

    static func saveIndex(_ index: ProjectIndex) throws {
        let data = try encoder.encode(index)
        try data.write(to: indexURL, options: .atomic)
    }

    // MARK: - Template index

    static func loadTemplateIndex() -> ProjectTemplateIndex? {
        guard let data = try? Data(contentsOf: templateIndexURL) else { return nil }
        return try? decoder.decode(ProjectTemplateIndex.self, from: data)
    }

    static func saveTemplateIndex(_ index: ProjectTemplateIndex) throws {
        let data = try encoder.encode(index)
        try data.write(to: templateIndexURL, options: .atomic)
    }

    // MARK: - Project data

    static func loadProject(_ id: UUID) -> ProjectData? {
        let url = projectDataURL(id)
        guard let data = try? Data(contentsOf: url) else { return nil }
        return try? decoder.decode(ProjectData.self, from: data)
    }

    static func saveProject(_ id: UUID, data: ProjectData) throws {
        let jsonData = try encoder.encode(data)
        try jsonData.write(to: projectDataURL(id), options: .atomic)
    }

    static func loadTemplate(_ id: UUID) -> ProjectData? {
        let url = templateDataURL(id)
        guard let data = try? Data(contentsOf: url) else { return nil }
        return try? decoder.decode(ProjectData.self, from: data)
    }

    static func saveTemplate(_ id: UUID, data: ProjectData) throws {
        let jsonData = try encoder.encode(data)
        try jsonData.write(to: templateDataURL(id), options: .atomic)
    }

    static func copyProject(from sourceId: UUID, to destId: UUID) {
        copyDirectory(from: projectDir(sourceId), to: projectDir(destId))
    }

    static func copyProjectToTemplate(from sourceId: UUID, to destId: UUID) {
        copyDirectory(from: projectDir(sourceId), to: templateDir(destId))
    }

    static func copyTemplateToProject(from sourceId: UUID, to destId: UUID) {
        copyDirectory(from: templateDir(sourceId), to: projectDir(destId))
    }

    static func deleteProject(_ id: UUID) {
        try? FileManager.default.removeItem(at: projectDir(id))
    }

    static func deleteTemplate(_ id: UUID) {
        try? FileManager.default.removeItem(at: templateDir(id))
    }

    private static func copyDirectory(from src: URL, to dst: URL) {
        let fm = FileManager.default
        try? fm.removeItem(at: dst)
        try? fm.copyItem(at: src, to: dst)
    }
}
