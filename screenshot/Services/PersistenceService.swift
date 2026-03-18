import Foundation

struct PersistenceService {
    private static let rootDirectoryOverrideKey = "SCREENSHOT_DATA_DIR"

    static var hasDataDirOverride: Bool {
        ProcessInfo.processInfo.environment[rootDirectoryOverrideKey]?.isEmpty == false
    }

    static let encoder: JSONEncoder = {
        let e = JSONEncoder()
        e.outputFormatting = [.prettyPrinted, .sortedKeys]
        return e
    }()

    static let decoder = JSONDecoder()

    static var localRootURL: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("screenshot", isDirectory: true)
    }

    static var isUsingICloud: Bool {
        ICloudSyncService.shared.isUsingICloud
    }

    static var rootURL: URL {
        if let override = ProcessInfo.processInfo.environment[rootDirectoryOverrideKey], !override.isEmpty {
            return URL(fileURLWithPath: override, isDirectory: true)
        }
        return ICloudSyncService.shared.activeRootURL
    }

    private static let indexFileName = "projects.json"
    private static let projectsDirName = "projects"

    private static var projectsDir: URL {
        rootURL.appendingPathComponent(projectsDirName, isDirectory: true)
    }

    static var indexURL: URL {
        rootURL.appendingPathComponent(indexFileName)
    }

    private static func projectDir(_ id: UUID) -> URL {
        projectsDir.appendingPathComponent(id.uuidString, isDirectory: true)
    }

    static func projectDataURL(_ id: UUID) -> URL {
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

    // MARK: - Generic load/save

    static func load<T: Decodable>(_ type: T.Type, from url: URL) -> T? {
        let data: Data?
        if isUsingICloud {
            data = ICloudSyncService.shared.coordinatedRead(from: url)
        } else {
            data = try? Data(contentsOf: url)
        }
        guard let data else { return nil }
        return try? decoder.decode(type, from: data)
    }

    static func save<T: Encodable>(_ value: T, to url: URL) throws {
        let data = try encoder.encode(value)
        if isUsingICloud {
            try ICloudSyncService.shared.coordinatedWrite(data, to: url)
        } else {
            try data.write(to: url, options: .atomic)
        }
    }

    // MARK: - Project index

    static func loadIndex() -> ProjectIndex? {
        load(ProjectIndex.self, from: indexURL)
    }

    static func saveIndex(_ index: ProjectIndex) throws {
        try save(index, to: indexURL)
    }

    // MARK: - Project data

    static func loadProject(_ id: UUID) -> ProjectData? {
        load(ProjectData.self, from: projectDataURL(id))
    }

    static func saveProject(_ id: UUID, data: ProjectData) throws {
        try save(data, to: projectDataURL(id))
    }

    static func copyProject(from sourceId: UUID, to destId: UUID) {
        copyDirectory(from: projectDir(sourceId), to: projectDir(destId))
    }

    static func deleteProject(_ id: UUID) {
        try? FileManager.default.removeItem(at: projectDir(id))
    }

    private static func copyDirectory(from src: URL, to dst: URL) {
        let fm = FileManager.default
        try? fm.removeItem(at: dst)
        try? fm.copyItem(at: src, to: dst)
    }

    // MARK: - Explicit-root helpers (for iCloud migration)
    // These bypass file coordination intentionally — they are only called during
    // the single-threaded enable/disable migration in ICloudSyncService.

    static func indexURL(at root: URL) -> URL {
        root.appendingPathComponent(indexFileName)
    }

    private static func projectsDir(at root: URL) -> URL {
        root.appendingPathComponent(projectsDirName, isDirectory: true)
    }

    private static func projectDir(_ id: UUID, at root: URL) -> URL {
        projectsDir(at: root).appendingPathComponent(id.uuidString, isDirectory: true)
    }

    static func projectDataURL(_ id: UUID, at root: URL) -> URL {
        projectDir(id, at: root).appendingPathComponent("project.json")
    }

    static func loadIndex(at root: URL) -> ProjectIndex? {
        let url = indexURL(at: root)
        guard let data = try? Data(contentsOf: url) else { return nil }
        return try? decoder.decode(ProjectIndex.self, from: data)
    }

    static func saveIndex(_ index: ProjectIndex, at root: URL) throws {
        let url = indexURL(at: root)
        let data = try encoder.encode(index)
        try data.write(to: url, options: .atomic)
    }

    static func loadProject(_ id: UUID, at root: URL) -> ProjectData? {
        let url = projectDataURL(id, at: root)
        guard let data = try? Data(contentsOf: url) else { return nil }
        return try? decoder.decode(ProjectData.self, from: data)
    }

    static func saveProject(_ id: UUID, data: ProjectData, at root: URL) throws {
        let url = projectDataURL(id, at: root)
        let fm = FileManager.default
        try fm.createDirectory(at: projectDir(id, at: root), withIntermediateDirectories: true, attributes: nil)
        try encoder.encode(data).write(to: url, options: .atomic)
    }

    static func ensureDirectories(at root: URL) {
        let fm = FileManager.default
        try? fm.createDirectory(at: root, withIntermediateDirectories: true)
        try? fm.createDirectory(at: projectsDir(at: root), withIntermediateDirectories: true)
    }

    /// Safely replace a project directory at destination with source.
    /// Copies to a temp location first, then swaps, to avoid data loss if the copy fails.
    static func replaceProjectDir(_ id: UUID, from sourceRoot: URL, to destRoot: URL) throws {
        let fm = FileManager.default
        let srcDir = projectDir(id, at: sourceRoot)
        let dstDir = projectDir(id, at: destRoot)
        guard fm.fileExists(atPath: srcDir.path) else { return }

        if !fm.fileExists(atPath: dstDir.path) {
            try fm.copyItem(at: srcDir, to: dstDir)
        } else {
            // Copy to temp first, then swap — if copy fails, destination is preserved
            let tmpDir = dstDir.deletingLastPathComponent()
                .appendingPathComponent(id.uuidString + ".tmp", isDirectory: true)
            try? fm.removeItem(at: tmpDir)
            try fm.copyItem(at: srcDir, to: tmpDir)
            try? fm.removeItem(at: dstDir)
            try fm.moveItem(at: tmpDir, to: dstDir)
        }
    }
}
