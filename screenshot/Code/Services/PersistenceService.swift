import Foundation

nonisolated struct PersistenceService {
    private static let rootDirectoryOverrideKey = "SCREENSHOT_DATA_DIR"
    private static let useTemporaryRootDirectoryKey = "SCREENSHOT_USE_TEMP_DATA_DIR"
    private static let temporaryRootURL: URL = {
        let root = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
        let directory = root
            .appendingPathComponent("screenshot-clean-install", isDirectory: true)
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }()

    static var hasDataDirOverride: Bool {
        ProcessInfo.processInfo.environment[rootDirectoryOverrideKey]?.isEmpty == false
            || isUsingTemporaryRootDirectory
            || isRunningUnderXCTest
    }

    // Tests override SCREENSHOT_DATA_DIR per-test, but the env var is process-global and
    // debounced saves can fire after a test unsets it — without this guard those saves
    // land in the user's real (iCloud) store, leaking test projects.
    static var isRunningUnderXCTest: Bool {
        let env = ProcessInfo.processInfo.environment
        return env["XCTestConfigurationFilePath"] != nil
            || env["XCTestSessionIdentifier"] != nil
            || NSClassFromString("XCTestCase") != nil
    }

    static let encoder: JSONEncoder = {
        let e = JSONEncoder()
        e.outputFormatting = [.sortedKeys]
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
        if isUsingTemporaryRootDirectory || isRunningUnderXCTest {
            return temporaryRootURL
        }
        return ICloudSyncService.shared.activeRootURL
    }

    /// Like `rootURL`, but always local — never the iCloud container. For derived data
    /// (e.g. thumbnails) that must not sync. Honors the test data-dir overrides.
    static var localBaseURL: URL {
        if let override = ProcessInfo.processInfo.environment[rootDirectoryOverrideKey], !override.isEmpty {
            return URL(fileURLWithPath: override, isDirectory: true)
        }
        if isUsingTemporaryRootDirectory || isRunningUnderXCTest {
            return temporaryRootURL
        }
        return localRootURL
    }

    private static var isUsingTemporaryRootDirectory: Bool {
        guard let value = ProcessInfo.processInfo.environment[useTemporaryRootDirectoryKey] else {
            return false
        }
        return !value.isEmpty && value != "0" && value.lowercased() != "false"
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

    static func projectDirectoryURL(_ id: UUID) -> URL {
        projectDir(id)
    }

    static func projectDataURL(_ id: UUID) -> URL {
        projectDir(id).appendingPathComponent("project.json")
    }

    static func resourcesDir(_ id: UUID) -> URL {
        projectDir(id).appendingPathComponent("resources", isDirectory: true)
    }

    static func projectDataExists(_ id: UUID) -> Bool {
        FileManager.default.fileExists(atPath: projectDataURL(id).path)
    }

    /// Per-project String Catalog holding the screenshot-content translations. Lives inside the
    /// project directory so directory-level copies (duplication, iCloud) carry it along.
    static func translationCatalogURL(_ id: UUID) -> URL {
        projectDir(id).appendingPathComponent("translations.xcstrings")
    }

    /// Modification date of the project's translation catalog, used to detect translator edits
    /// made outside the app (e.g. in Xcode's String Catalog editor). Nil when the file is absent.
    static func translationCatalogModifiedDate(_ id: UUID) -> Date? {
        (try? FileManager.default.attributesOfItem(atPath: translationCatalogURL(id).path))?[.modificationDate] as? Date
    }

    /// Rendered project-card thumbnails. Always local (never the iCloud root) — derived data
    /// that must not sync or be file-coordinated. Keyed per project; freshness is decided by
    /// comparing the PNG's file mod-date against the project's `modifiedAt`.
    static var thumbnailsDir: URL {
        thumbnailsDir(at: localBaseURL)
    }

    static func thumbnailsDir(at baseURL: URL) -> URL {
        baseURL.appendingPathComponent("thumbnails", isDirectory: true)
    }

    static func thumbnailURL(_ id: UUID) -> URL {
        thumbnailURL(id, at: localBaseURL)
    }

    static func thumbnailURL(_ id: UUID, at baseURL: URL) -> URL {
        thumbnailsDir(at: baseURL).appendingPathComponent("\(id.uuidString).png")
    }

    static func thumbnailVersionURL(_ id: UUID) -> URL {
        thumbnailVersionURL(id, at: localBaseURL)
    }

    static func thumbnailVersionURL(_ id: UUID, at baseURL: URL) -> URL {
        thumbnailURL(id, at: baseURL).appendingPathExtension("version")
    }

    // MARK: - Setup

    static func ensureDirectories() {
        createDirectory(at: rootURL, label: "root")
        createDirectory(at: projectsDir, label: "projects")
    }

    static func ensureProjectDirs(_ id: UUID) {
        createDirectory(at: projectDir(id), label: "project")
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
        do {
            return try decoder.decode(type, from: data)
        } catch {
            // Callers can't tell this apart from "file missing" and fall back to an empty
            // document, which the next autosave then writes over the real one.
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
        if isUsingICloud {
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

    // MARK: - Project index

    static func loadIndex() -> ProjectIndex? {
        guard case .loaded(let index) = loadIndex(at: rootURL) else { return nil }
        return index
    }

    /// The index is the one file whose loss makes every project invisible even though each
    /// project's data is still sitting in `projects/<uuid>/` — without this, a missing
    /// `projects.json` presents as "all your projects are gone" and the next save writes an empty
    /// index over the top. Returns nil (callers keep their current list) when there is nothing to
    /// recover; `wasRecovered` tells the caller to persist what it got back.
    static func loadIndexOrRecover() -> (index: ProjectIndex, wasRecovered: Bool)? {
        switch loadIndex(at: rootURL) {
        case .loaded(let index):
            return (index, false)
        case .absent:
            guard let rebuilt = rebuildIndexFromProjectDirs() else { return nil }
            reportRebuild(rebuilt, reason: "absent")
            return (rebuilt, true)
        case .unreadable:
            // Local only. An iCloud index that won't read may simply not have downloaded yet
            // (offline, or the coordinated read failed), and rebuilding would push an index
            // missing every project this device has never opened out to the other devices.
            guard !isUsingICloud, let rebuilt = rebuildIndexFromProjectDirs() else { return nil }
            preserveUnreadableIndex()
            reportRebuild(rebuilt, reason: "unreadable")
            return (rebuilt, true)
        }
    }

    /// Best-effort scan of `projects/` for anything that still decodes. Junk entries are skipped
    /// silently — the point is to salvage what is there, not to audit the folder.
    static func rebuildIndexFromProjectDirs() -> ProjectIndex? {
        let entries = (try? FileManager.default.contentsOfDirectory(
            at: projectsDir,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        )) ?? []

        var recovered: [Project] = []
        for entry in entries {
            guard let id = UUID(uuidString: entry.lastPathComponent),
                  let data = recoverableProjectData(id) else { continue }
            var project = Project(id: id, name: data.name ?? String(localized: "Recovered Project"))
            project.modifiedAt = data.modifiedAt
            recovered.append(project)
        }

        guard !recovered.isEmpty else { return nil }
        recovered.sort { $0.modifiedAt > $1.modifiedAt }
        return ProjectIndex(projects: recovered, activeProjectId: recovered.first?.id)
    }

    /// Quiet counterpart of `loadProject` for the recovery scan: no decode report, and no catalog
    /// merge — the rebuild only needs `name` and `modifiedAt`.
    private static func recoverableProjectData(_ id: UUID) -> ProjectData? {
        guard let data = readData(from: projectDataURL(id)) else { return nil }
        return try? decoder.decode(ProjectData.self, from: data)
    }

    /// Keeps the bytes we couldn't parse so a rebuild never destroys the only copy of the list.
    private static func preserveUnreadableIndex() {
        let backup = indexURL.appendingPathExtension("corrupt")
        try? FileManager.default.removeItem(at: backup)
        try? FileManager.default.moveItem(at: indexURL, to: backup)
    }

    private static func reportRebuild(_ index: ProjectIndex, reason: String) {
        CrashReportingService.breadcrumb(
            .persistence,
            "Rebuilt project index",
            data: ["projects": index.projects.count, "reason": reason],
            level: .warning
        )
        CrashReportingService.report(
            .projectIndexRebuilt,
            extra: ["projects": index.projects.count, "reason": reason],
            level: .warning
        )
    }

    /// `ensureDirectories()` first, mirroring `saveProject`'s `ensureProjectDirs`: the root is
    /// otherwise created only at launch, so a folder removed mid-session (external cleaner,
    /// container reset, restore) made every later index write fail with ENOENT on the parent.
    static func saveIndex(_ index: ProjectIndex) throws {
        ensureDirectories()
        try save(index, to: indexURL)
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

    @discardableResult
    static func copyProject(from sourceId: UUID, to destId: UUID) -> Bool {
        copyDirectory(from: projectDir(sourceId), to: projectDir(destId))
    }

    @discardableResult
    static func copyProjectFromURL(_ sourceURL: URL, to destId: UUID) -> Bool {
        guard copyDirectory(from: sourceURL, to: projectDir(destId)) else { return false }
        TemplateService.stripTemplateArtifacts(in: projectDir(destId))
        copySharedFontsIfNeeded(to: destId)
        // Update modifiedAt so iCloud sync treats this as a fresh project
        if var data = loadProject(destId) {
            data.modifiedAt = Date()
            try? saveProject(destId, data: data)
        }
        return true
    }

    private static func copySharedFontsIfNeeded(to projectId: UUID) {
        guard let sharedFontsURL = TemplateService.sharedFontsURL else { return }
        let fm = FileManager.default
        guard let fonts = try? fm.contentsOfDirectory(at: sharedFontsURL, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles]) else { return }
        let destResources = resourcesDir(projectId)
        try? fm.createDirectory(at: destResources, withIntermediateDirectories: true)
        for fontURL in fonts {
            let destURL = destResources.appendingPathComponent(fontURL.lastPathComponent)
            if !fm.fileExists(atPath: destURL.path) {
                try? fm.copyItem(at: fontURL, to: destURL)
            }
        }
    }

    static func deleteProject(_ id: UUID) {
        try? FileManager.default.removeItem(at: projectDir(id))
        deleteThumbnail(id)
    }

    static func deleteThumbnail(_ id: UUID, at baseURL: URL? = nil) {
        let url = baseURL.map { thumbnailURL(id, at: $0) } ?? thumbnailURL(id)
        let versionURL = baseURL.map { thumbnailVersionURL(id, at: $0) } ?? thumbnailVersionURL(id)
        try? FileManager.default.removeItem(at: url)
        try? FileManager.default.removeItem(at: versionURL)
    }

    static func deleteProject(_ id: UUID, at root: URL) {
        try? FileManager.default.removeItem(at: projectDir(id, at: root))
    }

    private static func copyDirectory(from src: URL, to dst: URL) -> Bool {
        let fm = FileManager.default
        try? fm.removeItem(at: dst)
        do {
            // copyItem does not create intermediates, and a missing projects/ makes it fail with
            // an ENOENT that names the *source* — which reads as a broken template, not a
            // missing destination.
            try fm.createDirectory(at: dst.deletingLastPathComponent(), withIntermediateDirectories: true)
            try fm.copyItem(at: src, to: dst)
            return true
        } catch {
            // Silently yields an empty duplicated / template-instantiated project.
            CrashReportingService.report(.projectDirectoryCopyFailed, error: error)
            return false
        }
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

    /// Distinguishing these two is what stops a migration from merging against an empty set:
    /// an index that is merely unreadable must not look like a first run.
    enum IndexLoadResult {
        case absent
        case loaded(ProjectIndex)
        case unreadable
    }

    /// The migration counterpart of `loadIndex()`. It can't just delegate, because `readData`
    /// picks coordination from the global `isUsingICloud`, which still describes the *old* mode
    /// while a switch is in flight — so the root being read decides instead.
    static func loadIndex(at root: URL) -> IndexLoadResult {
        let url = indexURL(at: root)
        let data: Data?

        if isICloudRoot(root) {
            data = ICloudSyncService.shared.coordinatedRead(from: url)
        } else {
            do {
                data = try Data(contentsOf: url)
            } catch {
                guard indexExists(at: url) else { return .absent }
                CrashReportingService.report(.projectReadFailed, error: error, extra: ["file": url.lastPathComponent])
                return .unreadable
            }
        }

        guard let data else {
            return indexExists(at: url) ? .unreadable : .absent
        }

        do {
            return .loaded(try decoder.decode(ProjectIndex.self, from: data))
        } catch {
            CrashReportingService.report(.projectDecodeFailed, error: error, extra: [
                "file": url.lastPathComponent,
                "type": String(describing: ProjectIndex.self),
                "bytes": data.count,
            ])
            return .unreadable
        }
    }

    private static func isICloudRoot(_ root: URL) -> Bool {
        guard let dataURL = ICloudSyncService.shared.iCloudDataURL else { return false }
        return root.standardizedFileURL == dataURL.standardizedFileURL
    }

    /// A ubiquitous file whose bytes haven't materialized has nothing at its own path — only a
    /// sibling `.name.icloud` placeholder. Reading that as "absent" is exactly what let a merge
    /// run against zero projects, so it counts as present.
    private static func indexExists(at url: URL) -> Bool {
        let fm = FileManager.default
        if fm.fileExists(atPath: url.path) { return true }
        let placeholder = url.deletingLastPathComponent()
            .appendingPathComponent(".\(url.lastPathComponent).icloud")
        return fm.fileExists(atPath: placeholder.path)
    }

    static func saveIndex(_ index: ProjectIndex, at root: URL) throws {
        ensureDirectories(at: root)
        let url = indexURL(at: root)
        let data = try encoder.encode(index)
        try data.write(to: url, options: .atomic)
    }

    static func ensureDirectories(at root: URL) {
        createDirectory(at: root, label: "migrationRoot")
        createDirectory(at: projectsDir(at: root), label: "migrationProjects")
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
