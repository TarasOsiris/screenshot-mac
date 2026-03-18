import Foundation

struct PersistenceService {
    private static let rootDirectoryOverrideKey = "SCREENSHOT_DATA_DIR"

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

    private static var projectsDir: URL {
        rootURL.appendingPathComponent("projects", isDirectory: true)
    }

    static var indexURL: URL {
        rootURL.appendingPathComponent("projects.json")
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
}
