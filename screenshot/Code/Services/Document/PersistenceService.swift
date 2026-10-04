import Foundation

nonisolated struct PersistenceService {
    static let encoder: JSONEncoder = {
        let e = JSONEncoder()
        e.outputFormatting = [.sortedKeys]
        return e
    }()

    static let decoder = JSONDecoder()

    static func projectDataExists(_ id: UUID) -> Bool {
        FileManager.default.fileExists(atPath: projectDataURL(id).path)
    }

    /// Where iCloud parks a ubiquitous file whose bytes haven't materialized: a hidden sibling
    /// named `.<name>.icloud`. Deleting one deletes the item itself, on every device.
    static func ubiquitousPlaceholderURL(for url: URL) -> URL {
        url.deletingLastPathComponent().appendingPathComponent(".\(url.lastPathComponent).icloud")
    }

    static func isUbiquitousPlaceholder(_ fileName: String) -> Bool {
        fileName.hasPrefix(".") && fileName.hasSuffix(".icloud")
    }

    /// A resource iCloud hasn't brought down yet is not a resource that is gone: the first is a
    /// wait, the second is a hole worth reporting. Nothing may delete or overwrite on the first.
    enum ResourceAvailability {
        case present
        case notDownloaded
        case absent
    }

    /// Blocks on the file provider for a ubiquitous path, so callers must be off the main thread.
    static func availability(of url: URL) -> ResourceAvailability {
        guard FileManager.default.fileExists(atPath: url.path) else {
            return FileManager.default.fileExists(atPath: ubiquitousPlaceholderURL(for: url).path) ? .notDownloaded : .absent
        }
        // Presence is not bytes: iCloud also represents an undownloaded item as a dataless file at
        // its own path, which exists, reports a size, and reads as empty. A non-ubiquitous file
        // answers nil here, which is the ordinary case.
        let status = try? url.resourceValues(forKeys: [.ubiquitousItemDownloadingStatusKey])
            .ubiquitousItemDownloadingStatus
        return status == .notDownloaded ? .notDownloaded : .present
    }

    /// Modification date of the project's translation catalog, used to detect translator edits
    /// made outside the app (e.g. in Xcode's String Catalog editor). Nil when the file is absent.
    static func translationCatalogModifiedDate(_ id: UUID) -> Date? {
        modificationDate(of: translationCatalogURL(id))
    }

    /// Nil when the file is absent. Reads the one attribute rather than `attributesOfItem`, which
    /// boxes a dozen of them per call — this runs on every save and every remote-change check.
    static func modificationDate(of url: URL) -> Date? {
        try? url.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate
    }

    // MARK: - Setup

    static func ensureDirectories() {
        ensureDirectories(at: rootURL)
    }

    static func ensureDirectories(at root: URL) {
        createDirectory(at: root, label: "root")
        createDirectory(at: projectsDir(at: root), label: "projects")
    }

    static func ensureProjectDirs(_ id: UUID) {
        createDirectory(at: projectDirectoryURL(id), label: "project")
        createDirectory(at: resourcesDir(id), label: "resources")
    }

    /// A failure here makes every later write fail for a reason nobody would otherwise record.
    private static func createDirectory(at url: URL, label: String) {
        do {
            try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        } catch {
            CrashReportingService.report(.directoryCreateFailed, error: error, extra: ["directory": label])
        }
    }

    // MARK: - Generic load/save

    static func load<T: Decodable>(_ type: T.Type, from url: URL) -> T? {
        let data = readData(from: url)
        guard let data else { return nil }
        // Callers can't tell a nil here apart from "file missing" and fall back to an empty
        // document, which the next autosave then writes over the real one — hence the report.
        return decodeReportingFailure(type, from: data, file: url)
    }

    static func decodeReportingFailure<T: Decodable>(_ type: T.Type, from data: Data, file url: URL) -> T? {
        do {
            return try decoder.decode(type, from: data)
        } catch {
            CrashReportingService.report(.projectDecodeFailed, error: error, extra: [
                "file": url.lastPathComponent,
                "type": String(describing: type),
                "bytes": data.count,
            ])
            return nil
        }
    }

    static func readData(from url: URL) -> Data? {
        if isUsingICloud {
            return ICloudSyncService.shared.coordinatedRead(from: url)
        }
        do {
            return try Data(contentsOf: url)
        } catch {
            // A missing file is the normal "not created yet" case; anything else is a real fault.
            if FileManager.default.fileExists(atPath: url.path) {
                CrashReportingService.report(.projectReadFailed, error: error, extra: ["file": url.lastPathComponent])
            }
            return nil
        }
    }

    static func save<T: Encodable>(_ value: T, to url: URL) throws {
        let data = try encoder.encode(value)
        try writeData(data, to: url)
    }

    /// Writes pre-encoded data using the same coordination strategy as `save`.
    /// Split out so callers can encode on one thread (e.g. the main actor) and
    /// perform the potentially-blocking coordinated write on another.
    static func writeData(_ data: Data, to url: URL) throws {
        try writeData(data, to: url, coordinated: isUsingICloud)
    }

    /// For a write under an explicit root: coordination follows the root, never the global flag.
    static func writeData(_ data: Data, to url: URL, inRoot root: URL) throws {
        try writeData(data, to: url, coordinated: isICloudRoot(root))
    }

    private static func writeData(_ data: Data, to url: URL, coordinated: Bool) throws {
        if coordinated {
            try ICloudSyncService.shared.coordinatedWrite(data, to: url)
        } else {
            try data.write(to: url, options: .atomic)
        }
    }

    static func removeItemIfExists(at url: URL) throws {
        if isUsingICloud {
            try ICloudSyncService.shared.coordinatedDelete(at: url)
        } else if FileManager.default.fileExists(atPath: url.path) {
            try FileManager.default.removeItem(at: url)
        }
    }

    // MARK: - Project data

    static func loadProject(_ id: UUID) -> ProjectData? {
        guard var data = load(ProjectData.self, from: projectDataURL(id)) else { return nil }
        // Catalog wins on read: merge translator-editable `.xcstrings` text over the inline copy.
        // Absent catalog (old project, first run) leaves the inline `ls.o` text untouched.
        if let localeState = data.localeState {
            data.localeState = TranslationCatalogService.merging(localeState, projectId: id, rows: data.rows)
        }
        return data
    }

    static func saveProject(_ id: UUID, data: ProjectData) throws {
        ensureProjectDirs(id)
        try save(data, to: projectDataURL(id))
        // Dual-write: mirror translations into the `.xcstrings` catalog. Inline text stays in
        // project.json during the transition so older builds / lagging iCloud devices don't lose it.
        // Existing catalogs are rewritten even when the build is empty, so stale translator files
        // cannot keep reintroducing deleted text.
        if let localeState = data.localeState,
           localeState.locales.count > 1 || !localeState.overrides.isEmpty || TranslationCatalogService.exists(projectId: id) {
            let catalogSpan = PerfSignpost.begin(
                "PersistenceService.buildCatalog",
                "locales=\(localeState.locales.count) overrides=\(localeState.overrides.count)"
            )
            let catalog = TranslationCatalog.build(rows: data.rows, localeState: localeState)
            PerfSignpost.end("PersistenceService.buildCatalog", catalogSpan)
            try TranslationCatalogService.write(catalog, projectId: id)
        } else if TranslationCatalogService.exists(projectId: id) {
            try TranslationCatalogService.delete(projectId: id)
        }
    }

    static func deleteProject(_ id: UUID) {
        try? FileManager.default.removeItem(at: projectDirectoryURL(id))
        deleteThumbnail(id)
    }

    static func deleteProject(_ id: UUID, at root: URL) {
        try? FileManager.default.removeItem(at: projectDirectoryURL(id, at: root))
    }

    static func deleteThumbnail(_ id: UUID, at baseURL: URL? = nil) {
        let url = baseURL.map { thumbnailURL(id, at: $0) } ?? thumbnailURL(id)
        let versionURL = baseURL.map { thumbnailVersionURL(id, at: $0) } ?? thumbnailVersionURL(id)
        try? FileManager.default.removeItem(at: url)
        try? FileManager.default.removeItem(at: versionURL)
    }
}
