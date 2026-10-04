import Foundation

nonisolated extension PersistenceService {
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
    static var isRunningUnderXCTest: Bool { PlatformProcess.isRunningUnderXCTest }

    static var localRootURL: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("screenshot", isDirectory: true)
    }

    static var isUsingICloud: Bool {
        ICloudSyncService.shared.isUsingICloud
    }

    static var rootURL: URL {
        rootURL(isUsingICloud: isUsingICloud)
    }

    /// Takes the flag rather than reading it, so a caller that gates on `isUsingICloud` reads the
    /// root that flag describes — a container resolving between the two lets them disagree.
    static func rootURL(isUsingICloud: Bool) -> URL {
        if !hasDataDirOverride, isUsingICloud, let url = ICloudSyncService.shared.iCloudDataURL {
            return url
        }
        return localBaseURL
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
    private static let projectDataFileName = "project.json"
    private static let projectsDirName = "projects"

    static let resourcesDirName = "resources"

    // MARK: - Live-root paths
    // The root is resolved on every call, never cached: it follows the current storage mode.

    static var indexURL: URL {
        indexURL(at: rootURL)
    }

    static func projectDirectoryURL(_ id: UUID) -> URL {
        projectDirectoryURL(id, at: rootURL)
    }

    static func projectDataURL(_ id: UUID) -> URL {
        projectDataURL(id, at: rootURL)
    }

    static func resourcesDir(_ id: UUID) -> URL {
        projectDirectoryURL(id).appendingPathComponent(resourcesDirName, isDirectory: true)
    }

    /// Per-project String Catalog holding the screenshot-content translations. Lives inside the
    /// project directory so directory-level copies (duplication, iCloud) carry it along.
    static func translationCatalogURL(_ id: UUID) -> URL {
        projectDirectoryURL(id).appendingPathComponent("translations.xcstrings")
    }

    // MARK: - Explicit-root paths

    static func indexURL(at root: URL) -> URL {
        root.appendingPathComponent(indexFileName)
    }

    static func projectsDir(at root: URL) -> URL {
        root.appendingPathComponent(projectsDirName, isDirectory: true)
    }

    static func projectDirectoryURL(_ id: UUID, at root: URL) -> URL {
        projectsDir(at: root).appendingPathComponent(id.uuidString, isDirectory: true)
    }

    static func projectDataURL(_ id: UUID, at root: URL) -> URL {
        projectDirectoryURL(id, at: root).appendingPathComponent(projectDataFileName)
    }

    // MARK: - Thumbnails

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
}
